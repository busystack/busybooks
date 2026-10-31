import 'dart:async';

import 'package:busybooks/src/platform/linux_gtk_settings_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('gtk/settings');

Future<ByteData?> _nativeCall(String method, [Object? arguments]) {
  final response = Completer<ByteData?>();
  ServicesBinding.instance.channelBuffers.push(
    _channel.name,
    _channel.codec.encodeMethodCall(MethodCall(method, arguments)),
    response.complete,
  );
  return response.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'owns one official GTK notification consumer across bootstrap retries',
    () async {
      final buffered = _nativeCall('notify', 'gtk-theme-name');
      final first = initializeLinuxGtkSettingsNotifications();
      expect(initializeLinuxGtkSettingsNotifications(), same(first));

      // Execute GtkSettings' real public-factory handler, with no replacement
      // dispatcher, GSettings initialization, GTK property reads, or widget theme.
      final response = await buffered;
      expect(response, isNotNull);
      expect(_channel.codec.decodeEnvelope(response!), isNull);

      expect(initializeLinuxGtkSettingsNotifications(), same(first));
      final next = await _nativeCall(
        'notify',
        'gtk-application-prefer-dark-theme',
      );
      expect(next, isNotNull);
      expect(_channel.codec.decodeEnvelope(next!), isNull);
    },
  );

  test(
    'official GTK consumer preserves unimplemented method responses',
    () async {
      initializeLinuxGtkSettingsNotifications();
      expect(await _nativeCall('unsupported-method'), isNull);
    },
  );
}
