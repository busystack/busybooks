import 'dart:async';
import 'dart:convert';

import 'package:busybooks/src/app/busybooks_design.dart';
import 'package:busybooks/src/core/reading_preferences.dart';
import 'package:busybooks/src/reading/presentation/reader_popover.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _update(
  WidgetTester tester,
  Map<String, dynamic> data, {
  bool settle = true,
}) async {
  final reply = Completer<void>();
  ServicesBinding.instance.channelBuffers.push(
    readerPopoverChannel.name,
    readerPopoverChannel.codec.encodeMethodCall(
      MethodCall('update', {
        'session': '1',
        'presentation': 1,
        'dark': false,
        'accent': 0xff3584e4,
        'locale': 'en',
        ...data,
      }),
    ),
    (_) => reply.complete(),
  );
  await tester.pump();
  await reply.future;
  if (settle) await tester.pumpAndSettle();
}

Future<void> _lookupResult(
  WidgetTester tester,
  Map<String, dynamic> result,
) async {
  ServicesBinding.instance.channelBuffers.push(
    readerPopoverChannel.name,
    readerPopoverChannel.codec.encodeMethodCall(
      MethodCall('result', {
        'session': '1',
        'presentation': 1,
        'lookupTerm': 'ice cream',
        ...result,
      }),
    ),
    (_) {},
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final actions = <Map>[];
  final presented = <Map>[];
  String? replyError;
  setUp(() {
    actions.clear();
    presented.clear();
    replyError = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(readerPopoverChannel, (call) async {
          if (call.method == 'presented') presented.add(call.arguments as Map);
          if (call.method == 'action') {
            final action = jsonDecode(call.arguments as String) as Map;
            actions.add(action);
            scheduleMicrotask(
              () => ServicesBinding.instance.channelBuffers.push(
                readerPopoverChannel.name,
                readerPopoverChannel.codec.encodeMethodCall(
                  MethodCall('result', {
                    'request': action['request'],
                    'ok': true,
                    if (replyError != null) 'error': replyError,
                  }),
                ),
                (_) {},
              ),
            );
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(readerPopoverChannel, null),
  );
  testWidgets(
    'compact appearance ignores stale hide and disposes the owned presentation',
    (tester) async {
      await tester.pumpWidget(const ProviderScope(child: ReaderPopoverApp()));
      await _update(tester, {
        'kind': 'appearance',
        'typography': {'fontFamily': true, 'textMetrics': true},
        'pdf': false,
        'appearance': defaultReadingAppearance,
      });
      expect(find.text('Font size'), findsOneWidget);
      expect(find.text('Font family'), findsNothing);
      Future<void> hidden(int presentation) async {
        ServicesBinding.instance.channelBuffers.push(
          readerPopoverChannel.name,
          readerPopoverChannel.codec.encodeMethodCall(
            MethodCall('hidden', {
              'session': '1',
              'presentation': presentation,
            }),
          ),
          (_) {},
        );
        await tester.pumpAndSettle();
      }

      await hidden(0);
      expect(find.text('Font size'), findsOneWidget);
      await hidden(1);
      expect(find.text('Font size'), findsNothing);
      expect(actions, isEmpty);
      // Font-family editing and Escape/focus remain covered by font_chooser_test
      // in the full Settings controls where advanced typography now belongs.
    },
  );
  testWidgets('selection exposes Search in This Book and deliberate Look Up', (
    tester,
  ) async {
    await tester.pumpWidget(const ReaderPopoverApp());
    await _update(tester, {'kind': 'selection', 'color': 'yellow'});
    expect(actions, isEmpty);
    await tester.tap(find.text('Search in This Book'));
    await tester.pumpAndSettle();
    expect(actions.single['action'], 'searchSelection');
    await tester.tap(find.text('Look Up'));
    await tester.pumpAndSettle();
    expect(actions.last['action'], 'dictionary');
  });
  testWidgets(
    'lookup native text, states, source, full entry and Escape work at narrow sizes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ReaderPopoverApp());
      await _update(tester, {
        'kind': 'lookup',
        'lookupTerm': 'ice cream',
        'lookup': {'status': 'loading'},
      }, settle: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('ice cream'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('English Wiktionary · Online'), findsOneWidget);
      expect(
        Focus.of(tester.element(find.text('Close'))).hasPrimaryFocus,
        isTrue,
      );
      await _lookupResult(tester, {
        'lookup': {
          'status': 'ready',
          'entry': 'https://en.wiktionary.org/wiki/ice%20cream',
          'sections': [
            {
              'language': 'English',
              'partOfSpeech': 'Noun',
              'definitions': ['A frozen dessert.'],
            },
            {
              'language': 'French',
              'partOfSpeech': 'Noun',
              'definitions': ['A different language.'],
            },
          ],
        },
      });
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.widgetWithText(SelectableText, '1. A frozen dessert.'),
        findsOneWidget,
      );
      expect(find.text('French · Noun'), findsOneWidget);
      expect(
        Focus.of(tester.element(find.text('Close'))).hasPrimaryFocus,
        isTrue,
      );
      await tester.ensureVisible(find.text('Open Full Entry'));
      await tester.tap(find.text('Open Full Entry'));
      await tester.pump();
      expect(actions.last['action'], 'lookupFullEntry');
      for (final status in [
        'missing',
        'offline',
        'timeout',
        'invalid',
        'unsupported',
        'unavailable',
      ]) {
        await _lookupResult(tester, {
          'lookup': {'status': status},
        });
        final retries = [
          'offline',
          'timeout',
          'invalid',
          'unavailable',
        ].contains(status);
        expect(find.text('Retry'), retries ? findsOneWidget : findsNothing);
        if (retries) {
          await tester.ensureVisible(find.text('Retry'));
          await tester.tap(find.text('Retry'));
          await tester.pump();
          expect(actions.last['action'], 'lookupRetry');
        }
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(actions.last['action'], 'dismiss');
      expect(tester.takeException(), isNull);
    },
  );
  for (final status in [
    'ready',
    'offline',
    'timeout',
    'unavailable',
    'invalid',
  ]) {
    for (final (keyName, key) in [
      ('Enter', LogicalKeyboardKey.enter),
      ('Space', LogicalKeyboardKey.space),
    ]) {
      testWidgets(
        'lookup keeps Close focused after delayed $status and $keyName dismisses',
        (tester) async {
          await tester.pumpWidget(const ReaderPopoverApp());
          await _update(tester, {
            'kind': 'lookup',
            'lookupTerm': 'ice cream',
            'lookup': {'status': 'loading'},
          }, settle: false);
          await tester.pump(const Duration(seconds: 1));
          expect(
            Focus.of(tester.element(find.text('Close'))).hasPrimaryFocus,
            isTrue,
          );
          await _lookupResult(tester, {
            'lookup': {
              'status': status,
              if (status == 'ready' || status == 'invalid')
                'entry': 'https://en.wiktionary.org/wiki/ice%20cream',
              if (status == 'ready')
                'sections': [
                  {
                    'language': 'English',
                    'partOfSpeech': 'Noun',
                    'definitions': ['A frozen dessert.'],
                  },
                ],
            },
          });
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(
            find.widgetWithText(FilledButton, 'Retry'),
            status == 'ready' ? findsNothing : findsOneWidget,
          );
          expect(
            find.widgetWithText(FilledButton, 'Open Full Entry'),
            status == 'ready' || status == 'invalid'
                ? findsOneWidget
                : findsNothing,
          );
          final closeHasFocus = Focus.of(
            tester.element(find.text('Close')),
          ).hasPrimaryFocus;
          expect(actions, isEmpty);
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
          expect(actions.map((action) => action['action']), ['dismiss']);
          expect(closeHasFocus, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'lookup grows from the native loading allocation to a readable definition',
    (tester) async {
      tester.view.physicalSize = const Size(460, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ReaderPopoverApp());
      await _update(tester, {
        'kind': 'lookup',
        'lookupTerm': 'ice cream',
        'lookup': {'status': 'loading'},
      }, settle: false);
      await tester.pump(const Duration(milliseconds: 100));
      final loadingHeight = presented.last['height'] as double;
      // Apply the allocation the native host requested for the loading frame.
      tester.view.physicalSize = Size(460, loadingHeight.ceilToDouble());
      await tester.pump();
      const definition =
          'A concise definition with enough detail to occupy several lines in this native lookup surface, while keeping the publication visible.';
      await _lookupResult(tester, {
        'lookup': {
          'status': 'ready',
          'entry': 'https://en.wiktionary.org/wiki/ice%20cream',
          'sections': [
            {
              'language': 'English',
              'partOfSpeech': 'Noun',
              'definitions': [definition],
            },
          ],
        },
      });
      final definitionHeight = presented.last['height'] as double;
      expect(definitionHeight, greaterThan(loadingHeight));
      tester.view.physicalSize = Size(
        460,
        definitionHeight.clamp(1, 480).ceilToDouble(),
      );
      await tester.pumpAndSettle();
      final text = find.widgetWithText(SelectableText, '1. $definition');
      final bounds = tester.getRect(text);
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'lookup status cannot replace a new presentation or reset focused input',
    (tester) async {
      await tester.pumpWidget(const ReaderPopoverApp());
      await _update(tester, {
        'kind': 'selection',
        'editing': true,
        'color': 'yellow',
        'presentation': 2,
      });
      await tester.enterText(find.byType(TextField), 'Protected note');
      final focus = FocusManager.instance.primaryFocus;
      await _lookupResult(tester, {
        'lookup': {'status': 'ready', 'sections': []},
      });
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Protected note',
      );
      expect(FocusManager.instance.primaryFocus, same(focus));
      expect(find.text('Open Full Entry'), findsNothing);
    },
  );
  testWidgets(
    'Go To printed labels are explicit and ambiguous labels do not navigate',
    (tester) async {
      tester.view.physicalSize = const Size(360, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ReaderPopoverApp());
      await _update(tester, {
        'kind': 'goto',
        'pdf': true,
        'pages': 3,
        'labels': ['i', '255', '255'],
        'toc': [],
        'location': {},
      });
      await tester.enterText(find.byType(TextField), '=255');
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(actions.where((a) => a['action'] == 'goto'), isEmpty);
      await _update(tester, {
        'presentation': 2,
        'kind': 'goto',
        'pdf': true,
        'pages': 3,
        'labels': ['i', '255', '256'],
        'toc': [],
        'location': {},
      });
      await tester.enterText(find.byType(TextField), '=255');
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(actions.singleWhere((a) => a['action'] == 'goto')['anchor'], {
        'page': 1,
      });
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Go To EPUB progress stays meaningful at enlarged text scale without fabricated page counts',
    (tester) async {
      tester.view.physicalSize = const Size(360, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ReaderPopoverApp());
      await _update(tester, {
        'kind': 'goto',
        'pdf': false,
        'pages': 0,
        'labels': [],
        'toc': [],
        'location': {},
        'textScale': 2.0,
      });
      await tester.enterText(find.byType(TextField), '101');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(actions.where((a) => a['action'] == 'goto'), isEmpty);
      await tester.enterText(find.byType(TextField), '75');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(actions.singleWhere((a) => a['action'] == 'goto')['anchor'], {
        'fraction': .75,
      });
      expect(presented.last['height'] as num, greaterThan(200));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Go To acknowledges a painted populated form and validates physical pages',
    (tester) async {
      tester.view.physicalSize = const Size(360, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ReaderPopoverApp());
      expect(presented, isEmpty);
      await _update(tester, {
        'kind': 'goto',
        'pdf': true,
        'pages': 322,
        'labels': List.generate(322, (i) => '${i - 25}'),
        'toc': [],
        'location': {
          'anchor': {'page': 280},
        },
      });
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Go'), findsOneWidget);
      expect(presented, isNotEmpty);
      expect(presented.last['session'], '1');
      expect(presented.last['presentation'], 1);
      expect(presented.last['height'] as num, lessThan(420));
      await tester.enterText(find.byType(TextField), '0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(actions.where((a) => a['action'] == 'goto'), isEmpty);
      await tester.enterText(find.byType(TextField), '281');
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(actions.singleWhere((a) => a['action'] == 'goto')['anchor'], {
        'page': 280,
      });
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'selection offers labeled contextual actions and saves a note inline with native selection identity',
    (tester) async {
      tester.view.physicalSize = const Size(460, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ProviderScope(child: ReaderPopoverApp()));
      await _update(tester, {'kind': 'selection', 'color': 'yellow'});
      expect(find.text('Highlight'), findsOneWidget);
      expect(find.text('Add Note'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('Add Note'));
      await tester.pumpAndSettle();
      expect(find.byType(BusyBooksGroupedTextEntry), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'A note about this passage',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(actions.first['action'], 'noteDraft');
      expect(actions.first['note'], 'A note about this passage');
      final saved = actions.singleWhere((a) => a['action'] == 'highlight');
      expect(saved['note'], 'A note about this passage');
      expect(saved['session'], '1');
      expect(saved['presentation'], 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(actions.last['action'], 'dismiss');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'an annotation write failure keeps the passage note editable and displays feedback',
    (tester) async {
      tester.view.physicalSize = const Size(460, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ProviderScope(child: ReaderPopoverApp()));
      await _update(tester, {
        'kind': 'selection',
        'color': 'yellow',
        'editing': true,
      });
      await tester.enterText(
        find.byType(TextField),
        'Preserve my unsaved note',
      );
      replyError = 'Fixture write failure';
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Fixture write failure'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Preserve my unsaved note',
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final (name, reflow, pdf, noText) in [
    ('reflowable EPUB', true, false, false),
    ('fixed EPUB', false, false, false),
    ('text PDF', false, true, false),
    ('scanned PDF', false, true, true),
  ]) {
    testWidgets(
      'Appearance actual form and reuse expose applicable controls for $name',
      (tester) async {
        tester.view.physicalSize = const Size(460, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(const ProviderScope(child: ReaderPopoverApp()));
        for (final presentation in [1, 2]) {
          await _update(tester, {
            'kind': 'appearance',
            'presentation': presentation,
            'typography': {'fontFamily': reflow, 'textMetrics': reflow},
            'pdf': pdf,
            'location': {'noText': noText},
            'appearance': reflow
                ? defaultReadingAppearance
                : defaultPdfAppearance,
          });
          expect(
            find.text('Font size'),
            reflow ? findsOneWidget : findsNothing,
          );
          if (!reflow) {
            await tester.scrollUntilVisible(find.text('Zoom'), 150);
            expect(find.text('Zoom'), findsOneWidget);
          }
          if (pdf) {
            await tester.scrollUntilVisible(find.text('Rotation'), 100);
            expect(find.text('Rotation'), findsOneWidget);
          } else {
            expect(find.text('Rotation'), findsNothing);
          }
          expect(
            presented.where((e) => e['presentation'] == presentation),
            isNotEmpty,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
  testWidgets(
    'compact appearance exposes common controls and routes advanced typography to Settings',
    (tester) async {
      tester.view.physicalSize = const Size(460, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ProviderScope(child: ReaderPopoverApp()));
      await _update(tester, {
        'kind': 'appearance',
        'typography': {'fontFamily': true, 'textMetrics': true},
        'pdf': false,
        'appearance': defaultReadingAppearance,
      });
      expect(find.text('Font size'), findsOneWidget);
      expect(find.text('Font weight'), findsNothing);
      expect(find.text('More Typography'), findsNothing);
      await tester.scrollUntilVisible(find.text('More Reading Settings…'), 200);
      await tester.tap(find.text('More Reading Settings…'));
      await tester.pumpAndSettle();
      expect(actions.single['action'], 'readingSettings');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Go To rejects invalid PDF pages and explicitly distinguishes printed labels',
    (tester) async {
      tester.view.physicalSize = const Size(460, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ProviderScope(child: ReaderPopoverApp()));
      await _update(tester, {
        'kind': 'goto',
        'pdf': true,
        'pages': 4,
        'labels': ['i', 'ii', '17', '18'],
        'toc': [],
      });
      await tester.enterText(find.byType(TextField), '99');
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(actions, isEmpty);
      expect(
        find.text(
          'Enter a physical page in range or an exact printed label. Use = for a numeric label.',
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), '3');
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(actions.single['anchor'], {'page': 2});
      expect(tester.takeException(), isNull);
    },
  );
}
