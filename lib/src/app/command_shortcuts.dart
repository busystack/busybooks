// Adapted from BusyMark.
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:flutter/widgets.dart';

import 'command_registry.dart';
import 'command_focus.dart';
import 'busybooks_search_field.dart';

/// A disabled command still owns its combination in this context.
/// It must not fall through to a different platform text-editing operation.
class BusyBooksCommandShortcuts extends StatefulWidget {
  const BusyBooksCommandShortcuts({
    super.key,
    required this.shortcuts,
    required this.child,
    this.isComposing,
  });
  final Map<ShortcutActivator, Intent> shortcuts;
  final Widget child;
  final bool Function()? isComposing;
  @override
  State<BusyBooksCommandShortcuts> createState() =>
      _BusyBooksCommandShortcutsState();
}

class _BusyBooksCommandShortcutsState extends State<BusyBooksCommandShortcuts> {
  late final _CommandShortcutManager _manager = _CommandShortcutManager(
    widget.shortcuts,
    widget.isComposing,
  );
  @override
  void didUpdateWidget(BusyBooksCommandShortcuts oldWidget) {
    super.didUpdateWidget(oldWidget);
    _manager.update(widget.shortcuts, widget.isComposing);
  }

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Shortcuts.manager(manager: _manager, child: widget.child);
}

class _CommandShortcutManager extends ShortcutManager {
  _CommandShortcutManager(
    Map<ShortcutActivator, Intent> bindings,
    bool Function()? isComposing,
  ) {
    update(bindings, isComposing);
  }
  bool Function()? _isComposing;
  final _commandKeys = <LogicalKeyboardKey, List<ShortcutActivator>>{};
  void update(
    Map<ShortcutActivator, Intent> bindings,
    bool Function()? isComposing,
  ) {
    _isComposing = isComposing;
    shortcuts = bindings;
    _commandKeys.clear();
    for (final entry in bindings.entries) {
      if (entry.value is! BusyBooksContextCommandIntent &&
          entry.value is! BusyBooksCommandIntent) {
        continue;
      }
      for (final key in entry.key.triggers ?? <LogicalKeyboardKey>[]) {
        (_commandKeys[key] ??= []).add(entry.key);
      }
    }
  }

  @override
  KeyEventResult handleKeypress(BuildContext context, KeyEvent event) {
    if (_isComposing?.call() ?? false) {
      return KeyEventResult.skipRemainingHandlers;
    }
    final focus = FocusManager.instance.primaryFocus,
        target = FocusManager.instance.primaryFocus?.context;
    final keyboard = HardwareKeyboard.instance;
    final editable =
        focus is BusyBooksSearchFocusNode ||
        target?.widget is EditableText ||
        target?.findAncestorWidgetOfExactType<TextField>() != null;
    final modified =
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed;
    final editingCombination =
        keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed &&
        [
          LogicalKeyboardKey.keyA,
          LogicalKeyboardKey.keyC,
          LogicalKeyboardKey.keyV,
          LogicalKeyboardKey.keyX,
          LogicalKeyboardKey.keyZ,
          LogicalKeyboardKey.keyY,
        ].contains(event.logicalKey);
    if (editable && (!modified || editingCombination)) {
      return KeyEventResult.ignored;
    }
    if (!modified &&
        focus is! BusyBooksPublicationFocusNode &&
        [
          LogicalKeyboardKey.space,
          LogicalKeyboardKey.pageUp,
          LogicalKeyboardKey.pageDown,
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
        ].contains(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    final result = super.handleKeypress(context, event);
    if (result == KeyEventResult.ignored &&
        (_commandKeys[event.logicalKey] ?? const []).any(
          (a) => a.accepts(event, HardwareKeyboard.instance),
        )) {
      return KeyEventResult.handled;
    }
    return result;
  }
}
