// Owned worker/request lifecycle adapted from BusyMark notes_store.dart.
// The schema and transactions below belong exclusively to BusyBooks.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import '../../core/atomic_file_writer.dart';
import '../../annotations/domain/annotation_order.dart';
import '../../core/reading_preferences.dart';
import '../../import_export/data/archive_guard.dart';
import 'book_inspection.dart';
import 'book_paths.dart';
import 'record_validation.dart';
import 'book_move.dart';
import 'file_identity.dart';
import '../../workspace/workspace_model.dart';
import 'cover_image.dart';
import 'reading_backup.dart';
import 'publication_cache.dart';
import '../domain/book_format.dart';

class ReadingDataStore {
  ReadingDataStore._(this.root, this._isolate, this._commands, this._replies) {
    _subscription = _replies.listen((dynamic message) {
      final result = message as List;
      final id = result[0] as int;
      if (result[1] == 'progress') {
        _progress.add((result[2] as Map).cast<String, dynamic>());
        return;
      }
      final pending = _pending.remove(id);
      if (result[1] == true) {
        pending?.complete(result[2]);
      } else {
        pending?.completeError(
          result[2] is Map
              ? WorkspaceException.fromJson(result[2] as Map)
              : StateError(result[2].toString()),
        );
      }
    });
  }
  final String root;
  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _replies;
  late final StreamSubscription<dynamic> _subscription;
  final _pending = <int, Completer<dynamic>>{};
  final _progress = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get progress => _progress.stream;
  int _serial = 0;
  bool _closed = false;
  Future<void>? _closing;

  static Future<ReadingDataStore> open(String root) async {
    await Directory(root).create(recursive: true);
    final ready = ReceivePort(), replies = ReceivePort();
    final isolate = await Isolate.spawn(_worker, [
      root,
      ready.sendPort,
      replies.sendPort,
    ]);
    final result = await ready.first as List;
    ready.close();
    if (result[0] != true) {
      isolate.kill();
      replies.close();
      throw StateError(result[1].toString());
    }
    return ReadingDataStore._(root, isolate, result[1] as SendPort, replies);
  }

  Future<dynamic> call(String action, [Object? argument]) {
    if (_closed) {
      return Future.error(StateError('Reading data store is closed'));
    }
    if (action == 'cancelPrepare') {
      _commands.send([0, 'cancel', 'prepare']);
      return Future.value(null);
    }
    final id = ++_serial, completer = Completer<dynamic>();
    _pending[id] = completer;
    _commands.send([id, action, argument]);
    return completer.future;
  }

  void cancel() => _commands.send([0, 'cancel', null]);

  Future<void> close() {
    if (_closing != null) {
      return _closing!;
    }
    if (_closed) {
      return Future.value();
    }
    final request = call('close');
    _closed = true;
    return _closing = request
        .then<void>((_) async {
          await _subscription.cancel();
          _replies.close();
          await _progress.close();
          _isolate.kill();
        })
        .catchError((Object error) {
          _closed = false;
          _closing = null;
          throw error;
        });
  }
}

// All filesystem inspection, SQLite work and archive processing is serialized
// in this owned worker; Flutter widgets never copy or decode whole books.
Future<void> _worker(List<dynamic> ports) async {
  final commands = ReceivePort(), ready = ports[1] as SendPort;
  final worker = _ReadingWorker(ports[0] as String, ports[2] as SendPort);
  try {
    await worker.initialize();
    ready.send([true, commands.sendPort]);
  } catch (error) {
    await worker.lock?.close();
    ready.send([false, error.toString()]);
    commands.close();
    return;
  }
  Future<void> tail = Future.value();
  commands.listen((dynamic message) {
    final request = message as List;
    if (request[1] == 'cancel') {
      if (request[2] != 'prepare' ||
          [
            'prepare',
            'openPath',
            'openMember',
            'relocate',
          ].contains(worker.currentAction)) {
        worker.cancelled = true;
      }
      return;
    }
    tail = tail.then((_) async {
      try {
        worker.cancelled = false;
        worker.replies.send([
          request[0],
          true,
          await worker.handle(
            request[0] as int,
            request[1] as String,
            request[2],
          ),
        ]);
      } catch (error) {
        worker.replies.send([
          request[0],
          false,
          error is WorkspaceException ? error.toJson() : error.toString(),
        ]);
      }
    });
  });
}

class _ReadingWorker {
  _ReadingWorker(this.root, this.replies);
  final String root;
  final SendPort replies;
  late Database database;
  RandomAccessFile? lock;
  bool cancelled = false;
  int currentRequest = 0;
  String currentAction = '';
  Future<void> initialize() async {
    for (final name in ['reading-data.sqlite', '.reading-data-lock']) {
      if (await FileSystemEntity.isLink(p.join(root, name))) {
        throw const FileSystemException(
          'Reading data must not be a symbolic link',
        );
      }
    }
    lock = await File(
      p.join(root, '.reading-data-lock'),
    ).open(mode: FileMode.append);
    await lock!.lock(FileLock.exclusive);
    // The profile lock makes these interrupted staging resources exclusively
    // owned by this worker. Never follow links while cleaning them up.
    for (final kind in ['epub', 'fb2-v1', 'comic-v1']) {
      final parent = Directory(p.join(root, 'cache', kind));
      if (await FileSystemEntity.isLink(p.join(root, 'cache')) ||
          await FileSystemEntity.isLink(parent.path)) {
        throw const FileSystemException(
          'Publication cache must not be a symbolic link',
        );
      }
      if (await parent.exists()) {
        await for (final entry in parent.list(followLinks: false)) {
          if (entry is Directory &&
              p.basename(entry.path).startsWith('.busybooks-')) {
            await entry.delete(recursive: true);
          }
        }
      }
    }
    database = sqlite3.open(p.join(root, 'reading-data.sqlite'));
    final schema =
        database.select('PRAGMA user_version').single.values.single as int;
    if (schema != 0 && schema != 1 && schema != 2) {
      throw const FormatException('Unsupported reading data version');
    }
    database.execute(
      'PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA busy_timeout=5000;',
    );
    if (database.select('PRAGMA foreign_keys').single.values.single != 1) {
      throw StateError('SQLite foreign key enforcement is unavailable');
    }
    database.execute('''
      CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY,json TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS records(id TEXT PRIMARY KEY,kind TEXT NOT NULL,book_id TEXT,json TEXT NOT NULL);
      CREATE INDEX IF NOT EXISTS records_kind ON records(kind);
      CREATE INDEX IF NOT EXISTS annotations_book ON records(book_id,kind);
      CREATE TABLE IF NOT EXISTS collections(id TEXT PRIMARY KEY,name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 256),created INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS memberships(collection_id TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE,book_id TEXT NOT NULL REFERENCES records(id),added INTEGER NOT NULL,PRIMARY KEY(collection_id,book_id));
      CREATE INDEX IF NOT EXISTS memberships_book ON memberships(book_id,collection_id);
      CREATE INDEX IF NOT EXISTS memberships_order ON memberships(collection_id,added);
      CREATE TABLE IF NOT EXISTS locations(book_id TEXT NOT NULL REFERENCES records(id),path TEXT NOT NULL,status TEXT NOT NULL CHECK(status IN ('available','unverified','missing','denied','changed')),verified INTEGER,preferred INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(book_id,path));
      CREATE INDEX IF NOT EXISTS locations_path ON locations(path);
      CREATE UNIQUE INDEX IF NOT EXISTS locations_preferred ON locations(book_id) WHERE preferred=1;
      CREATE TABLE IF NOT EXISTS recent_resources(kind TEXT NOT NULL CHECK(kind IN ('book','collection')),resource_id TEXT NOT NULL,opened INTEGER NOT NULL,PRIMARY KEY(kind,resource_id));
      CREATE TABLE IF NOT EXISTS move_operations(id TEXT PRIMARY KEY,json TEXT NOT NULL);
      CREATE INDEX IF NOT EXISTS recent_opened ON recent_resources(opened DESC);
      CREATE TRIGGER IF NOT EXISTS record_kind_immutable BEFORE UPDATE OF kind ON records WHEN old.kind != new.kind BEGIN SELECT RAISE(ABORT,'Entity kind cannot change'); END;
      CREATE TRIGGER IF NOT EXISTS annotation_book_insert BEFORE INSERT ON records WHEN new.kind='annotation' AND NOT EXISTS(SELECT 1 FROM records WHERE id=new.book_id AND kind='book') BEGIN SELECT RAISE(ABORT,'Annotation book absent'); END;
      CREATE TRIGGER IF NOT EXISTS annotation_book_update BEFORE UPDATE ON records WHEN new.kind='annotation' AND NOT EXISTS(SELECT 1 FROM records WHERE id=new.book_id AND kind='book') BEGIN SELECT RAISE(ABORT,'Annotation book absent'); END;
      CREATE TRIGGER IF NOT EXISTS recent_target BEFORE INSERT ON recent_resources WHEN (new.kind='book' AND NOT EXISTS(SELECT 1 FROM records WHERE id=new.resource_id AND kind='book')) OR (new.kind='collection' AND NOT EXISTS(SELECT 1 FROM collections WHERE id=new.resource_id)) BEGIN SELECT RAISE(ABORT,'Recent resource absent'); END;
      CREATE TRIGGER IF NOT EXISTS membership_book BEFORE INSERT ON memberships WHEN NOT EXISTS(SELECT 1 FROM records WHERE id=new.book_id AND kind='book') BEGIN SELECT RAISE(ABORT,'Membership book absent'); END;
      CREATE TRIGGER IF NOT EXISTS location_book BEFORE INSERT ON locations WHEN NOT EXISTS(SELECT 1 FROM records WHERE id=new.book_id AND kind='book') BEGIN SELECT RAISE(ABORT,'Location book absent'); END;
    ''');
    if (schema < 2) {
      transaction(() {
        for (final b in records('book')) {
          for (final path in b['paths'] as List? ?? []) {
            database.execute(
              'INSERT OR IGNORE INTO locations(book_id,path,status) VALUES(?,?,?)',
              [b['id'], path, 'unverified'],
            );
          }
        }
        for (final r in records('recent')) {
          if (r['resourceKind'] == 'book' &&
              book(r['bookId']?.toString() ?? '') != null) {
            database.execute(
              'INSERT INTO recent_resources(kind,resource_id,opened) VALUES(?,?,?) ON CONFLICT(kind,resource_id) DO UPDATE SET opened=max(opened,excluded.opened)',
              ['book', r['bookId'], r['opened']],
            );
          }
        }
        // Former filesystem definitions remain inert in the old records. No
        // manifest is consulted or converted, and no external file is touched.
        database.execute('PRAGMA user_version=2');
      });
    }
  }

  List<Map<String, dynamic>> records([String? kind]) => database
      .select(
        kind == null
            ? 'SELECT json FROM records ORDER BY rowid'
            : 'SELECT json FROM records WHERE kind=? ORDER BY rowid',
        kind == null ? [] : [kind],
      )
      .map(
        (r) => (jsonDecode(r['json'] as String) as Map).cast<String, dynamic>(),
      )
      .toList();
  Map<String, dynamic>? record(String id, String kind) {
    final rows = database.select(
      'SELECT json FROM records WHERE id=? AND kind=?',
      [id, kind],
    );
    return rows.isEmpty
        ? null
        : (jsonDecode(rows.single['json'] as String) as Map)
              .cast<String, dynamic>();
  }

  Map<String, dynamic>? book(String id) => record(id, 'book');
  List<Map<String, dynamic>> annotations(String id) => database
      .select('SELECT json FROM records WHERE kind=? AND book_id=?', [
        'annotation',
        id,
      ])
      .map(
        (r) => (jsonDecode(r['json'] as String) as Map).cast<String, dynamic>(),
      )
      .toList();
  void put(Map<String, dynamic> value, String kind) {
    if (!['book', 'annotation'].contains(kind)) {
      throw const FormatException('Unsupported entity kind');
    }
    final existing = database.select(
      'SELECT kind,book_id FROM records WHERE id=?',
      [value['id']],
    );
    if (existing.isNotEmpty &&
        (existing.single['kind'] != kind ||
            (kind == 'annotation' &&
                existing.single['book_id'] != value['bookId']))) {
      throw const FormatException('Conflicting entity identity');
    }
    if (kind == 'book') {
      validateBook(value);
    } else {
      final parent = book(value['bookId']?.toString() ?? '');
      if (parent == null) {
        throw const FormatException('Unknown annotation book');
      }
      validateAnnotation(value, parent);
    }
    database.execute(
      'INSERT INTO records(id,kind,book_id,json) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET book_id=excluded.book_id,json=excluded.json',
      [
        value['id'],
        kind,
        value['bookId'],
        jsonEncode({...value, 'kind': kind}),
      ],
    );
  }

  void transaction(void Function() body) {
    database.execute('BEGIN IMMEDIATE');
    try {
      body();
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  void progress(int request, int done, int total, String name) => replies.send([
    request,
    'progress',
    {'done': done, 'total': total, 'name': name},
  ]);
  void recent(String kind, String id) => database.execute(
    'INSERT INTO recent_resources(kind,resource_id,opened) VALUES(?,?,?) ON CONFLICT(kind,resource_id) DO UPDATE SET opened=excluded.opened',
    [kind, id, DateTime.now().millisecondsSinceEpoch],
  );
  List<Map<String, dynamic>> collectionList() => database
      .select(
        'SELECT c.*,count(m.book_id) AS count FROM collections c LEFT JOIN memberships m ON m.collection_id=c.id GROUP BY c.id ORDER BY c.name COLLATE NOCASE,c.id',
      )
      .map((r) => {...r, 'kind': 'collection'})
      .toList();
  List<Map<String, dynamic>> recentList() => database
      .select(
        'SELECT * FROM recent_resources ORDER BY opened DESC,kind,resource_id',
      )
      .map((r) {
        final id = r['resource_id'] as String;
        if (r['kind'] == 'book') {
          final b = book(id);
          return b == null
              ? <String, dynamic>{}
              : {
                  'id': 'recent:book:$id',
                  'resourceId': id,
                  'resourceKind': 'book',
                  'title': b['title'],
                  'path': preferredPath(id),
                  'opened': r['opened'],
                };
        }
        final c = database.select('SELECT name FROM collections WHERE id=?', [
          id,
        ]);
        return c.isEmpty
            ? <String, dynamic>{}
            : {
                'id': 'recent:collection:$id',
                'resourceId': id,
                'resourceKind': 'collection',
                'title': c.single['name'],
                'opened': r['opened'],
              };
      })
      .where((r) => r.isNotEmpty)
      .toList();
  String preferredPath(String id) =>
      database.select(
            'SELECT path FROM locations WHERE book_id=? ORDER BY preferred DESC,verified DESC,path LIMIT 1',
            [id],
          ).firstOrNull?['path']
          as String? ??
      '';
  Map<String, dynamic> storedBook(String id) {
    final value = book(id);
    if (value == null) throw const FormatException('Unknown book');
    final path = preferredPath(id);
    return {...value, 'path': path, 'status': 'unverified'};
  }

  Future<Map<String, dynamic>> accessibleBook(String id) async {
    final value = storedBook(id);
    var status = 'missing';
    for (final row in database.select(
      'SELECT path,status FROM locations WHERE book_id=? ORDER BY preferred DESC,verified DESC,path',
      [id],
    )) {
      final path = row['path'] as String;
      if (!isNativeAbsoluteReference(path)) continue;
      if (row['status'] == 'changed') {
        status = 'changed';
        continue;
      }
      try {
        final handle = await File(path).open();
        await handle.close();
        // Browsing checks accessibility only; identity is verified on opening.
        return {...value, 'path': path, 'status': 'available'};
      } on FileSystemException catch (e) {
        if ([13, 5].contains(e.osError?.errorCode)) status = 'denied';
      }
    }
    return {...value, 'status': status};
  }

  Future<Map<String, dynamic>> openCollection(
    String id, {
    bool recordRecent = true,
  }) async {
    final rows = database.select('SELECT * FROM collections WHERE id=?', [id]);
    if (rows.isEmpty) {
      throw const FormatException('Collection no longer exists');
    }
    final books = <Map<String, dynamic>>[];
    for (final row in database.select(
      'SELECT book_id,added FROM memberships WHERE collection_id=? ORDER BY added,book_id',
      [id],
    )) {
      if (cancelled) throw const FormatException('Opening cancelled');
      books.add({
        ...storedBook(row['book_id'] as String),
        'membershipOrder': row['added'],
      });
    }
    if (recordRecent) recent('collection', id);
    return {
      'id': id,
      'kind': 'collection',
      'name': rows.single['name'],
      'books': books,
    };
  }

  void checkCollectionName(dynamic name) {
    boundedText(name, 'collection name', limit: 256, empty: false);
  }

  Future<Map<String, dynamic>> openBook(
    String input, {
    String? expected,
    bool acceptChanged = false,
  }) async {
    if (isAbsoluteReference(input) && !isNativeAbsoluteReference(input)) {
      throw WorkspaceException(
        'missing',
        input,
        'This book path belongs to another operating system',
        bookId: expected,
      );
    }
    final absolute = p.normalize(p.absolute(input));
    final previousRows = database.select(
      'SELECT book_id FROM locations WHERE path=? ORDER BY verified DESC LIMIT 1',
      [absolute],
    );
    final previous = previousRows.isEmpty
        ? null
        : book(previousRows.single['book_id'] as String);
    expected ??= acceptChanged ? null : previous?['id'] as String?;
    if (await FileSystemEntity.type(absolute) != FileSystemEntityType.file) {
      throw WorkspaceException(
        'missing',
        absolute,
        'Book not found at its saved location. It may have been moved, deleted, or be on an unavailable drive.',
        bookId: expected,
      );
    }
    final canonical = p.normalize(await File(absolute).resolveSymbolicLinks());
    _validated.clear();
    _inspectedBytes = null;
    await _clearInspectedComic();
    late Map<String, dynamic> metadata;
    FileStat? inspectedStat;
    try {
      metadata = await inspectBook(
        canonical,
        () => cancelled,
        identified: (id) {
          if (expected != null && expected != id) {
            database.execute(
              'UPDATE locations SET status=? WHERE book_id=? AND path=?',
              ['changed', expected, canonical],
            );
            throw WorkspaceException(
              'changed',
              absolute,
              'Book contents differ from the saved identity. Reading data has been preserved.',
              bookId: expected,
            );
          }
        },
        comicStagingRoot: p.join(root, 'cache', 'comic-v1'),
        validatedStat: (stat) => inspectedStat = stat,
        retainComic: (prepared) => _inspectedComic = prepared,
        retainBytes: (bytes) {
          _inspectedBytes = bytes;
        },
      );
    } catch (error) {
      if (error is WorkspaceException) rethrow;
      throw WorkspaceException(
        error is FileSystemException &&
                [13, 5].contains(error.osError?.errorCode)
            ? 'denied'
            : RegExp(
                r'cancelled',
                caseSensitive: false,
              ).hasMatch(error.toString())
            ? 'cancelled'
            : RegExp(
                r'encrypted|DRM.protected',
                caseSensitive: false,
              ).hasMatch(error.toString())
            ? 'protected'
            : RegExp(
                r'resource|limit|too many',
                caseSensitive: false,
              ).hasMatch(error.toString())
            ? 'limit'
            : RegExp(
                r'unsupported',
                caseSensitive: false,
              ).hasMatch(error.toString())
            ? 'unsupported'
            : 'damaged',
        absolute,
        error.toString(),
        bookId: expected,
      );
    }
    final id = metadata['id'] as String;
    if (expected != null && expected != id) {
      await _clearInspectedComic();
      database.execute(
        'UPDATE locations SET status=? WHERE book_id=? AND path=?',
        ['changed', expected, canonical],
      );
      throw WorkspaceException(
        'changed',
        absolute,
        'Book contents differ from the saved identity. Reading data has been preserved.',
        bookId: expected,
      );
    }
    final existing = book(id);
    final paths = [
      ...(existing?['paths'] as List? ?? <String>[]).cast<String>(),
    ];
    if (!paths.any((x) => p.equals(x, canonical))) paths.add(canonical);
    transaction(() {
      put({...metadata, ...?existing, 'paths': paths}, 'book');
      database.execute('UPDATE locations SET preferred=0 WHERE book_id=?', [
        id,
      ]);
      database.execute(
        'UPDATE locations SET status=? WHERE path=? AND book_id!=?',
        ['changed', canonical, id],
      );
      database.execute(
        'INSERT INTO locations(book_id,path,status,verified,preferred) VALUES(?,?,?,?,1) ON CONFLICT(book_id,path) DO UPDATE SET status=excluded.status,verified=excluded.verified,preferred=1',
        [id, canonical, 'available', DateTime.now().millisecondsSinceEpoch],
      );
    });
    final value = {...book(id)!, 'path': canonical, 'status': 'available'};
    // Descriptor token prevents a second full inspection in the same validated
    // open. It is session-local, single-use, and tied to source stat metadata.
    final token = 'verified:${++_validationSerial}';
    _validated.clear();
    _validated[token] = {
      'id': id,
      'path': canonical,
      'stat': inspectedStat!,
      'bytes': _inspectedBytes,
      'comic': _inspectedComic,
    };
    return {...value, 'validationToken': token};
  }

  Map<String, dynamic>? _inspectedComic;
  Future<void> _clearInspectedComic() async {
    final directory = _inspectedComic?['directory'] as String?;
    _inspectedComic = null;
    if (directory != null && await Directory(directory).exists()) {
      await Directory(directory).delete(recursive: true);
    }
  }

  Uint8List? _inspectedBytes;
  int _validationSerial = 0;
  final _validated = <String, Map<String, dynamic>>{};
  Future<Map<String, dynamic>> openPath(
    String path, {
    String? expected,
    bool acceptChanged = false,
  }) async {
    if (await FileSystemEntity.isDirectory(path)) {
      throw WorkspaceException(
        'unsupported',
        path,
        'Folders are not BusyBooks resources. Open a supported book file or a saved collection.',
      );
    }
    if (bookFormatForPath(path) == null) {
      throw WorkspaceException(
        'unsupported',
        path,
        'Only EPUB 2/3, PDF, FB2, CBZ, CBR and saved database collections are supported.',
      );
    }
    final value = await openBook(
      path,
      expected: expected,
      acceptChanged: acceptChanged,
    );
    recent('book', value['id'] as String);
    return {
      'id': value['id'],
      'kind': 'book',
      'path': value['path'],
      'name': value['title'],
      'books': [value],
    };
  }

  Future<dynamic> handle(int request, String action, dynamic args) async {
    currentRequest = request;
    currentAction = action;
    switch (action) {
      case 'snapshot':
        return {
          'recent': recentList(),
          'collections': collectionList(),
          'moves': database
              .select('SELECT json FROM move_operations')
              .map((r) => jsonDecode(r['json'] as String))
              .toList(),
        };
      case 'touchBook':
        if (book(args as String) == null) {
          throw const FormatException('Unknown book');
        }
        recent('book', args);
        return null;
      case 'annotation':
        final value = record(args['id'] as String, 'annotation');
        if (value == null || value['bookId'] != args['bookId']) {
          throw const FormatException('Unknown annotation for this book');
        }
        return value;
      case 'annotations':
        return annotations(args as String);
      case 'book':
        return accessibleBook(args as String);
      case 'availability':
        final result = <Map<String, dynamic>>[];
        for (final id in (args as List).take(64)) {
          result.add(await accessibleBook(id as String));
        }
        return result;
      case 'openPath':
        return openPath(
          args['path'] as String,
          expected: args['expectedId'] as String?,
          acceptChanged: args['acceptChanged'] == true,
        );
      case 'openMember':
        final value = await openBook(
          args['path'] as String,
          expected: args['id'] as String,
        );
        recent('book', value['id'] as String);
        return value;
      case 'openCollection':
        return openCollection(
          args['id'] as String,
          recordRecent: args['recordRecent'] != false,
        );
      case 'collections':
        return collectionList();
      case 'createCollection':
        checkCollectionName(args['name']);
        final id =
            'collection:${List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
        database
            .execute('INSERT INTO collections(id,name,created) VALUES(?,?,?)', [
              id,
              (args['name'] as String).trim(),
              DateTime.now().millisecondsSinceEpoch,
            ]);
        return openCollection(id);
      case 'renameCollection':
        checkCollectionName(args['name']);
        database.execute('UPDATE collections SET name=? WHERE id=?', [
          (args['name'] as String).trim(),
          args['id'],
        ]);
        return openCollection(args['id'] as String, recordRecent: false);
      case 'deleteCollection':
        transaction(() {
          database.execute(
            'DELETE FROM recent_resources WHERE kind=? AND resource_id=?',
            ['collection', args],
          );
          database.execute('DELETE FROM collections WHERE id=?', [args]);
        });
        return null;
      case 'addBooks':
        final id = args['collectionId'] as String;
        if (!database.select('SELECT id FROM collections WHERE id=?', [
          id,
        ]).isNotEmpty) {
          throw const FormatException('Unknown collection');
        }
        final results = <Map<String, dynamic>>[];
        final paths = (args['paths'] as List).cast<String>();
        for (var i = 0; i < paths.length; i++) {
          if (cancelled) {
            results.add({
              'path': paths[i],
              'status': 'failed',
              'message': 'Adding books cancelled',
            });
            continue;
          }
          progress(request, i, paths.length, p.basename(paths[i]));
          try {
            final value = await openBook(paths[i]);
            final exists = database.select(
              'SELECT book_id FROM memberships WHERE collection_id=? AND book_id=?',
              [id, value['id']],
            ).isNotEmpty;
            database.execute(
              'INSERT OR IGNORE INTO memberships(collection_id,book_id,added) VALUES(?,?,?)',
              [id, value['id'], DateTime.now().microsecondsSinceEpoch],
            );
            results.add({
              'path': paths[i],
              'status': exists ? 'included' : 'added',
            });
          } catch (e) {
            results.add({
              'path': paths[i],
              'status': 'failed',
              'message': e.toString(),
            });
          }
        }
        return {
          'workspace': await openCollection(id, recordRecent: false),
          'results': results,
        };
      case 'removeBook':
        database.execute(
          'DELETE FROM memberships WHERE collection_id=? AND book_id=?',
          [args['collectionId'], args['bookId']],
        );
        return openCollection(
          args['collectionId'] as String,
          recordRecent: false,
        );
      case 'moveBook':
        final id = args['id'] as String,
            source = p.normalize(p.absolute(args['source'] as String)),
            target = p.normalize(p.absolute(args['destination'] as String));
        if (book(id) == null ||
            database.select(
              'SELECT path FROM locations WHERE book_id=? AND path=?',
              [id, source],
            ).isEmpty) {
          throw const FormatException('Unknown selected book location');
        }
        final journal = database
            .select('SELECT json FROM move_operations')
            .map(
              (r) => (jsonDecode(r['json'] as String) as Map)
                  .cast<String, dynamic>(),
            )
            .where(
              (r) =>
                  r['bookId'] == id &&
                  r['source'] == source &&
                  r['destination'] == target,
            )
            .firstOrNull;
        final result = await BookMoveService(
          report: (done, total) =>
              progress(request, done, total, p.basename(source)),
          record: (entry) {
            if (entry['stage'] == 'complete') {
              database.execute('DELETE FROM move_operations WHERE id=?', [
                entry['id'],
              ]);
            } else {
              database.execute(
                'INSERT INTO move_operations(id,json) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET json=excluded.json',
                [entry['id'], jsonEncode(entry)],
              );
            }
          },
          completed: (bookId, oldPath, newPath) {
            transaction(() {
              final value = book(bookId)!;
              value['paths'] = [
                ...(value['paths'] as List).where(
                  (p) => p != oldPath && p != newPath,
                ),
                newPath,
              ];
              put(value, 'book');
              database.execute(
                'UPDATE locations SET preferred=0 WHERE book_id=?',
                [bookId],
              );
              database.execute(
                'INSERT INTO locations(book_id,path,status,verified,preferred) VALUES(?,?,?,?,1) ON CONFLICT(book_id,path) DO UPDATE SET status=excluded.status,verified=excluded.verified,preferred=1',
                [
                  bookId,
                  newPath,
                  'available',
                  DateTime.now().millisecondsSinceEpoch,
                ],
              );
              database.execute(
                'UPDATE locations SET status=? WHERE book_id=? AND path=?',
                ['unverified', bookId, oldPath],
              );
            });
          },
          cancelled: () => cancelled,
        ).move(id, source, target, recovery: journal);
        if (result['status'] == 'moved') {
          database.execute('DELETE FROM locations WHERE book_id=? AND path=?', [
            id,
            source,
          ]);
        }
        return result;
      case 'dismissMove':
        final rows = database.select(
          'SELECT json FROM move_operations WHERE id=?',
          [args],
        );
        if (rows.isEmpty) return null;
        final entry = (jsonDecode(rows.single['json'] as String) as Map)
            .cast<String, dynamic>();
        final id = entry['bookId'] as String;
        var verified = false;
        for (final path in {
          entry['source'],
          entry['destination'],
          ...(book(id)?['paths'] as List? ?? []),
        }) {
          if (await File(path as String).exists() &&
              await contentHash(path) == id) {
            await openBook(path, expected: id);
            verified = true;
          }
        }
        if (!verified) {
          throw const FileSystemException(
            'No verified original is accessible. Retry recovery before dismissing it.',
          );
        }
        final staged = File(entry['stagePath'] as String);
        if (await staged.exists() &&
            entry['stageInstance'] == fileInstance(staged.path)) {
          await staged.delete();
          syncDirectory(p.dirname(staged.path));
        }
        // Keep both physical originals (and any quarantined original) by explicit
        // user choice. A replaced staging path is also preserved.
        database.execute('DELETE FROM move_operations WHERE id=?', [args]);
        return null;
      case 'relocate':
        final id = args['id'] as String;
        if (book(id) == null) throw const FormatException('Unknown book');
        return openBook(args['path'] as String, expected: id);
      case 'forgetRecent':
        database.execute(
          'DELETE FROM recent_resources WHERE kind=? AND resource_id=?',
          [args['kind'], args['id']],
        );
        return null;
      case 'prepare':
        final id = args['id'] as String;
        final validation = _validated.remove(args['validationToken']);
        Map<String, dynamic>? value;
        Uint8List? trustedBytes;
        Map<String, dynamic>? trustedComic;
        if (validation != null &&
            validation['id'] == id &&
            validation['path'] == args['path']) {
          final before = validation['stat'] as FileStat,
              after = await File(args['path'] as String).stat();
          if (before.size == after.size &&
              before.modified == after.modified &&
              before.changed == after.changed) {
            value = {...book(id)!, 'path': validation['path']};
            trustedBytes = validation['bytes'] as Uint8List?;
            trustedComic = validation['comic'] as Map<String, dynamic>?;
          }
        }
        value ??= await openBook(args['path'] as String, expected: id);
        final cache = await preparePublicationCache(
          root,
          id,
          value['format'] as String,
          sourcePath: value['path'] as String,
          verifiedBytes: trustedBytes ?? _inspectedBytes,
          verifiedComic: trustedComic ?? _inspectedComic,
          force: args['force'] == true,
          cancelled: () => cancelled,
        );
        _inspectedBytes = null;
        await _clearInspectedComic();
        return {'path': value['path'], 'cacheDirectory': cache};
      case 'updateBook':
        final value = book(args['id'] as String);
        if (value == null) {
          throw const FormatException('Unknown reading identity');
        }
        const allowed = [
          'title',
          'author',
          'series',
          'seriesOrder',
          'language',
          'state',
          'progress',
          'read',
          'anchor',
          'reference',
          'appearance',
          'cover',
          'metadataEdited',
          'coverEdited',
          'engineValidated',
          'outline',
          'pageLabels',
          'pages',
        ];
        final changes = (args['changes'] as Map).cast<String, dynamic>();
        if (changes.keys.any((k) => !allowed.contains(k))) {
          throw const FormatException('Invalid reading metadata field');
        }
        value.addAll(changes);
        if (value['appearance'] != null) {
          value['appearance'] = normalizeReadingAppearance(value['appearance']);
        }
        put(value, 'book');
        return {...value, 'path': preferredPath(value['id'] as String)};
      case 'putAnnotation':
        final value = (args as Map).cast<String, dynamic>();
        if (book(value['bookId'] as String) == null ||
            value['anchor'] is! Map) {
          throw const FormatException('Invalid annotation identity');
        }
        if (record(value['id'] as String, 'annotation') != null) {
          throw const FormatException(
            'Annotation already exists; use a conditional update',
          );
        }
        put(value, 'annotation');
        return null;
      case 'updateAnnotation':
        final value = record(args['id'] as String, 'annotation');
        if (value == null || value['bookId'] != args['bookId']) {
          throw const FormatException('Unknown annotation for this book');
        }
        final changes = (args['changes'] as Map).cast<String, dynamic>();
        if (changes.keys.any((key) => !['note', 'color'].contains(key))) {
          throw const FormatException('Invalid annotation field');
        }
        value.addAll(changes);
        validateAnnotation(value, book(value['bookId'] as String)!);
        database.execute(
          "UPDATE records SET json=? WHERE id=? AND kind='annotation' AND book_id=?",
          [jsonEncode(value), value['id'], args['bookId']],
        );
        if (database.updatedRows != 1) {
          throw const FormatException('Unknown annotation for this book');
        }
        return value;
      case 'deleteAnnotation':
        database.execute('DELETE FROM records WHERE id=? AND kind=?', [
          args,
          'annotation',
        ]);
        return null;
      case 'coverData':
        final data = args as String;
        if (data.length > 6 * 1024 * 1024 || !data.startsWith('data:image/')) {
          throw const FormatException('Cover exceeds resource limit');
        }
        return libraryCover(
          base64Decode(data.split(',').last),
          data.split(';').first.replaceFirst('data:', ''),
        );
      case 'cover':
        final file = File(args as String);
        if (await file.length() > 4 * 1024 * 1024) {
          throw const FormatException('Cover exceeds 4 MiB');
        }
        return libraryCover(
          await file.readAsBytes(),
          p.extension(file.path).toLowerCase() == '.svg'
              ? 'image/svg+xml'
              : 'image/png',
        );
      case 'exportOriginal':
        final value = book(args['id'] as String)!;
        final source = await verifiedPath(value, args['source'] as String?);
        final target = p.normalize(p.absolute(args['path'] as String));
        await protectOriginalTarget(target);
        if (p.equals(source, target) ||
            (await File(target).exists() &&
                p.equals(source, await File(target).resolveSymbolicLinks()))) {
          throw const FileSystemException(
            'Choose a different export destination from the original book',
          );
        }
        await const AtomicFileWriter().writeGenerated(target, (staged) async {
          final sink = staged.openWrite();
          try {
            await sink.addStream(File(source).openRead());
          } finally {
            await sink.close();
          }
          if ((await sha256.bind(staged.openRead()).first).toString() !=
              value['id']) {
            throw const FileSystemException(
              'Original book changed during export',
            );
          }
        }, overwrite: args['overwrite'] == true);
        return null;
      case 'exportMarkdown':
        await protectOriginalTarget(args['path'] as String);
        final value = book(args['id'] as String)!;
        final annotations = this.annotations(value['id'] as String)
          ..sort(compareAnnotationLocations);
        final output = StringBuffer(
          '# ${value['title']}\n\n${value['author']}\n',
        );
        for (final a in annotations) {
          final savedReference = a['reference'] as String? ?? '';
          final reference =
              savedReference.isNotEmpty &&
                  !savedReference.contains('epubcfi(') &&
                  !savedReference.startsWith('{')
              ? savedReference
              : a['anchor']['page'] is int
              ? 'Page ${(a['anchor']['page'] as int) + 1}'
              : a['anchor']['index'] is int
              ? 'Section ${(a['anchor']['index'] as int) + 1}'
              : 'Saved location';
          output.writeln(
            '\n## $reference${a['annotationKind'] == 'region' ? ' · Region note' : ''}\n',
          );
          if (a['annotationKind'] == 'region') {
            final region = a['anchor']['region'] as List;
            output.writeln(
              'Image region (oriented page, relative x/y/width/height): ${region.map((n) => (n as num).toStringAsFixed(6)).join(', ')}\n',
            );
          }
          final text = a['text'] as String? ?? '';
          if (text.isNotEmpty) {
            output.writeln(
              text.split('\n').map((line) => '> $line').join('\n'),
            );
          }
          if ((a['note'] as String? ?? '').isNotEmpty) {
            output.writeln('\n${a['note']}');
          }
          output.writeln(
            '\n<!-- BusyBooks anchor: ${jsonEncode(a['anchor']).replaceAll('--', r'\u002d\u002d')} -->',
          );
        }
        await const AtomicFileWriter().writeBytes(
          args['path'] as String,
          utf8.encode(output.toString()),
          overwrite: args['overwrite'] == true,
        );
        return null;
      case 'backup':
        await protectOriginalTarget(args['path'] as String);
        // Serialized worker + a read transaction gives one logical snapshot.
        late List<Map<String, dynamic>> exported;
        transaction(() {
          exported = backupRecords();
        });
        validateRestore(exported);
        final bytes = encodeReadingBackup(
          exported,
          normalizeAppPreferences(
            (args['preferences'] as Map).cast<String, dynamic>(),
          ),
        );
        await const AtomicFileWriter().writeGenerated(args['path'] as String, (
          staged,
        ) async {
          final encoder = ZipFileEncoder()
            ..create(
              staged.path,
              level: ZipFileEncoder.store,
              modified: DateTime.utc(2000),
            );
          try {
            encoder.addArchiveFile(
              ArchiveFile('manifest.json', bytes.length, bytes),
            );
          } finally {
            await encoder.close();
          }
        }, overwrite: args['overwrite'] == true);
        return null;
      case 'restore':
        return restore(args as String);
      case 'pendingPreferences':
        final rows = database.select('SELECT json FROM metadata WHERE key=?', [
          'restore-preferences',
        ]);
        return rows.isEmpty ? null : jsonDecode(rows.single['json'] as String);
      case 'acknowledgePreferences':
        database.execute('DELETE FROM metadata WHERE key=?', [
          'restore-preferences',
        ]);
        return null;
      case 'flush':
        database.execute('PRAGMA wal_checkpoint(FULL)');
        return null;
      case 'close':
        await _clearInspectedComic();
        database.execute('PRAGMA wal_checkpoint(TRUNCATE)');
        database.close();
        await lock?.unlock();
        await lock?.close();
        return null;
      default:
        throw ArgumentError('Unknown reading/workspace operation: $action');
    }
  }

  Future<void> protectOriginalTarget(String target) async {
    final absolute = p.normalize(p.absolute(target));
    final paths = {absolute};
    if (await File(absolute).exists()) {
      paths.add(await File(absolute).resolveSymbolicLinks());
    }
    for (final path in paths) {
      if (database.select(
        'SELECT book_id FROM locations WHERE path=? LIMIT 1',
        [path],
      ).isNotEmpty) {
        throw const FileSystemException(
          'An export or backup cannot overwrite a saved original book location',
        );
      }
    }
    for (final row in database.select('SELECT json FROM move_operations')) {
      final operation = jsonDecode(row['json'] as String) as Map;
      for (final key in ['source', 'destination', 'stagePath', 'quarantine']) {
        final ownedPath = operation[key];
        if (ownedPath is String &&
            paths.any((path) => p.equals(path, ownedPath))) {
          throw const FileSystemException(
            'An export or backup cannot overwrite a pending Move Book location',
          );
        }
      }
    }
  }

  Future<String> verifiedPath(
    Map<String, dynamic> value,
    String? preferred,
  ) async {
    for (final path in [
      if (preferred != null) preferred,
      ...(value['paths'] as List).cast<String>(),
    ]) {
      try {
        return (await openBook(path, expected: value['id'] as String))['path']
            as String;
      } catch (_) {
        /* Try another explicitly known location of this identity. */
      }
    }
    throw WorkspaceException(
      'missing',
      preferred ?? '',
      'Locate the original book before exporting it',
      bookId: value['id'] as String,
    );
  }

  Map<String, dynamic> _backupBook(Map<String, dynamic> book) {
    final value = Map<String, dynamic>.from(book);
    // Explicit and historical edited covers are owned metadata. Only a known
    // regenerable cover is omitted; no original is inspected for backup.
    if (book['coverEdited'] != true &&
        !(book['coverEdited'] == null && book['metadataEdited'] == true)) {
      value.remove('cover');
    }
    return value;
  }

  List<Map<String, dynamic>> backupRecords() {
    final count =
        database
                .select(
                  "SELECT (SELECT count(*) FROM records WHERE kind IN ('book','annotation'))+(SELECT count(*) FROM collections)+(SELECT count(*) FROM memberships)+(SELECT count(*) FROM locations)+(SELECT count(*) FROM recent_resources) AS n",
                )
                .single['n']
            as int;
    validateBackupResources(recordCount: count);
    return [
      ...records('book').map(_backupBook),
      ...records('annotation'),
      ...database
          .select('SELECT * FROM collections')
          .map((r) => {...r, 'kind': 'collection'}),
      ...database
          .select('SELECT * FROM memberships')
          .map((r) => {...r, 'kind': 'membership'}),
      ...database
          .select('SELECT * FROM locations')
          .map((r) => {...r, 'kind': 'location'}),
      ...database
          .select('SELECT * FROM recent_resources')
          .map((r) => {...r, 'resourceKind': r['kind'], 'kind': 'recent'}),
    ];
  }

  void validateRestore(List<Map<String, dynamic>> values) {
    validateBackupResources(recordCount: values.length);
    final books = <String, Map>{},
        collections = <String>{},
        ids = <String>{},
        relationships = <String>{};
    for (final v in values) {
      if (['book', 'annotation', 'collection'].contains(v['kind'])) {
        if (v['id'] is! String || !ids.add(v['id'])) {
          invalid('duplicate entity identity');
        }
        final existing = database.select(
          'SELECT kind,book_id FROM records WHERE id=?',
          [v['id']],
        );
        if (existing.isNotEmpty &&
            (existing.single['kind'] != v['kind'] ||
                (v['kind'] == 'annotation' &&
                    existing.single['book_id'] != v['bookId']))) {
          invalid('conflicting entity identity');
        }
      }
      if (v['kind'] == 'book') {
        validateBook(v);
        books[v['id'] as String] = v;
      }
      if (v['kind'] == 'collection') {
        if (v['id'] is! String || !collectionIdentity.hasMatch(v['id'])) {
          invalid('collection identity');
        }
        checkCollectionName(v['name']);
        if (v['created'] is! int || v['created'] < 0) {
          invalid('collection date');
        }
        collections.add(v['id']);
      }
    }
    for (final v in values) {
      switch (v['kind']) {
        case 'book':
          if (v['appearance'] != null) {
            v['appearance'] = normalizeReadingAppearance(v['appearance']);
          }
        case 'annotation':
          final parent = books[v['bookId']];
          if (parent == null) invalid('dangling annotation');
          validateAnnotation(v, parent);
        case 'collection':
          break;
        case 'membership':
          if (!collections.contains(v['collection_id']) ||
              !books.containsKey(v['book_id']) ||
              v['added'] is! int ||
              v['added'] < 0 ||
              !relationships.add(
                'member:${v['collection_id']}:${v['book_id']}',
              )) {
            invalid('membership');
          }
        case 'location':
          if (!books.containsKey(v['book_id'])) invalid('dangling location');
          validatePath(v['path']);
          if (!relationships.add('location:${v['book_id']}:${v['path']}') ||
              (v['preferred'] == 1 &&
                  !relationships.add('preferred:${v['book_id']}')) ||
              ![
                'available',
                'unverified',
                'missing',
                'denied',
                'changed',
              ].contains(v['status']) ||
              ![0, 1].contains(v['preferred']) ||
              (v['verified'] != null &&
                  (v['verified'] is! int || v['verified'] < 0))) {
            invalid('location');
          }
        case 'recent':
          if (v['opened'] is! int || v['opened'] < 0) invalid('recent date');
          final kind = v['resourceKind'];
          if (!(kind == 'book' && books.containsKey(v['resource_id']) ||
                  kind == 'collection' &&
                      collections.contains(v['resource_id'])) ||
              !relationships.add('recent:$kind:${v['resource_id']}')) {
            invalid('recent identity');
          }
        default:
          invalid('entity kind');
      }
    }
    for (final b in books.values) {
      for (final path in b['paths'] as List) {
        if (!relationships.contains('location:${b['id']}:$path')) {
          invalid('book location reference');
        }
      }
    }
  }

  void publishRestore(List<Map<String, dynamic>> values) {
    for (final kind in [
      'book',
      'collection',
      'annotation',
      'location',
      'membership',
      'recent',
    ]) {
      for (final v in values.where((v) => v['kind'] == kind)) {
        switch (kind) {
          case 'book':
            database.execute(
              'UPDATE locations SET preferred=0 WHERE book_id=?',
              [v['id']],
            );
            put(v, kind);
          case 'annotation':
            put(v, kind);
          case 'collection':
            database.execute(
              'INSERT INTO collections(id,name,created) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,created=excluded.created',
              [v['id'], v['name'], v['created']],
            );
          case 'membership':
            database.execute(
              'INSERT INTO memberships(collection_id,book_id,added) VALUES(?,?,?) ON CONFLICT(collection_id,book_id) DO UPDATE SET added=excluded.added',
              [v['collection_id'], v['book_id'], v['added']],
            );
          case 'location':
            database.execute(
              'INSERT INTO locations(book_id,path,status,verified,preferred) VALUES(?,?,?,?,?) ON CONFLICT(book_id,path) DO UPDATE SET status=excluded.status,verified=NULL,preferred=excluded.preferred',
              [v['book_id'], v['path'], 'unverified', null, v['preferred']],
            );
          case 'recent':
            database.execute(
              'INSERT INTO recent_resources(kind,resource_id,opened) VALUES(?,?,?) ON CONFLICT(kind,resource_id) DO UPDATE SET opened=excluded.opened',
              [v['resourceKind'], v['resource_id'], v['opened']],
            );
        }
      }
    }
  }

  Future<Map<String, dynamic>> restore(String source) async {
    if (database.select('SELECT id FROM move_operations LIMIT 1').isNotEmpty) {
      throw const FormatException(
        'Resolve the pending Move Book operation before restoring reading data.',
      );
    }
    final input = InputFileStream(source);
    try {
      checkZipEntryCount(input);
      final directory = ZipDirectory()..read(input);
      validateZipDirectory(directory, maximumTotal: maximumBackupManifestBytes);
      if (directory.fileHeaders.length != 1 ||
          directory.fileHeaders.single.filename != 'manifest.json') {
        throw const FormatException(
          'Reading-data backups contain only a manifest, never book files',
        );
      }
      final entry = directory.fileHeaders.single;
      validateBackupResources(encodedBytes: entry.uncompressedSize);
      final manifest = jsonDecode(utf8.decode(readZipEntry(entry))) as Map;
      if (manifest['type'] != 'busybooks-reading-data' ||
          manifest['schema'] != readingBackupSchema ||
          manifest['records'] is! List ||
          manifest['preferences'] is! Map) {
        throw const FormatException('Unsupported reading-data backup');
      }
      final values = (manifest['records'] as List)
          .map((x) => (x as Map).cast<String, dynamic>())
          .toList();
      validateRestore(values);
      final preferences = normalizeAppPreferences(
        (manifest['preferences'] as Map).cast<String, dynamic>(),
      );
      if (cancelled) throw const FormatException('Restore cancelled');
      transaction(() {
        publishRestore(values);
        database.execute(
          'INSERT OR REPLACE INTO metadata(key,json) VALUES(?,?)',
          ['restore-preferences', jsonEncode(preferences)],
        );
      });
      return preferences;
    } finally {
      await input.close();
    }
  }
}
