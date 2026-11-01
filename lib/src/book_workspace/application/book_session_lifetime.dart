import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

import '../../workspace/workspace_controller.dart';

/// Retain presentation state for the open book, including its Settings round
/// trip. Closing/replacing that book releases the lease; ordinary widget
/// listeners then determine when the auto-disposing provider is destroyed.
/// Protected drafts belong to NotebookController and do not need this lease.
void retainActiveBookSession(Ref ref, String bookId) {
  KeepAliveLink? lease;
  ref.listen(
    workspaceControllerProvider.select((state) => state.openedBook?.id),
    (_, activeBook) {
      if (activeBook == bookId) {
        lease ??= ref.keepAlive();
      } else {
        lease?.close();
        lease = null;
      }
    },
    fireImmediately: true,
  );
}
