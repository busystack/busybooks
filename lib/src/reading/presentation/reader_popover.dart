import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../annotations/presentation/annotation_presentation.dart';
import '../domain/publication_outline.dart';
import 'publication_location.dart';
import '../../app/app_theme.dart';
import '../../app/busybooks_design.dart';
import '../../app/busybooks_glyphs.dart';
import '../../app/localization.dart';
import '../../platform/native_menu_service.dart';
import '../domain/reading_navigation.dart';
import '../domain/reader_action.dart';
import '../../library/domain/annotation_limits.dart';
import 'appearance_panel.dart';
import '../../core/typography.dart';

const readerPopoverChannel = MethodChannel(
  'io.busystack.busybooks/reader_popover',
);

typedef _PopoverOwner = ({Object? session, Object? presentation});
bool _savesNote(String action) =>
    action == 'annotationNote' || action == 'highlight';
typedef _LocalNote = ({int revision, String note, String color});

/// A small owned Flutter view above WebKit/WebView2, using the application's
/// existing controls. It has no store, window chrome, network or book access.
class ReaderPopoverApp extends StatefulWidget {
  const ReaderPopoverApp({super.key});
  @override
  State<ReaderPopoverApp> createState() => _ReaderPopoverAppState();
}

class _ReaderPopoverAppState extends State<ReaderPopoverApp> {
  Map<String, dynamic>? data;
  int _serial = 0;
  final _pending = <int, Completer<void>>{};
  final _saving = <int, _PopoverOwner>{};
  final _unconfirmed = <int>{};
  final _localNotes = <_PopoverOwner, _LocalNote>{};
  final _noteRequests = <int, ({_PopoverOwner owner, int revision})>{};
  final _transferring = <_PopoverOwner>{};
  final _rejected = <_PopoverOwner>{};
  int _noteRevision = 0;
  final _failedPresentations = <_PopoverOwner>{};
  final _presentedHeights = <_PopoverOwner, double>{};
  late final ErrorWidgetBuilder _previousErrorBuilder;
  late final ErrorWidgetBuilder _errorBuilder;
  ({_PopoverOwner owner, String error})? _saveFailure;
  @override
  void initState() {
    super.initState();
    _previousErrorBuilder = ErrorWidget.builder;
    _errorBuilder = (details) {
      final owner = (
        session: data?['session'],
        presentation: data?['presentation'],
      );
      _failedPresentations.add(owner);
      unawaited(
        readerPopoverChannel
            .invokeMethod<void>('failed', {
              'session': owner.session,
              'presentation': owner.presentation,
            })
            .catchError((Object _) {}),
      );
      return _previousErrorBuilder(details);
    };
    ErrorWidget.builder = _errorBuilder;
    readerPopoverChannel.setMethodCallHandler((call) async {
      if ((call.method == 'escapeFontChooser' || call.method == 'hidden') &&
          call.arguments is Map) {
        final owner = call.arguments as Map;
        if (mounted &&
            data?['kind'] == 'appearance' &&
            owner['session'] == data?['session'] &&
            owner['presentation'] == data?['presentation']) {
          setState(
            () => data = {
              ...data!,
              if (call.method == 'hidden')
                'appearanceVisible': false
              else
                'fontChooserEscape':
                    (data?['fontChooserEscape'] as int? ?? 0) + 1,
            },
          );
        }
        return null;
      }
      if (call.method == 'capture') {
        final owner = (
          session: data?['session'],
          presentation: data?['presentation'],
        );
        final expected = call.arguments as Map?;
        if (expected?['session'] != owner.session ||
            expected?['presentation'] != owner.presentation) {
          return null;
        }
        if ((call.arguments as Map?)?['seal'] == true && mounted) {
          setState(() => _transferring.add(owner));
        }
        final note = _localNotes[owner];
        return note == null
            ? null
            : {
                'session': owner.session,
                'presentation': owner.presentation,
                'revision': note.revision,
                'note': note.note,
                'color': note.color,
              };
      }
      if (call.method == 'result' && call.arguments is Map) {
        final result = call.arguments as Map;
        if (mounted &&
            data?['kind'] == 'lookup' &&
            result['session'] == data?['session'] &&
            result['presentation'] == data?['presentation'] &&
            result['lookupTerm'] == data?['lookupTerm'] &&
            result['lookup'] is Map) {
          setState(() => data = {...data!, 'lookup': result['lookup']});
          return null;
        }
        if (result['captureComplete'] == true ||
            result['captureError'] != null) {
          final owner = (
            session: result['session'],
            presentation: result['presentation'],
          );
          if (_localNotes[owner]?.revision == result['capturedRevision']) {
            _localNotes.remove(owner);
          }
          if (result['captureComplete'] == true &&
              _rejected.remove(owner) &&
              _saveFailure?.owner == owner) {
            _saveFailure = null;
          }
          if (mounted) {
            setState(() {
              if (result['captureError'] != null) {
                _transferring.remove(owner);
              }
              if (result['captureError'] != null &&
                  owner ==
                      (
                        session: data?['session'],
                        presentation: data?['presentation'],
                      )) {
                _saveFailure = (
                  owner: owner,
                  error: result['captureError'].toString(),
                );
              }
            });
          }
          return null;
        }
        final received = _noteRequests.remove(result['request']);
        if (result['noteReceived'] == true &&
            received != null &&
            _localNotes[received.owner]?.revision == received.revision) {
          _localNotes.remove(received.owner);
          if (_rejected.remove(received.owner) &&
              _saveFailure?.owner == received.owner) {
            _saveFailure = null;
          }
        }
        if (result.containsKey('notePending') &&
            mounted &&
            result['session'] == data?['session'] &&
            result['presentation'] == data?['presentation'] &&
            (result['noteRevision'] as int? ?? 0) >=
                (data?['noteRevision'] as int? ?? 0)) {
          setState(
            () => data = {
              ...?data,
              'notePending': result['notePending'],
              'noteError': result['noteError'],
              'noteRevision': result['noteRevision'],
            },
          );
        }
        final pending = _pending.remove(result['request']);
        final owner = _saving[result['request']];
        _unconfirmed.remove(result['request']);
        if (owner != null && mounted) {
          setState(() {
            if (result['error'] != null) {
              if (owner ==
                  (
                    session: data?['session'],
                    presentation: data?['presentation'],
                  )) {
                _saving.remove(result['request']);
                _saveFailure = (
                  owner: owner,
                  error: result['error'].toString(),
                );
              }
            } else if (_saveFailure?.owner == owner) {
              _saveFailure = null;
            }
          });
          // Success closes this presentation. Keep its field sealed until it
          // is replaced, including any native popdown/focus transition.
          _pruneFinishedPresentations();
        }
        if (result['error'] != null) {
          pending?.completeError(StateError(result['error'].toString()));
        } else {
          pending?.complete();
        }
        return null;
      }
      if (call.method == 'update' && call.arguments is Map && mounted) {
        setState(() => data = (call.arguments as Map).cast<String, dynamic>());
        _pruneFinishedPresentations();
      }
    });
    unawaited(
      readerPopoverChannel.invokeMethod<void>('ready').catchError((Object _) {
        // Native's bounded presentation request reports startup failure to the primary.
      }),
    );
  }

  void _painted(_PopoverOwner owner, Size size) {
    if (!mounted ||
        owner !=
            (session: data?['session'], presentation: data?['presentation']) ||
        _failedPresentations.contains(owner) ||
        !size.height.isFinite ||
        size.height <= 0 ||
        _presentedHeights[owner] == size.height) {
      return;
    }
    _presentedHeights[owner] = size.height;
    unawaited(
      readerPopoverChannel
          .invokeMethod<void>('presented', {
            'session': owner.session,
            'presentation': owner.presentation,
            'height': size.height,
          })
          .catchError((Object _) {
            // This is not a database action. The native presentation timeout remains authoritative.
          }),
    );
  }

  void _pruneFinishedPresentations() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final owner = (
        session: data?['session'],
        presentation: data?['presentation'],
      );
      // The old field's synchronous input guard must survive until the frame
      // has disposed it. Unconfirmed writes retain their real reply waiter.
      _saving.removeWhere(
        (request, target) => target != owner && !_pending.containsKey(request),
      );
      _transferring.removeWhere((target) => target != owner);
      _presentedHeights.removeWhere((target, _) => target != owner);
      _failedPresentations.removeWhere((target) => target != owner);
    });
  }

  @override
  void dispose() {
    readerPopoverChannel.setMethodCallHandler(null);
    if (identical(ErrorWidget.builder, _errorBuilder)) {
      ErrorWidget.builder = _previousErrorBuilder;
    }
    // Detach UI waiters only. The primary controller still owns each draft
    // and any repository write; disposing this view cannot cancel either.
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(
          StateError('Reader controls closed before acknowledgement'),
        );
      }
    }
    _pending.clear();
    _saving.clear();
    _unconfirmed.clear();
    _noteRequests.clear();
    _localNotes.clear();
    super.dispose();
  }

  void _rejectDelivery(
    int request,
    _PopoverOwner owner,
    PlatformException error,
  ) {
    final completion = _pending.remove(request);
    final noteRequest = _noteRequests.remove(request);
    // A request already acknowledged by the primary must stay sealed through
    // closure. Disposal and repeated error observers are harmless too.
    if (completion == null && noteRequest == null) return;
    _unconfirmed.remove(request);
    _saving.remove(request);
    if (completion != null && !completion.isCompleted) {
      completion.complete();
    }
    if (mounted) {
      setState(() {
        _rejected.add(owner);
        if (owner ==
            (session: data?['session'], presentation: data?['presentation'])) {
          _saveFailure = (owner: owner, error: error.message ?? error.code);
        }
      });
    }
  }

  Future<void> action(
    String name, [
    Map<String, dynamic> args = const {},
  ]) async {
    if (!mounted) return;
    final owner = (
      session: args['session'] ?? data?['session'],
      presentation: args['presentation'] ?? data?['presentation'],
    );
    final savesNote = _savesNote(name);
    if (savesNote &&
        (_saving.containsValue(owner) || _transferring.contains(owner))) {
      return;
    }
    final request = ++_serial, completion = Completer<void>();
    _pending[request] = completion;
    if (args['note'] is String && (savesNote || name == 'noteDraft')) {
      final revision = ++_noteRevision;
      _localNotes[owner] = (
        revision: revision,
        note: args['note'] as String,
        color: args['color'] as String? ?? 'yellow',
      );
      _noteRequests[request] = (owner: owner, revision: revision);
    }
    if (savesNote) {
      // Latch synchronously, before another input event or frame. A timeout
      // cannot unlock the field: only the primary request result can do that.
      setState(() {
        _saving[request] = owner;
        if (_saveFailure?.owner == owner) _saveFailure = null;
      });
    }
    try {
      final encoded = jsonEncode({
        'type': 'popoverAction',
        'session': owner.session,
        'presentation': owner.presentation,
        'request': request,
        'action': name,
        ...args,
      });
      if (!validReaderPopoverAction(encoded)) {
        throw PlatformException(
          code: 'reader-action-size',
          message: 'Reader action exceeds its UTF-8 byte limit',
        );
      }
      await Future.wait<void>([
        readerPopoverChannel.invokeMethod<void>('action', encoded).catchError((
          Object error,
          StackTrace trace,
        ) {
          // This observer outlives the request timeout. A late definitive
          // rejection cannot produce a primary result to release its latch.
          if (error is PlatformException &&
              error.code == 'reader-action-size') {
            _rejectDelivery(request, owner, error);
          }
          Error.throwWithStackTrace(error, trace);
        }),
        completion.future.timeout(const Duration(seconds: 15)),
      ], eagerError: true);
    } catch (error) {
      // This code is reserved for rejection *before* native forwarding. A
      // timeout or unknown channel failure can still have an executing write.
      if (error is PlatformException && error.code == 'reader-action-size') {
        _rejectDelivery(request, owner, error);
      } else if (savesNote) {
        if (mounted && _pending.containsKey(request)) {
          setState(() => _unconfirmed.add(request));
        }
      } else if (!completion.isCompleted) {
        completion.complete();
      }
      rethrow;
    } finally {
      if (!savesNote) _pending.remove(request);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = data, dark = d?['dark'] == true;
    final owner = (session: d?['session'], presentation: d?['presentation']);
    Future<void> send(String name, [Map<String, dynamic> args = const {}]) =>
        action(name, {
          ...args,
          'session': owner.session,
          'presentation': owner.presentation,
        });
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale(d?['locale'] as String? ?? 'en'),
      theme: buildBusyBooksTheme(
        brightness: dark ? Brightness.dark : Brightness.light,
        accentColor: Color(d?['accent'] as int? ?? 0xff3584e4),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: d?['reducedMotion'] == true,
          textScaler: TextScaler.linear(
            (d?['textScale'] as num? ?? 1).toDouble(),
          ),
        ),
        child: child!,
      ),
      home: BusyBooksMenuHostScope(
        service: const NativeMenuService(supportedPlatform: false),
        child: Builder(
          builder: (context) => Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
            },
            child: Actions(
              actions: {
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (_) {
                    unawaited(send('dismiss').catchError((Object _) {}));
                    return null;
                  },
                ),
              },
              child: Material(
                color: BusyBooksSurfaceColors.of(context).popover,
                child: d == null || _failedPresentations.contains(owner)
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.topLeft,
                        child: _PopoverContents(
                          onPainted: (size) => _painted(owner, size),
                          key: ValueKey(owner),
                          data: d,
                          action: send,
                          isSaving: () =>
                              _saving.containsValue(owner) ||
                              _transferring.contains(owner),
                          unconfirmed: _saving.entries.any(
                            (e) =>
                                e.value == owner &&
                                _unconfirmed.contains(e.key),
                          ),
                          saveError: _saveFailure?.owner == owner
                              ? _saveFailure?.error
                              : null,
                          deliveryRejected: _rejected.contains(owner),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PopoverContents extends StatefulWidget {
  const _PopoverContents({
    super.key,
    required this.data,
    required this.action,
    required this.isSaving,
    required this.unconfirmed,
    this.saveError,
    required this.deliveryRejected,
    required this.onPainted,
  });
  final Map<String, dynamic> data;
  final Future<void> Function(String, [Map<String, dynamic>]) action;
  final bool Function() isSaving;
  final bool unconfirmed;
  final String? saveError;
  final bool deliveryRejected;
  final ValueChanged<Size> onPainted;
  @override
  State<_PopoverContents> createState() => _PopoverContentsState();
}

class _PopoverContentsState extends State<_PopoverContents> {
  late final note = TextEditingController(
    text: widget.data['note'] as String? ?? '',
  );
  final entry = TextEditingController();
  final _naturalContents = GlobalKey(), _feedback = GlobalKey();
  bool editing = false, printedLabel = false;
  String? error, operationError;
  bool invalidNote = false, navigating = false;
  late String color = widget.data['color'] as String? ?? 'yellow';
  late Map<String, dynamic> preferences =
      (widget.data['appearance'] as Map? ?? {}).cast<String, dynamic>();
  @override
  void initState() {
    super.initState();
    editing = widget.data['editing'] == true;
  }

  @override
  void dispose() {
    note.dispose();
    entry.dispose();
    super.dispose();
  }

  Future<void> act(String name, [Map<String, dynamic> args = const {}]) async {
    try {
      await widget.action(name, args);
      if (mounted && operationError != null) {
        setState(() => operationError = null);
      }
    } catch (error) {
      // Save feedback belongs to the request, including a reply after timeout.
      if (mounted &&
          !_savesNote(name) &&
          !(name == 'dismiss' && widget.isSaving())) {
        setState(() => operationError = error.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) => _PaintedContents(
    onPainted: (size) {
      final natural = _naturalContents.currentContext?.findRenderObject();
      final feedback = _feedback.currentContext?.findRenderObject();
      widget.onPainted(
        natural is RenderBox &&
                feedback is RenderBox &&
                natural.hasSize &&
                feedback.hasSize
            ? Size(
                size.width,
                natural.size.height +
                    feedback.size.height +
                    BusyBooksSpacing.lg * 2,
              )
            : size,
      );
    },
    child: Column(
      mainAxisSize: ['goto', 'lookup'].contains(widget.data['kind'])
          ? MainAxisSize.min
          : MainAxisSize.max,
      children: [
        Column(
          key: _feedback,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (operationError != null) BusyBooksBanner(title: operationError!),
            if (widget.unconfirmed)
              BusyBooksBanner(title: context.l10n.noteSaveStillPending),
            if (widget.saveError != null)
              BusyBooksBanner(title: widget.saveError!),
            if (widget.deliveryRejected)
              BusyBooksBanner(title: context.l10n.noteDeliveryRejected),
            if (invalidNote)
              BusyBooksBanner(title: context.l10n.noteInputLimit),
            if (widget.data['notePending'] == true && !widget.deliveryRejected)
              BusyBooksBanner(
                title: widget.data['noteError'] == null
                    ? context.l10n.unsavedNote
                    : context.l10n.noteSaveFailed,
              ),
          ],
        ),
        if (['goto', 'lookup'].contains(widget.data['kind']))
          Flexible(child: _contents(context))
        else
          Expanded(child: _contents(context)),
      ],
    ),
  );
  Widget _contents(BuildContext context) {
    final d = widget.data, l = context.l10n;
    final saving = widget.isSaving();
    final kind = d['kind'];
    if (kind == 'lookup') return _lookup(context);
    if (kind == 'appearance') {
      if (d['appearanceVisible'] == false) return const SizedBox.expand();
      return ReadingAppearanceControls(
        fontChooserEscape: d['fontChooserEscape'] as int? ?? 0,
        onFontChooserChanged: (visible) {
          unawaited(
            readerPopoverChannel
                .invokeMethod<void>('fontChooser', {
                  'session': d['session'],
                  'presentation': d['presentation'],
                  'visible': visible,
                })
                .catchError((Object error) {
                  if (mounted) {
                    setState(() => operationError = error.toString());
                  }
                }),
          );
        },
        preferences: preferences,
        capabilities: TypographyCapabilities.fromJson(d['typography']),
        pdf: d['pdf'] == true,
        noText: (d['location'] as Map?)?['noText'] == true,
        onChanged: (v) async {
          await widget.action('appearance', {'value': v});
          if (mounted) setState(() => preferences = {...preferences, ...v});
        },
        onReset: () => act('resetAppearance'),
        onSaveDefaults: () => act('saveDefaults'),
      );
    }
    if (kind == 'goto') return _goTo(context);
    if (kind == 'speech') {
      return ListView(
        padding: const EdgeInsets.all(BusyBooksSpacing.lg),
        children: [
          Text(l.speechOptions, style: Theme.of(context).textTheme.titleMedium),
          BusyBooksComboRow<String>(
            title: l.voice,
            values: (d['voices'] as List).cast<String>(),
            selected: d['voice'] as String,
            labelFor: (v) => v.isEmpty ? l.system : v,
            onSelected: (v) => act('voice', {'voice': v}),
          ),
          BusyBooksComboRow<num>(
            title: l.speed,
            values: ({
              .5,
              .75,
              1,
              1.25,
              1.5,
              1.75,
              2,
              d['speed'] as num,
            }.toList()..sort()),
            selected: d['speed'] as num,
            labelFor: (v) => '$v×',
            onSelected: (v) => act('speed', {'speed': v}),
          ),
        ],
      );
    }
    final existing = d['annotationId'] is String;
    return ListView(
      padding: const EdgeInsets.all(BusyBooksSpacing.lg),
      children: [
        if (editing || existing)
          Text(
            existing ? l.editNote : l.addNote,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        if (!editing && !existing)
          Row(
            children: [
              Expanded(
                child: BusyBooksPushButton.standard(
                  onPressed: saving
                      ? null
                      : () => act('highlight', {'color': color}),
                  child: Text(saving ? l.savingNote : l.highlight),
                ),
              ),
              const SizedBox(width: BusyBooksSpacing.sm),
              Expanded(
                child: BusyBooksPushButton.standard(
                  onPressed: saving
                      ? null
                      : () => setState(() => editing = true),
                  child: Text(l.addNote),
                ),
              ),
              const SizedBox(width: BusyBooksSpacing.sm),
              Expanded(
                child: BusyBooksPushButton.standard(
                  onPressed: () => act('copy'),
                  child: Text(l.copyShort),
                ),
              ),
            ],
          ),
        const SizedBox(height: BusyBooksSpacing.sm),
        if (d['annotationKind'] != 'bookmark') ...[
          Text(
            l.highlightColor,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: BusyBooksSpacing.sm),
          Wrap(
            spacing: BusyBooksSpacing.sm,
            runSpacing: BusyBooksSpacing.sm,
            children: [
              for (final entry in [
                ('yellow', l.yellow),
                ('green', l.green),
                ('blue', l.blue),
                ('pink', l.pink),
              ])
                Semantics(
                  selected: color == entry.$1,
                  child: BusyBooksPushButton.standardIcon(
                    icon: Icon(
                      color == entry.$1
                          ? BusyBooksGlyphs.check
                          : BusyBooksGlyphs.edit,
                      color: color == entry.$1
                          ? BusyBooksSurfaceColors.of(context).foreground
                          : annotationHighlightColor(entry.$1),
                      size: BusyBooksSizes.iconSm,
                    ),
                    label: Text(entry.$2),
                    onPressed: saving
                        ? null
                        : () {
                            if (widget.isSaving()) return;
                            setState(() => color = entry.$1);
                            act(
                              existing ? 'annotationColor' : 'highlightColor',
                              {'color': entry.$1},
                            );
                          },
                  ),
                ),
            ],
          ),
        ],
        if (editing || existing) ...[
          BusyBooksGroupedTextEntry(
            label: l.note,
            controller: note,
            readOnly: saving,
            // The old field can receive an IME event before the saving frame
            // rebuilds it as read-only. Reject it at the same synchronous latch.
            inputFormatters: [
              TextInputFormatter.withFunction((old, value) {
                if (widget.isSaving()) return old;
                final invalid = !validAnnotationText(value.text);
                if (invalid != invalidNote) {
                  setState(() => invalidNote = invalid);
                }
                return invalid ? old : value;
              }),
            ],
            onChanged: (text) {
              act('noteDraft', {'note': text, 'color': color});
            },
            autofocus: true,
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: BusyBooksSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (existing)
                BusyBooksHeaderIconButton(
                  tooltip: l.delete,
                  icon: BusyBooksGlyphs.delete,
                  onPressed: saving
                      ? null
                      : () {
                          if (!widget.isSaving()) act('deleteAnnotation');
                        },
                ),
              BusyBooksPushButton.standard(
                onPressed: () => act('dismiss'),
                child: Text(l.close),
              ),
              const SizedBox(width: BusyBooksSpacing.sm),
              BusyBooksPushButton.standard(
                onPressed: saving
                    ? null
                    : () => act(existing ? 'annotationNote' : 'highlight', {
                        'note': note.text,
                        'color': color,
                      }),
                child: Text(saving ? l.savingNote : l.save),
              ),
            ],
          ),
        ] else ...[
          BusyBooksActionRow(
            title: l.searchThisBook,
            onTap: () => act('searchSelection'),
          ),
          BusyBooksActionRow(title: l.lookUp, onTap: () => act('dictionary')),
          BusyBooksActionRow(title: l.readAloud, onTap: () => act('speak')),
        ],
      ],
    );
  }

  Widget _lookup(BuildContext context) {
    final d = widget.data, l = context.l10n;
    final result = d['lookup'] as Map? ?? const {};
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(BusyBooksSpacing.lg),
      child: Column(
        key: _naturalContents,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.lookUp,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              BusyBooksHeaderIconButton(
                tooltip: l.close,
                icon: BusyBooksGlyphs.close,
                onPressed: () => act('dismiss'),
              ),
            ],
          ),
          SelectableText(
            d['lookupTerm'] as String? ?? '',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: BusyBooksSpacing.sm),
          Text(l.lookupSource, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: BusyBooksSpacing.sm),
          if (status == 'loading') const LinearProgressIndicator(),
          if (message != null)
            Semantics(liveRegion: true, child: Text(message)),
          if (status == 'ready') ...[
            for (final section in result['sections'] as List? ?? const []) ...[
              Text(
                '${section['language']} · ${section['partOfSpeech']}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: BusyBooksSpacing.sm),
              for (final (index, text)
                  in (section['definitions'] as List).indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: BusyBooksSpacing.sm),
                  child: SelectableText('${index + 1}. $text'),
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
              if ([
                'offline',
                'timeout',
                'unavailable',
                'invalid',
              ].contains(status))
                BusyBooksPushButton.standard(
                  key: const ValueKey('lookup-retry'),
                  onPressed: () => act('lookupRetry'),
                  child: Text(l.retry),
                ),
              if (result['entry'] is String)
                BusyBooksPushButton.standard(
                  key: const ValueKey('lookup-full-entry'),
                  onPressed: () => act('lookupFullEntry'),
                  child: Text(l.openFullEntry),
                ),
              BusyBooksPushButton.standard(
                key: const ValueKey('lookup-close'),
                autofocus: true,
                onPressed: () => act('dismiss'),
                child: Text(l.close),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _pdfReference(BuildContext context) {
    final location = widget.data['location'] as Map?,
        anchor = location?['anchor'] as Map?;
    final page = anchor?['page'] as int?;
    if (page == null) return '';
    final labels = (widget.data['labels'] as List).cast<String>();
    return describePublicationPage(
      context.l10n,
      PublicationPageReference.pdf(page, widget.data['pages'] as int, labels),
    );
  }

  Widget _goTo(BuildContext context) {
    final d = widget.data, l = context.l10n, pdf = d['pdf'] == true;
    final chapters = (d['toc'] as List)
        .where(
          (entry) =>
              entry is Map &&
              entry['href'] is String &&
              (entry['href'] as String).isNotEmpty,
        )
        .cast<Map>()
        .toList();
    Future<void> go() async {
      if (navigating) return;
      Map<String, dynamic>? anchor;
      if (pdf) {
        final page = resolvePdfPage(
          entry.text,
          pages: d['pages'] as int,
          labels: (d['labels'] as List).cast<String>(),
          printedLabel: printedLabel,
        );
        if (page != null) anchor = {'page': page};
      } else {
        final n = double.tryParse(entry.text.trim());
        if (n != null && n.isFinite && n >= 0 && n <= 100) {
          anchor = {'fraction': n / 100};
        }
      }
      if (anchor == null) {
        setState(() => error = pdf ? l.invalidPage : l.invalidProgress);
        return;
      }
      setState(() => navigating = true);
      await act('goto', {'anchor': anchor});
      if (mounted) setState(() => navigating = false);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(BusyBooksSpacing.lg),
      child: Column(
        key: _naturalContents,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.goTo, style: Theme.of(context).textTheme.titleMedium),
          if (pdf && (d['location'] as Map?)?['anchor'] is Map)
            Text(
              _pdfReference(context),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (pdf)
            BusyBooksComboRow<bool>(
              title: l.location,
              values: const [false, true],
              selected: printedLabel,
              labelFor: (v) => v ? l.pageLabel : l.pageNumber,
              onSelected: (v) => setState(() {
                printedLabel = v;
                error = null;
              }),
            ),
          BusyBooksGroupedTextEntry(
            label: pdf
                ? (printedLabel ? l.pageLabel : l.pageNumber)
                : l.bookProgress,
            controller: entry,
            autofocus: true,
            errorText: error,
            onSubmitted: (_) => go(),
            readOnly: navigating,
          ),
          Text(
            pdf
                ? (printedLabel
                      ? l.pageLabelHelp
                      : '${l.pageNumberHelp} 1–${d['pages']}')
                : l.generatedPages,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          BusyBooksPushButton.standard(
            onPressed: navigating ? null : go,
            child: Text(l.go),
          ),
          if (!pdf && chapters.isNotEmpty)
            BusyBooksComboRow<int>(
              title: l.chapter,
              values: List.generate(chapters.length, (i) => i),
              selected: (chapters.indexWhere(
                (x) => x['href'] == (d['location'] as Map?)?['tocHref'],
              )).clamp(0, chapters.length - 1),
              labelFor: (i) => '${i + 1}. ${chapters[i]['label']}',
              onSelected: (i) => act('goto', {
                'anchor': {'href': chapters[i]['href']},
              }),
            ),
        ],
      ),
    );
  }
}

// Report after this populated subtree has painted, rather than on channel ready
// or an empty startup frame. Each callback retains its presentation identity.
class _PaintedContents extends SingleChildRenderObjectWidget {
  const _PaintedContents({required this.onPainted, required super.child});
  final ValueChanged<Size> onPainted;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PaintedRender(onPainted);
  @override
  void updateRenderObject(BuildContext context, _PaintedRender renderObject) =>
      renderObject.onPainted = onPainted;
}

class _PaintedRender extends RenderProxyBox {
  _PaintedRender(this.onPainted);
  ValueChanged<Size> onPainted;
  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final painted = size, report = onPainted;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) report(painted);
    });
  }
}
