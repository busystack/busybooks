import 'dart:convert';
import 'dart:io';
import 'package:busybooks/src/library/data/record_validation.dart';

// Validate every real native locator through the same contract as persistence
// and backup restore. Renderer-only navigation cannot establish this boundary.
void main(List<String> args) {
  if (args.length != 2) {
    throw ArgumentError('usage: validate_native_locations.dart FORMAT LOG');
  }
  var count = 0;
  void inspect(dynamic value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (['anchor', 'annotationAnchor', 'noteAnchor'].contains(entry.key) &&
            entry.value is Map) {
          validateAnchor(entry.value, args[0]);
          count++;
        } else {
          inspect(entry.value);
        }
      }
    } else if (value is List) {
      for (final item in value) {
        inspect(item);
      }
    }
  }

  for (final line in File(args[1]).readAsLinesSync()) {
    if (line.startsWith('{')) inspect(jsonDecode(line));
  }
  if (count == 0) throw StateError('No native locators were checked');
  stdout.writeln(
    jsonEncode({
      'status': 'passed',
      'nativeLocators': count,
      'format': args[0],
    }),
  );
}
