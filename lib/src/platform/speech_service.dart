import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart' hide Size;
import 'package:flutter/services.dart' hide Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../reading/application/narration_controller.dart';

const _channel = MethodChannel('io.busystack.busybooks/speech');

class SpeechServiceFailure implements Exception {
  const SpeechServiceFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class SpeechService {
  SpeechService() {
    if (Platform.isWindows) {
      _channel.setMethodCallHandler((call) async {
        if (!_disposed && call.method == 'event' && call.arguments is String) {
          events.add(call.arguments as String);
        }
      });
    }
  }
  bool _windowsUsed = false, _disposed = false;
  SendPort? _port;
  Future<void>? _starting;
  Isolate? _isolate;
  ReceivePort? _replies;
  Future<void>? _disposal;
  int _serial = 0;
  final _pending = <int, Completer<dynamic>>{};
  final events = StreamController<String>.broadcast();
  Future<dynamic> call(
    String action, [
    Map<String, dynamic> args = const {},
  ]) async {
    if (_disposed) throw const SpeechServiceFailure('Speech service is closed');
    return _call(action, args);
  }

  Future<dynamic> _call(
    String action, [
    Map<String, dynamic> args = const {},
  ]) async {
    if (Platform.isWindows) {
      _windowsUsed = true;
      try {
        return await _channel.invokeMethod(action, args);
      } on PlatformException catch (error) {
        throw SpeechServiceFailure(error.message ?? error.code);
      }
    }
    if (_port == null) {
      _starting ??= _start().whenComplete(() => _starting = null);
      await _starting;
    }
    final id = ++_serial, c = Completer<dynamic>();
    _pending[id] = c;
    _port!.send([id, action, args]);
    return c.future;
  }

  Future<void> _start() async {
    final ready = ReceivePort(), replies = ReceivePort();
    _replies = replies;
    try {
      _isolate = await Isolate.spawn(_speechWorker, [
        ready.sendPort,
        replies.sendPort,
      ]);
      final value = await ready.first;
      if (value is String) throw SpeechServiceFailure(value);
      _port = value as SendPort;
      replies.listen((dynamic message) {
        final m = message as List;
        if (m[0] == 0) {
          if (!_disposed) events.add(m[1] as String);
          return;
        }
        final completer = _pending.remove(m[0]);
        if (m[1] == true) {
          completer?.complete(m[2]);
        } else {
          completer?.completeError(m[2]);
        }
      });
    } catch (_) {
      replies.close();
      _replies = null;
      _isolate?.kill();
      _isolate = null;
      rethrow;
    } finally {
      ready.close();
    }
  }

  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    try {
      if (_starting != null) {
        try {
          await _starting;
        } on SpeechServiceFailure {
          // Startup already reports its unavailable service to the caller.
        }
      }
      if (_port != null || Platform.isWindows && _windowsUsed) {
        try {
          await _call('stop');
        } on SpeechServiceFailure catch (error) {
          debugPrint('Speech stop during disposal failed: $error');
        } finally {
          if (_port != null) await _call('close');
        }
      }
    } finally {
      if (Platform.isWindows) _channel.setMethodCallHandler(null);
      _port = null;
      _isolate?.kill();
      _isolate = null;
      _replies?.close();
      _replies = null;
      for (final pending in _pending.values) {
        pending.completeError(
          const SpeechServiceFailure('Speech service is closed'),
        );
      }
      _pending.clear();
      await events.close();
    }
  }
}

final speechServiceProvider = Provider<SpeechService>((ref) {
  final service = SpeechService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

typedef _SpeechCallback = Void Function(Size, Size, Int32);

final class _ConnectionPrefix extends Struct {
  external Pointer<NativeFunction<_SpeechCallback>> begin;
  external Pointer<NativeFunction<_SpeechCallback>> end;
  external Pointer<NativeFunction<_SpeechCallback>> cancel;
  external Pointer<NativeFunction<_SpeechCallback>> pause;
  external Pointer<NativeFunction<_SpeechCallback>> resume;
  external Pointer<Void> index;
}

final class _Voice extends Struct {
  external Pointer<Utf8> name;
  external Pointer<Utf8> language;
  external Pointer<Utf8> variant;
}

Future<void> _speechWorker(List<SendPort> ports) async {
  final commands = ReceivePort(), ready = ports[0], reply = ports[1];
  try {
    final lib = DynamicLibrary.open('libspeechd.so.2');
    final open = lib
        .lookupFunction<
          Pointer<_ConnectionPrefix> Function(
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Int32,
          ),
          Pointer<_ConnectionPrefix> Function(
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            int,
          )
        >('spd_open');
    final client = 'busybooks'.toNativeUtf8(), name = 'reader'.toNativeUtf8();
    final connection = open(client, name, nullptr, 1);
    malloc.free(client);
    malloc.free(name);
    if (connection == nullptr) {
      throw StateError(
        'Speech Dispatcher is unavailable. Install speech-dispatcher and an offline voice (for example speech-dispatcher-espeak-ng), then start the service.',
      );
    }
    int activeMessage = -1;
    final notifications = NativeCallable<_SpeechCallback>.listener((
      int message,
      int client,
      int state,
    ) {
      if (message != activeMessage) return;
      reply.send([
        0,
        switch (state) {
          0 => 'playing',
          1 => 'stopped',
          3 => 'stopped',
          4 => 'paused',
          5 => 'playing',
          _ => 'playing',
        },
      ]);
    });
    connection.ref.begin = notifications.nativeFunction;
    connection.ref.end = notifications.nativeFunction;
    connection.ref.cancel = notifications.nativeFunction;
    connection.ref.pause = notifications.nativeFunction;
    connection.ref.resume = notifications.nativeFunction;
    final notification = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>, Int32),
          int Function(Pointer<Void>, int)
        >('spd_set_notification_on');
    notification(connection.cast(), 63);
    int unary(String symbol) =>
        lib.lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >(symbol)(connection.cast());
    void check(int result) {
      if (result < 0) {
        throw const SpeechServiceFailure(
          'Speech Dispatcher rejected the request',
        );
      }
    }

    ready.send(commands.sendPort);
    await for (final dynamic message in commands) {
      final m = message as List,
          id = m[0] as int,
          action = m[1] as String,
          args = m[2] as Map;
      try {
        dynamic value;
        switch (action) {
          case 'voices':
            final list = lib
                .lookupFunction<
                  Pointer<Pointer<_Voice>> Function(Pointer<Void>),
                  Pointer<Pointer<_Voice>> Function(Pointer<Void>)
                >('spd_list_synthesis_voices')(connection.cast());
            final voices = <String>[];
            if (list != nullptr) {
              for (var i = 0; i < 1000 && list[i] != nullptr; i++) {
                voices.add(list[i].ref.name.toDartString());
              }
              lib.lookupFunction<
                Void Function(Pointer<Pointer<_Voice>>),
                void Function(Pointer<Pointer<_Voice>>)
              >('free_spd_voices')(list);
            }
            value = voices;
          case 'speak':
            check(unary('spd_cancel'));
            final voice = (args['voice'] as String? ?? '').toNativeUtf8(),
                text = (args['text'] as String).toNativeUtf8();
            try {
              if (args['voice'] != '' && args['voice'] != null) {
                check(
                  lib.lookupFunction<
                    Int32 Function(Pointer<Void>, Pointer<Utf8>),
                    int Function(Pointer<Void>, Pointer<Utf8>)
                  >('spd_set_synthesis_voice')(connection.cast(), voice),
                );
              }
              check(
                lib.lookupFunction<
                  Int32 Function(Pointer<Void>, Int32),
                  int Function(Pointer<Void>, int)
                >('spd_set_voice_rate')(
                  connection.cast(),
                  (((args['speed'] as num? ?? 1) - 1) * 100).round().clamp(
                    -100,
                    100,
                  ),
                ),
              );
              activeMessage = lib
                  .lookupFunction<
                    Int32 Function(Pointer<Void>, Int32, Pointer<Utf8>),
                    int Function(Pointer<Void>, int, Pointer<Utf8>)
                  >('spd_say')(connection.cast(), 3, text);
              check(activeMessage);
            } finally {
              malloc.free(voice);
              malloc.free(text);
            }
          case 'pause':
            check(unary('spd_pause'));
          case 'resume':
            check(unary('spd_resume'));
          case 'stop':
            check(unary('spd_cancel'));
          case 'close':
            lib.lookupFunction<
              Void Function(Pointer<Void>),
              void Function(Pointer<Void>)
            >('spd_close')(connection.cast());
            notifications.close();
            reply.send([id, true, null]);
            commands.close();
            return;
          default:
            throw ArgumentError(action);
        }
        reply.send([id, true, value]);
      } catch (e) {
        reply.send([id, false, e]);
      }
    }
  } catch (e) {
    ready.send(e.toString());
    commands.close();
  }
}

Future<void> showReadAloud(BuildContext context, WidgetRef ref) =>
    ref.read(narrationControllerProvider.notifier).start();
