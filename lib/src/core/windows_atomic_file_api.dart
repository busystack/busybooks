import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'atomic_file_writer.dart';

typedef _MoveNative = Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32);
typedef _MoveDart = int Function(Pointer<Utf16>, Pointer<Utf16>, int);
typedef _ReplaceNative =
    Int32 Function(
      Pointer<Utf16>,
      Pointer<Utf16>,
      Pointer<Utf16>,
      Uint32,
      Pointer<Void>,
      Pointer<Void>,
    );
typedef _ReplaceDart =
    int Function(
      Pointer<Utf16>,
      Pointer<Utf16>,
      Pointer<Utf16>,
      int,
      Pointer<Void>,
      Pointer<Void>,
    );

final class WindowsAtomicFileApi {
  WindowsAtomicFileApi._() : _kernel = DynamicLibrary.open('kernel32.dll');
  static final instance = WindowsAtomicFileApi._();
  final DynamicLibrary _kernel;
  late final _move = _kernel.lookupFunction<_MoveNative, _MoveDart>(
    'MoveFileExW',
  );
  late final _replace = _kernel.lookupFunction<_ReplaceNative, _ReplaceDart>(
    'ReplaceFileW',
  );
  late final _error = _kernel.lookupFunction<Uint32 Function(), int Function()>(
    'GetLastError',
  );
  Future<void> publish(
    String staged,
    String target, {
    required bool overwrite,
    void Function()? beforePublish,
    Future<bool> Function(String)? acceptReplaced,
  }) async {
    final source = staged.toNativeUtf16(),
        dest = target.toNativeUtf16(),
        backup = '$staged.previous'.toNativeUtf16();
    try {
      if (overwrite) {
        final type = await FileSystemEntity.type(target, followLinks: false);
        if (type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.file) {
          throw FileSystemException(
            'The export destination is not a regular file',
            target,
          );
        }
      }
      if (overwrite && acceptReplaced != null && await File(target).exists()) {
        beforePublish?.call();
        if (_replace(dest, source, backup, 0, nullptr, nullptr) == 0) {
          throw FileSystemException(
            'Atomic replacement failed',
            target,
            OSError('ReplaceFileW', _error()),
          );
        }
        bool accepted = false;
        Object? cause;
        try {
          accepted = await acceptReplaced('$staged.previous');
        } catch (e) {
          cause = e;
        }
        if (!accepted) {
          throw AtomicFileChangedException(
            target,
            recoveryPath: '$staged.previous',
            cause: cause,
          );
        }
        await File('$staged.previous').delete();
        return;
      }
      // MOVEFILE_WRITE_THROUGH; omission of REPLACE_EXISTING is a kernel-enforced
      // no-replace operation, including the final collision window.
      final flags = 8 | (overwrite && acceptReplaced == null ? 1 : 0);
      beforePublish?.call();
      if (_move(source, dest, flags) == 0) {
        final code = _error();
        if (code == 80 || code == 183) {
          if (acceptReplaced != null) throw AtomicFileChangedException(target);
          throw AtomicFileAlreadyExistsException(target);
        }
        throw FileSystemException(
          'Atomic publication failed',
          target,
          OSError('MoveFileExW', code),
        );
      }
    } finally {
      malloc.free(source);
      malloc.free(dest);
      malloc.free(backup);
    }
  }
}
