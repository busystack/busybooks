import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_router.dart';
import '../../app/product_actions.dart';
import '../../app/busybooks_design.dart';
import '../../app/busybooks_glyphs.dart';
import '../../app/command_registry.dart';
import '../../app/localization.dart';
import '../../workspace/workspace_controller.dart';
import '../application/notebook_controller.dart';
import '../../reading/application/reader_controller.dart';

enum BookView { reading, notebook }

Future<void> openNotebook(
  BuildContext context,
  WidgetRef ref,
  String id, {
  String? annotationId,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final router = container.read(appRouterProvider);
  final origin = router.routeInformationProvider.value.uri;
  if (origin.path == '/notebook/$id' && annotationId == null) return;
  bool current() => router.routeInformationProvider.value.uri == origin;
  await container.read(workspaceControllerProvider.notifier).navigate(() async {
    if (!current()) return;
    await container
        .read(workspaceControllerProvider.notifier)
        .loadBook(id, activate: true, isCurrent: current);
    if (!current()) return;
    if (origin.path != '/read/$id' && origin.path != '/notebook/$id') {
      await container
          .read(workspaceControllerProvider.notifier)
          .recordBookOpen(id);
      if (!current()) return;
    }
    await container.read(readerControllerProvider.notifier).suspend();
    if (!current()) return;
    if (annotationId != null) {
      container
          .read(notebookControllerProvider.notifier)
          .revealAnnotation(id, annotationId);
    }
    router.go('/notebook/$id');
  });
}

Future<void> openReading(
  BuildContext context,
  WidgetRef ref,
  String id, {
  Map<String, dynamic>? anchor,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final router = container.read(appRouterProvider);
  final origin = router.routeInformationProvider.value.uri;
  if (origin.path == '/read/$id' && anchor == null) return;
  bool current() => router.routeInformationProvider.value.uri == origin;
  await container.read(workspaceControllerProvider.notifier).navigate(() async {
    if (!current()) return;
    await container
        .read(workspaceControllerProvider.notifier)
        .loadBook(id, activate: true, isCurrent: current);
    if (!current()) return;
    container.read(readerControllerProvider.notifier).pendingJump = anchor;
    router.go('/read/$id');
  });
}

// Same header selector pattern as BusyMark's document view control: labels,
// icons, effective bindings, selected trailing check. Only two book views.
class BookViewSelector extends ConsumerWidget {
  const BookViewSelector({super.key, required this.id, required this.view});
  final String id;
  final BookView view;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = BusyBooksCommandRegistryScope.maybeOf(context);
    return BusyBooksHeaderPopupMenuButton<BookView>(
      onError: (error) => runAppAction(context, () async => throw error),
      tooltip: context.l10n.viewMode,
      icon: view == BookView.reading
          ? BusyBooksGlyphs.previewView
          : BusyBooksGlyphs.notebookView,
      itemBuilder: (c) => [
        for (final mode in BookView.values)
          BusyBooksPopupMenuItem(
            value: mode,
            label: mode == BookView.reading ? c.l10n.reading : c.l10n.notebook,
            icon: mode == BookView.reading
                ? BusyBooksGlyphs.previewView
                : BusyBooksGlyphs.notebookView,
            shortcut:
                registry?[mode == BookView.reading
                        ? BusyBooksCommandIds.viewReading
                        : BusyBooksCommandIds.viewNotebook]
                    ?.shortcut
                    ?.label,
            gtkAccelerator:
                registry?[mode == BookView.reading
                        ? BusyBooksCommandIds.viewReading
                        : BusyBooksCommandIds.viewNotebook]
                    ?.shortcut
                    ?.gtkAccelerator,
            checked: mode == view,
            trailingCheck: true,
          ),
      ],
      onSelected: (mode) async {
        if (mode == view) return;
        final command = mode == BookView.reading
            ? BusyBooksCommandIds.viewReading
            : BusyBooksCommandIds.viewNotebook;
        if (registry?[command]?.execute != null) {
          await registry!.execute(command);
        } else {
          await runAppAction(context, () async {
            if (mode == BookView.notebook) {
              await openNotebook(context, ref, id);
            } else {
              await openReading(context, ref, id);
            }
          });
        }
      },
    );
  }
}
