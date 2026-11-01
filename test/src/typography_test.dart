import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:busybooks/src/app/app_settings.dart';
import 'package:busybooks/src/core/reading_preferences.dart';
import 'package:busybooks/src/core/typography.dart';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/library/data/record_validation.dart';
import 'package:busybooks/src/library/domain/book.dart';
import 'package:busybooks/src/reading/fonts/reading_font_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _names = [
  'Noto Serif',
  'Français 日本語 العربية',
  'A "quote", slash\\ family',
  'serif',
  '📖 Reading',
];
Map<String, dynamic> _nativeResolution(String family) => {
  'family': family,
  'faces': [
    for (final style in [(400, false), (700, false), (400, true), (700, true)])
      {
        'sources': ['$family Face'],
        'weight': style.$1,
        'italic': style.$2,
      },
  ],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(readingFontChannel, null));
  test(
    'native resolution retains actual weights, italic faces and bounded face lists',
    () async {
      messenger.setMockMethodCallHandler(readingFontChannel, (call) async {
        if (call.method == 'catalogue') {
          return [
            {'id': 'Weights', 'label': 'Weights'},
          ];
        }
        return {
          'family': 'Weights',
          'faces': [
            for (final weight in [100, 200, 300, 400, 500, 600, 700, 800, 900])
              for (final italic in [false, true])
                {
                  'sources': ['Weight$weight${italic ? 'Italic' : ''}'],
                  'weight': weight,
                  'italic': italic,
                },
          ],
        };
      });
      final result = await ReadingFontService().resolve(
        const FontChoice.named('Weights'),
      );
      expect(result.availability, FontAvailability.available);
      expect(result.faces.length, 18);
      expect(result.faces.where((f) => !f.italic).map((f) => f.weight), [
        100,
        200,
        300,
        400,
        500,
        600,
        700,
        800,
        900,
      ]);
      expect(
        LocalFontFace.fromJson({
          'sources': ['ActualBookFace'],
          'weight': 380,
          'italic': false,
        }).weight,
        380,
      );
      for (final weight in [0, 1001, 400.5, '500']) {
        expect(
          () => LocalFontFace.fromJson({
            'sources': ['Face'],
            'weight': weight,
            'italic': false,
          }),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'named choices are bounded Unicode data, distinct from CSS generics',
    () {
      for (final name in _names) {
        final choice = FontChoice.named(name);
        final p = normalizeReadingAppearance({
          'font': choice.toJson(),
          'size': 27,
          'spread': true,
          'publisher': false,
        });
        expect(FontChoice.parse(p['font']), choice);
        validateBookAppearance(p);
        expect(Book({'appearance': jsonDecode(jsonEncode(p))}).appearance, p);
        expect(AppSettings({'reading': p}).reading, p);
        expect(p['size'], 27);
        expect(p['spread'], true);
      }
      expect(FontChoice.parse('serif'), FontChoice.serif);
      expect(FontChoice.parse({'family': 'serif'}), isNot(FontChoice.serif));
      expect(
        FontChoice.parse('Noto Serif'),
        const FontChoice.named('Noto Serif'),
      );
      for (final invalid in [
        '',
        ' ',
        ' leading',
        'trailing ',
        'x' * 257,
        'new\nline',
        'x\u007fy',
        'x\u0085y',
        '\ud800',
        {'family': 'Fine', 'path': '/font.ttf'},
        42,
      ]) {
        expect(FontChoice.parse(invalid), isNull, reason: '$invalid');
        expect(
          () => validateBookAppearance({'font': invalid}),
          throwsFormatException,
        );
        expect(normalizeReadingAppearance({'font': invalid})['font'], 'serif');
      }
    },
  );
  test('capabilities describe behavior independently of document format', () {
    const familyOnly = TypographyCapabilities(fontFamily: true);
    expect(familyOnly.permits(['font', 'color']), true);
    expect(familyOnly.permits(['size']), false);
    expect(TypographyCapabilities.none.permits(['font']), false);
    expect(TypographyCapabilities.fromJson(null).fontFamily, false);
    expect(
      TypographyCapabilities.fromJson(familyOnly.toJson()).fontFamily,
      true,
    );
  });
  test(
    'book, restart, settings and backup retain named identity without font binaries',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'busybooks-font-storage-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final profile = '${directory.path}/profile';
      var store = await ReadingDataStore.open(profile);
      final opened = await store.call('openPath', {
        'path': File('test/fixtures/reflowable.epub').absolute.path,
      });
      // The existing open-book worker returns its direct-file book record.
      final record = ((opened as Map)['books'] as List).single as Map;
      final id = record['id'] as String;
      final appearance = {
        ...defaultReadingAppearance,
        'publisher': false,
        'font': FontChoice.named(_names[2]).toJson(),
      };
      await store.call('updateBook', {
        'id': id,
        'changes': {'appearance': appearance},
      });
      final backup = '${directory.path}/reading.zip';
      await store.call('backup', {
        'path': backup,
        'preferences': AppSettings({'reading': appearance}).data,
      });
      await store.close();
      store = await ReadingDataStore.open(profile);
      try {
        expect((await store.call('book', id) as Map)['appearance'], appearance);
      } finally {
        await store.close();
      }
      final restored = await ReadingDataStore.open('${directory.path}/restore');
      try {
        await restored.call('restore', backup);
        expect(
          (await restored.call('book', id) as Map)['appearance'],
          appearance,
        );
        expect(
          (await restored.call('pendingPreferences') as Map)['reading'],
          appearance,
        );
      } finally {
        await restored.close();
      }
      final settings = JsonFileLocalSettingsStore(
        '${directory.path}/settings.json',
      );
      await settings.save(AppSettings({'reading': appearance}).data);
      expect(
        (await StartupAppSettings.load(settings)).settings.reading,
        appearance,
      );
      expect((await File(backup).length()), lessThan(10000));
    },
  );
  test(
    'catalogue coalesces, groups identities, keeps localized aliases, expires and refreshes',
    () async {
      final gate = Completer<List<dynamic>>();
      int requests = 0;
      var now = DateTime(2026);
      messenger.setMockMethodCallHandler(readingFontChannel, (call) async {
        if (call.method != 'catalogue') return null;
        requests++;
        if (requests == 1) return gate.future;
        return [
          {'id': 'New', 'label': 'Neu'},
        ];
      });
      final service = ReadingFontService(now: () => now);
      final a = service.catalogue(), b = service.catalogue();
      await Future<void>.delayed(Duration.zero);
      expect(requests, 1);
      gate.complete([
        {'id': 'Family', 'label': 'Familie'},
        {'id': 'Family', 'label': 'Alias'},
        {'id': 'Other', 'label': 'Familie'},
      ]);
      expect((await a).families.length, 2);
      expect(identical(await a, await b), true);
      expect((await service.catalogue()).families.first.label, 'Familie');
      expect(requests, 1);
      now = now.add(const Duration(minutes: 2));
      expect((await service.catalogue()).families.single.id, 'New');
      expect(requests, 2);
    },
  );
  test(
    'stale catalogue results cannot replace a newer refresh; failures can retry',
    () async {
      final old = Completer<List<dynamic>>();
      var calls = 0;
      messenger.setMockMethodCallHandler(readingFontChannel, (call) async {
        calls++;
        if (calls == 1) return old.future;
        if (calls == 2) throw PlatformException(code: 'local-fonts');
        return [
          {'id': 'Fresh', 'label': 'Fresh'},
        ];
      });
      final service = ReadingFontService();
      final pending = service.catalogue();
      await expectLater(
        service.catalogue(refresh: true),
        throwsA(isA<PlatformException>()),
      );
      await service.catalogue(refresh: true);
      old.complete([
        {'id': 'Obsolete', 'label': 'Obsolete'},
      ]);
      await pending;
      expect((await service.catalogue()).families.single.id, 'Fresh');
    },
  );
  test(
    'unavailable and discovery-failed are distinct and never rewrite the saved family',
    () async {
      var failed = false;
      messenger.setMockMethodCallHandler(readingFontChannel, (call) async {
        if (call.method == 'catalogue') {
          if (failed) throw PlatformException(code: 'local-fonts');
          return <dynamic>[];
        }
        return _nativeResolution('Fallback Serif');
      });
      final service = ReadingFontService();
      const choice = FontChoice.named('Temporarily Missing');
      final missing = await service.resolve(choice);
      expect(missing.choice, choice);
      expect(missing.availability, FontAvailability.unavailable);
      expect(missing.family, 'Fallback Serif');
      failed = true;
      await expectLater(
        service.catalogue(refresh: true),
        throwsA(isA<PlatformException>()),
      );
      final unavailable = await ReadingFontService().resolve(choice);
      expect(unavailable.availability, FontAvailability.discoveryFailed);
      expect(unavailable.choice, choice);
    },
  );
}
