import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_settings.dart';
import '../../app/busybooks_design.dart';
import '../../app/localization.dart';
import '../../app/product_actions.dart';
import '../application/narration_controller.dart';
import '../application/reader_controller.dart';

class SpeechOption {
  const SpeechOption({this.voice, this.speed});
  final String? voice;
  final num? speed;
}

Future<void> showSpeechOptionsMenu(
  BuildContext context,
  WidgetRef ref,
) => runAppAction(context, () async {
  final reader = ref.read(readerControllerProvider.notifier);
  final speech = ref.read(narrationControllerProvider.notifier);
  final menu = BusyBooksMenuSession();
  final previousFocus = FocusManager.instance.primaryFocus;
  final owner = await reader.prepareAppearanceMenu(dismiss: menu.dismiss);
  if (owner == null) return;
  try {
    final voices = await speech.availableVoices();
    if (!context.mounted || !reader.ownsAppearanceMenu(owner)) return;
    final settings = ref.read(appSettingsControllerProvider).data;
    final l = context.l10n;
    final voice = voices.contains(settings['voice']) ? settings['voice'] : '';
    final speed = settings['speed'] as num;
    final choice = await showBusyBooksMenu<SpeechOption>(
      context: context,
      session: menu,
      focusFirst: true,
      preferAbove: true,
      items: [
        BusyBooksSubmenuItem(
          label: l.voice,
          items: [
            for (final value in {'', ...voices})
              BusyBooksPopupMenuItem(
                value: SpeechOption(voice: value),
                label: value.isEmpty ? l.system : value,
                checked: voice == value,
                trailingCheck: true,
              ),
          ],
        ),
        BusyBooksSubmenuItem(
          label: l.speed,
          items: [
            for (final value in ({
              .5,
              .75,
              1,
              1.25,
              1.5,
              1.75,
              2,
              speed,
            }.toList()..sort()))
              BusyBooksPopupMenuItem(
                value: SpeechOption(speed: value),
                label: '$value×',
                checked: speed == value,
                trailingCheck: true,
              ),
          ],
        ),
      ],
    );
    if (choice != null && context.mounted && reader.ownsAppearanceMenu(owner)) {
      await speech.configure(voice: choice.voice, speed: choice.speed);
    }
  } finally {
    final current = reader.ownsAppearanceMenu(owner);
    reader.finishAppearanceMenu(owner);
    if (current && previousFocus?.context?.mounted == true) {
      previousFocus!.requestFocus();
    }
  }
});
