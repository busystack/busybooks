import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../../core/linux_atomic_file_api.dart';
import '../../core/windows_atomic_file_api.dart';
import 'file_identity.dart';
import 'book_paths.dart';

Future<String> contentHash(String path, {bool Function()? cancelled}) async {
  final stream = File(path).openRead().map((chunk) {
    if (cancelled?.call() == true) {
      throw const FileSystemException('Operation cancelled');
    }
    return chunk;
  });
  return (await sha256.bind(stream).first).toString();
}

// Only an explicitly requested original-file move uses this bounded journal.
// The worker owns the journal commits and location updates; it is never backed up.
class BookMoveService {
  const BookMoveService({
    required this.record,
    required this.completed,
    required this.cancelled,
    this.report,
  });
  final void Function(Map<String, dynamic>) record;
  final void Function(String, String, String) completed;
  final bool Function() cancelled;
  final void Function(int done, int total)? report;
  Future<void> _publish(String source, String target) async {
    if (Platform.isWindows) {
      await WindowsAtomicFileApi.instance.publish(
        source,
        target,
        overwrite: false,
      );
    } else {
      final error = LinuxAtomicFileApi.instance.publishNoReplace(
        source,
        target,
      );
      if (error != null) {
        throw FileSystemException(
          'Cannot publish without overwriting',
          target,
          OSError('no-replace rename', error),
        );
      }
    }
    syncDirectory(p.dirname(target));
    syncDirectory(p.dirname(source));
  }

  Future<Map<String, dynamic>> move(
    String id,
    String source,
    String target, {
    Map<String, dynamic>? recovery,
  }) async {
    final sourceIdentity = BookPathIdentity.resolve(source);
    final targetIdentity = BookPathIdentity.resolve(target);
    source = sourceIdentity.path;
    target = targetIdentity.path;
    if (sourceIdentity.sameLocation(targetIdentity)) {
      if (await contentHash(source, cancelled: cancelled) != id) {
        throw FileSystemException(
          'Source content changed; move cancelled',
          source,
        );
      }
      return {'status': 'unchanged', 'path': source};
    }
    final sourceFile = File(source), destination = File(target);
    if (await destination.exists() &&
        await sourceFile.exists() &&
        fileInstance(source) == fileInstance(target)) {
      if (await contentHash(source, cancelled: cancelled) != id) {
        throw FileSystemException(
          'Source content changed; move cancelled',
          source,
        );
      }
      return {'status': 'unchanged', 'path': source};
    }
    if (recovery == null &&
        await FileSystemEntity.type(target, followLinks: false) !=
            FileSystemEntityType.notFound) {
      throw FileSystemException(
        'Destination already exists. Choose another location.',
        target,
      );
    }
    final sourceInstance =
        recovery?['sourceInstance'] as String? ?? fileInstance(source);
    if (recovery == null &&
        (await contentHash(source, cancelled: cancelled) != id ||
            fileInstance(source) != sourceInstance)) {
      throw FileSystemException(
        'Source content changed; move cancelled',
        source,
      );
    }
    final nonce = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final intent =
        recovery ??
        <String, dynamic>{
          'id': 'move:$nonce',
          'bookId': id,
          'source': source,
          'destination': target,
          'sourceInstance': sourceInstance,
          'stagePath': p.join(p.dirname(target), '.busybooks-move-$nonce'),
          'stage': 'intent',
        };
    void stage(String value) {
      intent['stage'] = value;
      record(intent);
    }

    if (recovery == null) stage('intent');
    if (!await destination.exists()) {
      final recoveredStage = File(intent['stagePath'] as String);
      final stagedReady =
          recovery != null &&
          await recoveredStage.exists() &&
          intent['stageInstance'] == fileInstance(recoveredStage.path) &&
          await contentHash(recoveredStage.path, cancelled: cancelled) == id;
      if (stagedReady) {
        await _publish(recoveredStage.path, target);
      } else {
        if (!await sourceFile.exists() ||
            fileInstance(source) != intent['sourceInstance'] ||
            await contentHash(source, cancelled: cancelled) != id) {
          throw FileSystemException(
            'Source is unavailable or was replaced. Recovery retained.',
            source,
          );
        }
        if (cancelled()) {
          throw const FileSystemException('Move cancelled; recovery retained');
        }
        // No MOVEFILE_COPY_ALLOWED: Windows same-volume rename must remove the
        // source. EXDEV/ERROR_NOT_SAME_DEVICE selects our verified stream path.
        try {
          await _publish(source, target);
        } on FileSystemException catch (e) {
          if (e.osError?.errorCode != (Platform.isWindows ? 17 : 18)) rethrow;
          final staging = File(intent['stagePath'] as String);
          if (await staging.exists()) {
            if (intent['stageInstance'] != fileInstance(staging.path)) {
              throw FileSystemException(
                'Staged path was replaced; it has been preserved',
                staging.path,
              );
            }
            if (await contentHash(staging.path, cancelled: cancelled) != id) {
              await staging.delete();
            }
          }
          stage('copying');
          if (!await staging.exists()) {
            await staging.create(exclusive: true);
            intent['stageInstance'] = fileInstance(staging.path);
            stage('copying');
            final output = await staging.open(mode: FileMode.writeOnly);
            var written = 0;
            final total = await sourceFile.length();
            try {
              await for (final chunk in sourceFile.openRead()) {
                if (cancelled()) {
                  throw const FileSystemException(
                    'Move cancelled; source retained',
                  );
                }
                await output.writeFrom(chunk);
                written += chunk.length;
                report?.call(written, total);
              }
              await output.flush();
            } finally {
              await output.close();
            }
          }
          if (await contentHash(staging.path, cancelled: cancelled) != id) {
            throw FileSystemException(
              'Staged content verification failed; source retained',
              staging.path,
            );
          }
          stage('verified');
          await _publish(staging.path, target);
        }
      }
    }
    if (await contentHash(target) != id) {
      throw FileSystemException(
        'Destination verification failed; recovery retained',
        target,
      );
    }
    syncDirectory(p.dirname(target));
    stage('published');
    // Commit the verified location before any cross-volume source removal.
    completed(id, source, target);
    stage('recorded');
    if (await sourceFile.exists()) {
      if (fileInstance(source) != intent['sourceInstance'] ||
          await contentHash(source) != id) {
        throw FileSystemException(
          'Source was replaced; it has been preserved. Destination is verified.',
          source,
        );
      }
      if (cancelled()) {
        throw FileSystemException(
          'Destination is verified; source removal cancelled',
          source,
        );
      }
      // Quarantine by no-clobber rename before deletion, then verify the exact
      // moved instance again. A racing replacement is preserved, never deleted.
      final quarantine =
          intent['quarantine'] as String? ??
          p.join(p.dirname(source), '.busybooks-move-source-$nonce');
      intent['quarantine'] = quarantine;
      stage('removing');
      await _publish(source, quarantine);
      stage('quarantined');
      if (fileInstance(quarantine) != intent['sourceInstance'] ||
          await contentHash(quarantine) != id) {
        if (!await sourceFile.exists()) await _publish(quarantine, source);
        throw FileSystemException(
          'Source changed during removal; preserved for recovery',
          quarantine,
        );
      }
      await File(quarantine).delete();
      syncDirectory(p.dirname(source));
    }
    final quarantine = intent['quarantine'] as String?;
    if (quarantine != null && await File(quarantine).exists()) {
      if (fileInstance(quarantine) != intent['sourceInstance'] ||
          await contentHash(quarantine) != id) {
        throw FileSystemException(
          'Recovery source was replaced; it has been preserved',
          quarantine,
        );
      }
      await File(quarantine).delete();
      syncDirectory(p.dirname(quarantine));
    }
    if (await sourceFile.exists() || await contentHash(target) != id) {
      throw FileSystemException(
        'Move postconditions failed; recovery retained',
        target,
      );
    }
    final staged = File(intent['stagePath'] as String);
    if (await staged.exists()) {
      if (fileInstance(staged.path) != intent['stageInstance']) {
        throw FileSystemException(
          'Staged path was replaced; it has been preserved',
          staged.path,
        );
      }
      await staged.delete();
    }
    syncDirectory(p.dirname(source));
    syncDirectory(p.dirname(target));
    stage('complete');
    return {'status': 'moved', 'path': target, 'operationId': intent['id']};
  }
}
