import 'dart:io';

import 'package:aiset_core/aiset_core.dart';
import 'package:aiset_storage_io/aiset_storage_io.dart';
import 'package:test/test.dart';

import 'test_utils/helpers.dart';

/// The sidecar lock's behavior under contention, pinned
/// against the executed baseline discipline (`store.py:_FileLock`:
/// `O_CREAT | O_RDWR` on the sidecar,
/// `LOCK_EX | LOCK_NB` retried until
/// `lock_timeout_seconds`, then `LockTimeout`)
/// and the executed `dart:io` facts of this SDK:
///
/// * the OS lock EXCLUDES between processes (probe: a parent
///   opening the sidecar while a child holds it is refused);
/// * it does NOT exclude between isolates of one
///   process, and closing any duplicate descriptor drops
///   the process's locks — which is why this file's
///   adapter serializes its own isolate with a queue and the
///   declared `crossContextConcurrency` stays false.
/// * a contention that outlives the timeout
///   answers the stable `LOCK_TIMEOUT` code, not
///   a raw exception and not a busy-wait past the bound.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('aiset_io_lock');
    file = File('${dir.path}/cfg.json5')..writeAsStringSync('{ a: 1 }');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('a foreign OS lock on the sidecar blocks the write and times out '
      'with LOCK_TIMEOUT', () async {
    // Hold the real cross-process lock from a separate
    // process (the `hold` mode of the race worker), then
    // attempt a CAS with a short timeout.
    final gate = '${dir.path}/hold-gate';
    final holder = await LiveWorker.start(['hold', dir.path, '600', gate]);
    expect(await holder.nextLine(), 'HELD');
    try {
      final impatient = storageIn(dir,
          settings: const AisetNativeFileSettings(lockTimeout: Duration(milliseconds: 120)));
      final stored = await impatient.read();
      final failure = await captureError(impatient
          .compareAndSwap(expectedRevision: stored.revision, sourceText: '{ a: 2 }'));
      expect(failure, isA<AisetFailure>());
      expect((failure! as AisetFailure).code, AisetErrorCode.lockTimeout);
      expect(file.readAsStringSync(), '{ a: 1 }', reason: 'a timed-out write wrote nothing');
    } finally {
      File(gate).createSync();
      await holder.finish();
    }
  });

  test('a waiting writer proceeds after the holder releases, within the '
      'timeout', () async {
    final gate = '${dir.path}/hold-gate2';
    final holder = await LiveWorker.start(['hold', dir.path, '250', gate]);
    expect(await holder.nextLine(), 'HELD');
    // Generous timeout: the retry loop must wait for the
    // release rather than give up early.
    final patient = storageIn(dir,
        settings: const AisetNativeFileSettings(lockTimeout: Duration(seconds: 4)));
    final stored = await patient.read(); // reads need no lock, like the baseline
    final result =
        await patient.compareAndSwap(expectedRevision: stored.revision, sourceText: '{ a: 3 }');
    expect(result.status, AisetCommitStatus.committed);
    expect(file.readAsStringSync(), '{ a: 3 }');
    File(gate).createSync();
    await holder.finish();
  });

  test('the sidecar is created once, never deleted', () async {
    final storage = storageIn(dir);
    final stored = await storage.read();
    await storage.compareAndSwap(expectedRevision: stored.revision, sourceText: '{ a: 4 }');
    final sidecar = File('${dir.path}/cfg.json5.lock');
    expect(sidecar.existsSync(), isTrue);
    // The sidecar name matches the baseline discipline <file>.lock.
    expect(fileNames(dir), contains('cfg.json5.lock'));
    // A second commit still finds it.
    final again = await storage.compareAndSwap(
        expectedRevision: revisionOfBytes(utf8Bytes('{ a: 4 }')), sourceText: '{ a: 5 }');
    expect(again.status, AisetCommitStatus.committed);
    expect(sidecar.existsSync(), isTrue);
  });

  test('two independent adapter instances in one isolate serialize on '
      'the same sidecar', () async {
    // The in-process queue: two adapter objects for
    // the same path (two registrations of one file in a
    // test host) must not interleave their critical
    // sections. Without the queue, the OS lock would let
    // them run at once (probed fact: same-process fds do not
    // exclude), so both would see the same
    // revision and both could commit — a lost update.
    final a = storageIn(dir);
    final b = storageIn(dir);
    final stored = await a.read();
    final results = await Future.wait([
      a.compareAndSwap(expectedRevision: stored.revision, sourceText: '{ a: 10 } // A'),
      b.compareAndSwap(expectedRevision: stored.revision, sourceText: '{ a: 20 } // B'),
    ]);
    final statuses = results.map((r) => r.status).toList();
    expect(statuses.where((s) => s == AisetCommitStatus.committed), hasLength(1),
        reason: 'exactly one wins per revision: $statuses');
    expect(statuses.where((s) => s == AisetCommitStatus.revisionConflict), hasLength(1),
        reason: 'the other is refused: $statuses');
    expect(['{ a: 10 } // A', '{ a: 20 } // B'], contains(file.readAsStringSync()));
  });

  test('a lock file that cannot even be opened is STORAGE_ERROR, '
      'never LOCK_TIMEOUT', () async {
    // Occupy the sidecar NAME with a directory: opening it is a
    // storage problem, not contention, and the honest code
    // is STORAGE_ERROR (`SPEC.md` amendment 26:
    // LOCK_TIMEOUT is for a lock that could not be taken
    // within its bound).
    final storage = storageIn(dir, name: 'blocked.json5');
    File('${dir.path}/cfg.json5').writeAsStringSync('{ a: 1 }'); // the document exists
    Directory('${dir.path}/blocked.json5').createSync();
    Directory('${dir.path}/blocked.json5.lock').createSync();
    final failure = await captureError(
        storage.compareAndSwap(expectedRevision: 'sha256:${'0' * 32}', sourceText: 'x'));
    expect((failure! as AisetFailure).code, AisetErrorCode.storageError);
  });

  // Kept in this file because both cases are about the
  // adapter's answer when the FILESYSTEM refuses it.
  group('write refusals', () {
    late Directory wdir;
    late File doc;

    setUp(() {
      wdir = Directory.systemTemp.createTempSync('aiset_io_refuse');
      doc = File('${wdir.path}/cfg.json5')..writeAsStringSync('{ a: 1 }');
    });

    tearDown(() {
      if (wdir.existsSync()) {
        chmod(wdir.path, '755');
        wdir.deleteSync(recursive: true);
      }
    });

    test('a lock file that cannot even be created is a storage error', () async {
      if (Platform.isWindows) return; // POSIX modes; the class is the point.
      chmod(wdir.path, '555'); // r-x: reads work, creating the sidecar does not
      final storage = storageIn(wdir);
      final failure = await captureError(
          storage.compareAndSwap(expectedRevision: currentRevision(wdir), sourceText: '{ a: 2 }'));
      expect(failure, isA<AisetFailure>());
      expect((failure! as AisetFailure).code, AisetErrorCode.storageError,
          reason: 'a store that cannot even be reached is a STORAGE_ERROR throw, '
              'like a failed read — not a four-way write outcome');
      expect(doc.readAsStringSync(), '{ a: 1 }');
    });

    test('a refused replace answers rejected with zero retries burned', () async {
      if (Platform.isWindows) return;
      final audits = <String>[];
      // One shared adapter: its rotation arm is spent by the
      // first commit, so the refused second CAS goes
      // straight to the replace. (A fresh adapter would
      // re-arm and try to write `.back` first — also refused
      // once the directory is read-only — which is correct but
      // a different path.)
      final storage = storageIn(wdir, onAudit: (name, _) => audits.add(name));
      final stored = await storage.read();
      final first =
          await storage.compareAndSwap(expectedRevision: stored.revision, sourceText: '{ a: 2 }');
      expect(first.status, AisetCommitStatus.committed);
      chmod(wdir.path, '555'); // now creating the temp file is refused
      final result =
          await storage.compareAndSwap(expectedRevision: first.revision!, sourceText: '{ a: 3 }');
      expect(result.status, AisetCommitStatus.rejected,
          reason: 'EACCES proves nothing landed at the target: a refusal, '
              'not uncertainty');
      expect(result.detail, contains('Permission denied'));
      expect(audits, isEmpty,
          reason: 'a proven refusal stops immediately; it does not burn the '
              'retry budget (write_retry would appear per retried attempt)');
      expect(doc.readAsStringSync(), '{ a: 2 }');
      expect(fileNames(wdir).where((n) => n.endsWith('.tmp')), isEmpty,
          reason: 'no temp debris behind the refusal');
    });
  });
}
