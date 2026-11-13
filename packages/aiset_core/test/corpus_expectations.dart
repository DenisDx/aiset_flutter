/// Shared loading and comparison helpers for the generated compatibility
/// corpus under `fixtures/python_compat/`.
///
/// The corpus is versioned repository data produced by **executing** the Python
/// baseline, so a missing directory is a checkout failure and never a skip. Only
/// the generator itself needs the clone; see `corpus_generator_test.dart`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:aiset_core/aiset_core.dart';
import 'package:test/test.dart';

import 'fixtures_io.dart';

/// One case of the generated compatibility corpus.
class CompatCase {
  CompatCase._(this.area, this.file, this.body);

  /// Loads a case file.
  factory CompatCase.load(String area, File file) => CompatCase._(
      area, file, jsonDecode(file.readAsStringSync()) as Map<String, Object?>);

  /// The corpus area, e.g. `parse_accept` or `descriptor_compile`.
  final String area;

  /// The fixture file, for failure messages.
  final File file;

  /// The decoded fixture body.
  final Map<String, Object?> body;

  /// Stable case identifier.
  String get id => body['id']! as String;

  /// What the case pins.
  String get description => body['description']! as String;

  /// Behavior tags of the case.
  List<String> get classes => (body['classes']! as List).cast<String>();

  /// The document text fed to the engine.
  String get input => body['input']! as String;

  /// The asserted outcome: what the baseline produced, or the registered
  /// correction of a defective baseline result.
  Map<String, Object?> get expected => body['expected']! as Map<String, Object?>;

  /// The query payload of a `values` or `descriptor_semantics` case.
  Map<String, Object?>? get query => body['query'] as Map<String, Object?>?;

  /// The operation payload of an `operations` case.
  Map<String, Object?>? get operation => body['operation'] as Map<String, Object?>?;

  /// Non-null when the baseline output is a registered defect that the Dart
  /// implementation intentionally corrects (`SPEC.md` amendment 24,
  /// `SPEC_.md` amendment 38).
  ///
  /// A divergent case is never skipped: [expected] holds the corrected
  /// expectation the test asserts, and [baselineEvidence] the result the baseline
  /// actually produced.
  Map<String, Object?>? get divergence =>
      body['divergence'] as Map<String, Object?>?;

  /// The baseline's observed result, recorded as evidence for a case
  /// whose asserted [expected] is a registered correction.
  Map<String, Object?>? get baselineEvidence =>
      body['baselineEvidence'] as Map<String, Object?>?;

  /// Extra request fields the case carries (descriptor `mode`, `strict`,
  /// `typedefSources`, `fragments`).
  Map<String, Object?> get request => {
        for (final key in ['mode', 'strict', 'typedefSources', 'fragments'])
          if (body.containsKey(key)) key: body[key],
      };
}

/// The corpus areas, in the order the generator writes them.
const List<String> compatAreas = [
  'parse_accept',
  'parse_reject',
  'values',
  'operations',
  'descriptor_validate',
  'descriptor_compile',
  'descriptor_semantics',
  'resolver_lookup',
  'resolver_text',
  'resolver_effective',
  'validator_profile',
  'validator_value',
  'merge_base',
  'merge_update',
  'merge_immutability',
  'pipeline_revisions',
  'pipeline_operations',
  'pipeline_dry_run',
  'pipeline_rejections',
  'pipeline_revision_pair',
  'pipeline_views',
  'pipeline_callbacks',
];

/// The generated corpus directory, or a [StateError] explaining the broken
/// checkout. The corpus is versioned repository data, so a missing directory
/// is a failure and not a skip; `AISET_COMPAT_FIXTURES` overrides the location.
Directory compatDir() {
  final fromEnv = Platform.environment['AISET_COMPAT_FIXTURES'];
  final candidates = <String>[
    ?fromEnv,
    '../../fixtures/python_compat',
    'fixtures/python_compat',
  ];
  for (final candidate in candidates) {
    if (Directory(candidate).existsSync()) return Directory(candidate);
  }
  throw StateError(
    'Compatibility corpus not found. Looked in: ${candidates.join(', ')}. '
    'Expected the versioned fixtures/python_compat/ directory of the '
    'repository (or set AISET_COMPAT_FIXTURES).',
  );
}

/// The committed corpus.
class CompatCorpus {
  CompatCorpus._(this.root, this.byArea);

  /// Loads every area directory.
  factory CompatCorpus.load() {
    final root = compatDir();
    final byArea = <String, List<CompatCase>>{};
    for (final area in compatAreas) {
      final dir = Directory(join(root.path, area));
      if (!dir.existsSync()) {
        throw StateError('corpus area ${dir.path} is missing');
      }
      final files = dir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      if (files.isEmpty) {
        throw StateError('corpus area ${dir.path} is empty');
      }
      byArea[area] = [for (final file in files) CompatCase.load(area, file)];
    }
    return CompatCorpus._(root, byArea);
  }

  /// The corpus directory.
  final Directory root;

  /// Cases by area.
  final Map<String, List<CompatCase>> byArea;

  /// The cases of one area.
  List<CompatCase> area(String name) => byArea[name]!;

  /// The parsed `fixtures/BASELINE` document.
  Map<String, Object?> baseline() {
    final file = File(join(root.path, '..', 'BASELINE'));
    if (!file.existsSync()) {
      throw StateError('fixtures/BASELINE is missing next to the corpus');
    }
    return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  }
}

// -- expectation helpers -------------------------------------------------------

/// Decodes the driver's tagged value encoding into plain Dart data.
Object? decodeTagged(Object? node) {
  final tagged = node! as Map<String, Object?>;
  switch (tagged['k']! as String) {
    case 'null':
      return null;
    case 'missing':
      return resolverMissing;
    case 'bool':
      return tagged['v'];
    case 'int':
      final text = tagged['v']! as String;
      return int.tryParse(text) ?? BigInt.parse(text);
    case 'double':
      final value = tagged['v']!;
      if (value is String) {
        switch (value) {
          case 'inf':
            return double.infinity;
          case '-inf':
            return double.negativeInfinity;
          default:
            return double.nan;
        }
      }
      return (value as num).toDouble();
    case 'string':
      return tagged['v'];
    case 'template':
      final ref = tagged['v']! as Map<String, Object?>;
      return TemplateRef(ref['name']! as String, ref['default'] as String?);
    case 'object':
      return <String, Object?>{
        for (final entry in tagged['v']! as List)
          (entry as List)[0]! as String: decodeTagged(entry[1]),
      };
    case 'array':
      return [for (final item in tagged['v']! as List) decodeTagged(item)];
    default:
      throw StateError('unknown tagged value: $tagged');
  }
}

/// Whether [value] is a tagged-value map rather than an ordinary object.
bool isTaggedMap(Object? value) =>
    value is Map && value.containsKey('k') && value['k'] is String;

/// Replaces every tagged value inside [value] with plain Dart data,
/// leaving the surrounding structure untouched.
Object? decodeTaggedTree(Object? value) {
  if (isTaggedMap(value)) return decodeTagged(value);
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key as String: decodeTaggedTree(entry.value),
    };
  }
  if (value is List) return [for (final item in value) decodeTaggedTree(item)];
  return value;
}

/// Deep equality that also accepts `NaN` against `NaN` and `int` against
/// `BigInt` of the same magnitude.
///
/// Returns `null` when [actual] matches [expected], otherwise a description of
/// the first difference.
String? describeMismatch(Object? actual, Object? expected, [String path = r'$']) {
  if (expected is Map) {
    if (actual is! Map) {
      return '$path: expected ${_render(expected)}, got ${_render(actual)}';
    }
    if (expected.length != actual.length) {
      return '$path: expected ${expected.length} keys, got ${actual.length} '
          '(expected ${_render(expected)}, got ${_render(actual)})';
    }
    for (final entry in expected.entries) {
      if (!actual.containsKey(entry.key)) {
        return '$path: missing key ${_render(entry.key)}';
      }
      final nested = describeMismatch(actual[entry.key], entry.value, '$path.${entry.key}');
      if (nested != null) return nested;
    }
    return null;
  }
  if (expected is List) {
    if (actual is! List) {
      return '$path: expected ${_render(expected)}, got ${_render(actual)}';
    }
    if (expected.length != actual.length) {
      return '$path: expected length ${expected.length}, got ${actual.length} '
          '(expected ${_render(expected)}, got ${_render(actual)})';
    }
    for (var index = 0; index < expected.length; index++) {
      final nested = describeMismatch(actual[index], expected[index], '$path[$index]');
      if (nested != null) return nested;
    }
    return null;
  }
  if (expected is double && expected.isNaN && actual is double && actual.isNaN) {
    return null;
  }
  if (actual is BigInt && expected is int) {
    return actual == BigInt.from(expected) ? null : '$path: expected $expected, got $actual';
  }
  if (actual is int && expected is BigInt) {
    return BigInt.from(actual) == expected ? null : '$path: expected $expected, got $actual';
  }
  if (actual is String && expected is String && actual != expected) {
    return '$path: expected "${_escapePreview(expected)}", got "${_escapePreview(actual)}"';
  }
  if (actual != expected) {
    return '$path: expected ${_render(expected)}, got ${_render(actual)}';
  }
  return null;
}

String _escapePreview(String value) =>
    value.length > 120 ? '${value.substring(0, 120)}…' : value;

String _render(Object? value) => value is String
    ? '"${_escapePreview(value)}"'
    : value is List || value is Map
        ? jsonEncode(value)
        : '$value';

/// Asserts that [body] fails with the stable error [code], or - when the
/// baseline had no code because it crashed - that the Dart engine rejects
/// the input with a positioned parse error.
void expectCode(String? code, void Function() body) {
  if (code == null) {
    expect(body, throwsA(isA<Json5ParseException>()));
    return;
  }
  expect(
    body,
    throwsA(anyOf(
      isA<Json5SourceException>().having((e) => e.code, 'code', equals(code)),
      isA<DescriptorException>().having((e) => e.code, 'code', equals(code)),
    )),
  );
}

/// Asserts that two diagnostic lists carry the same issues, ignoring
/// the order the grammar rules produced them in.
///
/// Issue order is not part of the observable contract: what a
/// client sees is which properties are reported, at what severity and at what
/// position. Only the fields present in [expected] are compared, so a corrected
/// case can pin the diagnostic it is about without restating a
/// position the baseline never produced.
void expectSameIssues(
    List<DescriptorIssue> actual, List<Object?> expected, String reason) {
  expect(actual.length, equals(expected.length),
      reason: '$reason: ${_describeIssues(actual)}');
  final remaining = [...expected];
  for (final issue in actual) {
    final match = remaining.indexWhere((candidate) =>
        _issueMatches(issue, candidate as Map<String, Object?>));
    if (match < 0) {
      fail('$reason: unexpected issue $issue; expected ${_render(expected)}');
    }
    remaining.removeAt(match);
  }
  if (remaining.isNotEmpty) {
    fail('$reason: missing issues ${_render(remaining)}; got ${_describeIssues(actual)}');
  }
}

bool _issueMatches(DescriptorIssue issue, Map<String, Object?> expected) {
  bool field(String key, Object? Function() read) =>
      !expected.containsKey(key) || read() == expected[key];
  return field('code', () => issue.code) &&
      field('severity', () => issue.severity.label) &&
      field('path', () => issue.path) &&
      field('line', () => issue.line) &&
      field('column', () => issue.column) &&
      (!expected.containsKey('hasMessage') ||
          (expected['hasMessage'] as bool) == issue.message.isNotEmpty);
}

String _describeIssues(List<DescriptorIssue> issues) => jsonEncode([
      for (final issue in issues)
        {
          'code': issue.code,
          'severity': issue.severity.label,
          'path': issue.path,
          'line': issue.line,
          'column': issue.column,
        },
    ]);
