part of 'descriptor.dart';

/// How serious a [DescriptorIssue] is.
enum DescriptorSeverity {
  /// The descriptor still compiles; the property is reported so an
  /// author can see it (`SPEC.md` amendment 5).
  warning('warning'),

  /// The descriptor is refused.
  error('error');

  const DescriptorSeverity(this.label);

  /// The label used in diagnostics and transport envelopes.
  final String label;
}

/// One structured descriptor diagnostic (`SPEC.md` amendments 5 and 26).
///
/// [path] is a JSON Pointer into the descriptor document — the position an
/// author has to look at — and [line] and [column] are the 1-based source
/// position of that property, counted in Unicode code points like
/// every other length in this product (`docs/grammars.md` §1.4). A position is
/// `null` when the descriptor source could not be parsed at all.
final class DescriptorIssue {
  /// Creates one diagnostic.
  const DescriptorIssue({
    required this.code,
    required this.severity,
    required this.path,
    required this.message,
    this.line,
    this.column,
  });

  /// The descriptor issue code, e.g. `UNKNOWN_DESCRIPTOR_PROPERTY`.
  final String code;

  /// Whether this issue refuses the descriptor.
  final DescriptorSeverity severity;

  /// Pointer to the offending property inside the descriptor document.
  final String path;

  /// Short human-readable reason. Technical detail is not localized
  /// and never echoes a secret value.
  final String message;

  /// 1-based source line, or `null` when unknown.
  final int? line;

  /// 1-based source column in code points, or `null` when unknown.
  final int? column;

  /// The same issue with a source position attached.
  DescriptorIssue withPosition(int line, int column) => DescriptorIssue(
        code: code,
        severity: severity,
        path: path,
        message: message,
        line: line,
        column: column,
      );

  @override
  String toString() =>
      'DescriptorIssue($code, ${severity.label}, $path'
      '${line == null ? '' : ', line $line column $column'}): $message';
}

/// The result of [validateDescriptor].
final class DescriptorDiagnostic {
  /// Creates a diagnostic result.
  const DescriptorDiagnostic({required this.valid, required this.issues});

  /// True when no issue has error severity.
  final bool valid;

  /// Every issue, in the order the grammar rules produced them.
  final List<DescriptorIssue> issues;

  /// The issues that refuse the descriptor.
  List<DescriptorIssue> get errors =>
      issues.where((i) => i.severity == DescriptorSeverity.error).toList();

  @override
  String toString() => 'DescriptorDiagnostic(valid: $valid, ${issues.length} issues)';
}

/// A descriptor problem that stops an operation: an invalid descriptor,
/// or a composition failure.
///
/// [code] is one of the stable codes of `SPEC.md` amendment 26 —
/// `INVALID_DESCRIPTOR` for a grammar or composition failure, `PARSE_ERROR`
/// never (a syntax failure is reported as a [DescriptorIssue] by
/// [validateDescriptor] and thrown as [Json5ParseException] by
/// [compileDescriptor]).
final class DescriptorException implements Exception {
  /// Creates a descriptor failure with its diagnostics.
  DescriptorException(this.message, {this.issues = const [], this.path = ''})
      : code = 'INVALID_DESCRIPTOR';

  /// The stable error code.
  final String code;

  /// Short human-readable reason.
  final String message;

  /// The diagnostics that caused the failure, when they were collected.
  final List<DescriptorIssue> issues;

  /// Pointer of the position the failure is about, when known.
  final String path;

  @override
  String toString() => 'DescriptorException($code): $message'
      '${path.isEmpty ? '' : ' at $path'}';
}

/// Mutable issue under construction while the grammar walk runs.
final class _IssueBuilder {
  final List<DescriptorIssue> issues = [];

  void add(String code, String path, String message,
      {DescriptorSeverity severity = DescriptorSeverity.error}) {
    issues.add(DescriptorIssue(
        code: code, severity: severity, path: path, message: message));
  }

  void warn(String code, String path, String message) =>
      add(code, path, message, severity: DescriptorSeverity.warning);
}
