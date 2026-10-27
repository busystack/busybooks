import 'dart:async';
import 'dart:io';
import 'package:busybooks/src/library/data/library_store.dart';

class AnnotationStoreGate implements ReadingDataStore {
  AnnotationStoreGate(this.inner);
  final ReadingDataStore inner;
  bool fail = false, failDelete = false, failPut = false;
  bool failAfterProceed = false;
  Completer<void>? entered, proceed;
  Completer<void>? putEntered, putProceed;
  final calls = <String>[];
  bool failBook = false, failAppearance = false;
  Completer<void>? appearanceEntered, appearanceProceed;
  Completer<void>? bookEntered, bookProceed;
  @override
  String get root => inner.root;
  @override
  Stream<Map<String, dynamic>> get progress => inner.progress;
  @override
  Stream<int> get changes => inner.changes;
  @override
  int get searchRevision => inner.searchRevision;
  @override
  Future<dynamic> call(String action, [Object? argument]) async {
    calls.add(action);
    if (action == 'updateBook' &&
        ((argument as Map)['changes'] as Map).containsKey('appearance')) {
      if (appearanceEntered?.isCompleted == false) {
        appearanceEntered!.complete();
      }
      if (appearanceProceed != null) await appearanceProceed!.future;
      if (failAppearance) {
        throw const FileSystemException('Injected appearance write failure');
      }
    }
    if (action == 'book') {
      if (bookEntered != null && !bookEntered!.isCompleted) {
        bookEntered!.complete();
      }
      if (bookProceed != null) await bookProceed!.future;
      if (failBook) {
        throw const FileSystemException('Injected book-data failure');
      }
    }
    if (action == 'putAnnotation') {
      if (putEntered != null && !putEntered!.isCompleted) {
        putEntered!.complete();
      }
      if (putProceed != null) await putProceed!.future;
      if (failPut) {
        throw const FileSystemException('Injected insertion failure');
      }
    }
    if (action == 'deleteAnnotation' && failDelete) {
      throw const FileSystemException('Injected delete failure');
    }
    if (action == 'updateAnnotation') {
      if (fail) throw const FileSystemException('Injected full database');
      if (entered != null && !entered!.isCompleted) entered!.complete();
      if (proceed != null) await proceed!.future;
      if (failAfterProceed) {
        throw const FileSystemException('Injected delayed update failure');
      }
    }
    return inner.call(action, argument);
  }

  @override
  void cancel() => inner.cancel();
  @override
  Future<void> close() => inner.close();
}
