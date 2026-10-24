import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

Future<bool> completeCachedResources(
  Directory directory,
  dynamic resources, {
  required bool Function() cancelled,
}) async {
  if (resources is! Map || resources.isEmpty || resources.length > 20000) {
    return false;
  }
  for (final entry in resources.entries) {
    if (cancelled()) throw const FormatException('Book preparation cancelled');
    final value = entry.value;
    if (entry.key is! String ||
        value is! Map ||
        value['file'] !=
            sha256.convert(utf8.encode(entry.key as String)).toString() ||
        value['size'] is! int ||
        value['size'] < 0 ||
        value['size'] > 256 * 1024 * 1024) {
      return false;
    }
    final file = File(p.join(directory.path, value['file'] as String));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() != value['size']) {
      return false;
    }
  }
  return true;
}
