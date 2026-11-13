part of 'pipeline.dart';

/// The mandatory stage order of one write (`SPEC.md` amendment 8, normative):
///
/// ```text
/// authorize → revisions → candidate → resolve → validate → preserve
///           → probe → recheck → commit → apply → audit
/// ```
///
/// The enum documents the order in code; the steps themselves are the private
/// work of [AisetService]. A dry run stops after **preserve** — the
/// preservation check the candidate stage performs on the way is part of
/// producing the candidate — and never reaches probe, recheck, commit, apply
/// or audit, so no callback, subscription or notification can observe a
/// candidate that was not stored.
enum PipelineStage {
  /// The actor is identified and the operation's permission is held; a
  /// subtree the actor may not read or edit is refused here.
  authorize('authorize'),

  /// The revision pair is complete and current.
  revisions('revisions'),

  /// The staged operations are applied to one candidate source sequentially,
  /// so a later one sees an earlier one.
  candidate('candidate'),

  /// The candidate is resolved through the descriptor.
  resolve('resolve'),

  /// The resolved candidate is validated: the resource limits and then the
  /// descriptor constraints.
  validate('validate'),

  /// The candidate keeps every comment of the source it edited; an unsafe
  /// splice is refused rather than a reserialization.
  preserve('preserve'),

  /// The host's pre-commit probes may veto.
  probe('probe'),

  /// The snapshot is re-read and re-checked, so a long probe cannot let a
  /// stale candidate win.
  recheck('recheck'),

  /// The candidate is written once, conditionally.
  commit('commit'),

  /// The application handler runs for a `live`/`reload` change.
  apply('apply'),

  /// The audit record and the subscriptions.
  audit('audit');

  const PipelineStage(this.label);

  /// The name recorded in a diagnostic.
  final String label;
}

/// The outcome of the candidate / resolve / validate / preserve run for one
/// batch.
///
/// Exactly one of these shapes results:
///
/// * a usable [candidateText] with no [hasErrors] — the pipeline may commit;
/// * a [candidateText] carrying error issues, which refuses the batch with
///   `VALIDATION_ERROR`;
/// * no candidate at all, because an operation was refused
///   ([vetoedOperation] names its 0-based position) or because a comment
///   would have been lost ([preservationConflict] names the pointer).
final class CandidateOutcome {
  CandidateOutcome._({
    this.candidateText,
    this.candidateDocument,
    required this.issues,
    this.preservationConflict,
    this.vetoedOperation,
    this.failure,
  });

  /// The candidate source text, or `null` when the run produced none.
  final String? candidateText;

  /// The candidate as a parsed document.
  final Json5Document? candidateDocument;

  /// Every structured issue the stages found.
  final AisetIssueList issues;

  /// The pointer whose replacement could not keep its comments attached.
  final String? preservationConflict;

  /// The 0-based index of the operation that was refused, when one was.
  final int? vetoedOperation;

  /// The permission denial that stopped the batch, when one
  /// happened. A denied actor is the answer of the whole
  /// call, and it is reported as a value rather than an
  /// exception so that a transport can render the same envelope a
  /// rejected candidate gets (`SPEC.md` amendments 8, 9 and 14).
  final AisetFailure? failure;

  /// Whether an error-severity issue blocks the candidate.
  bool get hasErrors => issues.hasErrors;

  /// Whether a comment had to be dropped to produce the candidate.
  bool get hasPreservationConflict => preservationConflict != null;

  @override
  String toString() =>
      'CandidateOutcome(${candidateText == null ? 'no candidate' : 'candidate'}, '
      '${issues.items.length} issues)';
}

/// Applies [operations] in sequence to [text], then resolves, validates and
/// preservation-checks the result.
///
/// Each operation is authorized against the descriptor and the principal
/// before it is applied, and the next operation sees the previous one's
/// result, which is what makes create-the-container-then-fill-it work inside a
/// single batch (`SPEC.md` amendment 8).
///
/// A refused operation stops the batch and no candidate is kept: the whole
/// batch is saved by one write or not at all. Nothing here rolls back an
/// external action, and this is not a distributed transaction.
CandidateOutcome buildCandidate({
  required String text,
  required List<AisetOperation> operations,
  required AisetDocumentRegistration registration,
  required Principal principal,
  required Limits limits,
}) {
  final issues = AisetIssueList();
  final base = Json5Document(text, origin: registration.documentId);
  var current = text;
  for (var position = 0; position < operations.length; position++) {
    final operation = operations[position];
    try {
      current = _applyAuthorized(current, base, operation, registration, principal);
    } on AisetVeto catch (veto) {
      if (veto.preservationConflict) {
        return CandidateOutcome._(
            issues: issues, preservationConflict: operation.checkedPath);
      }
      issues.of(
        'operation',
        operation.path,
        'Operation ${position + 1} (${operation.kind.label}) failed: ${veto.message}',
      );
      return CandidateOutcome._(issues: issues, vetoedOperation: position);
    } on AisetFailure catch (denied) {
      return CandidateOutcome._(issues: issues, vetoedOperation: position, failure: denied);
    }
  }

  // Every operation applied. The candidate is parsed, resolved and
  // validated as a whole, so an edit that is legal operation by operation and
  // illegal as a document is still refused.
  final Json5Document candidate;
  try {
    candidate = Json5Document(current, origin: registration.documentId);
  } on Json5SourceException catch (error) {
    issues.of('parse', '', error.message);
    return CandidateOutcome._(issues: issues);
  }
  final stored = candidate.storedValue();
  final structural = [for (final i in checkLimits(stored, limits: limits)) _asIssue(i)];
  if (structural.isNotEmpty) {
    issues.addAll(structural);
    return CandidateOutcome._(
        candidateText: current, candidateDocument: candidate, issues: issues);
  }
  issues.addAll(_resolveAndValidate(stored, registration, limits));
  // Every reported rule points at the text the caller would have to
  // edit, so a UI can jump to the line
  // (`SPEC.md` amendment 26: a structured issue contains path, rule or
  // code, severity, message and source location where available).
  issues.locateWith((path) => locatePointer(candidate, path));
  // The preservation stage: the candidate keeps every comment of the
  // source that the batch did not legitimately address.
  final touched = touchedPaths(base, candidate, operations);
  if (!commentsPreserved(source: base, candidate: candidate, touched: touched)) {
    return CandidateOutcome._(
      candidateText: current,
      candidateDocument: candidate,
      issues: issues,
      preservationConflict: touched.isEmpty ? '' : touched.first,
    );
  }
  return CandidateOutcome._(
      candidateText: current, candidateDocument: candidate, issues: issues);
}

/// The resolution and constraint walk over a candidate tree.
///
/// Resolution problems are issues of their own; the constraint walk runs only
/// when resolution produced no error, because a value that could not be
/// resolved has no type to check and every following complaint would be an
/// artefact of the first (`SPEC.md` amendments 6 and 8).
List<AisetIssue> _resolveAndValidate(
  Object? stored,
  AisetDocumentRegistration registration,
  Limits limits,
) {
  final out = <AisetIssue>[];
  final layered = applyMountLayers(stored, registration.layers);
  final resolution = buildEffective(
      layered.tree, registration.descriptor.root, registration.resolver);
  for (final issue in resolution.issues) {
    out.add(AisetIssue(
      rule: issue.rule,
      path: issue.path,
      message: issue.message,
      severity: issue.severity == ResolutionSeverity.error
          ? AisetSeverity.error
          : AisetSeverity.warning,
    ));
  }
  if (out.any((i) => i.severity == AisetSeverity.error)) return out;
  out.addAll(validateResolved(resolution.value, registration, limits));
  return out;
}

/// The constraint walk over a resolved tree, with the resource limits applied
/// first (`SPEC.md` amendment 26).
List<AisetIssue> validateResolved(
  Object? effective,
  AisetDocumentRegistration registration,
  Limits limits,
) {
  final structural = [for (final i in checkLimits(effective, limits: limits)) _asIssue(i)];
  if (structural.isNotEmpty) return structural;
  return [
    for (final issue
        in validateDocument(effective, registration.descriptor.root, limits: limits).issues)
      _asIssue(issue),
  ];
}

AisetIssue _asIssue(ValidationIssue issue) => AisetIssue(
      rule: issue.rule,
      path: issue.path,
      message: issue.message,
      severity:
          issue.severity == ValidationSeverity.error ? AisetSeverity.error : AisetSeverity.warning,
    );

/// The pointers the batch addressed, which decide which comments were
/// allowed to disappear.
///
/// Both the stored and the candidate document are walked, because a batch may
/// create a container and then fill it, and a `rename`
/// produces a pointer that exists only after the batch
/// (`SPEC.md` amendment 8).
List<String> touchedPaths(
    Json5Document base, Json5Document candidate, List<AisetOperation> operations) {
  final touched = <String>{};
  for (final operation in operations) {
    for (final document in [base, candidate]) {
      touched.addAll(pathsSafely(document, operation.checkedPath));
      final secondary = operation.secondaryPath;
      if (secondary != null) touched.addAll(pathsSafely(document, secondary));
    }
    if (operation.kind == AisetOperationKind.rename) {
      final parent = splitPointer(operation.path).parentPointer;
      final newKey = operation.to;
      if (newKey != null && newKey.isNotEmpty) {
        final pointer = '$parent/${escapeToken(newKey)}';
        touched.addAll(pathsSafely(base, pointer));
        touched.addAll(pathsSafely(candidate, pointer));
      }
    }
  }
  return touched.toList()..sort();
}

/// Whether the candidate keeps every comment of [source] that lies
/// outside the paths the batch addressed.
///
/// This is the observable half of the preservation stage. Nothing may
/// be lost: an untouched comment of the source must still appear in
/// the candidate, with the same kind and text. A comment may
/// legitimately be *re-owned* by the splice (removing an array item
/// renumbers its siblings), and a submitted
/// `value_text` may bring a new comment of its own, so the test is
/// inclusion of the untouched source comments, not set
/// equality. Whether a comment was *detached* from the value it belongs
/// to is refused earlier by the splice engine itself with
/// `COMMENT_PRESERVATION_CONFLICT` (`SPEC.md` amendment 3
/// write rules 1, 2 and 6).
bool commentsPreserved({
  required Json5Document source,
  required Json5Document candidate,
  required List<String> touched,
}) {
  final kept = <String, int>{};
  for (final comment in candidate.comments) {
    final key = _commentKey(comment);
    kept[key] = (kept[key] ?? 0) + 1;
  }
  final sourceIndex = pointerIndex(source);
  for (final comment in source.comments) {
    final path = sourceIndex[comment.owner] ?? '';
    if (touched.any((pointer) => _overlaps(path, pointer))) continue;
    final key = _commentKey(comment);
    final count = kept[key] ?? 0;
    if (count == 0) return false;
    kept[key] = count - 1;
  }
  return true;
}

/// The identity of a comment for the preservation
/// comparison: its kind and its exact text. Neither the
/// owner pointer nor the role takes part, because both may
/// change legitimately when a neighbour of the comment is
/// rewritten, and neither change loses a comment.
String _commentKey(CommentNode comment) => '${comment.kind.name}|${comment.text}';

bool _overlaps(String a, String b) => a.isEmpty || b.isEmpty
    ? a == b
    : (a == b || a.startsWith('$b/') || b.startsWith('$a/'));
