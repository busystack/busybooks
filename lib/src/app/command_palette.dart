import 'package:flutter/material.dart';
import 'busybooks_design.dart';
import 'busybooks_dialogs.dart';
import 'busybooks_search_field.dart';
import 'command_registry.dart';
import 'localization.dart';

Future<void> showCommandPalette(
  BuildContext context,
  BusyBooksCommandRegistry registry,
) async {
  String query = '';
  final selected = await showBusyBooksModalDialog<String>(
    context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => BusyBooksDialogShell(
        title: c.l10n.commandPalette,
        children: [
          BusyBooksSearchField(
            autofocus: true,
            onChanged: (v) => setState(() => query = v),
          ),
          const SizedBox(height: 12),
          for (final command in registry.visibleCommands().where(
            (x) => x.label(c).toLowerCase().contains(query.toLowerCase()),
          ))
            BusyBooksActionRow(
              title: command.label(c),
              subtitle: command.shortcut?.label,
              enabled: command.canExecute,
              onTap: () => Navigator.pop(c, command.id),
            ),
        ],
      ),
    ),
  );
  if (selected != null) await registry.execute(selected);
}
