import 'dart:convert';
import 'dart:typed_data';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

// The worker is the character-decoding authority. Prepared XML is UTF-8;
// inspection and rendering never guess differently about a declaration.
String decodeBookXml(Uint8List bytes, {bool fictionBook = false}) {
  final bomLE = bytes.length > 1 && bytes[0] == 255 && bytes[1] == 254;
  final bomBE = bytes.length > 1 && bytes[0] == 254 && bytes[1] == 255;
  final le = bomLE || bytes.length > 3 && bytes[0] == 60 && bytes[1] == 0;
  final be = bomBE || bytes.length > 3 && bytes[0] == 0 && bytes[1] == 60;
  String result;
  if (le || be) {
    final start = bomLE || bomBE ? 2 : 0;
    if ((bytes.length - start).isOdd) {
      throw const FormatException('Damaged UTF-16 XML');
    }
    final data = ByteData.sublistView(bytes);
    final units = <int>[
      for (var i = start; i < bytes.length; i += 2)
        data.getUint16(i, le ? Endian.little : Endian.big),
    ];
    for (var i = 0; i < units.length; i++) {
      final n = units[i];
      if (n >= 0xd800 && n <= 0xdbff) {
        if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
          throw const FormatException('Damaged UTF-16 XML');
        }
      } else if (n >= 0xdc00 && n <= 0xdfff) {
        throw const FormatException('Damaged UTF-16 XML');
      }
    }
    result = String.fromCharCodes(units);
  } else {
    final prefix = latin1.decode(bytes.take(512).toList());
    final declaration =
        RegExp(r'^\uFEFF?<\?xml\s[^?]*\?>').firstMatch(prefix)?.group(0) ?? '';
    final encoding = RegExp(
      'encoding\\s*=\\s*["\']([^"\']+)["\']',
      caseSensitive: false,
    ).firstMatch(declaration)?.group(1)?.toLowerCase();
    if (encoding == null || ['utf-8', 'utf8', 'us-ascii'].contains(encoding)) {
      result = utf8.decode(bytes);
    } else if (fictionBook && ['windows-1251', 'cp1251'].contains(encoding)) {
      const high = [
        0x0402,
        0x0403,
        0x201a,
        0x0453,
        0x201e,
        0x2026,
        0x2020,
        0x2021,
        0x20ac,
        0x2030,
        0x0409,
        0x2039,
        0x040a,
        0x040c,
        0x040b,
        0x040f,
        0x0452,
        0x2018,
        0x2019,
        0x201c,
        0x201d,
        0x2022,
        0x2013,
        0x2014,
        0,
        0x2122,
        0x0459,
        0x203a,
        0x045a,
        0x045c,
        0x045b,
        0x045f,
        0x00a0,
        0x040e,
        0x045e,
        0x0408,
        0x00a4,
        0x0490,
        0x00a6,
        0x00a7,
        0x0401,
        0x00a9,
        0x0404,
        0x00ab,
        0x00ac,
        0x00ad,
        0x00ae,
        0x0407,
        0x00b0,
        0x00b1,
        0x0406,
        0x0456,
        0x0491,
        0x00b5,
        0x00b6,
        0x00b7,
        0x0451,
        0x2116,
        0x0454,
        0x00bb,
        0x0458,
        0x0405,
        0x0455,
        0x0457,
      ];
      result = String.fromCharCodes(
        bytes.map(
          (n) => n < 128
              ? n
              : n >= 192
              ? 0x0410 + n - 192
              : high[n - 128],
        ),
      );
    } else {
      throw FormatException(
        'Unsupported XML encoding: $encoding. Use UTF-8 or UTF-16${fictionBook ? ' or Windows-1251' : ''}.',
      );
    }
  }
  if (result.contains('\u0000')) {
    throw const FormatException('Invalid XML character');
  }
  final declaration = RegExp(
    r'^\uFEFF?<\?xml\s[^?]*\?>',
  ).firstMatch(result)?.group(0);
  if (declaration == null) return result;
  return result.replaceRange(
    0,
    declaration.length,
    declaration.replaceFirst(
      RegExp('encoding\\s*=\\s*["\'][^"\']+["\']', caseSensitive: false),
      'encoding="UTF-8"',
    ),
  );
}

XmlDocument boundedBookXml(
  Uint8List bytes, {
  bool fictionBook = false,
  int maximumBytes = 32 * 1024 * 1024,
}) {
  if (bytes.length > maximumBytes) {
    throw const FormatException('XML resource limit exceeded');
  }
  final text = decodeBookXml(bytes, fictionBook: fictionBook);
  if (RegExp(r'<!ENTITY', caseSensitive: false).hasMatch(text)) {
    throw const FormatException('XML entity declarations are unsupported');
  }
  _boundXmlTags(text);
  var nodes = 0, depth = 0;
  // Check lazily before constructing a DOM, so deep/tiny-element inputs cannot
  // allocate an unbounded tree or exhaust the recursive document parser first.
  for (final event in parseEvents(
    text,
    validateNesting: true,
    validateDocument: true,
  )) {
    if (event is XmlEndElementEvent) {
      depth--;
      continue;
    }
    nodes += 1 + (event is XmlStartElementEvent ? event.attributes.length : 0);
    if (nodes > 500000 ||
        event is XmlStartElementEvent &&
            (depth >= 128 || event.attributes.length > 256)) {
      throw const FormatException('XML structure resource limit exceeded');
    }
    if (event is XmlStartElementEvent && !event.isSelfClosing) depth++;
  }
  return XmlDocument.parse(text);
}

void _boundXmlTags(String text) {
  var offset = 0;
  while ((offset = text.indexOf('<', offset)) >= 0) {
    // These are text-bearing XML tokens, not potentially huge attribute lists.
    String? terminator;
    if (text.startsWith('<!--', offset)) {
      terminator = '-->';
    } else if (text.startsWith('<![CDATA[', offset)) {
      terminator = ']]>';
    } else if (text.startsWith('<?', offset)) {
      terminator = '?>';
    }
    if (terminator != null) {
      final end = text.indexOf(terminator, offset + 2);
      if (end < 0) return; // The XML parser supplies the well-formedness error.
      offset = end + terminator.length;
      continue;
    }
    var cursor = offset + 1, quote = 0;
    for (; cursor < text.length; cursor++) {
      if (cursor - offset >= 256 * 1024) {
        throw const FormatException('XML tag resource limit exceeded');
      }
      final char = text.codeUnitAt(cursor);
      if (quote != 0) {
        if (char == quote) quote = 0;
      } else if (char == 34 || char == 39) {
        quote = char;
      } else if (char == 62) {
        break;
      }
    }
    offset = cursor + 1;
  }
}
