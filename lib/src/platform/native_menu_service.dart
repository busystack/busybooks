// Adapted from BusyMark (BusyStack, Apache-2.0); modified for BusyBooks.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@visibleForTesting
const nativeMenuChannelName = 'busybooks/native_menus';

/// Identifies one native menu presentation.
///
/// The host compares this identity when dismissing a menu, so a retiring
/// widget cannot close a newer caller's menu.
@immutable
final class NativeMenuSession {
  NativeMenuSession() : id = _nextId++;

  static int _nextId = 1;

  final int id;
}

/// One semantic row exposed by a host-toolkit menu.
@immutable
final class NativeMenuEntry {
  const NativeMenuEntry.command({
    required this.label,
    this.iconName,
    this.iconMask,
    this.iconSize,
    this.iconColorArgb,
    this.shortcut,
    this.gtkAccelerator,
    this.enabled = true,
    this.checkable = false,
    this.selected = false,
    this.mutuallyExclusive = false,
  }) : separator = false,
       children = null;

  const NativeMenuEntry.submenu({
    required this.label,
    required List<NativeMenuEntry> this.children,
    this.enabled = true,
  }) : iconName = null,
       iconMask = null,
       iconSize = null,
       iconColorArgb = null,
       shortcut = null,
       gtkAccelerator = null,
       checkable = false,
       selected = false,
       mutuallyExclusive = false,
       separator = false;

  const NativeMenuEntry.separator()
    : label = '',
      iconName = null,
      iconMask = null,
      iconSize = null,
      iconColorArgb = null,
      shortcut = null,
      gtkAccelerator = null,
      enabled = false,
      checkable = false,
      selected = false,
      mutuallyExclusive = false,
      separator = true,
      children = null;

  final String label;
  final String? iconName;
  // Windows view-mode menus use the same Yaru glyph as Flutter. Bounded alpha
  // pixels let the host color it with its actual menu/high-contrast colors.
  final Uint8List? iconMask;
  final int? iconSize;
  final int? iconColorArgb;
  final String? shortcut;
  final String? gtkAccelerator;
  final bool enabled;
  final bool checkable;
  final bool selected;
  final bool mutuallyExclusive;
  final bool separator;
  final List<NativeMenuEntry>? children;

  Map<String, Object> _toPlatformMap() {
    return <String, Object>{
      'label': label,
      if (iconName != null && iconName!.isNotEmpty) 'icon': iconName!,
      if (iconMask != null) 'iconMask': iconMask!,
      if (iconMask != null) 'iconSize': iconSize!,
      if (iconColorArgb != null) 'iconColor': iconColorArgb!,
      if (shortcut != null && shortcut!.isNotEmpty) 'shortcut': shortcut!,
      if (gtkAccelerator != null && gtkAccelerator!.isNotEmpty)
        'gtkAccelerator': gtkAccelerator!,
      'enabled': enabled,
      'checkable': checkable,
      'selected': selected,
      'mutuallyExclusive': mutuallyExclusive,
      'separator': separator,
      if (children != null)
        'children': [for (final child in children!) child._toPlatformMap()],
    };
  }
}

/// Result of asking the host toolkit to present a native menu.
@immutable
final class NativeMenuResult {
  const NativeMenuResult.available({this.selectedIndex}) : available = true;

  const NativeMenuResult.unavailable()
    : available = false,
      selectedIndex = null;

  final bool available;
  final int? selectedIndex;
}

/// Presents anchored menus through the host desktop toolkit when available.
class NativeMenuService {
  const NativeMenuService({
    MethodChannel channel = const MethodChannel(nativeMenuChannelName),
    bool? supportedPlatform,
  }) : _channel = channel,
       _supportedPlatform = supportedPlatform;

  final MethodChannel _channel;
  final bool? _supportedPlatform;
  bool get _supported =>
      _supportedPlatform ??
      (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows);

  Future<NativeMenuResult> show({
    required NativeMenuSession session,
    required Rect anchor,
    required List<NativeMenuEntry> entries,
    bool focusFirst = false,
    bool preferAbove = false,
    TextDirection? textDirection,
  }) async {
    _validateEntries(entries);
    if (!_supported) return const NativeMenuResult.unavailable();
    try {
      final selectedIndex = await _channel.invokeMethod<int>('show', {
        'sessionId': session.id,
        'anchor': <String, double>{
          'x': anchor.left,
          'y': anchor.top,
          'width': anchor.width,
          'height': anchor.height,
        },
        'entries': [for (final entry in entries) entry._toPlatformMap()],
        'focusFirst': focusFirst,
        'preferredPosition': preferAbove ? 'top' : 'bottom',
        if (textDirection != null) 'textDirection': textDirection.name,
      });
      return NativeMenuResult.available(selectedIndex: selectedIndex);
    } on MissingPluginException {
      return const NativeMenuResult.unavailable();
    } on PlatformException catch (error) {
      // Invalid contracts are programming errors. Host presentation failures
      // use the same themed fallback as an absent host, without a modal dialog.
      if (error.code == 'invalid-arguments' || error.code == 'bad-arguments') {
        rethrow;
      }
      debugPrint(
        'Native menu ${session.id} failed (${entries.length} rows): '
        '${error.code}: ${error.message}',
      );
      return const NativeMenuResult.unavailable();
    }
  }

  Future<bool> dismiss(NativeMenuSession session) async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('dismiss', {
            'sessionId': session.id,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      if (error.code == 'invalid-arguments' || error.code == 'bad-arguments') {
        rethrow;
      }
      debugPrint(
        'Native menu ${session.id} dismissal failed: ${error.code}: ${error.message}',
      );
      return false;
    }
  }
}

void _validateEntries(List<NativeMenuEntry> entries) {
  var count = 0;
  void visit(List<NativeMenuEntry> rows, int depth) {
    if (depth > 8 || rows.isEmpty || rows.length > 4096 - count) {
      throw ArgumentError('Invalid or excessive menu entries');
    }
    count += rows.length;
    var selected = 0;
    for (final row in rows) {
      if (row.selected && !row.checkable ||
          row.children != null && (row.separator || row.checkable)) {
        throw ArgumentError('Invalid menu selection or submenu');
      }
      if (!row.separator && row.checkable && row.mutuallyExclusive) {
        if (row.selected) selected++;
        if (selected > 1) {
          throw ArgumentError('Multiple selections in a single-choice menu');
        }
      } else {
        selected = 0;
      }
      if (row.children != null) visit(row.children!, depth + 1);
    }
  }

  visit(entries, 0);
}
