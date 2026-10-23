import 'dart:async';
import 'package:busybooks/src/app/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements LocalSettingsStore {
  final values = <Map<String, dynamic>>[];
  final gate = Completer<void>();
  @override
  Future<Map<String, dynamic>> load() async => {'theme': 'dark'};
  @override
  Future<void> save(Map<String, dynamic> json) async {
    if (values.isEmpty) {
      values.add({...json});
      await gate.future;
    } else {
      values.add({...json});
    }
  }
}

void main() {
  test(
    'reading defaults save failures revert only their own optimistic revision',
    () async {
      final store = _Store(),
          container = ProviderContainer(
            overrides: [
              startupAppSettingsProvider.overrideWithValue(
                StartupAppSettings(AppSettings(), store),
              ),
            ],
          );
      addTearDown(container.dispose);
      final controller = container.read(appSettingsControllerProvider.notifier);
      final operation = controller.updateReadingDefaults('reading', {
        ...defaultReadingAppearance,
        'font': {'family': 'Named'},
        'publisher': false,
      });
      expect(container.read(appSettingsControllerProvider).reading['font'], {
        'family': 'Named',
      });
      final error = expectLater(operation, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      store.gate.completeError(StateError('Fixture save failure'));
      await error;
      expect(
        container.read(appSettingsControllerProvider).reading['font'],
        'serif',
      );
      await controller.updateReadingDefaults('reading', {
        ...defaultReadingAppearance,
        'font': {'family': 'Named'},
        'publisher': false,
      });
      expect(container.read(appSettingsControllerProvider).reading['font'], {
        'family': 'Named',
      });
    },
  );
  test(
    'saved appearance is available on first provider read and writes serialize',
    () async {
      final store = _Store(),
          initial = await StartupAppSettings.load(store),
          container = ProviderContainer(
            overrides: [startupAppSettingsProvider.overrideWithValue(initial)],
          );
      addTearDown(container.dispose);
      expect(
        container.read(appSettingsControllerProvider).themeMode,
        ThemeMode.dark,
      );
      final controller = container.read(appSettingsControllerProvider.notifier);
      final one = controller.update({'theme': 'light'}),
          two = controller.update({'grid': false});
      await Future<void>.delayed(Duration.zero);
      expect(store.values, hasLength(1));
      store.gate.complete();
      await Future.wait([one, two]);
      expect(store.values.last['theme'], 'light');
      expect(store.values.last['grid'], false);
    },
  );
}
