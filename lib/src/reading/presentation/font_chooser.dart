import 'package:yaru/yaru.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/busybooks_design.dart';
import '../../app/busybooks_search_field.dart';
import '../../app/localization.dart';
import '../../app/busybooks_glyphs.dart';
import '../../core/typography.dart';
import '../fonts/reading_font_service.dart';

String fontChoiceLabel(BuildContext context, FontChoice choice) =>
    choice.family ??
    switch (choice.generic!) {
      GenericFont.serif => context.l10n.serifFont,
      GenericFont.sansSerif => context.l10n.sansFont,
      GenericFont.monospace => context.l10n.monoFont,
    };

/// Shared, bounded chooser inside Appearance (also in its separate engine).
/// Candidate movement only owns preview requests; activation alone calls back.
class ReadingFontChooser extends StatefulWidget {
  const ReadingFontChooser({
    super.key,
    required this.service,
    required this.selected,
    required this.preferences,
    required this.onSelected,
    required this.onDismiss,
    this.escapeRevision = 0,
  });
  final ReadingFontService service;
  final FontChoice selected;
  final Map<String, dynamic> preferences;
  final Future<void> Function(FontChoice) onSelected;
  final VoidCallback onDismiss;
  final int escapeRevision;
  @override
  State<ReadingFontChooser> createState() => _ReadingFontChooserState();
}

class _ReadingFontChooserState extends State<ReadingFontChooser> {
  final _search = TextEditingController(), _scroll = ScrollController();
  final _sampleHeader = GlobalKey();
  FontCatalogue? _catalogue;
  bool _loading = true, _applying = false;
  Object? _error, _applyError;
  late FontChoice _candidate = widget.selected;
  int _catalogueRequest = 0;
  bool get _composing =>
      _search.value.composing.isValid && !_search.value.composing.isCollapsed;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant ReadingFontChooser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.escapeRevision != widget.escapeRevision && !_composing) {
      final revision = widget.escapeRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.escapeRevision == revision) widget.onDismiss();
      });
    }
  }

  @override
  void dispose() {
    _catalogueRequest++;
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    final request = ++_catalogueRequest;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await widget.service.catalogue(refresh: refresh);
      if (mounted && request == _catalogueRequest) {
        setState(() {
          _catalogue = value;
          _loading = false;
          _selectCandidateForQuery();
        });
      }
    } catch (error) {
      if (mounted && request == _catalogueRequest) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  List<(FontChoice, String)> _matches(BuildContext context) {
    final query = _search.text.toLowerCase().trim();
    return [
          for (final g in FontChoice.generics) (g, fontChoiceLabel(context, g)),
          if (widget.selected.family != null &&
              _catalogue?.find(widget.selected.family!) == null)
            (widget.selected, widget.selected.family!),
          for (final f in _catalogue?.families ?? <InstalledFontFamily>[])
            (f.choice, f.label),
        ]
        .where(
          (f) =>
              f.$2.toLowerCase().contains(query) ||
              f.$1.name.toLowerCase().contains(query),
        )
        .toList();
  }

  void _selectCandidateForQuery() {
    final rows = _matches(context);
    if (rows.isNotEmpty && !rows.any((row) => row.$1 == _candidate)) {
      _candidate = rows.first.$1;
    }
  }

  void _move(BuildContext context, int delta, double extent) {
    if (_composing) return;
    final rows = _matches(context);
    if (rows.isEmpty) return;
    final index = rows.indexWhere((r) => r.$1 == _candidate);
    final next = (index < 0 ? (delta > 0 ? 0 : rows.length - 1) : index + delta)
        .clamp(0, rows.length - 1);
    setState(() => _candidate = rows[next].$1);
    if (_scroll.hasClients) {
      final header = _sampleHeader.currentContext?.findRenderObject();
      final top =
          (header is RenderBox && header.hasSize ? header.size.height : 0) +
          next * extent;
      final bottom = top + extent, position = _scroll.position;
      if (top < position.pixels) {
        _scroll.jumpTo(top.clamp(0, position.maxScrollExtent));
      } else if (bottom > position.pixels + position.viewportDimension) {
        _scroll.jumpTo(
          (bottom - position.viewportDimension).clamp(
            0,
            position.maxScrollExtent,
          ),
        );
      }
    }
  }

  Future<void> _activate(FontChoice choice) async {
    if (_applying || _composing) return;
    setState(() {
      _applying = true;
      _applyError = null;
    });
    try {
      await widget.onSelected(choice);
    } catch (error) {
      if (mounted) setState(() => _applyError = error);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n, rows = _matches(context);
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final extent = 58.0 * scale;
    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            !_composing) {
          widget.onDismiss();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Padding(
        padding: const EdgeInsets.all(BusyBooksSpacing.lg),
        child: LayoutBuilder(
          builder: (context, bounds) => Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.fontFamily,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('font-chooser-close'),
                    onPressed: widget.onDismiss,
                    child: Text(l.close),
                  ),
                ],
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  '${l.currentFont}: ${fontChoiceLabel(context, widget.selected)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              SizedBox(
                height: 40 * scale,
                child: BusyBooksSearchField(
                  key: const ValueKey('font-search'),
                  controller: _search,
                  hintText: l.searchFonts,
                  autofocus: true,
                  clearOnEscape: false,
                  onEscape: widget.onDismiss,
                  onChanged: (_) => setState(_selectCandidateForQuery),
                  onMoveSelection: (delta) => _move(context, delta, extent),
                  onSubmitted: (_) {
                    if (rows.any((r) => r.$1 == _candidate)) {
                      unawaited(_activate(_candidate));
                    }
                  },
                ),
              ),
              const SizedBox(height: BusyBooksSpacing.sm),
              Expanded(
                child: CustomScrollView(
                  key: const ValueKey('font-results'),
                  controller: _scroll,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        key: _sampleHeader,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: (bounds.maxHeight * .30).clamp(68.0, 160.0),
                            child: FontSample(
                              key: const ValueKey('font-sample'),
                              service: widget.service,
                              refresh:
                                  _catalogueRequest * 2 + (_loading ? 0 : 1),
                              choice: _candidate,
                              preferences: widget.preferences,
                            ),
                          ),
                          if (widget.preferences['publisher'] == true)
                            Text(
                              l.fontPublisherHelp,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          if (_applyError != null)
                            Text(
                              l.fontApplyFailed,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          if (_applying)
                            const YaruLinearProgressIndicator(
                              key: ValueKey('font-applying'),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _loading
                                      ? l.loadingFonts
                                      : _error != null
                                      ? l.fontCatalogueFailed
                                      : _catalogue?.families.isEmpty == true
                                      ? l.noInstalledFonts
                                      : l.installedFonts,
                                  maxLines: 3,
                                ),
                              ),
                              TextButton(
                                key: const ValueKey('font-refresh'),
                                onPressed: _loading
                                    ? null
                                    : () => _load(refresh: true),
                                child: Text(
                                  _error == null ? l.refreshFonts : l.retry,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (rows.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: Text(l.noMatchingFonts)),
                      )
                    else
                      SliverFixedExtentList(
                        itemExtent: extent,
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final (choice, label) = rows[index];
                            final applied = choice == widget.selected;
                            final missing =
                                choice.family != null &&
                                _catalogue?.find(choice.family!) == null;
                            return Semantics(
                              key: ValueKey(choice.key),
                              selected: applied,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: choice == _candidate
                                      ? Theme.of(context).colorScheme.primary
                                            .withValues(alpha: .08)
                                      : null,
                                ),
                                child: BusyBooksActionRow(
                                  key: ValueKey('activate:${choice.key}'),
                                  title: label,
                                  subtitle: choice.family == null
                                      ? l.genericFontCategory
                                      : missing
                                      ? l.rememberedFont
                                      : l.installedFont,
                                  trailing: applied
                                      ? Icon(
                                          BusyBooksGlyphs.check,
                                          semanticLabel: l.currentFont,
                                        )
                                      : null,
                                  onFocusChange: (focused) {
                                    if (focused && mounted) {
                                      setState(() => _candidate = choice);
                                    }
                                  },
                                  onTap: () => _activate(choice),
                                ),
                              ),
                            );
                          },
                          childCount: rows.length,
                          findChildIndexCallback: (key) {
                            final index = rows.indexWhere(
                              (row) => ValueKey(row.$1.key) == key,
                            );
                            return index < 0 ? null : index;
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FontSample extends StatelessWidget {
  const FontSample({
    super.key,
    required this.service,
    required this.choice,
    required this.preferences,
    this.refresh = 0,
  });
  final int refresh;
  final ReadingFontService service;
  final FontChoice choice;
  final Map<String, dynamic> preferences;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => _NativeFontSample(
      service: service,
      refresh: refresh,
      choice: choice,
      preferences: preferences,
      width: bounds.maxWidth.round(),
      height: bounds.maxHeight.round().clamp(128, 160),
    ),
  );
}

class _NativeFontSample extends StatefulWidget {
  const _NativeFontSample({
    required this.service,
    required this.choice,
    required this.preferences,
    required this.width,
    required this.height,
    required this.refresh,
  });
  final int refresh;
  final ReadingFontService service;
  final FontChoice choice;
  final Map<String, dynamic> preferences;
  final int width, height;
  @override
  State<_NativeFontSample> createState() => _NativeFontSampleState();
}

class _NativeFontSampleState extends State<_NativeFontSample> {
  int _request = 0;
  Object? _parameters;
  Uint8List? _image;
  FontResolution? _resolved;
  bool _failed = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(covariant _NativeFontSample oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  void _load() {
    final l = context.l10n,
        theme = Theme.of(context),
        service = widget.service,
        choice = widget.choice;
    final bg = theme.colorScheme.surface, fg = theme.colorScheme.onSurface;
    final scale = MediaQuery.devicePixelRatioOf(context);
    final size =
        ((widget.preferences['size'] as num? ?? 20).toDouble() *
                MediaQuery.textScalerOf(context).scale(1))
            .clamp(14.0, 28.0);
    final line = (widget.preferences['line'] as num? ?? 1.5).toDouble();
    final weight = (widget.preferences['weight'] as num? ?? 400).toInt();
    final parameters = (
      choice.key,
      widget.refresh,
      widget.width,
      widget.height,
      scale,
      fg.toARGB32(),
      bg.toARGB32(),
      size,
      line,
      weight,
      l.fontSampleProse,
      service,
    );
    if (_parameters == parameters) return;
    _parameters = parameters;
    final request = ++_request, width = widget.width, height = widget.height;
    _image = null;
    _failed = false;
    _resolved = null;
    unawaited(() async {
      try {
        final resolved = await service.resolve(choice);
        if (!mounted || request != _request) return;
        final image = await service.preview(
          resolved,
          prose: l.fontSampleProse,
          bold: l.fontSampleBold,
          italic: l.fontSampleItalic,
          width: width,
          height: height,
          scale: scale,
          foreground: fg.toARGB32(),
          background: bg.toARGB32(),
          size: size,
          weight: weight,
          line: line,
        );
        if (mounted && request == _request) {
          setState(() {
            _image = image;
            _resolved = resolved;
          });
        }
      } catch (_) {
        if (mounted && request == _request) setState(() => _failed = true);
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Semantics(
      label:
          '${l.fontPreview}: ${fontChoiceLabel(context, widget.choice)}. ${l.fontSampleProse} ${l.fontSampleBold} ${l.fontSampleItalic}',
      image: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_image != null)
            Image.memory(
              _image!,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            )
          else
            Center(child: Text(_failed ? l.fontPreviewFailed : l.loadingFonts)),
          if (_resolved != null &&
              _resolved!.availability != FontAvailability.available)
            Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                l.fontUnavailable,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
