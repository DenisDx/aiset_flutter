/// Shared helpers for the native-file adapter tests.
///
/// Every test runs against a real temporary directory from the
/// platform (`Directory.systemTemp`), never a literal home path, and
/// never invokes Python: the baseline facts the expectations encode
/// were verified by execution during slice 2E-a (commands and outputs
/// in the slice report) and are baked in as plain expectations
/// (`SPEC_.md` amendment 37: the package builds and tests on a
/// plain checkout with no reference clone and no
/// `AISET_PYTHON_BASELINE`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aiset_core/aiset_core.dart';
import 'package:aiset_storage_io/aiset_storage_io.dart';

/// The minimal descriptor the pipeline-integration tests register:
/// one integer `/a` (a `reload` change) and a string `/name` (a
/// `live` change).
const String testDescriptorSource = '''
{ descriptor_version: "1.0", project: "storage-io", config_version: "1",
  root: {
    type: "object",
    children: {
      // The integer the tests edit.
      a: { type: "int", minimum: 0, maximum: 100, apply: "reload" },
      name: { type: "string", apply: "live" },
    },
  },
}
''';

/// The adapter under test, rooted at `cfg.json5` inside [dir].
AisetNativeFileStorage storageIn(
  Directory dir, {
  String name = 'cfg.json5',
  AisetNativeFileSettings settings = const AisetNativeFileSettings(),
  void Function(String event, Map<String, Object?> payload)? onAudit,
}) =>
    AisetNativeFileStorage('${dir.path}/$name', settings: settings, onAudit: onAudit);

/// Runs one async body inside a fresh temp directory and deletes
/// the directory afterwards, even on failure. Returns the
/// future so a test can be `() => run((dir) async { … })`.
Future<void> run(Future<void> Function(Directory dir) body) async {
  final dir = Directory.systemTemp.createTempSync('aiset_io_test');
  try {
    await body(dir);
  } finally {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

/// Sets POSIX file mode bits (dart:io has no permission API;
/// the tests shell out to `chmod` the way
/// any host script would). Only meaningful on POSIX;
/// callers guard with [Platform.isWindows].
void chmod(String path, String octalMode) {
  final result = Process.runSync('chmod', [octalMode, path]);
  if (result.exitCode != 0) {
    throw StateError('chmod $octalMode $path failed: ${result.stderr}');
  }
}

/// The revision of raw [bytes], spelled once for the tests.
String revisionOfBytes(List<int> bytes) =>
    sourceRevisionOfBytes(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));

/// The revision of the file as it is on disk now.
String currentRevision(Directory dir, [String name = 'cfg.json5']) =>
    revisionOfBytes(File('${dir.path}/$name').readAsBytesSync());

/// The raw bytes of [text], UTF-8, no implicit encoding.
Uint8List utf8Bytes(String text) => Uint8List.fromList(utf8.encode(text));

/// The error a future throws, or `null` when it completes.
Future<Object?> captureError(Future<Object?> future) =>
    future.then<Object?>((_) => null, onError: (Object e) => e);

/// A byte list as a `Uint8List` for comparisons.
Uint8List bytesOf(List<int> bytes) =>
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

/// The `dart` executable running these tests — the same VM the
/// spawned race worker processes use.
final String dartExecutable = Platform.resolvedExecutable;

/// The absolute path of the race worker script. `dart test` runs with
/// the package root as the working directory; the VM resolves the
/// spawned script's package config by walking up from the script, so
/// the worker sees both `aiset_core` and `aiset_storage_io`.
final String workerScript = File('test/race_worker.dart').absolute.uri.toFilePath();

/// The names inside [dir], sorted.
List<String> fileNames(Directory dir) =>
    dir.listSync().map((e) => _basename(e.path)).toList()..sort();

String _basename(String path) {
  final cut = path.lastIndexOf('/');
  return cut < 0 ? path : path.substring(cut + 1);
}

/// A live worker process whose stdout is buffered eagerly, so a
/// test can read lines one at a time without
/// cancelling the stream subscription.
final class LiveWorker {
  /// Starts [workerScript] with [args] and begins collecting its
  /// stdout lines.
  LiveWorker._(this._process) {
    _stdout = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty)
        .listen(_lines.add, onDone: () => _done.complete());
    _process.stderr.transform(utf8.decoder).join().then((value) => _stderr = value);
  }

  /// Starts a worker process.
  static Future<LiveWorker> start(List<String> args) async =>
      LiveWorker._(await Process.start(dartExecutable, [workerScript, ...args]));

  final Process _process;
  late final StreamSubscription<String> _stdout;
  final List<String> _lines = <String>[];
  final Completer<void> _done = Completer<void>();
  String _stderr = '';
  int _cursor = 0;

  /// The next stdout line not yet consumed, waiting for it to
  /// arrive.
  Future<String> nextLine({Duration timeout = const Duration(seconds: 60)}) async {
    final deadline = DateTime.now().add(timeout);
    while (_cursor >= _lines.length) {
      if (_done.isCompleted) {
        throw StateError('worker exited; stderr: $_stderr');
      }
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('no line within ${timeout.inSeconds}s; have $_lines');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return _lines[_cursor++];
  }

  /// Waits for the process to exit and returns all
  /// remaining lines plus the stderr text.
  Future<({List<String> lines, int exitCode, String stderr})> finish() async {
    final code = await _process.exitCode;
    await _done.future;
    await _stdout.cancel();
    return (lines: List<String>.unmodifiable(_lines), exitCode: code, stderr: _stderr);
  }

  /// The lines collected so far.
  List<String> get seen => List<String>.unmodifiable(_lines);

  /// The captured stderr so far.
  String get stderr => _stderr;
}

/// The result of one race worker.
final class RaceOutcome {
  /// Creates an outcome.
  const RaceOutcome(this.name, this.readRevision, this.status, this.exitCode);

  /// The worker's label.
  final String name;

  /// The revision the worker read BEFORE the release.
  final String readRevision;

  /// The CAS status it reported, or a marker when it died.
  final String status;

  /// The process exit code.
  final int exitCode;

  @override
  String toString() => '$name: read $readRevision -> $status (exit $exitCode)';
}

/// The two-process race: spawns a worker per entry of [candidates],
/// waits until EVERY worker has announced the revision it read,
/// touches [gateFile] to release them together, and returns each
/// worker's outcome.
///
/// The handshake makes the proof deterministic rather than
/// timing-dependent: all workers provably hold the same read revision
/// before any of them writes, so two `committed` answers would be the
/// lock failing, not the schedule.
Future<List<RaceOutcome>> raceWorkers(
  Directory dir,
  Map<String, String> candidates, {
  required String gateFile,
}) async {
  final gate = File(gateFile);
  if (gate.existsSync()) gate.deleteSync();
  final workers = <String, LiveWorker>{};
  for (final entry in candidates.entries) {
    workers[entry.key] = await LiveWorker.start([
      'race',
      dir.path,
      entry.key,
      entry.value,
      gateFile,
    ]);
  }
  // Collect the READY line of every worker: each carries the
  // worker's label and the revision it read.
  final reads = <String, String>{};
  for (final entry in workers.entries) {
    final ready = await entry.value.nextLine();
    final parts = ready.split(' ');
    if (parts.length < 3 || parts.first != 'READY') {
      throw StateError('worker ${entry.key} announced "$ready"; '
          'expected READY <name> <revision>. stderr: ${entry.value.stderr}');
    }
    reads[parts[1]] = parts[2];
  }
  gate.createSync();
  final outcomes = <RaceOutcome>[];
  for (final entry in workers.entries) {
    final result = await entry.value.finish();
    var status = '<no result>';
    for (final line in result.lines) {
      if (line.startsWith('RESULT ')) status = line.split(' ')[2];
    }
    outcomes.add(RaceOutcome(
      entry.key,
      reads[entry.key] ?? '<missing>',
      status,
      result.exitCode,
    ));
  }
  return outcomes;
}
