import 'dart:convert';
import 'dart:async';
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
    final units = Uint16List((bytes.length - start) ~/ 2);
    for (var i = 0; i < units.length; i++) {
      units[i] = data.getUint16(start + i * 2, le ? Endian.little : Endian.big);
    }
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
      result = _decodeWindows1251(bytes);
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
  validateBookXmlStructure(text);
  return XmlDocument.parse(text);
}

void validateBookXmlStructure(String text, {int maximumNodes = 500000}) {
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
    if (nodes > maximumNodes ||
        event is XmlStartElementEvent &&
            (depth >= 128 || event.attributes.length > 256)) {
      throw const FormatException('XML structure resource limit exceeded');
    }
    if (event is XmlStartElementEvent && !event.isSelfClosing) depth++;
  }
}

// Tolerant HTML still needs a token budget before the browser creates a DOM.
void validateBookMarkup(String text) =>
    _boundXmlTags(text, maximumNodes: 50000);

void _boundXmlTags(String text, {int? maximumNodes}) {
  var offset = 0, nodes = 0;
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
    if (!text.startsWith('</', offset)) nodes++;
    if (maximumNodes != null && nodes > maximumNodes) {
      throw const FormatException('Markup structure resource limit exceeded');
    }
    var cursor = offset + 1, quote = 0, attributes = 0;
    for (; cursor < text.length; cursor++) {
      if (cursor - offset >= 256 * 1024) {
        throw const FormatException('XML tag resource limit exceeded');
      }
      final char = text.codeUnitAt(cursor);
      if (quote != 0) {
        if (char == quote) quote = 0;
      } else if (char == 34 || char == 39) {
        quote = char;
      } else if (char == 61) {
        attributes++;
        nodes++;
        if (attributes > 256 || maximumNodes != null && nodes > maximumNodes) {
          throw const FormatException(
            'Markup attribute resource limit exceeded',
          );
        }
      } else if (char == 62) {
        break;
      }
    }
    offset = cursor + 1;
  }
}

const fb2XmlBytes = 64 * 1024 * 1024;
const fb2DecodedUnits = 16 * 1024 * 1024;

/// Incremental character and event decoding: no whole XML byte buffer, unit
/// list, source string, or second parse is retained beside the validated DOM.
Future<XmlDocument> streamedFb2Xml(
  Stream<List<int>> input,
  bool Function() cancelled, {
  int? declaredBytes,
}) async {
  final iterator = StreamIterator(input);
  try {
    final prefixBytes = BytesBuilder(copy: false);
    List<int>? remainder;
    var ended = false;
    while (prefixBytes.length < 512) {
      if (!await iterator.moveNext()) {
        ended = true;
        break;
      }
      final next = iterator.current,
          count = (512 - prefixBytes.length).clamp(0, iterator.current.length);
      prefixBytes.add(next.sublist(0, count));
      if (count < next.length) remainder = next.sublist(count);
    }
    final first = prefixBytes.takeBytes();
    if (first.isEmpty) throw const FormatException('Empty FB2 document');
    final encodedLimit = fb2EncodedByteLimit(first);
    if (declaredBytes != null && declaredBytes > encodedLimit) {
      throw const FormatException(
        'FB2 document exceeds the supported text size',
      );
    }
    final le =
        first.length >= 2 && first[0] == 255 && first[1] == 254 ||
        first.length >= 4 && first[0] == 60 && first[1] == 0;
    final be =
        first.length >= 2 && first[0] == 254 && first[1] == 255 ||
        first.length >= 4 && first[0] == 0 && first[1] == 60;
    Stream<List<int>> chunks() async* {
      var count = 0;
      Stream<List<int>> replay() async* {
        yield first;
        if (remainder != null) yield remainder;
        while (!ended && await iterator.moveNext()) {
          yield iterator.current;
        }
      }

      await for (final chunk in replay()) {
        if (cancelled()) {
          throw const FormatException('FB2 preparation cancelled');
        }
        count += chunk.length;
        if (count > encodedLimit) {
          throw const FormatException('FB2 source exceeds 64 MiB');
        }
        yield chunk;
      }
    }

    Stream<String> text;
    if (le || be) {
      text = _utf16Chunks(chunks(), le ? Endian.little : Endian.big);
    } else {
      final prefix = latin1.decode(first.take(512).toList());
      final declaration =
          RegExp(r'^\uFEFF?<\?xml\s[^?]*\?>').firstMatch(prefix)?.group(0) ??
          '';
      final encoding = RegExp(
        'encoding\\s*=\\s*["\']([^"\']+)["\']',
        caseSensitive: false,
      ).firstMatch(declaration)?.group(1)?.toLowerCase();
      if (encoding == null ||
          ['utf-8', 'utf8', 'us-ascii'].contains(encoding)) {
        text = chunks().transform(utf8.decoder);
      } else if (['windows-1251', 'cp1251'].contains(encoding)) {
        text = chunks().map(_decodeWindows1251);
      } else {
        throw FormatException('Unsupported XML encoding: $encoding');
      }
    }
    final lexical = _XmlStreamBudget();
    var units = 0;
    final checked = text.map((chunk) {
      units += chunk.length;
      if (units > fb2DecodedUnits) {
        throw const FormatException(
          'FB2 decoded text exceeds 16 Mi UTF-16 units',
        );
      }
      lexical.add(chunk);
      return chunk;
    });
    var nodes = 0, depth = 0;
    Stream<List<XmlEvent>> events() async* {
      StringBuffer? pending;
      var textLength = 0;
      var inBinary = false;
      await for (final batch in checked.toXmlEvents(
        validateNesting: true,
        validateDocument: true,
        withNamespace: true,
      )) {
        final output = <XmlEvent>[];
        for (final event in batch) {
          if (event is XmlTextEvent) {
            textLength += event.value.length;
            if (textLength > (inBinary ? 8 * 1024 * 1024 : 1024 * 1024)) {
              throw const FormatException(
                'FB2 text token resource limit exceeded',
              );
            }
            (pending ??= StringBuffer()).write(event.value);
            continue;
          }
          if (pending != null) {
            output.add(XmlTextEvent(pending.toString()));
            pending = null;
            textLength = 0;
            nodes++;
          }
          if (event is XmlStartElementEvent) {
            if (depth >= 128 || event.attributes.length > 256) {
              throw const FormatException(
                'FB2 XML structure resource limit exceeded',
              );
            }
            nodes += 1 + event.attributes.length;
            if (!event.isSelfClosing) depth++;
            if (event.name.split(':').last == 'binary' &&
                !event.isSelfClosing) {
              inBinary = true;
            }
          } else if (event is XmlEndElementEvent) {
            depth--;
            if (event.name.split(':').last == 'binary') inBinary = false;
          } else {
            nodes++;
          }
          if (nodes > 100000) {
            throw const FormatException(
              'FB2 XML structure resource limit exceeded',
            );
          }
          output.add(event);
        }
        yield output;
      }
      if (pending != null) yield [XmlTextEvent(pending.toString())];
    }

    final roots = <XmlNode>[];
    await for (final batch in events().toXmlNodes()) {
      roots.addAll(batch);
    }
    return XmlDocument(roots);
  } finally {
    await iterator.cancel();
  }
}

Stream<String> _utf16Chunks(Stream<List<int>> input, Endian endian) async* {
  int? odd, high;
  var first = true;
  await for (final chunk in input) {
    final bytes = Uint8List(chunk.length + (odd == null ? 0 : 1));
    if (odd != null) bytes[0] = odd;
    bytes.setAll(odd == null ? 0 : 1, chunk);
    odd = bytes.length.isOdd ? bytes.last : null;
    final data = ByteData.sublistView(bytes);
    final units = Uint16List(bytes.length ~/ 2 + (high == null ? 0 : 1));
    var count = 0;
    if (high != null) {
      units[count++] = high;
      high = null;
    }
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final unit = data.getUint16(i, endian);
      if (first) {
        first = false;
        if (unit == 0xfeff) continue;
      }
      units[count++] = unit;
    }
    if (count > 0 && units[count - 1] >= 0xd800 && units[count - 1] <= 0xdbff) {
      high = units[--count];
    }
    for (var i = 0; i < count; i++) {
      final n = units[i];
      if (n >= 0xd800 && n <= 0xdbff) {
        if (++i >= count || units[i] < 0xdc00 || units[i] > 0xdfff) {
          throw const FormatException('Damaged UTF-16 XML');
        }
      } else if (n >= 0xdc00 && n <= 0xdfff) {
        throw const FormatException('Damaged UTF-16 XML');
      }
    }
    yield String.fromCharCodes(units, 0, count);
  }
  if (odd != null || high != null) {
    throw const FormatException('Damaged UTF-16 XML');
  }
}

class _XmlStreamBudget {
  var markup = false, quote = 0, length = 0;
  String prefix = '', tail = '', recent = '';
  String? terminator;
  void add(String chunk) {
    if (chunk.contains('\u0000') ||
        RegExp(r'<!ENTITY', caseSensitive: false).hasMatch(recent + chunk)) {
      throw const FormatException(
        'Invalid XML character or entity declaration',
      );
    }
    final combined = recent + chunk;
    recent = combined.substring(
      (combined.length - 16).clamp(0, combined.length),
    );
    for (final unit in chunk.codeUnits) {
      if (!markup) {
        if (unit == 60) {
          markup = true;
          length = 1;
          prefix = '<';
          tail = '';
          terminator = null;
          quote = 0;
        } else if (++length > 8 * 1024 * 1024) {
          throw const FormatException('FB2 XML text token limit exceeded');
        }
        continue;
      }
      final char = String.fromCharCode(unit);
      length++;
      if (prefix.length < 9) prefix += char;
      if (prefix == '<!--') terminator = '-->';
      if (prefix == '<![CDATA[') terminator = ']]>';
      if (prefix == '<?') terminator = '?>';
      if (length > (terminator == null ? 65536 : 8 * 1024 * 1024)) {
        throw const FormatException('FB2 XML token limit exceeded');
      }
      if (terminator != null) {
        tail += char;
        if (tail.length > 3) tail = tail.substring(tail.length - 3);
        if (tail.endsWith(terminator!)) {
          markup = false;
          length = 0;
        }
      } else if (quote != 0) {
        if (unit == quote) quote = 0;
      } else if (unit == 34 || unit == 39) {
        quote = unit;
      } else if (unit == 62) {
        markup = false;
        length = 0;
      }
    }
  }
}

String _decodeWindows1251(List<int> bytes) {
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
  return String.fromCharCodes(
    bytes.map(
      (n) => n < 128
          ? n
          : n >= 192
          ? 0x0410 + n - 192
          : high[n - 128],
    ),
  );
}

// UTF-8 uses at most three bytes per UTF-16 unit; UTF-16 uses two and
// Windows-1251 one. Reject impossible-to-accept files before hashing or parsing.
int fb2EncodedByteLimit(List<int> prefix) {
  final le =
      prefix.length >= 2 && prefix[0] == 255 && prefix[1] == 254 ||
      prefix.length >= 4 && prefix[0] == 60 && prefix[1] == 0;
  final be =
      prefix.length >= 2 && prefix[0] == 254 && prefix[1] == 255 ||
      prefix.length >= 4 && prefix[0] == 0 && prefix[1] == 60;
  if (le || be) return fb2DecodedUnits * 2 + 2;
  final declaration =
      RegExp(
        r'^\uFEFF?<\?xml\s[^?]*\?>',
      ).firstMatch(latin1.decode(prefix.take(512).toList()))?.group(0) ??
      '';
  final encoding = RegExp(
    'encoding\\s*=\\s*["\']([^"\']+)["\']',
    caseSensitive: false,
  ).firstMatch(declaration)?.group(1)?.toLowerCase();
  if (['windows-1251', 'cp1251'].contains(encoding)) return fb2DecodedUnits;
  return fb2DecodedUnits * 3 + 3;
}
