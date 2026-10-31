import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../app/busybooks_design.dart';
import '../../app/busybooks_glyphs.dart';
import '../../app/localization.dart';
import '../application/reader_controller.dart';
import '../domain/publication_outline.dart';
import '../domain/reading_navigation.dart';
import 'publication_location.dart';

/// An ordinary part of the reading pane's layout. The measured native viewport
/// starts below it, so neither platform needs an overlay window or input grab.
class ReaderInformationPanel extends ConsumerStatefulWidget {
  const ReaderInformationPanel({super.key, required this.panel});
  final ReaderPanel panel;

  @override
  ConsumerState<ReaderInformationPanel> createState() =>
      _ReaderInformationPanelState();
}

class _ReaderInformationPanelState
    extends ConsumerState<ReaderInformationPanel> {
  final _entry = TextEditingController();
  final _initialFocus = FocusNode(debugLabel: 'Reader information panel');
  String? _error;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          ref
              .read(readerControllerProvider.notifier)
              .ownsReaderPanel(widget.panel)) {
        _initialFocus.requestFocus();
      }
    });
    if (Platform.environment['BUSYBOOKS_READER_DIAGNOSTICS'] == '1') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            ref
                .read(readerControllerProvider.notifier)
                .ownsReaderPanel(widget.panel)) {
          debugPrint(
            'reader-panel stage=presented kind=${widget.panel.kind == ReaderPanelKind.goTo ? 'goto' : 'lookup'} session=${widget.panel.session} presentation=${widget.panel.presentation}',
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _initialFocus.dispose();
    _entry.dispose();
    super.dispose();
  }

  Future<void> _navigate(Map<String, dynamic> anchor) async {
    final reader = ref.read(readerControllerProvider.notifier);
    if (_navigating || !reader.ownsReaderPanel(widget.panel)) return;
    setState(() {
      _navigating = true;
      _error = null;
    });
    try {
      await reader.navigateFromPanel(widget.panel, anchor);
    } catch (_) {
      if (mounted && reader.ownsReaderPanel(widget.panel)) {
        setState(() => _error = context.l10n.navigationInterrupted);
      }
    } finally {
      if (mounted) setState(() => _navigating = false);
    }
  }

  void _go() {
    if (_navigating) return;
    final reader = ref.read(readerControllerProvider.notifier);
    final state = ref.read(readerControllerProvider);
    Map<String, dynamic>? anchor;
    if (reader.pageNavigation) {
      final page = resolvePageDestination(
        _entry.text,
        pages: state.pages,
        labels: reader.regionNotes ? const [] : state.labels,
      );
      if (page != null) anchor = {'page': page};
    } else {
      final progress = double.tryParse(_entry.text.trim());
      if (progress != null &&
          progress.isFinite &&
          progress >= 0 &&
          progress <= 100) {
        anchor = {'fraction': progress / 100};
      }
    }
    if (anchor == null) {
      setState(
        () => _error = reader.pageNavigation
            ? context.l10n.invalidPage
            : context.l10n.invalidProgress,
      );
    } else {
      unawaited(_navigate(anchor));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reader = ref.read(readerControllerProvider.notifier);
    final state = ref.watch(readerControllerProvider);
    final l = context.l10n;
    final goTo = widget.panel.kind == ReaderPanelKind.goTo;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            unawaited(reader.dismissReaderControls()),
      },
      child: FocusTraversalGroup(
        child: Material(
          color: BusyBooksSurfaceColors.of(context).panel,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: BusyBooksSurfaceColors.of(context).divider,
                ),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(BusyBooksSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            goTo ? l.goTo : l.lookUp,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ),
                      BusyBooksHeaderIconButton(
                        tooltip: l.close,
                        icon: BusyBooksGlyphs.close,
                        onPressed: () => reader.dismissReaderControls(),
                      ),
                    ],
                  ),
                  if (goTo)
                    ..._goTo(context, reader, state)
                  else
                    ..._lookup(context, reader),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _goTo(
    BuildContext context,
    ReaderController reader,
    ReaderState state,
  ) {
    final l = context.l10n;
    final page = (state.location['anchor'] as Map?)?['page'] as int?;
    final chapters = state.toc
        .where((e) => e['href'] is String && (e['href'] as String).isNotEmpty)
        .toList();
    return [
      Text(
        reader.pageNavigation && page != null
            ? describePublicationPage(
                l,
                PublicationPageReference.pdf(page, state.pages, state.labels),
              )
            : '${state.location['chapter'] ?? ''} · ${((state.location['progress'] as num? ?? 0) * 100).round()}%',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      BusyBooksGroupedList(
        children: [
          BusyBooksGroupedTextEntry(
            key: const ValueKey('goto-entry'),
            label: reader.pageNavigation
                ? (reader.regionNotes ? l.pageNumber : l.pageDestination)
                : l.bookProgress,
            controller: _entry,
            focusNode: _initialFocus,
            autofocus: true,
            errorText: _error,
            onSubmitted: (_) => _go(),
            readOnly: _navigating,
          ),
        ],
      ),
      Text(
        reader.pageNavigation
            ? (reader.regionNotes
                  ? '${l.pageNumberHelp} 1–${state.pages}'
                  : l.pageDestinationHelp)
            : l.generatedPages,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: BusyBooksSpacing.sm),
      Wrap(
        spacing: BusyBooksSpacing.sm,
        runSpacing: BusyBooksSpacing.sm,
        children: [
          BusyBooksPushButton.suggested(
            onPressed: _navigating ? null : _go,
            child: Text(l.go),
          ),
          if (reader.regionNotes) ...[
            BusyBooksPushButton.standard(
              onPressed: _navigating ? null : () => _navigate({'page': 0}),
              child: Text(l.firstPage),
            ),
            BusyBooksPushButton.standard(
              onPressed: _navigating
                  ? null
                  : () => _navigate({'page': state.pages - 1}),
              child: Text(l.lastPage),
            ),
          ],
        ],
      ),
      if (chapters.isNotEmpty)
        BusyBooksComboRow<int>(
          activateSelected: true,
          title: l.chapter,
          values: List.generate(chapters.length, (i) => i),
          selected: chapters
              .indexWhere((e) => e['href'] == state.location['tocHref'])
              .clamp(0, chapters.length - 1),
          labelFor: (i) => '${i + 1}. ${chapters[i]['label']}',
          onSelected: (i) {
            if (!_navigating) {
              unawaited(_navigate({'href': chapters[i]['href']}));
            }
          },
        ),
    ];
  }

  List<Widget> _lookup(BuildContext context, ReaderController reader) {
    final l = context.l10n, result = widget.panel.lookup;
    final status = result['status'];
    final message = switch (status) {
      'loading' => l.lookupLoading,
      'missing' => l.lookupMissing,
      'offline' => l.lookupOffline,
      'timeout' => l.lookupTimeout,
      'unavailable' => l.lookupUnavailable,
      'invalid' => l.lookupInvalid,
      'unsupported' => l.lookupUnsupported,
      _ => null,
    };
    return [
      SelectableText(
        widget.panel.term,
        contextMenuBuilder: busyBooksTextContextMenu,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      Text(l.lookupSource, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: BusyBooksSpacing.sm),
      if (status == 'loading') const YaruLinearProgressIndicator(),
      if (message != null) Semantics(liveRegion: true, child: Text(message)),
      if (status == 'ready') ...[
        for (final section in result['sections'] as List? ?? const []) ...[
          Text(
            '${section['language']} · ${section['partOfSpeech']}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          for (final (index, text) in (section['definitions'] as List).indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: BusyBooksSpacing.sm),
              child: SelectableText(
                '${index + 1}. $text',
                contextMenuBuilder: busyBooksTextContextMenu,
              ),
            ),
        ],
        Text(l.lookupExcerpt, style: Theme.of(context).textTheme.bodySmall),
      ],
      const SizedBox(height: BusyBooksSpacing.sm),
      Wrap(
        alignment: WrapAlignment.end,
        spacing: BusyBooksSpacing.sm,
        runSpacing: BusyBooksSpacing.sm,
        children: [
          if (['offline', 'timeout', 'unavailable', 'invalid'].contains(status))
            BusyBooksPushButton.standard(
              key: const ValueKey('lookup-retry'),
              onPressed: () => reader.retryLookup(widget.panel),
              child: Text(l.retry),
            ),
          if (result['entry'] is String)
            BusyBooksPushButton.standard(
              key: const ValueKey('lookup-full-entry'),
              onPressed: () => reader.openLookupEntry(widget.panel),
              child: Text(l.openFullEntry),
            ),
          BusyBooksPushButton.standard(
            key: const ValueKey('lookup-close'),
            focusNode: _initialFocus,
            autofocus: true,
            onPressed: () => reader.dismissReaderControls(),
            child: Text(l.close),
          ),
        ],
      ),
    ];
  }
}
