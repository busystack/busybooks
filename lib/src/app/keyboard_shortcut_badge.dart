// Adapted from BusyMark keyboard_shortcut_badge.dart (Apache-2.0).
import 'package:flutter/material.dart';
import 'busybooks_design.dart';

class BusyBooksKeyboardShortcutBadge extends StatelessWidget {
  const BusyBooksKeyboardShortcutBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = BusyBooksSurfaceColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.control,
        borderRadius: BorderRadius.circular(BusyBooksRadius.sm),
        border: Border.all(color: colors.subtleBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BusyBooksSpacing.sm,
          vertical: BusyBooksSpacing.xxs,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            // Let a narrow/scaled badge wrap between modifiers, rather than
            // splitting a name such as Shift. Identity never comes from text.
            label.replaceAll('+', '+\u200B'),
            semanticsLabel: label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontFamily: BusyBooksTypography.monoFontFamily,
              fontFamilyFallback: BusyBooksTypography.monoFontFamilyFallback,
              color: colors.foreground,
            ),
          ),
        ),
      ),
    );
  }
}
