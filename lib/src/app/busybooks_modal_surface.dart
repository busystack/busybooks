import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart' show AsyncCallback;

/// Lets the primary desktop window cover its embedded reader for a modal.
/// The returned lease lasts until the dialog route has actually unmounted.
class BusyBooksModalSurfaceScope extends InheritedWidget {
  const BusyBooksModalSurfaceScope({
    super.key,
    required this.cover,
    required super.child,
  });
  final Future<AsyncCallback> Function() cover;
  static BusyBooksModalSurfaceScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BusyBooksModalSurfaceScope>();
  @override
  bool updateShouldNotify(BusyBooksModalSurfaceScope oldWidget) => false;
}
