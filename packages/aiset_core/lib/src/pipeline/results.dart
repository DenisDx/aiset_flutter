part of 'pipeline.dart';

/// What the application needs after one committed write
/// (`SPEC.md` amendment 8).
///
/// The descriptor declares per node whether a change is `live`,
/// needs a `reload` or needs a `restart`; an undeclared node means
/// `restart`, so a value the host never classified is never
/// pretended to be live. The result of a batch is the
/// strictest policy among the changed paths.
enum ApplyPolicy {
  /// The next read already returns the new value.
  live('live', 0),

  /// The host must re-read its configuration and re-apply it.
  reload('reload', 1),

  /// Only a process restart picks the change up.
  restart('restart', 2);

  const ApplyPolicy(this.label, this.strictness);

  /// The descriptor and wire spelling.
  final String label;

  /// Higher wins: `restart` is stricter than `reload`,
  /// which is stricter than `live`.
  final int strictness;

  /// The policy named by [label], or `null` for an unknown name.
  static ApplyPolicy? tryParse(String? label) {
    for (final policy in ApplyPolicy.values) {
      if (policy.label == label) return policy;
    }
    return null;
  }

  /// The strictest of [policies]; [live] is the identity, because
  /// "nothing restrictive was declared" is not a restriction.
  static ApplyPolicy strictestOf(Iterable<ApplyPolicy> policies) {
    var best = ApplyPolicy.live;
    for (final policy in policies) {
      if (policy.strictness > best.strictness) best = policy;
    }
    return best;
  }
}

/// The state the library reports about application
/// (`SPEC.md` amendment 8).
///
/// | state | meaning for the host |
/// |---|---|
/// | `applied` | every changed node is `live`; the next read sees the value |
/// | `reload_required` | the host must re-read and re-apply its configuration |
/// | `restart_required` | only a process restart picks the change up |
/// | `apply_failed` | the application handler failed; the file is committed |
enum ApplicationState {
  /// A `live` change is in effect: stored and active revisions agree.
  applied('applied'),

  /// Committed; the host must re-read.
  reloadRequired('reload_required'),

  /// Committed; the process must restart.
  restartRequired('restart_required'),

  /// Committed, and the host's apply step failed. The write is
  /// NOT undone and the result is NOT reported as unsaved.
  applyFailed('apply_failed');

  const ApplicationState(this.label);

  /// The wire spelling.
  final String label;

  @override
  String toString() => 'ApplicationState($label)';
}

/// The outcome of one conditional write
/// (`SPEC.md` amendments 8, 10 and 11).
///
/// [uncertain] is the state the amendment forces the
/// library to distinguish: the write may or may not have
/// reached storage, so the correct next move is to re-read the
/// state, never to repeat the write blindly.
final class CommitReport {
  /// Creates a report.
  const CommitReport({
    required this.committed,
    required this.revision,
    this.uncertain = false,
    this.detail = '',
    this.document = '',
  });

  /// Whether the store confirmed the bytes.
  final bool committed;

  /// The revision now stored, or `null` when nothing was confirmed.
  final String? revision;

  /// Whether the outcome could not be established.
  final bool uncertain;

  /// A short technical reason; never a configured value.
  final String detail;

  /// The document the report is about.
  final String document;

  /// The wire form.
  Map<String, Object?> toMap() => {
        'document': document,
        'committed': committed,
        'revision': revision,
        'uncertain': uncertain,
        'detail': detail,
      };

  @override
  String toString() =>
      'CommitReport(committed: $committed, uncertain: $uncertain, revision: $revision)';
}

/// The result of one write: the single entry point of the pipeline
/// (`SPEC.md` amendment 8).
///
/// A dry run answers with [candidateText] and the
/// [issues] the candidate would produce, and with
/// [stored] false — the stored source is byte-for-byte
/// unchanged. A pre-commit failure answers with a
/// [failure] and the same guarantee. A
/// successful save whose application step failed still has
/// [stored] true and [applicationState] [ApplicationState.applyFailed]:
/// the library must not report a saved file as unsaved.
final class AisetWriteResult {
  /// Creates a result.
  AisetWriteResult({
    required this.document,
    required this.stored,
    required this.revision,
    required this.descriptorRevision,
    required this.activeRevision,
    required this.applicationState,
    required this.changedPaths,
    List<AisetIssue> issues = const [],
    this.candidateText,
    this.commit,
    this.failure,
    this.layerRevision,
    this.resolverRevision,
    this.registryRevision,
  }) : issues = List<AisetIssue>.unmodifiable(issues);

  /// The registered document id.
  final String document;

  /// Whether the write reached storage.
  final bool stored;

  /// The revision the document now holds.
  final String revision;

  /// The descriptor revision the candidate was validated against.
  final String descriptorRevision;

  /// The revision the application is running on. Differs from
  /// [revision] for a reload, restart or failed apply, and only
  /// [ApplicationState.applied] means the two agree.
  final String activeRevision;

  /// The outcome of application handling, or `null` when nothing was
  /// committed (a dry run or a rejection).
  final ApplicationState? applicationState;

  /// The pointers the candidate changes; empty for a
  /// rejection that never produced a candidate.
  final List<String> changedPaths;

  /// Every structured issue found on the way, including the
  /// warnings that did not block the write.
  final List<AisetIssue> issues;

  /// The candidate source text the pipeline produced — a dry
  /// run's main answer. `null` when the pipeline never got that
  /// far (an authorization, revision or parse failure).
  final String? candidateText;

  /// The store's own report, when a commit was attempted.
  final CommitReport? commit;

  /// The rejection that stopped the write, if any.
  final AisetFailure? failure;

  /// The internal revisions captured with this candidate
  /// (`SPEC.md` amendment 8).
  final String? layerRevision;

  /// The resolver revision captured with this candidate.
  final String? resolverRevision;

  /// The registry revision captured with this candidate.
  final String? registryRevision;

  /// Whether the write was rejected before the commit.
  bool get rejected => failure != null;

  /// Whether the candidate the run produced is free of blocking issues.
  ///
  /// A dry run reports this instead of refusing: the caller asked what
  /// would happen, and a batch that would not validate is an
  /// answer rather than an error (`SPEC.md` amendment 8). A run
  /// stopped by a stable code — a stale revision, a permission
  /// denial, a preservation conflict — is not valid.
  bool get valid => failure == null && !issues.any((i) => i.severity == AisetSeverity.error);

  /// The transport-neutral envelope.
  Map<String, Object?> toEnvelope() => {
        'ok': !rejected,
        'document': document,
        'stored': stored,
        'revision': revision,
        'descriptor_revision': descriptorRevision,
        'application': {
          'state': applicationState?.label,
          'active_revision': activeRevision,
        },
        if (changedPaths.isNotEmpty) 'changed_paths': changedPaths,
        if (issues.isNotEmpty) 'issues': [for (final i in issues) i.toMap()],
        if (commit != null) 'commit_report': commit!.toMap(),
        if (rejected) 'error': failure!.toEnvelope()['error'],
      };

  @override
  String toString() =>
      'AisetWriteResult($document, stored: $stored, revision: $revision, '
      '${applicationState?.label ?? failure?.code}, ${changedPaths.length} paths)';
}

/// The result of validating a candidate without writing it.
///
/// [valid] is false when any issue blocks; [preservable]
/// is false when the failure is specifically a comment
/// preservation conflict, which the UI shows differently
/// (`SPEC.md` amendments 3 and 8).
final class AisetValidationResult {
  /// Creates a validation answer.
  AisetValidationResult({
    required this.document,
    required this.valid,
    required this.preservable,
    required List<AisetIssue> issues,
    required this.revision,
    required this.descriptorRevision,
    this.candidateText,
  }) : issues = List<AisetIssue>.unmodifiable(issues);

  /// The registered document id.
  final String document;

  /// Whether the candidate is free of blocking issues.
  final bool valid;

  /// Whether the candidate can be produced with comment
  /// preservation intact.
  final bool preservable;

  /// Every issue found.
  final List<AisetIssue> issues;

  /// The current source revision.
  final String revision;

  /// The descriptor revision the candidate was checked against.
  final String descriptorRevision;

  /// The candidate source text, when the pipeline got that far.
  final String? candidateText;

  /// The transport-neutral envelope.
  Map<String, Object?> toEnvelope() => {
        'ok': true,
        'document': document,
        'valid': valid,
        'preservable': preservable,
        'issues': [for (final i in issues) i.toMap()],
        'revision': revision,
        'descriptor_revision': descriptorRevision,
      };

  @override
  String toString() =>
      'AisetValidationResult($document, valid: $valid, preservable: $preservable, '
      '${issues.length} issues)';
}

/// The read answer for one pointer: the four views of
/// `SPEC.md` amendment 2 side by side, with the descriptor's
/// protections for that position.
///
/// [exists] is about the document: a value that is
/// absent and a value that is explicitly null are different, and a
/// default the descriptor supplies is a third — reported
/// through [defaultApplied] and never written into
/// [storedValue] (`SPEC.md` amendments 2 and 6).
final class AisetValueResult {
  /// Creates a read answer.
  const AisetValueResult({
    required this.document,
    required this.path,
    required this.exists,
    required this.sourceText,
    required this.storedValue,
    required this.effective,
    required this.active,
    required this.defaultApplied,
    required this.provenance,
    required this.revision,
    required this.descriptorRevision,
    required this.applyPolicy,
    required this.readOnly,
    required this.secret,
    required this.required,
    required this.constValue,
  });

  /// The registered document id.
  final String document;

  /// The pointer the answer is about.
  final String path;

  /// Whether the document itself holds a value at [path].
  final bool exists;

  /// The exact source slice at [path], or `null` when absent.
  final String? sourceText;

  /// The stored value, with a placeholder kept as [TemplateRef].
  final Object? storedValue;

  /// The effective value: layer, resolution and default applied.
  final Object? effective;

  /// The value the application is running on.
  final Object? active;

  /// Whether [effective] came from the descriptor's default rather
  /// than from a value the document or a layer supplied.
  final bool defaultApplied;

  /// Where the effective value came from, or `null` when the position
  /// holds no value at all: absent without a default has no
  /// origin to attribute. It names variables and layers, never values.
  final Provenance? provenance;

  /// The current source revision.
  final String revision;

  /// The current descriptor revision.
  final String descriptorRevision;

  /// What the host must do for a change here to take effect.
  final ApplyPolicy applyPolicy;

  /// The descriptor's protections for this position.
  final bool readOnly, secret, required, constValue;

  /// The revision pair a write to this position must present.
  RevisionPair get revisionPair =>
      RevisionPair(source: revision, descriptor: descriptorRevision);

  /// The envelope form.
  Map<String, Object?> toEnvelope() => {
        'ok': true,
        'document': document,
        'path': path,
        'exists': exists,
        'default_applied': defaultApplied,
        'effective': effective,
        if (provenance != null) 'provenance': provenance!.toMap(),
        'revision': revision,
        'descriptor_revision': descriptorRevision,
        'application': applyPolicy.label,
      };

  @override
  String toString() =>
      'AisetValueResult($path of $document, exists: $exists, '
      '${provenance?.kind.label ?? 'no value'}${defaultApplied ? ', default' : ''})';
}
