/// Compatibility corpus generator (SPEC.md amendment 24).
///
/// Executes the Python behavioral baseline over the catalog in
/// `tool/corpus_cases.dart` plus the committed preservation fixtures, and
/// writes the observed results to `fixtures/python_compat/` and
/// `fixtures/BASELINE`. Expectations are produced by running the baseline,
/// never transcribed by hand.
///
/// The one exception is a registered divergence
/// (`SPEC_.md` amendment 38): where the baseline output is a defect, the case
/// asserts the correction authored in the catalog, and the baseline's observed
/// result is written next to it under `baselineEvidence` as evidence. Such a
/// case is asserted, never skipped.
///
/// Deterministic: the same baseline commit and the same generator sources
/// produce byte-identical fixtures. No timestamp or machine
/// path is written into any tracked file (SPEC.md amendments 36, 37).
///
/// Usage:
///
///     dart run tool/generate_corpus.dart [options]
///
/// Options:
///
///     --baseline <path>   reference clone root; default
///                           $AISET_PYTHON_BASELINE
///     --python <exe>      interpreter; default
///                           <baseline>/.venv/bin/python, else `python3`
///     --out <dir>         output root; default <repo>/fixtures
///     --skip-oracle-check do not run the baseline test suite first
///     --help              show this text
///
/// Exit codes: 0 success, 64 usage error, 70 generation failure,
/// 75 the oracle is unhealthy (its own suite is not green).
library;

import 'dart:convert';
import 'dart:io';

import 'corpus_cases.dart';
import 'descriptor_cases.dart';
import 'merge_cases.dart';
import 'pipeline_cases.dart';
import 'resolver_cases.dart';
import 'validator_cases.dart';

/// Version of this generator, recorded in `fixtures/BASELINE`.
const String generatorVersion = '1.0.0';

/// Generator sources whose content hash identifies the produced corpus.
const List<String> generatorFiles = [
  'tool/generate_corpus.dart',
  'tool/corpus_cases.dart',
  'tool/descriptor_cases.dart',
  'tool/resolver_cases.dart',
  'tool/validator_cases.dart',
  'tool/merge_cases.dart',
  'tool/pipeline_cases.dart',
  'tool/python/corpus_driver.py',
];

const String _schemaVersion = '1';

Future<int> main(List<String> args) async {
  // `dart run` ignores a Future<int> result, so the code is set explicitly.
  final code = await _run(args);
  exitCode = code;
  return code;
}

Future<int> _run(List<String> args) async {
  final cli = _Cli.parse(args);
  if (cli == null) return 64;
  if (cli.help) {
    stdout.write(_usage);
    return 0;
  }
  try {
    return await _Generate(cli).run();
  } on _GenerationFailure catch (e) {
    stderr.writeln('generate_corpus: ${e.message}');
    return e.exitCode;
  } catch (e) {
    stderr.writeln('generate_corpus: unexpected failure: $e');
    return 70;
  }
}

const String _usage = '''
Usage: dart run tool/generate_corpus.dart [options]

  --baseline <path>    reference clone root (default \$AISET_PYTHON_BASELINE)
  --python <exe>       interpreter (default <baseline>/.venv/bin/python,
                       else python3)
  --out <dir>          output root (default <repo>/fixtures)
  --skip-oracle-check  do not run the baseline test suite before generating
  --help               show this text
''';

/// One generated fixture, ready to serialize.
class _Fixture {
  _Fixture({
    required this.area,
    required this.fileName,
    required this.body,
  });

  final String area;
  final String fileName;
  final Map<String, Object?> body;
}

class _Generate {
  _Generate(this.cli);

  final _Cli cli;

  Future<int> run() async {
    final repoRoot = File.fromUri(Platform.script).parent.parent;
    final baseline = _resolveBaseline(repoRoot);
    final python = _resolvePython(baseline);
    final driver = File('${repoRoot.path}/tool/python/corpus_driver.py');
    if (!driver.existsSync()) {
      throw _GenerationFailure('driver not found at ${_neutral(driver.path)}', 70);
    }

    final commit = _git(baseline, ['rev-parse', 'HEAD']);
    final branch = _git(baseline, ['rev-parse', '--abbrev-ref', 'HEAD']);

    final oracle = cli.skipOracleCheck
        ? <String, Object?>{
            'status': 'skipped',
            'reason': '--skip-oracle-check was passed',
          }
        : await _runOracleCheck(python, baseline);

    // Catalog cases plus one parse case per preservation fixture.
    final cases = <CorpusCase>[
      ...corpusCases(),
      ...descriptorCases(),
      ...resolverCases(),
      ...validatorCases(),
      ...mergeCases(),
      ...pipelineCases(),
      ..._preservationCases(repoRoot),
    ];
    _checkUniqueIds(cases);

    final job = <String, Object?>{
      'cases': [for (final c in cases) c.toJobEntry()],
      'hash_files': [for (final f in generatorFiles) '${repoRoot.path}/$f'],
    };
    final stdoutText = await _runProcess(
      python,
      [driver.path],
      workingDirectory: repoRoot.path,
      environment: {
        'PYTHONPATH': '$baseline/src',
        'PYTHONDONTWRITEBYTECODE': '1',
        'HOME': Platform.environment['HOME'] ?? '',
        'PATH': Platform.environment['PATH'] ?? '',
      },
      stdinText: jsonEncode(job),
    );

    final decoded = jsonDecode(stdoutText) as Map<String, Object?>;
    final results = (decoded['results']! as List).cast<Map<String, Object?>>();
    final generatorHash = decoded['generator_sha256']! as String;
    if (results.length != cases.length) {
      throw _GenerationFailure(
          'the driver returned ${results.length} results for ${cases.length} cases', 70);
    }

    final byId = {for (final c in cases) c.id: c};
    final fixtures = <_Fixture>[];
    for (final result in results) {
      final id = result['id']! as String;
      final source = byId[id];
      if (source == null) {
        throw _GenerationFailure('unknown case id from driver: $id', 70);
      }
      final area = result['area']! as String;
      final observed = <String, Object?>{
        for (final entry in result.entries)
          if (entry.key != 'id' && entry.key != 'area') entry.key: entry.value,
      };
      // A registered divergence asserts the corrected behavior and keeps the
      // baseline's observed result as evidence (SPEC_.md amendment 38).
      final divergence = source.divergence;
      Map<String, Object?> expected = observed;
      Map<String, Object?>? baselineEvidence;
      Map<String, Object?>? divergenceBlock;
      if (divergence != null) {
        expected = _correctedExpectation(id, divergence);
        baselineEvidence = observed;
        divergenceBlock = {...divergence}..remove('corrected');
      }
      fixtures.add(_Fixture(
        area: area,
        fileName: '$id.json',
        body: <String, Object?>{
          'schema': _schemaVersion,
          'area': area,
          'id': id,
          'description': source.description,
          'classes': source.classes,
          'input': source.input,
          if (source.query != null) 'query': source.query,
          if (source.operation != null) 'operation': source.operation,
          if (source.payload != null) ...source.payload!,
          if (divergenceBlock != null) 'divergence': divergenceBlock,
          'expected': expected,
          if (baselineEvidence != null) 'baselineEvidence': baselineEvidence,
        },
      ));
    }

    final counts = <String, Object?>{};
    for (final area in _areas) {
      counts[area] = fixtures.where((f) => f.area == area).length;
    }
    counts['total'] = fixtures.length;

    _writeFixtures(repoRoot, fixtures);
    final baselineFile = File('${cli.out.path}/BASELINE');
    baselineFile.writeAsStringSync(_encode(<String, Object?>{
      'schema': _schemaVersion,
      'baseline': {'commit': commit, 'branch': branch},
      'generator': {
        'name': 'tool/generate_corpus.dart',
        'version': generatorVersion,
        'sha256': generatorHash,
      },
      'oracle': oracle,
      'counts': counts,
    }));

    stdout.writeln('generate_corpus: baseline $commit ($branch)');
    stdout.writeln('generate_corpus: oracle $oracle');
    for (final area in _areas) {
      stdout.writeln('generate_corpus: $area ${counts[area]} cases');
    }
    stdout.writeln('generate_corpus: total ${counts['total']} cases');
    stdout.writeln('generate_corpus: wrote ${_neutral(baselineFile.path)}');
    return 0;
  }

  // -- inputs ---------------------------------------------------------------

  String _resolveBaseline(Directory repoRoot) {
    final path = cli.baseline;
    if (path == null || path.isEmpty) {
      throw _GenerationFailure(
        'no reference clone: pass --baseline or set AISET_PYTHON_BASELINE',
        64,
      );
    }
    final dir = Directory(path);
    if (!File('${dir.path}/src/aiset/jsonsrc.py').existsSync()) {
      throw _GenerationFailure(
          'the baseline path does not look like an aiset clone: no src/aiset/jsonsrc.py',
          64);
    }
    return dir.absolute.path;
  }

  String _resolvePython(String baseline) {
    if (cli.python != null && cli.python!.isNotEmpty) return cli.python!;
    final venv = File('$baseline/.venv/bin/python');
    if (venv.existsSync()) return venv.path;
    return 'python3';
  }

  Future<Map<String, Object?>> _runOracleCheck(String python, String baseline) async {
    final out = await _runProcess(
      python,
      ['-m', 'pytest', '-q', '-p', 'no:cacheprovider', 'tests'],
      workingDirectory: baseline,
      environment: {
        'PYTHONPATH': '$baseline/src',
        'PYTHONDONTWRITEBYTECODE': '1',
        'HOME': Platform.environment['HOME'] ?? '',
        'PATH': Platform.environment['PATH'] ?? '',
      },
    );
    final passed = _lastInt(out, RegExp(r'(\d+) passed')) ?? 0;
    final failed = _lastInt(out, RegExp(r'(\d+) failed')) ?? 0;
    final errors = _lastInt(out, RegExp(r'(\d+) error')) ?? 0;
    if (passed == 0 || failed != 0 || errors != 0) {
      throw _GenerationFailure(
        'the baseline suite is not green (passed=$passed failed=$failed errors=$errors); '
        'refusing to derive expectations from an unhealthy oracle',
        75,
      );
    }
    return {'suite': 'tests', 'status': 'checked', 'passed': passed, 'failed': 0};
  }

  /// One parse case per committed preservation fixture.
  List<CorpusCase> _preservationCases(Directory repoRoot) {
    final dir = Directory('${repoRoot.path}/fixtures/preservation');
    final manifestFile = File('${dir.path}/manifest.json');
    if (!manifestFile.existsSync()) {
      throw _GenerationFailure('preservation fixtures not found under ${_neutral(dir.path)}', 70);
    }
    final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
    final entries = (manifest['cases']! as List).cast<Map<String, Object?>>();
    return [
      for (final entry in entries)
        CorpusCase(
          id: entry['id']! as String,
          description: entry['description']! as String,
          classes: (entry['classes']! as List).cast<String>(),
          kind: 'parse',
          input: _readTextUtf8PreservingBom(File('${dir.path}/${entry['input']! as String}')),
        ),
    ];
  }

  // -- outputs --------------------------------------------------------------

  /// The asserted expectation of a divergent case: the correction authored in
  /// `tool/corpus_cases.dart`, marked so that no reader mistakes it for an
  /// observed baseline result. The observed result is kept
  /// alongside it as `baselineEvidence`.
  static Map<String, Object?> _correctedExpectation(
      String id, Map<String, Object?> divergence) {
    for (final key in ['id', 'report', 'note']) {
      if (key != 'corrected' && (divergence[key] is! String || (divergence[key]! as String).isEmpty)) {
        throw _GenerationFailure(
            'the divergence of case $id must carry a non-empty string "$key" '
            '(`SPEC_.md` amendment 38)',
            70);
      }
    }
    final corrected = divergence['corrected'];
    if (corrected is! Map<String, Object?> || corrected.isEmpty) {
      throw _GenerationFailure(
          'the divergence of case $id must carry a non-empty "corrected" expectation',
          70);
    }
    return {...corrected, 'expectation': 'corrected'};
  }

  void _checkUniqueIds(List<CorpusCase> cases) {
    final seen = <String>{};
    for (final c in cases) {
      if (!seen.add(c.id)) {
        throw _GenerationFailure('duplicate case id: ${c.id}', 70);
      }
    }
  }

  void _writeFixtures(Directory repoRoot, List<_Fixture> fixtures) {
    for (final area in _areas) {
      final dir = Directory('${cli.out.path}/python_compat/$area');
      dir.createSync(recursive: true);
      // Drop stale files so a removed case cannot survive a run.
      for (final entity in dir.listSync()) {
        if (entity is File) entity.deleteSync();
      }
    }
    for (final fixture in fixtures) {
      final file = File('${cli.out.path}/python_compat/${fixture.area}/${fixture.fileName}');
      file.writeAsBytesSync(utf8.encode(_encode(fixture.body)));
    }
  }

  /// Serializes [body] deterministically: fixed key order, two-space
  /// indent, LF endings, one trailing newline.
  String _encode(Map<String, Object?> body) =>
      '${const JsonEncoder.withIndent('  ').convert(body)}\n';
}

const List<String> _areas = [
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

// -- process helpers -----------------------------------------------------

Future<String> _runProcess(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  Map<String, String> environment = const {},
  String? stdinText,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: false,
  );
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();
  if (stdinText != null) {
    process.stdin.write(stdinText);
  }
  await process.stdin.close();
  final out = await stdoutFuture;
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    final err = await stderrFuture;
    throw _GenerationFailure(
      '${_neutral(executable)} ${arguments.join(' ')} exited with $exitCode:\n$err',
      70,
    );
  }
  final warnings = await stderrFuture;
  if (warnings.trim().isNotEmpty) stderr.write(warnings);
  return out;
}

String _git(String repo, List<String> args) {
  final result = Process.runSync('git', ['-C', repo, ...args], runInShell: false);
  if (result.exitCode != 0) {
    throw _GenerationFailure('git ${args.join(' ')} failed in the reference clone: ${result.stderr}', 70);
  }
  return (result.stdout as String).trim();
}

int? _lastInt(String text, RegExp pattern) {
  int? found;
  for (final match in pattern.allMatches(text)) {
    found = int.parse(match.group(1)!);
  }
  return found;
}

/// Reads [file] as UTF-8 without dropping a byte-order mark, which is
/// what the baseline's own `encoding='utf-8'` reads keep.
String _readTextUtf8PreservingBom(File file) {
  final bytes = file.readAsBytesSync();
  final decoded = utf8.decode(bytes);
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return '\uFEFF$decoded';
  }
  return decoded;
}

/// Strips machine-specific prefixes from a path before it
/// reaches a log line; tracked output never contains paths at all.
String _neutral(String path) {
  final home = Platform.environment['HOME'];
  if (home != null && home.isNotEmpty && path.startsWith(home)) {
    return '~${path.substring(home.length)}';
  }
  return path;
}

/// Parsed command line.
class _Cli {
  _Cli._({
    required this.baseline,
    required this.python,
    required this.out,
    required this.skipOracleCheck,
    required this.help,
  });

  final String? baseline;
  final String? python;
  final Directory out;
  final bool skipOracleCheck;
  final bool help;

  static _Cli? parse(List<String> args) {
    String? baseline;
    String? python;
    String? out;
    var skipOracleCheck = false;
    var help = false;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String? value() {
        if (i + 1 >= args.length) {
          stderr.writeln('generate_corpus: $arg needs a value');
          return null;
        }
        return args[++i];
      }

      switch (arg) {
        case '--baseline':
          baseline = value();
          if (baseline == null) return null;
        case '--python':
          python = value();
          if (python == null) return null;
        case '--out':
          out = value();
          if (out == null) return null;
        case '--skip-oracle-check':
          skipOracleCheck = true;
        case '--help':
        case '-h':
          help = true;
        default:
          stderr.writeln('generate_corpus: unknown option $arg');
          return null;
      }
    }
    if (help) {
      return _Cli._(
          baseline: baseline,
          python: python,
          out: Directory('.'),
          skipOracleCheck: skipOracleCheck,
          help: true);
    }
    baseline ??= Platform.environment['AISET_PYTHON_BASELINE'];
    final repoRoot = File.fromUri(Platform.script).parent.parent;
    final outDir = Directory(out ?? '${repoRoot.path}/fixtures');
    return _Cli._(
      baseline: baseline,
      python: python,
      out: outDir,
      skipOracleCheck: skipOracleCheck,
      help: false,
    );
  }
}

class _GenerationFailure implements Exception {
  _GenerationFailure(this.message, this.exitCode);

  final String message;
  final int exitCode;
}
