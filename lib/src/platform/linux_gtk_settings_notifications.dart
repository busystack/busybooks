import 'package:yaru/settings.dart';

YaruSettings? _settings;

/// Own the official GTK settings notification consumer for the primary engine.
///
/// YaruSettings constructs GtkSettings, which installs the gtk/settings method
/// handler and responds to native notifications. Without that consumer, a
/// buffered notification retains its native response task and Flutter engine.
/// Keep one consumer for this Dart engine's lifetime, including bootstrap
/// retries. Do not call init(): no GSettings subscriptions or theme changes are
/// needed to receive and acknowledge the GTK notifications.
YaruSettings initializeLinuxGtkSettingsNotifications() =>
    _settings ??= YaruSettings();
