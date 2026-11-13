part of 'pipeline.dart';

/// Builds the four views of `SPEC.md` amendment 2 for one
/// stored source text, and reports which paths one write changed.
///
/// [buildSnapshot] is what a read returns and what the
/// pipeline re-derives after a commit: stored
/// (the original JSON5 and its decoded values, placeholders kept),
/// effective (mounted layers, resolution, defaults), active (what the
/// application confirmed) and, for the editor, the draft the controller owns
/// and this service never sees.
///
/// Two rules bind the result:
///
/// * **A secret is never disclosed by a view.**
///   [AisetSnapshot] carries the unreadable-for-this-principal form;
///   the redaction itself is the service's
///   [_authorized] filter, so the snapshot a host stores
///   and the snapshot a UI renders come from one place
///   (`SPEC.md` amendments 6 and 26, SEC-01).
/// * **Provenance names sources, never values.** A materialized
///   default, a variable, and a mounted layer are three
///   different answers for the same pointer and each is
///   recorded with its kind (`SPEC_.md` 38, report A27: the executed
///   baseline overwrites a default's provenance with `file` while
///   the single-pointer read reports `default` for the same
///   field).
Future<AisetSnapshot> buildSnapshot({
  required AisetDocumentRegistration registration,
  required String sourceText,
  required String sourceRevision,
  required Object? activeTree,
  required String activeRevision,
  required Limits limits,
  required String registryRevision,
  String loadedFrom = 'file',
  String invalidReason = '',
  List<AisetIssue> invalidIssues = const [],
}) async {
  final document = Json5Document(sourceText, origin: registration.documentId);
  final stored = document.storedValue();
  final layered = applyMountLayers(stored, registration.layers);
  final resolution = buildEffective(
      layered.tree, registration.descriptor.root, registration.resolver);
  final issues = <AisetIssue>[
    for (final issue in resolution.issues)
      AisetIssue(
        rule: issue.rule,
        path: issue.path,
        message: issue.message,
        severity: issue.severity == ResolutionSeverity.error
            ? AisetSeverity.error
            : AisetSeverity.warning,
      ),
  ];
  var effective = resolution.value;
  if (issues.any((i) => i.severity == AisetSeverity.error)) {
    // A value that could not be resolved has no type to
    // constrain: the resolution issues are the answer and the
    // document is reported invalid rather than half-validated.
    effective = layered.tree;
  } else {
    issues.addAll(validateResolved(effective, registration, limits));
  }
  final invalid = issues.any((i) => i.severity == AisetSeverity.error);
  final provenance = <String, Provenance>{
    ...layered.provenance,
    ...resolution.provenance,
  };
  return AisetSnapshot(
    documentId: registration.documentId,
    sourceText: sourceText,
    storedTree: stored,
    effectiveTree: effective,
    activeTree: activeTree ?? effective,
    provenance: provenance,
    sourceRevision: sourceRevision,
    descriptorRevision: registration.descriptor.revision,
    activeRevision: activeRevision,
    layersRevision: registration.layersRevision,
    resolverRevision: computeResolverRevision(registration.resolver),
    registryRevision: registryRevision,
    issues: issues,
    loadedFrom: invalid ? 'invalid' : loadedFrom,
    invalidOnDisk: invalid,
    invalidReason: invalid
        ? (invalidReason.isEmpty ? _firstErrorSummary(issues) : invalidReason)
        : invalidReason,
    document: document,
  );
}

/// The first blocking issue as a short reason. It names a rule and a
/// pointer, never a value.
String _firstErrorSummary(List<AisetIssue> issues) {
  for (final issue in issues) {
    if (issue.severity == AisetSeverity.error) {
      return '${issue.rule} at ${issue.path.isEmpty ? '/' : issue.path}';
    }
  }
  return 'configuration is invalid';
}

/// The pointers a batch changed: every operation target's subtree,
/// in the document before and after, plus the key a `rename`
/// produced.
///
/// Sorted and de-duplicated, because the order the
/// operations were submitted in is not the order a subscriber
/// should see paths in, and because an append changes its
/// container too.
List<String> batchChangedPaths(
  Json5Document before,
  Json5Document after,
  List<AisetOperation> operations,
) {
  final touched = <String>{};
  for (final operation in operations) {
    for (final document in [before, after]) {
      final base = operation.checkedPath;
      touched.addAll(pathsSafely(document, base));
      final secondary = operation.secondaryPath;
      if (secondary != null) touched.addAll(pathsSafely(document, secondary));
      // An appended item changes its container as
      // well as the item itself.
      if (operation.path.endsWith('/$appendMarker')) {
        final container = operation.path.substring(0, operation.path.length - 2);
        touched.addAll(pathsSafely(document, container));
      }
    }
    if (operation.kind == AisetOperationKind.rename) {
      final parent = splitPointer(operation.path).parentPointer;
      final newKey = operation.to;
      if (newKey != null && newKey.isNotEmpty) {
        final pointer = '$parent/${escapeToken(newKey)}';
        touched.addAll(pathsSafely(before, pointer));
        touched.addAll(pathsSafely(after, pointer));
      }
    }
  }
  final out = touched.toList()..sort();
  return out;
}

/// The pointers present before or after one pointer-targeted
/// write, at or below it.
List<String> changedPathsFor(Json5Document before, Json5Document after, String pointer) {
  final out = <String>{...pathsSafely(before, pointer), ...pathsSafely(after, pointer)}.toList()
    ..sort();
  return out;
}
