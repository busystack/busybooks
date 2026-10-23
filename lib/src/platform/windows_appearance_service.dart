import 'dart:async';
import 'package:flutter/services.dart';

class WindowsAppearanceService {
  static const channel = MethodChannel('io.busystack.busybooks/desktop');
  final _changes = StreamController<Color>.broadcast();
  late Color color;
  Stream<Color> get colors async* {
    yield color;
    yield* _changes.stream;
  }

  Future<void> initialize() async {
    final value = await channel.invokeMethod<int>('getAccent');
    if (value == null) {
      throw StateError('Windows accent integration returned no color');
    }
    color = Color(value);
    channel.setMethodCallHandler((call) async {
      if (call.method == 'accentChanged' && call.arguments is int) {
        color = Color(call.arguments as int);
        _changes.add(color);
      }
    });
  }

  Future<void> dispose() async {
    channel.setMethodCallHandler(null);
    await _changes.close();
  }
}
