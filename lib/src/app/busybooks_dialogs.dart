// Adapted BusyMark modal shortcut boundary and theme-aware route.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'command_registry.dart';
import 'busybooks_design.dart';

class _DismissBusyBooksModalIntent extends Intent {
  const _DismissBusyBooksModalIntent();
}

/// Prevents application and workspace shortcuts from escaping a modal surface.
///
/// Use this around modal UI that is not presented by
/// [showBusyBooksModalDialog], such as an in-page editor overlay.
class BusyBooksModalShortcutBoundary extends StatefulWidget {
  const BusyBooksModalShortcutBoundary({super.key, required this.child});

  final Widget child;

  @override
  State<BusyBooksModalShortcutBoundary> createState() =>
      _BusyBooksModalShortcutBoundaryState();
}

class _BusyBooksModalShortcutBoundaryState
    extends State<BusyBooksModalShortcutBoundary> {
  final _fallbackFocusNode = FocusNode(
    debugLabel: 'BusyBooks modal shortcut fallback',
  );
  FocusScopeNode? _enclosingScope;

  @override
  void initState() {
    super.initState();
    // DialogRoute initially parks focus on its own scope. Wait for that focus
    // transition, then move it below Shortcuts only when no child requested
    // focus, so Escape works without overriding a field's autofocus.
    FocusManager.instance.addListener(_focusFallbackIfNeeded);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusFallbackIfNeeded();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enclosingScope = FocusScope.of(context);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusFallbackIfNeeded);
    _fallbackFocusNode.dispose();
    super.dispose();
  }

  void _focusFallbackIfNeeded() {
    if (!mounted || _fallbackFocusNode.context == null) return;
    if (FocusManager.instance.primaryFocus == _enclosingScope) {
      _fallbackFocusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        ...(BusyBooksCommandRegistryScope.maybeOf(context) ??
                BusyBooksCommandCatalog.metadata)
            .shortcutIntents(
              scopes: const {
                BusyBooksCommandScope.application,
                BusyBooksCommandScope.documentView,

                BusyBooksCommandScope.sidebar,
              },
              intentFor: (_) => const DoNothingAndStopPropagationIntent(),
            ),
        const SingleActivator(LogicalKeyboardKey.escape):
            const _DismissBusyBooksModalIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _DismissBusyBooksModalIntent:
              CallbackAction<_DismissBusyBooksModalIntent>(
                onInvoke: (_) {
                  unawaited(Navigator.maybePop(context));
                  return null;
                },
              ),
        },
        child: Focus(
          focusNode: _fallbackFocusNode,
          skipTraversal: true,
          includeSemantics: false,
          child: DefaultTextEditingShortcuts(child: widget.child),
        ),
      ),
    );
  }
}

Color busyBooksModalBarrierColor(BuildContext context) {
  return BusyBooksSurfaceColors.of(context).shade;
}

Future<T?> showBusyBooksModalDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  Color? barrierColor,
  bool barrierDismissible = true,
}) => _showBusyBooksFlutterDialog<T>(
  context,
  builder: builder,
  barrierColor: barrierColor,
  barrierDismissible: barrierDismissible,
);
Future<T?> _showBusyBooksFlutterDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  Color? barrierColor,
  bool barrierDismissible = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  return navigator.push<T>(
    _BusyBooksDialogRoute<T>(
      context: context,
      builder: builder,
      themes: themes,
      fixedBarrierColor: barrierColor,
      initialBarrierColor: barrierColor ?? busyBooksModalBarrierColor(context),
      barrierDismissible: barrierDismissible,
    ),
  );
}

class _BusyBooksDialogRoute<T> extends DialogRoute<T> {
  _BusyBooksDialogRoute({
    required super.context,
    required WidgetBuilder builder,
    required CapturedThemes themes,
    required Color? fixedBarrierColor,
    required Color initialBarrierColor,
    required super.barrierDismissible,
  }) : _fixedBarrierColor = fixedBarrierColor,
       _initialBarrierColor = initialBarrierColor,
       super(
         builder: (dialogContext) =>
             BusyBooksModalShortcutBoundary(child: builder(dialogContext)),
         themes: themes,
         barrierColor: initialBarrierColor,
         traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
       );

  final Color? _fixedBarrierColor;
  final Color _initialBarrierColor;

  /// Unlike [DialogRoute]'s constructor value, this getter is reevaluated
  /// when the Navigator's inherited theme changes.
  @override
  Color? get barrierColor {
    final fixedColor = _fixedBarrierColor;
    if (fixedColor != null) {
      return fixedColor;
    }
    final navigatorContext = navigator?.context;
    return navigatorContext == null
        ? _initialBarrierColor
        : busyBooksModalBarrierColor(navigatorContext);
  }
}
