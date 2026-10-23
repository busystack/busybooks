import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'app_settings.dart';
import 'app_router.dart';
import 'busybooks_design.dart';
import 'busybooks_dialogs.dart';
import 'busybooks_glyphs.dart';
import 'busybooks_main_menu.dart';
import 'command_registry.dart';
import 'keymap_controller.dart';
import 'shortcut_binding.dart';
import 'shortcut_capture.dart';
import 'localization.dart';
import 'linux/linux_page_frame.dart';
import 'linux/linux_header_style.dart';
import 'product_actions.dart';
import '../reading/presentation/appearance_panel.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String page = 'general';
  @override
  Widget build(BuildContext context) {
    final l = context.l10n, settings = ref.watch(appSettingsControllerProvider);
    return Scaffold(
      body: LinuxPageFrame(
        sidebarAvailable: true,
        sidebarExpanded: true,
        sidebarHeader: const BusyBooksLinuxBrandHeader(),
        sidebarBody: BusyBooksSidebarNavigation(
          children: [
            for (final item in [
              ('general', l.general, BusyBooksGlyphs.settings),
              ('reading', l.appearance, BusyBooksGlyphs.font),
              ('shortcuts', l.keyboardShortcuts, BusyBooksGlyphs.keyboard),
              ('backup', l.backupAndRestore, BusyBooksGlyphs.save),
            ])
              BusyBooksSidebarNavigationTile(
                selected: page == item.$1,
                leading: Icon(item.$3),
                title: Text(item.$2),
                onTap: () => setState(() => page = item.$1),
              ),
          ],
        ),
        header: BusyBooksLinuxHeaderLayout(
          leading: BusyBooksHeaderIconButton(
            tooltip: l.back,
            icon: BusyBooksGlyphs.back,
            onPressed: () {
              final uri = ref
                  .read(appRouterProvider)
                  .routeInformationProvider
                  .value
                  .uri;
              context.go(
                safeSettingsReturnTarget(uri.queryParameters['returnTo']),
              );
            },
          ),
          title: BusyBooksLinuxHeaderTitle(l.settings),
          trailing: const BusyBooksMainMenuButton(),
        ),
        body: BusyBooksClamp(
          maxWidth: BusyBooksSizes.settingsWidth,
          scrollable: false,
          child: switch (page) {
            'reading' => const AppearancePanel(defaults: true),
            'shortcuts' => const _ShortcutSettings(),
            'backup' => ListView(
              padding: const EdgeInsets.all(24),
              children: [
                BusyBooksGroupedList(
                  title: l.backupAndRestore,
                  description: l.backupHelp,
                  children: [
                    BusyBooksActionRow(
                      title: l.backup,
                      onTap: () => backupReadingData(context),
                    ),
                    BusyBooksActionRow(
                      title: l.restore,
                      onTap: () => backupReadingData(context, restore: true),
                    ),
                  ],
                ),
              ],
            ),
            _ => ListView(
              padding: const EdgeInsets.all(24),
              children: [
                BusyBooksGroupedList(
                  title: l.appearance,
                  children: [
                    BusyBooksComboRow<String>(
                      title: l.theme,
                      values: ['system', 'light', 'dark'],
                      selected: settings.data['theme'] as String,
                      labelFor: (s) => switch (s) {
                        'light' => l.light,
                        'dark' => l.dark,
                        _ => l.system,
                      },
                      onSelected: (v) => ref
                          .read(appSettingsControllerProvider.notifier)
                          .update({'theme': v}),
                    ),
                    BusyBooksComboRow<String>(
                      title: l.appLanguage,
                      values: ['system', 'en', 'de'],
                      selected: settings.data['locale'] as String? ?? 'system',
                      labelFor: (value) => value == 'system'
                          ? l.system
                          : value == 'de'
                          ? 'Deutsch'
                          : 'English',
                      onSelected: (v) => ref
                          .read(appSettingsControllerProvider.notifier)
                          .update({'locale': v == 'system' ? null : v}),
                    ),
                  ],
                ),
                BusyBooksGroupedList(
                  title: l.accessibility,
                  children: [
                    BusyBooksActionRow(
                      title: l.reducedMotion,
                      subtitle: l.system,
                    ),
                  ],
                ),
              ],
            ),
          },
        ),
      ),
    );
  }
}

class _ShortcutSettings extends ConsumerWidget {
  const _ShortcutSettings();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsControllerProvider), l = context.l10n;
    final registry = effectiveCommandRegistry(
      BusyBooksCommandCatalog.metadata,
      settings.shortcutOverrides,
    );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        BusyBooksGroupedList(
          title: l.keyboardShortcuts,
          children: [
            for (final command in registry.commands)
              BusyBooksActionRow(
                title: command.label(context),
                subtitle: command.shortcut?.label ?? l.disabled,
                onTap: () =>
                    _capture(context, ref, command, settings.shortcutOverrides),
              ),
          ],
        ),
        const SizedBox(height: 16),
        BusyBooksDialogButton(
          label: l.resetAll,
          onPressed: () =>
              ref.read(keymapControllerProvider.notifier).resetAll(),
        ),
      ],
    );
  }

  Future<void> _capture(
    BuildContext context,
    WidgetRef ref,
    BusyBooksCommand command,
    Map<String, BusyBooksKeyBinding?> expected,
  ) async {
    BusyBooksKeyBinding? candidate;
    bool reset = false, disable = false;
    final owner = Object();
    try {
      final accepted = await showBusyBooksModalDialog<bool>(
        context,
        builder: (c) => StatefulBuilder(
          builder: (c, setState) {
            BusyBooksShortcutCapture.begin(
              owner,
              onCandidate: (value) => setState(() => candidate = value),
              onCancel: () => Navigator.pop(c, false),
            );
            return BusyBooksDialogShell(
              title: command.label(c),
              actions: [
                BusyBooksDialogButton(
                  label: c.l10n.reset,
                  onPressed: () {
                    reset = true;
                    Navigator.pop(c, true);
                  },
                ),
                BusyBooksDialogButton(
                  label: c.l10n.disabled,
                  onPressed: () {
                    disable = true;
                    Navigator.pop(c, true);
                  },
                ),
                BusyBooksDialogButton(
                  label: c.l10n.cancel,
                  onPressed: () => Navigator.pop(c, false),
                ),
                BusyBooksDialogButton(
                  label: c.l10n.save,
                  suggested: true,
                  onPressed: candidate == null
                      ? null
                      : () => Navigator.pop(c, true),
                ),
              ],
              children: [
                Text(c.l10n.pressShortcut),
                const SizedBox(height: 16),
                Text(candidate?.label ?? '…'),
              ],
            );
          },
        ),
      );
      if (accepted != true) return;
    } finally {
      BusyBooksShortcutCapture.end(owner);
    }
    final result = await ref
        .read(keymapControllerProvider.notifier)
        .update(
          command.id,
          disable ? null : candidate,
          expected: expected,
          reset: reset,
        );
    if (context.mounted && result.status != KeymapUpdateStatus.saved) {
      await showError(context, switch (result.status) {
        KeymapUpdateStatus.conflict => context.l10n.shortcutConflict,
        KeymapUpdateStatus.invalid => context.l10n.shortcutInvalid,
        KeymapUpdateStatus.changed => context.l10n.shortcutChanged,
        _ => context.l10n.writeFailed,
      });
    }
  }
}
