import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../library/domain/book.dart';
import '../library/domain/book_format.dart';
import '../notebook/application/notebook_controller.dart';
import '../notebook/presentation/book_view_selector.dart';
import '../reading/application/narration_controller.dart';
import '../reading/application/reader_controller.dart';
import '../workspace/workspace_controller.dart';
import '../workspace/workspace_model.dart';
import 'app_router.dart';
import 'app_settings.dart';
import 'busybooks_design.dart';
import 'busybooks_dialogs.dart';
import 'busybooks_glyphs.dart';
import 'busybooks_toast.dart';
import 'localization.dart';
import 'settings_page.dart';

Future<void> showError(BuildContext context, Object error) =>
    showBusyBooksModalDialog<void>(
      context,
      builder: (c) => BusyBooksDialogShell(
        title: c.l10n.error,
        actions: [
          BusyBooksDialogButton(
            label: c.l10n.close,
            onPressed: () => Navigator.pop(c),
          ),
        ],
        children: [SelectableText(error.toString())],
      ),
    );
Future<void> runAppAction(
  BuildContext context,
  FutureOr<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    final target =
        rootNavigatorKey.currentState?.overlay?.context ??
        (context.mounted ? context : null);
    if (target != null && target.mounted) await showError(target, error);
  }
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  bool destructive = false,
  String? acceptLabel,
}) async =>
    await showBusyBooksModalDialog<bool>(
      context,
      builder: (c) => BusyBooksDialogShell(
        title: title,
        actions: [
          BusyBooksDialogButton(
            label: c.l10n.cancel,
            onPressed: () => Navigator.pop(c, false),
          ),
          BusyBooksDialogButton(
            label: acceptLabel ?? (destructive ? c.l10n.delete : c.l10n.open),
            destructive: destructive,
            suggested: !destructive,
            onPressed: () => Navigator.pop(c, true),
          ),
        ],
        children: [Text(message)],
      ),
    ) ??
    false;
Future<String?> textPrompt(
  BuildContext context,
  String title, {
  String value = '',
  bool multiline = false,
  String? help,
}) async {
  final controller = TextEditingController(text: value);
  try {
    return await showBusyBooksModalDialog<String>(
      context,
      builder: (c) => BusyBooksDialogShell(
        title: title,
        actions: [
          BusyBooksDialogButton(
            label: c.l10n.cancel,
            onPressed: () => Navigator.pop(c),
          ),
          BusyBooksDialogButton(
            label: c.l10n.save,
            suggested: true,
            onPressed: () => Navigator.pop(c, controller.text),
          ),
        ],
        children: [
          if (help != null) Text(help),
          BusyBooksGroupedTextEntry(
            label: title,
            controller: controller,
            autofocus: true,
            minLines: multiline ? 3 : 1,
            maxLines: multiline ? 8 : 1,
            onSubmitted: (_) => Navigator.pop(c, controller.text),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

final bookFileTypes = XTypeGroup(
  label: 'EPUB / PDF / FB2 / CBZ / CBR',
  // GTK's extension patterns are case sensitive. Use ordinary suffix variants
  // so compound names remain visible without accepting generic ZIP/RAR files.
  extensions: Platform.isLinux
      ? [for (final suffix in bookSuffixes) ..._suffixCases(suffix)]
      : bookSuffixes,
);

Iterable<String> _suffixCases(String suffix) sync* {
  if (suffix.isEmpty) {
    yield '';
    return;
  }
  final first = suffix[0], rest = suffix.substring(1);
  for (final tail in _suffixCases(rest)) {
    yield '$first$tail';
    if (first.toUpperCase() != first) yield '${first.toUpperCase()}$tail';
  }
}

Future<void> _readerLocation(ProviderContainer container, String id) async {
  final router = container.read(appRouterProvider);
  if (router.routeInformationProvider.value.uri.path == '/read/$id') {
    await container.read(readerControllerProvider.notifier).open(id);
  } else {
    router.go('/read/$id');
  }
}

Future<void> openPaths(
  BuildContext context,
  WidgetRef ref, {
  List<String>? paths,
  String? expectedId,
  String? expectedKind,
  bool acceptChanged = false,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final navigation = ref.read(workspaceControllerProvider.notifier);
  final selected =
      paths ??
      [
        if (await openFile(acceptedTypeGroups: [bookFileTypes])
            case final file?)
          file.path,
      ];
  for (final path in selected) {
    if (!context.mounted) return;
    try {
      await navigation.navigate(() async {
        final workspace = await container
            .read(workspaceControllerProvider.notifier)
            .preparePath(
              path,
              expectedId: expectedId,
              expectedKind: expectedKind,
              acceptChanged: acceptChanged,
            );
        await container.read(notebookControllerProvider.notifier).flush();
        await container.read(readerControllerProvider.notifier).close();
        await container
            .read(workspaceControllerProvider.notifier)
            .activateWorkspace(workspace);
        if (workspace.isBook) {
          await _readerLocation(container, workspace.books.single.id);
        } else {
          container.read(appRouterProvider).go('/workspace');
        }
      });
    } on WorkspaceException catch (error) {
      if (context.mounted) await unavailableFile(context, ref, error);
    } catch (error) {
      if (context.mounted) await showError(context, error);
    }
  }
}

Future<void> openCollection(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(workspaceControllerProvider.notifier);
  await controller.refresh();
  if (!context.mounted) return;
  final collections = ref.read(workspaceControllerProvider).collections;
  final id = await showBusyBooksModalDialog<String>(
    context,
    builder: (c) => BusyBooksDialogShell(
      title: c.l10n.openCollection,
      actions: [
        BusyBooksDialogButton(
          label: c.l10n.cancel,
          onPressed: () => Navigator.pop(c),
        ),
      ],
      children: [
        if (collections.isEmpty) Text(c.l10n.noCollections),
        SizedBox(
          height: 360,
          child: ListView(
            children: [
              for (final collection in collections)
                BusyBooksActionRow(
                  title: collection['name'] as String,
                  subtitle: '${collection['count']} · ${c.l10n.books}',
                  leading: const Icon(BusyBooksGlyphs.folder),
                  onTap: () => Navigator.pop(c, collection['id'] as String),
                ),
            ],
          ),
        ),
      ],
    ),
  );
  if (id != null && context.mounted) await openCollectionId(context, ref, id);
}

Future<void> openCollectionId(
  BuildContext context,
  WidgetRef ref,
  String id, {
  bool Function()? canActivate,
  Future<bool> Function()? validateActivation,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  bool current() => context.mounted && (canActivate?.call() ?? true);
  Future<bool> valid() async =>
      current() &&
      (validateActivation == null || await validateActivation()) &&
      current();
  try {
    await container.read(workspaceControllerProvider.notifier).navigate(
      () async {
        if (!await valid()) return;
        await container.read(notebookControllerProvider.notifier).flush();
        if (!await valid()) return;
        await container.read(readerControllerProvider.notifier).close();
        if (!await valid()) return;
        await container
            .read(workspaceControllerProvider.notifier)
            .openCollection(id);
        if (!await valid()) return;
        container.read(appRouterProvider).go('/workspace');
      },
    );
  } catch (error) {
    if (context.mounted) await showError(context, error);
  }
}

Future<void> openRecent(
  BuildContext context,
  WidgetRef ref,
  RecentResource resource, {
  bool Function()? canActivate,
  Future<bool> Function()? validateActivation,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  if (!(canActivate?.call() ?? true) ||
      (validateActivation != null && !await validateActivation())) {
    return;
  }
  if (!context.mounted) return;
  if (!resource.isBook) {
    await openCollectionId(
      context,
      ref,
      resource.resourceId,
      canActivate: canActivate,
      validateActivation: validateActivation,
    );
    return;
  }
  final book = await container
      .read(workspaceControllerProvider.notifier)
      .loadBook(resource.resourceId);
  if (context.mounted && (canActivate?.call() ?? true)) {
    await openBook(
      context,
      ref,
      book,
      canActivate: canActivate,
      validateActivation: validateActivation,
    );
  }
}

Future<void> createCollection(BuildContext context, WidgetRef ref) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final name = await textPrompt(
    context,
    context.l10n.createCollection,
    help: context.l10n.createCollectionHelp,
  );
  if (name == null || name.trim().isEmpty || !context.mounted) return;
  try {
    await container.read(workspaceControllerProvider.notifier).navigate(
      () async {
        final controller = container.read(workspaceControllerProvider.notifier);
        final workspace = await controller.prepareCollection(name.trim());
        await container.read(notebookControllerProvider.notifier).flush();
        await container.read(readerControllerProvider.notifier).close();
        await controller.activateWorkspace(workspace);
        container.read(appRouterProvider).go('/workspace');
      },
    );
  } catch (error) {
    if (context.mounted) await showError(context, error);
  }
}

Future<void> renameCollection(BuildContext context, WidgetRef ref) async {
  final workspace = ref.read(workspaceControllerProvider).workspace;
  if (workspace == null) return;
  final name = await textPrompt(
    context,
    context.l10n.renameCollection,
    value: workspace.name,
  );
  if (name != null && name.trim().isNotEmpty && context.mounted) {
    await runAppAction(
      context,
      () => ref
          .read(workspaceControllerProvider.notifier)
          .renameCollection(workspace.id, name.trim()),
    );
  }
}

Future<void> deleteCollection(BuildContext context, WidgetRef ref) async {
  final workspace = ref.read(workspaceControllerProvider).workspace;
  if (workspace == null) return;
  if (await confirm(
        context,
        context.l10n.deleteCollection,
        context.l10n.deleteCollectionHelp,
        destructive: true,
      ) &&
      context.mounted) {
    await runAppAction(context, () async {
      await ref
          .read(workspaceControllerProvider.notifier)
          .deleteCollection(workspace.id);
      if (context.mounted) ref.read(appRouterProvider).go('/');
    });
  }
}

Future<void> addExistingBooks(BuildContext context, WidgetRef ref) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final files = await openFiles(acceptedTypeGroups: [bookFileTypes]);
  if (files.isEmpty || !context.mounted) return;
  try {
    final results = await container
        .read(workspaceControllerProvider.notifier)
        .addBooks(files.map((f) => f.path).toList());
    final failures = results.where((r) => r['status'] == 'failed');
    if (failures.isNotEmpty && context.mounted) {
      await showError(
        context,
        failures.map((r) => '${r['path']}\n${r['message']}').join('\n\n'),
      );
    }
  } catch (error) {
    if (context.mounted) await showError(context, error);
  }
}

Future<void> openBook(
  BuildContext context,
  WidgetRef ref,
  Book book, {
  bool Function()? canActivate,
  Future<bool> Function()? validateActivation,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final navigation = container.read(workspaceControllerProvider.notifier);
  bool current() => context.mounted && (canActivate?.call() ?? true);
  Future<bool> valid() async =>
      current() &&
      (validateActivation == null || await validateActivation()) &&
      current();
  if (!current()) return;
  if (!book.available && book.status != 'unverified') {
    await unavailableFile(
      context,
      ref,
      WorkspaceException(
        book.status,
        book.path,
        book.data['fileError']?.toString() ?? context.l10n.fileUnavailable,
        bookId: RegExp(r'^[a-f0-9]{64}$').hasMatch(book.id) ? book.id : null,
      ),
      entry: book,
    );
    return;
  }
  try {
    await navigation.navigate(() async {
      if (!await valid()) return;
      final controller = container.read(workspaceControllerProvider.notifier);
      final prepared = await controller.prepareBook(book);
      if (!await valid()) return;
      await container.read(notebookControllerProvider.notifier).flush();
      if (!await valid()) return;
      await container.read(readerControllerProvider.notifier).close();
      if (!await valid()) return;
      await controller.activateBook(prepared);
      if (!await valid()) return;
      await _readerLocation(container, prepared.id);
    });
  } on WorkspaceException catch (error) {
    if (context.mounted) {
      await unavailableFile(context, ref, error, entry: book);
    }
  } catch (error) {
    if (context.mounted) await showError(context, error);
  }
}

Future<void> locateBook(
  BuildContext context,
  WidgetRef ref,
  String id, {
  Book? entry,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final file = await openFile(
    acceptedTypeGroups: [bookFileTypes],
    confirmButtonText: context.l10n.locateBook,
  );
  if (file == null || !context.mounted) return;
  try {
    await container
        .read(workspaceControllerProvider.notifier)
        .relocate(id, file.path, entry: entry);
    final path = container
        .read(appRouterProvider)
        .routeInformationProvider
        .value
        .uri
        .path;
    if (path == '/read/$id') {
      await container.read(readerControllerProvider.notifier).close();
      await container.read(readerControllerProvider.notifier).open(id);
    }
    final target = rootNavigatorKey.currentState?.overlay?.context;
    if (target != null && target.mounted) {
      BusyBooksToastOverlay.show(target, message: target.l10n.locationUpdated);
    }
  } catch (error) {
    if (context.mounted) await showError(context, error);
  }
}

Future<void> moveBook(BuildContext context, WidgetRef ref, Book book) async {
  final destination = await getDirectoryPath(
    confirmButtonText: context.l10n.moveBook,
  );
  if (destination == null || !context.mounted) return;
  final target = p.join(destination, p.basename(book.path));
  if (!await confirm(
    context,
    context.l10n.moveBook,
    '${context.l10n.moveBookHelp}\n\n${book.path} → $target',
    acceptLabel: context.l10n.moveBook,
  )) {
    return;
  }
  if (context.mounted) await _performMove(context, ref, book, target);
}

Future<void> resumeMove(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> operation,
) async {
  await runAppAction(context, () async {
    final choice = await showBusyBooksModalDialog<String>(
      context,
      builder: (c) => BusyBooksDialogShell(
        title: c.l10n.pendingMove,
        actions: [
          BusyBooksDialogButton(
            label: c.l10n.cancel,
            onPressed: () => Navigator.pop(c),
          ),
          BusyBooksDialogButton(
            label: c.l10n.keepFiles,
            onPressed: () => Navigator.pop(c, 'keep'),
          ),
          BusyBooksDialogButton(
            label: c.l10n.retry,
            suggested: true,
            onPressed: () => Navigator.pop(c, 'retry'),
          ),
        ],
        children: [
          Text(c.l10n.moveRecoveryHelp),
          SelectableText(
            '${operation['source']} → ${operation['destination']}${operation['quarantine'] == null ? '' : '\n${operation['quarantine']}'}',
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'keep') {
      await ref
          .read(workspaceControllerProvider.notifier)
          .dismissMove(operation['id'] as String);
      return;
    }
    final book = await ref
        .read(workspaceControllerProvider.notifier)
        .loadBook(operation['bookId'] as String);
    if (context.mounted) {
      await _performMove(
        context,
        ref,
        book.copy({'path': operation['source']}),
        operation['destination'] as String,
      );
    }
  });
}

Future<void> _performMove(
  BuildContext context,
  WidgetRef ref,
  Book book,
  String target,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final route = container
      .read(appRouterProvider)
      .routeInformationProvider
      .value
      .uri
      .path;
  final reader = container.read(readerControllerProvider.notifier);
  final active = reader.stateBookId == book.id;
  await container.read(workspaceControllerProvider.notifier).navigate(() async {
    await container.read(notebookControllerProvider.notifier).flush();
    if (active) await reader.close();
    try {
      final moved = await container
          .read(workspaceControllerProvider.notifier)
          .moveBook(book, target);
      final feedback = rootNavigatorKey.currentState?.overlay?.context;
      if (feedback != null && feedback.mounted) {
        BusyBooksToastOverlay.show(
          feedback,
          message: moved.data['moveStatus'] == 'unchanged'
              ? feedback.l10n.moveUnchanged
              : feedback.l10n.moveComplete,
        );
      }
    } finally {
      if (active && route == '/read/${book.id}') await reader.open(book.id);
    }
  });
}

Future<void> unavailableFile(
  BuildContext context,
  WidgetRef ref,
  WorkspaceException error, {
  Book? entry,
}) async {
  final choice = await showBusyBooksModalDialog<String>(
    context,
    builder: (c) => BusyBooksDialogShell(
      title: error.code == 'changed'
          ? c.l10n.fileChanged
          : c.l10n.fileUnavailable,
      actions: [
        BusyBooksDialogButton(
          label: c.l10n.cancel,
          onPressed: () => Navigator.pop(c),
        ),
        if (error.bookId != null)
          BusyBooksDialogButton(
            label: c.l10n.locateBook,
            onPressed: () => Navigator.pop(c, 'locate'),
          ),
        if (error.bookId != null)
          BusyBooksDialogButton(
            label: c.l10n.notebook,
            onPressed: () => Navigator.pop(c, 'notebook'),
          ),
        if (error.code == 'changed')
          BusyBooksDialogButton(
            label: c.l10n.openChangedBook,
            onPressed: () => Navigator.pop(c, 'changed'),
          ),
      ],
      children: [
        Text(
          error.code == 'changed'
              ? c.l10n.fileChangedHelp
              : error.code == 'unsupported'
              ? c.l10n.unsupportedTarget
              : error.code == 'protected'
              ? c.l10n.protectedBookHelp
              : error.code == 'limit'
              ? c.l10n.bookResourceLimitHelp
              : error.code == 'damaged'
              ? c.l10n.damagedBookHelp
              : c.l10n.locateBookHelp,
        ),
        SelectableText(error.toString()),
      ],
    ),
  );
  if (!context.mounted) return;
  if (choice == 'locate') {
    await locateBook(context, ref, error.bookId!, entry: entry);
  }
  if (choice == 'notebook' && error.bookId != null && context.mounted) {
    await openNotebook(context, ref, error.bookId!);
  }
  if (choice == 'changed' && context.mounted) {
    await openPaths(context, ref, paths: [error.path], acceptChanged: true);
  }
}

Future<void> returnToWorkspace(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(workspaceControllerProvider.notifier);
  final container = ProviderScope.containerOf(context, listen: false);
  await runAppAction(
    context,
    () => controller.navigate(() async {
      await container.read(readerControllerProvider.notifier).flush();
      await container.read(narrationControllerProvider.notifier).stop();
      final workspace = container.read(workspaceControllerProvider).workspace;
      container
          .read(appRouterProvider)
          .go(workspace != null && !workspace.isBook ? '/workspace' : '/');
    }),
  );
}

Future<void> openSettings(
  BuildContext context,
  WidgetRef ref, {
  SettingsPage page = SettingsPage.general,
  bool bookPreferences = false,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final router = container.read(appRouterProvider);
  final origin = router.routeInformationProvider.value.uri;
  if (origin.path == '/settings') return;
  await runAppAction(
    context,
    () =>
        container.read(workspaceControllerProvider.notifier).navigate(() async {
          if (router.routeInformationProvider.value.uri != origin) return;
          await container.read(readerControllerProvider.notifier).flush();
          await container.read(narrationControllerProvider.notifier).stop();
          if (router.routeInformationProvider.value.uri != origin) return;
          router.go(
            Uri(
              path: '/settings',
              queryParameters: {
                'returnTo': safeSettingsReturnTarget(origin.path),
                'page': page.name,
                if (bookPreferences) 'scope': 'book',
              },
            ).toString(),
          );
        }),
  );
}

Future<void> closeWorkspace(BuildContext context, WidgetRef ref) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final navigation = ref.read(workspaceControllerProvider.notifier);
  try {
    await navigation.navigate(() async {
      await container.read(notebookControllerProvider.notifier).flush();
      await container.read(readerControllerProvider.notifier).close();
      await container
          .read(workspaceControllerProvider.notifier)
          .closeWorkspace();
      container.read(appRouterProvider).go('/');
    });
  } catch (error) {
    if (context.mounted) await showError(context, error);
  }
}

Future<void> exportBook(
  BuildContext context,
  WidgetRef ref,
  Book book, {
  bool original = false,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final container = ProviderScope.containerOf(context, listen: false);
  final store = container.read(readingDataStoreProvider);
  BuildContext? feedbackContext() =>
      navigator.mounted && navigator.overlay?.mounted == true
      ? navigator.overlay!.context
      : null;
  final path = await getSaveLocation(
    suggestedName: original
        ? '${book.title}.${book.originalSuffix}'
        : '${book.title}.md',
    acceptedTypeGroups: [
      XTypeGroup(
        label: original ? book.format : 'Markdown',
        extensions: [original ? book.originalSuffix : 'md'],
      ),
    ],
  );
  if (path == null) return;
  try {
    await container.read(readerControllerProvider.notifier).flush();
    await container.read(notebookControllerProvider.notifier).flush();
    await store.call(original ? 'exportOriginal' : 'exportMarkdown', {
      'id': book.id,
      'source': book.path,
      'path': path.path,
      'overwrite': true,
    });
    final target = feedbackContext();
    if (target != null && target.mounted) {
      BusyBooksToastOverlay.show(target, message: target.l10n.exportComplete);
    }
  } catch (e) {
    final target = feedbackContext();
    if (target != null && target.mounted) await showError(target, e);
  }
}

Future<void> backupReadingData(
  BuildContext context, {
  bool restore = false,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final navigator = Navigator.of(context, rootNavigator: true);
  // Restoration removes Settings. Its feedback belongs to the live window,
  // whose Navigator/overlay survives replacement of the initiating route.
  BuildContext? feedbackContext() =>
      navigator.mounted ? navigator.overlay?.context : null;
  try {
    if (restore) {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'BusyBooks Backup',
            extensions: ['busybooks'],
          ),
        ],
      );
      if (file == null || !context.mounted) return;
      if (!await confirm(
        context,
        context.l10n.restore,
        context.l10n.restoreWarning,
        acceptLabel: context.l10n.restore,
      )) {
        return;
      }
      await container.read(workspaceControllerProvider.notifier).navigate(
        () async {
          await container.read(appSettingsControllerProvider.notifier).flush();
          await container.read(notebookControllerProvider.notifier).flush();
          await container.read(readerControllerProvider.notifier).close();
          await container
              .read(workspaceControllerProvider.notifier)
              .closeWorkspace();
          container.read(appRouterProvider).go('/');
          final data =
              await container
                      .read(readingDataStoreProvider)
                      .call('restore', file.path)
                  as Map;
          await container
              .read(workspaceControllerProvider.notifier)
              .afterRestore();
          try {
            await container
                .read(appSettingsControllerProvider.notifier)
                .update(data.cast<String, dynamic>());
            await container
                .read(readingDataStoreProvider)
                .call('acknowledgePreferences');
          } catch (error) {
            final message =
                feedbackContext()?.l10n.restorePreferencesPending ??
                'Reading data was restored; preference replay is pending.';
            throw StateError('$message\n$error');
          }
        },
      );
      final target = feedbackContext();
      if (target != null && target.mounted) {
        BusyBooksToastOverlay.show(
          target,
          message: target.l10n.restoreComplete,
        );
      }
    } else {
      final file = await getSaveLocation(
        suggestedName: 'BusyBooks.busybooks',
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'BusyBooks Backup',
            extensions: ['busybooks'],
          ),
        ],
      );
      if (file == null) return;
      // The renderer acknowledgement can deliver a final note draft or setting.
      // Snapshot those primary-application edits after the native flush.
      await container.read(readerControllerProvider.notifier).flush();
      await container.read(notebookControllerProvider.notifier).flush();
      await container.read(appSettingsControllerProvider.notifier).flush();
      await container.read(readingDataStoreProvider).call('backup', {
        'path': file.path,
        'preferences': container.read(appSettingsControllerProvider).data,
        'overwrite': true,
      });
      final target = feedbackContext();
      if (target != null && target.mounted) {
        BusyBooksToastOverlay.show(target, message: target.l10n.backupComplete);
      }
    }
  } catch (e) {
    final target = feedbackContext();
    if (target != null && target.mounted) await showError(target, e);
  }
}

Future<void> externalLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !['https', 'http', 'mailto'].contains(uri.scheme)) return;
  if (await confirm(
    context,
    context.l10n.externalLink,
    '${context.l10n.externalWarning}\n\n$url',
  )) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

Future<void> dictionary(
  BuildContext context,
  WidgetRef ref, {
  ReaderSelectionTarget? target,
}) async {
  final reader = ref.read(readerControllerProvider.notifier);
  final selection = target ?? await reader.prepareLookup();
  if (!context.mounted) return;
  if (selection == null) {
    BusyBooksToastOverlay.show(context, message: context.l10n.selectText);
    return;
  }
  if (await confirm(
    context,
    context.l10n.lookUp,
    '${selection.text}\n\n${context.l10n.dictionarySource}',
    acceptLabel: context.l10n.lookUp,
  )) {
    if (context.mounted) await reader.lookup(selection);
  }
}

Future<void> openDictionaryEntry(String url) async {
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

Future<void> copySelection(WidgetRef ref) async {
  final text = ref
      .read(readerControllerProvider)
      .selection?['text']
      ?.toString();
  if (text != null) await Clipboard.setData(ClipboardData(text: text));
}

Future<void> bookProperties(
  BuildContext context,
  WidgetRef ref,
  Book book,
) async {
  final fields = {
    'title': TextEditingController(text: book.title),
    'author': TextEditingController(text: book.author),
    'series': TextEditingController(text: book.series),
    'seriesOrder': TextEditingController(
      text: book.seriesOrder == 0 ? '' : book.seriesOrder.toString(),
    ),
  };
  String? cover = book.cover;
  try {
    final result = await showBusyBooksModalDialog<bool>(
      context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => BusyBooksDialogShell(
          title: c.l10n.properties,
          actions: [
            BusyBooksDialogButton(
              label: c.l10n.cancel,
              onPressed: () => Navigator.pop(c, false),
            ),
            BusyBooksDialogButton(
              label: c.l10n.save,
              suggested: true,
              onPressed: () => Navigator.pop(c, true),
            ),
          ],
          children: [
            BusyBooksGroupedList(
              children: [
                for (final key in fields.keys)
                  BusyBooksGroupedTextEntry(
                    label: switch (key) {
                      'title' => c.l10n.title,
                      'author' => c.l10n.author,
                      'series' => c.l10n.series,
                      _ => c.l10n.seriesOrder,
                    },
                    controller: fields[key],
                  ),
                BusyBooksActionRow(
                  title: c.l10n.chooseCover,
                  onTap: () async {
                    final file = await openFile(
                      acceptedTypeGroups: [
                        const XTypeGroup(
                          label: 'Image',
                          extensions: ['png', 'jpg', 'jpeg', 'webp', 'svg'],
                        ),
                      ],
                    );
                    if (file == null) return;
                    try {
                      final value =
                          await ref
                                  .read(readingDataStoreProvider)
                                  .call('cover', file.path)
                              as String?;
                      if (!c.mounted) return;
                      if (value == null) {
                        throw FormatException(c.l10n.invalidCover);
                      }
                      if (c.mounted) setState(() => cover = value);
                    } catch (error) {
                      if (c.mounted) await showError(c, error);
                    }
                  },
                ),
                BusyBooksActionRow(
                  title: c.l10n.removeCover,
                  onTap: () => setState(() => cover = null),
                ),
                BusyBooksActionRow(
                  title: c.l10n.language,
                  subtitle: book.language,
                ),
                BusyBooksActionRow(
                  title: c.l10n.format,
                  subtitle: book.format.toUpperCase(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      await ref.read(workspaceControllerProvider.notifier).updateBook(book.id, {
        'title': fields['title']!.text.trim(),
        'author': fields['author']!.text.trim(),
        'series': fields['series']!.text.trim(),
        'seriesOrder': num.tryParse(fields['seriesOrder']!.text) ?? 0,
        'cover': cover,
        'coverEdited':
            cover != book.cover ||
            book.data['coverEdited'] == true ||
            (book.data['coverEdited'] == null &&
                book.data['metadataEdited'] == true),
        'metadataEdited': true,
      });
    }
  } finally {
    for (final field in fields.values) {
      field.dispose();
    }
  }
}
