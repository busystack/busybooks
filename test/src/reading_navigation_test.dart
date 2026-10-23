import 'package:busybooks/src/core/reading_preferences.dart';
import 'package:busybooks/src/app/app_router.dart';
import 'package:busybooks/src/reading/domain/reading_navigation.dart';
import 'package:busybooks/src/reading/domain/publication_outline.dart';
import 'package:busybooks/src/reading/application/reader_sidebar_state.dart';
import 'package:busybooks/src/annotations/presentation/annotation_presentation.dart';
import 'package:busybooks/src/library/application/collection_view_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:busybooks/src/app/command_registry.dart';
import 'package:busybooks/src/app/shortcut_binding.dart';
import 'package:busybooks/src/reading/application/reader_controller.dart';

void main() {
  test(
    'Settings return targets allow only known internal book and workspace routes',
    () {
      final id = 'a' * 64;
      for (final target in ['/', '/workspace', '/read/$id', '/notebook/$id']) {
        expect(safeSettingsReturnTarget(target), target);
      }
      for (final target in [
        null,
        '/settings',
        'https://example.com',
        '//example.com',
        '/read/../settings',
        '/notebook/unknown',
        '/workspace?unsafe=true',
      ]) {
        expect(safeSettingsReturnTarget(target), '/');
      }
    },
  );

  test(
    'publication tree preserves mixed depths, repeated titles and exact destinations without fabricated grouping targets',
    () {
      final records = <Map<String, dynamic>>[
        {'id': 'group', 'label': 'Front matter', 'depth': 0},
        {
          'id': 'a',
          'label': 'Contents',
          'depth': 2,
          'anchor': {
            'page': 92,
            'point': [20, 700],
          },
        },
        {
          'id': 'b',
          'label': 'Contents',
          'depth': 2,
          'anchor': {
            'page': 92,
            'point': [20, 300],
          },
        },
        {
          'id': 'invalid',
          'label': 'Unresolved',
          'depth': 3,
          'href': 'not a page',
        },
        {
          'id': 'last',
          'label': 'Last',
          'depth': 0,
          'anchor': {'page': 100, 'y': .25},
        },
      ];
      final tree = PublicationOutline.fromRecords(records, pdf: true);
      expect(tree.roots.map((n) => n.id), ['group', 'last']);
      expect(tree.byId['group']!.children.map((n) => n.id), ['a', 'b']);
      expect(tree.byId['b']!.children.single.id, 'invalid');
      expect(tree.byId['group']!.destination, isNull);
      expect(tree.byId['invalid']!.destination, isNull);
      expect(tree.byId['b']!.destination, {
        'page': 92,
        'point': [20, 300],
      });
      expect(
        tree.activeAt({
          'tocId': 'b',
          'anchor': {'page': 92},
        }),
        'b',
      );
      expect(tree.activeAt({'tocHref': '92'}), isNull);
      expect(tree.visibleAncestor('b', {}), 'group');
      expect(tree.visible({'group'}).map((n) => n.id), [
        'group',
        'a',
        'b',
        'last',
      ]);
      expect(tree.byId['a']!.title, 'Contents');
      final epub = PublicationOutline.fromRecords([
        {'label': 'Contents', 'href': 'text.xhtml#part', 'depth': 0},
      ], pdf: false);
      expect(epub.ordered.single.destination, {'href': 'text.xhtml#part'});
      expect(epub.ordered.single.pageLabel, isNull);
    },
  );
  test(
    'large and deep publication trees have stable independent identities and iterative traversal',
    () {
      final rows = List<Map<String, dynamic>>.generate(
        10000,
        (i) => {'label': 'Repeated', 'depth': i, 'href': 'chapter.xhtml#s$i'},
      );
      final tree = PublicationOutline.fromRecords(rows, pdf: false);
      expect(tree.ordered.map((n) => n.id).toSet(), hasLength(10000));
      expect(
        tree.visible(tree.ordered.map((n) => n.id).toSet()),
        hasLength(10000),
      );
      expect(
        tree.visibleAncestor(tree.ordered.last.id, {}),
        tree.roots.single.id,
      );
    },
  );
  test(
    'sidebar state retains deliberate collapse and each book view across metadata and panel changes',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(readerSidebarProvider('one').notifier);
      final tree = PublicationOutline.fromRecords([
        {'id': 'group', 'label': 'Repeated', 'depth': 0},
        {
          'id': 'child',
          'label': 'Repeated',
          'depth': 1,
          'href': 'one.xhtml#fragment',
        },
      ], pdf: false);
      controller.reconcile(tree);
      expect(container.read(readerSidebarProvider('one')).expanded, {'group'});
      controller.toggle('group');
      controller.scrolled('outline', 240);
      controller.scrolled('annotations', 64);
      controller.filter(kind: 'bookmark', withNotes: true);
      controller.remember(
        panel: 'annotations',
        open: false,
        query: 'passage',
        currentMatch: 2,
      );
      controller.reconcile(
        PublicationOutline.fromRecords([
          {'id': 'group', 'label': 'Repeated', 'depth': 0},
          {
            'id': 'child',
            'label': 'Repeated',
            'depth': 1,
            'href': 'one.xhtml#fragment',
            'pageLabel': 'iv',
          },
        ], pdf: false),
      );
      final state = container.read(readerSidebarProvider('one'));
      expect(state.expanded, isEmpty);
      expect(state.scroll, {'outline': 240.0, 'annotations': 64.0});
      expect(state.filter, 'bookmark');
      expect(state.withNotes, isTrue);
      expect(state.query, 'passage');
      expect(container.read(readerSidebarProvider('two')).expanded, isEmpty);
      expect(container.read(readerSidebarProvider('two')).scroll, isEmpty);
      expect(container.read(readerSidebarProvider('two')).filter, 'all');
    },
  );
  test(
    'publication page references use supplied labels and never assume EPUB spine pagination',
    () {
      expect(
        PublicationPageReference.pdf(
          92,
          322,
          List.generate(322, (i) => '${i - 25}'),
        ).display,
        '67',
      );
      expect(
        PublicationPageReference.pdf(0, 3, ['iv', 'v', 'vi']).display,
        'iv',
      );
      expect(PublicationPageReference.pdf(2, 3, []).display, '3');
      const unavailable = PublicationPageReference();
      expect(unavailable.display, '—');
      expect(unavailable.physicalPage, isNull);
    },
  );
  test(
    'saved-item previews are bounded without changing Unicode note data',
    () {
      final note = 'A😀\n${'B' * 1000000}';
      final preview = annotationPreview(note);
      expect(preview.length, lessThanOrEqualTo(513));
      expect(preview, startsWith('A😀 '));
      expect(note.length, 1000004);
      expect(note, contains('\n'));
    },
  );

  test(
    'native keys choose the enabled document command before an application shortcut',
    () {
      final registry = BusyBooksCommandCatalog.create(
        executions: {
          BusyBooksCommandIds.search: () {},
          BusyBooksCommandIds.searchCollection: () {},
        },
        enabled: {BusyBooksCommandIds.searchCollection: () => false},
      );
      const binding = BusyBooksKeyBinding(
        LogicalKeyboardKey.keyF,
        control: true,
      );
      expect(
        registry.commandForNativeBinding(binding)?.id,
        BusyBooksCommandIds.search,
      );
      final both = BusyBooksCommandCatalog.create(
        executions: {
          BusyBooksCommandIds.search: () {},
          BusyBooksCommandIds.searchCollection: () {},
        },
      );
      expect(
        both.commandForNativeBinding(binding)?.id,
        BusyBooksCommandIds.search,
      );
      final collection = BusyBooksCommandCatalog.create(
        executions: {
          BusyBooksCommandIds.search: () {},
          BusyBooksCommandIds.searchCollection: () {},
        },
        enabled: {BusyBooksCommandIds.search: () => false},
      );
      expect(
        collection.commandForNativeBinding(binding)?.id,
        BusyBooksCommandIds.searchCollection,
      );
    },
  );
  test('speech can visit the second page of a final spread', () {
    const state = ReaderState(
      ready: true,
      navigation: {'next': false, 'speechNext': true},
    );
    expect(state.canNext, isFalse);
    expect(state.canSpeakNext, isTrue);
  });
  test('reader failures survive unrelated sidebar and selection updates', () {
    const error = ReaderState(bookId: 'fixture', error: 'Original unavailable');
    expect(
      error.copy(panel: 'annotations', panelOpen: true).error,
      'Original unavailable',
    );
  });
  test(
    'Go To separates physical page numbers from supplied labels and rejects invalid or ambiguous input',
    () {
      const labels = ['i', 'ii', '17', '18'];
      int? resolve(String text, bool printed) =>
          resolvePdfPage(text, pages: 4, labels: labels, printedLabel: printed);
      expect(resolve('3', false), 2);
      expect(resolve('17', true), 2);
      expect(resolve('ii', true), 1);
      for (final text in ['', '0', '5', '-1', '1.5', 'ii', '17']) {
        expect(resolve(text, false), isNull);
      }
      expect(resolve('3', true), isNull);
      expect(
        resolvePdfPage(
          '1',
          pages: 3,
          labels: ['1', '1', '2'],
          printedLabel: true,
        ),
        isNull,
      );
    },
  );
  test(
    'PDF bookmarks identify the page independently of viewport coordinates',
    () {
      expect(
        sameBookmarkLocation(
          {
            'page': 2,
            'point': [0, 700],
          },
          {
            'page': 2,
            'point': [24, 400],
          },
        ),
        isTrue,
      );
      expect(sameBookmarkLocation({'page': 2}, {'page': 3}), isFalse);
      expect(
        sameBookmarkLocation(
          {'cfi': 'epubcfi(/6/2!/4/2:3)'},
          {'cfi': 'epubcfi(/6/2!/4/2:3)'},
        ),
        isTrue,
      );
      expect(sameBookmarkLocation({}, {}), isFalse);
    },
  );
  test(
    'PDF defaults are continuous Fit Width, with independently saved EPUB and PDF preferences',
    () {
      final p = normalizeAppPreferences({});
      expect((p['pdfReading'] as Map)['flow'], 'scrolled');
      expect((p['pdfReading'] as Map)['zoom'], 'fit-width');
      expect((p['reading'] as Map)['flow'], 'paginated');
      final saved = normalizeAppPreferences({
        'pdfReading': {
          ...defaultPdfAppearance,
          'zoom': 'fit-page',
          'flow': 'paginated',
        },
        'readerSidebar': true,
        'readerPanel': 'annotations',
      });
      expect((saved['pdfReading'] as Map)['zoom'], 'fit-page');
      expect(saved['readerSidebar'], isTrue);
      expect(saved['readerPanel'], 'annotations');
    },
  );
  test(
    'collection view sessions retain query filter position and selected book by collection identity',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(collectionViewProvider('collection:${'a' * 32}').notifier)
          .update(
            query: 'library',
            filter: 'reading',
            selectedBook: 'sha256-one',
            scrollOffset: 512,
          );
      container
          .read(collectionViewProvider('collection:${'b' * 32}').notifier)
          .update(query: 'other');
      final first = container.read(
        collectionViewProvider('collection:${'a' * 32}'),
      );
      expect(first.query, 'library');
      expect(first.filter, 'reading');
      expect(first.selectedBook, 'sha256-one');
      expect(first.scrollOffset, 512);
      expect(
        container.read(collectionViewProvider('collection:${'b' * 32}')).query,
        'other',
      );
    },
  );
}
