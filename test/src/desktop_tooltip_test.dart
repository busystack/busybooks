import 'dart:ui' show PointerDeviceKind;

import 'package:busybooks/src/app/app_theme.dart';
import 'package:busybooks/src/app/busybooks_design.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _until(WidgetTester tester, bool Function() done) async {
  final watch = Stopwatch()..start();
  while (!done()) {
    if (watch.elapsed > const Duration(seconds: 5)) {
      fail('Native tooltip frame was not delivered');
    }
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '$platform $brightness delivers the rendered BusyMark tooltip specification to its host',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          final calls = <MethodCall>[];
          const channel = MethodChannel('io.busystack.busybooks/reader');
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
          final semantics = tester.ensureSemantics();
          final pointer = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          try {
            for (final scale in [1.0, 1.6]) {
              await tester.pumpWidget(
                MaterialApp(
                  theme: buildBusyBooksTheme(
                    brightness: brightness,
                    accentColor: const Color(0xff3584e4),
                  ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: Align(
                      alignment: Alignment.topLeft,
                      child: BusyBooksHeaderIconButton(
                        key: ValueKey(scale),
                        tooltip: 'Main Menu',
                        icon: Icons.menu,
                        onPressed: () {},
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final button = find.byType(IconButton);
              expect(tester.getSemantics(button).label, 'Main Menu');
              calls.clear();
              await pointer.addPointer(location: const Offset(500, 500));
              await pointer.moveTo(tester.getCenter(button));
              await tester.pump(const Duration(milliseconds: 449));
              expect(calls.where((c) => c.method == 'headerHint'), isEmpty);
              await tester.pump(const Duration(milliseconds: 1));
              await _until(
                tester,
                () => calls.any((c) => c.method == 'headerHint'),
              );
              final packet =
                  calls.firstWhere((c) => c.method == 'headerHint').arguments
                      as Map;
              final style = packet['style'] as Map;
              // These values are BusyMarkTooltipStyle/app_theme.dart's approved
              // specification, not a screenshot blessed from the current host.
              expect(style['background'], 0xcc000000);
              expect(style['foreground'], 0xffffffff);
              expect(style['border'], 0x1affffff);
              expect(style['borderWidth'], 1.0);
              expect(style['radius'], 8.0);
              expect(style['padding'], {
                'left': 10.0,
                'right': 10.0,
                'top': 6.0,
                'bottom': 6.0,
              });
              expect(style['fontSize'], 14.0);
              expect(style['textScale'], closeTo(scale, .001));
              expect(style['minHeight'], 30.0);
              expect(style['waitMilliseconds'], 450);
              expect(style['exitMilliseconds'], 100);
              final pixels = packet['pixels'] as Uint8List;
              final width = packet['width'] as int,
                  height = packet['height'] as int;
              expect(pixels.length, width * height * 4);
              expect(
                pixels[3],
                0,
                reason: 'The rounded window corner is transparent.',
              );
              final background = ((height - 4) * width + width ~/ 2) * 4;
              expect(pixels.sublist(background, background + 4), [
                0,
                0,
                0,
                204,
              ]);
              expect(
                calls.any(
                  (c) => ['capture', 'bounds', 'visible'].contains(c.method),
                ),
                isFalse,
              );
              expect(
                find.text('Main Menu'),
                findsNothing,
                reason: 'No simultaneous Flutter tooltip.',
              );
              await pointer.moveTo(const Offset(500, 500));
              await tester.pump(const Duration(milliseconds: 99));
              expect(calls.where((c) => c.method == 'hideHeaderHint'), isEmpty);
              await tester.pump(const Duration(milliseconds: 1));
              await tester.pumpAndSettle();
              expect(
                calls.lastWhere((c) => c.method == 'hideHeaderHint').arguments,
                packet['id'],
              );
              await pointer.removePointer();
            }
          } finally {
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
            semantics.dispose();
            messenger.setMockMethodCallHandler(channel, null);
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
    }
  }
}
