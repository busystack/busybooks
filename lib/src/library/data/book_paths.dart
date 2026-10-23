import 'dart:io';
import 'package:path/path.dart' as p;

bool isWindowsAbsoluteReference(String value) =>
    RegExp(r'^(?:[a-zA-Z]:[\\/]|\\\\)').hasMatch(value) &&
    p.windows.isAbsolute(value);
bool isAbsoluteReference(String value) =>
    p.posix.isAbsolute(value) || isWindowsAbsoluteReference(value);
bool isNativeAbsoluteReference(String value) => Platform.isWindows
    ? isWindowsAbsoluteReference(value)
    : p.posix.isAbsolute(value);
