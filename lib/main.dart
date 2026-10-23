import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import 'package:yaru/yaru.dart';
import 'src/app/app_settings.dart';
import 'src/reading/presentation/reader_popover.dart';
import 'src/app/busybooks_app.dart';
import 'src/app/startup_path.dart';
import 'src/app/startup_failure.dart';
import 'src/app/system_accent.dart';
import 'src/workspace/workspace_controller.dart';
import 'src/library/data/library_store.dart';
import 'src/platform/app_directories.dart';
import 'src/platform/windows_appearance_service.dart';
import 'src/platform/gtk_animation_settings_service.dart';
import 'src/platform/gtk_header_icon_service.dart';
import 'src/platform/gtk_window_preferences_service.dart';
import 'src/platform/linux_gtk_accent_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.length == 1 && args.single == '--busybooks-reader-popover') {
    runApp(const ProviderScope(child: ReaderPopoverApp()));
    return;
  }
  try {
    await _bootstrap(args);
  } catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
    runApp(BusyBooksStartupFailure(error: error, retry: () => main(args)));
  }
}

Future<void> _bootstrap(List<String> args) async {
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(640, 560));
  if (Platform.isLinux) await YaruWindow.ensureInitialized();
  final directory = await busyBooksDataDirectory();
  final settingsStore = JsonFileLocalSettingsStore(
    p.join(directory.path, 'settings.json'),
  );
  final store = await ReadingDataStore.open(directory.path);
  var presented = false;
  try {
    final pendingPreferences = await store.call('pendingPreferences');
    if (pendingPreferences is Map) {
      await settingsStore.save(pendingPreferences.cast<String, dynamic>());
      await store.call('acknowledgePreferences');
    }
    final settings = await StartupAppSettings.load(settingsStore);
    final accent = LinuxAccentCoordinator(
      sources: Platform.isLinux
          ? [const LinuxGtkAccentService(), const LinuxPortalAppearance()]
          : [],
    );
    await accent.initialize();
    final windowsAppearance = WindowsAppearanceService();
    if (Platform.isWindows) await windowsAppearance.initialize();
    final chrome = Platform.isLinux
        ? await Future.wait<Object?>([
            const GtkAnimationSettingsService().getAnimationsEnabled(),
            const GtkWindowPreferencesService().load(),
          ])
        : [null, null];
    final icons = GtkHeaderIconService();
    if (Platform.isLinux) await icons.initialize();
    if (Platform.isWindows) {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
    }
    runApp(
      ProviderScope(
        overrides: [
          startupAppSettingsProvider.overrideWithValue(settings),
          readingDataStoreProvider.overrideWithValue(store),
          startupPathsProvider.overrideWithValue(
            args.where((x) => !x.startsWith('--')).toList(),
          ),
          initialGtkAnimationsEnabledProvider.overrideWithValue(
            chrome[0] as bool?,
          ),
          initialGtkWindowPreferencesProvider.overrideWithValue(
            chrome[1] as GtkWindowPreferences?,
          ),
          gtkHeaderIconServiceProvider.overrideWith((ref) {
            ref.onDispose(icons.dispose);
            return icons;
          }),
          initialSystemAccentColorProvider.overrideWithValue(
            Platform.isWindows ? windowsAppearance.color : accent.color,
          ),
          if (Platform.isWindows)
            systemAccentColorProvider.overrideWith((ref) {
              ref.onDispose(() => unawaited(windowsAppearance.dispose()));
              return windowsAppearance.colors;
            }),
          linuxAccentCoordinatorProvider.overrideWith((ref) {
            ref.onDispose(() => unawaited(accent.dispose()));
            return accent;
          }),
        ],
        child: const BusyBooksApp(),
      ),
    );
    presented = true;
  } finally {
    if (!presented) await store.close();
  }
}
