import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

const comicDiskReserveBytes = 64 * 1024 * 1024;

int availableDiskBytes(String directory) {
  if (Platform.isLinux && sizeOf<IntPtr>() == 8) {
    final statvfs = DynamicLibrary.open('libc.so.6')
        .lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Uint8>),
          int Function(Pointer<Utf8>, Pointer<Uint8>)
        >('statvfs');
    final name = directory.toNativeUtf8(), buffer = calloc<Uint8>(128);
    try {
      if (statvfs(name, buffer) != 0) {
        throw FileSystemException('Cannot check cache disk space', directory);
      }
      final data = buffer.asTypedList(128).buffer.asByteData();
      return data.getUint64(8, Endian.host) * data.getUint64(32, Endian.host);
    } finally {
      malloc.free(name);
      calloc.free(buffer);
    }
  }
  if (Platform.isWindows) {
    final query = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<
          Int32 Function(
            Pointer<Utf16>,
            Pointer<Uint64>,
            Pointer<Uint64>,
            Pointer<Uint64>,
          ),
          int Function(
            Pointer<Utf16>,
            Pointer<Uint64>,
            Pointer<Uint64>,
            Pointer<Uint64>,
          )
        >('GetDiskFreeSpaceExW');
    final name = directory.toNativeUtf16(), available = calloc<Uint64>();
    try {
      if (query(name, available, nullptr, nullptr) == 0) {
        throw FileSystemException('Cannot check cache disk space', directory);
      }
      return available.value;
    } finally {
      malloc.free(name);
      calloc.free(available);
    }
  }
  throw UnsupportedError('Unsupported cache filesystem platform');
}

void requireComicDiskSpace(String directory, int bytes, {int? available}) {
  if (bytes < 0 ||
      (available ?? availableDiskBytes(directory)) <
          bytes + comicDiskReserveBytes) {
    throw FileSystemException(
      'Insufficient free disk space for comic pages and cache reserve',
      directory,
    );
  }
}
