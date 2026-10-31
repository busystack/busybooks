import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/localization.dart';
import '../../app/product_actions.dart';
import '../../library/domain/book.dart';
import '../../workspace/workspace_controller.dart';

/// Hold autosave while asking, then settle the captured write before deletion.
/// Both Marks and Notebook use the repository's existing draft coordination.
Future<void> deleteAnnotation(
  BuildContext context,
  WidgetRef ref,
  ReadingAnnotation annotation,
) => ref
    .read(workspaceControllerProvider.notifier)
    .deleteAnnotation(
      annotation.id,
      confirm: () => confirm(
        context,
        context.l10n.delete,
        context.l10n.removeAnnotationHelp,
        destructive: true,
      ),
    );
