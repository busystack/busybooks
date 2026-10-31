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
  final _initialFocus = FocusNode(debugLabel: 'Reader information panel');

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
            'reader-panel stage=presented kind=lookup session=${widget.panel.session} presentation=${widget.panel.presentation}',
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _initialFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reader = ref.read(readerControllerProvider.notifier);
    final l = context.l10n;
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
                            l.lookUp,
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
                  ..._lookup(context, reader),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
