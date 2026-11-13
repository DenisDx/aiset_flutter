import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Checks the corpus generator against the committed fixtures.
///
/// This is the only suite in the package that needs the Python reference
/// clone, so it skips with an explicit reason when `AISET_PYTHON_BASELINE`
/// is not configured (SPEC.md amendment 36): a machine without the clone still
/// gets a green run from the committed corpus, and this suite is
/// reported as skipped, never as passed.
void main() {
  const skipWithoutBaseline =
      'AISET_PYTHON_BASELINE is not set: the Python reference clone '
      'that generates the corpus is unavailable on this machine '
      '(SPEC.md amendment 36). The committed fixtures under '
      'fixtures/python_compat/ are still tested by compat_corpus_test.dart.';

  final baseline = Platform.environment['AISET_PYTHON_BASELINE'];
  final hasBaseline = baseline != null && baseline.isNotEmpty;

  test('regenerating the corpus reproduces the committed fixtures byte-for-byte', () {
    final repoRoot = Directory.current.parent.parent;
    final generator = File('${repoRoot.path}/tool/generate_corpus.dart');
    expect(generator.existsSync(), isTrue,
        reason: 'the tracked generator is missing: ${generator.path}');

    final first = Directory.systemTemp.createTempSync('aiset-corpus-1-');
    final second = Directory.systemTemp.createTempSync('aiset-corpus-2-');
    addTearDown(() {
      if (first.existsSync()) first.deleteSync(recursive: true);
      if (second.existsSync()) second.deleteSync(recursive: true);
    });

    for (final target in [first, second]) {
      final result = Process.runSync(
        Platform.resolvedExecutable,
        ['run', generator.path, '--baseline', baseline!, '--out', target.path],
        workingDirectory: Directory.current.path,
      );
      expect(result.exitCode, equals(0),
          reason: 'generator failed:\n${result.stdout}\n${result.stderr}');
    }

    // Determinism: two runs differ by nothing at all.
    expect(differences(first, second), isEmpty,
        reason: 'the generator is not deterministic');
    // Provenance: the committed corpus is what this generator and
    // this baseline produce. Only the generated paths are compared; the
    // rest of fixtures/ is hand-maintained data.
    expect(
        differences(Directory('${repoRoot.path}/fixtures'), first),
        isEmpty,
        reason: 'the committed fixtures do not match a fresh '
            'generation; regenerate the corpus');
  }, skip: hasBaseline ? false : skipWithoutBaseline, timeout: const Timeout(Duration(minutes: 20)));

  test('the generator refuses a missing baseline instead of guessing one', () {
    // No --baseline flag and no environment variable: the tool must fail with
    // a usage error that names the variable, never probe the machine.
    final repoRoot = Directory.current.parent.parent;
    final generator = File('${repoRoot.path}/tool/generate_corpus.dart');
    final out = Directory.systemTemp.createTempSync('aiset-corpus-none-');
    addTearDown(() {
      if (out.existsSync()) out.deleteSync(recursive: true);
    });
    final result = Process.runSync(
      Platform.resolvedExecutable,
      ['run', generator.path, '--out', out.path],
      environment: {'PATH': Platform.environment['PATH'] ?? ''},
      // Without the parent environment the tool cannot see the operator's
      // AISET_PYTHON_BASELINE, so it must fail instead of guessing a clone.
      includeParentEnvironment: false,
    );
    expect(result.exitCode, equals(64),
        reason: 'a missing clone must be a usage error: ${result.stderr}');
    expect('${result.stderr}', contains('AISET_PYTHON_BASELINE'));
  });

  test('no corpus or tool file names a local path', () {
    // The corpus and its provenance record must stay author-neutral
    // (SPEC.md amendments 36 and 37): only the commit SHA identifies the clone.
    // The forbidden strings come from this machine's environment, so the
    // check itself never contains a local path.
    final repoRoot = Directory.current.parent.parent;
    final home = Platform.environment['HOME'];
    final forbidden = <String>{
      if (baseline != null && baseline.length > 3) baseline,
      if (home != null && home.length > 1) home,
      if (repoRoot.path != home && repoRoot.path.length > 1) repoRoot.path,
    };
    // A path that reveals a local account name, wherever the machine is.
    // `/root/` is deliberately absent: in this corpus it is the descriptor
    // document's own root pointer (`/root/children/a`), not a directory.
    final accountPath = RegExp(r'/(?:home|Users)/[^/\s]+/');

    final files = <File>[
      File('${repoRoot.path}/fixtures/BASELINE'),
      ...Directory('${repoRoot.path}/fixtures/python_compat')
          .listSync(recursive: true)
          .whereType<File>(),
      File('${repoRoot.path}/tool/generate_corpus.dart'),
      File('${repoRoot.path}/tool/corpus_cases.dart'),
      File('${repoRoot.path}/tool/descriptor_cases.dart'),
      File('${repoRoot.path}/tool/resolver_cases.dart'),
      File('${repoRoot.path}/tool/validator_cases.dart'),
      File('${repoRoot.path}/tool/merge_cases.dart'),
      File('${repoRoot.path}/tool/pipeline_cases.dart'),
      File('${repoRoot.path}/tool/python/corpus_driver.py'),
    ];
    expect(files, isNotEmpty);
    for (final file in files) {
      final text = utf8.decode(file.readAsBytesSync());
      for (final needle in forbidden) {
        expect(text, isNot(contains(needle)),
            reason: '${file.path} leaks the local path "$needle"');
      }
      expect(accountPath.hasMatch(text), isFalse,
          reason: '${file.path} contains an account-specific path');
    }
  });
}

/// The relative-path differences between two directory trees: names present
/// in only one of them, and files whose bytes differ.
List<String> differences(Directory a, Directory b) {
  final filesA = relativeFiles(a);
  final filesB = relativeFiles(b);
  final problems = <String>[];
  for (final path in filesA.keys.where(_isGeneratedPath)) {
    if (!filesB.containsKey(path)) {
      problems.add('only in ${a.path}: $path');
      continue;
    }
    final bytesA = File(filesA[path]!).readAsBytesSync();
    final bytesB = File(filesB[path]!).readAsBytesSync();
    if (!_sameBytes(bytesA, bytesB)) problems.add('bytes differ: $path');
  }
  for (final path in filesB.keys.where(_isGeneratedPath)) {
    if (!filesA.containsKey(path)) problems.add('only in ${b.path}: $path');
  }
  return problems;
}

/// Whether a corpus-relative path belongs to the generated output.
bool _isGeneratedPath(String path) =>
    path == 'BASELINE' || path.startsWith('python_compat/');

/// Maps each file below [root] to its absolute path, keyed by the path
/// relative to [root].
Map<String, String> relativeFiles(Directory root) => {
      for (final entity in root.listSync(recursive: true).whereType<File>())
        entity.path.substring(root.path.length + 1): entity.path,
    };

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
