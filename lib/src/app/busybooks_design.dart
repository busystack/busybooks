// Adapted from BusyMark (BusyStack, Apache-2.0); modified for BusyBooks.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yaru/yaru.dart';

import '../platform/gtk_header_icon_service.dart';
import '../platform/native_menu_service.dart';
import 'busybooks_glyphs.dart';
import 'path_label.dart';

/// Resolve an explicit six-digit RGB color chosen in a document/export control.
/// This does not inherit the application's theme accent.
Color busyBooksRgbHexColor(String value) {
  if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
    throw ArgumentError.value(value, 'value');
  }
  return Color(int.parse(value.substring(1), radix: 16) | 0xff000000);
}

abstract final class BusyBooksSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double headerInset = 6;
  static const double sm = 8;
  static const double smPlus = 10;
  static const double md = 12;
  static const double mdPlus = 14;
  static const double lg = 16;
  static const double lgPlus = 18;
  static const double xl = 24;
  static const double xxl = 32;
  static const double tooltipHorizontal = 10;
  static const double tooltipVertical = 6;
}

abstract final class BusyBooksRadius {
  static const double sm = 4;
  static const double tooltip = kYaruButtonRadius;
  static const double md = 8;
  static const double lg = kYaruContainerRadius;
  static const double headerButton = kYaruButtonRadius;
  // Compatibility name for sidebar callers; geometry remains Yaru-owned.
  static const double nativeHeaderButton = kYaruButtonRadius;
  static const double window = kYaruWindowRadius;
  static const double pill = 999;
}

abstract final class BusyBooksSizes {
  static const double contentWidth = 760;
  static const double documentContentWidth = contentWidth;
  static const double sidebarWidth = 300;
  // The workspace header also needs room for document actions and window controls.
  static const double workspaceSidebarBreakpoint = sidebarWidth + 480;
  static const double sidebarRowHeight = 36;
  static const double settingsWidth = 760;
  static const double settingsSidebarBreakpoint = sidebarWidth + 520;
  static const double toolbarHeight = kYaruTitleBarHeight;
  static const double paneHeaderHeight = 38;
  static const double documentStatusBarHeight = 28;
  static const double iconButton = kYaruTitleBarItemHeight;
  static const double compactIconButton = 24;
  static const double compactIcon = 13;
  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double tooltipMinHeight = 30;
  static const double previewMinWidth = 320;
  static const double modalMaxWidth = 860;
  static const double modalHorizontalInset = 40;
  static const double modalVerticalInset = 24;
  static const double modalMaxHeightFraction = 0.86;
  static const double dialog = 520;
  static const double dialogNarrow = 480;
  static const double dialogCompact = 460;
  static const double dialogWide = 560;
  static const double popupMenuMinWidth = 180;
  static const double editorContextMenuWidth = 260;
  static const double languagePopupMinWidth = 220;
  static const double languagePopupMaxWidth = 280;
  static const double languageButtonMaxWidth = 256;
  static const double aboutLogoViewport = 136;
  static const double aboutLogoAsset = 216;
  static const double sidebarSeparatorHeight = 22;
  // The surrounding hairline insets bring tree rows to the same outer height
  // as sidebar header controls.
  static const double sidebarTreeRowHeight =
      iconButton - BusyBooksStroke.hairline * 2;
  static const double sidebarTreeDepthBase = 4;
  static const double sidebarTreeDepthIndent = 14;
  static const double sidebarTreeControl = 18;
  static const double sidebarTreeArrow = 14;
  static const double problemsListWidth = 700;
  static const double problemsListHeight = 420;
  static const double sourceGutterWidth = 50;
  static const double sourceFoldButton = 16;
  static const double sourceFoldButtonRightInset = 1;
  static const double documentHeadingTop = 18;
  static const double documentHeadingBottom = 6;
  static const double documentListMarkerWidth = 28;
  static const double documentListMarkerTopInset = 0;
  static const double documentListIndent =
      documentListMarkerWidth + BusyBooksSpacing.sm;
  static const double documentImageMinWidth = 80;
  static const double documentImageMaxWidth = documentContentWidth;
  static const double documentImageMinHeight = iconButton;
  static const double previewInlineImageMaxHeight = 180;
  static const double previewInlineImageHeight = 96;
  static const double wysiwygToolbarReserve =
      iconButton + BusyBooksSpacing.xs * 2;
  static const double wysiwygToolbarClearance =
      BusyBooksSpacing.sm + wysiwygToolbarReserve + BusyBooksSpacing.sm;
  static const double wysiwygPrefixWidth = 30;
  static const double tableDialogWidth = 360;
  static const double tablePickerHeight = 224;
  static const double tableMinWidth = 360;
  static const double markerDot = 6;
  static const double listMarkerTopInset = 7;
  static const double thematicBreakHandleWidth = 44;
  static const double controlRowWidth = 256;
  static const double sliderRowWidth = 260;
  static const double toolbarPlacementRowWidth = 430;
  static const double settingsControlBreakpoint = 560;
  static const double toolbarPlacementBreakpoint = 620;
  static const int tableMinColumns = 1;
  static const int tableMaxColumns = 12;
  static const int tableMinRows = 1;
  static const int tableMaxRows = 50;
}

abstract final class BusyBooksFormLayout {
  static const double comboInlineMaxFraction = 0.46;
}

abstract final class BusyBooksElevation {
  static const double none = 0;
  static const double surface = 2;
}

abstract final class BusyBooksStroke {
  static const double hairline = 1;
  static const double tableGrid = 0.5;
  static const double focus = kYaruFocusBorderWidth;
  static const double sourceCursor = 1.4;
  static const double thematicBreak = 1.6;
}

abstract final class BusyBooksAlpha {
  static const double groupedRowLightHoverStrength = 0.50;
  static const double tooltipBackground = 0.80;
  static const double tooltipBorder = 0.10;
  static const double textSelection = 0.32;
  static const double sourceCollapsedLine = 0.045;
  static const double sourceCursor = 0.82;
  static const double sourceSyntaxBackground = 0.10;
  static const double syntaxCommentDark = 0.82;
  static const double syntaxCommentLight = 0.76;
  static const double previewHighlight = 0.24;
  static const double thematicBreak = 0.34;
  static const double thematicBreakHandle = 0.24;
  static const double thematicBreakSelected = 0.72;
}

/// Native libadwaita/Yaru shadow layers shared by grouped card surfaces.
abstract final class BusyBooksShadow {
  static List<BoxShadow> nativeCardShadows(Color semanticShadow) {
    Color layer(double opacity) {
      return semanticShadow.withValues(alpha: semanticShadow.a * opacity);
    }

    // ShapeDecoration paints later shadows over earlier ones. Keep the
    // perimeter last so the compact native edge remains above the broad layer.
    return [
      BoxShadow(
        color: layer(0.03),
        blurRadius: 6,
        spreadRadius: 2,
        offset: const Offset(0, 2),
      ),
      BoxShadow(
        color: layer(0.07),
        blurRadius: 3,
        spreadRadius: 1,
        offset: const Offset(0, 1),
      ),
      BoxShadow(color: layer(0.03), spreadRadius: 1),
    ];
  }

  static List<BoxShadow> nativeCardShadowsFor(BuildContext context) {
    final theme = Theme.of(context);
    return nativeCardShadows(
      CardTheme.of(context).shadowColor ?? theme.colorScheme.shadow,
    );
  }
}

abstract final class BusyBooksTypography {
  static const String fontFamily = 'Ubuntu';
  static const String monoFontFamily = 'Ubuntu Mono';
  static const List<String> fontFamilyFallback = [
    'Noto Sans Arabic',
    'Noto Sans',
    'DejaVu Sans',
  ];
  static const List<String> monoFontFamilyFallback = [
    'Noto Sans Arabic',
    'Noto Sans Mono',
    'DejaVu Sans Mono',
    'DejaVu Sans',
  ];
  static const double codeLineHeight = 1.45;
  static const double sourceEditorLineHeight = 1.6;
  static const double bodyLineHeight = 1.5;
  static const double defaultFontSize = 14;
  static const double tooltipFontSize = defaultFontSize;
  static const double sourceCursorHeightScale = 1.34;
  static const double sourceLineNumberScale = 0.92;
  static const double hiddenLayoutFontSize = 0.01;
  static const double hiddenLayoutHeight = 0.01;

  static double markdownHeadingScale(int level) {
    return switch (level) {
      1 => 1.55,
      2 => 1.36,
      3 => 1.22,
      4 => 1.10,
      5 => 1.08,
      _ => 1.06,
    };
  }

  static double markdownHeadingLineHeight(int level) {
    return switch (level) {
      1 => 1.20,
      2 => 1.23,
      3 => 1.28,
      4 => 1.37,
      5 => 1.39,
      _ => 1.42,
    };
  }
}

/// Keeps a known left-to-right value stable inside surrounding RTL text.
String busyBooksLtrIsolate(Object value) => '\u2066$value\u2069';

/// Isolates a machine value only when the surrounding interface is RTL.
String busyBooksLtrIsolateFor(BuildContext context, Object value) {
  return Directionality.maybeOf(context) == TextDirection.rtl
      ? busyBooksLtrIsolate(value)
      : value.toString();
}

/// Lets the first strong character choose direction without affecting neighbors.
String busyBooksBidiIsolate(Object value) => '\u2068$value\u2069';

/// Applies first-strong isolation only inside an RTL interface.
String busyBooksBidiIsolateFor(BuildContext context, Object value) {
  return Directionality.maybeOf(context) == TextDirection.rtl
      ? busyBooksBidiIsolate(value)
      : value.toString();
}

abstract final class BusyBooksMotion {
  static const Duration fast = Duration(milliseconds: 100);
  static const Duration sidebar = Duration(milliseconds: 200);
  static const Duration search = Duration(milliseconds: 160);
  static const Duration crossfade = Duration(milliseconds: 140);
  static const Curve presentationCurve = Curves.easeOutCubic;
  static const Duration dialogInsets = Duration(milliseconds: 160);
  static const Duration bannerReveal = Duration(milliseconds: 250);
  static const Duration sidebarExpand = Duration(milliseconds: 120);
  static const Duration scroll = Duration(milliseconds: 180);
  static const Duration previewSearchDelay = Duration(milliseconds: 80);
  static const Duration tooltipWait = Duration(milliseconds: 450);
  static const Curve dialogInsetsCurve = Curves.easeOutCubic;
  static const Curve bannerRevealCurve = Curves.easeOutCubic;
}

abstract final class BusyBooksInsets {
  static const input = EdgeInsets.symmetric(
    horizontal: BusyBooksSpacing.md,
    vertical: BusyBooksSpacing.smPlus,
  );
  static const listTile = EdgeInsets.symmetric(horizontal: BusyBooksSpacing.md);
  static const settingsPage = EdgeInsets.fromLTRB(
    BusyBooksSpacing.xl,
    BusyBooksSpacing.mdPlus,
    BusyBooksSpacing.xl,
    BusyBooksSpacing.xxl,
  );
  static const welcomePage = EdgeInsets.fromLTRB(
    BusyBooksSpacing.xl,
    BusyBooksSpacing.lgPlus,
    BusyBooksSpacing.xl,
    BusyBooksSpacing.xxl,
  );
  static const sidebarTabs = EdgeInsets.fromLTRB(
    BusyBooksSpacing.smPlus,
    0,
    BusyBooksSpacing.smPlus,
    BusyBooksSpacing.sm,
  );
  static const sidebarHeader = EdgeInsetsDirectional.fromSTEB(
    BusyBooksSpacing.mdPlus,
    BusyBooksSpacing.mdPlus,
    BusyBooksSpacing.sm,
    BusyBooksSpacing.sm - BusyBooksSpacing.xxs,
  );
  static const sidebarList = EdgeInsets.fromLTRB(
    BusyBooksSpacing.sm,
    BusyBooksSpacing.xxs,
    BusyBooksSpacing.sm,
    BusyBooksSpacing.smPlus,
  );
  static const tocHeader = EdgeInsetsDirectional.fromSTEB(
    0,
    0,
    0,
    BusyBooksSpacing.sm,
  );
  static const documentCodeBlock = EdgeInsets.symmetric(
    vertical: BusyBooksSpacing.sm,
  );
  static const documentCodeContent = EdgeInsets.all(BusyBooksSpacing.mdPlus);
  static const documentCalloutBlock = EdgeInsets.symmetric(
    vertical: BusyBooksSpacing.sm,
  );
  static const documentCalloutContent = EdgeInsets.all(BusyBooksSpacing.md);
  static const documentTableCell = EdgeInsets.all(BusyBooksSpacing.smPlus);
  static const sectionLabel = EdgeInsets.fromLTRB(
    BusyBooksSpacing.md,
    BusyBooksSpacing.mdPlus,
    BusyBooksSpacing.md,
    6,
  );
  static const documentHeadingBlock = EdgeInsets.only(
    top: BusyBooksSizes.documentHeadingTop,
    bottom: BusyBooksSizes.documentHeadingBottom,
  );
  static const documentParagraphBlock = EdgeInsets.symmetric(
    vertical: BusyBooksSizes.documentHeadingBottom,
  );
  static const documentImageBlock = EdgeInsets.symmetric(
    vertical: BusyBooksSpacing.smPlus,
  );
  static const documentThematicBreakBlock = EdgeInsets.symmetric(
    vertical: BusyBooksSpacing.mdPlus,
  );
  static const wysiwygContainerBlock = documentCalloutBlock;
  static const wysiwygTableBlock = EdgeInsets.symmetric(
    vertical: BusyBooksSpacing.md,
  );
  static const wysiwygDefaultBlock = EdgeInsets.symmetric(
    vertical: BusyBooksSpacing.xs,
  );
  static const wysiwygContainerContent = documentCalloutContent;
  static const sourceEditor = EdgeInsets.fromLTRB(
    BusyBooksSourceEditorMetrics.paddingLeft,
    BusyBooksSourceEditorMetrics.paddingTop,
    BusyBooksSourceEditorMetrics.paddingRight,
    BusyBooksSourceEditorMetrics.paddingBottom,
  );
  static const searchResultRow = EdgeInsets.symmetric(
    horizontal: BusyBooksSpacing.lg,
    vertical: BusyBooksSpacing.sm,
  );
}

abstract final class BusyBooksSourceEditorMetrics {
  static const double paddingTop = BusyBooksSpacing.lg;
  static const double paddingBottom = BusyBooksSpacing.lg;
  static const double paddingLeft = BusyBooksSpacing.md;
  static const double paddingRight = BusyBooksSpacing.lg;
}

abstract final class BusyBooksLinuxPalette {
  static Color fromArgb(int value) => Color(value);

  static const transparent = Color(0x00000000);
  static const white = Color(0xFFFFFFFF);
  static const blueAccent = Color(0xFF3584E4);
  static const ubuntuBlueAccent = Color(0xFF0073E5);
  static const ubuntuTealAccent = Color(0xFF2190A4);
  static const ubuntuGreenAccent = Color(0xFF3A944A);
  static const ubuntuYellowAccent = Color(0xFFC88800);
  static const ubuntuOrangeAccent = Color(0xFFED5B00);
  static const ubuntuRedAccent = Color(0xFFDA3450);
  static const ubuntuPinkAccent = Color(0xFFD56199);
  static const ubuntuPurpleAccent = Color(0xFF7764D8);
  static const ubuntuSlateAccent = Color(0xFF6F8396);
  static const ubuntuBrownAccent = Color(0xFF986A44);
  static const ubuntuMagentaAccent = Color(0xFFB34CB3);
  static const ubuntuOliveAccent = Color(0xFF4B8501);
  static const ubuntuPrussianGreenAccent = Color(0xFF308280);
  static const ubuntuSageAccent = Color(0xFF657B69);
  static const ubuntuWartyBrownAccent = Color(0xFFB39169);
  static const destructiveForegroundLight = Color(0xFFC30000);
  static const destructiveForegroundDark = Color(0xFFFF938C);
  static const red = Color(0xFFC01C28);
  static const yellow = Color(0xFFE5A50A);
  static const green = Color(0xFF2EC27E);
  static const light2 = Color(0xFFF6F5F4);
  static const light4 = Color(0xFFC0BFBC);
  static const dark4 = Color(0xFF242424);
  static const black = Color(0xFF000000);
}

/// Cross-toolkit tooltip visuals.
///
/// Flutter and the native GTK header bar render their own tooltip widgets.
/// Keeping the palette and shape here lets each toolkit retain its native
/// layout, positioning, focus, and motion while presenting the same surface.
abstract final class BusyBooksTooltipStyle {
  /// Place book-header hints beside their trigger, within Flutter's header.
  static Offset insideHeader(
    BuildContext context,
    TooltipPositionContext info,
  ) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null ||
        !box.hasSize ||
        !box.constraints.hasBoundedWidth ||
        !box.constraints.hasBoundedHeight) {
      return info.target;
    }
    final origin = box.localToGlobal(Offset.zero),
        left = origin.dx + BusyBooksSpacing.sm,
        right = origin.dx + box.constraints.maxWidth - BusyBooksSpacing.sm;
    final after =
        info.target.dx + info.targetSize.width / 2 + BusyBooksSpacing.sm;
    final before =
        info.target.dx -
        info.targetSize.width / 2 -
        BusyBooksSpacing.sm -
        info.tooltipSize.width;
    return Offset(
      (after + info.tooltipSize.width <= right ? after : before).clamp(
        left,
        math.max(left, right - info.tooltipSize.width),
      ),
      origin.dy +
          math.max(
            0,
            (box.constraints.maxHeight - info.tooltipSize.height) / 2,
          ),
    );
  }

  /// Keep sidebar tooltips inside their Flutter surface, above native content.
  static Offset positionWithin(
    BuildContext context,
    TooltipPositionContext info,
  ) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.constraints.hasBoundedWidth) {
      return info.target;
    }
    final left = box.localToGlobal(Offset.zero).dx + BusyBooksSpacing.sm;
    // The tooltip delegate runs during overlay layout; reading an unrelated
    // RenderBox.size there violates Flutter's layout ownership contract.
    final right = left + box.constraints.maxWidth - BusyBooksSpacing.sm * 2;
    return Offset(
      (info.target.dx - info.tooltipSize.width / 2).clamp(
        left,
        math.max(left, right - info.tooltipSize.width),
      ),
      (info.target.dy + info.verticalOffset).clamp(
        0.0,
        math.max(0.0, info.overlaySize.height - info.tooltipSize.height),
      ),
    );
  }

  static final Color background = BusyBooksLinuxPalette.black.withValues(
    alpha: BusyBooksAlpha.tooltipBackground,
  );
  static const Color foreground = BusyBooksLinuxPalette.white;
  static final Color border = BusyBooksLinuxPalette.white.withValues(
    alpha: BusyBooksAlpha.tooltipBorder,
  );
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: BusyBooksSpacing.tooltipHorizontal,
    vertical: BusyBooksSpacing.tooltipVertical,
  );
  static const BorderRadius borderRadius = BorderRadius.all(
    Radius.circular(BusyBooksRadius.tooltip),
  );
  static const BoxConstraints constraints = BoxConstraints(
    minHeight: BusyBooksSizes.tooltipMinHeight,
  );
}

/// Filled destructive actions use Yaru's dark red button treatment.
///
/// The dark theme's generic error role is intentionally a light tint with
/// black content, which is appropriate for error text but not for destructive
/// push buttons.
abstract final class BusyBooksDestructiveButtonStyle {
  static Color background(ThemeData theme) =>
      theme.brightness == Brightness.dark
      ? BusyBooksLinuxPalette.red
      : theme.colorScheme.error;

  static Color foreground(ThemeData theme) =>
      theme.brightness == Brightness.dark
      ? BusyBooksLinuxPalette.white
      : theme.colorScheme.onError;
}

Color busyBooksDestructiveForeground(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? BusyBooksLinuxPalette.destructiveForegroundDark
      : BusyBooksLinuxPalette.destructiveForegroundLight;
}

BusyBooksSurfaceColors _busyBooksSemanticSurfaceColors(Brightness brightness) {
  final window = switch (brightness) {
    Brightness.light => const Color(0xFFFAFAFA),
    Brightness.dark => const Color(0xFF2C2C2C),
  };
  final view = switch (brightness) {
    Brightness.light => const Color(0xFFFFFFFF),
    Brightness.dark => const Color(0xFF272727),
  };
  final floatingSurface = switch (brightness) {
    // Installed Yaru/libadwaita owns this neutral role independently from the
    // window and content-view elevation ladder.
    Brightness.light => const Color(0xFFFAFAFA),
    Brightness.dark => const Color(0xFF3E3E3E),
  };
  final foreground = switch (brightness) {
    Brightness.light => const Color(0xFF3D3D3D),
    Brightness.dark => const Color(0xFFF7F7F7),
  };
  // These colors are used by non-disabled 10–14 px labels. Keep them opaque so
  // their contrast is stable across every neutral surface instead of stacking
  // a dim-label alpha on whichever view happens to be underneath.
  final mutedForeground = switch (brightness) {
    Brightness.light => const Color(0xFF666666),
    Brightness.dark => const Color(0xFFB5B5B5),
  };
  final card = switch (brightness) {
    Brightness.light => const Color(0xFFFFFFFF),
    Brightness.dark => const Color(0xFF3D3D3D),
  };
  final groupedSurface = switch (brightness) {
    Brightness.light => const Color(0xFFFFFFFF),
    Brightness.dark => const Color.fromRGBO(255, 255, 255, 0.08),
  };
  // Yaru renders the split-view boundary as a recessed divider in both
  // brightness modes. A foreground tint in dark mode produces a light seam.
  final sidebarBorder = switch (brightness) {
    Brightness.light => const Color.fromRGBO(24, 24, 24, 0.08),
    Brightness.dark => const Color.fromRGBO(16, 16, 16, 0.35),
  };

  Color tintedSurface(Color tint) {
    final alpha = brightness == Brightness.dark ? 0.16 : 0.08;
    return Color.alphaBlend(tint.withValues(alpha: alpha), card);
  }

  return switch (brightness) {
    Brightness.light => BusyBooksSurfaceColors(
      // Modern Yaru/libadwaita semantic roles. Flutter's Yaru theme exposes
      // geometry and interaction behavior, but not every contemporary
      // surface role, so these neutral fallbacks live in one resolver.
      window: window,
      view: view,
      sidebar: const Color(0xFFEBEBEB),
      secondarySidebar: const Color(0xFFF0F0F0),
      headerbar: const Color(0xFFFAFAFA),
      headerbarFlat: const Color(0xFFFFFFFF),
      panel: const Color(0xFFF0F0F0),
      card: card,
      groupedSurface: groupedSurface,
      dialog: floatingSurface,
      popover: floatingSurface,
      control: const Color.fromRGBO(0, 0, 0, 0.10),
      controlHover: const Color.fromRGBO(0, 0, 0, 0.14),
      controlActive: const Color.fromRGBO(0, 0, 0, 0.18),
      foreground: foreground,
      mutedForeground: mutedForeground,
      disabledForeground: foreground.withValues(alpha: 0.38),
      disabledControl: const Color.fromRGBO(0, 0, 0, 0.04),
      border: const Color.fromRGBO(0, 0, 0, 0.18),
      subtleBorder: const Color.fromRGBO(0, 0, 0, 0.10),
      divider: const Color.fromRGBO(0, 0, 0, 0.10),
      cardShade: const Color.fromRGBO(24, 24, 24, 0.08),
      // Dialogs use libadwaita's restrained inside highlight. This is
      // intentionally distinct from the darker popover perimeter.
      dialogOutline: const Color.fromRGBO(255, 255, 255, 0.07),
      floatingBorder: const Color.fromRGBO(0, 0, 0, 0.14),
      sidebarBorder: sidebarBorder,
      shade: const Color.fromRGBO(0, 0, 0, 0.07),
      muted: mutedForeground,
      admonitionNote: tintedSurface(BusyBooksLinuxPalette.ubuntuBlueAccent),
      admonitionTip: tintedSurface(BusyBooksLinuxPalette.ubuntuGreenAccent),
      admonitionWarning: tintedSurface(
        BusyBooksLinuxPalette.ubuntuYellowAccent,
      ),
    ),
    Brightness.dark => BusyBooksSurfaceColors(
      window: window,
      view: view,
      sidebar: const Color(0xFF393939),
      secondarySidebar: const Color(0xFF323232),
      headerbar: const Color(0xFF393939),
      headerbarFlat: const Color(0xFF272727),
      panel: const Color(0xFF323232),
      card: card,
      groupedSurface: groupedSurface,
      dialog: floatingSurface,
      popover: floatingSurface,
      control: const Color.fromRGBO(255, 255, 255, 0.10),
      controlHover: const Color.fromRGBO(255, 255, 255, 0.14),
      controlActive: const Color.fromRGBO(255, 255, 255, 0.18),
      foreground: foreground,
      mutedForeground: mutedForeground,
      disabledForeground: foreground.withValues(alpha: 0.38),
      disabledControl: const Color.fromRGBO(255, 255, 255, 0.06),
      border: const Color.fromRGBO(0, 0, 0, 0.75),
      subtleBorder: const Color.fromRGBO(255, 255, 255, 0.10),
      divider: const Color.fromRGBO(255, 255, 255, 0.10),
      cardShade: const Color.fromRGBO(0, 0, 0, 0.36),
      dialogOutline: const Color.fromRGBO(255, 255, 255, 0.07),
      floatingBorder: const Color.fromRGBO(0, 0, 0, 0.14),
      sidebarBorder: sidebarBorder,
      shade: const Color.fromRGBO(0, 0, 0, 0.25),
      muted: mutedForeground,
      admonitionNote: tintedSurface(BusyBooksLinuxPalette.ubuntuBlueAccent),
      admonitionTip: tintedSurface(BusyBooksLinuxPalette.ubuntuGreenAccent),
      admonitionWarning: tintedSurface(
        BusyBooksLinuxPalette.ubuntuYellowAccent,
      ),
    ),
  };
}

@immutable
class BusyBooksSurfaceColors extends ThemeExtension<BusyBooksSurfaceColors> {
  const BusyBooksSurfaceColors({
    required this.window,
    required this.view,
    required this.sidebar,
    required this.secondarySidebar,
    required this.headerbar,
    required this.headerbarFlat,
    required this.panel,
    required this.card,
    required this.groupedSurface,
    required this.dialog,
    required this.popover,
    required this.control,
    required this.controlHover,
    required this.controlActive,
    required this.foreground,
    required this.mutedForeground,
    required this.disabledForeground,
    required this.disabledControl,
    required this.border,
    required this.subtleBorder,
    required this.divider,
    required this.cardShade,
    required this.dialogOutline,
    required this.floatingBorder,
    required this.sidebarBorder,
    required this.shade,
    required this.muted,
    required this.admonitionNote,
    required this.admonitionTip,
    required this.admonitionWarning,
  });

  factory BusyBooksSurfaceColors.fromTheme(ThemeData theme) {
    return _busyBooksSemanticSurfaceColors(theme.brightness);
  }

  static BusyBooksSurfaceColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<BusyBooksSurfaceColors>() ??
        BusyBooksSurfaceColors.fromTheme(theme);
  }

  final Color window;
  final Color view;
  final Color sidebar;
  final Color secondarySidebar;
  final Color headerbar;
  final Color headerbarFlat;
  final Color panel;
  final Color card;
  final Color groupedSurface;
  final Color dialog;
  final Color popover;
  final Color control;
  final Color controlHover;
  final Color controlActive;
  final Color foreground;
  final Color mutedForeground;
  final Color disabledForeground;
  final Color disabledControl;
  final Color border;
  final Color subtleBorder;
  final Color divider;
  final Color cardShade;
  final Color dialogOutline;
  final Color floatingBorder;
  final Color sidebarBorder;
  final Color shade;
  final Color muted;
  final Color admonitionNote;
  final Color admonitionTip;
  final Color admonitionWarning;

  @override
  BusyBooksSurfaceColors copyWith({
    Color? window,
    Color? view,
    Color? sidebar,
    Color? secondarySidebar,
    Color? headerbar,
    Color? headerbarFlat,
    Color? panel,
    Color? card,
    Color? groupedSurface,
    Color? dialog,
    Color? popover,
    Color? control,
    Color? controlHover,
    Color? controlActive,
    Color? foreground,
    Color? mutedForeground,
    Color? disabledForeground,
    Color? disabledControl,
    Color? border,
    Color? subtleBorder,
    Color? divider,
    Color? cardShade,
    Color? dialogOutline,
    Color? floatingBorder,
    Color? sidebarBorder,
    Color? shade,
    Color? muted,
    Color? admonitionNote,
    Color? admonitionTip,
    Color? admonitionWarning,
  }) {
    return BusyBooksSurfaceColors(
      window: window ?? this.window,
      view: view ?? this.view,
      sidebar: sidebar ?? this.sidebar,
      secondarySidebar: secondarySidebar ?? this.secondarySidebar,
      headerbar: headerbar ?? this.headerbar,
      headerbarFlat: headerbarFlat ?? this.headerbarFlat,
      panel: panel ?? this.panel,
      card: card ?? this.card,
      groupedSurface: groupedSurface ?? this.groupedSurface,
      dialog: dialog ?? this.dialog,
      popover: popover ?? this.popover,
      control: control ?? this.control,
      controlHover: controlHover ?? this.controlHover,
      controlActive: controlActive ?? this.controlActive,
      foreground: foreground ?? this.foreground,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      disabledForeground: disabledForeground ?? this.disabledForeground,
      disabledControl: disabledControl ?? this.disabledControl,
      border: border ?? this.border,
      subtleBorder: subtleBorder ?? this.subtleBorder,
      divider: divider ?? this.divider,
      cardShade: cardShade ?? this.cardShade,
      dialogOutline: dialogOutline ?? this.dialogOutline,
      floatingBorder: floatingBorder ?? this.floatingBorder,
      sidebarBorder: sidebarBorder ?? this.sidebarBorder,
      shade: shade ?? this.shade,
      muted: muted ?? this.muted,
      admonitionNote: admonitionNote ?? this.admonitionNote,
      admonitionTip: admonitionTip ?? this.admonitionTip,
      admonitionWarning: admonitionWarning ?? this.admonitionWarning,
    );
  }

  @override
  BusyBooksSurfaceColors lerp(
    covariant BusyBooksSurfaceColors? other,
    double t,
  ) {
    if (other == null) {
      return this;
    }
    return BusyBooksSurfaceColors(
      window: Color.lerp(window, other.window, t)!,
      view: Color.lerp(view, other.view, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      secondarySidebar: Color.lerp(
        secondarySidebar,
        other.secondarySidebar,
        t,
      )!,
      headerbar: Color.lerp(headerbar, other.headerbar, t)!,
      headerbarFlat: Color.lerp(headerbarFlat, other.headerbarFlat, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      card: Color.lerp(card, other.card, t)!,
      groupedSurface: Color.lerp(groupedSurface, other.groupedSurface, t)!,
      dialog: Color.lerp(dialog, other.dialog, t)!,
      popover: Color.lerp(popover, other.popover, t)!,
      control: Color.lerp(control, other.control, t)!,
      controlHover: Color.lerp(controlHover, other.controlHover, t)!,
      controlActive: Color.lerp(controlActive, other.controlActive, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      mutedForeground: Color.lerp(mutedForeground, other.mutedForeground, t)!,
      disabledForeground: Color.lerp(
        disabledForeground,
        other.disabledForeground,
        t,
      )!,
      disabledControl: Color.lerp(disabledControl, other.disabledControl, t)!,
      border: Color.lerp(border, other.border, t)!,
      subtleBorder: Color.lerp(subtleBorder, other.subtleBorder, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      cardShade: Color.lerp(cardShade, other.cardShade, t)!,
      dialogOutline: Color.lerp(dialogOutline, other.dialogOutline, t)!,
      floatingBorder: Color.lerp(floatingBorder, other.floatingBorder, t)!,
      sidebarBorder: Color.lerp(sidebarBorder, other.sidebarBorder, t)!,
      shade: Color.lerp(shade, other.shade, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      admonitionNote: Color.lerp(admonitionNote, other.admonitionNote, t)!,
      admonitionTip: Color.lerp(admonitionTip, other.admonitionTip, t)!,
      admonitionWarning: Color.lerp(
        admonitionWarning,
        other.admonitionWarning,
        t,
      )!,
    );
  }
}

ButtonStyle busyBooksHeaderIconButtonStyle({
  Color? foregroundColor,
  Color? disabledForegroundColor,
  WidgetStateProperty<Color?>? backgroundColor,
  WidgetStateProperty<Color?>? overlayColor,
  double borderRadius = BusyBooksRadius.headerButton,
}) {
  return ButtonStyle(
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    foregroundColor: foregroundColor == null
        ? null
        : WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled) &&
                disabledForegroundColor != null) {
              return disabledForegroundColor;
            }
            return foregroundColor;
          }),
    backgroundColor: backgroundColor,
    overlayColor: overlayColor,
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
    ),
  );
}

WidgetStateProperty<Color?> busyBooksHeaderButtonBackground(
  BuildContext context,
) {
  return Theme.of(context).filledButtonTheme.style?.backgroundColor ??
      WidgetStatePropertyAll(BusyBooksSurfaceColors.of(context).control);
}

/// Resolves a contained control state against its semantic host surface.
///
/// Yaru control fills are translucent state layers, which is appropriate when
/// a parent control surface owns the background. Free-floating controls, such
/// as the editing toolbar over a document, have no such parent and must resolve
/// that layer once so document content cannot show through the button.
WidgetStateProperty<Color?> busyBooksContainedControlBackground(
  BuildContext context, {
  required Color surface,
}) {
  final background = busyBooksHeaderButtonBackground(context);
  return WidgetStateProperty.resolveWith((states) {
    final stateColor = background.resolve(states);
    return stateColor == null ? null : Color.alphaBlend(stateColor, surface);
  });
}

WidgetStateProperty<Color?> busyBooksTransparentHeaderButtonBackground(
  BuildContext _,
) {
  return const WidgetStatePropertyAll(BusyBooksLinuxPalette.transparent);
}

Color busyBooksSelectedBackground(BuildContext context) {
  return BusyBooksSurfaceColors.of(context).controlActive;
}

Color busyBooksRowHoverColor(BuildContext context) {
  final theme = Theme.of(context);
  final hover = theme.hoverColor;
  if (theme.colorScheme.isHighContrast ||
      theme.colorScheme.brightness == Brightness.dark) {
    return hover;
  }
  return hover.withValues(
    alpha: hover.a * BusyBooksAlpha.groupedRowLightHoverStrength,
  );
}

TextStyle? busyBooksSectionHeaderStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.bodyMedium?.copyWith(
    color: BusyBooksSurfaceColors.of(context).foreground,
    fontWeight: FontWeight.w700,
  );
}

Widget _busyBooksGroupedRowSubtitle(
  BuildContext context,
  Widget child, {
  bool enabled = true,
}) {
  final colors = BusyBooksSurfaceColors.of(context);
  return DefaultTextStyle.merge(
    style: TextStyle(
      color: enabled ? colors.mutedForeground : colors.disabledForeground,
    ),
    child: child,
  );
}

class BusyBooksHeaderControlStyleScope extends InheritedWidget {
  const BusyBooksHeaderControlStyleScope({
    super.key,
    required this.foregroundColor,
    required this.disabledForegroundColor,
    required this.backgroundColor,
    required this.overlayColor,
    this.tooltipPositionDelegate,
    required super.child,
  });

  final Color foregroundColor;
  final Color disabledForegroundColor;
  final WidgetStateProperty<Color?> backgroundColor;
  final WidgetStateProperty<Color?> overlayColor;
  final TooltipPositionDelegate? tooltipPositionDelegate;

  static BusyBooksHeaderControlStyleScope? maybeOf(
    BuildContext context,
  ) => context
      .dependOnInheritedWidgetOfExactType<BusyBooksHeaderControlStyleScope>();

  @override
  bool updateShouldNotify(BusyBooksHeaderControlStyleScope oldWidget) =>
      foregroundColor != oldWidget.foregroundColor ||
      disabledForegroundColor != oldWidget.disabledForegroundColor ||
      backgroundColor != oldWidget.backgroundColor ||
      overlayColor != oldWidget.overlayColor ||
      tooltipPositionDelegate != oldWidget.tooltipPositionDelegate;
}

class BusyBooksHeaderIconButton extends StatelessWidget {
  const BusyBooksHeaderIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.nativeIcon,
    this.selected = false,
    this.accented = false,
    this.transparent = true,
    this.elevated = false,
    this.shortcut,
    this.foregroundColor,
    this.disabledForegroundColor,
    this.backgroundColor,
    this.overlayColor,
    this.borderRadius = BusyBooksRadius.headerButton,
    this.tooltipPositionDelegate,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final BusyBooksLinuxHeaderIcon? nativeIcon;
  final bool selected;
  final bool accented;
  final bool transparent;

  /// Uses the theme's physical button elevation without drawing a custom
  /// shadow surface around the control.
  final bool elevated;
  final String? shortcut;
  final Color? foregroundColor;
  final Color? disabledForegroundColor;
  final WidgetStateProperty<Color?>? backgroundColor;
  final WidgetStateProperty<Color?>? overlayColor;
  final double borderRadius;
  final TooltipPositionDelegate? tooltipPositionDelegate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colors = BusyBooksSurfaceColors.of(context);
    final controlStyle = BusyBooksHeaderControlStyleScope.maybeOf(context),
        inheritedStyle = accented ? null : controlStyle,
        tooltipPosition =
            tooltipPositionDelegate ?? controlStyle?.tooltipPositionDelegate;
    final semanticStyle = busyBooksHeaderIconButtonStyle(
      foregroundColor:
          foregroundColor ??
          (accented ? colorScheme.onPrimary : inheritedStyle?.foregroundColor),
      disabledForegroundColor:
          disabledForegroundColor ??
          inheritedStyle?.disabledForegroundColor ??
          colors.disabledForeground,
      backgroundColor:
          backgroundColor ??
          (accented
              ? WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return colors.disabledControl;
                  }
                  return colorScheme.primary;
                })
              : inheritedStyle?.backgroundColor ??
                    (elevated || !transparent
                        ? busyBooksHeaderButtonBackground(context)
                        : null)),
      overlayColor: overlayColor ?? inheritedStyle?.overlayColor,
      borderRadius: borderRadius,
    );
    final style = elevated
        ? semanticStyle.copyWith(
            elevation: WidgetStatePropertyAll(
              theme.cardTheme.elevation ?? BusyBooksElevation.surface,
            ),
            shadowColor: WidgetStatePropertyAll(colorScheme.shadow),
            surfaceTintColor: const WidgetStatePropertyAll(
              BusyBooksLinuxPalette.transparent,
            ),
          )
        : semanticStyle;
    // YaruIconButton merges its defaults as the receiver, so non-null default
    // colors win over caller-supplied semantic colors. Compose the styles in
    // the opposite direction and give the result directly to IconButton.
    final yaruDefaults = YaruIconButton(
      icon: const SizedBox.shrink(),
      iconSize: BusyBooksSizes.iconButton,
    ).defaultStyleOf(context);
    final button = IconButton(
      isSelected: selected,
      tooltip: tooltipPosition == null
          ? (shortcut == null ? tooltip : '$tooltip ($shortcut)')
          : null,
      // Native accessibility bridges do not consistently expose tooltip
      // metadata as a name. Label the artwork inside the button's semantics.
      icon: Semantics(
        label: tooltip,
        child: BusyBooksGtkHeaderIcon(icon, nativeIcon: nativeIcon),
      ),
      padding: EdgeInsets.zero,
      style: style.merge(yaruDefaults),
      onPressed: onPressed,
    );
    final labeledButton = tooltipPosition == null
        ? button
        : Tooltip(
            message: shortcut == null ? tooltip : '$tooltip ($shortcut)',
            positionDelegate: tooltipPosition,
            child: button,
          );
    return YaruTheme.maybeOf(context)?.focusBorders == true
        ? YaruFocusBorder.primary(
            borderRadius: BorderRadius.circular(BusyBooksRadius.pill),
            child: labeledButton,
          )
        : labeledButton;
  }
}

/// A compact icon action that keeps Yaru's interaction and focus behavior.
///
/// Compact controls are appropriate inside dense editor affordances, where a
/// full title-bar item would consume too much document space.
class BusyBooksCompactIconButton extends StatelessWidget {
  const BusyBooksCompactIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.size = BusyBooksSizes.compactIconButton,
    this.glyphSize = BusyBooksSizes.compactIcon,
    this.foregroundColor,
    this.focusNode,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double glyphSize;
  final Color? foregroundColor;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final colors = BusyBooksSurfaceColors.of(context);
    final semanticStyle = ButtonStyle(
      foregroundColor: foregroundColor == null
          ? null
          : WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return colors.disabledForeground;
              }
              return foregroundColor;
            }),
    );
    final yaruDefaults = YaruIconButton(
      icon: const SizedBox.shrink(),
      iconSize: size,
    ).defaultStyleOf(context);
    final button = IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: glyphSize, semanticLabel: tooltip),
      constraints: BoxConstraints.tightFor(width: size, height: size),
      padding: EdgeInsets.zero,
      style: semanticStyle.merge(yaruDefaults),
      focusNode: focusNode,
      onPressed: onPressed,
    );
    return YaruTheme.maybeOf(context)?.focusBorders == true
        ? YaruFocusBorder.primary(
            borderRadius: BorderRadius.circular(BusyBooksRadius.pill),
            child: button,
          )
        : button;
  }
}

class BusyBooksHeaderPopupMenuButton<T> extends StatefulWidget {
  const BusyBooksHeaderPopupMenuButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.itemBuilder,
    required this.onSelected,
    this.onCanceled,
    this.onError,
    this.transparent = true,
    this.elevated = false,
    this.shortcut,
    this.foregroundColor,
    this.backgroundColor,
    this.borderRadius = BusyBooksRadius.headerButton,
    this.highlightWhenOpen = true,
    this.nativeMenuService = const NativeMenuService(),
    this.tooltipPositionDelegate,
  });

  final String tooltip;
  final IconData icon;
  final FutureOr<List<PopupMenuEntry<T>>> Function(BuildContext context)
  itemBuilder;
  final FutureOr<void> Function(T) onSelected;
  final FutureOr<void> Function(Object)? onError;
  final VoidCallback? onCanceled;
  final bool transparent;

  /// Uses the theme's physical button elevation.
  final bool elevated;
  final String? shortcut;
  final Color? foregroundColor;
  final WidgetStateProperty<Color?>? backgroundColor;
  final double borderRadius;
  final bool highlightWhenOpen;
  final NativeMenuService nativeMenuService;
  final TooltipPositionDelegate? tooltipPositionDelegate;

  @override
  State<BusyBooksHeaderPopupMenuButton<T>> createState() =>
      _BusyBooksHeaderPopupMenuButtonState<T>();
}

class _BusyBooksHeaderPopupMenuButtonState<T>
    extends State<BusyBooksHeaderPopupMenuButton<T>> {
  final _triggerKey = GlobalKey();
  BusyBooksMenuSession? _activeMenuSession;
  var _loading = false;
  var _open = false;

  @override
  void dispose() {
    final session = _activeMenuSession;
    _activeMenuSession = null;
    if (session != null) {
      unawaited(session.dismiss());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _triggerKey,
      child: Semantics(
        expanded: _open,
        child: BusyBooksHeaderIconButton(
          tooltip: widget.tooltip,
          tooltipPositionDelegate: widget.tooltipPositionDelegate,
          icon: widget.icon,
          shortcut: widget.shortcut,
          selected: widget.highlightWhenOpen && (_loading || _open),
          transparent: widget.transparent,
          elevated: widget.elevated,
          foregroundColor: widget.foregroundColor,
          backgroundColor: widget.backgroundColor,
          borderRadius: widget.borderRadius,
          onPressed: _loadAndShowMenu,
        ),
      ),
    );
  }

  Future<void> _loadAndShowMenu() async {
    if (_loading || _open) {
      return;
    }
    setState(() => _loading = true);
    // A menu response belongs to the context in which it was opened. A
    // rebuilt caller may now represent another buffer or element.
    final onSelected = widget.onSelected;
    final onCanceled = widget.onCanceled;
    final onError = widget.onError;
    try {
      final items = await widget.itemBuilder(context);
      if (!mounted) return;
      if (items.isEmpty) throw StateError('The menu has no available items.');
      final triggerContext = _triggerKey.currentContext;
      if (triggerContext == null || !triggerContext.mounted) {
        return;
      }
      final session = BusyBooksMenuSession();
      _activeMenuSession = session;
      setState(() => _open = true);
      T? selection;
      try {
        selection = await showBusyBooksMenu<T>(
          context: triggerContext,
          anchorContext: triggerContext,
          items: List.unmodifiable(items),
          nativeMenuService: widget.nativeMenuService,
          session: session,
        );
      } finally {
        if (mounted && identical(_activeMenuSession, session)) {
          setState(() {
            _activeMenuSession = null;
            _open = false;
          });
        }
      }
      if (mounted && !session.dismissed) {
        if (selection != null) {
          await onSelected(selection);
        } else {
          onCanceled?.call();
        }
      }
    } catch (error) {
      if (!mounted) return;
      if (onError == null) rethrow;
      await onError(error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}

/// Owns one native or Flutter fallback menu presentation.
final class BusyBooksMenuSession {
  BusyBooksMenuSession() : _nativeSession = NativeMenuSession();

  final NativeMenuSession _nativeSession;
  final GlobalKey _fallbackRouteKey = GlobalKey();
  NativeMenuService _nativeMenuService = const NativeMenuService();
  Route<dynamic>? _fallbackRoute;
  var _started = false;
  var _dismissed = false;

  bool get dismissed => _dismissed;

  Future<void> dismiss() async {
    if (_dismissed) {
      return;
    }
    _dismissed = true;
    _removeFallbackRoute();
    await _nativeMenuService.dismiss(_nativeSession);
  }

  void _beginPresentation(NativeMenuService nativeMenuService) {
    if (_started) {
      throw StateError('A BusyBooksMenuSession can present only one menu.');
    }
    _started = true;
    _nativeMenuService = nativeMenuService;
  }

  void _captureFallbackRoute() {
    final routeContext = _fallbackRouteKey.currentContext;
    final route = routeContext == null ? null : ModalRoute.of(routeContext);
    if (route == null) {
      return;
    }
    _fallbackRoute = route;
    if (_dismissed) {
      _removeFallbackRoute();
    }
  }

  void _releaseFallbackRoute() {
    _fallbackRoute = null;
  }

  void _removeFallbackRoute() {
    final route = _fallbackRoute;
    final navigator = route?.navigator;
    if (route != null && navigator != null && route.isActive) {
      navigator.removeRoute(route);
    }
    _fallbackRoute = null;
  }
}

/// Chooses the available menu host for an owned Flutter view.
class BusyBooksMenuHostScope extends InheritedWidget {
  const BusyBooksMenuHostScope({
    super.key,
    required this.service,
    required super.child,
  });
  final NativeMenuService service;
  @override
  bool updateShouldNotify(BusyBooksMenuHostScope oldWidget) =>
      service != oldWidget.service;
}

/// Presents menus, including nested submenus, through the desktop toolkit.
/// A themed fallback is only used when no native host is available.
Future<T?> showBusyBooksMenu<T>({
  required BuildContext context,
  required List<PopupMenuEntry<T>> items,
  BuildContext? anchorContext,
  Offset? anchorPoint,
  Rect? anchorRect,
  NativeMenuService nativeMenuService = const NativeMenuService(),
  BusyBooksMenuSession? session,
  bool focusFirst = false,
  bool preferAbove = false,
  double? width,
}) async {
  assert(
    anchorRect == null || (anchorContext == null && anchorPoint == null),
    'anchorRect cannot be combined with anchorContext or anchorPoint.',
  );
  if (items.isEmpty) {
    return null;
  }
  final itemSnapshot = List<PopupMenuEntry<T>>.unmodifiable(items);
  final presentation = session ?? BusyBooksMenuSession();
  if (presentation.dismissed) {
    return null;
  }
  final menuHost =
      context
          .dependOnInheritedWidgetOfExactType<BusyBooksMenuHostScope>()
          ?.service ??
      nativeMenuService;
  presentation._beginPresentation(menuHost);
  final anchor =
      anchorRect ??
      _busyBooksMenuAnchorRect(anchorContext ?? context, anchorPoint);
  final iconSize =
      (BusyBooksSizes.iconSm * MediaQuery.devicePixelRatioOf(context))
          .round()
          .clamp(16, 64);
  final nativeEntries = await _busyBooksNativeMenuEntries(
    itemSnapshot,
    iconSize: iconSize,
  );
  if (!context.mounted || presentation.dismissed) return null;
  if (nativeEntries != null) {
    final nativeResult = await menuHost.show(
      session: presentation._nativeSession,
      anchor: anchor,
      entries: nativeEntries,
      focusFirst: focusFirst,
      preferAbove: preferAbove,
      textDirection: Directionality.of(context),
    );
    if (presentation.dismissed) {
      return null;
    }
    if (nativeResult.available) {
      return _busyBooksMenuValueAt(itemSnapshot, nativeResult.selectedIndex);
    }
  }
  if (!context.mounted) {
    return null;
  }
  if (itemSnapshot.any((item) => item is BusyBooksSubmenuItem<T>)) {
    final navigator = Navigator.of(context, rootNavigator: true);
    if (!navigator.mounted || navigator.overlay?.mounted != true) return null;
    final previousFocus = FocusManager.instance.primaryFocus;
    final overlay = navigator.overlay?.context.findRenderObject();
    final localAnchor = overlay is RenderBox
        ? Rect.fromPoints(
            overlay.globalToLocal(anchor.topLeft),
            overlay.globalToLocal(anchor.bottomRight),
          )
        : anchor;
    final route = _BusyBooksNestedMenuRoute<T>(
      anchor: localAnchor,
      items: itemSnapshot,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      direction: Directionality.of(context),
      focusFirst: focusFirst,
      routeKey: presentation._fallbackRouteKey,
      dismissLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    );
    final result = navigator.push<T>(route);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => presentation._captureFallbackRoute(),
    );
    try {
      final value = await result;
      return presentation.dismissed ? null : value;
    } finally {
      presentation._releaseFallbackRoute();
      if (previousFocus?.context?.mounted == true) {
        previousFocus!.requestFocus();
      }
    }
  }
  final selection = await _showBusyBooksFallbackMenu<T>(
    context: context,
    anchor: anchor,
    items: itemSnapshot,
    session: presentation,
    width: width,
  );
  return presentation.dismissed ? null : selection;
}

Rect _busyBooksMenuAnchorRect(BuildContext anchorContext, Offset? anchorPoint) {
  if (anchorPoint != null) {
    return Rect.fromLTWH(anchorPoint.dx, anchorPoint.dy, 0, 0);
  }
  final renderObject = anchorContext.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) {
    return Rect.zero;
  }
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

Future<List<NativeMenuEntry>?> _busyBooksNativeMenuEntries<T>(
  List<PopupMenuEntry<T>> items, {
  required int iconSize,
}) async {
  final entries = <NativeMenuEntry>[];
  for (final item in items) {
    if (item is BusyBooksPopupMenuItem<T>) {
      final useMask =
          defaultTargetPlatform == TargetPlatform.windows &&
          (item.icon == BusyBooksGlyphs.previewView ||
              item.icon == BusyBooksGlyphs.notebookView);
      final mask = useMask
          ? await _busyBooksMenuIconMask(item.icon!, iconSize)
          : null;
      entries.add(
        NativeMenuEntry.command(
          label: item.label,
          iconName: BusyBooksGlyphs.nativeMenuIconName(item.icon),
          iconMask: mask,
          iconSize: mask == null ? null : iconSize,
          iconColorArgb: item.iconColor?.toARGB32(),
          shortcut: item.shortcut,
          gtkAccelerator: item.gtkAccelerator,
          enabled: item.enabled,
          checkable: item.trailingCheck,
          selected: item.trailingCheck && item.checked,
          mutuallyExclusive: item.mutuallyExclusive,
        ),
      );
    } else if (item is BusyBooksSubmenuItem<T>) {
      final children = await _busyBooksNativeMenuEntries(
        item.items,
        iconSize: iconSize,
      );
      if (children == null) return null;
      entries.add(
        NativeMenuEntry.submenu(
          label: item.label,
          enabled: item.enabled,
          children: children,
        ),
      );
    } else if (item is PopupMenuDivider) {
      entries.add(const NativeMenuEntry.separator());
    } else {
      return null;
    }
  }
  return entries;
}

// Rasterize existing font artwork only; no new icon files or renderer access.
Future<Uint8List> _busyBooksMenuIconMask(IconData glyph, int size) async {
  final recorder = ui.PictureRecorder();
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(glyph.codePoint),
      style: TextStyle(
        fontFamily: glyph.fontFamily,
        package: glyph.fontPackage,
        fontSize: size.toDouble(),
        height: 1,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(
    Canvas(recorder),
    Offset((size - painter.width) / 2, (size - painter.height) / 2),
  );
  painter.dispose();
  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(size, size);
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (pixels == null) {
      throw StateError('The menu icon could not be prepared.');
    }
    return Uint8List.fromList([
      for (var i = 3; i < pixels.lengthInBytes; i += 4) pixels.getUint8(i),
    ]);
  } finally {
    image?.dispose();
    picture.dispose();
  }
}

T? _busyBooksMenuValueAt<T>(List<PopupMenuEntry<T>> items, int? index) {
  if (index == null || index < 0) return null;
  // GTK and Dart use the same preorder, including headings and separators.
  // Only enabled leaves (with enabled ancestors) can return an action.
  var position = 0;
  T? visit(List<PopupMenuEntry<T>> entries, bool ancestorsEnabled) {
    for (final item in entries) {
      final current = position++;
      if (item is BusyBooksSubmenuItem<T>) {
        final value = visit(item.items, ancestorsEnabled && item.enabled);
        if (value != null) return value;
      } else if (current == index &&
          ancestorsEnabled &&
          item is BusyBooksPopupMenuItem<T> &&
          item.enabled) {
        return item.menuValue;
      }
    }
    return null;
  }

  return visit(items, true);
}

double _busyBooksMenuTextWidth(
  BuildContext context,
  String text,
  TextStyle? style,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

double? _busyBooksFallbackMenuWidth<T>(
  BuildContext context,
  List<PopupMenuEntry<T>> items,
  double? preferred,
  double available,
) {
  final theme = Theme.of(context),
      labelStyle =
          theme.popupMenuTheme.labelTextStyle?.resolve({}) ??
          theme.popupMenuTheme.textStyle ??
          theme.textTheme.labelLarge;
  var width = preferred ?? BusyBooksSizes.popupMenuMinWidth;
  for (final entry in items) {
    if (entry is! BusyBooksPopupMenuItem<T>) {
      if (entry is! PopupMenuDivider) return preferred;
      continue;
    }
    var content =
        _busyBooksMenuTextWidth(context, entry.label, labelStyle) +
        BusyBooksSpacing.md * 2;
    if (entry.icon != null) {
      content += BusyBooksSizes.iconSm + BusyBooksSpacing.sm;
    }
    if (entry.shortcut case final String shortcut) {
      content +=
          BusyBooksSpacing.sm +
          _busyBooksMenuTextWidth(
            context,
            shortcut,
            theme.textTheme.labelSmall,
          );
    }
    if (entry.trailingCheck) {
      content += BusyBooksSpacing.sm + BusyBooksSizes.iconSm;
    }
    width = math.max(width, content);
  }
  return width.clamp(1, math.max(1, available - BusyBooksSpacing.sm * 2));
}

Future<T?> _showBusyBooksFallbackMenu<T>({
  required BuildContext context,
  required Rect anchor,
  required List<PopupMenuEntry<T>> items,
  required BusyBooksMenuSession session,
  required double? width,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = navigator.overlay?.context.findRenderObject();
  if (overlay is! RenderBox || !overlay.hasSize) {
    return null;
  }
  final localAnchor = Rect.fromPoints(
    overlay.globalToLocal(anchor.topLeft),
    overlay.globalToLocal(anchor.bottomRight),
  );
  final menuAnchor = Rect.fromLTWH(
    localAnchor.left,
    localAnchor.bottom,
    localAnchor.width,
    0,
  );
  final fallbackItems = _busyBooksFallbackItems(
    items,
    session._fallbackRouteKey,
  );
  final selection = showMenu<T>(
    context: context,
    useRootNavigator: true,
    position: RelativeRect.fromRect(menuAnchor, Offset.zero & overlay.size),
    items: fallbackItems,
    constraints: switch (_busyBooksFallbackMenuWidth(
      context,
      items,
      width,
      overlay.size.width,
    )) {
      final double measured => BoxConstraints.tightFor(width: measured),
      _ => null,
    },
    requestFocus: true,
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    session._captureFallbackRoute();
  });
  try {
    return await selection;
  } finally {
    session._releaseFallbackRoute();
  }
}

List<PopupMenuEntry<T>> _busyBooksFallbackItems<T>(
  List<PopupMenuEntry<T>> items,
  GlobalKey routeKey,
) {
  final fallbackItems = <PopupMenuEntry<T>>[];
  var routeKeyPending = true;
  for (final item in items) {
    if (item is BusyBooksPopupMenuItem<T>) {
      fallbackItems.add(
        BusyBooksPopupMenuItem<T>(
          value: item.menuValue,
          label: item.label,
          icon: item.icon,
          iconColor: item.iconColor,
          shortcut: item.shortcut,
          enabled: item.enabled,
          checked: item.checked,
          trailingCheck: item.trailingCheck,
          mutuallyExclusive: item.mutuallyExclusive,
          routeKey: routeKeyPending ? routeKey : null,
        ),
      );
      routeKeyPending = false;
    } else {
      fallbackItems.add(item);
    }
  }
  return fallbackItems;
}

/// Shows a BusyBooks context menu at a global pointer position.
///
/// The menu opens away from the pointer's reading-direction edge and stays
/// inside the root overlay. Use [BusyBooksPopupMenuItem] entries to keep menu
/// rows consistent with the rest of the application.
Future<T?> showBusyBooksContextMenu<T>(
  BuildContext context,
  Offset globalPosition, {
  required List<PopupMenuEntry<T>> items,
  double width = BusyBooksSizes.popupMenuMinWidth,
}) {
  if (items.isEmpty) {
    return Future<T?>.value();
  }
  return showBusyBooksMenu<T>(
    context: context,
    anchorPoint: globalPosition,
    items: items,
    width: width,
  );
}

/// A real nested menu; its label is never a selectable command.
class BusyBooksSubmenuItem<T> extends PopupMenuEntry<T> {
  const BusyBooksSubmenuItem({
    super.key,
    required this.label,
    required this.items,
    this.enabled = true,
  });
  final String label;
  final List<PopupMenuEntry<T>> items;
  final bool enabled;
  @override
  double get height => kMinInteractiveDimension;
  @override
  bool represents(T? value) => false;
  @override
  State<BusyBooksSubmenuItem<T>> createState() =>
      _BusyBooksSubmenuItemState<T>();
}

class _BusyBooksSubmenuItemState<T> extends State<BusyBooksSubmenuItem<T>> {
  @override
  Widget build(BuildContext context) => Text(widget.label);
}

class _BusyBooksNestedMenuRoute<T> extends PopupRoute<T> {
  _BusyBooksNestedMenuRoute({
    required this.anchor,
    required this.items,
    required this.themes,
    required this.direction,
    required this.routeKey,
    required this.dismissLabel,
    required this.focusFirst,
  });
  final bool focusFirst;
  final Rect anchor;
  final List<PopupMenuEntry<T>> items;
  final CapturedThemes themes;
  final TextDirection direction;
  final GlobalKey routeKey;
  final String dismissLabel;
  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => dismissLabel;
  @override
  Duration get transitionDuration => Duration.zero;
  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => themes.wrap(
    Directionality(
      textDirection: direction,
      child: _BusyBooksNestedMenu<T>(route: this),
    ),
  );
}

class _BusyBooksNestedMenu<T> extends StatefulWidget {
  const _BusyBooksNestedMenu({required this.route});
  final _BusyBooksNestedMenuRoute<T> route;
  @override
  State<_BusyBooksNestedMenu<T>> createState() =>
      _BusyBooksNestedMenuState<T>();
}

class _BusyBooksNestedMenuState<T> extends State<_BusyBooksNestedMenu<T>> {
  final _controller = MenuController();
  final _firstFocus = FocusNode(debugLabel: 'First nested menu item');
  bool _selected = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.open();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.route.focusFirst) _firstFocus.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    _firstFocus.dispose();
    super.dispose();
  }

  List<Widget> _children(
    List<PopupMenuEntry<T>> items, {
    bool root = false,
  }) => [
    for (final item in items)
      if (item is BusyBooksSubmenuItem<T>)
        SubmenuButton(
          focusNode: root && identical(item, items.first) ? _firstFocus : null,
          menuChildren: item.enabled ? _children(item.items) : const [],
          child: Text(item.label),
        )
      else if (item is BusyBooksPopupMenuItem<T>)
        Semantics(
          checked: item.trailingCheck ? item.checked : null,
          inMutuallyExclusiveGroup:
              item.trailingCheck && item.mutuallyExclusive,
          child: MenuItemButton(
            focusNode: root && identical(item, items.first)
                ? _firstFocus
                : null,
            closeOnActivate: false,
            onPressed: item.enabled
                ? () {
                    _selected = true;
                    Navigator.of(context).pop(item.menuValue);
                  }
                : null,
            leadingIcon: item.icon == null
                ? null
                : Icon(
                    item.icon,
                    size: BusyBooksSizes.iconSm,
                    color: item.iconColor,
                  ),
            trailingIcon: item.trailingCheck
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.shortcut case final shortcut?) ...[
                        Text(shortcut),
                        const SizedBox(width: BusyBooksSpacing.sm),
                      ],
                      Visibility.maintain(
                        visible: item.checked,
                        child: const Icon(
                          BusyBooksGlyphs.check,
                          size: BusyBooksSizes.iconSm,
                        ),
                      ),
                    ],
                  )
                : item.shortcut == null
                ? null
                : Text(item.shortcut!),
            child: Text(item.label),
          ),
        )
      else if (item is PopupMenuDivider)
        const Divider(height: BusyBooksSpacing.sm),
  ];

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        left: widget.route.anchor.left,
        top: widget.route.anchor.bottom,
        child: MenuAnchor(
          key: widget.route.routeKey,
          controller: _controller,
          consumeOutsideTap: true,
          onClose: () {
            if (!_selected && mounted && widget.route.isCurrent) {
              Navigator.of(context).pop();
            }
          },
          menuChildren: _children(widget.route.items, root: true),
          child: const SizedBox.shrink(),
        ),
      ),
    ],
  );
}

class BusyBooksPopupMenuItem<T> extends PopupMenuItem<T> {
  BusyBooksPopupMenuItem({
    super.key,
    required T value,
    required String label,
    IconData? icon,
    Color? iconColor,
    String? shortcut,
    this.gtkAccelerator,
    super.enabled = true,
    bool checked = false,
    bool trailingCheck = false,
    bool mutuallyExclusive = true,
    Key? routeKey,
  }) : label = label,
       menuValue = value,
       icon = icon,
       iconColor = iconColor,
       shortcut = shortcut,
       checked = checked,
       trailingCheck = trailingCheck,
       mutuallyExclusive = mutuallyExclusive,
       super(
         value: value,
         child: KeyedSubtree(
           key: routeKey,
           child: _BusyBooksPopupMenuItemContent(
             label: label,
             icon: icon,
             iconColor: iconColor,
             shortcut: shortcut,
             checked: checked,
             trailingCheck: trailingCheck,
             mutuallyExclusive: mutuallyExclusive,
           ),
         ),
       );

  final String label;
  final T menuValue;
  final IconData? icon;
  final Color? iconColor;
  final String? shortcut;
  final String? gtkAccelerator;
  final bool checked;
  final bool trailingCheck;
  final bool mutuallyExclusive;
}

class _BusyBooksPopupMenuItemContent extends StatelessWidget {
  const _BusyBooksPopupMenuItemContent({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.shortcut,
    required this.checked,
    required this.trailingCheck,
    required this.mutuallyExclusive,
  });

  final String label;
  final IconData? icon;
  final Color? iconColor;
  final String? shortcut;
  final bool checked;
  final bool trailingCheck;
  final bool mutuallyExclusive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelText = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
    final shortcutText = shortcut == null || shortcut!.isEmpty
        ? null
        : Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              shortcut!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          );
    final labelWidth = _busyBooksMenuTextWidth(
          context,
          label,
          DefaultTextStyle.of(context).style,
        ),
        shortcutWidth = shortcut == null
            ? 0.0
            : _busyBooksMenuTextWidth(
                context,
                shortcut!,
                theme.textTheme.labelSmall,
              );
    return Semantics(
      checked: trailingCheck ? checked : null,
      inMutuallyExclusiveGroup: trailingCheck && mutuallyExclusive,
      child: IconTheme.merge(
        data: const IconThemeData(size: BusyBooksSizes.iconSm),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: iconColor),
              const SizedBox(width: BusyBooksSpacing.sm),
            ],
            Expanded(flex: math.max(1, labelWidth.ceil()), child: labelText),
            if (shortcutText != null) ...[
              const SizedBox(width: BusyBooksSpacing.sm),
              Expanded(
                flex: math.max(1, shortcutWidth.ceil()),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: shortcutText,
                ),
              ),
            ],
            if (trailingCheck) ...[
              const SizedBox(width: BusyBooksSpacing.sm),
              Visibility.maintain(
                visible: checked,
                child: const Icon(BusyBooksGlyphs.check),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

typedef BusyBooksMenuTriggerBuilder =
    Widget Function(BuildContext context, BusyBooksMenuTriggerDetails trigger);

@immutable
class BusyBooksMenuTriggerDetails {
  const BusyBooksMenuTriggerDetails._({
    required this.onPressed,
    required this.focusNode,
    required this.isOpen,
    required GlobalKey anchorKey,
  }) : _anchorKey = anchorKey;

  final VoidCallback? onPressed;
  final FocusNode focusNode;
  final bool isOpen;
  final GlobalKey _anchorKey;

  Widget anchor({required Widget child}) {
    return KeyedSubtree(key: _anchorKey, child: child);
  }
}

/// A shared trigger that presents GTK menus with a Flutter fallback.
class BusyBooksMenuButton<T> extends StatefulWidget {
  const BusyBooksMenuButton({
    super.key,
    required this.tooltip,
    required this.items,
    required this.onSelected,
    required this.triggerBuilder,
    this.enabled = true,
    this.nativeMenuService = const NativeMenuService(),
    this.fallbackMenuWidth,
  });

  final String tooltip;
  final List<PopupMenuEntry<T>> items;
  final ValueChanged<T> onSelected;
  final BusyBooksMenuTriggerBuilder triggerBuilder;
  final bool enabled;
  final NativeMenuService nativeMenuService;
  final double? fallbackMenuWidth;

  @override
  State<BusyBooksMenuButton<T>> createState() => _BusyBooksMenuButtonState<T>();
}

class _BusyBooksMenuButtonState<T> extends State<BusyBooksMenuButton<T>> {
  final _triggerKey = GlobalKey();
  final _anchorKey = GlobalKey();
  late final FocusNode _focusNode;
  BusyBooksMenuSession? _activeMenuSession;
  var _open = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(
      debugLabel: 'BusyBooks menu trigger',
      onKeyEvent: _handleKeyEvent,
    );
  }

  @override
  void didUpdateWidget(covariant BusyBooksMenuButton<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled && _open) {
      _closeMenu();
    }
  }

  @override
  void dispose() {
    final session = _activeMenuSession;
    _activeMenuSession = null;
    if (session != null) {
      unawaited(session.dismiss());
    }
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trigger = BusyBooksMenuTriggerDetails._(
      onPressed: widget.enabled ? _toggleMenu : null,
      focusNode: _focusNode,
      isOpen: _open,
      anchorKey: _anchorKey,
    );
    return KeyedSubtree(
      key: _triggerKey,
      child: widget.triggerBuilder(context, trigger),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (isBusyBooksContextMenuKeyEvent(event) ||
        event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      if (!_open) {
        unawaited(_openMenu(focusFirst: true));
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && _open) {
      _closeMenu();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _toggleMenu() {
    if (_open) {
      _closeMenu();
      return;
    }
    unawaited(_openMenu());
  }

  Future<void> _openMenu({bool focusFirst = false}) async {
    final triggerContext = _triggerKey.currentContext;
    if (!widget.enabled ||
        _open ||
        triggerContext == null ||
        widget.items.isEmpty) {
      return;
    }
    final items = List<PopupMenuEntry<T>>.unmodifiable(widget.items);
    final onSelected = widget.onSelected;
    final session = BusyBooksMenuSession();
    _activeMenuSession = session;
    setState(() => _open = true);

    T? selection;
    try {
      final anchorContext = _anchorKey.currentContext ?? triggerContext;
      selection = await showBusyBooksMenu<T>(
        context: triggerContext,
        anchorContext: anchorContext,
        items: items,
        nativeMenuService: widget.nativeMenuService,
        session: session,
        focusFirst: focusFirst,
        width: widget.fallbackMenuWidth,
      );
    } finally {
      if (mounted && identical(_activeMenuSession, session)) {
        setState(() {
          _activeMenuSession = null;
          _open = false;
        });
      }
    }
    if (mounted && !session.dismissed && selection != null) {
      onSelected(selection);
    }
  }

  void _closeMenu() {
    final session = _activeMenuSession;
    if (session == null) {
      return;
    }
    setState(() {
      _activeMenuSession = null;
      _open = false;
    });
    unawaited(session.dismiss());
  }
}

/// Whether [event] is the standard desktop request for an item context menu.
///
/// Linux applications conventionally support both the Menu key and Shift+F10.
bool isBusyBooksContextMenuKeyEvent(KeyEvent event) {
  if (event is! KeyDownEvent) {
    return false;
  }
  return event.logicalKey == LogicalKeyboardKey.contextMenu ||
      (event.logicalKey == LogicalKeyboardKey.f10 &&
          HardwareKeyboard.instance.isShiftPressed);
}

class BusyBooksPopupSelectorOption<T> {
  const BusyBooksPopupSelectorOption({
    required this.value,
    required this.label,
    this.icon,
    this.iconColor,
    this.shortcut,
    this.gtkAccelerator,
  });

  final T value;
  final String label;
  final IconData? icon;
  final Color? iconColor;
  final String? shortcut;
  final String? gtkAccelerator;
}

/// The shared desktop selector used by Settings-style control rows.
class BusyBooksPopupSelector<T> extends StatelessWidget {
  const BusyBooksPopupSelector({
    super.key,
    required this.value,
    required this.label,
    required this.tooltip,
    required this.options,
    required this.onSelected,
    this.enabled = true,
    this.popupMinWidth = BusyBooksSizes.languagePopupMinWidth,
    this.popupMaxWidth = BusyBooksSizes.languagePopupMaxWidth,
    this.buttonMaxWidth = BusyBooksSizes.languageButtonMaxWidth,
    this.leading,
    this.fullWidth = false,
    this.maxLabelLines = 1,
  });

  final T? value;
  final String label;
  final String tooltip;
  final List<BusyBooksPopupSelectorOption<T>> options;
  final ValueChanged<T> onSelected;
  final bool enabled;
  final double popupMinWidth;
  final double popupMaxWidth;
  final double buttonMaxWidth;
  final Widget? leading;
  final bool fullWidth;
  final int maxLabelLines;
  @override
  Widget build(BuildContext context) {
    // Inherit borderless button geometry and interaction states while keeping
    // the neutral control foreground rather than an action-link accent.
    final neutralButtonStyle = Theme.of(context).outlinedButtonTheme.style;
    final selectorEnabled = enabled && options.isNotEmpty;
    final fallbackMenuWidth = (fullWidth ? popupMaxWidth : buttonMaxWidth)
        .clamp(popupMinWidth, popupMaxWidth);
    return Align(
      widthFactor: fullWidth ? null : 1,
      alignment: AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: fullWidth ? double.infinity : buttonMaxWidth,
        ),
        child: BusyBooksMenuButton<T>(
          tooltip: tooltip,
          enabled: selectorEnabled,
          fallbackMenuWidth: fallbackMenuWidth,
          onSelected: onSelected,
          items: [
            for (final option in options)
              BusyBooksPopupMenuItem<T>(
                value: option.value,
                label: option.label,
                icon: option.icon,
                iconColor: option.iconColor,
                shortcut: option.shortcut,
                gtkAccelerator: option.gtkAccelerator,
                checked: option.value == value,
                trailingCheck: true,
              ),
          ],
          triggerBuilder: (context, trigger) {
            return trigger.anchor(
              child: Tooltip(
                message: tooltip,
                child: Semantics(
                  expanded: trigger.isOpen,
                  child: TextButton(
                    style: ButtonStyle(
                      foregroundColor: neutralButtonStyle?.foregroundColor,
                      iconColor: neutralButtonStyle?.iconColor,
                    ),
                    onPressed: trigger.onPressed,
                    focusNode: trigger.focusNode,
                    child: Row(
                      mainAxisSize: fullWidth
                          ? MainAxisSize.max
                          : MainAxisSize.min,
                      children: [
                        if (leading != null) ...[
                          leading!,
                          const SizedBox(width: BusyBooksSpacing.sm),
                        ],
                        if (fullWidth)
                          Expanded(
                            child: Text(
                              label,
                              maxLines: maxLabelLines,
                              overflow: TextOverflow.ellipsis,
                              softWrap: maxLabelLines > 1,
                            ),
                          )
                        else
                          Flexible(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: math.max(
                                  0,
                                  buttonMaxWidth -
                                      BusyBooksSizes.iconButton -
                                      BusyBooksSpacing.smPlus,
                                ),
                              ),
                              child: Text(
                                label,
                                maxLines: maxLabelLines,
                                overflow: TextOverflow.ellipsis,
                                softWrap: maxLabelLines > 1,
                              ),
                            ),
                          ),
                        const SizedBox(width: BusyBooksSpacing.sm),
                        const Icon(
                          BusyBooksGlyphs.downArrow,
                          size: BusyBooksSizes.iconSm,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Input decoration inherited by controls hosted in a grouped-list row.
///
/// The grouped list owns the surface, outline, padding, and separators. Yaru
/// and Flutter continue to own editing behavior without painting a second
/// Material input surface inside the native desktop row.
InputDecorationThemeData busyBooksGroupedInputDecorationTheme(
  BuildContext context,
) {
  final theme = Theme.of(context);
  final labelColor = theme.colorScheme.onSurfaceVariant;
  final labelStyle = theme.textTheme.bodyMedium?.copyWith(color: labelColor);

  return theme.inputDecorationTheme.copyWith(
    filled: false,
    fillColor: Colors.transparent,
    hoverColor: Colors.transparent,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    contentPadding: EdgeInsets.zero,
    labelStyle: labelStyle,
    floatingLabelStyle: labelStyle,
    floatingLabelBehavior: FloatingLabelBehavior.auto,
  );
}

InputDecoration busyBooksGroupedTextFieldDecoration(
  BuildContext context, {
  required String labelText,
  String? hintText,
  String? errorText,
  bool alignLabelWithHint = false,
}) {
  final decoration = InputDecoration(
    labelText: labelText,
    hintText: hintText,
    errorText: errorText,
    alignLabelWithHint: alignLabelWithHint,
  );
  final defaults = busyBooksGroupedInputDecorationTheme(context);
  final resolved = decoration.applyDefaults(defaults);
  if (errorText == null) {
    return resolved;
  }
  final errorLabelStyle = Theme.of(
    context,
  ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error);
  return resolved.copyWith(
    labelStyle: errorLabelStyle,
    floatingLabelStyle: errorLabelStyle,
  );
}

/// A text entry hosted by the native grouped-list form surface.
///
/// The row owns the background, outline, padding, and separators while
/// [TextFormField] continues to own editing, validation, and focus behavior.
class BusyBooksGroupedTextEntry extends StatefulWidget {
  const BusyBooksGroupedTextEntry({
    super.key,
    required this.label,
    this.controller,
    this.initialValue,
    this.errorText,
    this.hintText,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.focusNode,
    this.keyboardType,
    this.inputFormatters,
    this.minLines = 1,
    this.maxLines = 1,
    this.textInputAction,
    this.textDirection,
    this.textStyle,
    this.alignLabelWithHint = false,
    this.obscureText = false,
    this.enableSuggestions = true,
    this.autocorrect = true,
    this.trailing,
    this.onChanged,
    this.onSubmitted,
  }) : assert(controller == null || initialValue == null),
       assert(minLines > 0),
       assert(maxLines >= minLines);

  final String label;
  final TextEditingController? controller;
  final String? initialValue;
  final String? errorText;
  final String? hintText;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int minLines;
  final int maxLines;
  final TextInputAction? textInputAction;
  final TextDirection? textDirection;
  final TextStyle? textStyle;
  final bool alignLabelWithHint;
  final bool obscureText;
  final bool enableSuggestions;
  final bool autocorrect;
  final Widget? trailing;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<BusyBooksGroupedTextEntry> createState() =>
      _BusyBooksGroupedTextEntryState();
}

class _BusyBooksGroupedTextEntryState extends State<BusyBooksGroupedTextEntry> {
  final _fieldKey = GlobalKey<FormFieldState<String>>();

  @override
  Widget build(BuildContext context) {
    final row = _buildRow(context);
    if (!widget.enabled || widget.onSubmitted == null) {
      return row;
    }
    // Linux physical key events are not always translated into the text-input
    // action that drives TextFormField.onFieldSubmitted. Keep that callback for
    // IME actions and bind the desktop Enter keys explicitly as well.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _submit,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _submit,
      },
      child: row,
    );
  }

  Widget _buildRow(BuildContext context) {
    return YaruListTile.square(
      title: TextFormField(
        key: _fieldKey,
        controller: widget.controller,
        initialValue: widget.initialValue,
        enabled: widget.enabled,
        readOnly: widget.readOnly,
        autofocus: widget.autofocus,
        focusNode: widget.focusNode,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.inputFormatters,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        textInputAction: widget.textInputAction,
        textDirection: widget.textDirection,
        obscureText: widget.obscureText,
        enableSuggestions: widget.enableSuggestions,
        autocorrect: widget.autocorrect,
        style: widget.textStyle,
        onChanged: widget.enabled ? widget.onChanged : null,
        onFieldSubmitted: widget.enabled ? widget.onSubmitted : null,
        decoration: busyBooksGroupedTextFieldDecoration(
          context,
          labelText: widget.label,
          hintText: widget.hintText,
          errorText: widget.errorText,
          alignLabelWithHint: widget.alignLabelWithHint,
        ),
      ),
      trailing: widget.trailing,
    );
  }

  void _submit() {
    final value =
        widget.controller?.text ??
        _fieldKey.currentState?.value ??
        widget.initialValue ??
        '';
    widget.onSubmitted?.call(value);
  }
}

class BusyBooksClamp extends StatelessWidget {
  const BusyBooksClamp({
    super.key,
    required this.child,
    this.maxWidth = 680,
    this.scrollable = true,
    this.center = true,
    this.padding = EdgeInsets.zero,
    this.margin = const EdgeInsets.all(BusyBooksSpacing.lg),
    this.controller,
  });

  final Widget child;
  final double maxWidth;
  final bool scrollable;
  final bool center;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final clamped = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      margin: margin,
      padding: padding,
      child: child,
    );

    final body = center
        ? Align(alignment: Alignment.topCenter, child: clamped)
        : clamped;

    return scrollable
        ? SingleChildScrollView(controller: controller, child: body)
        : body;
  }
}

/// Semantic parent surfaces that can contain a grouped card.
enum BusyBooksSurfaceRole { window, view, sidebar, dialog, popover }

class BusyBooksSurfaceScope extends InheritedWidget {
  const BusyBooksSurfaceScope({
    super.key,
    required this.role,
    required super.child,
  });

  final BusyBooksSurfaceRole role;

  static BusyBooksSurfaceRole roleOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<BusyBooksSurfaceScope>()
            ?.role ??
        BusyBooksSurfaceRole.window;
  }

  @override
  bool updateShouldNotify(BusyBooksSurfaceScope oldWidget) {
    return role != oldWidget.role;
  }
}

Color busyBooksGroupedSurfaceColor(
  BuildContext context, {
  BusyBooksSurfaceRole? parentRole,
}) {
  final colors = BusyBooksSurfaceColors.of(context);
  final role = parentRole ?? BusyBooksSurfaceScope.roleOf(context);
  if (role == BusyBooksSurfaceRole.window) {
    return colors.card;
  }
  final parent = switch (role) {
    BusyBooksSurfaceRole.window => colors.window,
    BusyBooksSurfaceRole.view => colors.view,
    BusyBooksSurfaceRole.sidebar => colors.sidebar,
    BusyBooksSurfaceRole.dialog => colors.dialog,
    BusyBooksSurfaceRole.popover => colors.popover,
  };
  return Color.alphaBlend(colors.groupedSurface, parent);
}

class BusyBooksSurface extends StatelessWidget {
  const BusyBooksSurface({
    super.key,
    required this.child,
    this.filled = true,
    this.color,
    this.side,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final bool filled;
  final Color? color;
  final BorderSide? side;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final cardTheme = CardTheme.of(context);
    final surfaceColors = BusyBooksSurfaceColors.of(context);
    final fallbackShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(BusyBooksRadius.lg),
    );
    final themedShape = cardTheme.shape;
    final ShapeBorder shape;
    if (themedShape is OutlinedBorder) {
      shape = side == null ? themedShape : themedShape.copyWith(side: side);
    } else if (themedShape != null && side == null) {
      shape = themedShape;
    } else {
      shape = fallbackShape.copyWith(side: side ?? BorderSide.none);
    }
    final surfaceColor = filled
        ? color ?? cardTheme.color ?? surfaceColors.card
        : Colors.transparent;
    if (filled) {
      final shadowShape = shape is OutlinedBorder
          ? shape.copyWith(side: BorderSide.none)
          : shape;
      return DecoratedBox(
        decoration: ShapeDecoration(
          shape: shadowShape,
          shadows: BusyBooksShadow.nativeCardShadowsFor(context),
        ),
        child: Card(
          margin: EdgeInsets.zero,
          semanticContainer: false,
          color: surfaceColor,
          shadowColor: Colors.transparent,
          shape: shape,
          clipBehavior: clipBehavior,
          child: child,
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      elevation: 0,
      surfaceTintColor: cardTheme.surfaceTintColor ?? Colors.transparent,
      shape: shape,
      clipBehavior: clipBehavior,
      child: child,
    );
  }
}

/// The single semantic raised surface for grouped rows and cards.
class BusyBooksGroupedSurface extends StatelessWidget {
  const BusyBooksGroupedSurface({
    super.key,
    required this.child,
    this.clipBehavior = Clip.antiAlias,
    this.focused = false,
  });

  final Widget child;
  final Clip clipBehavior;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.highContrastOf(context);
    return BusyBooksSurface(
      color: busyBooksGroupedSurfaceColor(context),
      side: focused
          ? BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: BusyBooksStroke.focus,
            )
          : highContrast
          ? BorderSide(color: Theme.of(context).colorScheme.outline)
          : null,
      clipBehavior: clipBehavior,
      child: child,
    );
  }
}

/// Shared split-view sidebar surface and reading-direction boundary.
class BusyBooksSidebarSurface extends StatelessWidget {
  const BusyBooksSidebarSurface({
    super.key,
    required this.child,
    this.showEndBorder = true,
  });

  final Widget child;
  final bool showEndBorder;

  @override
  Widget build(BuildContext context) {
    final colors = BusyBooksSurfaceColors.of(context);
    return Material(
      color: colors.sidebar,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: !showEndBorder
              ? null
              : BorderDirectional(
                  end: BorderSide(
                    color: colors.sidebarBorder,
                    width: BusyBooksStroke.hairline,
                  ),
                ),
        ),
        child: child,
      ),
    );
  }
}

/// A GTK-style navigation list for a persistent desktop sidebar.
class BusyBooksSidebarNavigation extends StatelessWidget {
  const BusyBooksSidebarNavigation({
    super.key,
    required this.children,
    this.surfaceColor,
  });

  final List<Widget> children;
  final Color? surfaceColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BusyBooksSurfaceColors.of(context);
    final masterDetailTheme = YaruMasterDetailTheme.of(context);

    return Theme(
      data: theme.copyWith(
        listTileTheme: theme.listTileTheme.copyWith(
          selectedColor: colors.foreground,
          selectedTileColor: Color.alphaBlend(
            colors.control,
            surfaceColor ?? colors.sidebar,
          ),
          tileColor: Colors.transparent,
          iconColor: colors.mutedForeground,
          textColor: colors.foreground,
          titleTextStyle: theme.textTheme.bodyMedium,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: BusyBooksSpacing.sm,
          ),
          horizontalTitleGap: BusyBooksSpacing.sm,
          minVerticalPadding: 0,
          minLeadingWidth: BusyBooksSizes.iconSm,
          minTileHeight: BusyBooksSizes.sidebarRowHeight,
          visualDensity: VisualDensity.standard,
          titleAlignment: ListTileTitleAlignment.center,
        ),
      ),
      child: ListView.separated(
        padding:
            masterDetailTheme.listPadding ??
            const EdgeInsets.symmetric(vertical: BusyBooksSpacing.sm),
        itemCount: children.length,
        itemBuilder: (context, index) => children[index],
        separatorBuilder: (context, index) => SizedBox(
          height: masterDetailTheme.tileSpacing ?? BusyBooksSpacing.xxs,
        ),
      ),
    );
  }
}

/// A selectable row for [BusyBooksSidebarNavigation].
class BusyBooksSidebarNavigationTile extends StatelessWidget {
  const BusyBooksSidebarNavigationTile({
    super.key,
    required this.selected,
    required this.leading,
    required this.title,
    required this.onTap,
  });

  final bool selected;
  final Widget leading;
  final Widget title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return YaruMasterTile(
      selected: selected,
      leading: IconTheme.merge(
        data: const IconThemeData(size: BusyBooksSizes.iconSm),
        child: leading,
      ),
      title: title,
      onTap: onTap,
    );
  }
}

typedef BusyBooksSidebarRecordMenuBuilder<T> =
    List<PopupMenuEntry<T>> Function(BuildContext context);

/// The interactive record surface used by persistent sidebar lists.
///
/// This is the shared form of the Recent-workspace row: a transparent rounded
/// surface with native hover treatment and, when supplied, one overflow and
/// context-menu action model. Callers can use the standard title/subtitle
/// identity layout or provide domain-specific [content].
class BusyBooksSidebarRecordRow<T> extends StatefulWidget {
  const BusyBooksSidebarRecordRow({
    super.key,
    required this.icon,
    required this.onTap,
    this.title,
    this.subtitle,
    this.pathSubtitle = false,
    this.content,
    this.selected = false,
    this.compact = false,
    this.focusNode,
    this.geometryKey,
    this.onFocusChange,
    this.trailing,
    this.onDoubleTap,
    this.semanticsLabel,
    this.tooltip,
    this.menuTooltip,
    this.menuItemsBuilder,
    this.onMenuSelected,
    this.onMenuOpening,
  }) : assert(
         (title == null) != (content == null),
         'Supply either the standard title or custom content.',
       ),
       assert(
         (menuItemsBuilder == null) == (onMenuSelected == null),
         'Menu items and selection handling must be supplied together.',
       ),
       assert(
         menuItemsBuilder == null || menuTooltip != null,
         'Rows with a menu need a tooltip for its trigger.',
       );

  final IconData icon;
  final String? title;
  final String? subtitle;
  final bool pathSubtitle;
  final Widget? content;
  final bool selected, compact;
  final FocusNode? focusNode;

  /// Optional measured anchor; the public row key remains its resource identity.
  final GlobalKey? geometryKey;
  final ValueChanged<bool>? onFocusChange;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final String? semanticsLabel;
  final String? tooltip;
  final String? menuTooltip;
  final BusyBooksSidebarRecordMenuBuilder<T>? menuItemsBuilder;
  final ValueChanged<T>? onMenuSelected;
  final VoidCallback? onMenuOpening;

  @override
  State<BusyBooksSidebarRecordRow<T>> createState() =>
      _BusyBooksSidebarRecordRowState<T>();
}

class _BusyBooksSidebarRecordRowState<T>
    extends State<BusyBooksSidebarRecordRow<T>> {
  final _rowKey = GlobalKey();
  late final FocusNode _rowFocusNode;
  var _contextMenuOpen = false;
  DateTime? _lastTapAt;

  bool get _hasMenu =>
      widget.menuItemsBuilder != null && widget.onMenuSelected != null;

  @override
  void initState() {
    super.initState();
    _rowFocusNode = FocusNode(debugLabel: 'BusyBooks sidebar record row');
  }

  @override
  void dispose() {
    _rowFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_hasMenu || !isBusyBooksContextMenuKeyEvent(event)) {
      return KeyEventResult.ignored;
    }
    unawaited(_showContextMenu());
    return KeyEventResult.handled;
  }

  void _handleTap() {
    final onDoubleTap = widget.onDoubleTap;
    if (onDoubleTap == null) {
      widget.onTap?.call();
      return;
    }
    final now = DateTime.now();
    final previous = _lastTapAt;
    final doubleTap =
        previous != null && now.difference(previous) <= kDoubleTapTimeout;
    _lastTapAt = doubleTap ? null : now;
    widget.onTap?.call();
    if (doubleTap) onDoubleTap();
  }

  Future<void> _showContextMenu([Offset? position]) async {
    if (!_hasMenu || _contextMenuOpen) return;
    final rowContext = _rowKey.currentContext;
    if (rowContext == null) return;

    widget.onMenuOpening?.call();
    setState(() => _contextMenuOpen = true);
    T? action;
    try {
      final items = widget.menuItemsBuilder!(rowContext);
      action = position == null
          ? await showBusyBooksMenu<T>(
              context: rowContext,
              anchorContext: rowContext,
              items: items,
              focusFirst: true,
            )
          : await showBusyBooksContextMenu<T>(
              rowContext,
              position,
              items: items,
            );
    } finally {
      if (mounted) setState(() => _contextMenuOpen = false);
    }
    if (mounted && action != null) widget.onMenuSelected!(action);
  }

  @override
  Widget build(BuildContext context) {
    final colors = BusyBooksSurfaceColors.of(context);
    final subtitle = widget.subtitle?.trim();
    final customContent = widget.content;
    final menuItems = widget.menuItemsBuilder?.call(context);
    final trailing = menuItems == null || menuItems.isEmpty
        ? widget.trailing
        : BusyBooksMenuButton<T>(
            tooltip: widget.menuTooltip!,
            items: menuItems,
            onSelected: widget.onMenuSelected!,
            triggerBuilder: (context, trigger) => trigger.anchor(
              child: BusyBooksCompactIconButton(
                tooltip: widget.menuTooltip!,
                icon: BusyBooksGlyphs.menuVertical,
                focusNode: trigger.focusNode,
                onPressed: trigger.onPressed == null
                    ? null
                    : () {
                        widget.onMenuOpening?.call();
                        trigger.onPressed!();
                      },
              ),
            ),
          );
    final customRow = customContent == null
        ? null
        : ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: widget.compact
                  ? BusyBooksSizes.sidebarTreeRowHeight
                  : BusyBooksSizes.sidebarTreeRowHeight * 2,
            ),
            child: Row(
              children: [
                const SizedBox(width: BusyBooksSpacing.sm),
                Icon(
                  widget.icon,
                  size: BusyBooksSizes.iconSm,
                  color: colors.mutedForeground,
                ),
                const SizedBox(width: BusyBooksSpacing.sm),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: widget.compact
                          ? BusyBooksSpacing.xs
                          : BusyBooksSpacing.sm,
                    ),
                    child: customContent,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: BusyBooksSpacing.xs),
                  trailing,
                ],
                const SizedBox(width: BusyBooksSpacing.sm),
              ],
            ),
          );
    // Standard identities use the same native row layout as other BusyBooks
    // lists. Yaru owns their typography, content spacing and minimum extent.
    final tile = customRow == null
        ? YaruListTile.square(
            leading: Icon(
              widget.icon,
              size: BusyBooksSizes.iconSm,
              color: colors.mutedForeground,
            ),
            title: Text(
              widget.title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: subtitle == null || subtitle.isEmpty
                ? null
                : _busyBooksGroupedRowSubtitle(
                    context,
                    widget.pathSubtitle
                        ? BusyBooksPathLabel(path: subtitle)
                        : Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
            trailing: trailing,
            focusNode: widget.focusNode ?? _rowFocusNode,
            onFocusChange: widget.onFocusChange,
            hoverColor: busyBooksRowHoverColor(context),
            onTap: widget.onTap == null ? null : _handleTap,
          )
        : InkWell(
            hoverColor: busyBooksRowHoverColor(context),
            focusNode: widget.focusNode ?? _rowFocusNode,
            onFocusChange: widget.onFocusChange,
            canRequestFocus: true,
            onTap: widget.onTap == null ? null : _handleTap,
            child: customRow,
          );
    final row = KeyedSubtree(
      key: _rowKey,
      child: Focus(
        onKeyEvent: _handleKeyEvent,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: BusyBooksStroke.hairline,
          ),
          child: Material(
            color: widget.selected || _contextMenuOpen
                ? busyBooksRowHoverColor(context)
                : BusyBooksLinuxPalette.transparent,
            borderRadius: BorderRadius.circular(BusyBooksRadius.md),
            clipBehavior: Clip.antiAlias,
            child: GestureDetector(
              onSecondaryTapUp: !_hasMenu
                  ? null
                  : (details) {
                      (widget.focusNode ?? _rowFocusNode).requestFocus();
                      unawaited(_showContextMenu(details.globalPosition));
                    },
              child: tile,
            ),
          ),
        ),
      ),
    );
    final semanticRow = Semantics(
      container: true,
      selected: widget.selected,
      button: true,
      label: widget.semanticsLabel,
      enabled: widget.onTap != null,
      onTap: widget.onTap == null ? null : _handleTap,
      child: row,
    );
    final tooltip = widget.tooltip;
    final presented = tooltip == null || tooltip.isEmpty
        ? semanticRow
        : Tooltip(
            message: tooltip,
            excludeFromSemantics: true,
            child: semanticRow,
          );
    return widget.geometryKey == null
        ? presented
        : KeyedSubtree(key: widget.geometryKey, child: presented);
  }
}

/// A native contextual information bar embedded in the surrounding layout.
///
/// This mirrors Libadwaita's banner pattern: the host decides when the banner
/// is revealed, while the banner owns semantic surface, typography, and
/// native action-control presentation without floating over content.
class BusyBooksBanner extends StatelessWidget {
  const BusyBooksBanner({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.suggestedAction = false,
    this.revealed = true,
  }) : assert(actionLabel != null || onAction == null);

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool suggestedAction;
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final colors = BusyBooksSurfaceColors.of(context);
    final actionLabel = this.actionLabel;
    final action = actionLabel == null
        ? null
        : suggestedAction
        ? BusyBooksPushButton.suggested(
            onPressed: onAction,
            child: Text(actionLabel),
          )
        : BusyBooksPushButton.standard(
            onPressed: onAction,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: BusyBooksSpacing.sm,
              ),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(actionLabel),
          );
    final banner = Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.panel,
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BusyBooksSpacing.md,
            vertical: BusyBooksSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.foreground),
                  textAlign: TextAlign.start,
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: BusyBooksSpacing.md),
                action,
              ],
            ],
          ),
        ),
      ),
    );
    final revealDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : BusyBooksMotion.bannerReveal;
    if (revealDuration == Duration.zero) {
      return ClipRect(child: revealed ? banner : const SizedBox.shrink());
    }
    return ClipRect(
      child: AnimatedSize(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.hardEdge,
        duration: revealDuration,
        reverseDuration: revealDuration,
        curve: BusyBooksMotion.bannerRevealCurve,
        child: revealed ? banner : const SizedBox.shrink(),
      ),
    );
  }
}

class BusyBooksGroupedList extends StatelessWidget {
  const BusyBooksGroupedList({
    super.key,
    this.title,
    this.description,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: BusyBooksSpacing.xs),
    this.filled = false,
  });

  final String? title;
  final String? description;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        top: title == null && (description == null || description!.isEmpty)
            ? BusyBooksSpacing.md
            : BusyBooksSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Padding(
              padding: padding,
              child: Semantics(
                header: true,
                child: Text(
                  title!,
                  style: busyBooksSectionHeaderStyle(context),
                ),
              ),
            ),
            if (description != null && description!.isNotEmpty) ...[
              const SizedBox(height: BusyBooksSpacing.xs),
              Padding(
                padding: padding,
                child: Text(
                  description!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: BusyBooksSpacing.sm),
          ],
          _BusyBooksGroupedListSurface(filled: filled, children: children),
        ],
      ),
    );
  }
}

class _BusyBooksGroupedListSurface extends StatelessWidget {
  const _BusyBooksGroupedListSurface({
    required this.filled,
    required this.children,
  });

  final bool filled;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = BusyBooksSurfaceColors.of(context);
    final list = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index < children.length - 1)
            Divider(height: 1, thickness: 1, color: colors.cardShade),
        ],
      ],
    );

    if (!filled) {
      return list;
    }

    return BusyBooksGroupedSurface(child: list);
  }
}

/// A single-selection row following the native AdwComboRow interaction model.
///
/// The complete row owns hover, focus, and activation. Menu presentation is
/// delegated to BusyBooks's GTK menu bridge on Linux.
class BusyBooksComboRow<T> extends StatelessWidget {
  BusyBooksComboRow({
    super.key,
    required this.title,
    required List<T> values,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
    this.subtitle,
    this.errorText,
    this.leading,
    this.enabled = true,
    this.tooltip,
    this.width = BusyBooksSizes.controlRowWidth,
  }) : values = List<T>.unmodifiable(values) {
    if (this.values.isEmpty) {
      throw ArgumentError.value(
        values,
        'values',
        'A combo row requires at least one value.',
      );
    }
    if (this.values.toSet().length != this.values.length) {
      throw ArgumentError.value(
        values,
        'values',
        'A combo row requires unique values.',
      );
    }
    if (!this.values.contains(selected)) {
      throw ArgumentError.value(
        selected,
        'selected',
        'The selected value must be present in values.',
      );
    }
    if (!width.isFinite || width <= 0) {
      throw ArgumentError.value(
        width,
        'width',
        'The maximum value width must be finite and positive.',
      );
    }
  }

  final String title;
  final List<T> values;
  final T selected;
  final String Function(T value) labelFor;
  final ValueChanged<T> onSelected;
  final String? subtitle;
  final String? errorText;
  final Widget? leading;
  final bool enabled;
  final String? tooltip;
  final double width;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasError = errorText?.isNotEmpty ?? false;
        final subtitleWidget = hasError
            ? Text(
                errorText!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              )
            : subtitle == null
            ? null
            : Text(subtitle!);
        final styledSubtitle = subtitleWidget == null
            ? null
            : _busyBooksGroupedRowSubtitle(
                context,
                subtitleWidget,
                enabled: enabled,
              );
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : width + BusyBooksSpacing.md * 2;
        final maximumValueWidth =
            (availableWidth * BusyBooksFormLayout.comboInlineMaxFraction)
                .clamp(0.0, width)
                .toDouble();

        return BusyBooksMenuButton<int>(
          tooltip: tooltip ?? title,
          enabled: enabled,
          onSelected: (index) {
            final value = values[index];
            if (value != selected) {
              onSelected(value);
            }
          },
          items: [
            for (var index = 0; index < values.length; index++)
              BusyBooksPopupMenuItem<int>(
                value: index,
                label: labelFor(values[index]),
                checked: values[index] == selected,
                trailingCheck: true,
              ),
          ],
          triggerBuilder: (context, trigger) {
            final colors = BusyBooksSurfaceColors.of(context);
            final valueForeground = enabled
                ? colors.foreground
                : colors.disabledForeground;
            final value = ExcludeSemantics(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maximumValueWidth),
                child: DefaultTextStyle.merge(
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: valueForeground),
                  child: IconTheme.merge(
                    data: IconThemeData(
                      color: valueForeground,
                      size: BusyBooksSizes.iconSm,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            labelFor(selected),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: BusyBooksSpacing.sm),
                        trigger.anchor(
                          child: const Icon(BusyBooksGlyphs.downArrow),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            final row = YaruListTile.square(
              leading: leading == null
                  ? null
                  : ExcludeSemantics(child: leading!),
              title: ExcludeSemantics(child: Text(title)),
              subtitle: styledSubtitle == null
                  ? null
                  : ExcludeSemantics(child: styledSubtitle),
              trailing: value,
              onTap: trigger.onPressed,
              focusNode: trigger.focusNode,
              hoverColor: busyBooksRowHoverColor(context),
              enabled: enabled,
            );
            final semanticRow = Semantics(
              container: true,
              button: true,
              enabled: enabled,
              expanded: trigger.isOpen,
              onTap: enabled ? trigger.onPressed : null,
              label: subtitle == null || subtitle!.isEmpty
                  ? title
                  : '$title, $subtitle',
              value: labelFor(selected),
              hint: hasError ? errorText : null,
              liveRegion: hasError,
              validationResult: hasError
                  ? ui.SemanticsValidationResult.invalid
                  : ui.SemanticsValidationResult.valid,
              child: ExcludeSemantics(child: row),
            );
            final statefulRow = ColoredBox(
              color: trigger.isOpen
                  ? busyBooksRowHoverColor(context)
                  : Colors.transparent,
              child: semanticRow,
            );
            final boundedRow = constraints.hasBoundedWidth
                ? statefulRow
                : SizedBox(width: availableWidth, child: statefulRow);
            return tooltip == null
                ? boundedRow
                : Tooltip(
                    message: tooltip!,
                    excludeFromSemantics: true,
                    child: boundedRow,
                  );
          },
        );
      },
    );
  }
}

typedef BusyBooksRowActivationCallback =
    void Function(BuildContext context, Offset? globalPosition);

class BusyBooksActionRow extends StatefulWidget {
  const BusyBooksActionRow({
    super.key,
    required this.title,
    this.subtitle,
    this.titleWidget,
    this.subtitleWidget,
    this.leading,
    this.trailing,
    this.onTap,
    this.onActivated,
    this.enabled = true,
    this.tooltip,
    this.destructive = false,
    this.autofocus = false,
    this.hoverColor,
    this.focusNode,
    this.onFocusChange,
  }) : assert(onTap == null || onActivated == null);

  final String title;
  final String? subtitle;
  final Widget? titleWidget;
  final Widget? subtitleWidget;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final BusyBooksRowActivationCallback? onActivated;
  final bool enabled;
  final String? tooltip;
  final bool destructive;
  final bool autofocus;
  final Color? hoverColor;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;

  @override
  State<BusyBooksActionRow> createState() => _BusyBooksActionRowState();
}

class _BusyBooksActionRowState extends State<BusyBooksActionRow> {
  int? _primaryPointer;
  Offset? _pointerDownPosition;

  @override
  void didUpdateWidget(covariant BusyBooksActionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || widget.onActivated == null) {
      _clearPointer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BusyBooksSurfaceColors.of(context);
    final titleStyle = widget.destructive
        ? TextStyle(
            color: widget.enabled
                ? busyBooksDestructiveForeground(context)
                : colors.disabledForeground,
          )
        : null;
    final subtitle =
        widget.subtitleWidget ??
        (widget.subtitle == null || widget.subtitle!.isEmpty
            ? null
            : Text(
                widget.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ));
    final interactive =
        widget.enabled && (widget.onTap != null || widget.onActivated != null);
    final row = YaruListTile.square(
      leading: widget.leading,
      title:
          widget.titleWidget ??
          Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
      subtitle: subtitle == null
          ? null
          : _busyBooksGroupedRowSubtitle(
              context,
              subtitle,
              enabled: widget.enabled,
            ),
      trailing: widget.trailing,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      onFocusChange: widget.onFocusChange,
      hoverColor: widget.hoverColor ?? busyBooksRowHoverColor(context),
      onTap: interactive ? _activate : null,
    );

    final trackedRow = widget.onActivated == null
        ? row
        : Listener(
            onPointerDown: widget.enabled ? _handlePointerDown : null,
            onPointerUp: widget.enabled ? _handlePointerUp : null,
            onPointerCancel: widget.enabled ? _handlePointerCancel : null,
            child: row,
          );

    if (widget.enabled || widget.tooltip == null) {
      return trackedRow;
    }

    return Tooltip(
      message: widget.tooltip!,
      child: Opacity(opacity: 0.6, child: IgnorePointer(child: trackedRow)),
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) {
      return;
    }
    _primaryPointer = event.pointer;
    _pointerDownPosition = event.position;
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_primaryPointer != event.pointer) {
      return;
    }
    final pointer = event.pointer;
    scheduleMicrotask(() {
      if (mounted && _primaryPointer == pointer) {
        _clearPointer();
      }
    });
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_primaryPointer == event.pointer) {
      _clearPointer();
    }
  }

  void _activate() {
    final onActivated = widget.onActivated;
    if (onActivated == null) {
      widget.onTap?.call();
      return;
    }
    final globalPosition = _pointerDownPosition;
    _clearPointer();
    onActivated(context, globalPosition);
  }

  void _clearPointer() {
    _primaryPointer = null;
    _pointerDownPosition = null;
  }
}

/// A Yaru switch with Libadwaita-style state colors and no external halo.
class BusyBooksSwitch extends StatefulWidget {
  const BusyBooksSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.focusNode,
    this.autofocus = false,
    this.mouseCursor,
    this.onOffShapes,
    this.hasFocusBorder,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final FocusNode? focusNode;
  final bool autofocus;
  final MouseCursor? mouseCursor;
  final bool? onOffShapes;
  final bool? hasFocusBorder;

  @override
  State<BusyBooksSwitch> createState() => _BusyBooksSwitchState();
}

class _BusyBooksSwitchState extends State<BusyBooksSwitch> {
  bool _hovered = false;
  int? _pressedPointer;

  bool get _pressed => _pressedPointer != null;

  @override
  void didUpdateWidget(BusyBooksSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onChanged == null) {
      _pressedPointer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inheritedSwitchTheme = YaruSwitchTheme.of(context);
    final checkedTrackColor = _busyBooksCheckedSwitchColor(
      theme.colorScheme.primary,
      brightness: theme.brightness,
      hovered: _hovered,
      pressed: _pressed,
    );

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: Listener(
        onPointerDown: widget.onChanged == null ? null : _handlePointerDown,
        onPointerUp: widget.onChanged == null ? null : _handlePointerUp,
        onPointerCancel: widget.onChanged == null ? null : _handlePointerCancel,
        child: YaruSwitchTheme(
          data: inheritedSwitchTheme.copyWith(
            indicatorColor: const WidgetStatePropertyAll<Color?>(
              Colors.transparent,
            ),
          ),
          child: YaruSwitch(
            value: widget.value,
            onChanged: widget.onChanged,
            selectedColor: checkedTrackColor,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            mouseCursor: widget.mouseCursor,
            onOffShapes: widget.onOffShapes,
            hasFocusBorder: widget.hasFocusBorder,
          ),
        ),
      ),
    );
  }

  void _setHovered(bool hovered) {
    if (_hovered != hovered) {
      setState(() => _hovered = hovered);
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_pressedPointer != null || event.buttons != kPrimaryButton) {
      return;
    }
    setState(() => _pressedPointer = event.pointer);
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_pressedPointer == event.pointer) {
      setState(() => _pressedPointer = null);
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_pressedPointer == event.pointer) {
      setState(() => _pressedPointer = null);
    }
  }
}

Color _busyBooksCheckedSwitchColor(
  Color accent, {
  required Brightness brightness,
  required bool hovered,
  required bool pressed,
}) {
  final normalLightnessDelta = brightness == Brightness.light ? 0.05 : 0.0;
  final stateLightnessDelta = pressed ? -0.07 : (hovered ? 0.07 : 0.0);
  final hsl = HSLColor.fromColor(accent);
  return hsl
      .withLightness(
        (hsl.lightness + normalLightnessDelta + stateLightnessDelta).clamp(
          0.0,
          1.0,
        ),
      )
      .toColor();
}

class BusyBooksSwitchRow extends StatelessWidget {
  const BusyBooksSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.leading,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? leading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final switchControl = BusyBooksSwitch(
      value: value,
      onChanged: enabled ? onChanged : null,
    );
    return YaruSwitchListTile(
      value: value,
      onChanged: enabled ? onChanged : null,
      control: switchControl,
      secondary: leading,
      title: Text(title),
      subtitle: subtitle == null
          ? null
          : _busyBooksGroupedRowSubtitle(
              context,
              Text(subtitle!),
              enabled: enabled,
            ),
      shape: const RoundedRectangleBorder(),
      hoverColor: busyBooksRowHoverColor(context),
    );
  }
}

/// A Yaru radio button with GTK-style state colors and no external halo.
class BusyBooksRadioButton<T> extends StatefulWidget {
  const BusyBooksRadioButton({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.contentPadding,
    this.autofocus = false,
    this.focusNode,
    this.mouseCursor,
    this.hasFocusBorder,
  });

  final T value;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final Widget title;
  final Widget? subtitle;
  final EdgeInsetsGeometry? contentPadding;
  final bool autofocus;
  final FocusNode? focusNode;
  final MouseCursor? mouseCursor;
  final bool? hasFocusBorder;

  @override
  State<BusyBooksRadioButton<T>> createState() =>
      _BusyBooksRadioButtonState<T>();
}

class _BusyBooksRadioButtonState<T> extends State<BusyBooksRadioButton<T>> {
  bool _hovered = false;
  int? _pressedPointer;

  bool get _pressed => _pressedPointer != null;

  @override
  void didUpdateWidget(BusyBooksRadioButton<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onChanged == null) {
      _pressedPointer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inheritedRadioTheme = YaruRadioTheme.of(context);
    final checkedColor = _busyBooksCheckedRadioColor(
      theme.colorScheme.primary,
      brightness: theme.brightness,
      hovered: _hovered,
      pressed: _pressed,
    );

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: Listener(
        onPointerDown: widget.onChanged == null ? null : _handlePointerDown,
        onPointerUp: widget.onChanged == null ? null : _handlePointerUp,
        onPointerCancel: widget.onChanged == null ? null : _handlePointerCancel,
        child: YaruRadioTheme(
          data: inheritedRadioTheme.copyWith(
            color: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return inheritedRadioTheme.color?.resolve(states);
              }
              if (states.contains(WidgetState.selected)) {
                return checkedColor;
              }
              return inheritedRadioTheme.color?.resolve(states);
            }),
            indicatorColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
          child: YaruRadioButton<T>(
            value: widget.value,
            groupValue: widget.groupValue,
            onChanged: widget.onChanged,
            title: widget.title,
            subtitle: widget.subtitle,
            contentPadding: widget.contentPadding,
            autofocus: widget.autofocus,
            focusNode: widget.focusNode,
            mouseCursor: widget.mouseCursor,
            hasFocusBorder: widget.hasFocusBorder,
          ),
        ),
      ),
    );
  }

  void _setHovered(bool hovered) {
    if (_hovered != hovered) {
      setState(() => _hovered = hovered);
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_pressedPointer != null || event.buttons != kPrimaryButton) {
      return;
    }
    setState(() => _pressedPointer = event.pointer);
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_pressedPointer == event.pointer) {
      setState(() => _pressedPointer = null);
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_pressedPointer == event.pointer) {
      setState(() => _pressedPointer = null);
    }
  }
}

Color _busyBooksCheckedRadioColor(
  Color accent, {
  required Brightness brightness,
  required bool hovered,
  required bool pressed,
}) {
  final normalLightnessDelta = brightness == Brightness.light ? 0.05 : 0.0;
  final stateLightnessDelta = pressed ? -0.07 : (hovered ? 0.07 : 0.0);
  final hsl = HSLColor.fromColor(accent);
  return hsl
      .withLightness(
        (hsl.lightness + normalLightnessDelta + stateLightnessDelta).clamp(
          0.0,
          1.0,
        ),
      )
      .toColor();
}

class BusyBooksCheckbox extends StatelessWidget {
  const BusyBooksCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.tooltip,
    this.tristate = false,
  });

  final bool? value;
  final bool tristate;
  final String? tooltip;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final checkbox = YaruCheckbox(
      value: value,
      tristate: tristate,
      onChanged: onChanged,
    );
    final message = tooltip;
    if (message == null || message.isEmpty) {
      return checkbox;
    }
    return Tooltip(message: message, child: checkbox);
  }
}

enum BusyBooksStatusKind { information, success, warning, error }

Color busyBooksStatusColor(BuildContext context, BusyBooksStatusKind kind) {
  final colors = YaruColors.of(context);
  return switch (kind) {
    BusyBooksStatusKind.information => colors.link,
    BusyBooksStatusKind.success => colors.success,
    BusyBooksStatusKind.warning => colors.warning,
    BusyBooksStatusKind.error => colors.error,
  };
}

class BusyBooksStatusBox extends StatelessWidget {
  const BusyBooksStatusBox({
    super.key,
    required this.message,
    this.kind = BusyBooksStatusKind.information,
  });

  final String message;
  final BusyBooksStatusKind kind;

  @override
  Widget build(BuildContext context) {
    return YaruInfoBox(
      yaruInfoType: switch (kind) {
        BusyBooksStatusKind.information => YaruInfoType.information,
        BusyBooksStatusKind.success => YaruInfoType.success,
        BusyBooksStatusKind.warning => YaruInfoType.warning,
        BusyBooksStatusKind.error => YaruInfoType.danger,
      },
      subtitle: Text(message),
    );
  }
}

Color busyBooksDialogSurfaceColor(BuildContext context) {
  return DialogTheme.of(context).backgroundColor ??
      BusyBooksSurfaceColors.of(context).dialog;
}

class BusyBooksDialogTitleBar extends StatelessWidget {
  const BusyBooksDialogTitleBar({
    super.key,
    this.title,
    this.centerTitle = true,
    this.closeSemanticLabel,
    this.closable = true,
    this.showDividerInHighContrast = true,
  });

  final Widget? title;
  final bool centerTitle;
  final String? closeSemanticLabel;
  final bool closable;
  final bool showDividerInHighContrast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BusyBooksSurfaceColors.of(context);
    final dialogSurface = busyBooksDialogSurfaceColor(context);
    return Theme(
      data: theme.copyWith(
        appBarTheme: theme.appBarTheme.copyWith(
          backgroundColor: dialogSurface,
          surfaceTintColor: dialogSurface,
          shadowColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      child: YaruDialogTitleBar(
        title: title,
        centerTitle: centerTitle,
        isClosable: closable,
        isActive: true,
        backgroundColor: dialogSurface,
        border: showDividerInHighContrast && theme.colorScheme.isHighContrast
            ? BorderSide(color: colors.divider)
            : BorderSide.none,
        closeSemanticLabel: closeSemanticLabel,
        heroTag: null,
      ),
    );
  }
}

class BusyBooksDialogShell extends StatelessWidget {
  const BusyBooksDialogShell({
    super.key,
    required this.title,
    required this.children,
    this.maxWidth = BusyBooksSizes.dialog,
    this.header,
    this.actions = const [],
    this.closable = true,
  });

  final String title;
  final List<Widget> children;
  final double maxWidth;
  final Widget? header;
  final List<Widget> actions;
  final bool closable;

  @override
  Widget build(BuildContext context) {
    final dialogSurface = busyBooksDialogSurfaceColor(context);
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: BusyBooksSurfaceScope(
        role: BusyBooksSurfaceRole.dialog,
        child: Dialog(
          backgroundColor: dialogSurface,
          surfaceTintColor: dialogSurface,
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header ??
                    BusyBooksDialogTitleBar(
                      title: Text(title),
                      closable: closable,
                    ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(BusyBooksSpacing.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
                if (actions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(BusyBooksSpacing.lg),
                    child: OverflowBar(
                      alignment: MainAxisAlignment.end,
                      overflowAlignment: OverflowBarAlignment.end,
                      spacing: BusyBooksSpacing.sm,
                      overflowSpacing: BusyBooksSpacing.sm,
                      children: actions,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Semantic desktop push-button roles backed by real Yaru-themed controls.
abstract final class BusyBooksPushButton {
  static FilledButton standard({
    required Widget child,
    required VoidCallback? onPressed,
    ButtonStyle? style,
    FocusNode? focusNode,
    bool autofocus = false,
    WidgetStatesController? statesController,
    Key? key,
  }) {
    return FilledButton(
      key: key,
      onPressed: onPressed,
      style: style,
      focusNode: focusNode,
      autofocus: autofocus,
      statesController: statesController,
      child: child,
    );
  }

  static FilledButton standardIcon({
    required Widget icon,
    required Widget label,
    required VoidCallback? onPressed,
    ButtonStyle? style,
    FocusNode? focusNode,
    bool autofocus = false,
    WidgetStatesController? statesController,
    Key? key,
  }) {
    return FilledButton.icon(
      key: key,
      onPressed: onPressed,
      style: style,
      focusNode: focusNode,
      autofocus: autofocus,
      statesController: statesController,
      icon: icon,
      label: label,
    );
  }

  static ElevatedButton suggested({
    required Widget child,
    required VoidCallback? onPressed,
    ButtonStyle? style,
    FocusNode? focusNode,
    bool autofocus = false,
    WidgetStatesController? statesController,
    Key? key,
  }) {
    return ElevatedButton(
      key: key,
      onPressed: onPressed,
      style: style,
      focusNode: focusNode,
      autofocus: autofocus,
      statesController: statesController,
      child: child,
    );
  }

  static ElevatedButton destructive({
    required BuildContext context,
    required Widget child,
    required VoidCallback? onPressed,
    ButtonStyle? style,
    FocusNode? focusNode,
    bool autofocus = false,
    WidgetStatesController? statesController,
    Key? key,
  }) {
    return ElevatedButton(
      key: key,
      onPressed: onPressed,
      style: _destructiveButtonStyle(context).merge(style),
      focusNode: focusNode,
      autofocus: autofocus,
      statesController: statesController,
      child: child,
    );
  }
}

class BusyBooksDialogButton extends StatelessWidget {
  const BusyBooksDialogButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.suggested = false,
    this.destructive = false,
  }) : assert(!suggested || !destructive);

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool suggested;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final child = _BusyBooksDialogButtonContent(label: label, icon: icon);
    if (destructive) {
      return BusyBooksPushButton.destructive(
        context: context,
        onPressed: onPressed,
        child: child,
      );
    }
    if (suggested) {
      return BusyBooksPushButton.suggested(onPressed: onPressed, child: child);
    }
    return BusyBooksPushButton.standard(onPressed: onPressed, child: child);
  }
}

ButtonStyle _destructiveButtonStyle(BuildContext context) {
  final theme = Theme.of(context);
  final colors = BusyBooksSurfaceColors.of(context);
  Color? background(Set<WidgetState> states) =>
      states.contains(WidgetState.disabled)
      ? colors.disabledControl
      : BusyBooksDestructiveButtonStyle.background(theme);
  Color? foreground(Set<WidgetState> states) =>
      states.contains(WidgetState.disabled)
      ? colors.disabledForeground
      : BusyBooksDestructiveButtonStyle.foreground(theme);
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(background),
    foregroundColor: WidgetStateProperty.resolveWith(foreground),
    iconColor: WidgetStateProperty.resolveWith(foreground),
  );
}

class _BusyBooksDialogButtonContent extends StatelessWidget {
  const _BusyBooksDialogButtonContent({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
    final icon = this.icon;
    if (icon == null) {
      return Center(widthFactor: 1, child: text);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: BusyBooksSizes.iconSm),
        const SizedBox(width: BusyBooksSpacing.sm),
        Flexible(child: text),
      ],
    );
  }
}

class BusyBooksFloatingTextEntryGroup extends StatelessWidget {
  const BusyBooksFloatingTextEntryGroup({super.key, required this.children})
    : assert(children.length > 1);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(height: BusyBooksSpacing.sm),
            children[index],
          ],
        ],
      ),
    );
  }
}

class BusyBooksFloatingTextEntry extends StatelessWidget {
  const BusyBooksFloatingTextEntry({
    super.key,
    required this.label,
    required this.controller,
    this.errorText,
    this.hintText,
    this.enabled = true,
    this.autofocus = false,
    this.keyboardType,
    this.minLines = 1,
    this.maxLines = 1,
    this.textInputAction,
    this.textDirection,
    this.textStyle,
    this.onSubmitted,
  }) : assert(minLines > 0),
       assert(maxLines >= minLines);

  final String label;
  final TextEditingController controller;
  final String? errorText;
  final String? hintText;
  final bool enabled;
  final bool autofocus;
  final TextInputType? keyboardType;
  final int minLines;
  final int maxLines;
  final TextInputAction? textInputAction;
  final TextDirection? textDirection;
  final TextStyle? textStyle;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      textInputAction: textInputAction,
      textDirection: textDirection,
      style: textStyle,
      onFieldSubmitted: enabled ? onSubmitted : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        errorText: errorText,
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: BusyBooksInsets.sectionLabel,
      child: Text(text, style: busyBooksSectionHeaderStyle(context)),
    );
  }
}
