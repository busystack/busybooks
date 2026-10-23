/// Shared reading typography. Neither preferences nor capabilities name formats.
class TypographyCapabilities {
  const TypographyCapabilities({
    this.fontFamily = false,
    this.textMetrics = false,
  });
  static const none = TypographyCapabilities();
  static const reflowable = TypographyCapabilities(
    fontFamily: true,
    textMetrics: true,
  );
  final bool fontFamily, textMetrics;
  factory TypographyCapabilities.fromJson(Object? value) => value is Map
      ? TypographyCapabilities(
          fontFamily: value['fontFamily'] == true,
          textMetrics: value['textMetrics'] == true,
        )
      : none;
  Map<String, bool> toJson() => {
    'fontFamily': fontFamily,
    'textMetrics': textMetrics,
  };
  bool permits(Iterable<String> fields) => fields.every(
    (f) => f == 'font'
        ? fontFamily
        : f == 'publisher'
        ? (fontFamily || textMetrics)
        : !metricFields.contains(f) || textMetrics,
  );
  static const metricFields = {
    'size',
    'weight',
    'line',
    'paragraph',
    'align',
    'hyphenate',
    'margin',
    'width',
  };
}

enum GenericFont { serif, sansSerif, monospace }

/// Generics remain the existing strings. Literal names use a tagged value, so
/// even an installed family called "serif" can be stored without ambiguity.
class FontChoice {
  const FontChoice.generic(this.generic) : family = null;
  const FontChoice.named(String this.family) : generic = null;
  static const serif = FontChoice.generic(GenericFont.serif);
  static const generics = [
    serif,
    FontChoice.generic(GenericFont.sansSerif),
    FontChoice.generic(GenericFont.monospace),
  ];
  final GenericFont? generic;
  final String? family;
  String get name =>
      family ??
      switch (generic!) {
        GenericFont.serif => 'serif',
        GenericFont.sansSerif => 'sans-serif',
        GenericFont.monospace => 'monospace',
      };
  String get key => '${family == null ? 'generic' : 'family'}:$name';
  Object toJson() =>
      family == null ? name : <String, String>{'family': family!};
  static FontChoice? parse(Object? value) {
    if (value is Map) {
      return value.length == 1 && validFamily(value['family'])
          ? FontChoice.named(value['family'] as String)
          : null;
    }
    if (value is! String) return null;
    for (final choice in generics) {
      if (choice.name == value) return choice;
    }
    // Existing named string preferences, including Noto Serif/Sans, remain valid.
    return validFamily(value) ? FontChoice.named(value) : null;
  }

  static bool validFamily(Object? value) {
    if (value is! String ||
        value.isEmpty ||
        value.length > 256 ||
        value.trim() != value) {
      return false;
    }
    for (final rune in value.runes) {
      if (rune < 32 ||
          (rune >= 127 && rune <= 159) ||
          (rune >= 0xd800 && rune <= 0xdfff) ||
          rune == 0xfffd) {
        return false;
      }
    }
    return true;
  }

  @override
  bool operator ==(Object other) => other is FontChoice && key == other.key;
  @override
  int get hashCode => key.hashCode;
}

enum FontAvailability { available, unavailable, discoveryFailed }

class FontResolution {
  const FontResolution({
    required this.choice,
    required this.availability,
    required this.family,
    required this.faces,
  });
  final FontChoice choice;
  final FontAvailability availability;
  final String family;
  final List<LocalFontFace> faces;
  Map<String, dynamic> toJson() => {
    'family': family,
    'faces': faces.map((f) => f.toJson()).toList(),
  };
}

class LocalFontFace {
  const LocalFontFace(this.sources, this.weight, this.italic);
  final List<String> sources;
  final int weight;
  final bool italic;
  factory LocalFontFace.fromJson(Map value) {
    final sources = value['sources'];
    if (sources is! List ||
        sources.isEmpty ||
        sources.length > 8 ||
        sources.any((s) => !FontChoice.validFamily(s))) {
      throw const FormatException('Invalid local font source');
    }
    final names = sources.cast<String>();
    if (names.isEmpty ||
        value['weight'] is! int ||
        (value['weight'] as int) < 1 ||
        (value['weight'] as int) > 1000 ||
        value['italic'] is! bool) {
      throw const FormatException('Invalid local font face');
    }
    return LocalFontFace(
      names,
      value['weight'] as int,
      value['italic'] as bool,
    );
  }
  Map<String, dynamic> toJson() => {
    'sources': sources,
    'weight': weight,
    'italic': italic,
  };
}
