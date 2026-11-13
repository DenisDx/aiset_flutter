import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'fixtures_io.dart';

/// Repository hygiene: the local-space data leak scan (SEC-02, `SPEC.md`
/// amendment 36) and the author-neutrality scan (LIB-04, `SPEC_.md`
/// amendment 37).
///
/// Both scans walk the directory tree instead of asking git what is tracked,
/// so they run in a checkout with no git at all. [isIgnored] mirrors
/// `.gitignore` for the entries that can appear inside the scanned roots, and no
/// ignored file is opened. It is also why the local endpoint address is never
/// compared against a value read from `.env`: the check takes it from the process
/// environment instead, so the check itself carries no local data.
///
/// The two rules deliberately look at different content:
///
/// * **SEC-02** applies to every scanned file, prose included. A private-range
///   address literal, a local endpoint host, a machine-specific absolute path or
///   a key shape is a leak wherever it appears, documentation included.
/// * **LIB-04** applies to executable content only: the Dart, Python, YAML, JSON,
///   JSON5 and shell files a build, a test or a fixture loader actually
///   reads. Project prose (`*.md`) MAY name the operator-side paths, because
///   naming a path is not depending on it (amendment 37) - the repository has to
///   be able to write down the exclusion policy it follows.
///
/// Every needle is a pattern with a one-element character class around the
/// character that would otherwise complete the literal, so this file does not
/// contain the strings it forbids and is scanned like any other one.
void main() {
  final repo = repositoryRoot();
  final files = scannedFiles(repo);

  group('local-space data leak scan (SEC-02)', () {
    test('the scan reads the repository source content and nothing ignored', () {
      // Guards against a scan that silently reads almost nothing and so
      // "passes" on an empty set.
      expect(files.length, greaterThan(300),
          reason: 'the scan found too few files; is the repository root wrong?');
      final paths = [for (final file in files) relativeTo(repo, file)];
      for (final required in const [
        'SPEC.md',
        'packages/aiset_core/pubspec.yaml',
        'packages/aiset_core/lib/src/json5/parser.dart',
        'packages/aiset_core/test/repository_hygiene_test.dart',
        'tool/generate_corpus.dart',
        'tool/python/corpus_driver.py',
        'fixtures/BASELINE',
        'fixtures/python_compat/operations/set_scalar_multiline.json',
      ]) {
        expect(paths, contains(required), reason: 'the scan must read $required');
      }
      for (final path in paths) {
        expect(isIgnored(path), isFalse,
            reason: 'the scan opened a git-ignored path: $path');
      }
    });

    test('no private address, local endpoint host, machine path or key shape', () {
      final problems = <String>[];
      for (final file in files) {
        final path = relativeTo(repo, file);
        final text = scanText(file);
        for (final (rule, pattern) in _leakRules) {
          final match = pattern.firstMatch(text);
          if (match != null) problems.add('$path: $rule -> ${mask(match.group(0)!)}');
        }
        for (final (rule, value) in _environmentNeedles(repo)) {
          if (text.contains(value)) problems.add('$path: $rule -> ${mask(value)}');
        }
      }
      expect(problems, isEmpty,
          reason: 'local-space data in tracked content:\n${problems.join('\n')}');
    });
  });

  group('author-neutrality scan (LIB-04)', () {
    test('executable content never references operator tooling', () {
      final problems = <String>[];
      for (final file in files) {
        final path = relativeTo(repo, file);
        if (isProse(path)) continue; // Prose states the policy; see the header.
        final text = scanText(file);
        for (final needle in _operatorTooling) {
          final match = needle.pattern.firstMatch(text);
          if (match != null) {
            problems.add('$path: references ${needle.what} -> ${mask(match.group(0)!)}');
          }
        }
      }
      expect(
          problems,
          isEmpty,
          reason: 'executable content would depend on one author\'s tooling, so a '
              "fresh clone could not build or test without it (SPEC_.md 37):\n"
              '${problems.join('\n')}');
    });

    test('the prose/executable split is explicit, not incidental', () {
      // The exemption is a rule about file kinds, so the classifier is checked
      // directly rather than inferred from a scan result.
      expect(isProse('README.md'), isTrue);
      expect(isProse('docs/grammars.md'), isTrue);
      expect(isProse('proposal_stage1_core_cst_corpus.md'), isTrue);
      expect(isProse('packages/aiset_core/lib/aiset_core.dart'), isFalse);
      expect(isProse('tool/python/corpus_driver.py'), isFalse);
      expect(isProse('packages/aiset_core/pubspec.yaml'), isFalse);
      expect(isProse('fixtures/BASELINE'), isFalse);
      expect(isProse('fixtures/preservation/cases/bom.input.json5'), isFalse);
      expect(isProse('tool/build.sh'), isFalse);

      // And the exemption is exercised: the tracked documents do state the
      // exclusion policy by naming the paths it excludes. If that ever stops
      // being true on purpose, this guard is the reminder to revisit the rule.
      final naming = [
        for (final file in files)
          if (isProse(relativeTo(repo, file)) &&
              _operatorTooling.any((needle) => needle.pattern.hasMatch(scanText(file))))
            relativeTo(repo, file),
      ];
      expect(naming, isNotEmpty,
          reason: 'no prose file names an operator path, so the LIB-04 prose '
              'exemption is untested here');
    });
  });
}

// -- needles ---------------------------------------------------------------

/// One forbidden reference to tooling that lives outside the repository.
typedef ToolingNeedle = ({RegExp pattern, String what});

/// The operator-side paths executable content must not depend on
/// (`SPEC_.md` amendment 37). Each is written with a one-element character class
/// so this file does not contain the literal it forbids.
final List<ToolingNeedle> _operatorTooling = [
  for (final (source, what) in const <(String, String)>[
    (r'local[_]tools/', 'the operator-only tools directory'),
    (r'[.]opencode/', 'the local agent configuration directory'),
    (r'memor[y]/', 'the local agent memory directory'),
    (r'AGENT[S][.]md', 'the local agent workflow code'),
  ])
    (pattern: RegExp(source), what: what),
];

/// Content-level leak rules (SEC-02): a reason plus the pattern that finds it.
/// None of them matches its own source in this file.
///
/// Case-insensitivity is a `RegExp` option here rather than an inline `(?i)`
/// group: the Dart engine is ECMAScript-flavoured and rejects inline flags, which
/// is one of the dialect differences recorded in `docs/grammars.md`.
final List<(String, RegExp)> _leakRules = [
  for (final (rule, source, foldCase) in const <(String, String, bool)>[
    (
      'private-range IPv4 literal',
      r'\b(?:10|127)(?:\.\d{1,3}){3}\b|\b192[.]168(?:\.\d{1,3}){2}\b'
          r'|\b172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2}\b'
          r'|\b169[.]254(?:\.\d{1,3}){2}\b',
      false,
    ),
    (
      'machine-specific absolute path',
      r'/(?:home|Users|Volumes|mnt|media|run[/]user|private[/]var[/]folders)/',
      false,
    ),
    ('Windows account path', r'\b[a-z]:[\\]', true),
    ('key or token shape', r'sk[-][A-Za-z0-9]{16,}', false),
    (
      'key or token shape',
      r'gh[pousr][_][A-Za-z0-9]{20,}|github[_]pat[_][A-Za-z0-9_]{20,}',
      false,
    ),
    ('key or token shape', r'xox[baprs][-][A-Za-z0-9-]{10,}', false),
    ('key or token shape', r'AKIA[0-9A-Z]{16}', false),
    ('key or token shape', r'AIza[0-9A-Za-z_\-]{30,}', false),
    ('key or token shape', r'[-]{5}BEGIN [A-Z ]*PRIVATE KEY[-]{5}', false),
    (
      'key or token shape',
      r'''[A]uthorization["']?\s*[:=]\s*["']?\s*[B]earer\s+[A-Za-z0-9._\-]{12,}''',
      true,
    ),
    (
      'key or token shape',
      r'''\b(?:api[_-]?key|access[_-]?token|auth[_-]?token|secret[_-]?key'''
          r'''|client[_-]?secret|password)\b\s*[:=]\s*["'][^"'\n]{7,}["']''',
      true,
    ),
  ])
    (rule, RegExp(source, caseSensitive: !foldCase)),
];

// -- scanning --------------------------------------------------------------

/// The repository root, located without git: the directory that holds
/// `packages/`, `tool/` and the corpus provenance record.
Directory repositoryRoot() {
  var directory = Directory.current;
  for (var depth = 0; depth < 8; depth++) {
    if (Directory(join(directory.path, 'packages')).existsSync() &&
        Directory(join(directory.path, 'tool')).existsSync() &&
        File(join(directory.path, 'fixtures', 'BASELINE')).existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  throw StateError(
    'Repository root not found above ${Directory.current.path}. Expected the '
    'directory containing packages/, tool/ and fixtures/BASELINE.',
  );
}

/// The roots the scans cover: repository source plus the root-level project
/// documentation. `docs/` and `examples/` are scanned when they exist.
const List<String> _scannedDirectories = [
  'packages',
  'tool',
  'fixtures',
  'docs',
  'examples',
];

/// Every scanned file, with git-ignored paths excluded.
List<File> scannedFiles(Directory repo) {
  final files = <File>[];
  for (final name in _scannedDirectories) {
    final directory = Directory(join(repo.path, name));
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File) continue;
      final path = relativeTo(repo, entity);
      if (!isIgnored(path)) files.add(entity);
    }
  }
  for (final entity in repo.listSync()) {
    if (entity is! File || !entity.path.endsWith('.md')) continue;
    final path = relativeTo(repo, entity);
    if (!isIgnored(path)) files.add(entity);
  }
  files.sort((a, b) => relativeTo(repo, a).compareTo(relativeTo(repo, b)));
  return files;
}

/// [file] below [repo] as a repository-relative path with forward slashes.
String relativeTo(Directory repo, File file) =>
    file.path.substring(repo.path.length + 1).replaceAll(r'\', '/');

/// Whether a repository-relative path is excluded from version control.
///
/// Mirrors `.gitignore` for the entries that can appear inside the scanned
/// roots; a scan must never open one of them.
bool isIgnored(String path) {
  final segments = path.split('/');
  final fileName = segments.last;
  for (final segment in segments.take(segments.length - 1)) {
    if (_ignoredDirectories.contains(segment) || segment.startsWith('local_')) {
      return true;
    }
  }
  if (segments.length == 1 && _ignoredRootFiles.contains(fileName)) return true;
  if (_ignoredNames.contains(fileName)) return true;
  if (fileName.startsWith('local_')) return true;
  if (fileName == '.env') return true;
  if (fileName.startsWith('.env.') && fileName != '.env.example') return true;
  for (final suffix in const ['.pyc', '.js.deps', '.js.map', '.dart.js', '.info.json']) {
    if (fileName.endsWith(suffix)) return true;
  }
  // `pubspec.lock` is ignored except the lockfile of a deployable example.
  if (fileName == 'pubspec.lock' &&
      !(segments.length == 3 && segments.first == 'examples')) {
    return true;
  }
  return false;
}

/// Directories that never hold tracked content.
const Set<String> _ignoredDirectories = {
  '.cxx',
  '.dart_tool',
  '.ephemeral',
  '.git',
  '.gradle',
  '.idea',
  '.mypy_cache',
  '.opencode',
  '.pytest_cache',
  '.ruff_cache',
  '.symlinks',
  '.venv',
  '.vscode',
  'DerivedData',
  'Pods',
  'build',
  'coverage',
  'local_tools',
  'memory',
  'node_modules',
  'venv',
  '__pycache__',
};

/// Names ignored at the repository root only. The agent workflow code is
/// composed from two literals so this scanner does not contain the
/// path it forbids and can stay inside its own scan.
const Set<String> _ignoredRootFiles = {'AGENTS' 'S.md'};

/// File names ignored at any depth.
const Set<String> _ignoredNames = {
  '.DS_Store',
  '.flutter-plugins',
  '.flutter-plugins-dependencies',
  '.packages',
  'Thumbs.db',
};

/// Whether a scanned file is prose rather than executable content.
///
/// Prose is Markdown: it may name the operator-side paths in order to state the
/// exclusion policy. Everything else - code, configuration, fixture data,
/// scripts - is content a build or a test reads, and must not name them.
bool isProse(String path) => path.endsWith('.md');

/// The text of [file] for needle matching.
///
/// Decoded as Latin-1 so every byte survives and no binary file can hide a
/// needle: all needles are ASCII, so a mis-decoded multi-byte sequence can
/// neither create nor hide a match.
String scanText(File file) => latin1.decode(file.readAsBytesSync(), allowInvalid: true);

/// A short, non-reproducing rendering of a finding: printing the leaked value in
/// the failure output would be a leak of its own.
String mask(String value) {
  final flat = value.replaceAll('\n', ' ').replaceAll('\r', ' ');
  if (flat.length <= 8) return '"$flat" (${flat.length} chars)';
  return '"${flat.substring(0, 4)}…${flat.substring(flat.length - 2)}" '
      '(${flat.length} chars)';
}

/// The values that identify this machine, read from the process
/// environment rather than from a file, so the check itself stays portable and
/// holds no local data (`SPEC.md` amendment 36).
///
/// A machine with nothing configured simply runs the static rules: the
/// endpoint-host check is only as strong as the operator's environment, which is
/// the intended trade - the alternative would be a hardcoded host in tracked
/// content. The container's own service name is deliberately not a needle:
/// tracked documents name it on purpose, and it reveals no account or address.
List<(String, String)> _environmentNeedles(Directory repo) {
  final environment = Platform.environment;
  final baseUrl = environment['AISET_AI_BASE_URL'] ?? '';
  final host = RegExp(r'https?://([^/:?#]+)').firstMatch(baseUrl)?.group(1) ?? '';
  return [
    ('local endpoint URL', baseUrl),
    ('local endpoint host', host),
    ('reference clone path', environment['AISET_PYTHON_BASELINE'] ?? ''),
    ('home directory', environment['HOME'] ?? ''),
    ('repository path', repo.absolute.path),
  ].where((needle) => needle.$2.length > 3).toList();
}
