import 'dart:typed_data';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// File-instance identity, in addition to SHA-256, prevents recovery from
// deleting a different file subsequently placed at the saved source pathname.
String fileInstance(String path) {
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
      if (data.getUint16(28, Endian.host) & 0xf000 != 0x8000) {
        throw FileSystemException(
          'Book access requires a regular physical file',
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
    final kernel = DynamicLibrary.open('kernel32.dll');
    final open = kernel
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
    final info = kernel
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Uint8>),
          int Function(Pointer<Void>, Pointer<Uint8>)
        >('GetFileInformationByHandle');
    final close = kernel
        .lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('CloseHandle');
    final name = path.toNativeUtf16(), buffer = calloc<Uint8>(52);
    final handle = open(name, 0x80, 7, nullptr, 3, 0x00200000, nullptr);
    try {
      if (handle.address == Pointer<Void>.fromAddress(-1).address ||
          info(handle, buffer) == 0) {
        throw FileSystemException('Cannot identify book file', path);
      }
      final data = buffer.asTypedList(52).buffer.asByteData();
      if (data.getUint32(0, Endian.host) & 0x410 != 0) {
        throw FileSystemException(
          'Book access requires a regular physical file',
          path,
        );
      }
      return '${data.getUint32(28, Endian.host)}:${data.getUint32(44, Endian.host)}:${data.getUint32(48, Endian.host)}';
    } finally {
      if (handle.address != Pointer<Void>.fromAddress(-1).address) {
        close(handle);
      }
      calloc.free(buffer);
      malloc.free(name);
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
