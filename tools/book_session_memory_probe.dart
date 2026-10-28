// Run with the unmodified SDK in profile mode. Debug Riverpod records provider
// history for DevTools, which intentionally retains disposed debug objects.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:busybooks/src/app/app_router.dart';
import 'package:busybooks/src/app/app_settings.dart';
import 'package:busybooks/src/book_workspace/application/book_sidebar_controller.dart';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/reading/domain/publication_outline.dart';
import 'package:busybooks/src/search/book_search_session.dart';
import 'package:busybooks/src/workspace/workspace_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) throw StateError('Use an actual profile or release build');
  final directory = await Directory.systemTemp.createTemp(
    'busybooks-session-memory-',
  );
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('Book session memory probe')),
    ),
  );
  final store = await ReadingDataStore.open(p.join(directory.path, 'profile'));
  final container = ProviderContainer(
    overrides: [
      readingDataStoreProvider.overrideWithValue(store),
      startupAppSettingsProvider.overrideWithValue(
        StartupAppSettings(
          AppSettings(),
          JsonFileLocalSettingsStore(p.join(directory.path, 'settings.json')),
        ),
      ),
    ],
  );
  try {
    final workspace = container.read(workspaceControllerProvider.notifier);
    final router = container.read(appRouterProvider);
    final bytes = await File('test/fixtures/text.pdf').readAsBytes();
    final samples = <Map<String, int>>[];
    final service = (await developer.Service.getInfo()).serverUri;
    for (var visit = 0; visit < 180; visit++) {
      final index = visit % 60;
      final file = File(p.join(directory.path, 'book-$index.pdf'));
      if (!await file.exists()) {
        await file.writeAsBytes([
          ...bytes,
          ...utf8.encode('\n% book $index\n'),
        ]);
      }
      final id = (await workspace.openPath(file.path)).books.single.id;
      router.go('/notebook/$id');
      container
          .read(bookSidebarProvider(id).notifier)
          .publication(
            outline: PublicationOutline.fromRecords([
              for (var chapter = 0; chapter < 300; chapter++)
                {
                  'id': '$index:$chapter',
                  'label': 'Book $index chapter $chapter',
                  'depth': 0,
                  'href': 'chapter-$chapter.xhtml',
                },
            ], pdf: false),
            status: 'ready',
            pages: 300,
            labels: List.generate(300, (i) => '$i'),
          );
      await container
          .read(bookSearchSessionProvider.notifier)
          .open(category: BookSearchCategory.chapters, query: 'chapter');
      final deadline = Stopwatch()..start();
      while (container.read(bookSearchSessionProvider).loading) {
        if (deadline.elapsed > const Duration(seconds: 5)) {
          throw StateError('Search did not finish');
        }
        await Future<void>.delayed(Duration.zero);
      }
      while (container.read(bookSearchSessionProvider).hasMore) {
        await container.read(bookSearchSessionProvider.notifier).showMore();
      }
      if (container.read(bookSearchSessionProvider).results.length != 300) {
        throw StateError('Incomplete search');
      }
      await container.pump();
      if ((visit + 1) % 20 == 0) {
        final sample = <String, int>{
          'visits': visit + 1,
          'distinctBooks': visit < 60 ? visit + 1 : 60,
          'searchProviders': container.exists(bookSearchSessionProvider)
              ? 1
              : 0,
          'sidebarProviders': container
              .allProviders(family: bookSidebarProvider)
              .length,
          'rssBytes': ProcessInfo.currentRss,
        };
        if (service != null) {
          final client = HttpClient();
          try {
            final request = await client.getUrl(
              service
                  .resolve('getAllocationProfile')
                  .replace(
                    queryParameters: {
                      'isolateId': developer.Service.getIsolateId(
                        Isolate.current,
                      )!,
                      'gc': 'true',
                    },
                  ),
            );
            final response =
                jsonDecode(
                      await utf8.decoder.bind(await request.close()).join(),
                    )
                    as Map;
            if (response['error'] != null) {
              throw StateError('VM allocation query failed');
            }
            final result = response['result'] as Map;
            sample['heapUsedBytes'] =
                (result['memoryUsage'] as Map)['heapUsage'] as int;
            for (final name in [
              'BookSearchController',
              'BookSidebarController',
            ]) {
              sample['${name}Instances'] = (result['members'] as List)
                  .cast<Map>()
                  .where((m) => (m['class'] as Map)['name'] == name)
                  .fold<int>(0, (n, m) => n + (m['instancesCurrent'] as int));
            }
          } finally {
            client.close(force: true);
          }
        }
        samples.add(sample);
        stdout.writeln('BOOK_SESSION_MEMORY ${jsonEncode(sample)}');
        if (sample['searchProviders'] != 1 || sample['sidebarProviders'] != 1) {
          throw StateError('Unbounded active sessions');
        }
        if ((sample['BookSearchControllerInstances'] ?? 0) > 2 ||
            (sample['BookSidebarControllerInstances'] ?? 0) > 2) {
          throw StateError('Disposed controllers retained in profile mode');
        }
      }
    }
    await workspace.closeWorkspace();
    router.go('/');
    await container.pump();
    await Future<void>.delayed(Duration.zero);
    container
        .read(bookSearchSessionProvider.notifier)
        .close(restoreFocus: false);
    // The single lightweight window session remains; old book metadata and
    // result pages must be released with their sidebar providers.
    final remaining = container
        .allProviders(family: bookSidebarProvider)
        .length;
    if (remaining != 0 ||
        container.read(bookSearchSessionProvider).results.isNotEmpty) {
      throw StateError('Session subscriptions survived close');
    }
    await File(p.join(directory.path, 'result.json')).writeAsString(
      jsonEncode({
        'mode': kProfileMode ? 'profile' : 'release',
        'samples': samples,
        'remainingProviders': remaining,
        'passed': true,
      }),
    );
    stdout.writeln(
      'BOOK_SESSION_MEMORY_PASSED ${p.join(directory.path, 'result.json')}',
    );
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exitCode = 1;
  } finally {
    container.dispose();
    await store.close();
  }
}
