import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../book_workspace/application/book_presentation.dart';
import '../reading/application/reader_controller.dart';
import '../reading/presentation/appearance_panel.dart';
import '../search/book_search_session.dart';
import '../search/book_search_widgets.dart';
import 'app_router.dart';
import 'app_settings.dart';
import 'busybooks_design.dart';
import 'busybooks_dialogs.dart';
import 'busybooks_glyphs.dart';
import 'busybooks_main_menu.dart';
import 'command_registry.dart';
import 'keymap_controller.dart';
import 'linux/linux_header_style.dart';
import 'linux/linux_page_frame.dart';
import 'localization.dart';
import 'product_actions.dart';
import 'settings_page.dart';
import 'shortcut_binding.dart';
import 'shortcut_capture.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
    this.initialPage = SettingsPage.general,
    this.bookPreferences = false,
  });
  final SettingsPage initialPage;
  final bool bookPreferences;
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

String settingsPageLabel(BuildContext context, SettingsPage page) =>
    switch (page) {
      SettingsPage.general => context.l10n.general,
      SettingsPage.reading => context.l10n.reading,
      SettingsPage.accessibility => context.l10n.accessibility,
      SettingsPage.shortcuts => context.l10n.keyboardShortcuts,
      SettingsPage.data => context.l10n.data,
    };
IconData _settingsPageIcon(SettingsPage page) => switch (page) {
  SettingsPage.general => BusyBooksGlyphs.settings,
  SettingsPage.reading => BusyBooksGlyphs.font,
  SettingsPage.accessibility => BusyBooksGlyphs.info,
  SettingsPage.shortcuts => BusyBooksGlyphs.keyboard,
  SettingsPage.data => BusyBooksGlyphs.save,
};

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late SettingsPage _page = widget.initialPage;
  late bool _bookPreferences = widget.bookPreferences;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n,
        settings = ref.watch(appSettingsControllerProvider),
        controller = ref.read(appSettingsControllerProvider.notifier),
        colors = BusyBooksSurfaceColors.of(context),
        search = ref.watch(bookSearchSessionProvider);
    final wide =
        MediaQuery.sizeOf(context).width >=
        BusyBooksSizes.settingsSidebarBreakpoint;
    final renderer = ref.watch(readerControllerProvider),
        reader = ref.read(readerControllerProvider.notifier),
        returnTo = ref
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .queryParameters['returnTo'];
    final currentBook =
        renderer.bookId != null &&
            bookIdForRoute(safeSettingsReturnTarget(returnTo)) ==
                renderer.bookId
        ? reader.book
        : null;
    final body = switch (_page) {
      SettingsPage.reading => Column(
        children: [
          if (currentBook != null)
            BusyBooksComboRow<bool>(
              title: l.reading,
              values: const [false, true],
              selected: _bookPreferences,
              labelFor: (value) =>
                  value ? currentBook.title : l.readingDefaults,
              onSelected: (value) => setState(() => _bookPreferences = value),
            ),
          Expanded(
            child: AppearancePanel(
              defaults: !_bookPreferences || currentBook == null,
            ),
          ),
        ],
      ),
      SettingsPage.shortcuts => const _ShortcutSettings(),
      SettingsPage.data => ListView(
        padding: BusyBooksInsets.settingsPage,
        children: [
          BusyBooksGroupedList(
            title: l.backupAndRestore,
            description: l.backupHelp,
            filled: true,
            children: [
              BusyBooksActionRow(
                title: l.backup,
                leading: const Icon(BusyBooksGlyphs.save),
                onTap: () => backupReadingData(context),
              ),
              BusyBooksActionRow(
                title: l.restore,
                leading: const Icon(BusyBooksGlyphs.documentOpen),
                onTap: () => backupReadingData(context, restore: true),
              ),
            ],
          ),
        ],
      ),
      SettingsPage.accessibility => ListView(
        padding: BusyBooksInsets.settingsPage,
        children: [
          BusyBooksGroupedList(
            title: l.accessibility,
            filled: true,
            children: [
              BusyBooksActionRow(
                title: l.reducedMotion,
                subtitle:
                    '${l.systemControlled} · ${MediaQuery.disableAnimationsOf(context) ? l.motionReduced : l.motionEnabled}',
              ),
            ],
          ),
        ],
      ),
      SettingsPage.general => ListView(
        padding: BusyBooksInsets.settingsPage,
        children: [
          BusyBooksGroupedList(
            title: l.general,
            filled: true,
            children: [
              BusyBooksComboRow<String>(
                title: l.theme,
                values: const ['system', 'light', 'dark'],
                selected: settings.data['theme'] as String,
                labelFor: (value) => switch (value) {
                  'light' => l.light,
                  'dark' => l.dark,
                  _ => l.system,
                },
                onSelected: (value) => controller.update({'theme': value}),
              ),
              BusyBooksComboRow<String>(
                title: l.appLanguage,
                values: const ['system', 'en', 'de'],
                selected: settings.data['locale'] as String? ?? 'system',
                labelFor: (value) => value == 'system'
                    ? l.system
                    : value == 'de'
                    ? 'Deutsch'
                    : 'English',
                onSelected: (value) => controller.update({
                  'locale': value == 'system' ? null : value,
                }),
              ),
            ],
          ),
        ],
      ),
    };
    void back() {
      final uri = ref
          .read(appRouterProvider)
          .routeInformationProvider
          .value
          .uri;
      context.go(safeSettingsReturnTarget(uri.queryParameters['returnTo']));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) back();
      },
      child: Scaffold(
        backgroundColor: colors.view,
        body: LinuxPageFrame(
          sidebarAvailable: wide || search.active,
          sidebarExpanded: true,
          sidebarOverlay: !wide,
          onSidebarDismiss: search.active
              ? () => ref.read(bookSearchSessionProvider.notifier).close()
              : null,
          sidebarHeader: const BusyBooksLinuxBrandHeader(),
          sidebarBody: BookSearchSidebarHost(
            child: BusyBooksSidebarNavigation(
              children: [
                for (final page in SettingsPage.values)
                  BusyBooksSidebarNavigationTile(
                    selected: _page == page,
                    leading: Icon(_settingsPageIcon(page)),
                    title: Text(settingsPageLabel(context, page)),
                    onTap: () => setState(() => _page = page),
                  ),
              ],
            ),
          ),
          header: BusyBooksLinuxHeaderLayout(
            leading: BusyBooksHeaderIconButton(
              tooltip: l.back,
              icon: BusyBooksGlyphs.back,
              onPressed: back,
            ),
            centerAllocation: search.active
                ? BusyBooksLinuxHeaderCenterAllocation.fillBetweenControls
                : BusyBooksLinuxHeaderCenterAllocation.centeredBetweenControls,
            title: search.active
                ? const BookSearchHeaderField()
                : BusyBooksLinuxHeaderTitle(settingsPageLabel(context, _page)),
            trailing: const BusyBooksMainMenuButton(),
          ),
          body: ColoredBox(
            key: const ValueKey('settings-content-surface'),
            color: colors.view,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!wide)
                  Padding(
                    padding: const EdgeInsets.all(BusyBooksSpacing.md),
                    child: BusyBooksPopupSelector<SettingsPage>(
                      key: const ValueKey('settings-page-selector'),
                      fullWidth: true,
                      value: _page,
                      label: settingsPageLabel(context, _page),
                      tooltip: l.settings,
                      options: [
                        for (final page in SettingsPage.values)
                          BusyBooksPopupSelectorOption(
                            value: page,
                            label: settingsPageLabel(context, page),
                          ),
                      ],
                      onSelected: (page) => setState(() => _page = page),
                    ),
                  ),
                Expanded(
                  child: BusyBooksClamp(
                    maxWidth: BusyBooksSizes.settingsWidth,
                    scrollable: false,
                    margin: EdgeInsets.zero,
                    padding: EdgeInsets.zero,
                    child: body,
                  ),
                ),
              ],
            ),
          ),
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
        BusyBooksPushButton.standard(
          child: Text(l.resetAll),
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
