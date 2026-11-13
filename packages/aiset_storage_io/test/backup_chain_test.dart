import 'dart:io';

import 'package:aiset_core/aiset_core.dart';
import 'package:aiset_storage_io/aiset_storage_io.dart';
import 'package:test/test.dart';

import 'test_utils/helpers.dart';

/// The `.back` chain of `SPEC.md` amendment 11: rotation at the
/// default depth of five, once per editing session, the baseline
/// naming discipline, the newest-valid backup rule, rollback,
/// retention, and the PENDING-A42 divergences — each pinned against
/// facts verified by executing the reference clone during slice 2E-a
/// (commands and outputs in the slice report; nothing here invokes
/// Python).
///
/// Executed baseline facts baked in:
///
/// * `Settings()` defaults: backup_depth=5, conflicted_retention=5.
/// * `backup_path(3)` == `<name>.back.back.back`; the chain is
///   level 1 newest first.
/// * After eight session-writes `v1..v8` the chain holds
///   {1: v7, 2: v6, 3: v5, 4: v4, 5: v3}, the current file is v8, and
///   no sixth slot exists.
/// * One session, three writes: level 1 holds the session-start bytes
///   and level 2 does not exist (`backup_done` semantics; a new Store
///   is a new session).
/// * Conflicted name:
///   `<name>.conflicted.<UTC %Y%m%dT%H%M%S.%fZ>.back`, pruned to the
///   five newest by NAME SORT.
/// * Restore: the consumed slot vanishes and deeper slots
///   shift up (cur v4, chain [v3, v2, v1] → restore(1) →
///   cur v3, chain [v2, v1], no level 3).
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('aiset_io_backup');
    file = File('${dir.path}/cfg.json5')..createSync();
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// A fresh adapter is a fresh editing session (the baseline's fresh
  /// `Store` object, `backup_done = False`).
  AisetNativeFileStorage fresh() => storageIn(dir);

  /// One simulated editing session: a new adapter, one CAS commit.
  Future<void> sessionWrite(String text) async {
    final storage = fresh();
    final stored = await storage.read();
    final result =
        await storage.compareAndSwap(expectedRevision: stored.revision, sourceText: text);
    expect(result.status, AisetCommitStatus.committed, reason: text);
  }

  group('naming and rotation order', () {
    test('the chain names repeat .back per level', () async {
      file.writeAsStringSync('v0');
      for (var session = 1; session <= 3; session++) {
        await sessionWrite('v$session');
      }
      expect(File('${dir.path}/cfg.json5.back').existsSync(), isTrue);
      expect(File('${dir.path}/cfg.json5.back.back').existsSync(), isTrue);
      expect(File('${dir.path}/cfg.json5.back.back.back').existsSync(), isTrue);
      expect(File('${dir.path}/cfg.json5.back.back.back.back').existsSync(), isFalse);
    });

    test('depth 5 after eight sessions: chain v7..v3, file v8, no sixth slot', () async {
      // The exact executed-baseline matrix.
      file.writeAsStringSync('v1');
      for (var i = 2; i <= 8; i++) {
        await sessionWrite('v$i');
      }
      final chain = fresh().backupChain();
      expect(chain.map((e) => e.level), [1, 2, 3, 4, 5], reason: 'depth 5 default, newest first');
      expect([for (final e in chain) String.fromCharCodes(e.bytes)], ['v7', 'v6', 'v5', 'v4', 'v3']);
      expect(file.readAsStringSync(), 'v8');
      expect(File('${dir.path}/cfg.json5.back.back.back.back.back.back').existsSync(), isFalse,
          reason: 'no sixth slot at depth 5');
    });

    test('one session rotates once; three CAS writes fill one slot', () async {
      file.writeAsStringSync('a: 1');
      final storage = fresh();
      var revision = (await storage.read()).revision;
      for (final text in ['a: 2', 'a: 3']) {
        final result =
            await storage.compareAndSwap(expectedRevision: revision, sourceText: text);
        expect(result.status, AisetCommitStatus.committed);
        revision = result.revision!;
      }
      final chain = storage.backupChain();
      expect(chain, hasLength(1));
      expect(String.fromCharCodes(chain.single.bytes), 'a: 1',
          reason: 'the slot holds the session-start bytes (baseline: back1=b"a: 1")');

      // A reload — beginEditingSession — re-arms the rotation.
      storage.beginEditingSession();
      final result = await storage.compareAndSwap(expectedRevision: revision, sourceText: 'a: 4');
      expect(result.status, AisetCommitStatus.committed);
      expect(storage.backupChain().map((e) => String.fromCharCodes(e.bytes)), ['a: 3', 'a: 1'],
          reason: 'the second session shifts the chain down');
    });

    test('a refused CAS never rotates', () async {
      file.writeAsStringSync('a: 1');
      final result = await fresh().compareAndSwap(
          expectedRevision: 'sha256:${'f' * 32}', sourceText: 'a: 2');
      expect(result.status, AisetCommitStatus.revisionConflict);
      expect(fresh().backupChain(), isEmpty, reason: 'no write, no rotation');
    });

    test('depth 0 disables the chain and the backup/LKG promises', () async {
      file.writeAsStringSync('a: 1');
      final storage =
          storageIn(dir, settings: const AisetNativeFileSettings(backupDepth: 0));
      expect(storage.capabilities.backup, isFalse);
      expect(storage.capabilities.loadLkg, isFalse);
      final stored = await storage.read();
      final result =
          await storage.compareAndSwap(expectedRevision: stored.revision, sourceText: 'a: 2');
      expect(result.status, AisetCommitStatus.committed);
      expect(File('${dir.path}/cfg.json5.back').existsSync(), isFalse);
    });
  });

  group('LKG read-back', () {
    test('the newest valid slot answers; an invalid slot is skipped', () async {
      // The executed baseline rule (`_newest_valid_backup`): walk
      // newest first, SKIP an invalid slot, take the first good
      // one — and never touch the current file.
      file.writeAsStringSync('{ a: <<broken current');
      File('${dir.path}/cfg.json5.back').writeAsStringSync('{ a: <<broken slot');
      File('${dir.path}/cfg.json5.back.back').writeAsStringSync('{ a: 7 }');
      final lkg = await fresh().loadLkg();
      expect(lkg.loadedFrom, 'lkg');
      expect(lkg.sourceText, '{ a: 7 }');
      expect(lkg.revision, revisionOfBytes(utf8Bytes('{ a: 7 }')));
      expect(lkg.metadata['backupLevel'], 2);
      expect(file.readAsStringSync(), '{ a: <<broken current',
          reason: 'the fallback reads the chain; the current file stays untouched');
    });

    test('the host validity check demotes a slot that parses but violates', () async {
      file.writeAsStringSync('broken');
      File('${dir.path}/cfg.json5.back').writeAsStringSync('{ a: 500 }');
      File('${dir.path}/cfg.json5.back.back').writeAsStringSync('{ a: 7 }');
      final descriptor = compileDescriptor(testDescriptorSource);
      final lkg = await fresh().loadLkg(isValid: (text) {
        final value = Json5Document(text, origin: 'check').storedValue();
        return validateDocument(value, descriptor.root).valid;
      });
      expect(lkg.sourceText, '{ a: 7 }', reason: '500 exceeds the descriptor maximum');
      expect(lkg.metadata['backupLevel'], 2);
    });

    test('a throwing validity check marks the slot invalid, never crashes', () async {
      file.writeAsStringSync('broken');
      File('${dir.path}/cfg.json5.back').writeAsStringSync('{ a: 1 }');
      await expectLater(
        fresh().loadLkg(isValid: (_) => throw StateError('validator down')),
        throwsA(isA<AisetFailure>()
            .having((f) => f.code, 'code', AisetErrorCode.noValidBackup)),
        reason: 'a check that cannot answer has validated nothing',
      );
    });

    test('no chain at all is NO_VALID_BACKUP, not an empty success', () async {
      file.writeAsStringSync('{ a: 1 }');
      await expectLater(
        fresh().loadLkg(),
        throwsA(isA<AisetFailure>()
            .having((f) => f.code, 'code', AisetErrorCode.noValidBackup)),
      );
    });

    test('a slot with undecodable bytes is skipped (PENDING-A42c divergence)', () async {
      // The baseline's `_newest_valid_backup` decodes every slot,
      // so ONE slot of invalid UTF-8 crashes the whole LKG read with
      // `UnicodeDecodeError`. Here that slot simply is not valid
      // and the walk continues (`SPEC_.md` amendment 38).
      file.writeAsStringSync('broken');
      File('${dir.path}/cfg.json5.back').writeAsBytesSync([0xFF, 0xFE, 0x00, 0x80]);
      File('${dir.path}/cfg.json5.back.back').writeAsStringSync('{ a: 7 }');
      final lkg = await fresh().loadLkg();
      expect(lkg.sourceText, '{ a: 7 }');
      expect(lkg.metadata['backupLevel'], 2);
    });
  });

  group('rollback', () {
    test('restore(1) consumes the slot and shifts the chain up', () async {
      // The executed baseline matrix.
      file.writeAsStringSync('v1');
      for (var i = 2; i <= 4; i++) {
        await sessionWrite('v$i');
      }
      final storage = fresh();
      expect(storage.backupChain().map((e) => String.fromCharCodes(e.bytes)), ['v3', 'v2', 'v1']);

      final restored = await storage.restoreBackup(1, expectedRevision: currentRevision(dir));
      expect(restored.sourceText, 'v3');
      expect(restored.loadedFrom, 'file');
      expect(restored.metadata['restoredFrom'], 1);
      expect(file.readAsStringSync(), 'v3');
      expect(storage.backupChain().map((e) => String.fromCharCodes(e.bytes)), ['v2', 'v1']);
      expect(File('${dir.path}/cfg.json5.back.back.back').existsSync(), isFalse);
    });

    test('a rollback does not start a new editing session', () async {
      file.writeAsStringSync('v1');
      await sessionWrite('v2');
      final storage = fresh();
      await storage.restoreBackup(1, expectedRevision: currentRevision(dir));
      expect(storage.backupChain(), isEmpty,
          reason: 'the restored bytes must not re-fill the slot they consumed');
    });

    test('a stale restore expectation conflicts with the file untouched', () async {
      file.writeAsStringSync('v1');
      await sessionWrite('v2');
      final storage = fresh();
      file.writeAsStringSync('foreign');
      await expectLater(
        storage.restoreBackup(1, expectedRevision: revisionOfBytes(utf8Bytes('v2'))),
        throwsA(isA<AisetFailure>()
            .having((f) => f.code, 'code', AisetErrorCode.revisionConflict)),
      );
      expect(file.readAsStringSync(), 'foreign', reason: 'a refused restore writes nothing');
      expect(storage.backupChain().map((e) => String.fromCharCodes(e.bytes)), ['v1'],
          reason: 'and consumes no slot');
    });

    test('restoring an absent slot says NO_VALID_BACKUP', () async {
      file.writeAsStringSync('v1');
      await expectLater(
        fresh().restoreBackup(1),
        throwsA(isA<AisetFailure>()
            .having((f) => f.code, 'code', AisetErrorCode.noValidBackup)),
      );
    });

    test('a level outside the chain is BAD_REQUEST', () async {
      file.writeAsStringSync('v1');
      final storage = fresh();
      await expectLater(
        storage.readBackup(0),
        throwsA(
            isA<AisetFailure>().having((f) => f.code, 'code', AisetErrorCode.badRequest)),
      );
      await expectLater(
        storage.restoreBackup(6),
        throwsA(
            isA<AisetFailure>().having((f) => f.code, 'code', AisetErrorCode.badRequest)),
      );
    });
  });

  group('conflicted copies', () {
    test('preserveRejectedBytes keeps the current bytes with the baseline name', () async {
      file.writeAsStringSync('{ a: <<rejected');
      final name = await fresh().preserveRejectedBytes();
      expect(
        name,
        matches(RegExp(r'^cfg\.json5\.conflicted\.\d{8}T\d{6}\.\d{6}Z\.back$')),
        reason: '<name>.conflicted.<UTC %Y%m%dT%H%M%S.%fZ>.back (executed from store.py)',
      );
      expect(File('${dir.path}/$name').readAsStringSync(), '{ a: <<rejected');
      expect(file.readAsStringSync(), '{ a: <<rejected',
          reason: 'preservation copies; it never replaces the document');
    });

    test('retention keeps the five newest copies by name', () async {
      final contents = <String, String>{};
      for (var i = 0; i < 7; i++) {
        file.writeAsStringSync('rejected $i');
        final name = await fresh().preserveRejectedBytes();
        contents[name] = 'rejected $i';
      }
      final copies = fileNames(dir).where((n) => n.contains('.conflicted.')).toList()..sort();
      expect(copies, hasLength(5), reason: 'conflicted_retention default 5');
      // Prune-by-name-sort keeps the newest five stamps,
      // i.e. the LAST five in name order — the same rule the
      // baseline runs. The two oldest were removed.
      final survivors = contents.entries
          .where((e) => copies.contains(e.key))
          .map((e) => e.value)
          .toList()
        ..sort();
      expect(survivors, ['rejected 2', 'rejected 3', 'rejected 4', 'rejected 5', 'rejected 6'],
          reason: 'the five newest contents survive');
    });

    test('preserving an absent document is NOT_FOUND', () async {
      file.deleteSync();
      await expectLater(
        fresh().preserveRejectedBytes(),
        throwsA(isA<AisetFailure>().having((f) => f.code, 'code', AisetErrorCode.notFound)),
      );
    });
  });

  group('the runtime restore (the 2E-c hook)', () {
    test('rejected bytes go to a conflicted copy; the good text returns and the '
        'corrupt bytes never enter the .back chain', () async {
      // The flow the bootstrap of slice 2E-c runs when the on-disk
      // revision fails to load: the baseline's invalid-reread
      // restore, verified by execution — including its
      // PENDING-A42b defect: `write_unchecked(last_validated)`
      // runs the ORDINARY rotation, so the corrupt current bytes
      // land in `.back` (byte-identical to the conflicted copy) and
      // the LKG slot can hold garbage. This adapter preserves
      // the bytes and restores WITHOUT poisoning the
      // chain.
      file.writeAsStringSync('v1');
      final storage = fresh();
      await storage.read();
      // An external tool corrupts the file: valid UTF-8, so the
      // read answers; it is the DOCUMENT that is invalid,
      // which the pipeline (not the adapter) reports.
      file.writeAsStringSync('{ a: <<garbage');
      final garbage = await storage.read();

      final result = await storage.restoreLastValidated(
          rejectedRevision: garbage.revision, goodText: 'v1');
      expect(result.status, AisetCommitStatus.committed);
      expect(file.readAsStringSync(), 'v1', reason: 'the good text is back');

      final conflicted = fileNames(dir).where((n) => n.contains('.conflicted.')).toList();
      expect(conflicted, hasLength(1));
      expect(File('${dir.path}/${conflicted.single}').readAsStringSync(), '{ a: <<garbage');
      expect(File('${dir.path}/cfg.json5.back').existsSync(), isFalse,
          reason: 'PENDING-A42b: corrupt bytes must not become the session backup');
    });

    test('a restore over a revision that moved is refused', () async {
      file.writeAsStringSync('v1');
      final storage = fresh();
      await storage.read();
      file.writeAsStringSync('{ a: <<garbage');
      final garbage = await storage.read();
      // A third writer landed after our invalid read.
      file.writeAsStringSync('{ a: 2 } // someone else');
      final result =
          await storage.restoreLastValidated(rejectedRevision: garbage.revision, goodText: 'v1');
      expect(result.status, AisetCommitStatus.revisionConflict,
          reason: 'the restore must not bulldoze a revision nobody rejected');
      expect(file.readAsStringSync(), '{ a: 2 } // someone else');
      expect(fileNames(dir).where((n) => n.contains('.conflicted.')), isEmpty,
          reason: 'the failed check writes nothing at all');
    });

    test('a repeated restore against the same rejected revision is a '
        'conflict, not a second overwrite', () async {
      // After the first restore the file holds the
      // good text, so the rejected revision no longer matches and a
      // stale second attempt must be refused.
      file.writeAsStringSync('v1');
      final storage = fresh();
      await storage.read();
      file.writeAsStringSync('{ a: <<garbage');
      final garbage = await storage.read();
      final first =
          await storage.restoreLastValidated(rejectedRevision: garbage.revision, goodText: 'v1');
      expect(first.status, AisetCommitStatus.committed);
      expect(first.revision, revisionOfBytes(utf8Bytes('v1')));
      final second =
          await storage.restoreLastValidated(rejectedRevision: garbage.revision, goodText: 'v1');
      expect(second.status, AisetCommitStatus.revisionConflict);
    });
  });
}
