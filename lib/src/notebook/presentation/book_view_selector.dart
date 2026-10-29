import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../app/busybooks_design.dart';
import '../../app/busybooks_glyphs.dart';
import '../../app/command_registry.dart';
import '../../app/localization.dart';
import '../../app/product_actions.dart';
import '../../book_workspace/application/book_sidebar_controller.dart';
import '../../book_workspace/application/book_presentation.dart';
import '../../reading/application/reader_controller.dart';
import '../../search/book_search_session.dart';
import '../../workspace/workspace_controller.dart';
import '../application/notebook_controller.dart';

Future<void> _dismissBookOverlay(
  ProviderContainer container,
  String id,
  bool narrow,
) async {
  if (!narrow) return;
  container.read(bookSearchSessionProvider.notifier).dismissForActivation();
  await container.read(bookSidebarProvider(id).notifier).setOpen(false);
}

Future<void> openNotebook(
  BuildContext context,
  WidgetRef ref,
  String id, {
  BookView? view,
  String? annotationId,
  bool Function()? canActivate,
  Future<bool> Function()? validateActivation,
}) async {
  final narrow =
      MediaQuery.sizeOf(context).width <
      BusyBooksSizes.workspaceSidebarBreakpoint;
  final container = ProviderScope.containerOf(context, listen: false);
  final router = container.read(appRouterProvider);
  final origin = router.routeInformationProvider.value.uri;
  final target = Uri(path: notebookTargetRoute(origin.path, id, view: view));
  final targetView = bookViewForRoute(target.path)!;
  if (origin == target &&
      targetView == BookView.notebook &&
      annotationId == null) {
    return;
  }
  bool sameRoute() => router.routeInformationProvider.value.uri == origin;
  bool current() => sameRoute() && (canActivate?.call() ?? true);
  Future<bool> valid() async =>
      current() &&
      (validateActivation == null || await validateActivation()) &&
      current();
  bool annotationAvailable() =>
      annotationId == null ||
      container
              .read(notebookControllerProvider)
              .findAnnotation(
                id,
                annotationId,
                container.read(workspaceControllerProvider).annotations,
              ) !=
          null;
  await container.read(workspaceControllerProvider.notifier).navigate(() async {
    if (!current()) return;
    if (container.read(workspaceControllerProvider).openedBook?.id != id) {
      await container
          .read(workspaceControllerProvider.notifier)
          .loadBook(id, activate: true, isCurrent: current);
    }
    if (!await valid() || !annotationAvailable()) return;
    if (bookIdForRoute(origin.path) != id) {
      await container
          .read(workspaceControllerProvider.notifier)
          .recordBookOpen(id);
      if (!current()) return;
    }
    final reader = container.read(readerControllerProvider.notifier);
    if (!targetView.hasReader) await reader.suspend();
    if (!await valid() || !annotationAvailable()) return;
    if (origin == target && targetView == BookView.split) {
      final presentation = container.read(bookPresentationProvider);
      if (!presentation.splitAvailable &&
          presentation.lastPane == BookPane.reading) {
        await reader.setWorkspaceVisible(false);
        if (!await valid() || !annotationAvailable()) return;
      }
      container
          .read(bookPresentationProvider.notifier)
          .focusPane(id, BookPane.notebook);
    }
    if (annotationId != null) {
      await _dismissBookOverlay(container, id, narrow);
      // A narrow handoff deliberately closes its search session. Validate the
      // route and actual record again without rejecting that owned dismissal.
      if (!await valid() ||
          !sameRoute() ||
          !(canActivate?.call() ?? true) ||
          !annotationAvailable()) {
        return;
      }
      container
          .read(notebookControllerProvider.notifier)
          .revealAnnotation(id, annotationId);
    }
    if (origin != target) {
      await reader.setWorkspaceVisible(false);
      if (!await valid() || !annotationAvailable()) {
        if (sameRoute() && bookViewForRoute(origin.path)?.hasReader == true) {
          await reader.setWorkspaceVisible(true);
        }
        return;
      }
      final presentation = container.read(bookPresentationProvider.notifier);
      presentation.enterBook(id, targetView);
      if (targetView == BookView.split) {
        presentation.focusPane(id, BookPane.notebook);
      }
      router.go(target.toString());
    }
  });
}

Future<void> openReading(
  BuildContext context,
  WidgetRef ref,
  String id, {
  BookView? view,
  Map<String, dynamic>? anchor,
  String? annotationId,
  bool Function()? canActivate,
  Future<bool> Function()? validateActivation,
  void Function(ReaderJumpRequest)? onDeferred,
}) async {
  final narrow =
      MediaQuery.sizeOf(context).width <
      BusyBooksSizes.workspaceSidebarBreakpoint;
  final container = ProviderScope.containerOf(context, listen: false);
  final router = container.read(appRouterProvider);
  final origin = router.routeInformationProvider.value.uri;
  final target = Uri(path: readingTargetRoute(origin.path, id, view: view));
  final targetView = bookViewForRoute(target.path)!;
  if (origin == target && targetView == BookView.reading && anchor == null) {
    return;
  }
  bool sameRoute() => router.routeInformationProvider.value.uri == origin;
  bool current() => sameRoute() && (canActivate?.call() ?? true);
  Future<bool> valid() async =>
      current() &&
      (validateActivation == null || await validateActivation()) &&
      current();
  bool annotationAvailable() =>
      annotationId == null ||
      container
              .read(notebookControllerProvider)
              .findAnnotation(
                id,
                annotationId,
                container.read(workspaceControllerProvider).annotations,
              ) !=
          null;
  final targetAnchor = anchor == null ? null : jsonEncode(anchor);
  Future<bool> sourceValid() async {
    if (!annotationAvailable()) return false;
    if (annotationId == null || targetAnchor == null) return true;
    final notes = container.read(notebookControllerProvider);
    final draft = notes.drafts[annotationId];
    if (draft?.creating == true && draft?.creationWritten == false) {
      final source = notes.sources[annotationId];
      return source?.bookId == id && jsonEncode(source?.anchor) == targetAnchor;
    }
    try {
      final stored =
          await container.read(readingDataStoreProvider).call('annotation', {
                'id': annotationId,
                'bookId': id,
              })
              as Map;
      return jsonEncode(stored['anchor']) == targetAnchor &&
          annotationAvailable();
    } on Object {
      return false;
    }
  }

  await container.read(workspaceControllerProvider.notifier).navigate(() async {
    if (!current()) return;
    if (container.read(workspaceControllerProvider).openedBook?.id != id) {
      await container
          .read(workspaceControllerProvider.notifier)
          .loadBook(id, activate: true, isCurrent: current);
    }
    if (!await valid() || !annotationAvailable()) return;
    final reader = container.read(readerControllerProvider.notifier);
    if (origin == target &&
        targetView == BookView.split &&
        !container.read(bookPresentationProvider).splitAvailable) {
      container
          .read(bookPresentationProvider.notifier)
          .focusPane(id, BookPane.reading);
    }
    if (anchor != null) {
      if (!await valid()) return;
      await _dismissBookOverlay(container, id, narrow);
      if (!await valid() ||
          !sameRoute() ||
          !(canActivate?.call() ?? true) ||
          !annotationAvailable()) {
        return;
      }
      if (origin == target && reader.stateBookId == id && !reader.suspended) {
        if (!sameRoute() || !await valid() || !annotationAvailable()) {
          return;
        }
        if (reader.interactive) {
          await reader.navigateFromSidebar(
            anchor,
            bookId: id,
            validateNavigation: () async =>
                await valid() && await sourceValid() && await valid(),
          );
          return;
        }
      }
    }
    ReaderJumpRequest? pending;
    if (anchor != null) {
      final routes = router.routeInformationProvider;
      var arrived = origin == target;
      ReaderJumpRequest? request;
      bool ownsRoute() =>
          routes.value.uri == (arrived ? target : origin) ||
          (!arrived && routes.value.uri == target);
      void routeChanged() {
        if (!arrived && routes.value.uri == target) arrived = true;
        if (!ownsRoute()) request?.cancel();
      }

      // The query/result validator survives an owned route through its deferred
      // activation lease; source existence is checked again after readiness.
      Future<bool> validateJump() async {
        if (!ownsRoute() ||
            !(canActivate?.call() ?? true) ||
            !annotationAvailable()) {
          return false;
        }
        if (!await sourceValid()) return false;
        return ownsRoute() &&
            (canActivate?.call() ?? true) &&
            annotationAvailable() &&
            (validateActivation == null || await validateActivation()) &&
            ownsRoute() &&
            (canActivate?.call() ?? true) &&
            annotationAvailable();
      }

      routes.addListener(routeChanged);
      request = reader.deferJump(
        bookId: id,
        anchor: anchor,
        useCurrentOpening:
            sameReaderBookRoutes(origin.path, target.path) &&
            reader.stateBookId == id,
        isCurrent: () =>
            ownsRoute() &&
            container.read(workspaceControllerProvider).openedBook?.id == id &&
            (canActivate?.call() ?? true),
        validate: validateJump,
        onReleased: () => routes.removeListener(routeChanged),
      );
      pending = request;
      onDeferred?.call(request);
    }
    if (origin != target) {
      await reader.setWorkspaceVisible(false);
      if (!await valid() || !annotationAvailable()) {
        pending?.cancel();
        if (sameRoute() && bookViewForRoute(origin.path)?.hasReader == true) {
          await reader.setWorkspaceVisible(true);
        }
        return;
      }
      final presentation = container.read(bookPresentationProvider.notifier);
      presentation.enterBook(id, targetView);
      if (targetView == BookView.split &&
          !container.read(bookPresentationProvider).splitAvailable) {
        presentation.focusPane(id, BookPane.reading);
      }
      router.go(target.toString());
    }
  });
}

// Same header selector pattern as BusyMark's document view control: labels,
// icons, effective bindings, and selected trailing check.
class BookViewSelector extends ConsumerWidget {
  const BookViewSelector({super.key, required this.id, required this.view});
  final String id;
  final BookView view;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = BusyBooksCommandRegistryScope.maybeOf(context);
    final presentation = ref.watch(bookPresentationProvider);
    final fallbackRoute = ref.read(appRouterProvider).routeInformationProvider;
    final fallbackOrigin = fallbackRoute.value.uri;
    BusyBooksPopupMenuItem<BookView> item(BuildContext context, BookView mode) {
      final command = registry?[_viewCommand(mode)];
      final enabled =
          command?.canExecute ??
          (mode != BookView.split ||
              presentation.bookId == id && presentation.splitAvailable);
      final reason = enabled
          ? null
          : command?.disabledReason?.call(context) ??
                context.l10n.splitMinimumWidth(
                  presentation.splitMetrics.minimumWidth.ceil(),
                );
      final label = switch (mode) {
        BookView.reading => context.l10n.reading,
        BookView.notebook => context.l10n.notebook,
        BookView.split => context.l10n.split,
      };
      return BusyBooksPopupMenuItem(
        value: mode,
        label: reason == null || reason.isEmpty ? label : '$label · $reason',
        icon: _viewIcon(mode),
        enabled: enabled,
        shortcut: command?.shortcut?.label,
        gtkAccelerator: command?.shortcut?.gtkAccelerator,
        checked: mode == view,
        trailingCheck: true,
      );
    }

    return BusyBooksHeaderPopupMenuButton<BookView>(
      onError: (error) => runAppAction(context, () async => throw error),
      tooltip: context.l10n.viewMode,
      icon: _viewIcon(view),
      itemBuilder: (c) => [for (final mode in BookView.values) item(c, mode)],
      onSelected: (mode) async {
        if (mode == view) return;
        final command = _viewCommand(mode);
        if (registry?[command]?.execute != null) {
          await registry!.execute(command);
        } else {
          bool current() {
            if (!context.mounted ||
                fallbackRoute.value.uri != fallbackOrigin ||
                bookIdForRoute(fallbackOrigin.path) != id) {
              return false;
            }
            final capacity = ref.read(bookPresentationProvider);
            return mode != BookView.split ||
                capacity.bookId == id && capacity.splitAvailable;
          }

          if (!current()) return;
          await runAppAction(context, () async {
            if (mode == BookView.notebook) {
              await openNotebook(
                context,
                ref,
                id,
                view: mode,
                canActivate: current,
              );
            } else {
              await openReading(
                context,
                ref,
                id,
                view: mode,
                canActivate: current,
              );
            }
          });
        }
      },
    );
  }
}

String _viewCommand(BookView view) => switch (view) {
  BookView.reading => BusyBooksCommandIds.viewReading,
  BookView.notebook => BusyBooksCommandIds.viewNotebook,
  BookView.split => BusyBooksCommandIds.viewSplit,
};

IconData _viewIcon(BookView view) => switch (view) {
  BookView.reading => BusyBooksGlyphs.previewView,
  BookView.notebook => BusyBooksGlyphs.notebookView,
  BookView.split => BusyBooksGlyphs.splitView,
};
