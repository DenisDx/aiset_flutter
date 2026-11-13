/// The backup surface of the native-file adapter: the bounded `.back`
/// chain of `SPEC.md` amendment 11, last-known-good
/// read-back, revision-checked rollback, and conflicted-copy
/// preservation (`SPEC.md` amendment 10: "backups, notifications and
/// history are optional capability interfaces").
///
/// The [AisetStorage] port stays three members because that is
/// what the pipeline calls. The backup behavior is a second
/// interface that adapters which actually keep a chain
/// implement, which is how the amendment separates the mandatory
/// write contract from the optional durability surface.
library;

import 'dart:typed_data';

import 'package:aiset_core/aiset_core.dart';

/// One backup slot, newest first by [level]: level 1 is the
/// `.back` sibling, level N repeats the suffix N times, exactly the
/// baseline naming discipline (verified against `store.py:backup_path`
/// by execution).
final class AisetBackupEntry {
  /// Creates a chain entry from the slot's raw bytes.
  const AisetBackupEntry({
    required this.level,
    required this.bytes,
    required this.revision,
  });

  /// The chain position, 1 = newest.
  final int level;

  /// The slot's stored bytes, verbatim; possibly not valid UTF-8,
  /// which is why the raw form is what the chain reports.
  final Uint8List bytes;

  /// The revision of [bytes] — the same
  /// `sha256:`-prefixed hash a read of the document reports.
  final String revision;

  /// The slot's size in bytes, for quota reporting
  /// (`SPEC.md` amendment 11: document size and storage quota are not
  /// conflated).
  int get sizeInBytes => bytes.length;

  @override
  String toString() => 'AisetBackupEntry(level $level, @$revision, $sizeInBytes B)';
}

/// The optional backup interface a persistent adapter declares
/// (`SPEC.md` amendment 11, STO-05/STO-06/LKG-01).
///
/// Every method is a separate call from the pipeline's
/// [AisetStorage.read]: "`load` and `loadLkg` are separate calls". A
/// fallback read never rewrites the current source; the only methods
/// that touch the document file are the explicit host commands
/// [restoreBackup] and, through the concrete adapter, the runtime
/// restore.
abstract interface class AisetBackupChain {
  /// The configured chain depth; 0 disables rotation and with it the
  /// [AisetStorageCapabilities.backup] and
  /// [AisetStorageCapabilities.loadLkg] promises.
  int get backupDepth;

  /// Marks the start of a new editing session: the next committed
  /// write rotates the current bytes into the chain, and no later
  /// write in this session does again (`SPEC.md` amendment 11: "a
  /// backup is created no more than once per editing session,
  /// where load or reload — not a widget rebuild — defines the
  /// boundary"). The bootstrap of slice 2E-c calls this on every load
  /// and reread; a freshly constructed adapter already counts as
  /// a new session.
  void beginEditingSession();

  /// The existing chain slots, newest first, truncated at
  /// [backupDepth]. Takes no lock: a concurrent rotation can only make
  /// the answer slightly stale, never inconsistent.
  List<AisetBackupEntry> backupChain();

  /// Reads chain slot [level] (1-based). Throws `NOT_FOUND` when that
  /// slot does not exist, `PAYLOAD_TOO_LARGE` past the size
  /// limit, `STORAGE_ERROR` when its bytes are not valid UTF-8, and
  /// `BAD_REQUEST` for a level outside the chain.
  Future<AisetStoredDocument> readBackup(int level);

  /// The last known good: the newest chain slot whose content still
  /// satisfies the validity check — at minimum parsable JSON5; pass
  /// [isValid] to apply the descriptor's validation too, which is how
  /// the bootstrap reproduces the baseline's newest-valid rule
  /// (verified against `service.py:_newest_valid_backup` by execution:
  /// invalid and oversize slots are skipped).
  ///
  /// Reads the chain only: never touches the current document,
  /// so a fallback cannot overwrite an invalid current source
  /// (`SPEC.md` amendment 11). Throws `NO_VALID_BACKUP` when no slot
  /// qualifies — the honest answer, not an empty success.
  Future<AisetStoredDocument> loadLkg({bool Function(String sourceText)? isValid});

  /// Destructive rollback: consumes slot [level] and shifts the rest
  /// of the chain up one position, so the last change is undone as if
  /// it had never happened (the baseline's `restore_backup`, verified
  /// by execution). When [expectedRevision] is given it is the
  /// amendment's revision check: a stale answer is `REVISION_CONFLICT`
  /// and the file stays untouched. A rollback never starts a new
  /// editing session.
  Future<AisetStoredDocument> restoreBackup(int level, {String? expectedRevision});

  /// Preserves the document's current bytes as a timestamped
  /// `.conflicted…back` copy and prunes old copies to the
  /// retention bound — the call the runtime-restore flow makes before
  /// writing back the last good version, so the rejected foreign
  /// bytes survive either way (`SPEC.md` amendment 3: rejected bytes
  /// are preserved, never silently replaced). Returns the
  /// copy's file name.
  Future<String> preserveRejectedBytes();
}
