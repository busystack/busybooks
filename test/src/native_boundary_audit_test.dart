import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Flutter owns chrome and platforms have real reader implementations',
    () {
      final native = File('linux/runner/my_application.cc').readAsStringSync();
      expect(native, contains('hdy_application_window_new'));
      expect(native, contains('busybooks_reader_host_new'));
      expect(native, isNot(contains('gtk_header_bar_new')));
      expect(native, isNot(contains('hdy_header_bar_new')));
      expect(
        File('windows/runner/reader_host.cpp').readAsStringSync(),
        contains('CreateCoreWebView2EnvironmentWithOptions'),
      );
      expect(
        File('lib/src/app/desktop_frame.dart').readAsStringSync(),
        contains('WindowsWindowHost'),
      );
    },
  );
  test('feature surfaces use the ported controls', () {
    for (final p in [
      'lib/src/library/presentation',
      'lib/src/reading/presentation',
      'lib/src/workspace/presentation',
    ]) {
      for (final file
          in Directory(p)
              .listSync(recursive: true)
              .whereType<File>()
              .where((x) => x.path.endsWith('.dart'))) {
        final source = file.readAsStringSync();
        for (final forbidden in [
          'DropdownButton<',
          'SwitchListTile(',
          'AlertDialog(',
          'AppBar(',
          'NavigationRail(',
          'ElevatedButton(',
          'FilledButton(',
          'IconButton(',
        ]) {
          expect(
            source.contains(
              RegExp(
                '(?<!BusyBooksHeader)(?<!BusyBooksLinuxHeader)${RegExp.escape(forbidden)}',
              ),
            ),
            false,
            reason: '${file.path}: $forbidden',
          );
        }
      }
    }
  });
  test('book content cannot silently request network resources', () {
    final html = File('assets/reader/index.html').readAsStringSync();
    expect(html, contains("default-src 'none'"));
    expect(html, contains("object-src 'none'"));
    expect(
      File('assets/reader/reader.js').readAsStringSync(),
      contains('safeDocument'),
    );
    expect(
      File('windows/runner/reader_host.cpp').readAsStringSync(),
      contains('COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL'),
    );
  });
}
