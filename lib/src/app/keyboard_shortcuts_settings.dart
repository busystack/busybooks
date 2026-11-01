// Adapted from BusyMark keyboard_shortcuts_settings.dart (Apache-2.0).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_settings.dart';
import 'busybooks_design.dart';
import 'busybooks_dialogs.dart';
import 'command_registry.dart';
import 'keymap_controller.dart';
import 'keyboard_shortcut_badge.dart';
import 'busybooks_glyphs.dart';
import 'localization.dart';
import 'shortcut_binding.dart';
import 'shortcut_capture.dart';

class KeyboardShortcutsSettings extends ConsumerStatefulWidget {
  const KeyboardShortcutsSettings({super.key});
  @override
  ConsumerState<KeyboardShortcutsSettings> createState() =>
      _KeyboardShortcutsSettingsState();
}

class _KeyboardShortcutsSettingsState
    extends ConsumerState<KeyboardShortcutsSettings> {
  bool _restoring = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsControllerProvider);
    final registry = effectiveCommandRegistry(
      BusyBooksCommandCatalog.metadata,
      settings.shortcutOverrides,
    );
    final l10n = context.l10n;
    final categories = registry.commands
        .map((c) => c.category(context))
        .toSet()
        .toList();
    final commands = registry.commands.toList()
      ..sort((a, b) {
        final group = categories
            .indexOf(a.category(context))
            .compareTo(categories.indexOf(b.category(context)));
        if (group != 0) return group;
        final name = a.label(context).compareTo(b.label(context));
        return name != 0 ? name : a.id.compareTo(b.id);
      });
    final groups = <String, List<BusyBooksCommand>>{
      for (final category in categories)
        if (commands.any((c) => c.category(context) == category))
          category: commands
              .where((c) => c.category(context) == category)
              .toList(),
    };
    final deferred = deferredDefaultConflicts(
      BusyBooksCommandCatalog.metadata,
      validatedShortcutOverrides(
        BusyBooksCommandCatalog.metadata,
        settings.shortcutOverrides,
      ),
    );
    return ListView(
      key: const ValueKey('settings-shortcut-list'),
      padding: BusyBooksInsets.settingsPage,
      children: [
        if (ref.watch(keymapControllerProvider) == KeymapUpdateStatus.failed)
          BusyBooksBanner(
            title: l10n.shortcutSaveFailed,
            actionLabel: l10n.shortcutRetry,
            onAction: () =>
                unawaited(ref.read(keymapControllerProvider.notifier).retry()),
          ),
        for (final group in groups.entries)
          BusyBooksGroupedList(
            title: group.key,
            filled: true,
            children: [
              for (final command in group.value)
                _commandRow(context, registry, command, deferred[command.id]),
            ],
          ),
        BusyBooksGroupedList(
          filled: true,
          children: [
            BusyBooksActionRow(
              key: const ValueKey('reset-all-shortcuts'),
              title: l10n.shortcutRestoreAll,
              enabled: !_restoring,
              onTap: _restoring ? null : _restoreAll,
            ),
          ],
        ),
      ],
    );
  }

  Widget _commandRow(
    BuildContext context,
    BusyBooksCommandRegistry registry,
    BusyBooksCommand command,
    List<BusyBooksCommand>? conflicts,
  ) {
    final configurable = shortcutConfigurable(command);
    final description = [
      commandContextLabel(context, command),
      if (!configurable) context.l10n.shortcutFixed,
      if (conflicts != null) context.l10n.shortcutDefaultConflict,
      for (final a
          in registry
              .activators(command.id)
              .skip(1)
              .whereType<SingleActivator>())
        '\u2066${BusyBooksKeyBinding.fromActivator(a).label}\u2069',
    ].join(' · ');
    return BusyBooksActionRow(
      key: ValueKey('shortcut-edit-${command.id}'),
      title: command.label(context),
      subtitle: description,
      tooltip: '${command.label(context)}\n$description',
      enabled: configurable,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: BusyBooksKeyboardShortcutBadge(
          command.shortcut?.label ?? context.l10n.shortcutUnassigned,
        ),
      ),
      onTap: configurable
          ? () => showBusyBooksModalDialog<void>(
              context,
              builder: (_) => _ShortcutEditor(command: command),
            )
          : null,
    );
  }

  Future<void> _restoreAll() async {
    if (_restoring) return;
    setState(() => _restoring = true);
    try {
      final confirmed = await showBusyBooksModalDialog<bool>(
        context,
        builder: (c) => BusyBooksDialogShell(
          title: context.l10n.shortcutRestoreAll,
          actions: [
            BusyBooksPushButton.standard(
              onPressed: () => Navigator.pop(c, false),
              child: Text(context.l10n.cancel),
            ),
            BusyBooksPushButton.suggested(
              onPressed: () => Navigator.pop(c, true),
              child: Text(context.l10n.shortcutRestoreAll),
            ),
          ],
          children: [Text(context.l10n.shortcutRestoreAllQuestion)],
        ),
      );
      if (confirmed == true && mounted) {
        await ref.read(keymapControllerProvider.notifier).resetAll();
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }
}

class _ShortcutEditor extends ConsumerStatefulWidget {
  const _ShortcutEditor({required this.command});
  final BusyBooksCommand command;
  @override
  ConsumerState<_ShortcutEditor> createState() => _ShortcutEditorState();
}

class _ShortcutEditorState extends ConsumerState<_ShortcutEditor> {
  late Map<String, BusyBooksKeyBinding?> _expected;
  BusyBooksKeyBinding? _candidate;
  bool _recording = false, _saving = false;
  bool _reset = false;
  List<BusyBooksCommand> _conflicts = const [];
  String? _message;
  final _assignFocus = FocusNode();
  final _captureFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _expected = ref.read(appSettingsControllerProvider).shortcutOverrides;
    _conflicts =
        deferredDefaultConflicts(
          BusyBooksCommandCatalog.metadata,
          validatedShortcutOverrides(
            BusyBooksCommandCatalog.metadata,
            _expected,
          ),
        )[widget.command.id] ??
        const [];
    if (_conflicts.isNotEmpty) {
      _candidate = defaultBinding(
        BusyBooksCommandCatalog.metadata[widget.command.id]!,
      );
      _reset = true;
    }

    _captureFocus.addListener(() {
      if (!_captureFocus.hasFocus && _recording) {
        _cancelCapture();
      }
    });
  }

  @override
  void dispose() {
    BusyBooksShortcutCapture.end(this);
    _assignFocus.dispose();
    _captureFocus.dispose();
    super.dispose();
  }

  void _cancelCapture() {
    BusyBooksShortcutCapture.end(this);
    if (mounted) {
      setState(() {
        _recording = false;
      });
    }
  }

  void _record() {
    _captureFocus.requestFocus();
    setState(() {
      _recording = true;
      _conflicts = const [];
      _message = null;
    });
    BusyBooksShortcutCapture.begin(
      this,
      onCandidate: (binding) {
        BusyBooksShortcutCapture.end(this);
        if (!mounted) return;
        setState(() {
          _candidate = binding;
          _recording = false;
          _reset = false;
          _expected = ref.read(appSettingsControllerProvider).shortcutOverrides;
          _conflicts = effectiveCommandRegistry(
            BusyBooksCommandCatalog.metadata,
            _expected,
          ).conflicts(widget.command.id, binding);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _assignFocus.requestFocus();
        });
      },
      onCancel: _cancelCapture,
    );
  }

  Future<void> _save({bool reset = false, bool remove = false}) async {
    if (_saving) return;
    _cancelCapture();
    setState(() {
      _saving = true;
      _reset = reset;
    });
    final result = await ref
        .read(keymapControllerProvider.notifier)
        .update(
          widget.command.id,
          remove ? null : _candidate,
          expected: _expected,
          reset: reset,
        );
    if (!mounted) return;
    // A dismissed editor stays mounted through its reverse transition. A late
    // save owns this editor only; it must never pop the page now beneath it.
    if (result.status == KeymapUpdateStatus.saved &&
        ModalRoute.of(context)?.isCurrent == true) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = false;
      _conflicts = result.conflicts;
      _expected = ref.read(appSettingsControllerProvider).shortcutOverrides;
      _message = switch (result.status) {
        KeymapUpdateStatus.failed => context.l10n.shortcutSaveFailed,
        KeymapUpdateStatus.changed => context.l10n.shortcutChanged,
        KeymapUpdateStatus.invalid => context.l10n.shortcutInvalid,
        KeymapUpdateStatus.conflict => context.l10n.shortcutConflict,
        _ => null,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final current = effectiveCommandRegistry(
      BusyBooksCommandCatalog.metadata,
      ref.watch(appSettingsControllerProvider).shortcutOverrides,
    )[widget.command.id]!;
    return BusyBooksDialogShell(
      title: widget.command.label(context),
      actions: [
        BusyBooksPushButton.standard(
          onPressed: _saving
              ? null
              : () {
                  _cancelCapture();
                  Navigator.pop(context);
                },
          child: Text(l10n.cancel),
        ),
        BusyBooksPushButton.suggested(
          key: const ValueKey('assign-shortcut'),
          focusNode: _assignFocus,
          onPressed:
              _saving || _recording || _candidate == null && _conflicts.isEmpty
              ? null
              : () => _save(reset: _reset),
          child: Text(l10n.shortcutAssign),
        ),
      ],
      children: [
        if (_saving)
          Semantics(
            label: l10n.save,
            liveRegion: true,
            child: const YaruLinearProgressIndicator(
              key: ValueKey('shortcut-saving'),
            ),
          ),
        BusyBooksGroupedList(
          filled: true,
          children: [
            BusyBooksActionRow(
              title: l10n.shortcutCurrentBinding,
              subtitle: commandContextLabel(context, widget.command),
              trailing: BusyBooksKeyboardShortcutBadge(
                current.shortcut?.label ?? l10n.shortcutUnassigned,
              ),
            ),
            BusyBooksActionRow(
              key: const ValueKey('record-shortcut'),
              title: _recording ? l10n.shortcutPressKeys : l10n.shortcutRecord,
              enabled: !_saving,
              leading: const Icon(BusyBooksGlyphs.keyboard),
              onTap: _recording ? _cancelCapture : _record,
              // Focus remains on the explicit recording control, never an editor.
              trailing: Focus(
                focusNode: _captureFocus,
                skipTraversal: true,
                includeSemantics: false,
                child: const SizedBox.shrink(),
              ),
            ),
            if (_candidate != null)
              BusyBooksActionRow(
                title: l10n.shortcutProposedBinding,
                trailing: BusyBooksKeyboardShortcutBadge(_candidate!.label),
              ),
          ],
        ),
        if (_conflicts.isNotEmpty)
          BusyBooksGroupedList(
            title: l10n.shortcutConflicts,
            filled: true,
            children: [
              for (final c in _conflicts)
                BusyBooksActionRow(
                  title: c.label(context),
                  subtitle: commandContextLabel(context, c),
                  trailing: BusyBooksKeyboardShortcutBadge(
                    effectiveCommandRegistry(
                          BusyBooksCommandCatalog.metadata,
                          ref
                              .read(appSettingsControllerProvider)
                              .shortcutOverrides,
                        )[c.id]?.shortcut?.label ??
                        l10n.shortcutUnassigned,
                  ),
                ),
            ],
          ),
        if (_message != null)
          Semantics(
            liveRegion: true,
            child: Text(_message!, key: const ValueKey('shortcut-feedback')),
          ),
        BusyBooksGroupedList(
          filled: true,
          children: [
            BusyBooksActionRow(
              key: const ValueKey('remove-shortcut'),
              title: l10n.shortcutRemove,
              enabled: !_saving,
              onTap: () => _save(remove: true),
            ),
            BusyBooksActionRow(
              key: const ValueKey('restore-shortcut-default'),
              title: l10n.shortcutRestoreDefault,
              enabled: !_saving,
              onTap: () => _save(reset: true),
            ),
          ],
        ),
      ],
    );
  }
}

String commandContextLabel(
  BuildContext context,
  BusyBooksCommand command,
) => switch (command.scope) {
  BusyBooksCommandScope.application => context.l10n.shortcutContextApplication,
  BusyBooksCommandScope.documentView => context.l10n.shortcutContextDocument,
  BusyBooksCommandScope.textEditing => context.l10n.shortcutContextEditor,
  BusyBooksCommandScope.sidebar => context.l10n.shortcutContextWorkspace,
};
