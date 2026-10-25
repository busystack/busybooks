import 'dart:typed_data';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// File-instance identity, in addition to SHA-256, prevents recovery from
// deleting a different file subsequently placed at the saved source pathname.
String fileInstance(String path) => _instance(path, directory: false);

String directoryInstance(String path) => _instance(path, directory: true);

String _instance(String path, {required bool directory}) {
  if (Platform.isLinux) {
    final libc = DynamicLibrary.open('libc.so.6');
    final statx = libc
        .lookupFunction<
          Int32 Function(Int32, Pointer<Utf8>, Int32, Uint32, Pointer<Uint8>),
          int Function(int, Pointer<Utf8>, int, int, Pointer<Uint8>)
        >('statx');
    final name = path.toNativeUtf8(), buffer = calloc<Uint8>(256);
    try {
      if (statx(-100, name, 0x100, 0x7ff, buffer) != 0) {
        throw FileSystemException('Cannot identify book file', path);
      }
      final data = buffer.asTypedList(256).buffer.asByteData();
      if (data.getUint16(28, Endian.host) & 0xf000 !=
          (directory ? 0x4000 : 0x8000)) {
        throw FileSystemException(
          directory
              ? 'Path access requires a physical directory'
              : 'Book access requires a regular physical file',
          path,
        );
      }
      return '${data.getUint32(136, Endian.host)}:${data.getUint32(140, Endian.host)}:${data.getUint64(32, Endian.host)}';
    } finally {
      calloc.free(buffer);
      malloc.free(name);
    }
  }
  if (Platform.isWindows) {
    final handle = _WindowsIdentityHandle(path, directory: directory);
    try {
      // A legacy 64-bit identifier is not conclusive on ReFS. Keep the full
      // FILE_ID_INFO: 64-bit volume serial followed by all 128 file-ID bits.
      return windowsFileInstance(handle.info(18, 24));
    } finally {
      handle.close();
    }
  }
  throw UnsupportedError('Unsupported file identity platform');
}

void syncDirectory(String directory) {
  if (!Platform.isLinux) return;
  final libc = DynamicLibrary.open('libc.so.6');
  final open = libc
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32),
        int Function(Pointer<Utf8>, int)
      >('open');
  final fsync = libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
    'fsync',
  );
  final close = libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
    'close',
  );
  final name = directory.toNativeUtf8();
  final fd = open(name, 0x10000);
  try {
    if (fd < 0 || fsync(fd) != 0) {
      throw FileSystemException(
        'Cannot make file operation durable',
        directory,
      );
    }
  } finally {
    if (fd >= 0) close(fd);
    malloc.free(name);
  }
}

// Encode the entire FILE_ID_INFO without integer truncation or signedness loss.
String windowsFileInstance(Uint8List info) {
  if (info.length != 24) throw const FormatException('Invalid FILE_ID_INFO');
  return 'win128:${info.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';
}

bool directoryCaseSensitive(String path) {
  if (!Platform.isWindows) return true;
  final handle = _WindowsIdentityHandle(path, directory: true);
  try {
    // FileCaseSensitiveInfo (23), FILE_CS_FLAG_CASE_SENSITIVE_DIR (1).
    // Filesystems without this per-directory feature use Windows name matching.
    final info = handle.info(23, 4, unsupported: const [1, 50, 87]);
    return info.isNotEmpty &&
        ByteData.sublistView(info).getUint32(0, Endian.host) & 1 != 0;
  } finally {
    handle.close();
  }
}

bool windowsNamesEqual(String first, String second) {
  if (!Platform.isWindows) return first == second;
  final compare = _WindowsIdentityHandle.kernel
      .lookupFunction<
        Int32 Function(Pointer<Utf16>, Int32, Pointer<Utf16>, Int32, Int32),
        int Function(Pointer<Utf16>, int, Pointer<Utf16>, int, int)
      >('CompareStringOrdinal');
  final a = first.toNativeUtf16(), b = second.toNativeUtf16();
  try {
    final result = compare(a, first.length, b, second.length, 1);
    if (result == 0) {
      throw const FileSystemException('Cannot compare Windows names');
    }
    return result == 2;
  } finally {
    malloc.free(a);
    malloc.free(b);
  }
}

class _WindowsIdentityHandle {
  _WindowsIdentityHandle(String path, {required bool directory}) : path = path {
    final name = path.toNativeUtf16();
    try {
      handle = _open(
        name,
        0x80,
        7,
        nullptr,
        3,
        0x00200000 | (directory ? 0x02000000 : 0),
        nullptr,
      );
    } finally {
      malloc.free(name);
    }
    if (handle.address == Pointer<Void>.fromAddress(-1).address) {
      throw FileSystemException(
        'Cannot identify filesystem object',
        path,
        OSError('CreateFileW', _error()),
      );
    }
    try {
      final attributes = ByteData.sublistView(
        info(9, 8),
      ).getUint32(0, Endian.host);
      if (attributes & 0x400 != 0 || (attributes & 0x10 != 0) != directory) {
        throw FileSystemException(
          'Path requires a physical ${directory ? 'directory' : 'regular file'}',
          path,
        );
      }
    } catch (_) {
      close();
      rethrow;
    }
  }

  final String path;
  late final Pointer<Void> handle;
  static final kernel = DynamicLibrary.open('kernel32.dll');
  static final _open = kernel
      .lookupFunction<
        Pointer<Void> Function(
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Pointer<Void>,
          Uint32,
          Uint32,
          Pointer<Void>,
        ),
        Pointer<Void> Function(
          Pointer<Utf16>,
          int,
          int,
          Pointer<Void>,
          int,
          int,
          Pointer<Void>,
        )
      >('CreateFileW');
  static final _query = kernel
      .lookupFunction<
        Int32 Function(Pointer<Void>, Int32, Pointer<Uint8>, Uint32),
        int Function(Pointer<Void>, int, Pointer<Uint8>, int)
      >('GetFileInformationByHandleEx');
  static final _close = kernel
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('CloseHandle');
  static final _error = kernel
      .lookupFunction<Uint32 Function(), int Function()>('GetLastError');

  Uint8List info(int kind, int length, {List<int> unsupported = const []}) {
    final buffer = calloc<Uint8>(length);
    try {
      if (_query(handle, kind, buffer, length) == 0) {
        final error = _error();
        if (unsupported.contains(error)) return Uint8List(0);
        throw FileSystemException(
          'Cannot query filesystem identity',
          path,
          OSError('GetFileInformationByHandleEx($kind)', error),
        );
      }
      return Uint8List.fromList(buffer.asTypedList(length));
    } finally {
      calloc.free(buffer);
    }
  }

  void close() => _close(handle);
}
