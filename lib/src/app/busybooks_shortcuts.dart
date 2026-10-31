import 'shortcut_binding.dart';
import 'package:flutter/widgets.dart';

class BusyBooksShortcutDefinition {
  const BusyBooksShortcutDefinition({
    required this.label,
    required this.activator,
    String? gtkAccelerator,
  }) : _gtkAccelerator = gtkAccelerator;

  final String label;
  final ShortcutActivator activator;

  /// GTK accelerator syntax for native controls that render this command.
  ///
  /// This is deliberately separate from [label]: GTK parses strings such as
  /// `<Primary>comma`, then formats the visible label for the current desktop.
  final String? _gtkAccelerator;
  String? get gtkAccelerator =>
      _gtkAccelerator ??
      switch (activator) {
        final SingleActivator value => BusyBooksKeyBinding.fromActivator(
          value,
        ).gtkAccelerator,
        _ => null,
      };
}
