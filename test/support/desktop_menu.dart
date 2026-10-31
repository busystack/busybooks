import 'package:busybooks/src/platform/native_menu_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Select a real production menu command through its desktop channel contract.
Future<void> chooseDesktopMenu(
  WidgetTester tester,
  Finder trigger,
  String label,
) async {
  final previous = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  const channel = MethodChannel(nativeMenuChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method != 'show') return null;
    final entries = <Map>[];
    void visit(List rows) {
      for (final row in rows.cast<Map>()) {
        entries.add(row);
        if (row['children'] is List) visit(row['children'] as List);
      }
    }

    visit((call.arguments as Map)['entries'] as List);
    final index = entries.indexWhere((row) => row['label'] == label);
    expect(
      index,
      greaterThanOrEqualTo(0),
      reason: 'Missing native command: $label',
    );
    return index;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  try {
    await tester.tap(trigger);
    await tester.pumpAndSettle();
  } finally {
    debugDefaultTargetPlatformOverride = previous;
  }
}
