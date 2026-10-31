import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_localizations/ubuntu_localizations.dart';

import '../../l10n/generated/app_localizations.dart';
import '../book_workspace/application/book_presentation.dart';
import '../book_workspace/application/book_sidebar_controller.dart';
import '../notebook/application/notebook_controller.dart';
import '../notebook/presentation/book_view_selector.dart';
import '../platform/gtk_animation_settings_service.dart';
import '../platform/gtk_header_icon_service.dart';
import '../platform/speech_service.dart';
import '../reading/application/narration_controller.dart';
import '../reading/application/reader_controller.dart';
import '../reading/presentation/appearance_menu.dart';
import '../search/book_search_session.dart';
import '../search/book_search_widgets.dart';
import '../workspace/workspace_controller.dart';
import 'app_locale.dart';
import 'app_router.dart';
import 'app_settings.dart';
import 'app_theme.dart';
import 'busybooks_toast.dart';
import 'busybooks_modal_surface.dart';
import 'busybooks_search_field.dart';
import 'command_registry.dart';
import 'command_shortcuts.dart';
import 'desktop_frame.dart';
import 'keymap_controller.dart';
import 'localization.dart';
import 'product_actions.dart';
import 'settings_page.dart';
import 'shortcut_binding.dart';
import 'startup_path.dart';
import 'system_accent.dart';
import 'window_control_service.dart';

class BusyBooksApp extends ConsumerStatefulWidget {
  const BusyBooksApp({super.key});
  @override
  ConsumerState<BusyBooksApp> createState() => _BusyBooksAppState();
}

class _BusyBooksAppState extends ConsumerState<BusyBooksApp> {
  final _input = const MethodChannel('com.busybooks.app/asset_input');
  StreamSubscription<Map<String, dynamic>>? _events;
  bool startup = false;
  bool _goingHome = false;

  Future<void> _goHome(BuildContext context) async {
    if (_goingHome) return;
    _goingHome = true;
    try {
      await closeWorkspace(context, ref);
    } finally {
      _goingHome = false;
    }
  }

  late final WindowControlService _windowControls;
  @override
  void initState() {
    super.initState();
    final window = ref.read(windowControlServiceProvider);
    _windowControls = window;
    unawaited(window.initialize());
    window.registerCloseHandler(() async {
      try {
        await ref.read(workspaceControllerProvider.notifier).navigate(() async {
          await ref.read(narrationControllerProvider.notifier).stop();
          await ref.read(notebookControllerProvider.notifier).flush();
          await ref.read(readerControllerProvider.notifier).close();
          await ref.read(appSettingsControllerProvider.notifier).flush();
          await ref.read(speechServiceProvider).dispose();
          await ref.read(readingDataStoreProvider).close();
          await window.closeWindow();
        });
      } catch (e) {
        final context = rootNavigatorKey.currentContext;
        if (context != null && context.mounted) await showError(context, e);
      }
    });
    _input.setMethodCallHandler((call) async {
      if (call.method == 'assetFilesDropped' || call.method == 'filesOpened') {
        final paths = (call.arguments as List).cast<String>();
        final context = rootNavigatorKey.currentContext;
        if (context != null && context.mounted) {
          await openPaths(context, ref, paths: paths);
        }
      }
    });
    if (Platform.isWindows || Platform.isLinux) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_input.invokeMethod<void>('ready'));
      });
    }
    _events = ref.read(readerControllerProvider.notifier).events.stream.listen((
      event,
    ) {
      if (event['type'] == 'key') unawaited(_nativeKey(event));
      if (event['type'] == 'readingSettings') {
        final context = rootNavigatorKey.currentContext;
        if (context != null && context.mounted) {
          unawaited(
            openSettings(
              context,
              ref,
              page: SettingsPage.reading,
              bookPreferences: true,
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _input.setMethodCallHandler(null);
    unawaited(_events?.cancel());
    _windowControls.unregisterCloseHandler();
    super.dispose();
  }

  BusyBooksCommandRegistry _registry(BuildContext context) {
    context = rootNavigatorKey.currentState?.overlay?.context ?? context;
    final reader = ref.read(readerControllerProvider.notifier);
    final origin = ref
        .read(appRouterProvider)
        .routeInformationProvider
        .value
        .uri;
    final workspaceId = ref.read(workspaceControllerProvider).workspace?.id;
    bool ownsContext() =>
        ref.read(appRouterProvider).routeInformationProvider.value.uri ==
            origin &&
        ref.read(workspaceControllerProvider).workspace?.id == workspaceId;
    String routePath() =>
        ref.read(appRouterProvider).routeInformationProvider.value.uri.path;
    BookView? activeView() => bookViewForRoute(routePath());
    String? activeBook() => bookIdForRoute(routePath());
    bool reading() {
      final state = ref.read(readerControllerProvider);
      return activeView()?.hasReader == true &&
          state.surfaceVisible &&
          state.ready &&
          state.error == null &&
          reader.stateBookId == activeBook();
    }

    bool bookView() => activeView() != null;
    bool hasBook() =>
        bookView() &&
        ref.read(workspaceControllerProvider).bookById(activeBook()) != null;
    bool notebook() => activeView() == BookView.notebook;
    bool notebookFocused() {
      final view = activeView();
      final presentation = ref.read(bookPresentationProvider);
      return view == BookView.notebook ||
          view == BookView.split &&
              presentation.bookId == activeBook() &&
              presentation.lastPane == BookPane.notebook;
    }

    BookSearchScope defaultScope(BookSearchCategory category) {
      final data = ref.read(workspaceControllerProvider);
      if (bookView() && category != BookSearchCategory.books) {
        final book = data.bookById(activeBook());
        return BookSearchScope(
          BookSearchScopeKind.thisBook,
          id: book?.id,
          name: book?.title ?? '',
        );
      }
      final collection = data.workspace;
      if (collection != null &&
          !collection.isBook &&
          origin.path != '/' &&
          origin.path != '/settings') {
        return BookSearchScope(
          BookSearchScopeKind.currentCollection,
          id: collection.id,
          name: collection.name,
        );
      }
      return const BookSearchScope.all();
    }

    const sharedBookCommands = {
      BusyBooksCommandIds.viewReading,
      BusyBooksCommandIds.viewNotebook,
      BusyBooksCommandIds.viewSplit,
      BusyBooksCommandIds.bookProperties,
      BusyBooksCommandIds.moveBook,
      BusyBooksCommandIds.locateBook,
      BusyBooksCommandIds.export,
      BusyBooksCommandIds.search,
      BusyBooksCommandIds.sidebar,
      BusyBooksCommandIds.outline,
      BusyBooksCommandIds.thumbnails,
      BusyBooksCommandIds.readerBooks,
      BusyBooksCommandIds.annotations,
      BusyBooksCommandIds.nextResult,
      BusyBooksCommandIds.previousResult,
    };
    final actions = <String, BusyBooksCommandCallback>{
      BusyBooksCommandIds.viewReading: () =>
          openReading(context, ref, activeBook()!, view: BookView.reading),
      BusyBooksCommandIds.viewNotebook: () =>
          openNotebook(context, ref, activeBook()!, view: BookView.notebook),
      BusyBooksCommandIds.viewSplit: () =>
          openReading(context, ref, activeBook()!, view: BookView.split),
      BusyBooksCommandIds.bookProperties: () async {
        final book = ref
            .read(workspaceControllerProvider)
            .bookById(activeBook());
        if (book != null) await bookProperties(context, ref, book);
      },
      BusyBooksCommandIds.moveBook: () async {
        final book = ref
            .read(workspaceControllerProvider)
            .bookById(activeBook());
        if (book != null) await moveBook(context, ref, book);
      },
      BusyBooksCommandIds.locateBook: () =>
          locateBook(context, ref, activeBook()!),
      BusyBooksCommandIds.open: () => openPaths(context, ref),
      BusyBooksCommandIds.openCollection: () => openCollection(context, ref),
      BusyBooksCommandIds.createCollection: () =>
          createCollection(context, ref),
      BusyBooksCommandIds.addBooks: () => addExistingBooks(context, ref),
      BusyBooksCommandIds.closeWorkspace: () => _goHome(context),
      BusyBooksCommandIds.refreshWorkspace: () =>
          ref.read(workspaceControllerProvider.notifier).refreshWorkspace(),
      BusyBooksCommandIds.welcome: () => _goHome(context),
      BusyBooksCommandIds.settings: () => openSettings(context, ref),
      BusyBooksCommandIds.fullScreen: () =>
          ref.read(windowControlServiceProvider).toggleFullScreen(),
      BusyBooksCommandIds.outline: () async {
        ref.read(bookSearchSessionProvider.notifier).close(restoreFocus: false);
        await ref
            .read(bookSidebarProvider(activeBook()!).notifier)
            .selectPanel(BookSidebarPanel.outline);
      },
      BusyBooksCommandIds.thumbnails: () async {
        ref.read(bookSearchSessionProvider.notifier).close(restoreFocus: false);
        await ref
            .read(bookSidebarProvider(activeBook()!).notifier)
            .selectPanel(BookSidebarPanel.thumbnails);
      },
      BusyBooksCommandIds.readerBooks: () async {
        ref.read(bookSearchSessionProvider.notifier).close(restoreFocus: false);
        await ref
            .read(bookSidebarProvider(activeBook()!).notifier)
            .selectPanel(BookSidebarPanel.books);
      },
      BusyBooksCommandIds.search: () async {
        final search = ref.read(bookSearchSessionProvider.notifier);
        await search.open(
          category: notebookFocused()
              ? BookSearchCategory.notebook
              : BookSearchCategory.bookText,
          scope: defaultScope(
            notebookFocused()
                ? BookSearchCategory.notebook
                : BookSearchCategory.bookText,
          ),
          actions: bookSearchActions(context, _registry(context)),
        );
      },
      BusyBooksCommandIds.searchCollection: () => ref
          .read(bookSearchSessionProvider.notifier)
          .open(
            category: BookSearchCategory.books,
            scope: defaultScope(BookSearchCategory.books),
            actions: bookSearchActions(context, _registry(context)),
          ),
      for (final MapEntry(key: command, value: category)
          in searchCategoryCommands.entries)
        command: () => ref
            .read(bookSearchSessionProvider.notifier)
            .open(
              category: category,
              scope: defaultScope(category),
              actions: bookSearchActions(context, _registry(context)),
            ),
      BusyBooksCommandIds.sidebar: () async {
        final search = ref.read(bookSearchSessionProvider.notifier);
        if (ref.read(bookSearchSessionProvider).active) {
          search.close();
        } else {
          await ref
              .read(bookSidebarProvider(activeBook()!).notifier)
              .toggleOpen();
        }
      },
      BusyBooksCommandIds.backToCollection: () =>
          returnToWorkspace(context, ref),
      BusyBooksCommandIds.returnToPassage: () => reader.send('back'),
      BusyBooksCommandIds.nextResult: () =>
          _activateSearchStep(context, activeBook()!, 1),
      BusyBooksCommandIds.previousResult: () =>
          _activateSearchStep(context, activeBook()!, -1),
      BusyBooksCommandIds.addNote: reader.addNote,
      BusyBooksCommandIds.annotations: () async {
        ref.read(bookSearchSessionProvider.notifier).close(restoreFocus: false);
        await ref
            .read(bookSidebarProvider(activeBook()!).notifier)
            .selectPanel(BookSidebarPanel.marks);
      },
      BusyBooksCommandIds.appearance: () =>
          showReadingAppearanceMenu(context, reader, isCurrent: ownsContext),
      BusyBooksCommandIds.bookmark: () => reader.annotation('bookmark'),
      BusyBooksCommandIds.highlight: () => reader.annotation('highlight'),
      BusyBooksCommandIds.dictionary: () => dictionary(context, ref),
      BusyBooksCommandIds.readAloud: () => showReadAloud(context, ref),
      BusyBooksCommandIds.next: () => reader.send('next'),
      BusyBooksCommandIds.previous: () => reader.send('previous'),
      BusyBooksCommandIds.back: () => reader.send('back'),
      BusyBooksCommandIds.forward: () => reader.send('forward'),
      BusyBooksCommandIds.export: () => exportBook(
        context,
        ref,
        ref.read(workspaceControllerProvider).bookById(activeBook())!,
      ),
    };
    final defaults = BusyBooksCommandCatalog.create(
      labels: {
        BusyBooksCommandIds.searchCollection: (c) =>
            c.l10n.collectionSearchScope,
        BusyBooksCommandIds.bookmark: (c) =>
            reader.bookmarked ? c.l10n.removeBookmark : c.l10n.bookmark,
        BusyBooksCommandIds.appearance: (c) =>
            ref.read(readerControllerProvider).fixed
            ? c.l10n.viewOptions
            : c.l10n.appearance,
        BusyBooksCommandIds.search: (c) =>
            notebookFocused() ? c.l10n.searchNotebook : c.l10n.searchBook,
      },
      disabledReasons: {
        BusyBooksCommandIds.viewSplit: (c) {
          final presentation = ref.read(bookPresentationProvider);
          return hasBook() && !presentation.splitAvailable
              ? c.l10n.splitMinimumWidth(
                  presentation.splitMetrics.minimumWidth.ceil(),
                )
              : null;
        },
      },
      executions: {
        for (final entry in actions.entries)
          entry.key: () async {
            if (!ownsContext()) return;
            await runAppAction(context, entry.value);
          },
        BusyBooksCommandIds.commandPalette: () async {
          await ref
              .read(bookSearchSessionProvider.notifier)
              .open(
                category: BookSearchCategory.actions,
                actions: bookSearchActions(context, _registry(context)),
              );
        },
      },
      visible: {
        for (final MapEntry(key: id, value: category)
            in searchCategoryCommands.entries)
          id: () => ref
              .read(bookSearchSessionProvider.notifier)
              .categories
              .contains(category),
        BusyBooksCommandIds.searchCollection: () =>
            ref
                .read(appRouterProvider)
                .routeInformationProvider
                .value
                .uri
                .path ==
            '/workspace',

        BusyBooksCommandIds.backToCollection: () =>
            bookView() &&
            ref.read(workspaceControllerProvider).workspace?.isBook == false,
        BusyBooksCommandIds.addBooks: () =>
            ref.read(workspaceControllerProvider).workspace?.editable == true,
        for (final c in BusyBooksCommandCatalog.metadata.commands)
          if (c.scope == BusyBooksCommandScope.documentView)
            c.id: () =>
                bookView() &&
                (!notebook() || sharedBookCommands.contains(c.id)),
        BusyBooksCommandIds.search: () => hasBook(),
        BusyBooksCommandIds.readAloud: () =>
            reading() && reader.textInteraction,
        BusyBooksCommandIds.dictionary: () =>
            reading() && reader.textInteraction,
        BusyBooksCommandIds.highlight: () =>
            reading() && reader.textInteraction,
        BusyBooksCommandIds.thumbnails: () =>
            hasBook() &&
            ref
                .read(bookSidebarProvider(activeBook()!).notifier)
                .available(BookSidebarPanel.thumbnails),
        BusyBooksCommandIds.readerBooks: () =>
            hasBook() &&
            ref
                .read(bookSidebarProvider(activeBook()!).notifier)
                .available(BookSidebarPanel.books),
      },
      enabled: {
        for (final MapEntry(key: id, value: category)
            in searchCategoryCommands.entries)
          id: () => ref
              .read(bookSearchSessionProvider.notifier)
              .categories
              .contains(category),
        BusyBooksCommandIds.settings: () =>
            ref
                .read(appRouterProvider)
                .routeInformationProvider
                .value
                .uri
                .path !=
            '/settings',

        BusyBooksCommandIds.searchCollection: () =>
            ref
                .read(appRouterProvider)
                .routeInformationProvider
                .value
                .uri
                .path ==
            '/workspace',
        BusyBooksCommandIds.addBooks: () =>
            ref.read(workspaceControllerProvider).workspace?.editable == true &&
            !ref.read(workspaceControllerProvider).loading,
        BusyBooksCommandIds.closeWorkspace: () =>
            ref.read(workspaceControllerProvider).workspace != null,
        BusyBooksCommandIds.refreshWorkspace: () =>
            ref.read(workspaceControllerProvider).workspace?.isBook == false &&
            !ref.read(workspaceControllerProvider).loading,
        for (final c in BusyBooksCommandCatalog.metadata.commands)
          if (c.scope == BusyBooksCommandScope.documentView)
            c.id: () => reading(),
        for (final id in [
          BusyBooksCommandIds.sidebar,
          BusyBooksCommandIds.outline,
          BusyBooksCommandIds.annotations,
          BusyBooksCommandIds.viewReading,
          BusyBooksCommandIds.viewNotebook,
          BusyBooksCommandIds.viewSplit,
          BusyBooksCommandIds.bookProperties,
          BusyBooksCommandIds.moveBook,
          BusyBooksCommandIds.locateBook,
          BusyBooksCommandIds.export,
          BusyBooksCommandIds.search,
        ])
          id: () => hasBook(),
        BusyBooksCommandIds.viewSplit: () =>
            hasBook() && ref.read(bookPresentationProvider).splitAvailable,
        BusyBooksCommandIds.thumbnails: () =>
            hasBook() &&
            ref
                .read(bookSidebarProvider(activeBook()!).notifier)
                .available(BookSidebarPanel.thumbnails),
        BusyBooksCommandIds.readerBooks: () =>
            hasBook() &&
            ref
                .read(bookSidebarProvider(activeBook()!).notifier)
                .available(BookSidebarPanel.books),
        BusyBooksCommandIds.search: () => hasBook(),
        BusyBooksCommandIds.readAloud: () =>
            reading() &&
            reader.textInteraction &&
            ref.read(readerControllerProvider).location['noText'] != true,
        BusyBooksCommandIds.backToCollection: () =>
            bookView() &&
            ref.read(workspaceControllerProvider).workspace?.isBook == false,
        BusyBooksCommandIds.returnToPassage: () =>
            reading() && ref.read(readerControllerProvider).canBack,
        BusyBooksCommandIds.back: () =>
            reading() && ref.read(readerControllerProvider).canBack,
        BusyBooksCommandIds.forward: () =>
            reading() && ref.read(readerControllerProvider).canForward,
        BusyBooksCommandIds.next: () =>
            reading() && ref.read(readerControllerProvider).canNext,
        BusyBooksCommandIds.previous: () =>
            reading() && ref.read(readerControllerProvider).canPrevious,
        BusyBooksCommandIds.bookmark: () => reading() && reader.canBookmark,
        BusyBooksCommandIds.addNote: () =>
            reading() &&
            (reader.regionNotes ||
                ref.read(readerControllerProvider).selection != null),
        BusyBooksCommandIds.nextResult: () =>
            hasBook() &&
            ref.read(bookSearchSessionProvider).active &&
            ref.read(bookSearchSessionProvider).category ==
                BookSearchCategory.bookText &&
            ref.read(bookSearchSessionProvider).query.isNotEmpty,
        BusyBooksCommandIds.previousResult: () =>
            hasBook() &&
            ref.read(bookSearchSessionProvider).active &&
            ref.read(bookSearchSessionProvider).category ==
                BookSearchCategory.bookText &&
            ref.read(bookSearchSessionProvider).query.isNotEmpty,
        BusyBooksCommandIds.highlight: () =>
            reading() &&
            reader.textInteraction &&
            ref.read(readerControllerProvider).selection != null,
        BusyBooksCommandIds.dictionary: () =>
            reading() &&
            reader.textInteraction &&
            ref.read(readerControllerProvider).selection != null,
      },
    );
    return effectiveCommandRegistry(
      defaults,
      ref.read(appSettingsControllerProvider).shortcutOverrides,
    );
  }

  Future<void> _activateSearchStep(
    BuildContext context,
    String bookId,
    int delta,
  ) async {
    final controller = ref.read(bookSearchSessionProvider.notifier);
    if (!await controller.selectOccurrence(delta) || !context.mounted) return;
    final result = controller.selectedResult;
    if (result != null) {
      await activateBookSearchResult(
        context,
        ref,
        result,
        ref.read(bookSearchSessionProvider).generation,
      );
    }
  }

  Future<void> _nativeKey(Map<String, dynamic> e) async {
    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final key = e['key'] as String;
    final logical = switch (key) {
      'ArrowLeft' => LogicalKeyboardKey.arrowLeft,
      'ArrowRight' => LogicalKeyboardKey.arrowRight,
      'PageDown' => LogicalKeyboardKey.pageDown,
      'PageUp' => LogicalKeyboardKey.pageUp,
      'F11' => LogicalKeyboardKey.f11,
      'F9' => LogicalKeyboardKey.f9,
      'Escape' => LogicalKeyboardKey.escape,
      _ when RegExp(r'^F(?:[1-9]|1[0-9]|2[0-4])$').hasMatch(key) =>
        LogicalKeyboardKey.findKeyByKeyId(
          LogicalKeyboardKey.f1.keyId + int.parse(key.substring(1)) - 1,
        ),
      _ =>
        key.length == 1
            ? LogicalKeyboardKey(key.toLowerCase().codeUnitAt(0))
            : null,
    };
    if (logical == null) return;
    final binding = BusyBooksKeyBinding(
          logical,
          control: e['control'] == true,
          shift: e['shift'] == true,
          alt: e['alt'] == true,
          meta: e['meta'] == true,
        ),
        registry = _registry(context);
    if (key == 'Escape') {
      ref.read(bookSearchSessionProvider.notifier).close();
      return;
    }
    final command = registry.commandForNativeBinding(binding);
    if (command != null) await registry.execute(command.id);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLocationProvider);
    final settings = ref.watch(appSettingsControllerProvider),
        router = ref.watch(appRouterProvider);
    ref.watch(readerControllerProvider);
    ref.watch(bookPresentationProvider);
    ref.watch(workspaceControllerProvider);
    final accent =
        ref.watch(systemAccentColorProvider).asData?.value ??
        ref.watch(initialSystemAccentColorProvider) ??
        busyBooksDefaultAccentColor;
    final animations = ref.watch(gtkAnimationsEnabledProvider).asData?.value;
    return MaterialApp.router(
      title: 'BusyBooks',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: buildBusyBooksTheme(
        brightness: Brightness.light,
        accentColor: accent,
      ),
      darkTheme: buildBusyBooksTheme(
        brightness: Brightness.dark,
        accentColor: accent,
      ),
      themeMode: settings.themeMode,
      locale: settings.data['locale'] is String
          ? Locale(settings.data['locale'] as String)
          : null,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: resolveBusyBooksLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        UbuntuLocalizations.delegate,
      ],
      builder: (context, child) {
        if (!startup) {
          startup = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final paths = ref.read(startupPathsProvider);
            if (paths.isNotEmpty) {
              await ref.read(workspaceControllerProvider.notifier).refresh();
              final target = rootNavigatorKey.currentState?.overlay?.context;
              if (target != null && target.mounted) {
                await openPaths(target, ref, paths: paths);
              }
            }
            if (ref.read(startupAppSettingsProvider).error != null &&
                context.mounted) {
              await showError(
                rootNavigatorKey.currentContext!,
                context.l10n.appDataError,
              );
            }
          });
        }
        final registry = _registry(context);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations:
                MediaQuery.disableAnimationsOf(context) || animations == false,
          ),
          child: BusyBooksCommandRegistryScope(
            registry: registry,
            child: Focus(
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape &&
                    !busyBooksTextInputComposing() &&
                    ref.read(bookSearchSessionProvider).active) {
                  ref.read(bookSearchSessionProvider.notifier).close();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: BusyBooksCommandShortcuts(
                shortcuts: registry.shortcutIntents(
                  scopes: {
                    BusyBooksCommandScope.application,
                    if (bookViewForRoute(
                          router.routeInformationProvider.value.uri.path,
                        ) !=
                        null)
                      BusyBooksCommandScope.documentView,
                  },
                  intentFor: BusyBooksCommandIntent.new,
                ),
                child: Actions(
                  actions: {
                    BusyBooksCommandIntent:
                        CallbackAction<BusyBooksCommandIntent>(
                          onInvoke: (intent) {
                            unawaited(
                              registry.execute(intent.commandId).catchError((
                                Object e,
                              ) {
                                if (context.mounted) {
                                  unawaited(
                                    showError(
                                      rootNavigatorKey.currentContext!,
                                      e,
                                    ),
                                  );
                                }
                                return false;
                              }),
                            );
                            return null;
                          },
                        ),
                  },
                  child: GtkHeaderIconScope(
                    service: ref.watch(gtkHeaderIconServiceProvider),
                    child: BusyBooksModalSurfaceScope(
                      cover: ref
                          .read(readerControllerProvider.notifier)
                          .coverForModal,
                      child: BusyBooksToastOverlay(
                        child: desktopWindowHost(
                          child ?? const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
