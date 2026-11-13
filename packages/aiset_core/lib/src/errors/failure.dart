part of 'errors.dart';

/// How serious an [AisetIssue] is.
enum AisetSeverity {
  /// The operation is refused.
  error('error'),

  /// A check could not be performed; this issue alone does not
  /// refuse the value.
  warning('warning');

  const AisetSeverity(this.label);

  /// The label carried in an envelope.
  final String label;
}

/// One structured problem reported by the pipeline (`SPEC.md` amendment 26).
///
/// [rule] is the stable rule name — an operation rejection
/// (`operation`), a descriptor path problem (`undeclared_path`), a value
/// constraint (`maximum`), a resource limit (`max_depth`) or a
/// pre-commit veto. [path] is the JSON Pointer the issue is about,
/// `''` for the root. [line] and [column] are the
/// 1-based source position of that path in the candidate, when
/// the pipeline could locate it.
///
/// [message] is human-readable and never contains a configured value:
/// the same rule that binds a validation message binds
/// this one, because an issue travels to the UI, the
/// audit log and sometimes an HTTP response.
final class AisetIssue {
  /// Creates a structured issue.
  const AisetIssue({
    required this.rule,
    required this.path,
    required this.message,
    this.severity = AisetSeverity.error,
    this.line,
    this.column,
  });

  /// The stable rule name.
  final String rule;

  /// Pointer of the value the issue is about.
  final String path;

  /// Short human-readable reason, never a configured value.
  final String message;

  /// Whether the issue blocks the operation.
  final AisetSeverity severity;

  /// 1-based line of [path] in the candidate source, when located.
  final int? line;

  /// 1-based column of [path] in the candidate source, when located.
  final int? column;

  /// The envelope form: only the keys that carry information.
  Map<String, Object?> toMap() => {
        'path': path,
        'rule': rule,
        'message': message,
        'severity': severity.label,
        if (line != null) 'line': line,
        if (column != null) 'column': column,
      };

  @override
  String toString() =>
      'AisetIssue($rule at ${path.isEmpty ? '<root>' : path}, ${severity.label})';
}

/// A rejected operation, in the shape the envelope and the public API
/// share.
///
/// One type rather than an exception per code, because the code is the
/// contract and Dart callers can catch this and switch on
/// [code] (`SPEC.md` amendment 14: typed errors keep Python-compatible
/// codes, and the envelope and the exceptions draw on one source).
///
/// [issues] carries the structured detail a validation or
/// operation failure produced; [detail] is a short technical
/// note for logs — for a conflict it names the revision the store
/// holds, which is what a client needs to recover. Neither field
/// ever contains a configured value.
final class AisetFailure implements Exception {
  /// Creates a failure with one of the stable codes.
  AisetFailure(
    this.code,
    this.message, {
    List<AisetIssue> issues = const [],
    this.detail,
  })  : issues = List<AisetIssue>.unmodifiable(issues),
        assert(AisetErrorCode.all.contains(code), 'not a stable code: $code');

  /// The stable code; one of [AisetErrorCode.all].
  final String code;

  /// Short human-readable reason.
  final String message;

  /// The structured issues behind the rejection.
  final List<AisetIssue> issues;

  /// A short technical note for diagnostics. Never a value.
  final String? detail;

  /// The HTTP status this code maps to (`AisetErrorCode.httpStatus`).
  int get httpStatus => AisetErrorCode.statusOf(code);

  /// The transport-neutral envelope: `{ ok: false, error: { … } }`.
  Map<String, Object?> toEnvelope() => {
        'ok': false,
        'error': {
          'code': code,
          'message': message,
          if (issues.isNotEmpty) 'issues': [for (final i in issues) i.toMap()],
          if (detail != null && detail!.isNotEmpty) 'detail': detail,
        },
      };

  @override
  String toString() => 'AisetFailure($code): $message'
      '${detail == null || detail!.isEmpty ? '' : ' [$detail]'}'
      '${issues.isEmpty ? '' : ' ${issues.map((i) => i.rule).toList()}'}';
}

/// Reads the 1-based source position of a pointer, or `null` when the
/// candidate has no such position.
typedef PointerLocator = ({int line, int column})? Function(String path);

/// A failure list builder that keeps insertion order and de-duplicates
/// nothing: two problems at one path are two issues, exactly as the
/// baseline reports them.
final class AisetIssueList {
  final List<AisetIssue> _items = [];

  /// The issues collected so far.
  List<AisetIssue> get items => UnmodifiableListView(_items);

  /// Whether any issue blocks the operation.
  bool get hasErrors => _items.any((i) => i.severity == AisetSeverity.error);

  /// The blocking issues.
  List<AisetIssue> get errors =>
      _items.where((i) => i.severity == AisetSeverity.error).toList(growable: false);

  /// Adds [issue].
  void add(AisetIssue issue) => _items.add(issue);

  /// Adds every issue of [issues].
  void addAll(Iterable<AisetIssue> issues) => _items.addAll(issues);

  /// Adds one issue.
  void of(String rule, String path, String message,
          {AisetSeverity severity = AisetSeverity.error}) =>
      _items.add(AisetIssue(
          rule: rule, path: path, message: message, severity: severity));

  /// Attaches the source position of each issue that has none, using
  /// [locate] — the pipeline hands it the candidate document, so
  /// every reported rule points at the text the user would have to edit.
  void locateWith(PointerLocator locate) {
    for (var i = 0; i < _items.length; i++) {
      final issue = _items[i];
      if (issue.line != null) continue;
      final at = locate(issue.path);
      if (at == null) continue;
      _items[i] = AisetIssue(
        rule: issue.rule,
        path: issue.path,
        message: issue.message,
        severity: issue.severity,
        line: at.line,
        column: at.column,
      );
    }
  }
}
