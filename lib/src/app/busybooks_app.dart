import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_localizations/ubuntu_localizations.dart';
import '../../l10n/generated/app_localizations.dart';
import '../workspace/workspace_controller.dart';
import '../reading/application/reader_controller.dart';
import '../reading/application/narration_controller.dart';
import '../platform/gtk_animation_settings_service.dart';
import '../platform/speech_service.dart';
import 'app_router.dart';
import 'app_settings.dart';
import '../library/application/collection_view_controller.dart';
import 'app_theme.dart';
import 'app_locale.dart';
import 'busybooks_toast.dart';
import 'command_registry.dart';
import 'command_shortcuts.dart';
import 'command_palette.dart';
import 'keymap_controller.dart';
import 'shortcut_binding.dart';
import 'desktop_frame.dart';
import 'localization.dart';
import 'product_actions.dart';
import '../notebook/application/notebook_controller.dart';
import '../notebook/presentation/book_view_selector.dart';
import 'startup_path.dart';
import '../platform/gtk_header_icon_service.dart';
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
    bool reading() =>
        ref.read(readerControllerProvider).ready &&
        ref.read(readerControllerProvider).error == null &&
        ref
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path
            .startsWith('/read/');
    String? activeBook() => ref
        .read(appRouterProvider)
        .routeInformationProvider
        .value
        .uri
        .path
        .split('/')
        .last;
    bool bookView() => RegExp(r'^/(read|notebook)/').hasMatch(
      ref.read(appRouterProvider).routeInformationProvider.value.uri.path,
    );
    bool hasBook() =>
        bookView() &&
        ref.read(workspaceControllerProvider).bookById(activeBook()) != null;
    bool notebook() => ref
        .read(appRouterProvider)
        .routeInformationProvider
        .value
        .uri
        .path
        .startsWith('/notebook/');
    const sharedBookCommands = {
      BusyBooksCommandIds.viewReading,
      BusyBooksCommandIds.viewNotebook,
      BusyBooksCommandIds.moveBook,
      BusyBooksCommandIds.locateBook,
      BusyBooksCommandIds.export,
      BusyBooksCommandIds.search,
    };
    final actions = <String, BusyBooksCommandCallback>{
      BusyBooksCommandIds.viewReading: () =>
          openReading(context, ref, activeBook()!),
      BusyBooksCommandIds.viewNotebook: () =>
          openNotebook(context, ref, activeBook()!),
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
      BusyBooksCommandIds.outline: () => reader.panel('outline'),
      BusyBooksCommandIds.thumbnails: () => reader.panel('thumbnails'),
      BusyBooksCommandIds.readerBooks: () => reader.panel('books'),
      BusyBooksCommandIds.search: () async {
        if (notebook()) {
          final id = activeBook()!;
          final view = ref.read(notebookControllerProvider).view(id);
          ref
              .read(notebookControllerProvider.notifier)
              .view(id, searchVisible: !view.searchVisible, focus: true);
        } else {
          await reader.toggleSearch();
        }
      },
      BusyBooksCommandIds.searchCollection: () {
        final path = ref.read(workspaceControllerProvider).workspace?.id;
        if (path != null) {
          ref.read(collectionViewProvider(path).notifier).update(focus: true);
        }
      },
      BusyBooksCommandIds.sidebar: reader.toggleSidebar,
      BusyBooksCommandIds.goTo: () => reader.showPopover('goto'),
      BusyBooksCommandIds.backToCollection: () =>
          returnToWorkspace(context, ref),
      BusyBooksCommandIds.returnToPassage: () => reader.send('back'),
      BusyBooksCommandIds.nextResult: () => reader.stepMatch(1),
      BusyBooksCommandIds.previousResult: () => reader.stepMatch(-1),
      BusyBooksCommandIds.addNote: reader.addNote,
      BusyBooksCommandIds.annotations: () => reader.panel('annotations'),
      BusyBooksCommandIds.appearance: () => reader.showPopover(
        'appearance',
        anchor: reader.appearanceAnchor?.call(),
      ),
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
            notebook() ? c.l10n.searchNotebook : c.l10n.searchBook,
      },
      executions: {
        for (final entry in actions.entries)
          entry.key: () async {
            if (!ownsContext()) return;
            await runAppAction(context, entry.value);
          },
        BusyBooksCommandIds.commandPalette: () =>
            showCommandPalette(context, _registry(context)),
      },
      visible: {
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
        BusyBooksCommandIds.search: () =>
            notebook() || reading() && reader.textInteraction,
        BusyBooksCommandIds.readAloud: () =>
            reading() && reader.textInteraction,
        BusyBooksCommandIds.dictionary: () =>
            reading() && reader.textInteraction,
        BusyBooksCommandIds.highlight: () =>
            reading() && reader.textInteraction,
        BusyBooksCommandIds.thumbnails: () =>
            reading() && reader.panelAvailable('thumbnails'),
        BusyBooksCommandIds.readerBooks: () =>
            reading() && reader.panelAvailable('books'),
      },
      enabled: {
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
          BusyBooksCommandIds.viewReading,
          BusyBooksCommandIds.viewNotebook,
          BusyBooksCommandIds.moveBook,
          BusyBooksCommandIds.locateBook,
          BusyBooksCommandIds.export,
          BusyBooksCommandIds.search,
        ])
          id: () => hasBook(),
        BusyBooksCommandIds.thumbnails: () =>
            reading() && reader.panelAvailable('thumbnails'),
        BusyBooksCommandIds.readerBooks: () =>
            reading() && reader.panelAvailable('books'),
        BusyBooksCommandIds.search: () =>
            notebook() || reading() && reader.textInteraction,
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
            reading() && ref.read(readerControllerProvider).matches.isNotEmpty,
        BusyBooksCommandIds.previousResult: () =>
            reading() && ref.read(readerControllerProvider).matches.isNotEmpty,
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
      ref.read(readerControllerProvider.notifier).toggleSearch(visible: false);
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
            child: BusyBooksCommandShortcuts(
              shortcuts: registry.shortcutIntents(
                scopes: {
                  BusyBooksCommandScope.application,
                  if (router.routeInformationProvider.value.uri.path.startsWith(
                        '/read/',
                      ) ||
                      router.routeInformationProvider.value.uri.path.startsWith(
                        '/notebook/',
                      ))
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
                  child: BusyBooksToastOverlay(
                    child: desktopWindowHost(child ?? const SizedBox.shrink()),
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
