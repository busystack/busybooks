// Adapted from BusyMark command registry. Product catalog is independent.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'busybooks_shortcuts.dart';
import 'shortcut_binding.dart';
import 'shortcut_capture.dart';
import 'localization.dart';

typedef BusyBooksCommandCallback = FutureOr<void> Function();
typedef BusyBooksCommandPredicate = bool Function();
typedef BusyBooksCommandLabel = String Function(BuildContext context);
typedef BusyBooksCommandDescription = String? Function(BuildContext context);

class BusyBooksCommandIntent extends Intent {
  const BusyBooksCommandIntent(this.commandId);

  final String commandId;
}

class BusyBooksContextCommandIntent extends Intent {
  const BusyBooksContextCommandIntent(this.commandId);

  final String commandId;
}

class BusyBooksContextCommandAction
    extends Action<BusyBooksContextCommandIntent> {
  BusyBooksContextCommandAction({
    required this.isCommandEnabled,
    required this.onCommand,
    this.captureTarget,
  });

  final bool Function(String commandId) isCommandEnabled;
  final void Function(String commandId) onCommand;
  final BusyBooksContextCommandSnapshot Function()? captureTarget;

  @override
  bool isEnabled(BusyBooksContextCommandIntent intent) {
    return isCommandEnabled(intent.commandId);
  }

  @override
  Object? invoke(BusyBooksContextCommandIntent intent) {
    onCommand(intent.commandId);
    return null;
  }
}

/// Text controls capture their selection before the query receives focus.
/// Validation never restores a different selection.
class BusyBooksContextCommandSnapshot {
  const BusyBooksContextCommandSnapshot(this._validate);
  final bool Function() _validate;
  bool get isCurrent => _validate();
}

enum BusyBooksCommandScope { application, documentView, sidebar, textEditing }

enum BusyBooksCommandResourceContext { any }

@immutable
class BusyBooksCommand {
  const BusyBooksCommand({
    required this.id,
    required this.label,
    required this.category,
    required this.scope,
    this.shortcut,
    this.defaultYieldsToOverrides = false,
    this.resourceContext = BusyBooksCommandResourceContext.any,
    this.description,
    this.disabledReason,
    this.execute,
    this.enabled = _always,
    this.visible = _always,
  });

  final String id;
  final BusyBooksCommandLabel label;
  final BusyBooksCommandLabel category;
  final BusyBooksCommandScope scope;
  final BusyBooksShortcutDefinition? shortcut;
  final bool defaultYieldsToOverrides;
  final BusyBooksCommandResourceContext resourceContext;

  BusyBooksCommand withShortcut(BusyBooksShortcutDefinition? value) =>
      BusyBooksCommand(
        id: id,
        label: label,
        category: category,
        scope: scope,
        shortcut: value,
        defaultYieldsToOverrides: defaultYieldsToOverrides,
        resourceContext: resourceContext,
        description: description,
        disabledReason: disabledReason,
        execute: execute,
        enabled: enabled,
        visible: visible,
      );
  final BusyBooksCommandDescription? description;
  final BusyBooksCommandDescription? disabledReason;
  final BusyBooksCommandCallback? execute;
  final BusyBooksCommandPredicate enabled;
  final BusyBooksCommandPredicate visible;

  bool get canExecute => execute != null && enabled();

  static bool _always() => true;
}

class BusyBooksCommandRegistryScope extends InheritedWidget {
  const BusyBooksCommandRegistryScope({
    super.key,
    required this.registry,
    required super.child,
  });

  final BusyBooksCommandRegistry registry;

  static BusyBooksCommandRegistry? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<BusyBooksCommandRegistryScope>()
        ?.registry;
  }

  static BusyBooksCommandRegistry? read(BuildContext context) {
    final widget = context
        .getElementForInheritedWidgetOfExactType<
          BusyBooksCommandRegistryScope
        >()
        ?.widget;
    return widget is BusyBooksCommandRegistryScope ? widget.registry : null;
  }

  @override
  bool updateShouldNotify(BusyBooksCommandRegistryScope oldWidget) {
    return !identical(registry, oldWidget.registry);
  }
}

class BusyBooksCommandRegistryValidationException implements Exception {
  const BusyBooksCommandRegistryValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BusyBooksCommandRegistry {
  BusyBooksCommandRegistry(Iterable<BusyBooksCommand> commands)
    : commands = List.unmodifiable(commands) {
    _validate(this.commands);
    _byId = {for (final command in this.commands) command.id: command};
    for (final c in this.commands) {
      _aliases[c.id] = _defaultAliases(c);
    }
    _compileKeyCandidates();
  }

  final List<BusyBooksCommand> commands;
  final Map<String, List<ShortcutActivator>> _aliases = {};
  final Map<(BusyBooksCommandScope, LogicalKeyboardKey), List<String>>
  _keyCandidates = {};
  void _compileKeyCandidates() {
    _keyCandidates.clear();
    for (final c in commands) {
      for (final activator in activators(c.id)) {
        for (final trigger in activator.triggers ?? <LogicalKeyboardKey>[]) {
          (_keyCandidates[(c.scope, trigger)] ??= []).add(c.id);
        }
      }
    }
  }

  final Map<String, BusyBooksCommand> _replacedDefaults = {};
  final Map<String, List<ShortcutActivator>> _retiredBindings = {};
  final Map<int, List<ShortcutActivator>> _blockedBindings = {};
  List<ShortcutActivator> _blockedFor(Set<BusyBooksCommandScope> scopes) {
    final key = scopes.fold(0, (int bits, scope) => bits | 1 << scope.index);
    return _blockedBindings.putIfAbsent(key, () {
      final receivers = {
        ...scopes,
        BusyBooksCommandScope.application,
        BusyBooksCommandScope.documentView,
        BusyBooksCommandScope.sidebar,
      };
      bool replaced(BusyBooksCommand old, ShortcutActivator retired) =>
          commands.any(
            (c) =>
                receivers.contains(c.scope) &&
                contextsOverlap(old, c) &&
                activators(c.id).any(
                  (a) => a is SingleActivator && retired is SingleActivator
                      ? BusyBooksKeyBinding.fromActivator(a) ==
                            BusyBooksKeyBinding.fromActivator(retired)
                      : a == retired,
                ),
          );
      return [
        for (final c in _replacedDefaults.values)
          if (scopes.contains(c.scope))
            for (final a in _retiredBindings[c.id] ?? <ShortcutActivator>[])
              if (!replaced(c, a)) a,
      ];
    });
  }

  Map<ShortcutActivator, Intent> blockedDefaultIntents(
    Set<BusyBooksCommandScope> scopes,
  ) => {
    for (final a in _blockedFor(scopes))
      a: const DoNothingAndStopPropagationIntent(),
  };
  bool blocksReplacedDefault(
    KeyEvent event,
    HardwareKeyboard keyboard,
    Set<BusyBooksCommandScope> scopes,
  ) => _blockedFor(scopes).any((a) => a.accepts(event, keyboard));
  List<ShortcutActivator> activators(String id) => [
    if (_byId[id]?.shortcut case final value?) value.activator,
    ...?_aliases[id],
  ];

  BusyBooksCommandRegistry withOverrides(
    Map<String, BusyBooksKeyBinding?> overrides,
  ) {
    final result = BusyBooksCommandRegistry([
      for (final command in commands)
        if (!overrides.containsKey(command.id))
          command
        else
          command.withShortcut(switch (overrides[command.id]) {
            final binding? => BusyBooksShortcutDefinition(
              label: binding.label,
              activator: binding.activator,
              gtkAccelerator: binding.gtkAccelerator,
            ),
            _ => null,
          }),
    ]);
    result._aliases.clear();
    for (final command in result.commands) {
      if (overrides.containsKey(command.id)) {
        result._replacedDefaults[command.id] = this[command.id]!;
        result._retiredBindings[command.id] = activators(command.id);
      } else {
        result._aliases[command.id] = _defaultAliases(command);
      }
    }
    result._compileKeyCandidates();
    return result;
  }

  Map<ShortcutActivator, Intent> bindingIntents(String id, Intent intent) => {
    for (final activator in activators(id)) activator: intent,
  };

  /// Actual receiving contexts overlap across scopes. Tree browsing is the one
  /// disjoint document context; line movement edits the Source .tree buffer.
  static bool contextsOverlap(BusyBooksCommand a, BusyBooksCommand b) => true;

  List<BusyBooksCommand> conflicts(String id, BusyBooksKeyBinding binding) {
    final command = this[id];
    if (command == null) return const [];
    return [
      for (final other in commands)
        if (other.id != id &&
            contextsOverlap(command, other) &&
            activators(other.id).whereType<SingleActivator>().any(
              (a) => BusyBooksKeyBinding.fromActivator(a) == binding,
            ))
          other,
    ];
  }

  late final Map<String, BusyBooksCommand> _byId;

  BusyBooksCommand? operator [](String id) => _byId[id];

  List<BusyBooksCommand> visibleCommands() => [
    for (final command in commands)
      if (command.visible()) command,
  ];

  /// Native content has document focus. Prefer its enabled effective command
  /// over an application binding, and never stop at a disabled scope.
  BusyBooksCommand? commandForNativeBinding(BusyBooksKeyBinding binding) {
    final candidates = commands.where((c) => c.canExecute).toList()
      ..sort((a, b) => b.scope.index.compareTo(a.scope.index));
    for (final command in candidates) {
      if (activators(command.id).whereType<SingleActivator>().any(
        (a) => BusyBooksKeyBinding.fromActivator(a) == binding,
      )) {
        return command;
      }
    }
    return null;
  }

  Future<bool> execute(String id) async {
    final command = _byId[id];
    if (command == null || !command.canExecute) {
      return false;
    }
    await command.execute!();
    return true;
  }

  bool canExecuteInContext(String id, BuildContext? contextTarget) {
    final command = _byId[id];
    if (command == null || command.execute == null) {
      return false;
    }
    if (!isContextual(command) || contextTarget == null) {
      return command.enabled();
    }
    final action = Actions.maybeFind<BusyBooksContextCommandIntent>(
      contextTarget,
    );
    return action?.isEnabled(BusyBooksContextCommandIntent(id)) ?? false;
  }

  Future<bool> executeInContext(String id, BuildContext? contextTarget) async {
    final command = _byId[id];
    if (command == null || !canExecuteInContext(id, contextTarget)) {
      return false;
    }
    if (isContextual(command) && contextTarget != null) {
      Actions.maybeInvoke(contextTarget, BusyBooksContextCommandIntent(id));
      return true;
    }
    await command.execute!();
    return true;
  }

  bool isContextual(BusyBooksCommand command) => false;
  bool requiresDocumentTarget(BusyBooksCommand command) =>
      command.scope == BusyBooksCommandScope.documentView;
  bool requiresWorkspaceTarget(BusyBooksCommand command) => false;

  bool shortcutAccepts(String id, KeyEvent event, HardwareKeyboard keyboard) {
    return !BusyBooksShortcutCapture.suppressing &&
        activators(id).any((a) => a.accepts(event, keyboard));
  }

  String? matchingCommandId(
    KeyEvent event,
    HardwareKeyboard keyboard, {
    required BusyBooksCommandScope scope,
  }) {
    if (BusyBooksShortcutCapture.suppressing) return null;
    for (final id in _keyCandidates[(scope, event.logicalKey)] ?? <String>[]) {
      if (shortcutAccepts(id, event, keyboard)) return id;
    }
    return null;
  }

  Map<ShortcutActivator, Intent> shortcutIntents({
    required Set<BusyBooksCommandScope> scopes,
    required Intent Function(String commandId) intentFor,
    Set<String> excludedIds = const {},
  }) {
    return {
      for (final command in commands)
        if (scopes.contains(command.scope) &&
            command.shortcut != null &&
            !excludedIds.contains(command.id))
          for (final activator in activators(command.id))
            activator: intentFor(command.id),
    };
  }

  static void _validate(List<BusyBooksCommand> commands) {
    final ids = <String>{};
    final shortcuts =
        <(BusyBooksCommandScope, Object), List<BusyBooksCommand>>{};
    for (final command in commands) {
      if (!RegExp(
        r'^[a-z][A-Za-z0-9]*(?:\.[a-z][A-Za-z0-9]*)+$',
      ).hasMatch(command.id)) {
        throw BusyBooksCommandRegistryValidationException(
          'Invalid command ID: ${command.id}',
        );
      }
      if (!ids.add(command.id)) {
        throw BusyBooksCommandRegistryValidationException(
          'Duplicate command ID: ${command.id}',
        );
      }
      final shortcut = command.shortcut;
      if (shortcut == null) {
        continue;
      }
      final activator = shortcut.activator;
      final key = (
        command.scope,
        activator is SingleActivator
            ? BusyBooksKeyBinding.fromActivator(activator)
            : activator,
      );
      final existing = shortcuts[key] ??= [];
      for (final other in existing) {
        if (contextsOverlap(command, other)) {
          throw BusyBooksCommandRegistryValidationException(
            'Shortcut conflict in ${command.scope.name}: ${other.id} and ${command.id}',
          );
        }
      }
      existing.add(command);
    }
  }
}

List<ShortcutActivator> _defaultAliases(BusyBooksCommand command) =>
    switch (command.id) {
      BusyBooksCommandIds.next => const [
        SingleActivator(LogicalKeyboardKey.arrowRight),
        SingleActivator(LogicalKeyboardKey.space),
      ],
      BusyBooksCommandIds.previous => const [
        SingleActivator(LogicalKeyboardKey.arrowLeft),
        SingleActivator(LogicalKeyboardKey.space, shift: true),
      ],
      _ => const [],
    };

abstract final class BusyBooksCommandIds {
  static const open = 'file.openBook';
  static const openCollection = 'workspace.openCollection';
  static const createCollection = 'workspace.createCollection';
  static const addBooks = 'workspace.addBooks';
  static const closeWorkspace = 'workspace.close';
  static const refreshWorkspace = 'workspace.refresh';
  static const welcome = 'app.welcome';
  static const search = 'reader.search';
  static const searchCollection = 'workspace.search';
  static const sidebar = 'reader.sidebar';
  static const goTo = 'reader.goTo';
  static const backToCollection = 'book.backToCollection';
  static const returnToPassage = 'reader.returnToPassage';
  static const nextResult = 'reader.nextResult';
  static const previousResult = 'reader.previousResult';
  static const addNote = 'reader.addNote';
  static const outline = 'reader.outline';
  static const annotations = 'reader.annotations';
  static const thumbnails = 'reader.thumbnails';
  static const readerBooks = 'reader.books';
  static const appearance = 'reader.appearance';
  static const bookmark = 'reader.bookmark';
  static const highlight = 'reader.highlight';
  static const dictionary = 'reader.dictionary';
  static const readAloud = 'reader.readAloud';
  static const next = 'reader.next';
  static const previous = 'reader.previous';
  static const back = 'reader.back';
  static const forward = 'reader.forward';
  static const fullScreen = 'window.fullScreen';
  static const settings = 'app.settings';
  static const commandPalette = 'app.commandPalette';
  static const export = 'book.exportAnnotations';
  static const viewReading = 'book.viewReading';
  static const viewNotebook = 'book.viewNotebook';
  static const moveBook = 'book.move';
  static const locateBook = 'book.locate';
}

abstract final class BusyBooksCommandCatalog {
  static final metadata = create();
  static BusyBooksCommandRegistry create({
    Map<String, BusyBooksCommandCallback> executions = const {},
    Map<String, BusyBooksCommandLabel> labels = const {},
    Map<String, BusyBooksCommandPredicate> enabled = const {},
    Map<String, BusyBooksCommandPredicate> visible = const {},
  }) {
    BusyBooksCommand command(
      String id,
      String Function(BuildContext) label,
      LogicalKeyboardKey key, {
      bool control = false,
      bool alt = false,
      bool shift = false,
      bool reader = true,
    }) {
      final binding = BusyBooksKeyBinding(
        key,
        control: control,
        alt: alt,
        shift: shift,
      );
      return BusyBooksCommand(
        id: id,
        label: labels[id] ?? label,
        category: (c) => reader ? c.l10n.reader : c.l10n.workspace,
        scope: reader
            ? BusyBooksCommandScope.documentView
            : BusyBooksCommandScope.application,
        shortcut: BusyBooksShortcutDefinition(
          label: binding.label,
          activator: binding.activator,
        ),
        execute: executions[id],
        enabled: enabled[id] ?? () => true,
        visible: visible[id] ?? () => true,
      );
    }

    return BusyBooksCommandRegistry([
      command(
        BusyBooksCommandIds.viewReading,
        (c) => c.l10n.reading,
        LogicalKeyboardKey.digit1,
        control: true,
        alt: true,
      ),
      command(
        BusyBooksCommandIds.viewNotebook,
        (c) => c.l10n.notebook,
        LogicalKeyboardKey.digit2,
        control: true,
        alt: true,
      ),
      command(
        BusyBooksCommandIds.moveBook,
        (c) => c.l10n.moveBook,
        LogicalKeyboardKey.keyM,
        control: true,
        alt: true,
      ),
      command(
        BusyBooksCommandIds.locateBook,
        (c) => c.l10n.locateBook,
        LogicalKeyboardKey.keyL,
        control: true,
        alt: true,
      ),
      command(
        BusyBooksCommandIds.searchCollection,
        (c) => c.l10n.collectionSearchScope,
        LogicalKeyboardKey.keyF,
        control: true,
        reader: false,
      ),
      command(
        BusyBooksCommandIds.sidebar,
        (c) => c.l10n.sidebar,
        LogicalKeyboardKey.f9,
      ),
      command(
        BusyBooksCommandIds.goTo,
        (c) => c.l10n.goTo,
        LogicalKeyboardKey.keyG,
        control: true,
      ),
      command(
        BusyBooksCommandIds.nextResult,
        (c) => c.l10n.nextResult,
        LogicalKeyboardKey.f3,
      ),
      command(
        BusyBooksCommandIds.previousResult,
        (c) => c.l10n.previousResult,
        LogicalKeyboardKey.f3,
        shift: true,
      ),
      command(
        BusyBooksCommandIds.addNote,
        (c) => c.l10n.addNote,
        LogicalKeyboardKey.keyN,
        control: true,
        shift: true,
      ),
      command(
        BusyBooksCommandIds.open,
        (c) => c.l10n.openBook,
        LogicalKeyboardKey.keyO,
        control: true,
        reader: false,
      ),
      for (final (id, label, reader) in [
        (
          BusyBooksCommandIds.backToCollection,
          (BuildContext c) => c.l10n.backToCollection,
          false,
        ),
        (
          BusyBooksCommandIds.returnToPassage,
          (BuildContext c) => c.l10n.returnToPassage,
          true,
        ),
      ])
        BusyBooksCommand(
          id: id,
          label: labels[id] ?? label,
          category: (c) => reader ? c.l10n.reader : c.l10n.workspace,
          scope: reader
              ? BusyBooksCommandScope.documentView
              : BusyBooksCommandScope.application,
          execute: executions[id],
          enabled: enabled[id] ?? () => true,
          visible: visible[id] ?? () => true,
        ),
      command(
        BusyBooksCommandIds.welcome,
        (c) => c.l10n.welcome,
        LogicalKeyboardKey.keyL,
        control: true,
        reader: false,
      ),
      command(
        BusyBooksCommandIds.openCollection,
        (c) => c.l10n.openCollection,
        LogicalKeyboardKey.keyO,
        control: true,
        shift: true,
        reader: false,
      ),
      command(
        BusyBooksCommandIds.createCollection,
        (c) => c.l10n.createCollection,
        LogicalKeyboardKey.keyN,
        control: true,
        shift: true,
        reader: false,
      ),
      command(
        BusyBooksCommandIds.addBooks,
        (c) => c.l10n.addExistingBooks,
        LogicalKeyboardKey.keyA,
        control: true,
        shift: true,
        reader: false,
      ),
      command(
        BusyBooksCommandIds.closeWorkspace,
        (c) => c.l10n.closeWorkspace,
        LogicalKeyboardKey.keyW,
        control: true,
        reader: false,
      ),
      command(
        BusyBooksCommandIds.refreshWorkspace,
        (c) => c.l10n.refreshWorkspace,
        LogicalKeyboardKey.f5,
        reader: false,
      ),
      command(
        BusyBooksCommandIds.search,
        (c) => c.l10n.searchBook,
        LogicalKeyboardKey.keyF,
        control: true,
        reader: true,
      ),
      command(
        BusyBooksCommandIds.outline,
        (c) => c.l10n.outline,
        LogicalKeyboardKey.keyT,
        control: true,
        reader: true,
      ),
      for (final (id, label) in [
        (BusyBooksCommandIds.thumbnails, (BuildContext c) => c.l10n.thumbnails),
        (BusyBooksCommandIds.readerBooks, (BuildContext c) => c.l10n.books),
      ])
        BusyBooksCommand(
          id: id,
          label: labels[id] ?? label,
          category: (c) => c.l10n.reader,
          scope: BusyBooksCommandScope.documentView,
          execute: executions[id],
          enabled: enabled[id] ?? () => true,
          visible: visible[id] ?? () => true,
        ),
      command(
        BusyBooksCommandIds.annotations,
        (c) => c.l10n.annotations,
        LogicalKeyboardKey.keyH,
        control: true,
        shift: true,
        reader: true,
      ),
      command(
        BusyBooksCommandIds.appearance,
        (c) => c.l10n.appearance,
        LogicalKeyboardKey.keyA,
        control: true,
        shift: true,
        reader: true,
      ),
      command(
        BusyBooksCommandIds.bookmark,
        (c) => c.l10n.bookmark,
        LogicalKeyboardKey.keyB,
        control: true,
        reader: true,
      ),
      command(
        BusyBooksCommandIds.highlight,
        (c) => c.l10n.highlight,
        LogicalKeyboardKey.keyH,
        control: true,
        reader: true,
      ),
      command(
        BusyBooksCommandIds.dictionary,
        (c) => c.l10n.dictionary,
        LogicalKeyboardKey.keyD,
        control: true,
        reader: true,
      ),
      command(
        BusyBooksCommandIds.readAloud,
        (c) => c.l10n.readAloud,
        LogicalKeyboardKey.keyS,
        control: true,
        shift: true,
        reader: true,
      ),
      command(
        BusyBooksCommandIds.next,
        (c) => c.l10n.nextPage,
        LogicalKeyboardKey.pageDown,
        reader: true,
      ),
      command(
        BusyBooksCommandIds.previous,
        (c) => c.l10n.previousPage,
        LogicalKeyboardKey.pageUp,
        reader: true,
      ),
      command(
        BusyBooksCommandIds.back,
        (c) => c.l10n.readingBack,
        LogicalKeyboardKey.arrowLeft,
        alt: true,
        reader: true,
      ),
      command(
        BusyBooksCommandIds.forward,
        (c) => c.l10n.readingForward,
        LogicalKeyboardKey.arrowRight,
        alt: true,
        reader: true,
      ),
      command(
        BusyBooksCommandIds.fullScreen,
        (c) => c.l10n.fullScreen,
        LogicalKeyboardKey.f11,
        reader: false,
      ),
      command(
        BusyBooksCommandIds.settings,
        (c) => c.l10n.settings,
        LogicalKeyboardKey.keyS,
        control: true,
        alt: true,
        reader: false,
      ),
      command(
        BusyBooksCommandIds.commandPalette,
        (c) => c.l10n.commandPalette,
        LogicalKeyboardKey.keyP,
        control: true,
        shift: true,
        reader: false,
      ),
      command(
        BusyBooksCommandIds.export,
        (c) => c.l10n.exportAnnotations,
        LogicalKeyboardKey.keyE,
        control: true,
        shift: true,
        reader: true,
      ),
    ]);
  }
}
