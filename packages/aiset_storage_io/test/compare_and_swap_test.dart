import 'dart:io';

import 'package:aiset_core/aiset_core.dart';
import 'package:aiset_storage_io/aiset_storage_io.dart';
import 'package:test/test.dart';

import 'test_utils/helpers.dart';

/// The conditional-write contract of `SPEC.md` amendments 8 and 10
/// at the port boundary: the outcome classes, the untouched
/// file on every refusal, and the two-process race proof that
/// makes `conditionalWrite: true` honest.
///
/// Baseline facts baked in (verified by execution during slice 2E-a;
/// the commands and outputs are in the slice report):
///
/// * `Store.write(expected_revision=stale)` re-reads UNDER THE LOCK,
///   raises, and writes nothing; the file keeps its bytes. The
///   baseline's own service `set()` likewise does
///   `with store.lock(): read; compare; write_locked` — check and
///   replace in ONE lock acquisition, the ordering this adapter
///   reproduces.
/// * A matching expected revision commits and the reported revision is
///   the hash of the new bytes.
/// * `read_bytes` of an absent file raises ("does not exist") —
///   absence is never an empty document, and it is a different class
///   from a read that failed.
void main() {
  late Directory dir;
  late File file;
  late AisetNativeFileStorage storage;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('aiset_io_cas');
    file = File('${dir.path}/cfg.json5')..writeAsStringSync('{ a: 1 }');
    storage = storageIn(dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('CAS success', () {
    test('a matching revision commits and reports the new revision', () async {
      final stored = await storage.read();
      final result = await storage.compareAndSwap(
        expectedRevision: stored.revision,
        sourceText: '{ a: 2 }',
      );
      expect(result.status, AisetCommitStatus.committed);
      expect(result.isCommitted, isTrue);
      expect(result.revision, revisionOfBytes(utf8Bytes('{ a: 2 }')));
      expect(file.readAsStringSync(), '{ a: 2 }');
    });

    test('the revision the commit reports is what the next read returns', () async {
      final stored = await storage.read();
      final result = await storage.compareAndSwap(
          expectedRevision: stored.revision, sourceText: '{ a: 3 } // now');
      expect(result.status, AisetCommitStatus.committed);
      final again = await storage.read();
      expect(again.revision, result.revision);
      expect(again.sourceText, '{ a: 3 } // now');
    });
  });

  group('stale revision is refused with the file untouched', () {
    test('a wrong expected revision answers revisionConflict', () async {
      final before = file.readAsBytesSync();
      final result = await storage.compareAndSwap(
        expectedRevision: 'sha256:${'0' * 32}',
        sourceText: '{ a: 99 }',
      );
      expect(result.status, AisetCommitStatus.revisionConflict);
      expect(result.isCommitted, isFalse);
      expect(result.revision, revisionOfBytes(before),
          reason: 'the conflict names the revision actually stored');
      expect(file.readAsBytesSync(), before, reason: 'a refusal writes zero bytes');
    });

    test('the PREVIOUS revision is stale once a commit landed', () async {
      final first = await storage.read();
      final second = await storage.compareAndSwap(
          expectedRevision: first.revision, sourceText: '{ a: 2 }');
      expect(second.status, AisetCommitStatus.committed);
      final stale = await storage.compareAndSwap(
          expectedRevision: first.revision, sourceText: '{ a: 3 }');
      expect(stale.status, AisetCommitStatus.revisionConflict);
      expect(stale.revision, second.revision);
      expect(file.readAsStringSync(), '{ a: 2 }');
    });

    test('a foreign edit makes the client revision stale', () async {
      final stored = await storage.read();
      // A writer outside the adapter: the
      // two-controllers-on-one-file case of SPEC.md amendment 8.
      file.writeAsStringSync('{ a: 7 } // foreign');
      final result = await storage.compareAndSwap(
          expectedRevision: stored.revision, sourceText: '{ a: 8 }');
      expect(result.status, AisetCommitStatus.revisionConflict);
      expect(file.readAsStringSync(), '{ a: 7 } // foreign',
          reason: 'the foreign bytes are never bulldozed');
    });
  });

  group('rejected paths never touch the file', () {
    test('a blank expected revision is rejected before any I/O', () async {
      final before = file.readAsBytesSync();
      for (final blank in ['', '   ', '\t\n']) {
        final result = await storage.compareAndSwap(
          expectedRevision: blank,
          sourceText: '{ a: 42 }',
        );
        expect(result.status, AisetCommitStatus.rejected, reason: blank.codeUnits.toString());
        expect(result.detail, isNotEmpty);
      }
      expect(file.readAsBytesSync(), before);
      expect(fileNames(dir), isNot(contains('cfg.json5.back')),
          reason: 'a rejected CAS does not even rotate the chain');
    });

    test('an oversized candidate is rejected and the file survives', () async {
      final tiny = storageIn(
        dir,
        settings: const AisetNativeFileSettings(limits: Limits(maxFileSize: 32)),
      );
      final stored = await tiny.read();
      final result = await tiny.compareAndSwap(
        expectedRevision: stored.revision,
        sourceText: 'x' * 1000,
      );
      expect(result.status, AisetCommitStatus.rejected);
      expect(result.detail, contains('32'));
      expect(file.readAsBytesSync(), utf8Bytes('{ a: 1 }'),
          reason: 'a quota refusal MUST NOT damage the previous version');
    });

    test('a dry run through the pipeline leaves the file byte-for-byte unchanged', () async {
      final service = AisetService();
      service.register(AisetDocumentRegistration(
        documentId: 'cfg',
        storage: storageIn(dir),
        descriptorSource: testDescriptorSource,
      ));
      final before = file.readAsBytesSync();
      final pair = await service.revisionPair('cfg', principal: Principal.demo());
      final result = await service.setValue('cfg', '/a', '5',
          expected: pair, principal: Principal.demo(), dryRun: true);
      expect(result.stored, isFalse);
      expect(result.candidateText, isNotNull, reason: 'a dry run answers the candidate');
      expect(file.readAsBytesSync(), before);
      expect(fileNames(dir), isNot(contains('cfg.json5.back')));
    });
  });

  group('the absent-document create is not smuggled through CAS', () {
    test('a create attempt against a missing file conflicts', () async {
      file.deleteSync();
      final result = await storage.compareAndSwap(
        expectedRevision: 'sha256:${'0' * 32}',
        sourceText: '{ a: 1 }',
      );
      expect(result.status, AisetCommitStatus.revisionConflict);
      expect(result.detail, contains('initial create'));
      expect(file.existsSync(), isFalse, reason: 'no accidental create');
    });
  });

  group('two-process race: the proof behind conditionalWrite: true', () {
    test('concurrent processes: exactly one commit per revision', () async {
      const candidateA = '{ a: 11 } // A';
      const candidateB = '{ a: 222 } // B';
      final outcomes = await raceWorkers(dir, {'A': candidateA, 'B': candidateB},
          gateFile: '${dir.path}/gate');
      for (final outcome in outcomes) {
        expect(outcome.exitCode, 0, reason: '$outcome');
      }
      // The handshake proves both read the same revision
      // before either was released.
      expect(outcomes.map((o) => o.readRevision).toSet(), hasLength(1),
          reason: 'both workers must have read the same revision: $outcomes');
      expect(outcomes.map((o) => o.status), containsAll(['committed', 'revisionConflict']),
          reason: '$outcomes');
      expect(outcomes.where((o) => o.status == 'committed'), hasLength(1),
          reason: 'at most one CAS lands per revision: $outcomes');
      final finalText = file.readAsStringSync();
      expect([candidateA, candidateB], contains(finalText),
          reason: 'the stored text is one complete candidate, not a mix');
    });

    test('10 x 2 processes: no lost update and no torn file', () async {
      // Repeating the race catches the narrow window where a lock
      // handoff could let two writers both pass the revision check.
      const candidateA = '{ a: 100 } // round-A';
      const candidateB = '{ a: 200 } // round-B';
      for (var round = 0; round < 10; round++) {
        file.writeAsStringSync('{ a: 1 }');
        final outcomes = await raceWorkers(dir, {'A': candidateA, 'B': candidateB},
            gateFile: '${dir.path}/gate.$round');
        expect(outcomes.where((o) => o.status == 'committed'), hasLength(1),
            reason: 'round $round: $outcomes');
        expect(outcomes.where((o) => o.status == 'revisionConflict'), hasLength(1),
            reason: 'round $round: $outcomes');
        expect([candidateA, candidateB], contains(file.readAsStringSync()),
            reason: 'round $round stored a torn or mixed file');
      }
    });

    test('a reader never observes a half-written document', () async {
      // A separate process loops whole-file reads and verifies
      // after EVERY read that the content is one whole document of
      // the agreed family; this process commits 40
      // differently-sized documents. With the
      // temp-file-plus-rename replace a reader sees only the old or
      // the new bytes — never a prefix, a suffix or a mix.
      file.writeAsStringSync('SEED');
      const total = 40;
      final finalCandidate = 'x' * (1000 + total * 37);
      final watcher = await LiveWorker.start(['watch', dir.path, finalCandidate]);
      expect(await watcher.nextLine(), 'READY', reason: 'the reader is live before writes');

      var revision = revisionOfBytes(utf8Bytes('SEED'));
      for (var i = 1; i <= total; i++) {
        final candidate = 'x' * (1000 + i * 37);
        final result =
            await storage.compareAndSwap(expectedRevision: revision, sourceText: candidate);
        expect(result.status, AisetCommitStatus.committed, reason: 'write $i: $result');
        revision = result.revision!;
      }
      final result = await watcher.finish();
      final last = result.lines.last;
      expect(last, startsWith('DONE'),
          reason: 'the watcher reported a problem: ${result.lines} / ${result.stderr}');
      expect(int.parse(last.split(' ').last), greaterThanOrEqualTo(total),
          reason: 'the reader must have observed the intermediate revisions');
    });
  });
}
