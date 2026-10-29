import 'package:busybooks/src/book_workspace/application/book_presentation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('passage and note handoffs retain Split for the exact target book', () {
    expect(readingTargetRoute('/split/a', 'b'), '/split/b');
    expect(notebookTargetRoute('/split/a', 'b'), '/split/b');
    expect(
      readingTargetRoute('/split/a', 'a', view: BookView.reading),
      '/read/a',
    );
    expect(
      notebookTargetRoute('/split/a', 'a', view: BookView.notebook),
      '/notebook/a',
    );
    expect(readingTargetRoute('/notebook/a', 'a'), '/read/a');
    expect(readingTargetRoute('/', 'b'), '/read/b');
    expect(notebookTargetRoute('/workspace', 'b'), '/notebook/b');
    expect(
      () => readingTargetRoute('/split/a', 'a', view: BookView.notebook),
      throwsArgumentError,
    );
  });

  test(
    'reader ownership includes both reader views and excludes retained books',
    () {
      expect(sameReaderBookRoutes('/read/a', '/split/a'), isTrue);
      expect(sameReaderBookRoutes('/split/a', '/read/a'), isTrue);
      for (final route in ['/notebook/a', '/split/b', '/settings', '/']) {
        expect(sameReaderBookRoutes('/split/a', route), isFalse);
      }
      for (final route in [
        '/settings',
        '/workspace',
        '/split/',
        '/read/a/other',
      ]) {
        expect(bookIdForRoute(route), isNull);
        expect(bookViewForRoute(route), isNull);
      }
    },
  );

  test(
    'one active presentation retains divider memory and rejects old pane events',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(bookPresentationProvider.notifier);
      controller.enterBook('a', BookView.reading);
      controller.setDividerRatio('a', .62);
      controller.focusPane('a', BookPane.notebook);
      controller.enterBook('a', BookView.split);
      expect(
        container.read(bookPresentationProvider).lastPane,
        BookPane.notebook,
      );
      expect(container.read(bookPresentationProvider).dividerRatio, .62);
      controller.enterBook('a', BookView.reading);
      expect(
        container.read(bookPresentationProvider).lastPane,
        BookPane.reading,
      );
      controller.enterBook('b', BookView.split);
      final current = container.read(bookPresentationProvider);
      controller.focusPane('a', BookPane.notebook);
      controller.setDividerRatio('a', .2);
      expect(
        identical(container.read(bookPresentationProvider), current),
        isTrue,
      );
      expect(current.bookId, 'b');
      expect(current.lastPane, BookPane.reading);
      expect(current.dividerRatio, .62);
      controller.setDividerRatio('b', double.nan);
      expect(
        identical(container.read(bookPresentationProvider), current),
        isTrue,
      );
    },
  );

  test('Split capacity follows measured content width and text scaling', () {
    expect(BookSplitMetrics(1).minimumWidth, 772);
    expect(BookSplitMetrics(1.5).minimumWidth, 976);
    expect(BookSplitMetrics(2).minimumWidth, 1276);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(bookPresentationProvider.notifier);
    controller.enterBook('a', BookView.split);
    controller.focusPane('a', BookPane.notebook);
    controller.setDividerRatio('a', .62);
    controller.updateLayout('a', availableWidth: 772, textScale: 1);
    expect(container.read(bookPresentationProvider).splitAvailable, isTrue);
    // The same window loses content width when its sidebar is allocated.
    controller.updateLayout('a', availableWidth: 700, textScale: 1);
    final collapsed = container.read(bookPresentationProvider);
    expect(collapsed.splitAvailable, isFalse);
    expect(collapsed.lastPane, BookPane.notebook);
    expect(collapsed.dividerRatio, .62);
    controller.updateLayout('a', availableWidth: 1000, textScale: 1.5);
    expect(container.read(bookPresentationProvider).splitAvailable, isTrue);
    controller.updateLayout('a', availableWidth: 1000, textScale: 2);
    expect(container.read(bookPresentationProvider).splitAvailable, isFalse);
    controller.updateLayout('a', availableWidth: 1276, textScale: 2);
    expect(container.read(bookPresentationProvider).splitAvailable, isTrue);
    expect(container.read(bookPresentationProvider).dividerRatio, .62);
    controller.enterBook('b', BookView.reading);
    final next = container.read(bookPresentationProvider);
    expect(next.availableWidth, isNull);
    controller.updateLayout('a', availableWidth: 2000, textScale: 1);
    expect(identical(container.read(bookPresentationProvider), next), isTrue);
  });
}
