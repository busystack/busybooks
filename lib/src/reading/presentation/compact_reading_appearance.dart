import 'package:flutter/material.dart';

import '../../app/busybooks_design.dart';
import '../../app/localization.dart';
import '../../core/typography.dart';

/// Reading adjustments only. Advanced typography and defaults have their own
/// Settings presentation, sharing the existing preferences and write contract.
class CompactReadingAppearance extends StatefulWidget {
  const CompactReadingAppearance({
    super.key,
    required this.preferences,
    required this.capabilities,
    required this.pdf,
    required this.comic,
    required this.onChanged,
    required this.onMore,
  });
  final Map<String, dynamic> preferences;
  final TypographyCapabilities capabilities;
  final bool pdf, comic;
  final Future<void> Function(Map<String, dynamic>) onChanged;
  final Future<void> Function() onMore;
  @override
  State<CompactReadingAppearance> createState() =>
      _CompactReadingAppearanceState();
}

class _CompactReadingAppearanceState extends State<CompactReadingAppearance> {
  String? _error;
  Future<void> _set(String key, Object value) async {
    try {
      await widget.onChanged({
        key: value,
        if (['size', 'line'].contains(key)) 'publisher': false,
      });
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preferences, l = context.l10n;
    Widget number(
      String key,
      String label,
      List<num> choices,
      String Function(num) format,
    ) {
      final values = {...choices, if (p[key] is num) p[key] as num}.toList()
        ..sort();
      return BusyBooksComboRow<num>(
        title: label,
        values: values,
        selected: p[key] as num,
        labelFor: format,
        onSelected: (value) => _set(key, value),
      );
    }

    Widget choice(String key, String title, List<(String, String)> options) =>
        BusyBooksComboRow<String>(
          title: title,
          values: options.map((v) => v.$1).toList(),
          selected: p[key] as String,
          labelFor: (value) =>
              options.where((v) => v.$1 == value).firstOrNull?.$2 ?? value,
          onSelected: (value) => _set(key, value),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) BusyBooksBanner(title: '${l.writeFailed}\n$_error'),
        BusyBooksGroupedList(
          children: [
            if (!widget.comic)
              choice('color', l.pageColor, [
                ('system', l.system),
                ('light', l.light),
                ('dark', l.dark),
                ('sepia', l.sepia),
              ]),
            if (widget.capabilities.textMetrics) ...[
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
              ], (n) => '${n.toInt()} px'),
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
              number('width', l.readingWidth, [
                400,
                520,
                640,
                720,
                840,
                960,
                1200,
              ], (n) => '${n.toInt()} px'),
              number('margin', l.margins, [
                0,
                12,
                20,
                32,
                48,
                64,
                80,
              ], (n) => '${n.toInt()} px'),
              BusyBooksSwitchRow(
                title: l.publisher,
                value: p['publisher'] == true,
                onChanged: (value) => _set('publisher', value),
              ),
            ] else ...[
              choice('zoom', l.zoom, [
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
              BusyBooksSwitchRow(
                title: l.twoPages,
                value: p['spread'] == true,
                onChanged: (value) => _set('spread', value),
              ),
              if (widget.comic)
                choice('direction', l.readingDirection, [
                  ('auto', l.directionAuto),
                  ('ltr', l.directionLtr),
                  ('rtl', l.directionRtl),
                ]),
            ],
            BusyBooksActionRow(
              title: l.moreReadingSettings,
              onTap: widget.onMore,
            ),
          ],
        ),
      ],
    );
  }
}
