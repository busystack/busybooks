import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/busybooks_design.dart';
import '../application/book_presentation.dart';

/// Two persistent content slots. A view change only alters their allocation;
/// it never moves either element into another parent or creates a second copy.
class BookPaneLayout extends StatelessWidget {
  const BookPaneLayout({
    super.key,
    required this.view,
    required this.ratio,
    required this.reading,
    required this.notebook,
    required this.onRatioChanged,
    required this.prepareResize,
    required this.dividerLabel,
    required this.dividerHint,
    required this.ratioLabel,
    required this.readingMinWidth,
    required this.notebookMinWidth,
  });

  final BookView view;
  final double ratio, readingMinWidth, notebookMinWidth;
  final Widget reading, notebook;
  final ValueChanged<double> onRatioChanged;
  final Future<bool> Function() prepareResize;
  final String dividerLabel, dividerHint;
  final String Function(int reading, int notebook) ratioLabel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final available = constraints.maxWidth - bookSplitDividerWidth;
      final width = view == BookView.split
          ? splitReadingWidth(
              available,
              ratio,
              readingMinWidth,
              notebookMinWidth,
            )
          : 0.0;
      Widget pane(bool visible, Widget child) => ExcludeFocus(
        excluding: !visible,
        child: Offstage(
          offstage: !visible,
          child: TickerMode(enabled: visible, child: child),
        ),
      );
      return FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: CustomMultiChildLayout(
          delegate: _BookPaneDelegate(view, width),
          children: [
            LayoutId(id: _Pane.reading, child: pane(view.hasReader, reading)),
            LayoutId(
              id: _Pane.divider,
              child: pane(
                view == BookView.split,
                _PaneDivider(
                  enabled: view == BookView.split,
                  readingWidth: width,
                  availableWidth: available,
                  readingMinWidth: view == BookView.split ? readingMinWidth : 0,
                  notebookMinWidth: view == BookView.split
                      ? notebookMinWidth
                      : 0,
                  onRatioChanged: onRatioChanged,
                  prepareResize: prepareResize,
                  label: dividerLabel,
                  hint: dividerHint,
                  value: ratioLabel,
                ),
              ),
            ),
            LayoutId(
              id: _Pane.notebook,
              child: pane(view.hasNotebook, notebook),
            ),
          ],
        ),
      );
    },
  );
}

/// The workspace uses a retained single-pane allocation below these minima;
/// the side-by-side layout is invoked only when both panes fit.
double splitReadingWidth(
  double available,
  double ratio,
  double readingMinimum,
  double notebookMinimum,
) {
  assert(
    available >= readingMinimum + notebookMinimum,
    'Split requires a usable allocation for both panes.',
  );
  return (available * ratio).clamp(readingMinimum, available - notebookMinimum);
}

enum _Pane { reading, divider, notebook }

class _BookPaneDelegate extends MultiChildLayoutDelegate {
  _BookPaneDelegate(this.view, this.readingWidth);
  final BookView view;
  final double readingWidth;

  @override
  void performLayout(Size size) {
    final split = view == BookView.split;
    final reader = split ? Size(readingWidth, size.height) : size;
    final note = split
        ? Size(size.width - readingWidth - bookSplitDividerWidth, size.height)
        : size;
    layoutChild(_Pane.reading, BoxConstraints.tight(reader));
    positionChild(_Pane.reading, Offset.zero);
    layoutChild(
      _Pane.divider,
      BoxConstraints.tight(
        Size(split ? bookSplitDividerWidth : 0, size.height),
      ),
    );
    positionChild(_Pane.divider, Offset(split ? readingWidth : 0, 0));
    layoutChild(_Pane.notebook, BoxConstraints.tight(note));
    positionChild(
      _Pane.notebook,
      Offset(split ? readingWidth + bookSplitDividerWidth : 0, 0),
    );
  }

  @override
  bool shouldRelayout(_BookPaneDelegate oldDelegate) =>
      view != oldDelegate.view || readingWidth != oldDelegate.readingWidth;
}

class _PaneDivider extends StatefulWidget {
  const _PaneDivider({
    required this.enabled,
    required this.readingWidth,
    required this.availableWidth,
    required this.readingMinWidth,
    required this.notebookMinWidth,
    required this.onRatioChanged,
    required this.prepareResize,
    required this.label,
    required this.hint,
    required this.value,
  });
  final bool enabled;
  final double readingWidth, availableWidth, readingMinWidth, notebookMinWidth;
  final ValueChanged<double> onRatioChanged;
  final Future<bool> Function() prepareResize;
  final String label, hint;
  final String Function(int reading, int notebook) value;

  @override
  State<_PaneDivider> createState() => _PaneDividerState();
}

class _PaneDividerState extends State<_PaneDivider> {
  final _focus = FocusNode(debugLabel: 'Book split divider');
  bool _hovered = false, _resizing = false;
  int _request = 0;
  double _start = 0, _delta = 0;
  double? _keyboardWidth;
  Future<bool>? _preparing;

  @override
  void didUpdateWidget(covariant _PaneDivider oldWidget) {
    super.didUpdateWidget(oldWidget);
    _keyboardWidth = null;
    if (oldWidget.enabled != widget.enabled) {
      _request++;
      _resizing = false;
    }
  }

  @override
  void dispose() {
    _request++;
    _focus.dispose();
    super.dispose();
  }

  void _setWidth(double width) {
    if (!widget.enabled) return;
    final value = width.clamp(
      widget.readingMinWidth,
      widget.availableWidth - widget.notebookMinWidth,
    );
    widget.onRatioChanged(value / widget.availableWidth);
  }

  Future<void> _adjust(double delta) async {
    if (!widget.enabled) return;
    final target = _keyboardWidth =
        ((_keyboardWidth ?? widget.readingWidth) + delta).clamp(
          widget.readingMinWidth,
          widget.availableWidth - widget.notebookMinWidth,
        );
    final request = ++_request;
    if (!await _prepareResize() || !mounted || request != _request) {
      return;
    }
    _focus.requestFocus();
    _setWidth(target);
  }

  Future<bool> _prepareResize() {
    if (_preparing case final Future<bool> pending) return pending;
    final operation = widget.prepareResize();
    _preparing = operation;
    operation.whenComplete(() {
      if (identical(_preparing, operation)) _preparing = null;
    });
    return operation;
  }

  Future<void> _startDrag() async {
    if (!widget.enabled) return;
    _start = widget.readingWidth;
    _delta = 0;
    _keyboardWidth = null;
    final request = ++_request;
    if (!await _prepareResize() || !mounted || request != _request) {
      return;
    }
    _focus.requestFocus();
    setState(() => _resizing = true);
    _setWidth(_start + _delta);
  }

  void _endDrag() {
    _request++;
    if (_resizing) setState(() => _resizing = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = BusyBooksSurfaceColors.of(context);
    final reading = widget.availableWidth > 0
        ? (100 * widget.readingWidth / widget.availableWidth).round()
        : 50;
    String adjustedValue(double delta) {
      final width = (widget.readingWidth + delta).clamp(
        widget.readingMinWidth,
        widget.availableWidth - widget.notebookMinWidth,
      );
      final percent = (100 * width / widget.availableWidth).round();
      return widget.value(percent, 100 - percent);
    }

    return Semantics(
      key: const ValueKey('book-split-divider'),
      label: widget.label,
      hint: widget.hint,
      value: widget.value(reading, 100 - reading),
      increasedValue: adjustedValue(16),
      decreasedValue: adjustedValue(-16),
      slider: true,
      onIncrease: () => _adjust(16),
      onDecrease: () => _adjust(-16),
      child: Focus(
        focusNode: _focus,
        onFocusChange: (_) => setState(() {}),
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          final direction = switch (event.logicalKey) {
            LogicalKeyboardKey.arrowLeft => -1,
            LogicalKeyboardKey.arrowRight => 1,
            _ => 0,
          };
          if (direction == 0) return KeyEventResult.ignored;
          _adjust(
            direction * (HardwareKeyboard.instance.isShiftPressed ? 64 : 16),
          );
          return KeyEventResult.handled;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => _startDrag(),
            onHorizontalDragUpdate: (details) {
              _delta += details.delta.dx;
              if (_resizing) _setWidth(_start + _delta);
            },
            onHorizontalDragEnd: (_) => _endDrag(),
            onHorizontalDragCancel: _endDrag,
            child: ColoredBox(
              color: _focus.hasFocus || _hovered || _resizing
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: .08)
                  : colors.view,
              child: Center(
                child: SizedBox(
                  width: _focus.hasFocus || _resizing ? 2 : 1,
                  child: ColoredBox(
                    color: _focus.hasFocus || _resizing
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).dividerColor,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
