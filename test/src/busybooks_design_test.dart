import 'package:busybooks/src/app/app_theme.dart';
import 'package:busybooks/src/app/busybooks_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaru/yaru.dart';

void main() {
  for (final brightness in Brightness.values) {
    test('semantic surfaces preserve Yaru control geometry in $brightness', () {
      const accent = Color(0xff3584e4);
      final actual = buildBusyBooksTheme(
            brightness: brightness,
            accentColor: accent,
          ),
          base = brightness == Brightness.dark
              ? createYaruDarkTheme(primaryColor: accent)
              : createYaruLightTheme(primaryColor: accent);
      expect(
        actual.filledButtonTheme.style?.shape,
        base.filledButtonTheme.style?.shape,
      );
      expect(
        actual.filledButtonTheme.style?.minimumSize,
        base.filledButtonTheme.style?.minimumSize,
      );
      expect(actual.inputDecorationTheme, base.inputDecorationTheme);
      final surfaces = actual.extension<BusyBooksSurfaceColors>()!;
      expect(actual.scaffoldBackgroundColor, surfaces.window);
      expect(actual.colorScheme.primary, accent);
    });
  }
  testWidgets('grouped switch row activates once and exposes focus', (
    tester,
  ) async {
    var value = false, changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBusyBooksTheme(
          brightness: Brightness.light,
          accentColor: const Color(0xff3584e4),
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (c, setState) => BusyBooksSwitchRow(
              title: 'Reading',
              value: value,
              onChanged: (v) => setState(() {
                value = v;
                changes++;
              }),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Reading'));
    await tester.pump();
    expect(value, true);
    expect(changes, 1);
  });
}
