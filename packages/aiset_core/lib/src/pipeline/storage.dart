part of 'pipeline.dart';

/// The mode a document is stored in (`SPEC.md` amendment 10).
///
/// Exactly one mode and one authoritative source per document. A
/// cache, an effective snapshot and a draft are never additional
/// authoritative copies, and the memory store is not a fourth
/// persistent user mode.
enum StorageMode {
  /// The document lives on a remote backend, read and saved by that
  /// backend through an API.
  remoteApi('remote_api'),

  /// The document lives in a host-defined place, read and saved by the host
  /// through an adapter it provides.
  hostApi('host_api'),

  /// The document lives in file or persistent device/browser storage, read and
  /// saved by a built-in adapter.
  local('local'),

  /// Ephemeral storage for tests and temporary documents. Declared
  /// non-persistent so no UI can present it as a saved place.
  memory('memory');

  const StorageMode(this.label);

  /// The wire spelling.
  final String label;

  /// The mode named by [label], or `null` for an unknown name.
  static StorageMode? tryParse(String label) {
    for (final mode in StorageMode.values) {
      if (mode.label == label) return mode;
    }
    return null;
  }
}

/// What a storage adapter can actually guarantee
/// (`SPEC.md` amendments 10 and 11).
///
/// A missing capability is reported as missing and never
/// emulated: an adapter that has no conditional write says so, and the
/// pipeline then refuses to claim multi-writer safety rather than
/// pretending a read-then-write pair is one.
final class AisetStorageCapabilities {
  /// Creates a capability set.
  const AisetStorageCapabilities({
    required this.mode,
    required this.persistent,
    required this.conditionalWrite,
    required this.crossContextConcurrency,
    required this.sourcePreservation,
    required this.backup,
    required this.history,
    required this.loadLkg,
    required this.changeNotifications,
    this.validationAuthority = ValidationAuthority.descriptor,
    this.note = '',
  });

  /// The declared mode of this adapter.
  final StorageMode mode;

  /// Whether the data survives the process.
  final bool persistent;

  /// Whether the adapter offers an atomic conditional write
  /// (compare-and-swap). Without it, no concurrent-write promise
  /// may be made.
  final bool conditionalWrite;

  /// Whether that CAS holds across tabs, isolates or processes, as
  /// opposed to a mutex inside one isolate.
  final bool crossContextConcurrency;

  /// Whether the adapter stores the original source text rather than a
  /// decoded-and-re-encoded map.
  final bool sourcePreservation;

  /// Whether a backup chain is kept.
  final bool backup;

  /// Whether the adapter exposes an edit history.
  final bool history;

  /// Whether a last known good version can be loaded.
  final bool loadLkg;

  /// Whether the adapter notifies about external edits. A
  /// notification is not a lock.
  final bool changeNotifications;

  /// How much of the validation this backend performs.
  final ValidationAuthority validationAuthority;

  /// A short, value-free note about a limitation, shown by the UI
  /// instead of a silent downgrade.
  final String note;

  /// The capability set of a Web localStorage adapter: persistent
  /// per browser profile, single-key writes only, no transaction
  /// across keys, no cross-tab coordination, and no
  /// promise that a lost update cannot happen
  /// (`SPEC.md` amendment 10).
  static const AisetStorageCapabilities webLocalStorage =
      AisetStorageCapabilities(
    mode: StorageMode.local,
    persistent: true,
    conditionalWrite: false,
    crossContextConcurrency: false,
    sourcePreservation: true,
    backup: false,
    history: false,
    loadLkg: false,
    changeNotifications: false,
    validationAuthority: ValidationAuthority.none,
    note: 'localStorage: single-writer, no cross-tab coordination',
  );

  @override
  String toString() =>
      'AisetStorageCapabilities(${mode.label}, persistent: $persistent, '
      'cas: $conditionalWrite, crossContext: $crossContextConcurrency)';
}

/// How much validation a remote or host backend performs
/// (`SPEC.md` amendment 10).
///
/// Local validation is not protection of the backend against an arbitrary
/// client. A backend that performs no descriptor validation must say
/// so; it must not be presented as full `aiset_service` compatibility.
enum ValidationAuthority {
  /// The backend runs the same descriptor validation, so its
  /// acceptance is authoritative.
  descriptor('descriptor'),

  /// The backend only checks the schema of its own
  /// document API.
  structural('structural'),

  /// The backend stores whatever it is given. The library validates
  /// locally and says plainly that this is not server-side
  /// protection.
  none('none');

  const ValidationAuthority(this.label);

  /// The wire spelling.
  final String label;
}

/// One read result: source text, revision and the permitted
/// metadata (`SPEC.md` amendment 10).
final class AisetStoredDocument {
  /// Creates a read result.
  const AisetStoredDocument({
    required this.sourceText,
    required this.revision,
    this.loadedFrom = 'file',
    this.metadata = const {},
  });

  /// The stored source text, verbatim.
  final String sourceText;

  /// The revision the adapter computed for those bytes.
  final String revision;

  /// Where it came from: `file`, `memory`, `lkg`, `remote`.
  final String loadedFrom;

  /// Permitted metadata. Physical secret paths are never part of it
  /// (`SPEC.md` amendment 10).
  final Map<String, Object?> metadata;

  @override
  String toString() => 'AisetStoredDocument(@ $revision, $loadedFrom)';
}

/// The answer to a conditional write
/// (`SPEC.md` amendment 10).
enum AisetCommitStatus {
  /// The bytes are stored.
  committed('committed'),

  /// The expected revision no longer matches. Nothing was written.
  revisionConflict('revision_conflict'),

  /// The adapter refused the write on policy or capacity grounds. Nothing was
  /// written.
  rejected('rejected'),

  /// The adapter cannot tell whether the write landed. The caller must
  /// re-read the state, never repeat the write
  /// (`SPEC.md` amendment 8).
  uncertain('uncertain');

  const AisetCommitStatus(this.label);

  /// The wire spelling.
  final String label;
}

/// The outcome of one [AisetStorage.compareAndSwap].
final class AisetCommitResult {
  /// Creates a commit outcome.
  const AisetCommitResult(this.status, {this.revision, this.report, this.detail = ''});

  /// The four-way status of the attempt.
  final AisetCommitStatus status;

  /// The revision now stored, when it can be established.
  final String? revision;

  /// The store's own report, with its retry and backup detail.
  final CommitReport? report;

  /// A short technical reason for [AisetCommitStatus.rejected].
  final String detail;

  /// Whether the bytes are confirmed stored.
  bool get isCommitted => status == AisetCommitStatus.committed;

  @override
  String toString() => 'AisetCommitResult(${status.label}, $revision)';
}

/// The storage port the pipeline writes through
/// (`SPEC.md` amendments 10 and 14).
///
/// This is the minimal host contract, and the same port is what
/// the built-in local adapters and the remote profiles
/// implement (slice 2E): the pipeline never knows which.
/// Semantics, not names, are the mandatory part of the
/// contract:
///
/// * [read] returns the stored source text and the revision the adapter
///   computed for those bytes. A failure to reach the
///   store is a thrown [AisetFailure] with `STORAGE_ERROR`, never an
///   empty document — an unavailable backend is not an absent
///   document (`SPEC.md` amendments 10 and 11, STO-05).
/// * [compareAndSwap] writes [sourceText] only if the stored revision is
///   still [expectedRevision], and reports one of the four
///   outcomes. An adapter that cannot do this must declare
///   `conditionalWrite: false` and answer
///   `UNSUPPORTED_CAPABILITY`.
/// * [capabilities] is the truth about what the adapter can
///   promise.
abstract interface class AisetStorage {
  /// The declared guarantees of this adapter.
  AisetStorageCapabilities get capabilities;

  /// Reads the current source text and revision.
  Future<AisetStoredDocument> read();

  /// Writes [sourceText] if the stored revision is still [expectedRevision].
  Future<AisetCommitResult> compareAndSwap({
    required String expectedRevision,
    required String sourceText,
  });
}
