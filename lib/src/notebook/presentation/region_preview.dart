import 'package:yaru/yaru.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/busybooks_design.dart';
import '../../app/localization.dart';
import '../../library/domain/book.dart';
import '../application/region_preview_provider.dart';
import 'book_view_selector.dart';

class NotebookRegionPreview extends ConsumerStatefulWidget {
  const NotebookRegionPreview({
    super.key,
    required this.annotation,
    required this.active,
  });
  final ReadingAnnotation annotation;
  final bool active;
  @override
  ConsumerState<NotebookRegionPreview> createState() =>
      _NotebookRegionPreviewState();
}

class _NotebookRegionPreviewState extends ConsumerState<NotebookRegionPreview> {
  @override
  void didUpdateWidget(covariant NotebookRegionPreview old) {
    super.didUpdateWidget(old);
    if (!old.active && widget.active) {
      final target = notebookRegion(widget.annotation);
      final preview = ref.read(notebookRegionPreviewProvider(target));
      if (preview.hasError || preview.hasValue && preview.value == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              widget.active &&
              notebookRegion(widget.annotation) == target) {
            ref.invalidate(notebookRegionPreviewProvider(target));
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(
      notebookRegionPreviewProvider(notebookRegion(widget.annotation)),
    );
    final unavailable = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.regionPreviewUnavailable,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        TextButton(
          onPressed: () => openReading(
            context,
            ref,
            widget.annotation.bookId,
            anchor: widget.annotation.anchor,
            annotationId: widget.annotation.id,
          ),
          child: Text(context.l10n.showInReading),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BusyBooksSpacing.md),
      child: preview.when(
        data: (bytes) => bytes == null
            ? unavailable
            : Semantics(
                image: true,
                label: context.l10n.regionNote,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: BusyBooksSizes.previewInlineImageMaxHeight,
                  ),
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => unavailable,
                  ),
                ),
              ),
        loading: () => YaruLinearProgressIndicator(
          semanticsLabel: context.l10n.regionPreviewLoading,
        ),
        error: (_, _) => unavailable,
      ),
    );
  }
}
