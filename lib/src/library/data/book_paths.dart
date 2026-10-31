import 'dart:io';
import 'package:path/path.dart' as p;
import 'file_identity.dart';

bool isWindowsAbsoluteReference(String value) =>
    RegExp(r'^(?:[a-zA-Z]:[\\/]|\\\\)').hasMatch(value) &&
    p.windows.isAbsolute(value);
bool isAbsoluteReference(String value) =>
    p.posix.isAbsolute(value) || isWindowsAbsoluteReference(value);
bool isNativeAbsoluteReference(String value) => Platform.isWindows
    ? isWindowsAbsoluteReference(value)
    : p.posix.isAbsolute(value);

/// A filesystem location, including a name that does not exist yet.
///
/// Resolve the nearest existing ancestor before appending missing components.
/// This preserves Windows long names, junctions and directory links without
/// treating a missing destination as an unrelated lexical path. Directory
/// identity distinguishes different objects and Linux names remain case-sensitive.
class BookPathIdentity {
  BookPathIdentity._(
    this.path,
    this.ancestorInstance,
    this.components,
    this.caseSensitive,
  );

  final String path;
  final String ancestorInstance;
  final List<String> components;
  final bool caseSensitive;

  factory BookPathIdentity.resolve(String input) {
    if (isAbsoluteReference(input) && !isNativeAbsoluteReference(input)) {
      throw FileSystemException(
        'Path belongs to another operating system',
        input,
      );
    }
    // POSIX resolves a link before a following '..'; Windows resolves dot
    // segments first. Do not apply Windows lexical rules to Linux paths.
    var cursor = Platform.isWindows
        ? p.normalize(p.absolute(input))
        : p.absolute(input);
    final missing = <String>[];
    while (true) {
      try {
        final resolved = p.normalize(File(cursor).resolveSymbolicLinksSync());
        final String ancestor;
        final List<String> components;
        if (missing.isEmpty) {
          ancestor = p.dirname(resolved);
          components = [p.basename(resolved)];
        } else {
          ancestor = resolved;
          components = missing.reversed.toList();
        }
        return BookPathIdentity._(
          p.joinAll([resolved, ...missing.reversed]),
          directoryInstance(ancestor),
          components,
          directoryCaseSensitive(ancestor),
        );
      } on FileSystemException catch (error) {
        // Never reinterpret a dangling link, denied access or a non-directory
        // component as an ordinary missing destination.
        if (![2, 3].contains(error.osError?.errorCode) ||
            FileSystemEntity.typeSync(cursor, followLinks: false) !=
                FileSystemEntityType.notFound) {
          rethrow;
        }
        final parent = p.dirname(cursor);
        if (parent == cursor) rethrow;
        final name = p.basename(cursor);
        if (name == '.' ||
            name == '..' ||
            Platform.isWindows &&
                (name.endsWith('.') ||
                    name.endsWith(' ') ||
                    name.contains(':'))) {
          throw FileSystemException(
            'Ambiguous missing destination component',
            input,
          );
        }
        missing.add(name);
        cursor = parent;
      }
    }
  }

  bool sameLocation(BookPathIdentity other) {
    if (ancestorInstance != other.ancestorInstance ||
        components.length != other.components.length) {
      return false;
    }
    for (var i = 0; i < components.length; i++) {
      if (caseSensitive || other.caseSensitive) {
        if (components[i] != other.components[i]) return false;
      } else if (!windowsNamesEqual(components[i], other.components[i])) {
        return false;
      }
    }
    return true;
  }
}
