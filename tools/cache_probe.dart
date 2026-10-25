import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import 'package:busybooks/src/library/data/epub_cache.dart';

Future<void> main() async => stdout.writeln(jsonEncode(await runCacheProbe()));

Future<Map<String, Object>> runCacheProbe() async {
  final root = await Directory.systemTemp.createTemp('busybooks-cache-proof-');
  var checks = 0;
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
    checks++;
  }

  Future<void> rejects(Future<void> Function() action, String message) async {
    try {
      await action();
    } catch (_) {
      checks++;
      return;
    }
    throw StateError(message);
  }

  try {
    final archive = ZipDecoder().decodeBytes(
      await File('test/fixtures/reflowable.epub').readAsBytes(),
    );
    final names = ['EPUB/A.xhtml', 'EPUB/a.xhtml', '%2e%2e/outside', 'a%2Fb'];
    final contents = <String, String>{};
    final package = XmlDocument.parse(
      utf8.decode(archive.findFile('EPUB/package.opf')!.content),
    );
    for (var i = 0; i < names.length; i++) {
      final name = names[i];
      final document = XmlDocument([
        XmlElement(
          XmlName.parts('html'),
          [
            XmlAttribute(
              XmlName.parts('xmlns'),
              'http://www.w3.org/1999/xhtml',
            ),
          ],
          [
            XmlElement(XmlName.parts('head'), [], [
              XmlElement(XmlName.parts('title'), [], [
                XmlText('Cache resource $i'),
              ]),
            ]),
            XmlElement(XmlName.parts('body'), [], [
              XmlElement(XmlName.parts('p'), [], [XmlText('Content of $name')]),
            ]),
          ],
        ),
      ]).toXmlString();
      contents[name] = document;
      final bytes = utf8.encode(document);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
      // Percent signs in literal ZIP names are escaped once in OPF URLs.
      final href = name.startsWith('EPUB/') ? name.substring(5) : '../$name';
      package.rootElement
          .getElement('manifest')!
          .children
          .add(
            XmlElement(XmlName.parts('item'), [
              XmlAttribute(XmlName.parts('id'), 'cache-$i'),
              XmlAttribute(XmlName.parts('href'), href.replaceAll('%', '%25')),
              XmlAttribute(
                XmlName.parts('media-type'),
                'application/xhtml+xml',
              ),
            ]),
          );
      package.rootElement
          .getElement('spine')!
          .children
          .add(
            XmlElement(XmlName.parts('itemref'), [
              XmlAttribute(XmlName.parts('idref'), 'cache-$i'),
            ]),
          );
    }
    final opf = utf8.encode(package.toXmlString());
    archive.addFile(ArchiveFile('EPUB/package.opf', opf.length, opf));
    final bytes = ZipEncoder().encode(archive);
    final id = sha256.convert(bytes).toString();
    final source = File(p.join(root.path, 'original-location', 'source.epub'));
    await source.parent.create();
    await source.writeAsBytes(bytes);
    Future<void> prepare({bool force = false, bool cancel = false}) =>
        prepareEpubCache(
          root.path,
          id,
          sourcePath: source.path,
          force: force,
          cancelled: () => cancel,
        );
    await prepare();
    final indexFile = File(p.join(root.path, 'cache', 'epub', '$id.json'));
    final index = jsonDecode(await indexFile.readAsString()) as Map;
    final resources = index['resources'] as Map;
    final files = <String>{};
    for (final name in names) {
      final filename = resources[name]['file'] as String;
      check(
        RegExp(r'^[a-f0-9]{64}$').hasMatch(filename) && files.add(filename),
        'Distinct logical paths must have safe distinct physical names',
      );
      check(
        await File(
              p.join(root.path, 'cache', 'epub', id, filename),
            ).readAsString() ==
            contents[name],
        'Resource changed',
      );
    }
    check(
      !await File(p.join(root.path, 'outside')).exists(),
      'Encoded resource path escaped the cache',
    );
    final resource = File(p.join(root.path, 'cache', 'epub', id, files.first));
    await resource.setLastModified(DateTime.utc(2001));
    final before = await resource.lastModified();
    final seal = await indexFile.readAsString();
    await prepare();
    check(await resource.lastModified() == before, 'Warm cache was rebuilt');
    check(await indexFile.readAsString() == seal, 'Warm cache index changed');
    await resource.writeAsString(
      contents[names.first]!.replaceFirst('Content', 'Changed'),
    );
    await prepare();
    check(
      await resource.readAsString() == contents[names.first],
      'Same-length corruption was reused',
    );
    await resource.delete();
    await prepare();
    check(await resource.exists(), 'Missing resource was not regenerated');
    await rejects(
      () => prepare(force: true, cancel: true),
      'Cancellation accepted',
    );
    check(
      await indexFile.readAsString() == seal,
      'Cancellation changed valid cache',
    );
    await source.writeAsBytes([...bytes, 0]);
    await rejects(() => prepare(), 'Changed original reused a verified cache');
    check(
      await indexFile.readAsString() == seal,
      'Changed source damaged cache',
    );

    final invalid = utf8.encode('Content of EPUB/A.xhtml');
    archive.addFile(ArchiveFile(names.first, invalid.length, invalid));
    final invalidBytes = ZipEncoder().encode(archive);
    final invalidId = sha256.convert(invalidBytes).toString();
    await source.writeAsBytes(invalidBytes);
    await rejects(
      () => prepareEpubCache(
        root.path,
        invalidId,
        sourcePath: source.path,
        cancelled: () => false,
      ),
      'Plain text was accepted as XHTML',
    );
    check(
      !await File(
        p.join(root.path, 'cache', 'epub', '$invalidId.json'),
      ).exists(),
      'Invalid XHTML cache was published',
    );
    return {
      'status': 'passed',
      'resources': names.length,
      'checks': checks,
      'scope':
          'Valid XHTML and OPF, case-sensitive names, encoded paths, warm reuse, corrupt/missing cache regeneration, cancellation and changed-source/invalid-XML rejection',
    };
  } finally {
    await root.delete(recursive: true);
  }
}
