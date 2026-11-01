// Adapted from BusyMark shared foundation behavior.
import 'package:busybooks/src/platform/native_menu_service.dart';
import 'package:busybooks/src/app/busybooks_design.dart';
import 'package:busybooks/src/app/busybooks_toast.dart';
import 'package:busybooks/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'recoverable native failure reports feedback without a Flutter menu',
    (tester) async {
      const channel = MethodChannel('busybooks/test/fallback');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(code: 'presentation-failed'),
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BusyBooksToastOverlay(
            child: Scaffold(
              body: BusyBooksHeaderPopupMenuButton<String>(
                tooltip: 'Menu',
                icon: Icons.menu,
                nativeMenuService: const NativeMenuService(
                  channel: channel,
                  supportedPlatform: true,
                ),
                itemBuilder: (_) => [
                  BusyBooksPopupMenuItem(
                    value: 'disabled',
                    label: 'Loading',
                    enabled: false,
                  ),
                  BusyBooksPopupMenuItem(value: 'open', label: 'Open Book'),
                ],
                onSelected: (value) => selected = value,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      expect(find.text('Loading'), findsNothing);
      expect(find.text('Open Book'), findsNothing);
      expect(find.byType(MenuAnchor), findsNothing);
      expect(find.byType(PopupMenuItem<String>), findsNothing);
      expect(
        find.text('The menu could not be opened. Please try again.'),
        findsOneWidget,
      );
      expect(selected, isNull);
    },
  );

  test(
    'show serializes native menu presentation and returns its selection',
    () async {
      const channel = MethodChannel('busybooks/test/native-menu');
      MethodCall? call;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (value) async {
            call = value;
            return 2;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final session = NativeMenuSession();
      final result =
          await const NativeMenuService(
            channel: channel,
            supportedPlatform: true,
          ).show(
            session: session,
            anchor: const Rect.fromLTWH(12, 34, 56, 78),
            entries: const [
              NativeMenuEntry.command(
                label: 'Open',
                iconName: 'document-open-symbolic',
                iconColorArgb: 0xff3584e4,
                shortcut: 'Ctrl+O',
                checkable: true,
                selected: true,
                mutuallyExclusive: true,
              ),
              NativeMenuEntry.separator(),
              NativeMenuEntry.command(label: 'Disabled', enabled: false),
              NativeMenuEntry.command(
                label: 'Full Screen',
                checkable: true,
                selected: true,
              ),
            ],
            focusFirst: true,
            preferAbove: true,
          );

      expect(result.available, isTrue);
      expect(result.selectedIndex, 2);
      expect(call?.method, 'show');
      expect(call?.arguments, {
        'sessionId': session.id,
        'anchor': {'x': 12.0, 'y': 34.0, 'width': 56.0, 'height': 78.0},
        'entries': [
          {
            'label': 'Open',
            'icon': 'document-open-symbolic',
            'iconColor': 0xff3584e4,
            'shortcut': 'Ctrl+O',
            'enabled': true,
            'checkable': true,
            'selected': true,
            'mutuallyExclusive': true,
            'separator': false,
          },
          {
            'label': '',
            'enabled': false,
            'checkable': false,
            'selected': false,
            'mutuallyExclusive': false,
            'separator': true,
          },
          {
            'label': 'Disabled',
            'enabled': false,
            'checkable': false,
            'selected': false,
            'mutuallyExclusive': false,
            'separator': false,
          },
          {
            'label': 'Full Screen',
            'enabled': true,
            'checkable': true,
            'selected': true,
            'mutuallyExclusive': false,
            'separator': false,
          },
        ],
        'focusFirst': true,
        'preferredPosition': 'top',
      });
    },
  );

  test('dismiss is scoped to the native menu session', () async {
    const channel = MethodChannel('busybooks/test/native-menu-dismiss');
    MethodCall? call;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (value) async {
          call = value;
          return true;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final session = NativeMenuSession();
    final dismissed = await const NativeMenuService(
      channel: channel,
      supportedPlatform: true,
    ).dismiss(session);

    expect(dismissed, isTrue);
    expect(call?.method, 'dismiss');
    expect(call?.arguments, {'sessionId': session.id});
  });

  test('missing native host reports unavailable', () async {
    const channel = MethodChannel('busybooks/test/native-menu-missing');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw MissingPluginException(),
        );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final result =
        await const NativeMenuService(
          channel: channel,
          supportedPlatform: true,
        ).show(
          session: NativeMenuSession(),
          anchor: Rect.zero,
          entries: const [NativeMenuEntry.command(label: 'Fallback')],
        );

    expect(result.available, isFalse);
    expect(result.selectedIndex, isNull);
  });
  test(
    'disabled selected radio entries are valid; duplicate selections are not',
    () async {
      const service = NativeMenuService(supportedPlatform: false);
      const disabled = NativeMenuEntry.command(
        label: 'Reading',
        enabled: false,
        checkable: true,
        selected: true,
        mutuallyExclusive: true,
      );
      const enabled = NativeMenuEntry.command(
        label: 'Notebook',
        checkable: true,
        mutuallyExclusive: true,
      );
      expect(
        (await service.show(
          session: NativeMenuSession(),
          anchor: Rect.zero,
          entries: const [disabled, enabled],
        )).available,
        false,
      );
      await expectLater(
        service.show(
          session: NativeMenuSession(),
          anchor: Rect.zero,
          entries: const [
            disabled,
            NativeMenuEntry.command(
              label: 'Other',
              checkable: true,
              selected: true,
              mutuallyExclusive: true,
            ),
          ],
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'host presentation failure is explicit; invalid contracts remain errors',
    () async {
      const channel = MethodChannel('busybooks/test/native-menu-failure');
      var code = 'presentation-failed';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(code: code),
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      const service = NativeMenuService(
        channel: channel,
        supportedPlatform: true,
      );
      Future<NativeMenuResult> show() => service.show(
        session: NativeMenuSession(),
        anchor: Rect.zero,
        entries: const [NativeMenuEntry.command(label: 'Open')],
      );
      expect((await show()).available, false);
      code = 'invalid-arguments';
      await expectLater(show(), throwsA(isA<PlatformException>()));
    },
  );
}
