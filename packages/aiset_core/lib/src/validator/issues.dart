part of 'validator.dart';

/// How serious a [ValidationIssue] is.
enum ValidationSeverity {
  /// The value is rejected.
  error('error'),

  /// A check could not be performed; the value is not
  /// rejected by this issue alone.
  warning('warning');

  const ValidationSeverity(this.label);

  /// The label used in envelopes and diagnostics.
  final String label;
}

/// One structured validation problem (`SPEC.md` amendment 26).
///
/// [rule] is the stable rule name the pipeline and the HTTP envelope report
/// under `VALIDATION_ERROR` (`minimum`, `pattern`,
/// `max_depth`, …). [path] is the JSON Pointer of the value
/// the issue is about, `''` for the root.
final class ValidationIssue {
  /// Creates a validation issue.
  const ValidationIssue({
    required this.rule,
    required this.path,
    required this.message,
    this.severity = ValidationSeverity.error,
  });

  /// The stable rule name.
  final String rule;

  /// Pointer of the offending value (`''` is the root).
  final String path;

  /// Short human-readable reason. It never contains a value, so
  /// validation cannot disclose a secret through an issue
  /// (`SPEC.md` amendments 6 and 26).
  final String message;

  /// Whether the issue rejects the value.
  final ValidationSeverity severity;

  /// The stable error code of the envelope this issue maps to.
  String get code => 'VALIDATION_ERROR';

  @override
  String toString() =>
      'ValidationIssue($rule at ${path.isEmpty ? '<root>' : path}, ${severity.label})';
}
