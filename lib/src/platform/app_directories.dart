import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<Directory> busyBooksDataDirectory() async {
  final override = Platform.environment['BUSYBOOKS_PROFILE'];
  final directory = override == null
      ? await getApplicationSupportDirectory()
      : Directory(override);
  if (override != null && !p.isAbsolute(override)) {
    throw ArgumentError('BUSYBOOKS_PROFILE must be absolute');
  }
  await directory.create(recursive: true);
  if (await FileSystemEntity.isLink(directory.path)) {
    throw const FileSystemException('The profile cannot be a symbolic link');
  }
  return directory;
}
