import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:busybooks/src/reading/application/dictionary_service.dart';
import 'package:flutter_test/flutter_test.dart';

String _body(String term) => jsonEncode({
  'en': [
    {
      'language': 'Translingual',
      'partOfSpeech': 'Symbol',
      'definitions': [
        {'definition': '<i>A code &amp; symbol.</i>'},
      ],
    },
    {
      'language': 'English',
      'partOfSpeech': 'Noun',
      'definitions': [
        {'definition': ''},
        {
          'definition':
              '<span>A <b>$term</b>.</span><script>bad()</script><link href="https://example.org">',
        },
        {'definition': 'Another sense&nbsp;&#xE9;.'},
        {'definition': 'A third sense.'},
      ],
    },
  ],
  'other': [
    {
      'language': 'Old French',
      'partOfSpeech': 'Noun',
      'definitions': [
        {'definition': 'An older term.'},
      ],
    },
  ],
});

class _Headers implements HttpHeaders {
  final values = <String, Object>{};
  @override
  ContentType? contentType = ContentType.json;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      values[name] = value;
  @override
  String? value(String name) => values[name]?.toString();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(String body, {this.statusCode = 200}) : bytes = utf8.encode(body);
  final List<int> bytes;
  @override
  final int statusCode;
  @override
  final headers = _Headers();
  @override
  int get contentLength => bytes.length;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final Future<HttpClientResponse> Function() response;
  @override
  bool followRedirects = true;
  @override
  final headers = _Headers();
  @override
  Future<HttpClientResponse> close() => response();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  _Client(this.respond);
  final Future<HttpClientResponse> Function(Uri) respond;
  final uris = <Uri>[];
  final requests = <_Request>[];
  bool closed = false;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    uris.add(uri);
    final request = _Request(() => respond(uri));
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) => closed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final term in ['cat', 'café', 'ice cream', 'A/B #?% 東京']) {
    test('lookup encodes and sends the whole term: $term', () async {
      final client = _Client((_) async => _Response(_body('term')));
      final service = WiktionaryService(clientFactory: () => client);
      final result = await service.lookup(' $term ').result;
      expect(result.status, DictionaryStatus.ready);
      expect(client.uris.single.pathSegments.last, term);
      expect(client.uris.single.queryParameters, {'redirect': 'false'});
      expect(client.requests.single.followRedirects, isFalse);
      expect(result.entry!.pathSegments, ['wiki', term]);
      expect(result.sections.first.language, 'Translingual');
      expect(result.sections[1].language, 'English');
      expect(result.sections[1].definitions, ['A term.', 'Another sense é.']);
      expect(result.sections.last.language, 'Old French');
      expect(client.closed, isTrue);
    });
  }
  for (final (status, expected) in [
    (404, DictionaryStatus.missing),
    (429, DictionaryStatus.unavailable),
    (503, DictionaryStatus.unavailable),
    (501, DictionaryStatus.unsupported),
  ]) {
    test('lookup handles HTTP $status', () async {
      final service = WiktionaryService(
        clientFactory: () =>
            _Client((_) async => _Response('{}', statusCode: status)),
      );
      expect((await service.lookup('ice cream').result).status, expected);
    });
  }
  test('offline and bounded total deadline have distinct results', () async {
    final offline = WiktionaryService(
      clientFactory: () =>
          _Client((_) async => throw const SocketException('offline')),
    );
    expect(
      (await offline.lookup('café').result).status,
      DictionaryStatus.offline,
    );
    final client = _Client((_) => Completer<HttpClientResponse>().future);
    final service = WiktionaryService(
      timeout: const Duration(milliseconds: 5),
      clientFactory: () => client,
    );
    expect(
      (await service.lookup('café').result).status,
      DictionaryStatus.timeout,
    );
    expect(client.closed, isTrue);
  });
  test('cancellation closes the application-owned client', () async {
    final pending = Completer<HttpClientResponse>();
    final client = _Client((_) => pending.future);
    final request = WiktionaryService(
      clientFactory: () => client,
    ).lookup('cat');
    request.cancel();
    expect(client.closed, isTrue);
    pending.completeError(const SocketException('cancelled'));
    await request.result;
  });
  for (final body in [
    '<html>error</html>',
    '{}',
    '[]',
    '{"usages": []}',
    '{"en":[{}]}',
    '{"en":[{"language":"English","partOfSpeech":"Noun","definitions":[{"definition":42}]}]}',
  ]) {
    test('malformed or unsupported response: $body', () async {
      final result = await WiktionaryService(
        clientFactory: () => _Client((_) async => _Response(body)),
      ).lookup('cat').result;
      expect(result.status, DictionaryStatus.invalid);
    });
  }
  test('response MIME type, byte bound and redirects are validated', () async {
    final htmlResponse = _Response(_body('term'))
      ..headers.contentType = ContentType.html;
    final oversized = _Response(' ' * (WiktionaryService.maxResponseBytes + 1));
    final redirect = _Response('', statusCode: 302)
      ..headers.set('location', 'https://example.org/private');
    for (final response in [htmlResponse, oversized, redirect]) {
      final client = _Client((_) async => response);
      final result = await WiktionaryService(
        clientFactory: () => client,
      ).lookup('cat').result;
      expect(result.status, DictionaryStatus.invalid);
      expect(client.uris, hasLength(1));
    }
  });
  test(
    'same-source normalization keeps the corresponding full entry',
    () async {
      final client = _Client(
        (uri) async => uri.pathSegments.last == 'ice cream'
            ? (_Response('', statusCode: 301)
                ..headers.set(
                  'location',
                  '/api/rest_v1/page/definition/ice_cream',
                ))
            : _Response(_body('term')),
      );
      final result = await WiktionaryService(
        clientFactory: () => client,
      ).lookup('ice cream').result;
      expect(result.status, DictionaryStatus.ready);
      expect(result.entry!.pathSegments.last, 'ice_cream');
    },
  );
  test('unsupported selections are not shortened or sent', () async {
    var clients = 0;
    final service = WiktionaryService(
      clientFactory: () {
        clients++;
        return _Client((_) async => _Response('{}'));
      },
    );
    for (final term in ['', 'x' * 257, 'a\u0000b']) {
      expect(
        (await service.lookup(term).result).status,
        DictionaryStatus.unsupported,
      );
    }
    expect(clients, 0);
  });
  test(
    'live Wiktionary contract: word, Unicode, phrase and missing entry',
    () async {
      for (final term in ['cat', 'café', 'ice cream']) {
        final result = await WiktionaryService().lookup(term).result;
        expect(result.status, DictionaryStatus.ready, reason: term);
        expect(result.sections, isNotEmpty);
        expect(result.entry!.host, 'en.wiktionary.org');
      }
      expect(
        (await WiktionaryService().lookup('busybooksnonexistentwordzq').result)
            .status,
        DictionaryStatus.missing,
      );
    },
    skip: !const bool.fromEnvironment('BUSYBOOKS_LIVE_WIKTIONARY'),
  );
}
