import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/typography.dart';

const readingFontChannel = MethodChannel(
  'io.busystack.busybooks/reading_fonts',
);
final readingFontServiceProvider = Provider<ReadingFontService>(
  (_) => ReadingFontService.instance,
);

class InstalledFontFamily {
  const InstalledFontFamily(this.id, this.label);
  final String id, label;
  FontChoice get choice => FontChoice.named(id);
}

class FontCatalogue {
  FontCatalogue(Iterable<InstalledFontFamily> families)
    : families = List.unmodifiable(_unique(families));
  final List<InstalledFontFamily> families;
  static Iterable<InstalledFontFamily> _unique(
    Iterable<InstalledFontFamily> input,
  ) sync* {
    final seen = <String>{};
    for (final f in input) {
      // Native family identities group localized aliases. Only identical
      // identities are coalesced here; similar labels can be distinct families.
      if (FontChoice.validFamily(f.id) &&
          FontChoice.validFamily(f.label) &&
          seen.add(f.id)) {
        yield f;
      }
    }
  }

  InstalledFontFamily? find(String name) {
    for (final f in families) {
      if (f.id.toLowerCase() == name.toLowerCase()) return f;
    }
    return null;
  }
}

/// One service per Dart engine; the native catalogue is process-owned and the
/// same channel is registered on the primary and transient engines. No stores,
/// file paths, font binaries or publication data are part of this service.
class ReadingFontService {
  ReadingFontService({
    MethodChannel channel = readingFontChannel,
    DateTime Function()? now,
  }) : _channel = channel,
       _now = now ?? DateTime.now;
  static final instance = ReadingFontService();
  final MethodChannel _channel;
  final DateTime Function() _now;
  FontCatalogue? _catalogue;
  DateTime? _loadedAt;
  Future<FontCatalogue>? _pending;
  int _revision = 0;
  final _resolved = <String, Future<FontResolution>>{};
  DateTime? _resolvedAt;

  Future<FontCatalogue> catalogue({bool refresh = false}) {
    if (!refresh && _pending != null) return _pending!;
    if (!refresh &&
        _catalogue != null &&
        _now().difference(_loadedAt!) < const Duration(minutes: 1)) {
      return Future.value(_catalogue);
    }
    final revision = ++_revision;
    _resolved.clear();
    final operation = _load(refresh, revision);
    _pending = operation;
    return operation;
  }

  Future<FontCatalogue> _load(bool refresh, int revision) async {
    try {
      final rows = await _channel.invokeListMethod<dynamic>('catalogue', {
        'refresh': refresh,
      });
      if (rows == null) throw const FormatException('Missing font catalogue');
      final families = <InstalledFontFamily>[];
      for (final row in rows) {
        if (row is! Map ||
            !FontChoice.validFamily(row['id']) ||
            !FontChoice.validFamily(row['label'])) {
          throw const FormatException('Invalid font catalogue');
        }
        families.add(
          InstalledFontFamily(row['id'] as String, row['label'] as String),
        );
      }
      final result = FontCatalogue(families);
      if (revision == _revision) {
        _resolved.clear();
        _catalogue = result;
        _loadedAt = _now();
      }
      return result;
    } finally {
      if (revision == _revision) _pending = null;
    }
  }

  Future<FontResolution> resolve(FontChoice choice) async {
    // Refresh/availability never mutates the saved choice.
    if (choice.family != null) {
      FontCatalogue list;
      try {
        list = await catalogue();
      } on Exception {
        return _fallback(choice, FontAvailability.discoveryFailed);
      }
      if (list.find(choice.family!) == null) {
        return _fallback(choice, FontAvailability.unavailable);
      }
    }
    if (_resolvedAt == null ||
        _now().difference(_resolvedAt!) >= const Duration(minutes: 1) ||
        _resolved.length > 64) {
      _resolved.clear();
      _resolvedAt = _now();
    }
    return _resolved.putIfAbsent(choice.key, () => _resolve(choice));
  }

  Future<FontResolution> _resolve(FontChoice choice) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'resolve',
        _identity(choice),
      );
      if (result == null || !FontChoice.validFamily(result['family'])) {
        throw const FormatException('Invalid resolved font');
      }
      final rawFaces = result['faces'];
      if (rawFaces is! List || rawFaces.any((f) => f is! Map)) {
        throw const FormatException('Invalid resolved faces');
      }
      final faces = rawFaces
          .map((f) => LocalFontFace.fromJson(f as Map))
          .toList();
      if (faces.isEmpty || faces.length > 18) {
        throw const FormatException('Incomplete resolved font');
      }
      return FontResolution(
        choice: choice,
        availability: FontAvailability.available,
        family: result['family'] as String,
        faces: faces,
      );
    } on Exception {
      return _fallback(choice, FontAvailability.unavailable);
    }
  }

  Future<FontResolution> _fallback(
    FontChoice choice,
    FontAvailability availability,
  ) async {
    if (choice != FontChoice.serif) {
      final fallback = await resolve(FontChoice.serif);
      return FontResolution(
        choice: choice,
        availability: availability,
        family: fallback.family,
        faces: fallback.faces,
      );
    }
    return FontResolution(
      choice: choice,
      availability: availability,
      family: 'serif',
      faces: const [],
    );
  }

  Map<String, Object> _identity(FontChoice choice) => {
    'name': choice.name,
    'generic': choice.family == null,
  };

  Future<Uint8List> preview(
    FontResolution resolved, {
    required String prose,
    required String bold,
    required String italic,
    required int width,
    required int height,
    required double scale,
    required int foreground,
    required int background,
    double size = 20,
    int weight = 400,
    double line = 1.5,
  }) async {
    if (resolved.faces.isEmpty) throw StateError('Font preview is unavailable');
    // Resolve the effective family, including generic categories, identically
    // in the native sample and the publication's private local() FontFaces.
    final bytes = await _channel.invokeMethod<Uint8List>('preview', {
      'name': resolved.family,
      'generic': false,
      'prose': prose,
      'bold': bold,
      'italic': italic,
      'width': width,
      'height': height,
      'scale': scale,
      'foreground': foreground,
      'background': background,
      'size': size,
      'weight': weight,
      'line': line,
    });
    if (bytes == null || bytes.isEmpty || bytes.length > 4 * 1024 * 1024) {
      throw const FormatException('Invalid font preview');
    }
    return bytes;
  }
}
