import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'busybooks_design.dart';
import 'busybooks_glyphs.dart';
import 'localization.dart';
import 'linux/linux_window_host.dart';
import '../platform/gtk_window_preferences_service.dart';

class WindowsWindowHost extends StatefulWidget {
  const WindowsWindowHost({super.key, required this.child});
  final Widget child;
  @override
  State<WindowsWindowHost> createState() => _WindowsWindowHostState();
}

class _WindowsWindowHostState extends State<WindowsWindowHost>
    with WindowListener {
  bool active = true, maximized = false, fullscreen = false;
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowFocus() => setState(() => active = true);
  @override
  void onWindowBlur() => setState(() => active = false);
  @override
  void onWindowMaximize() => setState(() => maximized = true);
  @override
  void onWindowUnmaximize() => setState(() => maximized = false);
  @override
  void onWindowEnterFullScreen() => setState(() => fullscreen = true);
  @override
  void onWindowLeaveFullScreen() => setState(() => fullscreen = false);
  @override
  Widget build(BuildContext context) => LinuxWindowMetricsScope(
    leftControlInset: 0,
    rightControlInset: fullscreen ? 0 : 124,
    windowActive: active,
    platform: TargetPlatform.windows,
    preferences: GtkWindowPreferences.defaults(),
    child: Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (!fullscreen)
          Positioned(
            top: 0,
            right: 8,
            height: BusyBooksSizes.toolbarHeight,
            child: Row(
              children: [
                BusyBooksHeaderIconButton(
                  tooltip: context.l10n.windowMinimize,
                  icon: BusyBooksGlyphs.hide,
                  onPressed: () => windowManager.minimize(),
                ),
                BusyBooksHeaderIconButton(
                  tooltip: maximized
                      ? context.l10n.windowRestore
                      : context.l10n.windowMaximize,
                  icon: BusyBooksGlyphs.fullScreen,
                  onPressed: () => maximized
                      ? windowManager.unmaximize()
                      : windowManager.maximize(),
                ),
                BusyBooksHeaderIconButton(
                  tooltip: context.l10n.windowClose,
                  icon: BusyBooksGlyphs.close,
                  onPressed: () => windowManager.close(),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

Widget desktopWindowHost(Widget child) => Platform.isLinux
    ? LinuxWindowHost(child: child)
    : WindowsWindowHost(child: child);
