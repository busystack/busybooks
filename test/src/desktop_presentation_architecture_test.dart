import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:busybooks/src/app/app_metadata.dart';

void main() {
  test(
    'About reports the package version without a second metadata dependency',
    () {
      final version = RegExp(
        r'^version:\s*([^+\s]+)',
        multiLine: true,
      ).firstMatch(File('pubspec.yaml').readAsStringSync())![1];
      expect(busyBooksAppVersion, version);
    },
  );
  test('visible primitive constructions have precise reviewed BusyMark owners', () {
    final manifest =
        jsonDecode(
              File(
                'docs/development/desktop-control-contracts.json',
              ).readAsStringSync(),
            )
            as Map;
    final reviewed = <String, int>{};
    for (final contract in manifest['contracts'] as List) {
      expect(
        contract['reference'],
        anyOf(contains('BusyMark'), contains('busymark')),
      );
      expect((contract['construction'] as String).length, greaterThan(60));
      reviewed['${contract['source']}::${contract['owner']}::${contract['constructor']}'] =
          contract['count'] as int;
    }
    final actual = <String, int>{};
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final source = _withoutCommentsAndStrings(file.readAsStringSync());
      final owners = <({String name, int start, int end})>[];
      for (final declaration in RegExp(
        r'\bclass\s+(\w+)[^{;]*\{',
      ).allMatches(source)) {
        var depth = 1, end = declaration.end;
        while (depth > 0 && end < source.length) {
          if (source[end] == '{') depth++;
          if (source[end] == '}') depth--;
          end++;
        }
        owners.add((name: declaration[1]!, start: declaration.end, end: end));
      }
      for (final control in _visiblePrimitive.allMatches(source)) {
        final owner =
            owners
                .where((o) => o.start <= control.start && control.end <= o.end)
                .firstOrNull
                ?.name ??
            '<top-level>';
        final key = '${file.path}::$owner::${control[1]}';
        actual.update(key, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    expect(
      actual,
      reviewed,
      reason:
          'New primitives require a specific reference construction and rendered review; no file-wide exemption.',
    );
    final notebook = File(
      'lib/src/notebook/presentation/notebook_item.dart',
    ).readAsStringSync();
    expect(notebook, contains('hoverColor: busyBooksRowHoverColor(context)'));
    final selector = File(
      'lib/src/app/busybooks_design.dart',
    ).readAsStringSync();
    expect(
      selector,
      contains('foregroundColor: neutralButtonStyle?.foregroundColor'),
    );
  });

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

final _visiblePrimitive = RegExp(
  r'\b(TextButton|FilledButton|ElevatedButton|OutlinedButton|IconButton|TextField|TextFormField|Tooltip|InkWell|InkResponse|Switch|Checkbox|Radio|Slider|DropdownButton|PopupMenuButton|MenuAnchor|MenuItemButton|AlertDialog|SimpleDialog|Dialog|YaruListTile|YaruSwitch|YaruCheckbox|YaruIconButton|Material|Card|SelectableText|CircularProgressIndicator|LinearProgressIndicator|YaruCircularProgressIndicator|YaruLinearProgressIndicator|YaruWindowControl|YaruMasterTile|YaruSwitchListTile|YaruInfoBox|YaruDialogTitleBar|SwitchListTile|CheckboxListTile|RadioListTile|SegmentedButton|ToggleButtons|ChoiceChip|FilterChip|ActionChip|InputChip|Chip|TabBar|NavigationRail|NavigationBar|DropdownMenu|MenuBar)\s*(?:<[^;\n]*?>)?\s*(?:\.(?:icon|tonal|tonalIcon|adaptive|square))?\s*\(',
);

String _withoutCommentsAndStrings(String source) {
  final literals = RegExp(
    r'''//[^\n]*|/\*[\s\S]*?\*/|r?\x27\x27\x27[\s\S]*?\x27\x27\x27|r?"""[\s\S]*?"""|r?\x27(?:\\.|[^\x27\\])*\x27|r?"(?:\\.|[^"\\])*"''',
  );
  return source.replaceAllMapped(
    literals,
    (match) => match[0]!.replaceAll(RegExp(r'[^\n]'), ' '),
  );
}
