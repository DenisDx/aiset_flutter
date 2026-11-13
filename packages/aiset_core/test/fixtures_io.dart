/// Shared helpers for the preservation-fixture tests.
///
/// Fixtures are versioned repository data under `fixtures/preservation/`
/// (repo root). Tests run with the package root as the working
/// directory, so the default location is `../../fixtures/preservation`;
/// the `AISET_PRESERVATION_FIXTURES` environment variable
/// overrides it for custom checkouts.
library;

import 'dart:convert';
import 'dart:io';



/// The preservation fixtures directory, or a [StateError] explaining the
/// broken checkout (fixture data ships with the repository, so a
/// missing directory is a failure, not a skip).
Directory preservationDir() {
  final fromEnv = Platform.environment['AISET_PRESERVATION_FIXTURES'];
  final candidates = <String>[
    ?fromEnv,
    '../../fixtures/preservation',
    'fixtures/preservation',
  ];
  for (final candidate in candidates) {
    final dir = Directory(candidate);
    if (File('$candidate/manifest.json').existsSync()) {
      return dir;
    }
  }
  throw StateError(
    'Preservation fixtures not found. Looked in: ${candidates.join(', ')}. '
    'Expected the versioned fixtures/preservation/ directory of the '
    'repository (or set AISET_PRESERVATION_FIXTURES).',
  );
}

/// One manifest entry.
class PreservationCase {
  /// Creates a case from its manifest data plus the resolved
  /// fixtures directory.
  PreservationCase({
    required this.id,
    required this.origin,
    required this.classes,
    required this.description,
    required this.inputBytes,
    required this.expectedBytes,
  });

  /// Loads every manifest case with its input and expected bytes.
  static List<PreservationCase> loadAll() {
    final dir = preservationDir();
    final manifest = jsonDecode(
      File(join(dir.path, 'manifest.json')).readAsStringSync(),
    ) as Map<String, Object?>;
    final entries = (manifest['cases']! as List).cast<Map<String, Object?>>();
    return [
      for (final entry in entries)
        PreservationCase(
          id: entry['id']! as String,
          origin: entry['origin']! as String,
          classes: (entry['classes']! as List).cast<String>(),
          description: entry['description']! as String,
          inputBytes:
              File(join(dir.path, entry['input']! as String)).readAsBytesSync(),
          expectedBytes: File(join(dir.path, entry['expected']! as String))
              .readAsBytesSync(),
        ),
    ];
  }

  /// Stable case identifier from the manifest.
  final String id;

  /// `python-baseline` when the text is taken verbatim from the baseline
  /// corpus, `authored` otherwise.
  final String origin;

  /// Edge classes the case covers (bom, crlf, astral, ...).
  final List<String> classes;

  /// Human-readable purpose.
  final String description;

  /// Raw input file bytes.
  final List<int> inputBytes;

  /// Raw expected output bytes (identity with the input).
  final List<int> expectedBytes;

  /// The input decoded as UTF-8, keeping a leading BOM as the
  /// U+FEFF character (`dart:convert` would otherwise strip it).
  String get inputText => decodeUtf8PreserveBom(inputBytes);
}

/// Decodes UTF-8 [bytes] without dropping a byte-order mark, so the decoded
/// string round-trips to the same bytes.
String decodeUtf8PreserveBom(List<int> bytes) {
  final decoded = utf8.decode(bytes);
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return '\uFEFF$decoded';
  }
  return decoded;
}

/// Describes the first byte difference between [actual] and [expected],
/// for readable test failures.
String? firstByteDifference(List<int> actual, List<int> expected) {
  final shared = actual.length < expected.length ? actual.length : expected.length;
  for (var i = 0; i < shared; i++) {
    if (actual[i] != expected[i]) {
      return 'byte $i: expected 0x${expected[i].toRadixString(16)} '
          'got 0x${actual[i].toRadixString(16)}';
    }
  }
  if (actual.length != expected.length) {
    return 'length: expected ${expected.length} bytes, got ${actual.length}';
  }
  return null;
}

/// Joins path segments with `/` (test-only; avoids a package dependency).
String join(String a, [String? b, String? c]) =>
    b == null ? a : (c == null ? '$a/$b' : '$a/$b/$c');
