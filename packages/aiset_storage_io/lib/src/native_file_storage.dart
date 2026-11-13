/// The `local`/`native_file` storage adapter of `SPEC.md` amendment
/// 10: one registered document file, durable, with a real
/// cross-process compare-and-swap.
///
/// Behavior follows the Python baseline's `store.py` where the
/// baseline is right — the sidecar lock, the temp-file plus
/// same-directory rename atomic replace, the bounded `.back` chain
/// rotating once per editing session at the default depth of five,
/// the timestamped conflicted-copy names with a retention bound, the
/// newest-valid-backup rule, and the "a read failure is never an
/// absent document" separation — and diverges where the baseline is
/// wrong, per `SPEC_.md` amendment 38. Each divergence carries a
/// `PENDING-A42…` comment at the code; the tests pin the
/// executed-baseline facts they replace (the notes-file numbering
/// continues after A41; the coordinator re-verifies and files the
/// entries).
///
/// Concurrency, stated exactly:
///
/// * [compareAndSwap] checks the revision INSIDE the cross-process
///   sidecar lock immediately before the atomic replace, so two
///   PROCESSES race honestly: at most one commits per revision, the
///   loser is refused, and the file never interleaves —
///   `test/two_process_cas_test.dart` proves it, and that proof is
///   what makes `conditionalWrite: true` honest.
/// * Within one PROCESS, `dart:io`'s POSIX record locks do not exclude
///   two opens of the sidecar, and closing any duplicate descriptor
///   drops the process's locks — both verified by executed probes. The
///   adapter therefore serializes critical sections inside its own
///   isolate with a queue and declares `crossContextConcurrency:
///   false`: an app with several isolates or engines must share one
///   adapter (and one service) per document, which the
///   bootstrap of 2E-c wires.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aiset_core/aiset_core.dart';

import 'backup_chain.dart';
import 'storage_lock.dart';

part 'io_bytes.dart';

/// Bootstrap parameters of the native-file mode (`SPEC.md` amendment
/// 11: the host passes mode, path and policy when the runtime is
/// created; bootstrap is no second settings store).
///
/// The defaults are the baseline's executed `Settings` values: backup
/// depth 5, conflicted retention 5, a 5 s lock timeout, three write
/// attempts.
final class AisetNativeFileSettings {
  /// Creates a parameter set; every field has the baseline default.
  const AisetNativeFileSettings({
    this.backupDepth = 5,
    this.conflictedRetention = 5,
    this.lockTimeout = const Duration(seconds: 5),
    this.writeAttempts = 3,
    this.symlinksAllowed = true,
    this.limits = Limits.defaultProfile,
  });

  /// How many `.back` slots the chain keeps; 0 disables rotation and
  /// with it the [AisetStorageCapabilities.backup] and
  /// [AisetStorageCapabilities.loadLkg] promises.
  final int backupDepth;

  /// How many `.conflicted…back` copies survive pruning; at least
  /// one, like the baseline's `max(retention, 1)`.
  final int conflictedRetention;

  /// How long a critical section waits for the OS lock before
  /// `LOCK_TIMEOUT`. A long asynchronous pre-commit probe never holds
  /// the lock: the pipeline runs its probes outside the store calls
  /// (`SPEC.md` amendment 9), and only the port methods enter the
  /// gate.
  final Duration lockTimeout;

  /// How often a failing atomic replace is retried before the outcome
  /// is reported. A refusal that proves the target was
  /// never touched stops immediately; only unexplained failures
  /// retry.
  final int writeAttempts;

  /// Whether the document path may resolve through symlinks. A
  /// refusal is a policy statement: a symlink out of the declared
  /// directory escapes the access policy set at bootstrap.
  final bool symlinksAllowed;

  /// The document size limit the adapter enforces (`SPEC.md`
  /// amendment 26: the storage adapters enforce it, not the value
  /// walk).
  final Limits limits;
}

/// The native-file adapter: the [AisetStorage] port plus the optional
/// [AisetBackupChain] surface, over one document file.
///
/// A freshly constructed adapter begins in a new editing session,
/// like the baseline's fresh `Store` object (`backup_done = False`):
/// the first committed write rotates the session-start bytes into the
/// chain, and no later write in this session does again.
final class AisetNativeFileStorage implements AisetStorage, AisetBackupChain {
  /// Opens the adapter for [documentPath]. The parent directory need
  /// not exist yet: the first committed write creates it, like the
  /// baseline. [onAudit], when given, receives the adapter's own
  /// events (`write_retry`, `external_edit_restored`, `rollback`)
  /// with values-free payloads — the bootstrap of slice 2E-c wires it
  /// to the service's audit sink.
  AisetNativeFileStorage(
    this.documentPath, {
    AisetNativeFileSettings settings = const AisetNativeFileSettings(),
    this.onAudit,
  })  : settings = settings,
        lock = AisetSidecarLock('$documentPath.lock', timeout: settings.lockTimeout) {
    if (documentPath.isEmpty) {
      throw AisetFailure(AisetErrorCode.badRequest, 'The document path is empty');
    }
  }

  /// The path of the document file, set at bootstrap together with
  /// the access policy (`SPEC.md` amendment 10: a shipped asset is a
  /// seed, never this file). Relative paths resolve against the
  /// process's working directory like every other `dart:io` path.
  final String documentPath;

  /// The bootstrap parameters of this adapter.
  final AisetNativeFileSettings settings;

  /// The adapter's audit sink; see the constructor.
  final void Function(String name, Map<String, Object?> payload)? onAudit;

  /// The write gate of this document. Public so a contention test (or
  /// a host implementing its own coordinated command)
  /// can hold the same lock from the outside; ordinary hosts
  /// never touch it.
  final AisetSidecarLock lock;

  /// Whether the next committed user edit still has to rotate the
  /// current bytes into the chain. Re-armed by
  /// [AisetBackupChain.beginEditingSession] — a load or reload, not a
  /// widget rebuild, is the session boundary (`SPEC.md` amendment 11).
  bool _rotationArmed = true;

  // -- the port ----------------------------------------------------------------

  @override
  AisetStorageCapabilities get capabilities {
    final keepsChain = settings.backupDepth > 0;
    return AisetStorageCapabilities(
      mode: StorageMode.local,
      persistent: true,
      // Real CAS: the revision is checked inside the cross-process
      // lock right before the atomic replace, and the two-process
      // race test proves a stale writer is refused while the file
      // stays whole and never interleaves.
      conditionalWrite: true,
      // The OS sidecar lock excludes between PROCESSES. It does NOT
      // exclude between isolates of one process on the POSIX
      // record-lock semantics `dart:io` exposes (verified by probes:
      // a second isolate's lock request succeeds immediately while
      // the first holds it, and closing a duplicate descriptor
      // drops the process's locks). One adapter instance serializes
      // its own isolate's sections with a queue, but that is an
      // in-isolate mutex and the amendment forbids selling it
      // as more (`SPEC.md` amendment 8): multi-isolate Flutter apps
      // share one adapter per document, and the bootstrap wires
      // that.
      crossContextConcurrency: false,
      // The stored form is the verbatim source text: reads and writes
      // go through raw bytes with an explicit strict UTF-8 codec,
      // never a decode-encode reformatting; the round-trip
      // test pins byte identity through the adapter, byte
      // order mark included.
      sourcePreservation: true,
      backup: keepsChain,
      // No edit history beyond the bounded .back chain: honest false.
      history: false,
      loadLkg: keepsChain,
      // No change notifications: watching a file for external edits
      // means polling, and the port treats notifications as a
      // declared capability, not a duty. External edits are adopted
      // by the host's explicit reread (which the amendment notes
      // is NOT a lock), and a concurrent writer is caught by the
      // CAS under the lock — the strong guarantee lives in the
      // write path, not in an event stream.
      changeNotifications: false,
      // The file stores whatever it is given; the library validates
      // locally, and that is not server-side protection.
      validationAuthority: ValidationAuthority.none,
      note: 'native_file: cross-process CAS under a sidecar lock; isolates '
          'of one process must share one adapter per document; no change '
          'notifications, external edits are adopted by reread',
    );
  }

  @override
  Future<AisetStoredDocument> read() async {
    final bytes = await _readCurrentBytes();
    if (bytes == null) {
      throw AisetFailure(
        AisetErrorCode.notFound,
        'The document is not stored yet',
        detail: 'no file at the registered location',
      );
    }
    // The size limit is enforced over the raw bytes before the
    // text is handed out, like the baseline's `read()`.
    if (bytes.length > settings.limits.maxFileSize) {
      throw AisetFailure(
        AisetErrorCode.payloadTooLarge,
        'The document exceeds the ${settings.limits.maxFileSize}-byte limit',
        detail: '${bytes.length} bytes',
      );
    }
    return AisetStoredDocument(
      sourceText: _decodeOrReport(bytes),
      revision: sourceRevisionOfBytes(bytes),
      metadata: const {'storage': 'native_file'},
    );
  }

  @override
  Future<AisetCommitResult> compareAndSwap({
    required String expectedRevision,
    required String sourceText,
  }) async {
    // DECISION(port-contract): a blank expected revision is the
    // adapter's own precondition complaint — `rejected`, zero bytes
    // touched. The pipeline checks the revision pair above the port
    // and never sends a blank; a bypassing caller gets a refusal
    // rather than an unconditional overwrite.
    if (expectedRevision.trim().isEmpty) {
      return const AisetCommitResult(
        AisetCommitStatus.rejected,
        detail: 'a conditional write requires the expected revision',
      );
    }
    final bytes = _encodeText(sourceText);
    // Quota before policy: an oversized candidate must not
    // damage the previous version (`SPEC.md` amendment 11), and here
    // it never even reaches the file. Reported as `rejected`
    // rather than a throw, because the port offers that honest
    // outcome for a policy refusal.
    if (bytes.length > settings.limits.maxFileSize) {
      return AisetCommitResult(
        AisetCommitStatus.rejected,
        detail: 'the candidate exceeds the ${settings.limits.maxFileSize}-byte limit',
      );
    }
    return lock.hold(() => _casLocked(expectedRevision: expectedRevision, bytes: bytes));
  }

  /// The critical section: re-read, compare, rotate, replace. One
  /// lock acquisition covers the whole read-modify-write, so a
  /// concurrent process can neither interleave a replace nor be
  /// compared against bytes that were already replaced.
  Future<AisetCommitResult> _casLocked({
    required String expectedRevision,
    required Uint8List bytes,
  }) async {
    final current = await _readCurrentBytes(); // absent reads as null
    if (current == null) {
      // DECISION(port-contract-cas-absent): an absent file has no
      // stored revision, so no non-empty expectation can match it —
      // `revisionConflict`, nothing written. The initial create is
      // NOT smuggled through CAS: `SPEC.md` amendment 11 demands
      // create-if-absent so two launches cannot overwrite each other,
      // and that transition belongs to the 2E-c bootstrap command
      // under this same lock. (The memory store creates blindly
      // on an absent revision because it is a test double;
      // a durable adapter may not.) The baseline's
      // `write(expected_revision: None)` blind overwrite has no port
      // method here and none is invented.
      return const AisetCommitResult(
        AisetCommitStatus.revisionConflict,
        detail: 'the document does not exist yet; the initial create is a separate command',
      );
    }
    if (sourceRevisionOfBytes(current) != expectedRevision) {
      // Nothing was written; the file still holds exactly the
      // bytes of [AisetCommitResult.revision] (pinned by the
      // stale-write test).
      return AisetCommitResult(
        AisetCommitStatus.revisionConflict,
        revision: sourceRevisionOfBytes(current),
      );
    }
    // The session rotates once. The consumed session-start bytes
    // move into the chain BEFORE the replace, and the rotation is
    // spent even if the replace then fails — the baseline's exact
    // ordering (`rotate_backups(current); backup_done = True` before
    // the rename attempts, verified by execution). A failed replace
    // leaves the current file equal to the just-rotated slot, so the
    // chain never holds bytes that were not the document. Like the
    // baseline's `if not backup_done and current:`, an EMPTY
    // session start rotates no slot and stays armed — an empty
    // `.back` file would promise nothing.
    final rotates = _rotationArmed && current.isNotEmpty;
    if (rotates) {
      await _rotateBackups(current);
      _rotationArmed = false;
    }
    // The byte order mark rides with the bytes: [bytes] came from
    // `utf8.encode(sourceText)`, whose first character is the mark
    // whenever the file had one, so no separate preservation flag
    // exists to get wrong. PENDING-A42a: the baseline tests
    // `current_text.startswith(BOM)` on its ALREADY-BOM-STRIPPED
    // decoded text — always false — and silently drops the
    // mark on the first save (verified by execution).
    return _atomicReplace(bytes);
  }

  /// The temp-file-plus-rename replace of `store.py:_atomic_write`,
  /// under the caller-held lock: hidden `.name.pid.attempt.tmp` in
  /// the SAME directory, write, flush, rename. A failure whose OS
  /// error proves the target was never touched answers
  /// [AisetCommitStatus.rejected]; anything else that survives
  /// [AisetNativeFileSettings.writeAttempts] attempts answers
  /// [AisetCommitStatus.uncertain] — the caller re-reads the state
  /// instead of repeating the write blindly (`SPEC.md` amendment 8).
  ///
  /// A target occupied by a DIRECTORY is refused: the
  /// read inside the critical section fails with EISDIR and throws
  /// `STORAGE_ERROR` before any rotation, so the directory and
  /// the chain stay untouched — the same outcome class the baseline
  /// answers (`read_bytes` wraps `IsADirectoryError` into
  /// `StorageError`, verified by execution). The rename itself keeps
  /// EISDIR in the refused set as a belt-and-braces classification.
  Future<AisetCommitResult> _atomicReplace(Uint8List bytes) async {
    final target = File(documentPath);
    // The baseline's `max(write_attempts, 1)`:
    // a mis-set 0 still attempts the write.
    final attempts = settings.writeAttempts < 1 ? 1 : settings.writeAttempts;
    var detail = '';
    var refused = false;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      final temp = File(_tempName(target, attempt));
      try {
        await target.parent.create(recursive: true);
        final raf = await temp.open(mode: FileMode.write);
        try {
          await raf.writeFrom(bytes);
          await _flushToOs(raf);
        } finally {
          await raf.close();
        }
        await temp.rename(target.path);
        return AisetCommitResult(
          AisetCommitStatus.committed,
          revision: sourceRevisionOfBytes(bytes),
        );
      } on FileSystemException catch (error) {
        detail = error.osError?.message ?? error.message;
        refused = _refusedWriteErrors.contains(error.osError?.errorCode ?? 0);
        try {
          if (await temp.exists()) await temp.delete();
        } on FileSystemException {
          // Best-effort cleanup; the failure below is the report.
        }
        if (refused) {
          // The platform proved the target was never touched;
          // retrying cannot help and would only re-attempt a
          // write the policy or capacity refuses. Stop now.
          break;
        }
        if (attempt < attempts) {
          onAudit?.call('write_retry', {'attempt': attempt, 'detail': detail});
          await Future<void>.delayed(Duration(milliseconds: 50 * attempt));
        }
      }
    }
    return refused
        ? AisetCommitResult(AisetCommitStatus.rejected, detail: detail)
        : AisetCommitResult(AisetCommitStatus.uncertain, detail: detail);
  }

  // -- the backup surface ----------------------------------------------------------

  @override
  int get backupDepth => settings.backupDepth;

  @override
  void beginEditingSession() {
    _rotationArmed = true;
  }

  @override
  List<AisetBackupEntry> backupChain() {
    final entries = <AisetBackupEntry>[];
    for (var level = 1; level <= settings.backupDepth; level++) {
      final file = File(_backupPath(level));
      if (!file.existsSync()) continue;
      final Uint8List bytes;
      try {
        bytes = file.readAsBytesSync();
      } on FileSystemException {
        // A slot a concurrent rotation just moved, or a
        // slot the OS refuses: the chain answers with what
        // could be listed, never with a raw exception.
        continue;
      }
      entries.add(AisetBackupEntry(
        level: level,
        bytes: bytes,
        revision: sourceRevisionOfBytes(bytes),
      ));
    }
    return entries;
  }

  @override
  Future<AisetStoredDocument> readBackup(int level) async {
    if (level < 1 || level > settings.backupDepth) {
      throw AisetFailure(AisetErrorCode.badRequest, 'Backup level $level is outside the chain');
    }
    final file = File(_backupPath(level));
    final bytes = await _readFileBytes(file, what: 'backup level $level');
    if (bytes == null) {
      throw AisetFailure(AisetErrorCode.notFound, 'Backup level $level does not exist');
    }
    if (bytes.length > settings.limits.maxFileSize) {
      throw AisetFailure(
        AisetErrorCode.payloadTooLarge,
        'The backup exceeds the ${settings.limits.maxFileSize}-byte limit',
        detail: '${bytes.length} bytes',
      );
    }
    return AisetStoredDocument(
      sourceText: _decodeOrReport(bytes),
      revision: sourceRevisionOfBytes(bytes),
      metadata: {'storage': 'native_file', 'backupLevel': level},
    );
  }

  @override
  Future<AisetStoredDocument> loadLkg({bool Function(String sourceText)? isValid}) async {
    // The baseline's newest-valid rule (`service.py:
    // _newest_valid_backup`, verified by execution): walk the chain
    // newest first, skip an oversize or otherwise invalid slot, and
    // return the FIRST good one. Read-only — the current document is
    // never touched, so a fallback cannot overwrite an invalid
    // current source (`SPEC.md` amendment 11). PENDING-A42c: the
    // baseline lets a raw `UnicodeDecodeError` escape this walk when
    // a backup's bytes are not UTF-8; here such a slot is simply not
    // valid and the walk continues.
    for (final entry in backupChain()) {
      if (entry.sizeInBytes > settings.limits.maxFileSize) continue;
      final String text;
      try {
        text = _decodeText(entry.bytes);
      } on FormatException {
        continue;
      }
      if (!await _slotValid(text, isValid)) continue;
      return AisetStoredDocument(
        sourceText: text,
        revision: entry.revision,
        loadedFrom: 'lkg',
        metadata: {'storage': 'native_file', 'backupLevel': entry.level},
      );
    }
    throw AisetFailure(
      AisetErrorCode.noValidBackup,
      'No valid backup is available for this document',
    );
  }

  /// Whether one chain slot passes: parses as JSON5 (the baseline's
  /// minimum validity gate — an unparsable backup is skipped, verified
  /// by execution) and, when the host gave a check, passes that too.
  /// A throwing [isValid] counts as invalid: a validator that cannot
  /// answer has not validated anything.
  Future<bool> _slotValid(String text, bool Function(String)? isValid) async {
    try {
      Json5Document(text, origin: 'backup-slot');
    } on Json5SourceException {
      return false;
    }
    if (isValid == null) return true;
    try {
      return isValid(text);
    } on Object {
      return false;
    }
  }

  @override
  Future<AisetStoredDocument> restoreBackup(int level, {String? expectedRevision}) async {
    // Destructive rollback: a different command from the read-only
    // fallback above, revision-checked and audit-logged (`SPEC.md`
    // amendment 11, LKG-01). The consumed slot disappears and deeper
    // slots shift up, so the undone change vanishes as if it had
    // never happened — the baseline's `restore_backup`, verified by
    // execution.
    if (level < 1 || level > settings.backupDepth) {
      throw AisetFailure(AisetErrorCode.badRequest, 'Backup level $level is outside the chain');
    }
    return lock.hold(() async {
      final slot = File(_backupPath(level));
      final bytes = await _readFileBytes(slot, what: 'backup level $level');
      if (bytes == null) {
        throw AisetFailure(AisetErrorCode.noValidBackup, 'Backup level $level does not exist');
      }
      if (bytes.length > settings.limits.maxFileSize) {
        throw AisetFailure(
          AisetErrorCode.payloadTooLarge,
          'The backup exceeds the ${settings.limits.maxFileSize}-byte limit',
          detail: '${bytes.length} bytes',
        );
      }
      final current = await _readCurrentBytes();
      if (expectedRevision != null) {
        final stored = current == null ? null : sourceRevisionOfBytes(current);
        if (stored != expectedRevision) {
          throw AisetFailure(
            AisetErrorCode.revisionConflict,
            'The document moved since the restore was planned; re-read before restoring',
            detail: 'stored=${stored ?? '<absent>'}',
          );
        }
      }
      // A rollback does not start a new editing session (the
      // baseline's `backup_done = True`): the consumed slot is gone,
      // the restored bytes become current, and the chain is
      // not re-filled by the restore itself.
      _rotationArmed = false;
      await slot.delete();
      for (var deeper = level + 1; deeper <= settings.backupDepth; deeper++) {
        final candidate = File(_backupPath(deeper));
        if (await candidate.exists()) {
          await candidate.rename(_backupPath(deeper - 1));
        }
      }
      final result = await _atomicReplace(bytes);
      if (result.status != AisetCommitStatus.committed) {
        throw AisetFailure(
          AisetErrorCode.storageError,
          'The rollback could not be persisted',
          detail: result.detail,
        );
      }
      onAudit?.call('rollback', {'level': level, 'revision': result.revision});
      return AisetStoredDocument(
        sourceText: _decodeOrReport(bytes),
        revision: result.revision!,
          metadata: {'storage': 'native_file', 'restoredFrom': level},
      );
    });
  }

  @override
  Future<String> preserveRejectedBytes() {
    // The conflicted copy of the preservation contract (`SPEC.md`
    // amendment 3): bytes being replaced or refused are preserved,
    // never silently dropped. Naming and retention are the
    // baseline's, verified by execution. Takes the same lock as a
    // commit, so preserved bytes are never a torn mid-replace view.
    return lock.hold(() async {
      final bytes = await _requireCurrentBytes();
      return _writeConflicted(bytes);
    });
  }

  /// The revision of the CURRENT stored bytes, without
  /// decoding them. This is the piece the port
  /// cannot answer when the file is corrupt: [read]
  /// throws `STORAGE_ERROR` on undecodable bytes, and a
  /// later [restoreLastValidated] still needs the exact
  /// revision token of those bytes to CAS the restore.
  /// Throws `NOT_FOUND` for an absent document and
  /// `STORAGE_ERROR` for a file that cannot be read — the same
  /// outcome classes as [read], minus only the decode.
  Future<String> revisionOfCurrentBytes() async {
    final bytes = await _readCurrentBytes();
    if (bytes == null) {
      throw AisetFailure(AisetErrorCode.notFound, 'The document is not stored yet');
    }
    return sourceRevisionOfBytes(bytes);
  }

  /// The runtime-restore step the bootstrap of slice 2E-c runs when
  /// the current file came back invalid but the session's good text
  /// is in hand (the baseline's invalid-reread restore —
  /// `service.py:_preserve_rejected` plus
  /// `store.write_unchecked(last_validated)`, verified by
  /// execution). [rejectedRevision] is the corrupt
  /// revision the failed read was about — take it from
  /// [revisionOfCurrentBytes], because [read] throws before
  /// handing it out:
  ///
  /// 1. the CAS check against [rejectedRevision] runs
  ///    FIRST: if another writer committed since the invalid
  ///    read, this command refuses
  ///    (`revisionConflict`) and does NOT bulldoze the new
  ///    revision with a stale "good" copy;
  /// 2. the rejected bytes go to a timestamped conflicted copy —
  ///    nothing is destroyed;
  /// 3. [goodText] is written back WITHOUT rotating: the corrupt
  ///    bytes never enter the `.back` chain, and the session stays
  ///    armed so its own first real edit still gets a
  ///    backup slot. PENDING-A42b: the baseline's
  ///    `write_unchecked` runs the ordinary rotation, so the corrupt
  ///    current content lands in `.back` — its LKG slot can hold
  ///    garbage, byte-identical to the conflicted copy (verified by
  ///    execution); an amendment-11 fallback promise must not
  ///    be built on it.
  ///
  /// The fallback is reported to the host and NEVER overwrites an
  /// invalid current source with defaults (`SPEC.md`
  /// amendment 11): [goodText] is a document this stack validated,
  /// chosen by the caller, not an adapter-side invention.
  Future<AisetCommitResult> restoreLastValidated({
    required String rejectedRevision,
    required String goodText,
  }) async {
    final bytes = _encodeText(goodText);
    if (bytes.length > settings.limits.maxFileSize) {
      return AisetCommitResult(
        AisetCommitStatus.rejected,
        detail: 'the good text exceeds the ${settings.limits.maxFileSize}-byte limit',
      );
    }
    return lock.hold(() async {
      final current = await _readCurrentBytes();
      if (current == null) {
        return const AisetCommitResult(
          AisetCommitStatus.rejected,
          detail: 'there is no current file to restore over',
        );
      }
      final stored = sourceRevisionOfBytes(current);
      if (stored != rejectedRevision) {
        return AisetCommitResult(
          AisetCommitStatus.revisionConflict,
          revision: stored,
        );
      }
      await _writeConflicted(current);
      final result = await _atomicReplace(bytes);
      onAudit?.call('external_edit_restored', {
        'committed': result.status == AisetCommitStatus.committed,
        'revision': result.revision,
      });
      return result;
    });
  }

  // -- internals -----------------------------------------------------------------

  /// The current file's bytes, or `null` when the document does not
  /// exist. A read that FAILS for another reason throws a
  /// `STORAGE_ERROR`, never an absent-document answer
  /// (`SPEC.md` amendment 11: four different results stay four).
  Future<Uint8List?> _readCurrentBytes() async {
    _checkSymlinkPolicy();
    return _readFileBytes(File(documentPath), what: 'the document');
  }

  Future<Uint8List> _requireCurrentBytes() async {
    final bytes = await _readCurrentBytes();
    if (bytes == null) {
      throw AisetFailure(AisetErrorCode.notFound, 'The document is not stored yet');
    }
    return bytes;
  }

  Future<Uint8List?> _readFileBytes(File file, {required String what}) async {
    try {
      return await file.readAsBytes();
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode == _enoent) return null;
      throw AisetFailure(
        AisetErrorCode.storageError,
        'Unable to read $what',
        detail: error.osError?.message ?? error.message,
      );
    }
  }

  /// Decodes the stored bytes for the port. The byte order mark
  /// survives as the first character of the text (see
  /// `io_bytes.dart`), which is what makes the round-trip
  /// byte-exact; the core's parser accepts the mark as leading
  /// whitespace.
  ///
  /// PENDING-A42c (divergence): undecodable bytes answer a clean
  /// `STORAGE_ERROR` [AisetFailure]. The baseline lets a raw
  /// `UnicodeDecodeError` escape `store.read()` and `service.load()`
  /// for the same file (verified by execution); a storage failure
  /// must be a reportable outcome class, not a crash, and it NEVER
  /// authorizes a seed overwrite (`SPEC.md` amendment 11).
  /// The bytes stay untouched: this path only reads.
  String _decodeOrReport(Uint8List bytes) {
    try {
      return _decodeText(bytes);
    } on FormatException catch (error) {
      throw AisetFailure(
        AisetErrorCode.storageError,
        'The stored bytes are not valid UTF-8 and cannot be read as a document',
        detail: error.message,
      );
    }
  }

  /// The baseline's `check_symlink`, kept as an opt-in policy: with
  /// symlinks allowed nothing is checked; with them forbidden, any
  /// symlinked component of the registered path is a refusal.
  void _checkSymlinkPolicy() {
    if (settings.symlinksAllowed) return;
    if (Link(documentPath).existsSync()) {
      throw AisetFailure(
        AisetErrorCode.storageError,
        'The registered path resolves through a symlink; disabled by policy',
      );
    }
    var directory = File(documentPath).parent;
    while (true) {
      if (Link(directory.path).existsSync()) {
        throw AisetFailure(
          AisetErrorCode.storageError,
          'A parent of the registered path is a symlink; disabled by policy',
        );
      }
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
  }

  /// `store.py:backup_path`: level N repeats the `.back` suffix N
  /// times (`.back`, `.back.back`, …), verified by execution. Only
  /// renames move slots, never a rewrite.
  String _backupPath(int level) {
    final buffer = StringBuffer('$documentPath.back');
    for (var i = 1; i < level; i++) {
      buffer.write('.back');
    }
    return buffer.toString();
  }

  /// The chain shift of `store.py:rotate_backups`, under the
  /// caller-held lock: drop the deepest slot if occupied, move every
  /// shallower slot one level down, and write the session-start bytes
  /// into level 1. A slot that cannot be moved is a storage
  /// failure of the write, not a silent skip: the
  /// amendment's backup promise is only as good as the chain.
  Future<void> _rotateBackups(Uint8List preReplace) async {
    final depth = settings.backupDepth;
    if (depth <= 0) return;
    try {
      final deepest = File(_backupPath(depth));
      if (await deepest.exists()) {
        await deepest.delete();
      }
      for (var level = depth - 1; level >= 1; level--) {
        final source = File(_backupPath(level));
        if (await source.exists()) {
          await source.rename(_backupPath(level + 1));
        }
      }
      await File(_backupPath(1)).writeAsBytes(preReplace, flush: true);
    } on FileSystemException catch (error) {
      throw AisetFailure(
        AisetErrorCode.storageError,
        'The backup chain could not be rotated',
        detail: error.osError?.message ?? error.message,
      );
    }
  }

  String _tempName(File target, int attempt) =>
      '${target.parent.path}${Platform.pathSeparator}.'
      '${_basename(target.path)}.$pid.$attempt.tmp';

  /// The conflicted-copy name discipline of
  /// `store.py:conflicted_path`, verified by execution:
  /// `<name>.conflicted.<UTC %Y%m%dT%H%M%S.%fZ>.back`, created
  /// exclusively so a collision can never overwrite a
  /// preserved copy.
  ///
  /// PENDING-A42d (divergence): on a same-microsecond name collision the
  /// baseline's `open(..., "xb")` raises, the `StorageError`
  /// propagates out of `_preserve_rejected` and the whole reread
  /// crashes (the rejected bytes survive only because they are
  /// still the current file); here a fresh timestamp is recomputed and
  /// the exclusive create retried a bounded number of times, so the
  /// copy still lands and name order stays time order.
  Future<String> _writeConflicted(Uint8List bytes) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      final name = _conflictedName();
      final target = File(name);
      try {
        await target.create(recursive: true, exclusive: true);
      } on FileSystemException catch (error) {
        final code = error.osError?.errorCode ?? 0;
        if (code != _eexist) {
          throw AisetFailure(
            AisetErrorCode.storageError,
            'The rejected bytes could not be preserved',
            detail: error.osError?.message ?? error.message,
          );
        }
        continue; // same-microsecond name: re-stamp and retry
      }
      try {
        await target.writeAsBytes(bytes, flush: true);
      } on FileSystemException catch (error) {
        throw AisetFailure(
          AisetErrorCode.storageError,
          'The rejected bytes could not be preserved',
          detail: error.osError?.message ?? error.message,
        );
      }
      await _pruneConflicted();
      return _basename(name);
    }
    throw AisetFailure(
      AisetErrorCode.storageError,
      'The rejected bytes could not be preserved',
      detail: 'conflicted-copy name collision within the retry window',
    );
  }

  String _conflictedName() {
    final now = DateTime.now().toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    // The 6-digit fraction is MICROSECONDS WITHIN
    // THE CURRENT SECOND, derived from the epoch clock. Dart's
    // `DateTime.microsecond` field is only 0..999 (µs within the
    // millisecond) and wraps every millisecond, so
    // formatting it as a 0..999999 fraction would make
    // the name sort diverge from time order — breaking the
    // baseline's prune-by-name-sort retention. The epoch
    // remainder is strictly monotonic inside a
    // second, and the `ss` field advances at the rollover, so
    // the full name keeps chronological order.
    final microsOfSecond = now.microsecondsSinceEpoch % 1000000;
    final stamp = '${now.year}${two(now.month)}${two(now.day)}'
        'T${two(now.hour)}${two(now.minute)}${two(now.second)}'
        '.${microsOfSecond.toString().padLeft(6, '0')}'
        'Z';
    return '$documentPath.conflicted.$stamp.back';
  }

  /// Retention of `store.py:_rotate_conflicted`, verified by
  /// execution: the newest [AisetNativeFileSettings.conflictedRetention]
  /// copies by name survive; older ones are removed best-effort.
  Future<void> _pruneConflicted() async {
    final retention = settings.conflictedRetention < 1 ? 1 : settings.conflictedRetention;
    final prefix = '${_basename(documentPath)}.conflicted.';
    final directory = File(documentPath).parent;
    final copies = <String>[];
    try {
      await for (final entity in directory.list()) {
        final name = _basename(entity.path);
        if (entity is File && name.startsWith(prefix) && name.endsWith('.back')) {
          copies.add(name);
        }
      }
    } on FileSystemException {
      return; // best effort, like the baseline
    }
    copies.sort();
    final stale = copies.length - retention;
    for (final name in copies.take(stale > 0 ? stale : 0)) {
      try {
        await File('${directory.path}${Platform.pathSeparator}$name').delete();
      } on FileSystemException {
        // Best-effort cleanup.
      }
    }
  }
}
