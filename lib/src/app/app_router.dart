import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../library/presentation/collection_screen.dart';
import '../workspace/presentation/welcome_screen.dart';
import '../reading/presentation/reader_screen.dart';
import '../reading/application/reader_controller.dart';
import 'settings_screen.dart';
import '../notebook/presentation/notebook_screen.dart';

/// Only existing internal surfaces can be Settings return destinations.
String safeSettingsReturnTarget(String? target) =>
    target == '/' ||
        target == '/workspace' ||
        target != null &&
            RegExp(r'^/(read|notebook)/[a-f0-9]{64}$').hasMatch(target)
    ? target!
    : '/';

final rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'BusyBooks root navigator',
);

class _ReaderRouteObserver extends NavigatorObserver {
  _ReaderRouteObserver(this.reader);
  final ReaderController reader;
  @override
  void didChangeTop(
    Route<dynamic> topRoute,
    Route<dynamic>? previousTopRoute,
  ) => unawaited(reader.show(topRoute.settings.name == 'reader'));
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
          key: s.pageKey,
          name: 'reader',
          child: ReaderScreen(id: s.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/notebook/:id',
        pageBuilder: (c, s) => NoTransitionPage<void>(
          key: s.pageKey,
          name: 'notebook',
          child: NotebookScreen(
            key: ValueKey(s.pathParameters['id']),
            id: s.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (c, s) => NoTransitionPage<void>(
          key: s.pageKey,
          name: 'settings',
          child: const SettingsScreen(),
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
