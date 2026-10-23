import 'dart:convert';
import 'dart:typed_data';
import 'package:xml/xml.dart';
import 'package:image/image.dart' as image;
import '../../import_export/data/archive_guard.dart';
import 'book_xml.dart';
import 'cover_image.dart';

const fb2Namespace = 'http://www.gribuser.ru/xml/fictionbook/2.0';
const xlinkNamespace = 'http://www.w3.org/1999/xlink';
const xhtmlNamespace = 'http://www.w3.org/1999/xhtml';

Uint8List unwrapFb2(Uint8List bytes, String suffix) {
  if (suffix == 'fb2') return bytes;
  final archive = validatedArchive(bytes, maximumTotal: 64 * 1024 * 1024);
  final documents = archive.files
      .where(
        (entry) => entry.isFile && entry.name.toLowerCase().endsWith('.fb2'),
      )
      .toList();
  if (documents.length != 1) {
    throw const FormatException(
      'An FB2 wrapper must contain exactly one .fb2 document',
    );
  }
  return documents.single.content;
}

class PreparedFb2 {
  PreparedFb2(this.metadata, this.sections, this.toc, this.resources);
  final Map<String, dynamic> metadata;
  final List<Map<String, dynamic>> sections, toc;
  final Map<String, Uint8List> resources;
}

// Version 1: section boundaries are the direct children of each FictionBook
// body. Nested sections stay nested. Both rendered and search documents load
// these exact sanitized bytes; cache rebuilding never changes their identity.
PreparedFb2 prepareFb2(Uint8List bytes) {
  final doc = boundedBookXml(
    bytes,
    fictionBook: true,
    maximumBytes: 64 * 1024 * 1024,
  );
  final root = doc.rootElement;
  if (root.name.local != 'FictionBook' || root.namespaceUri != fb2Namespace) {
    throw const FormatException('Invalid FictionBook root or namespace');
  }
  Iterable<XmlElement> children(XmlElement node, String name) => node
      .childElements
      .where((e) => e.name.local == name && e.namespaceUri == fb2Namespace);
  String text(XmlElement? node, String name) => node == null
      ? ''
      : children(node, name).map((e) => e.innerText.trim()).join(' ');
  final titleInfo = root.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'title-info')
      .firstOrNull;
  final authors = titleInfo == null
      ? <String>[]
      : children(titleInfo, 'author')
            .map((e) {
              final name = [
                'first-name',
                'middle-name',
                'last-name',
              ].map((n) => text(e, n)).where((s) => s.isNotEmpty).join(' ');
              return name.isNotEmpty ? name : text(e, 'nickname');
            })
            .where((s) => s.isNotEmpty)
            .toList();
  final sequence = titleInfo == null
      ? null
      : children(titleInfo, 'sequence').firstOrNull;
  final seriesOrder = num.tryParse(sequence?.getAttribute('number') ?? '');
  final metadata = <String, dynamic>{
    'title': text(titleInfo, 'book-title'),
    'author': authors.join(', '),
    'language': text(titleInfo, 'lang'),
    'series': sequence?.getAttribute('name') ?? '',
    'seriesOrder':
        seriesOrder != null &&
            seriesOrder.isFinite &&
            seriesOrder.abs() <= 10000000
        ? seriesOrder
        : 0,
  };
  final resources = <String, Uint8List>{};
  final images = <String, String>{};
  final binaryIds = <String>{};
  var binaryTotal = 0, binaries = 0;
  for (final binary in children(root, 'binary')) {
    if (++binaries > 2048) {
      throw const FormatException('FB2 binary resource limit exceeded');
    }
    final id = binary.getAttribute('id'),
        type = binary.getAttribute('content-type');
    if (id == null || id.isEmpty || id.length > 1024 || !binaryIds.add(id)) {
      throw const FormatException('Invalid or duplicate FB2 binary identity');
    }
    final encoded = binary.innerText.replaceAll(RegExp(r'\s'), '');
    if (encoded.length > 24 * 1024 * 1024) {
      throw const FormatException('FB2 image resource limit exceeded');
    }
    binaryTotal += encoded.length;
    if (binaryTotal > 64 * 1024 * 1024) {
      throw const FormatException('FB2 aggregate image limit exceeded');
    }
    if (![
      'image/png',
      'image/jpeg',
      'image/webp',
      'image/gif',
    ].contains(type)) {
      continue;
    }
    try {
      final data = base64.decode(encoded);
      final decoder = image.findDecoderForData(data),
          info = decoder?.startDecode(data);
      if (info == null ||
          info.width <= 0 ||
          info.height <= 0 ||
          info.width > 16000 ||
          info.height > 16000 ||
          info.width * info.height > 32 * 1024 * 1024 ||
          info.numFrames > 1) {
        continue;
      }
      final path = 'binary/${images.length}';
      resources[path] = data;
      images[id] = path;
    } catch (_) {
      /* An unusable optional image does not discard text. */
    }
  }
  final coverImage = titleInfo?.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'coverpage')
      .firstOrNull
      ?.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'image')
      .firstOrNull;
  final coverId = coverImage
      ?.getAttribute('href', namespaceUri: xlinkNamespace)
      ?.replaceFirst('#', '');
  final cover = resources[images[coverId]];
  if (cover != null) {
    try {
      metadata['cover'] = libraryCover(cover, '');
    } catch (_) {
      /* optional */
    }
  }
  final sections = <Map<String, dynamic>>[], toc = <Map<String, dynamic>>[];
  final destinations = <String, String>{};
  final bodies = children(root, 'body').toList();
  if (bodies.isEmpty) {
    throw const FormatException('FictionBook has no readable body');
  }
  var sectionCount = 0;
  for (var b = 0; b < bodies.length; b++) {
    final body = bodies[b],
        notes = b > 0 || body.getAttribute('name') == 'notes';
    final parts = body.childElements.toList();
    for (var s = 0; s < parts.length; s++) {
      final section = parts[s];
      if (++sectionCount > 10000) {
        throw const FormatException('FB2 section limit exceeded');
      }
      final identity = 'body:$b/part:$s';
      final path = 'sections/${sections.length}.xhtml';
      for (final el in [
        section,
        ...section.descendants.whereType<XmlElement>(),
      ]) {
        final id = el.getAttribute('id');
        if (id != null) {
          if (id.isEmpty ||
              id.length > 1024 ||
              binaryIds.contains(id) ||
              destinations.containsKey(id)) {
            throw const FormatException(
              'Invalid or duplicate FB2 content identity',
            );
          }
          destinations[id] = '$path#${Uri.encodeComponent(id)}';
        }
      }
      sections.add({
        'id': identity,
        'path': path,
        'notes': notes,
        'source': section,
      });
    }
  }
  // Add attributes only: existing version-1 CFI paths/text offsets stay valid.
  // Reserve every source ID first so generated destinations cannot collide with
  // an ID authored later in the document (including binary/description IDs).
  final usedIds = doc.descendants
      .whereType<XmlElement>()
      .map((node) => node.getAttribute('id'))
      .whereType<String>()
      .toSet();
  final sectionIds = Map<XmlElement, String>.identity();
  for (final (index, section) in sections.indexed) {
    final source = section['source'] as XmlElement;
    var ordinal = 0;
    for (final node in [
      source,
      ...source.descendants.whereType<XmlElement>(),
    ]) {
      if (node.namespaceUri != fb2Namespace ||
          node.name.local != 'section' ||
          node.getAttribute('id') != null) {
        continue;
      }
      final base = 'busybooks-section-$index-${ordinal++}';
      var id = base, collision = 0;
      while (!usedIds.add(id)) {
        id = '$base-${++collision}';
      }
      sectionIds[node] = id;
      destinations[id] = '${section['path']}#${Uri.encodeComponent(id)}';
    }
  }
  const tags = {
    'body': 'section',
    'section': 'section',
    'title': 'header',
    'p': 'p',
    'strong': 'strong',
    'emphasis': 'em',
    'style': 'span',
    'strikethrough': 's',
    'sub': 'sub',
    'sup': 'sup',
    'code': 'code',
    'poem': 'blockquote',
    'stanza': 'div',
    'v': 'p',
    'epigraph': 'blockquote',
    'cite': 'blockquote',
    'annotation': 'aside',
    'subtitle': 'h2',
    'text-author': 'p',
    'date': 'p',
    'empty-line': 'br',
    'table': 'table',
    'tr': 'tr',
    'td': 'td',
    'th': 'th',
    'a': 'a',
    'image': 'img',
  };
  XmlNode? convert(XmlNode node, bool notes) {
    if (node is XmlText || node is XmlCDATA) return XmlText(node.value ?? '');
    if (node is! XmlElement || node.namespaceUri != fb2Namespace) return null;
    final name = tags[node.name.local];
    if (name == null) return null;
    final attrs = <XmlAttribute>[
      XmlAttribute(XmlName.parts('class'), node.name.local),
    ];
    final id = node.getAttribute('id') ?? sectionIds[node];
    if (id != null) attrs.add(XmlAttribute(XmlName.parts('id'), id));
    if (notes && node.name.local == 'section') {
      attrs.add(XmlAttribute(XmlName.parts('role'), 'doc-endnote'));
    }
    if (name == 'a') {
      final href =
          node.getAttribute('href', namespaceUri: xlinkNamespace) ?? '';
      final resolved = href.startsWith('#')
          ? destinations[Uri.decodeComponent(href.substring(1))]
          : Uri.tryParse(href)?.hasScheme == true
          ? href
          : null;
      if (resolved != null) {
        attrs.add(XmlAttribute(XmlName.parts('href'), resolved));
      }
      if (node.getAttribute('type') == 'note') {
        attrs.add(XmlAttribute(XmlName.parts('role'), 'doc-noteref'));
      }
    }
    if (name == 'img') {
      final id = node
          .getAttribute('href', namespaceUri: xlinkNamespace)
          ?.replaceFirst('#', '');
      final path = images[id];
      if (path == null) {
        return XmlElement(XmlName.parts('span'), [], [
          XmlText(node.getAttribute('alt') ?? ''),
        ]);
      }
      attrs.add(XmlAttribute(XmlName.parts('src'), path));
      attrs.add(
        XmlAttribute(XmlName.parts('alt'), node.getAttribute('alt') ?? ''),
      );
    }
    if (name == 'td' || name == 'th') {
      for (final attr in ['colspan', 'rowspan']) {
        final value = int.tryParse(node.getAttribute(attr) ?? '');
        if (value != null && value > 0 && value <= 100) {
          attrs.add(XmlAttribute(XmlName.parts(attr), '$value'));
        }
      }
    }
    return XmlElement(XmlName.parts(name), attrs, [
      for (final child in node.children)
        if (convert(child, notes) case final XmlNode value) value,
    ]);
  }

  for (final section in sections) {
    final source = section.remove('source') as XmlElement,
        notes = section['notes'] as bool;
    final html = XmlElement(
      XmlName.parts('html'),
      [
        XmlAttribute(XmlName.parts('xmlns'), xhtmlNamespace),
        XmlAttribute(XmlName.parts('lang'), metadata['language'] as String),
      ],
      [
        XmlElement(XmlName.parts('head'), [], [
          XmlElement(XmlName.parts('style'), [], [
            XmlText(
              'body { line-height: 1.5; } img { max-width:100%; } .poem .v { margin:0; white-space:pre-wrap; } .stanza { margin-block:1em; } table { border-collapse:collapse; } td,th { padding:.25em; } header { font-weight:bold; font-size:1.3em; }',
            ),
          ]),
        ]),
        XmlElement(XmlName.parts('body'), [], [
          if (convert(source, notes) case final XmlNode value) value,
        ]),
      ],
    ).toXmlString();
    final encoded = utf8.encode(html);
    if (encoded.length > 32 * 1024 * 1024) {
      throw const FormatException(
        'FB2 section resource limit exceeded (32 MiB)',
      );
    }
    resources[section['path'] as String] = Uint8List.fromList(encoded);
    void outline(XmlElement node, List<Map<String, dynamic>> target) {
      if (node.name.local == 'section') {
        final title = text(node, 'title'),
            id = node.getAttribute('id') ?? sectionIds[node];
        final children = <Map<String, dynamic>>[];
        for (final el in node.childElements) {
          if (el.name.local == 'section') outline(el, children);
        }
        target.add({
          'label': title.isEmpty
              ? (notes ? 'Notes' : metadata['title'])
              : title,
          'href': id == null ? section['path'] : destinations[id],
          'subitems': children,
        });
      }
    }

    outline(source, toc);
  }
  return PreparedFb2(metadata, sections, toc, resources);
}
