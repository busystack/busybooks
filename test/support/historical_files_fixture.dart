import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// Disposable sentinels only. Observe opens/reads as well as writes on Linux;
// matching bytes alone would not establish that the application ignored them.
class HistoricalFilesFixture {
  HistoricalFilesFixture._(this.files, this.before);
  final Map<File, List<int>> files;
  final Map<File, FileStat> before;
  int? _descriptor;
  static final _libc = Platform.isLinux ? DynamicLibrary.process() : null;

  static Future<HistoricalFilesFixture> create(
    String profile, {
    required bool present,
  }) async {
    final files = <File, List<int>>{};
    if (present) {
      files[File(p.join(profile, 'library.sqlite'))] =
          'Unrelated historical database: do not open'.codeUnits;
      files[File(p.join(profile, 'books', 'historical.epub'))] =
          'Unrelated historical book copy: do not open'.codeUnits;
    }
    final before = <File, FileStat>{};
    for (final entry in files.entries) {
      await entry.key.parent.create(recursive: true);
      await entry.key.writeAsBytes(entry.value, flush: true);
      await entry.key.setLastModified(DateTime.utc(2000));
      await entry.key.setLastAccessed(DateTime.utc(2000));
      before[entry.key] = await entry.key.stat();
    }
    final fixture = HistoricalFilesFixture._(files, before);
    if (_libc != null && files.isNotEmpty) {
      final initialize = _libc!
          .lookupFunction<Int32 Function(Int32), int Function(int)>(
            'inotify_init1',
          );
      final addWatch = _libc!
          .lookupFunction<
            Int32 Function(Int32, Pointer<Utf8>, Uint32),
            int Function(int, Pointer<Utf8>, int)
          >('inotify_add_watch');
      final fd = initialize(0x800 | 0x80000); // Nonblocking, close-on-exec.
      if (fd < 0) throw StateError('Could not observe disposable files');
      fixture._descriptor = fd;
      try {
        for (final file in files.keys) {
          final path = file.path.toNativeUtf8();
          try {
            // Access, modify, attributes, close-after-write, open, delete, move.
            if (addWatch(
                  fd,
                  path,
                  0x1 | 0x2 | 0x4 | 0x8 | 0x20 | 0x400 | 0x800,
                ) <
                0) {
              throw StateError('Could not observe disposable file');
            }
          } finally {
            calloc.free(path);
          }
        }
      } catch (_) {
        fixture.close();
        rethrow;
      }
    }
    return fixture;
  }

  void expectUnaccessed() {
    final fd = _descriptor;
    if (fd == null) return;
    final read = _libc!
        .lookupFunction<
          IntPtr Function(Int32, Pointer<Uint8>, UintPtr),
          int Function(int, Pointer<Uint8>, int)
        >('read');
    final errno = _libc!
        .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
          '__errno_location',
        );
    final buffer = calloc<Uint8>(4096);
    try {
      final count = read(fd, buffer, 4096);
      final code = errno().value;
      expectSync(count, -1, reason: 'Historical files must not be accessed');
      expectSync(code, 11, reason: 'An empty nonblocking watch returns EAGAIN');
    } finally {
      calloc.free(buffer);
    }
  }

  Future<void> verifyUnchanged() async {
    expectUnaccessed();
    close(); // Our own verification reads happen after application observation.
    for (final entry in files.entries) {
      final now = await entry.key.stat(), old = before[entry.key]!;
      expectSync(
        [now.type, now.size, now.mode, now.modified, now.changed, now.accessed],
        [old.type, old.size, old.mode, old.modified, old.changed, old.accessed],
      );
      expectSync(await entry.key.readAsBytes(), entry.value);
    }
  }

  void close() {
    final fd = _descriptor;
    if (fd == null) return;
    _descriptor = null;
    _libc!.lookupFunction<Int32 Function(Int32), int Function(int)>('close')(
      fd,
    );
  }
}
