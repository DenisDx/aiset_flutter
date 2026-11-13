part of 'pipeline.dart';

/// The ephemeral memory store: the storage mode the amendment keeps for
/// tests and temporary documents, never a fourth persistent user mode
/// (`SPEC.md` amendment 10).
///
/// It implements the same [AisetStorage] port as every real adapter, with
/// honest capabilities: [AisetStorageCapabilities.persistent] is false,
/// conditional write is true because the compare-and-swap is atomic inside the
/// isolate, and backup/history/LKG are false because this store keeps no
/// chain. A host therefore gets no last-known-good promise from it, exactly as
/// the amendment requires.
///
/// Two services may be registered against one instance of this store —
/// that is how a test proves the concurrency rule from the outside:
/// whichever writer holds the current revision wins, and the other is refused
/// with `REVISION_CONFLICT` while the stored bytes stay untouched.
final class AisetMemoryStorage implements AisetStorage {
  /// Creates a store holding [initialText]; pass [absent] to start with no
  /// document at all, the state an initial create must confirm into.
  AisetMemoryStorage({String initialText = '', bool absent = false})
      : _text = absent ? null : initialText,
        _revision = absent ? null : sourceRevisionOfText(initialText);

  String? _text;
  String? _revision;

  /// Whether nothing is stored yet.
  bool get isAbsent => _text == null;

  /// The stored text, or `null` when nothing is stored.
  String? get text => _text;

  /// The revision of the stored bytes, or `null`.
  String? get revision => _revision;

  @override
  AisetStorageCapabilities get capabilities =>
      const AisetStorageCapabilities(
        mode: StorageMode.memory,
        persistent: false,
        conditionalWrite: true,
        crossContextConcurrency: false,
        sourcePreservation: true,
        backup: false,
        history: false,
        loadLkg: false,
        changeNotifications: false,
        validationAuthority: ValidationAuthority.none,
        note: 'memory store: ephemeral, one isolate, no backup chain',
      );

  @override
  Future<AisetStoredDocument> read() async {
    final text = _text;
    final revision = _revision;
    if (text == null || revision == null) {
      throw AisetFailure(AisetErrorCode.notFound, 'The document is not stored yet');
    }
    return AisetStoredDocument(sourceText: text, revision: revision, loadedFrom: 'memory');
  }

  @override
  Future<AisetCommitResult> compareAndSwap({
    required String expectedRevision,
    required String sourceText,
  }) async {
    final current = _revision;
    if (current != null && current != expectedRevision) {
      return AisetCommitResult(AisetCommitStatus.revisionConflict, revision: current);
    }
    _text = sourceText;
    _revision = sourceRevisionOfText(sourceText);
    return AisetCommitResult(AisetCommitStatus.committed, revision: _revision);
  }

  @override
  String toString() => 'AisetMemoryStorage(${_revision ?? '<absent>'})';

  /// Replaces the stored bytes the way a writer outside this
  /// service would: without a revision check and without telling
  /// anyone.
  ///
  /// This exists so a test can prove the pipeline's
  /// claim about concurrent writes: an adapter that holds the
  /// current revision wins, and a writer whose revision went
  /// stale is refused while the foreign bytes stay untouched.
  void writeExternally(String sourceText) {
    _text = sourceText;
    _revision = sourceRevisionOfText(sourceText);
  }
}
