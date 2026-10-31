import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all reader control entry points stay in the primary application', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, isNot(contains('--busybooks-reader-popover')));
    final indicator = File(
      'lib/src/book_workspace/presentation/reading_location_control.dart',
    ).readAsStringSync();
    expect(indicator, isNot(matches(r'TextButton|Tooltip|onPressed|Focus\(')));
    for (final file in Directory(
      'lib/src',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      expect(
        file.readAsStringSync(),
        isNot(matches(r'reader\.goTo|showGoTo|ReaderPanelKind|goto-entry')),
        reason: file.path,
      );
    }
    expect(
      File(
        'lib/src/reading/application/reader_controller.dart',
      ).readAsStringSync(),
      contains("send('goto'"),
    );
    for (final path in [
      'lib/src/reading/presentation/reader_popover.dart',
      'linux/runner/reader_popover.cc',
      'windows/runner/reader_popover.cpp',
    ]) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
    for (final root in ['lib', 'linux/runner', 'windows/runner']) {
      for (final file in Directory(
        root,
      ).listSync(recursive: true).whereType<File>()) {
        if (!RegExp(r'\.(dart|cc|cpp|h|txt)$').hasMatch(file.path)) continue;
        final source = file.readAsStringSync();
        expect(
          source,
          isNot(
            matches(
              r'ReaderPopover|showPopover|capturePopover|popoverAction|busybooks-reader-popover',
            ),
          ),
          reason: file.path,
        );
      }
    }
    for (final host in [
      'linux/runner/reader_host.cc',
      'windows/runner/reader_host.cpp',
    ]) {
      expect(
        File(host).readAsStringSync(),
        isNot(matches(r'fl_view_new|fl_engine_new|FlutterViewController')),
        reason: 'Reader controls must share the primary application: $host',
      );
    }
  });

  test(
    'desktop menus have one native presentation path and no Flutter fallback route',
    () {
      final design = File(
        'lib/src/app/busybooks_design.dart',
      ).readAsStringSync();
      expect(design, contains('menuHost.show('));
      expect(design, contains('context.l10n.menuUnavailable'));
      expect(
        design,
        isNot(
          matches(
            r'\bshowMenu\s*<|\bshowMenu\s*\(|MenuAnchor\(|MenuItemButton\(|extends PopupRoute|FallbackMenu|NestedMenuRoute',
          ),
        ),
      );
      final speech = File(
        'lib/src/reading/presentation/speech_menu.dart',
      ).readAsStringSync();
      expect(speech, contains('showBusyBooksMenu<SpeechOption>'));
      expect(speech, contains('speech.availableVoices()'));
      final selection = File(
        'lib/src/reading/presentation/selection_menu.dart',
      ).readAsStringSync();
      expect(selection, contains('showBusyBooksMenu<ReadingSelectionChoice>'));
    },
  );

  test(
    'every application text editor and selectable label opts into desktop menus',
    () {
      for (final file
          in Directory('lib/src')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final source = file.readAsStringSync();
        final occurrences = RegExp(
          r'\b(?:TextField|TextFormField|SelectableText)\(',
        ).allMatches(source).length;
        if (occurrences == 0) continue;
        expect(
          RegExp(
            r'contextMenuBuilder:\s*busyBooksTextContextMenu',
          ).allMatches(source).length,
          occurrences,
          reason: file.path,
        );
      }
    },
  );
}
