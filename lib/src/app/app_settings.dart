// Ordered settings persistence and startup handoff adapted from BusyMark.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/atomic_file_writer.dart';
import 'shortcut_binding.dart';
import '../core/reading_preferences.dart';
export '../core/reading_preferences.dart' show defaultReadingAppearance;

class AppSettings {
  AppSettings([Map<String, dynamic>? value])
    : data = normalizeAppPreferences(value ?? {});
  final Map<String, dynamic> data;
  static const defaults = busyBooksSettingsDefaults;
  ThemeMode get themeMode => switch (data['theme']) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
  Map<String, dynamic> get reading => {
    ...defaultReadingAppearance,
    ...(data['reading'] as Map? ?? {}).cast<String, dynamic>(),
  };
  Map<String, BusyBooksKeyBinding?> get shortcutOverrides => {
    for (final e in (data['shortcuts'] as Map? ?? {}).entries)
      e.key.toString(): e.value == null
          ? null
          : BusyBooksKeyBinding.fromJson(e.value),
  };
  AppSettings copy(Map<String, dynamic> changes) =>
      AppSettings({...data, ...changes});
}

abstract class LocalSettingsStore {
  Future<Map<String, dynamic>> load();
  Future<void> save(Map<String, dynamic> json);
}

class JsonFileLocalSettingsStore implements LocalSettingsStore {
  JsonFileLocalSettingsStore(this.path);
  final String path;
  bool _damaged = false;
  @override
  Future<Map<String, dynamic>> load() async {
    final file = File(path);
    if (!await file.exists()) return {};
    if (await file.length() > 4 * 1024 * 1024) {
      throw const FormatException('Settings exceed resource limit');
    }
    try {
      return (jsonDecode(await file.readAsString()) as Map)
          .cast<String, dynamic>();
    } catch (_) {
      _damaged = true;
      rethrow;
    }
  }

  @override
  Future<void> save(Map<String, dynamic> json) async {
    await File(path).parent.create(recursive: true);
    if (_damaged && await File(path).exists()) {
      await File(
        path,
      ).copy('$path.damaged-${DateTime.now().microsecondsSinceEpoch}');
      _damaged = false;
    }
    await const AtomicFileWriter().writeBytes(
      path,
      utf8.encode(const JsonEncoder.withIndent('  ').convert(json)),
      overwrite: true,
    );
  }
}

class StartupAppSettings {
  StartupAppSettings(this.settings, this.store, [this.error]);
  final AppSettings settings;
  final LocalSettingsStore store;
  final Object? error;
  static Future<StartupAppSettings> load(LocalSettingsStore store) async {
    try {
      return StartupAppSettings(AppSettings(await store.load()), store);
    } catch (e) {
      return StartupAppSettings(AppSettings(), store, e);
    }
  }
}

final startupAppSettingsProvider = Provider<StartupAppSettings>(
  (ref) => throw StateError('Startup settings were not injected'),
);
final localSettingsStoreProvider = Provider<LocalSettingsStore>(
  (ref) => ref.read(startupAppSettingsProvider).store,
);

class AppSettingsController extends Notifier<AppSettings> {
  Future<void> _tail = Future.value();
  Object? _saveError;
  @override
  AppSettings build() => ref.read(startupAppSettingsProvider).settings;
  Future<void> waitUntilLoaded() => Future.value();
  Future<void> update(Map<String, dynamic> changes) {
    state = state.copy(changes);
    final snapshot = state.data;
    final save = _tail.then(
      (_) => ref.read(localSettingsStoreProvider).save(snapshot),
    );
    _tail = save
        .then<void>((_) {
          _saveError = null;
        })
        .catchError((Object error) {
          _saveError = error;
        });
    return save;
  }

  Future<void> updateReadingDefaults(
    String key,
    Map<String, dynamic> appearance,
  ) async {
    if (key != 'reading' && key != 'pdfReading' && key != 'comicReading') {
      throw ArgumentError.value(key);
    }
    final before = state;
    final operation = update({key: normalizeReadingAppearance(appearance)});
    final snapshot = state;
    try {
      await operation;
    } catch (_) {
      if (ref.mounted && identical(state, snapshot)) state = before;
      rethrow;
    }
  }

  Future<bool> saveShortcutOverrides(
    Map<String, BusyBooksKeyBinding?> value,
  ) async {
    try {
      await update({
        'shortcuts': {for (final e in value.entries) e.key: e.value?.toJson()},
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> retryShortcutSave() async {
    try {
      await update({});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> flush() async {
    await _tail;
    if (_saveError != null) {
      await update({});
    }
  }
}

final appSettingsControllerProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );

class ShortcutPersistenceOutcome extends Notifier<bool?> {
  @override
  bool? build() => null;
}

final shortcutPersistenceOutcomeProvider =
    NotifierProvider<ShortcutPersistenceOutcome, bool?>(
      ShortcutPersistenceOutcome.new,
    );
