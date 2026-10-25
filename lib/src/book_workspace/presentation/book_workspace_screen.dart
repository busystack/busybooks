import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/busybooks_design.dart';
import '../../app/command_focus.dart';
import '../../app/linux/linux_page_frame.dart';
import '../../app/localization.dart';
import '../../notebook/presentation/book_view_selector.dart';
import '../../notebook/presentation/notebook_screen.dart';
import '../../reading/application/reader_controller.dart';
import '../../reading/presentation/reader_screen.dart';
import '../../reading/presentation/reader_sidebar.dart';
import '../../search/book_search_session.dart';
import '../../search/book_search_widgets.dart';
import '../../workspace/workspace_controller.dart';
import '../application/book_sidebar_controller.dart';
import 'book_header.dart';

/// Both public book URLs update this same page and element. The shell, header,
/// sidebar, content scroll positions and search session survive view changes.
class BookWorkspaceScreen extends ConsumerStatefulWidget {
  const BookWorkspaceScreen({super.key, required this.id, required this.view});
  final String id;
  final BookView view;
  @override
  ConsumerState<BookWorkspaceScreen> createState() =>
      _BookWorkspaceScreenState();
}

class _BookWorkspaceScreenState extends ConsumerState<BookWorkspaceScreen> {
  String? _error;
  bool _loading = true;
  int _loadRevision = 0;
  bool? _readerVisible;
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void didUpdateWidget(covariant BookWorkspaceScreen old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      unawaited(
        ref.read(readerControllerProvider.notifier).setWorkspaceVisible(false),
      );
      _readerVisible = null;
      _loading = true;
      Future.microtask(() {
        if (mounted) unawaited(_load());
      });
    }
    final id = widget.id, view = widget.view;
    Future.microtask(() async {
      if (!mounted || widget.id != id || widget.view != view) return;
      final reader = ref.read(readerControllerProvider.notifier);
      if (view == BookView.notebook) {
        await reader.setWorkspaceVisible(false);
        if (!reader.suspended) {
          try {
            await reader.suspend();
          } catch (error) {
            if (mounted && widget.id == id) {
              setState(() => _error = error.toString());
            }
          }
        }
      } else if (old.view != view) {
        _readerVisible = null;
        if (ModalRoute.of(context)?.isCurrent != false) await reader.show(true);
      }
    });
  }

  Future<void> _load() async {
    final revision = ++_loadRevision, id = widget.id;
    _loading = true;
    _error = null;
    try {
      final workspace = ref.read(workspaceControllerProvider.notifier);
      if (ref.read(workspaceControllerProvider).openedBook?.id != id) {
        await workspace.loadBook(
          id,
          activate: true,
          isCurrent: () =>
              mounted && revision == _loadRevision && widget.id == id,
        );
      }
      if (!mounted || revision != _loadRevision) return;
      final reader = ref.read(readerControllerProvider.notifier);
      if (widget.view == BookView.notebook && !reader.suspended) {
        await reader.suspend();
      }
    } catch (error) {
      if (mounted && revision == _loadRevision) _error = error.toString();
    }
    if (mounted && revision == _loadRevision) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final sidebar = ref.watch(bookSidebarProvider(widget.id)),
        search = ref.watch(bookSearchProvider(widget.id)),
        l = context.l10n;
    final narrow =
        MediaQuery.sizeOf(context).width <
        BusyBooksSizes.workspaceSidebarBreakpoint;
    final open = search.active || sidebar.open;
    final visible =
        widget.view == BookView.reading &&
        !(narrow && open) &&
        !_loading &&
        _error == null;
    if (_readerVisible != visible) {
      _readerVisible = visible;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _readerVisible != visible) return;
        final reader = ref.read(readerControllerProvider.notifier);
        await reader.setWorkspaceVisible(visible);
        if (mounted &&
            _readerVisible == true &&
            reader.interactive &&
            FocusManager.instance.primaryFocus
                is BusyBooksPublicationFocusNode) {
          await reader.send('focus');
        }
      });
    }
    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BusyBooksStatusBox(
              message: '${l.bookError}\n$_error',
              kind: BusyBooksStatusKind.error,
            ),
            TextButton(
              onPressed: () => setState(() => unawaited(_load())),
              child: Text(l.retry),
            ),
          ],
        ),
      );
    } else {
      content = IndexedStack(
        index: widget.view.index,
        children: [
          ExcludeFocus(
            excluding: widget.view != BookView.reading || !visible,
            child: TickerMode(
              enabled: widget.view == BookView.reading,
              child: ReadingContent(
                key: ValueKey('reading-${widget.id}'),
                id: widget.id,
                active: widget.view == BookView.reading,
                visible: visible,
              ),
            ),
          ),
          ExcludeFocus(
            excluding: widget.view != BookView.notebook,
            child: TickerMode(
              enabled: widget.view == BookView.notebook,
              child: NotebookContent(
                key: ValueKey('notebook-${widget.id}'),
                id: widget.id,
                active: widget.view == BookView.notebook,
              ),
            ),
          ),
        ],
      );
    }
    return Scaffold(
      body: LinuxPageFrame(
        sidebarOverlay: narrow,
        sidebarAvailable: true,
        sidebarExpanded: open,
        sidebarTransitionGeneration: open ? 1 : 0,
        onSidebarDismiss: () => search.active
            ? ref.read(bookSearchProvider(widget.id).notifier).close()
            : unawaited(
                ref
                    .read(bookSidebarProvider(widget.id).notifier)
                    .setOpen(false),
              ),
        sidebarHeader: const BusyBooksLinuxBrandHeader(),
        sidebarBody: BookSearchSidebarHost(
          bookId: widget.id,
          child: Column(
            children: [
              ReadingSidebarHeader(bookId: widget.id),
              Expanded(child: ReadingSidebarBody(bookId: widget.id)),
            ],
          ),
        ),
        header: BookHeader(bookId: widget.id, view: widget.view),
        body: ColoredBox(
          color: BusyBooksSurfaceColors.of(context).view,
          child: content,
        ),
      ),
    );
  }
}
