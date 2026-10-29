// Adapted from BusyMark (BusyStack, Apache-2.0); modified for BusyBooks.
import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import 'busybooks_design.dart';
import 'busybooks_glyphs.dart';

/// Controls how a toast is ordered when another toast is already visible.
enum BusyBooksToastPriority { normal, high }

/// Hosts native-looking, window-level feedback for short-lived app events.
///
/// The presentation follows the GNOME/Libadwaita toast pattern: one compact,
/// user-dismissible message is overlaid at the bottom center of the window.
class BusyBooksToastOverlay extends StatefulWidget {
  const BusyBooksToastOverlay({super.key, required this.child});

  final Widget child;

  static void show(
    BuildContext context, {
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 5),
    BusyBooksToastPriority priority = BusyBooksToastPriority.normal,
  }) {
    final host = context
        .dependOnInheritedWidgetOfExactType<_BusyBooksToastScope>()
        ?._state;
    host?._show(
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
      priority: priority,
    );
  }

  @override
  State<BusyBooksToastOverlay> createState() => _BusyBooksToastOverlayState();
}

class _BusyBooksToastOverlayState extends State<BusyBooksToastOverlay> {
  static const _transitionDuration = Duration(milliseconds: 180);

  final _pending = ListQueue<_BusyBooksToast>();
  _BusyBooksToast? _active;
  Timer? _dismissTimer;
  Timer? _nextToastTimer;
  var _nextId = 0;

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _nextToastTimer?.cancel();
    super.dispose();
  }

  void _show({
    required String message,
    required String? actionLabel,
    required VoidCallback? onAction,
    required Duration duration,
    required BusyBooksToastPriority priority,
  }) {
    final normalizedMessage = message.trim();
    if (normalizedMessage.isEmpty || !mounted) {
      return;
    }
    final toast = _BusyBooksToast(
      id: _nextId++,
      message: normalizedMessage,
      actionLabel: actionLabel?.trim(),
      onAction: onAction,
      duration: duration,
      priority: priority,
    );
    final active = _active;
    if (active == null) {
      _activate(toast);
      return;
    }
    if (active.matches(toast)) {
      setState(() => _active = toast);
      _startDismissTimer(toast);
      return;
    }
    if (priority == BusyBooksToastPriority.high) {
      _pending.addFirst(toast);
    } else {
      _pending.addLast(toast);
    }
  }

  void _activate(_BusyBooksToast toast) {
    _nextToastTimer?.cancel();
    setState(() => _active = toast);
    _startDismissTimer(toast);
  }

  void _startDismissTimer(_BusyBooksToast toast) {
    _dismissTimer?.cancel();
    if (toast.duration <= Duration.zero) {
      return;
    }
    _dismissTimer = Timer(toast.duration, () => _dismiss(toast.id));
  }

  void _dismiss(int id) {
    if (!mounted || _active?.id != id) {
      return;
    }
    _dismissTimer?.cancel();
    setState(() => _active = null);
    _nextToastTimer?.cancel();
    _nextToastTimer = Timer(_transitionDuration, _showNext);
  }

  void _showNext() {
    if (!mounted || _active != null || _pending.isEmpty) {
      return;
    }
    _activate(_pending.removeFirst());
  }

  void _invokeAction(_BusyBooksToast toast) {
    toast.onAction?.call();
    _dismiss(toast.id);
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    return Overlay.wrap(
      child: _BusyBooksToastScope(
        state: this,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            Positioned(
              left: BusyBooksSpacing.lg,
              right: BusyBooksSpacing.lg,
              bottom: BusyBooksSpacing.lg,
              child: SafeArea(
                top: false,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  heightFactor: 1,
                  child: AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : _transitionDuration,
                    reverseDuration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : _transitionDuration,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.15),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: active == null
                        ? const SizedBox.shrink()
                        : _BusyBooksToastSurface(
                            key: ValueKey(active.id),
                            toast: active,
                            onAction: () => _invokeAction(active),
                            onDismiss: () => _dismiss(active.id),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusyBooksToastScope extends InheritedWidget {
  const _BusyBooksToastScope({required this.state, required super.child});

  final _BusyBooksToastOverlayState state;

  _BusyBooksToastOverlayState get _state => state;

  @override
  bool updateShouldNotify(_BusyBooksToastScope oldWidget) => false;
}

@immutable
class _BusyBooksToast {
  const _BusyBooksToast({
    required this.id,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.duration,
    required this.priority,
  });

  final int id;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final BusyBooksToastPriority priority;

  bool matches(_BusyBooksToast other) =>
      message == other.message && actionLabel == other.actionLabel;
}

class _BusyBooksToastSurface extends StatelessWidget {
  const _BusyBooksToastSurface({
    super.key,
    required this.toast,
    required this.onAction,
    required this.onDismiss,
  });

  final _BusyBooksToast toast;
  final VoidCallback onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BusyBooksSurfaceColors.of(context);
    final actionLabel = toast.actionLabel;
    return Semantics(
      container: true,
      liveRegion: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Material(
          color: BusyBooksLinuxPalette.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.popover,
              borderRadius: BorderRadius.circular(BusyBooksRadius.lg),
              border: Border.all(color: colors.floatingBorder),
              boxShadow: BusyBooksShadow.nativeCardShadowsFor(context),
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                BusyBooksSpacing.lg,
                BusyBooksSpacing.sm,
                BusyBooksSpacing.sm,
                BusyBooksSpacing.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      toast.message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (actionLabel != null && actionLabel.isNotEmpty) ...[
                    const SizedBox(width: BusyBooksSpacing.sm),
                    TextButton(onPressed: onAction, child: Text(actionLabel)),
                  ],
                  const SizedBox(width: BusyBooksSpacing.xs),
                  BusyBooksCompactIconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    icon: BusyBooksGlyphs.windowClose,
                    onPressed: onDismiss,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
