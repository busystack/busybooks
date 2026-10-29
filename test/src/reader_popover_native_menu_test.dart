import 'dart:async';
import 'dart:convert';

import 'package:busybooks/src/platform/native_menu_service.dart';
import 'package:busybooks/src/reading/presentation/reader_popover.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _deliver(
  WidgetTester tester,
  String method,
  Map<String, Object?> data,
) async {
  final completion = Completer<void>();
  ServicesBinding.instance.channelBuffers.push(
    readerPopoverChannel.name,
    readerPopoverChannel.codec.encodeMethodCall(MethodCall(method, data)),
    (_) => completion.complete(),
  );
  await tester.pump();
  await completion.future;
  await tester.pumpAndSettle();
}

Map<String, Object?> _speech({int presentation = 1}) => {
  'session': 'speech-session',
  'presentation': presentation,
  'kind': 'speech',
  'dark': false,
  'locale': 'en',
  'voices': ['', 'Voice A'],
  'voice': '',
  'speed': 1.1,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const menus = MethodChannel(nativeMenuChannelName);
  final actions = <Map>[];
  final menuCalls = <MethodCall>[];
  Future<int?> Function(MethodCall)? selection;
  setUp(() {
    actions.clear();
    menuCalls.clear();
    selection = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(menus, (call) async {
      menuCalls.add(call);
      if (call.method == 'dismiss') return true;
      return selection?.call(call);
    });
    messenger.setMockMethodCallHandler(readerPopoverChannel, (call) async {
      if (call.method == 'action') {
        final action = jsonDecode(call.arguments as String) as Map;
        actions.add(action);
        scheduleMicrotask(
          () => ServicesBinding.instance.channelBuffers.push(
            readerPopoverChannel.name,
            readerPopoverChannel.codec.encodeMethodCall(
              MethodCall('result', {'request': action['request'], 'ok': true}),
            ),
            (_) {},
          ),
        );
      }
      return null;
    });
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(menus, null);
    messenger.setMockMethodCallHandler(readerPopoverChannel, null);
  });

  for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
    testWidgets(
      'speech Voice and nonpreset Speed use their $platform view native bridge',
      (tester) async {
        await tester.pumpWidget(const ReaderPopoverApp());
        await _deliver(tester, 'update', _speech());
        selection = (_) async => 1;
        await tester.tap(find.text('System'));
        await tester.pumpAndSettle();
        expect(actions.single['action'], 'voice');
        expect(actions.single['voice'], 'Voice A');
        final voice =
            menuCalls.singleWhere((call) => call.method == 'show').arguments
                as Map;
        final anchor = voice['anchor'] as Map;
        expect(anchor['width'], greaterThan(0));
        expect(anchor['height'], greaterThan(0));
        expect(anchor['x'], greaterThanOrEqualTo(0));
        expect(anchor['y'], greaterThanOrEqualTo(0));
        final entries = voice['entries'] as List;
        expect((entries.first as Map)['selected'], isTrue);
        expect((entries[1] as Map)['label'], 'Voice A');
        actions.clear();
        selection = (_) async => 0;
        await tester.tap(find.text('1.1×'));
        await tester.pumpAndSettle();
        expect(actions.single['action'], 'speed');
        expect(actions.single['speed'], .5);
        final speed =
            menuCalls.where((call) => call.method == 'show').last.arguments
                as Map;
        expect(
          (speed['entries'] as List)
              .where((entry) => (entry as Map)['selected'] == true)
              .single,
          containsPair('label', '1.1×'),
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({platform}),
    );
  }

  for (final replace in [false, true]) {
    testWidgets(
      'late native speech menu result is rejected after ${replace ? 'replacement' : 'hide'}',
      (tester) async {
        final reply = Completer<int?>();
        selection = (_) => reply.future;
        await tester.pumpWidget(const ReaderPopoverApp());
        await _deliver(tester, 'update', _speech());
        await tester.tap(find.text('System'));
        await tester.pump();
        final show =
            menuCalls.singleWhere((call) => call.method == 'show').arguments
                as Map;
        await _deliver(
          tester,
          replace ? 'update' : 'hidden',
          replace
              ? _speech(presentation: 2)
              : {'session': 'speech-session', 'presentation': 1},
        );
        expect(
          menuCalls
              .where((call) => call.method == 'dismiss')
              .map((call) => (call.arguments as Map)['sessionId']),
          contains(show['sessionId']),
        );
        reply.complete(1);
        await tester.pumpAndSettle();
        expect(actions, isEmpty);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({TargetPlatform.linux}),
    );
  }
}
