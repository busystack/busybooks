import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_settings.dart';
import '../../platform/speech_service.dart';
import 'reader_controller.dart';

class NarrationState {
  const NarrationState({
    this.status = 'stopped',
    this.text = '',
    this.error,
    this.voices = const [],
  });
  final String status, text;
  final String? error;
  final List<String> voices;
  bool get active =>
      status == 'playing' || status == 'paused' || status == 'loading';
}

/// Owns speech independently of transient UI and stops it before a book changes.
class NarrationController extends Notifier<NarrationState> {
  StreamSubscription<String>? _subscription;
  int _revision = 0;
  bool _speaking = false, _continuous = false;
  Map<String, dynamic>? _passage;
  @override
  NarrationState build() {
    _subscription = ref.read(speechServiceProvider).events.stream.listen((
      status,
    ) {
      if (!state.active) return;
      if (status == 'stopped' &&
          _continuous &&
          state.status == 'playing' &&
          ref.read(readerControllerProvider).canSpeakNext) {
        _speaking = false;
        unawaited(_advance());
        return;
      }
      if (status == 'playing' && state.status == 'paused') return;
      state = NarrationState(
        status: status,
        text: state.text,
        voices: state.voices,
      );
      if (status == 'stopped') {
        _speaking = false;
        unawaited(
          ref.read(readerControllerProvider.notifier).send('speaking', {
            'anchor': null,
          }),
        );
      }
    });
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    return const NarrationState();
  }

  Future<void> start({
    Map<String, dynamic>? passage,
    bool continueReading = false,
  }) async {
    final revision = ++_revision;
    final reader = ref.read(readerControllerProvider.notifier);
    try {
      state = NarrationState(
        status: 'loading',
        text: state.text,
        voices: state.voices,
      );
      if (passage == null) {
        final response = reader.events.stream
            .firstWhere(
              (e) => e['type'] == 'passage' && e['request'] == revision,
            )
            .timeout(const Duration(seconds: 5));
        await reader.send('passage', {'request': revision});
        passage = await response;
        continueReading = passage['selected'] != true;
      }
      if (revision != _revision) return;
      final text = passage['text']?.toString() ?? '';
      if (text.trim().isEmpty) {
        state = const NarrationState(error: 'no-text');
        return;
      }
      final voices =
          (await ref.read(speechServiceProvider).call('voices') as List)
              .cast<String>()
              .toSet()
              .toList();
      if (revision != _revision) return;
      _passage = passage;
      _continuous = continueReading;
      final settings = ref.read(appSettingsControllerProvider).data;
      _speaking = true;
      await ref.read(speechServiceProvider).call('speak', {
        'text': text,
        'voice': voices.contains(settings['voice']) ? settings['voice'] : '',
        'speed': settings['speed'],
      });
      if (revision != _revision) {
        await ref.read(speechServiceProvider).call('stop');
        return;
      }
      state = NarrationState(status: 'playing', text: text, voices: voices);
      await reader.send('speaking', {'anchor': passage['anchor']});
    } catch (error) {
      if (revision == _revision) {
        state = NarrationState(error: error.toString());
      }
    }
  }

  Future<void> _advance() async {
    final revision = _revision,
        reader = ref.read(readerControllerProvider.notifier);
    state = NarrationState(
      status: 'loading',
      text: state.text,
      voices: state.voices,
    );
    try {
      final response = reader.events.stream
          .firstWhere((e) => e['type'] == 'passage' && e['request'] == revision)
          .timeout(const Duration(seconds: 15));
      await reader.send('advanceSpeech', {'request': revision});
      final passage = await response;
      if (revision == _revision) {
        await start(passage: passage, continueReading: true);
      }
    } catch (error) {
      if (revision == _revision) {
        state = NarrationState(error: error.toString());
      }
    }
  }

  Future<void> pauseResume() async {
    try {
      final paused = state.status == 'paused';
      await ref.read(speechServiceProvider).call(paused ? 'resume' : 'pause');
      state = NarrationState(
        status: paused ? 'playing' : 'paused',
        text: state.text,
        voices: state.voices,
      );
    } catch (error) {
      state = NarrationState(error: error.toString());
    }
  }

  Future<void> stop() async {
    ++_revision;
    _continuous = false;
    if (!state.active && !_speaking) {
      state = const NarrationState();
      _passage = null;
      return;
    }
    await ref.read(speechServiceProvider).call('stop');
    _speaking = false;
    state = const NarrationState();
    await ref.read(readerControllerProvider.notifier).send('speaking', {
      'anchor': null,
    });
    _passage = null;
  }

  Future<void> configure({String? voice, num? speed}) async {
    await ref.read(appSettingsControllerProvider.notifier).update({
      if (voice != null) 'voice': voice,
      if (speed != null) 'speed': speed,
    });
    if (state.active && _passage != null) {
      final paused = state.status == 'paused';
      await start(passage: _passage, continueReading: _continuous);
      if (paused && state.status == 'playing') await pauseResume();
    }
    await options();
  }

  Future<void> options() async {
    final settings = ref.read(appSettingsControllerProvider).data;
    await ref
        .read(readerControllerProvider.notifier)
        .showPopover(
          'speech',
          extra: {
            'voices': ['', ...state.voices],
            'voice': state.voices.contains(settings['voice'])
                ? settings['voice']
                : '',
            'speed': settings['speed'],
          },
        );
  }
}

final narrationControllerProvider =
    NotifierProvider<NarrationController, NarrationState>(
      NarrationController.new,
    );
