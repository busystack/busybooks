import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;

enum DictionaryStatus {
  ready,
  missing,
  offline,
  timeout,
  unavailable,
  invalid,
  unsupported,
}

class DictionarySection {
  const DictionarySection(this.language, this.partOfSpeech, this.definitions);
  final String language, partOfSpeech;
  final List<String> definitions;
  Map<String, dynamic> toJson() => {
    'language': language,
    'partOfSpeech': partOfSpeech,
    'definitions': definitions,
  };
}

class DictionaryResult {
  const DictionaryResult(this.status, {this.sections = const [], this.entry});
  final DictionaryStatus status;
  final List<DictionarySection> sections;
  final Uri? entry;
  Map<String, dynamic> toJson() => {
    'status': status.name,
    'sections': sections.map((s) => s.toJson()).toList(),
    'entry': entry?.toString(),
  };
}

class DictionaryRequest {
  const DictionaryRequest(this.result, this.cancel);
  final Future<DictionaryResult> result;
  final void Function() cancel;
}

abstract interface class DictionaryService {
  DictionaryRequest lookup(String term);
}

final dictionaryServiceProvider = Provider<DictionaryService>(
  (_) => WiktionaryService(),
);

/// Only the primary application makes requests. No renderer, publication URL,
/// book metadata, cookies or private notes participate in lookup.
class WiktionaryService implements DictionaryService {
  WiktionaryService({
    this.timeout = const Duration(seconds: 10),
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? HttpClient.new;
  final Duration timeout;
  final HttpClient Function() _clientFactory;
  static const maxResponseBytes = 1024 * 1024;
  static Uri entryUri(String term) => Uri(
    scheme: 'https',
    host: 'en.wiktionary.org',
    pathSegments: ['wiki', term],
  );

  @override
  DictionaryRequest lookup(String term) {
    final query = term.trim();
    if (query.isEmpty ||
        query.runes.length > 256 ||
        query.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      return DictionaryRequest(
        Future.value(const DictionaryResult(DictionaryStatus.unsupported)),
        () {},
      );
    }
    final client = _clientFactory()..connectionTimeout = timeout;
    final result = _fetch(client, query)
        .timeout(timeout)
        .onError((error, stack) {
          return DictionaryResult(switch (error) {
            TimeoutException() => DictionaryStatus.timeout,
            SocketException() => DictionaryStatus.offline,
            FormatException() => DictionaryStatus.invalid,
            _ => DictionaryStatus.unavailable,
          });
        })
        .whenComplete(() => client.close(force: true));
    return DictionaryRequest(result, () => client.close(force: true));
  }

  Future<DictionaryResult> _fetch(HttpClient client, String term) async {
    var uri = Uri(
      scheme: 'https',
      host: 'en.wiktionary.org',
      pathSegments: ['api', 'rest_v1', 'page', 'definition', term],
      queryParameters: {'redirect': 'false'},
    );
    for (var redirects = 0; redirects <= 3; redirects++) {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'BusyBooks/0.1 (https://github.com/busystack/busybooks)',
      );
      final response = await request.close();
      if ([301, 302, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        final next = location == null ? null : uri.resolve(location);
        if (next == null ||
            next.scheme != 'https' ||
            next.host != 'en.wiktionary.org' ||
            next.port != 443 ||
            next.userInfo.isNotEmpty ||
            !next.path.startsWith('/api/rest_v1/page/definition/')) {
          return const DictionaryResult(DictionaryStatus.invalid);
        }
        // Close this response without retaining cookies or following other hosts.
        await response.take(0).drain<void>();
        uri = next;
        continue;
      }
      if (response.statusCode == 404) {
        return const DictionaryResult(DictionaryStatus.missing);
      }
      if (response.statusCode == 501) {
        return const DictionaryResult(DictionaryStatus.unsupported);
      }
      if (response.statusCode != 200) {
        return const DictionaryResult(DictionaryStatus.unavailable);
      }
      if (response.headers.contentType?.mimeType != 'application/json' ||
          response.contentLength > maxResponseBytes) {
        return const DictionaryResult(DictionaryStatus.invalid);
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > maxResponseBytes) {
          return const DictionaryResult(DictionaryStatus.invalid);
        }
        bytes.addAll(chunk);
      }
      return parse(utf8.decode(bytes), entry: entryUri(uri.pathSegments.last));
    }
    return const DictionaryResult(DictionaryStatus.unavailable);
  }

  /// The live definition/0.8.1 format is keyed by language code (including
  /// "other"), not the older "usages" object in the published OpenAPI schema.
  /// Actual section labels are authoritative: even "en" can be Translingual.
  static DictionaryResult parse(String body, {required Uri entry}) {
    try {
      if (utf8.encode(body).length > maxResponseBytes) {
        throw const FormatException();
      }
      final value = jsonDecode(body);
      if (value is! Map ||
          value.isEmpty ||
          value.length > 256 ||
          value.containsKey('usages')) {
        throw const FormatException();
      }
      final sections = <DictionarySection>[];
      var count = 0, senseCount = 0;
      for (final usages in value.values) {
        if (usages is! List) throw const FormatException();
        for (final usage in usages) {
          if (++count > 512 ||
              usage is! Map ||
              usage['language'] is! String ||
              usage['partOfSpeech'] is! String ||
              usage['definitions'] is! List) {
            throw const FormatException();
          }
          final language = _plain(usage['language'] as String);
          final part = _plain(usage['partOfSpeech'] as String);
          if (language.isEmpty ||
              part.isEmpty ||
              language.length > 100 ||
              part.length > 100) {
            throw const FormatException();
          }
          final definitions = <String>[];
          final senses = usage['definitions'] as List;
          if (senses.length > 2048) throw const FormatException();
          for (final sense in senses) {
            if (++senseCount > 4096 ||
                sense is! Map ||
                sense['definition'] is! String) {
              throw const FormatException();
            }
            if (definitions.length >= 2) continue;
            final text = _plain(sense['definition'] as String);
            // Empty senses occur in otherwise valid live responses.
            if (text.isNotEmpty &&
                definitions.length < 2 &&
                !definitions.contains(text)) {
              definitions.add(
                text.runes.length > 700
                    ? '${String.fromCharCodes(text.runes.take(700))}…'
                    : text,
              );
            }
          }
          if (definitions.isNotEmpty) {
            sections.add(DictionarySection(language, part, definitions));
          }
        }
      }
      if (sections.isEmpty) {
        return DictionaryResult(DictionaryStatus.unsupported, entry: entry);
      }
      return DictionaryResult(
        DictionaryStatus.ready,
        sections: sections.take(8).toList(),
        entry: entry,
      );
    } on FormatException {
      return DictionaryResult(DictionaryStatus.invalid, entry: entry);
    }
  }

  static String _plain(String fragment) {
    final document = html.parseFragment(fragment);
    for (final node in document.querySelectorAll(
      'script, style, link, sup.reference',
    )) {
      node.remove();
    }
    for (final node in document.querySelectorAll('br, p, li, div')) {
      node.nodes.add(dom.Text(' '));
    }
    return (document.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
