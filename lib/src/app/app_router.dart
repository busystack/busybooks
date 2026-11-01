import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../book_workspace/application/book_presentation.dart';
import '../book_workspace/presentation/book_workspace_screen.dart';
import '../library/presentation/collection_screen.dart';
import '../reading/application/reader_controller.dart';
import '../workspace/presentation/welcome_screen.dart';
import 'settings_page.dart';
import 'settings_screen.dart';

/// Only existing internal surfaces can be Settings return destinations.
String safeSettingsReturnTarget(String? target) =>
    target == '/' ||
        target == '/workspace' ||
        target != null &&
            RegExp(r'^/(read|notebook|split)/[a-f0-9]{64}$').hasMatch(target)
    ? target!
    : '/';

final rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'BusyBooks root navigator',
);

class _ReaderRouteObserver extends NavigatorObserver {
  _ReaderRouteObserver(this.reader);
  final ReaderController reader;
  int _revision = 0;

  Future<void> _showTop(bool visible, int revision) async {
    if (!visible) {
      await reader.show(false);
      return;
    }
    // Retained geometry belongs to the previous allocation. ReadingContent
    // measures the current visible pane after show requests a fresh viewport.
    final hidden = reader.setWorkspaceVisible(false);
    if (revision != _revision) {
      await hidden;
      return;
    }
    // Restore route intent before a dismissed dialog's continuation runs.
    // Native pixels remain fenced by the invalidated viewport acknowledgement.
    final shown = reader.show(true);
    await Future.wait<void>([hidden, shown]);
  }

  final _routes = <Route<dynamic>>[];
  bool? _pageVisible;
  void _sync() {
    final page = _routes.whereType<PageRoute<dynamic>>().lastOrNull;
    final visible =
        page?.settings.name == 'reader' || page?.settings.name == 'split';
    if (visible == _pageVisible) return;
    _pageVisible = visible;
    unawaited(_showTop(visible, ++_revision));
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    _sync();
  }

  @override
  void didChangeTop(
    Route<dynamic> topRoute,
    Route<dynamic>? previousTopRoute,
  ) => _sync();
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    observers: [
      _ReaderRouteObserver(ref.read(readerControllerProvider.notifier)),
    ],
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (c, s) => NoTransitionPage<void>(
          key: s.pageKey,
          name: 'welcome',
          child: const WelcomeScreen(),
        ),
      ),
      GoRoute(
        path: '/workspace',
        pageBuilder: (c, s) => NoTransitionPage<void>(
          key: s.pageKey,
          name: 'workspace',
          child: const CollectionScreen(),
        ),
      ),
      GoRoute(
        path: '/read/:id',
        pageBuilder: (c, s) => NoTransitionPage<void>(
          key: const ValueKey('book-workspace'),
          name: 'reader',
          child: BookWorkspaceScreen(
            id: s.pathParameters['id']!,
            view: BookView.reading,
          ),
        ),
      ),
      GoRoute(
        path: '/notebook/:id',
        pageBuilder: (c, s) => NoTransitionPage<void>(
          key: const ValueKey('book-workspace'),
          name: 'notebook',
          child: BookWorkspaceScreen(
            id: s.pathParameters['id']!,
            view: BookView.notebook,
          ),
        ),
      ),
      GoRoute(
        path: '/split/:id',
        pageBuilder: (c, s) => NoTransitionPage<void>(
          key: const ValueKey('book-workspace'),
          name: 'split',
          child: BookWorkspaceScreen(
            id: s.pathParameters['id']!,
            view: BookView.split,
          ),
        ),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (c, s) => NoTransitionPage<void>(
          key: s.pageKey,
          name: 'settings',
          child: SettingsScreen(
            bookPreferences: s.uri.queryParameters['scope'] == 'book',
            initialPage:
                SettingsPage.values
                    .where((page) => page.name == s.uri.queryParameters['page'])
                    .firstOrNull ??
                SettingsPage.general,
          ),
        ),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

final appLocationProvider = StreamProvider<Uri>((ref) async* {
  final source = ref.watch(appRouterProvider).routeInformationProvider,
      changes = StreamController<Uri>();
  void update() => changes.add(source.value.uri);
  source.addListener(update);
  ref.onDispose(() {
    source.removeListener(update);
    unawaited(changes.close());
  });
  yield source.value.uri;
  yield* changes.stream;
});
