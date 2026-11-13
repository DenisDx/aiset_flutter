/// Out-of-process race worker for the CAS proof
/// (`test/compare_and_swap_test.dart`). NOT a test file —
/// the test spawns it with the same `dart` VM as a real
/// SECOND PROCESS against the same document file. It imports
/// the adapter as a package, exactly as a host application would,
/// which is the point: the lock and the CAS must hold between two
/// independent programs.
///
/// Modes:
///
/// * `race <dir> <name> <candidate> <gateFile>` — read the current
///   revision, announce `READY <name> <revision>`, wait until
///   [gateFile] exists, then fire one CAS with the revision read
///   BEFORE the gate. Two workers on one gate race their
///   check-and-replace as closely as the OS allows, and the
///   handshake removes any timing luck: both workers have
///   provably read the same revision before either writes.
/// * `watch <dir> <finalCandidate>` — re-read `<dir>/cfg.json5`
///   until it holds [finalCandidate] byte-exactly. After every read
///   the content must be a whole document of the agreed family
///   (`SEED`, or a run of `x` at least 1000 long); any other shape —
///   a prefix, a suffix, a mix, undecodable bytes — is a torn write
///   and is reported. Announces `READY` once the seed has been
///   observed, so the writer starts while the reader is live.
/// * `hold <dir> <holdMs> <gateFile>` — take the RAW OS lock on
///   `<dir>/cfg.json5.lock` the way the adapter does (`dart:io`
///   exclusive lock on the sidecar), announce `HELD`, and
///   hold it until [gateFile] appears or 30 s pass, then
///   release. This is a foreign PROCESS holding the lock: it proves
///   both that the adapter's lock excludes across
///   processes and that the adapter's timeout path
///   answers `LOCK_TIMEOUT` rather than writing anyway.
library;

import 'dart:io';

import 'package:aiset_storage_io/aiset_storage_io.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: race_worker.dart <race|watch|hold> ...');
    exitCode = 64;
    return;
  }
  switch (args.first) {
    case 'race':
      await _race(args[1], args[2], args[3], args[4]);
    case 'watch':
      await _watch(args[1], args[2]);
    case 'hold':
      await _hold(args[1], int.parse(args[2]), args[3]);
    default:
      stderr.writeln('unknown mode: ${args.first}');
      exitCode = 64;
  }
}

Future<void> _race(String dir, String name, String candidate, String gateFile) async {
  final storage = AisetNativeFileStorage('$dir/cfg.json5');
  final stored = await storage.read();
  stdout.writeln('READY $name ${stored.revision}');
  await stdout.flush();
  // Wait for the release: both workers are then inside
  // the same microsecond of their CAS call.
  final gate = File(gateFile);
  while (!gate.existsSync()) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  final result = await storage.compareAndSwap(
    expectedRevision: stored.revision,
    sourceText: candidate,
  );
  stdout.writeln('RESULT $name ${result.status.name}');
  await stdout.flush();
}

Future<void> _watch(String dir, String finalCandidate) async {
  final file = File('$dir/cfg.json5');
  var reads = 0;
  var ready = false;
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (true) {
    if (DateTime.now().isAfter(deadline)) {
      stdout.writeln('TIMEOUT $reads');
      await stdout.flush();
      return;
    }
    String text;
    try {
      text = file.readAsStringSync();
    } on FileSystemException {
      continue; // the file exists for every moment of this
      // protocol; a transient open race is not a content problem.
    } on FormatException {
      stdout.writeln('TORN undecodable-bytes');
      await stdout.flush();
      return;
    }
    reads++;
    if (text == finalCandidate) {
      stdout.writeln('DONE $reads');
      await stdout.flush();
      return;
    }
    // The document family: the seed marker or one run of 'x'.
    // Anything else can only come from a non-atomic replace.
    final whole = text == 'SEED' ||
        (text.length >= 1000 && text.codeUnits.every((unit) => unit == 0x78 /* 'x' */));
    if (!whole) {
      stdout.writeln('TORN $text');
      await stdout.flush();
      return;
    }
    if (!ready) {
      ready = true;
      stdout.writeln('READY');
      await stdout.flush();
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// A foreign process holding the adapter's own sidecar lock,
/// so the test exercises the real contention the
/// CAS path sees. [holdMs] is a floor; the lock is also
/// released early when [gateFile] appears, whichever is first,
/// with a 30 s ceiling.
Future<void> _hold(String dir, int holdMs, String gateFile) async {
  final lock = AisetSidecarLock('$dir/cfg.json5.lock', timeout: const Duration(seconds: 20));
  final gate = File(gateFile);
  final started = DateTime.now().millisecondsSinceEpoch;
  await lock.hold(() async {
    stdout.writeln('HELD');
    await stdout.flush();
    // Hold at least [holdMs], and release early once the test
    // touches the gate. The ceiling keeps a stuck test
    // from deadlocking the suite.
    final ceiling = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().millisecondsSinceEpoch < started + holdMs && !gate.existsSync()) {
      if (DateTime.now().isAfter(ceiling)) break;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  });
}
