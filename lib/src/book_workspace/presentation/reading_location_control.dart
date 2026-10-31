import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/busybooks_design.dart';
import '../../app/linux/linux_header_style.dart';
import '../../app/localization.dart';
import '../../app/product_actions.dart';
import '../../reading/application/reader_controller.dart';
import '../../reading/domain/publication_outline.dart';
import '../../reading/presentation/publication_location.dart';

class ReadingLocationControl extends ConsumerWidget {
  const ReadingLocationControl({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(readerControllerProvider),
        reader = ref.read(readerControllerProvider.notifier),
        l = context.l10n;
    final page = (state.location['anchor'] as Map?)?['page'] as int?;
    final pdf = reader.book?.pageBased == true;
    final pageReference = pdf && page != null
        ? PublicationPageReference.pdf(page, state.pages, state.labels)
        : null;
    final progress =
        '${((state.location['progress'] as num? ?? reader.book?.progress ?? 0) * 100).round()}%';
    final anchor = state.location['anchor'] as Map?;
    final available =
        state.ready &&
        state.error == null &&
        (pdf
            ? page != null && page >= 0 && page < state.pages
            : anchor?['cfi'] is String || anchor?['index'] is int);
    final title = !available
        ? l.loadingBook
        : pageReference != null
        ? pageReference.display
        : state.location['printPage'] != null
        ? '${state.location['printPage']}'
        : progress;
    final reference = pageReference != null
        ? describePublicationPage(l, pageReference)
        : [
            state.location['chapter']?.toString() ?? l.goTo,
            progress,
          ].where((v) => v.isNotEmpty).join(' · ');
    return Tooltip(
      message: l.goTo,
      positionDelegate: BusyBooksHeaderControlStyleScope.maybeOf(
        context,
      )?.tooltipPositionDelegate,
      child: Semantics(
        button: true,
        label: '${l.goTo} · $reference',
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 132),
          child: TextButton(
            key: const ValueKey('reader-location'),
            style:
                busyBooksHeaderIconButtonStyle(
                  foregroundColor: busyBooksLinuxHeaderForeground(context),
                  disabledForegroundColor: busyBooksLinuxHeaderForeground(
                    context,
                    disabled: true,
                  ),
                  backgroundColor: busyBooksLinuxHeaderControlBackground(
                    context,
                  ),
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                ).copyWith(
                  minimumSize: const WidgetStatePropertyAll(
                    Size(0, BusyBooksSizes.iconButton),
                  ),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: BusyBooksSpacing.sm),
                  ),
                ),
            onPressed: available
                ? () => runAppAction(context, () => reader.showGoTo())
                : null,
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    );
  }
}
