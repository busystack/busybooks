import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_settings.dart';
import '../../app/busybooks_design.dart';
import '../../app/localization.dart';
import '../../core/reading_preferences.dart';
import '../../core/typography.dart';
import '../fonts/reading_font_service.dart';
import 'font_chooser.dart';
import '../application/reader_controller.dart';

/// The same callback-driven controls are used in Settings and the owned reader
/// popover. No persistence or renderer work runs inside these controls.
class ReadingAppearanceControls extends StatefulWidget {
  const ReadingAppearanceControls({
    super.key,
    required this.preferences,
    required this.capabilities,
    this.fonts,
    this.onFontChooserChanged,
    this.fontChooserEscape = 0,
    required this.pdf,
    required this.onChanged,
    required this.onReset,
    required this.onSaveDefaults,
    this.defaults = false,
    this.noText = false,
    this.comic = false,
  });
  final Map<String, dynamic> preferences;
  final TypographyCapabilities capabilities;
  final ReadingFontService? fonts;
  final ValueChanged<bool>? onFontChooserChanged;
  final int fontChooserEscape;
  final bool pdf, comic, defaults, noText;
  final Future<void> Function(Map<String, dynamic>) onChanged;
  final Future<void> Function() onReset, onSaveDefaults;
  @override
  State<ReadingAppearanceControls> createState() =>
      _ReadingAppearanceControlsState();
}

class _ReadingAppearanceControlsState extends State<ReadingAppearanceControls> {
  bool advanced = false, choosingFont = false;
  bool operationFailed = false;
  final _fontFocus = FocusNode(debugLabel: 'Font family');
  FontAvailability? _availability;
  int _resolutionRequest = 0, _chooserRevision = 0;
  ReadingFontService get _fonts => widget.fonts ?? ReadingFontService.instance;
  @override
  void initState() {
    super.initState();
    _checkFont();
  }

  @override
  void didUpdateWidget(covariant ReadingAppearanceControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (FontChoice.parse(oldWidget.preferences['font']) !=
            FontChoice.parse(widget.preferences['font']) ||
        oldWidget.fonts != widget.fonts) {
      _checkFont();
    }
    if (!widget.capabilities.fontFamily && choosingFont) _closeChooser();
  }

  void _checkFont() {
    final request = ++_resolutionRequest;
    final choice =
        FontChoice.parse(widget.preferences['font']) ?? FontChoice.serif;
    _availability = null;
    if (choice.family != null) {
      unawaited(
        _fonts.resolve(choice).then((value) {
          if (mounted && request == _resolutionRequest) {
            setState(() => _availability = value.availability);
          }
        }),
      );
    }
  }

  void _closeChooser() {
    _chooserRevision++;
    setState(() => choosingFont = false);
    widget.onFontChooserChanged?.call(false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fontFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _resolutionRequest++;
    if (choosingFont) widget.onFontChooserChanged?.call(false);
    _fontFocus.dispose();
    super.dispose();
  }

  Future<void> _perform(Future<void> Function() operation) async {
    try {
      await operation();
      if (mounted && operationFailed) setState(() => operationFailed = false);
    } catch (_) {
      if (mounted) setState(() => operationFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preferences, l = context.l10n;
    final font = FontChoice.parse(p['font']) ?? FontChoice.serif;
    final chooserRevision = _chooserRevision;
    if (choosingFont && widget.capabilities.fontFamily) {
      return ReadingFontChooser(
        service: _fonts,
        escapeRevision: widget.fontChooserEscape,
        selected: font,
        preferences: p,
        onDismiss: _closeChooser,
        onSelected: (choice) async {
          await widget.onChanged({'font': choice.toJson(), 'publisher': false});
          if (mounted && choosingFont && chooserRevision == _chooserRevision) {
            _closeChooser();
          }
        },
      );
    }
    void set(String key, Object value) => unawaited(
      _perform(
        () => widget.onChanged({
          key: value,
          if ([
            'font',
            'size',
            'weight',
            'line',
            'paragraph',
            'align',
            'hyphenate',
          ].contains(key))
            'publisher': false,
        }),
      ),
    );
    Widget number(
      String key,
      String title,
      List<num> choices,
      String Function(num) label,
    ) {
      final values = [
        ...choices,
        if (p[key] is num && !choices.contains(p[key])) p[key] as num,
      ]..sort();
      return BusyBooksComboRow<num>(
        title: title,
        values: values,
        selected: p[key] as num,
        labelFor: label,
        onSelected: (v) => set(key, v),
      );
    }

    Widget choices(String key, String title, List<(String, String)> values) {
      // A previously saved family remains visible without promising it is installed.
      final available = [
        ...values,
        if (!values.any((v) => v.$1 == p[key]))
          (p[key].toString(), p[key].toString()),
      ];
      return BusyBooksComboRow<String>(
        title: title,
        values: available.map((v) => v.$1).toList(),
        selected: p[key] as String,
        labelFor: (v) => available.firstWhere((x) => x.$1 == v).$2,
        onSelected: (v) => set(key, v),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(BusyBooksSpacing.lg),
      children: [
        if (operationFailed)
          BusyBooksBanner(
            key: const ValueKey('appearance-write-error'),
            title: l.writeFailed,
          ),
        if (widget.noText) Text(l.noText),
        if (widget.capabilities.textMetrics || widget.capabilities.fontFamily)
          BusyBooksGroupedList(
            children: [
              if (widget.capabilities.textMetrics ||
                  widget.capabilities.fontFamily)
                BusyBooksSwitchRow(
                  title: l.publisher,
                  value: p['publisher'] == true,
                  onChanged: (v) => set('publisher', v),
                ),
              if (widget.capabilities.fontFamily)
                BusyBooksActionRow(
                  key: const ValueKey('font-family'),
                  focusNode: _fontFocus,
                  title: l.fontFamily,
                  subtitle: fontChoiceLabel(context, font),
                  onTap: () {
                    setState(() {
                      choosingFont = true;
                      _chooserRevision++;
                    });
                    widget.onFontChooserChanged?.call(true);
                  },
                ),
              if (p['publisher'] == true)
                Padding(
                  padding: const EdgeInsets.all(BusyBooksSpacing.sm),
                  child: Text(
                    l.publisherFontActive,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (p['publisher'] != true &&
                  _availability != null &&
                  _availability != FontAvailability.available)
                Padding(
                  padding: const EdgeInsets.all(BusyBooksSpacing.sm),
                  child: Text(
                    _availability == FontAvailability.discoveryFailed
                        ? l.fontCatalogueFailed
                        : l.fontUnavailable,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (widget.capabilities.textMetrics)
                number('size', l.fontSize, [
                  12,
                  14,
                  16,
                  18,
                  20,
                  22,
                  24,
                  28,
                  32,
                  36,
                  40,
                ], (n) => '${n.toStringAsFixed(0)} px'),
            ],
          ),
        BusyBooksGroupedList(
          children: [
            if (!widget.comic)
              choices('color', l.pageColor, [
                ('system', l.system),
                ('light', l.light),
                ('dark', l.dark),
                ('sepia', l.sepia),
              ]),
            if (widget.capabilities.textMetrics || widget.pdf)
              choices('flow', l.readingMode, [
                ('paginated', l.paginated),
                ('scrolled', l.continuous),
              ]),
            if (widget.comic)
              choices('direction', l.readingDirection, [
                ('auto', l.directionAuto),
                ('ltr', l.directionLtr),
                ('rtl', l.directionRtl),
              ]),
            BusyBooksSwitchRow(
              title: l.twoPages,
              value: p['spread'] == true,
              onChanged: (v) => set('spread', v),
            ),
            if (!widget.capabilities.textMetrics)
              choices('zoom', l.zoom, [
                ('fit-page', l.fitPage),
                ('fit-width', l.fitWidth),
                ('.5', '50%'),
                ('.75', '75%'),
                ('1', '100%'),
                ('1.25', '125%'),
                ('1.5', '150%'),
                ('2', '200%'),
                ('3', '300%'),
              ]),
            if (widget.pdf)
              number('rotation', l.rotation, [
                0,
                90,
                180,
                270,
              ], (n) => '${n.toInt()}°'),
          ],
        ),
        if (widget.capabilities.textMetrics) ...[
          BusyBooksSwitchRow(
            title: l.moreTypography,
            value: advanced,
            onChanged: (v) => setState(() => advanced = v),
          ),
          if (advanced)
            BusyBooksGroupedList(
              children: [
                number(
                  'weight',
                  l.fontWeight,
                  [300, 400, 500, 600, 700],
                  (n) => switch (n.toInt()) {
                    300 => l.lightWeight,
                    400 => l.regular,
                    500 => l.mediumWeight,
                    600 => l.semibold,
                    700 => l.boldWeight,
                    _ => '${n.toInt()}',
                  },
                ),
                number('line', l.lineSpacing, [
                  1,
                  1.2,
                  1.4,
                  1.5,
                  1.6,
                  1.8,
                  2,
                  2.2,
                ], (n) => '$n×'),
                number('paragraph', l.paragraphSpacing, [
                  0,
                  .3,
                  .6,
                  .9,
                  1.2,
                  1.5,
                  2,
                ], (n) => '$n em'),
                number('margin', l.margins, [
                  0,
                  12,
                  20,
                  32,
                  48,
                  64,
                  80,
                ], (n) => '${n.toInt()} px'),
                number('width', l.readingWidth, [
                  400,
                  520,
                  640,
                  720,
                  840,
                  960,
                  1200,
                ], (n) => '${n.toInt()} px'),
                choices('align', l.alignment, [
                  ('start', l.start),
                  ('justify', l.justify),
                  ('center', l.center),
                ]),
                BusyBooksSwitchRow(
                  title: l.hyphenation,
                  value: p['hyphenate'] != false,
                  onChanged: (v) => set('hyphenate', v),
                ),
              ],
            ),
        ] else
          Padding(
            padding: const EdgeInsets.all(BusyBooksSpacing.sm),
            child: Text(
              l.fixedAppearanceHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        BusyBooksGroupedList(
          children: [
            if (!widget.defaults)
              BusyBooksActionRow(
                key: const ValueKey('appearance-save-defaults'),
                title: l.saveDefaults,
                onTap: () => _perform(widget.onSaveDefaults),
              ),
            BusyBooksActionRow(
              key: const ValueKey('appearance-reset'),
              title: widget.defaults ? l.reset : l.resetBook,
              onTap: () => _perform(widget.onReset),
            ),
          ],
        ),
        if (widget.capabilities.textMetrics)
          Padding(
            padding: const EdgeInsets.all(BusyBooksSpacing.sm),
            child: Text(
              l.generatedPages,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class AppearancePanel extends ConsumerStatefulWidget {
  const AppearancePanel({super.key, this.defaults = false});
  final bool defaults;
  @override
  ConsumerState<AppearancePanel> createState() => _AppearancePanelState();
}

class _AppearancePanelState extends ConsumerState<AppearancePanel> {
  String defaultsKey = 'reading';
  @override
  Widget build(BuildContext context) {
    ref.watch(readerControllerProvider);
    final settings = ref.watch(appSettingsControllerProvider);
    final reader = ref.read(readerControllerProvider.notifier),
        pdf = widget.defaults
            ? defaultsKey == 'pdfReading'
            : reader.book?.format == 'pdf',
        comic = widget.defaults
            ? defaultsKey == 'comicReading'
            : reader.regionNotes;
    final key = widget.defaults ? defaultsKey : reader.appearanceDefaultsKey;
    final p = widget.defaults
        ? (settings.data[key] as Map).cast<String, dynamic>()
        : reader.appearance;
    return Column(
      children: [
        if (widget.defaults)
          BusyBooksComboRow<String>(
            title: context.l10n.reading,
            values: const ['reading', 'pdfReading', 'comicReading'],
            selected: defaultsKey,
            labelFor: (v) => v == 'pdfReading'
                ? context.l10n.pdfDefaults
                : v == 'comicReading'
                ? context.l10n.comicDefaults
                : context.l10n.reflowableDefaults,
            onSelected: (v) => setState(() => defaultsKey = v),
          ),
        Expanded(
          child: ReadingAppearanceControls(
            preferences: p,
            capabilities: widget.defaults
                ? (pdf || comic
                      ? TypographyCapabilities.none
                      : TypographyCapabilities.reflowable)
                : reader.typographyCapabilities,
            fonts: ref.read(readingFontServiceProvider),
            pdf: pdf,
            comic: comic,
            defaults: widget.defaults,
            onChanged: (v) => widget.defaults
                ? ref
                      .read(appSettingsControllerProvider.notifier)
                      .updateReadingDefaults(key, {
                        ...(ref.read(appSettingsControllerProvider).data[key]
                            as Map),
                        ...v,
                      })
                : reader.setAppearance(v),
            onReset: () => widget.defaults
                ? ref
                      .read(appSettingsControllerProvider.notifier)
                      .updateReadingDefaults(
                        key,
                        pdf
                            ? defaultPdfAppearance
                            : comic
                            ? defaultComicAppearance
                            : defaultReadingAppearance,
                      )
                : reader.resetAppearance(),
            onSaveDefaults: () => reader.setAppearance({}, defaults: true),
          ),
        ),
      ],
    );
  }
}
