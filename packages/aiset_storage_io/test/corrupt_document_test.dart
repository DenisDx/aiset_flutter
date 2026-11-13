import 'dart:io';

import 'package:aiset_core/aiset_core.dart';
import 'package:aiset_storage_io/aiset_storage_io.dart';
import 'package:test/test.dart';

import 'test_utils/helpers.dart';

/// Corrupt and hostile file states answered with the
/// RIGHT outcome class, each pinned against an
/// executed-baseline fact from slice 2E-a:
///
/// * invalid UTF-8 at the path: the baseline lets a raw
///   `UnicodeDecodeError` escape `store.read()` and `service.load()`
///   (executed). Here: a clean `STORAGE_ERROR` failure, the file
///   untouched — PENDING-A42c.
/// * a directory at the path: the baseline crashes on the
///   NEXT write with `IsADirectoryError` from
///   `read_bytes()` (executed); its `read` path wraps
///   it into `StorageError`. Here: `STORAGE_ERROR` at
///   every entry point — never a phantom
///   "absent document" (`SPEC.md` amendment 11).
/// * a file name longer than the filesystem accepts (ENAMETOOLONG,
///   not ENOENT): `STORAGE_ERROR`, because only
///   ENOENT may read as absent.
/// * an oversized document: `PAYLOAD_TOO_LARGE`
///   on read, and a `rejected` CAS on write — before any
///   I/O, so the previous version cannot be damaged.
/// * an external edit that parses but violates the
///   descriptor: a revision the pipeline refuses to
///   commit over; the bytes on disk stay
///   exactly as the external writer left them.
void main() {
  group('undecodable bytes', () {
    test('read answers STORAGE_ERROR, never absence and never a crash',
        () => run((dir) async {
              // Executed baseline: the same bytes make the
              // baseline raise UnicodeDecodeError out of load().
              File('${dir.path}/cfg.json5')
                  .writeAsBytesSync([0x7B, 0x20, 0x61, 0xFF, 0xFE, 0x7D]);
              final failure = await captureError(storageIn(dir).read());
              expect(failure, isA<AisetFailure>(),
                  reason: 'PENDING-A42c: a stable code, not a raw exception');
              expect((failure! as AisetFailure).code, AisetErrorCode.storageError);
            }));

    test('revisionOfCurrentBytes reports the corrupt revision that read() cannot',
        () => run((dir) async {
          // The port's read throws on undecodable bytes, so a
          // later restore needs the raw-byte revision from this
          // helper — the corrupt bytes are still a real,
          // CAS-checkable revision.
          final corrupt = [0x7B, 0x61, 0xFF, 0xFE, 0x7D];
          File('${dir.path}/cfg.json5').writeAsBytesSync(corrupt);
          final storage = storageIn(dir);
          expect(await captureError(storage.read()), isA<AisetFailure>(),
              reason: 'read() cannot hand out the text');
          final revision = await storage.revisionOfCurrentBytes();
          expect(revision, revisionOfBytes(corrupt),
              reason: 'the revision is the hash of the RAW bytes');
          // An external valid edit changes the raw revision, so a
          // restore keyed to the corrupt one is refused.
          File('${dir.path}/cfg.json5').writeAsStringSync('{ a: 1 }');
          final result = await storage.restoreLastValidated(
              rejectedRevision: revision, goodText: '{ a: 2 }');
          expect(result.status, AisetCommitStatus.revisionConflict);
        }));

    test('a CAS against undecodable current bytes conflicts without rewriting',
        () => run((dir) async {
              final file = File('${dir.path}/cfg.json5')
                ..writeAsBytesSync([0xEF, 0xBB, 0xBF, 0xC0, 0x80]);
              final bogus = revisionOfBytes(utf8Bytes('{ a: 1 }'));
              final result =
                  await storageIn(dir).compareAndSwap(expectedRevision: bogus, sourceText: 'x');
              expect(result.status, AisetCommitStatus.revisionConflict,
                  reason: 'the hash of the corrupt bytes is the stored revision; it is '
                      'never equal to a guess, so a blind overwrite is '
                      'impossible at this boundary');
              expect(file.readAsBytesSync(), [0xEF, 0xBB, 0xBF, 0xC0, 0x80]);
            }));
  });

  group('a directory at the document path', () {
    test('reads as STORAGE_ERROR, never as absence', () => run((dir) async {
          Directory('${dir.path}/cfg.json5').createSync();
          final storage = storageIn(dir);
          final failure = await captureError(storage.read());
          expect((failure! as AisetFailure).code, AisetErrorCode.storageError);
          // The write path meets the same answer under the
          // lock: no crash, no damage, no phantom create.
          final casFailure = await captureError(
              storage.compareAndSwap(expectedRevision: 'sha256:${'0' * 32}', sourceText: 'x'));
          expect((casFailure! as AisetFailure).code, AisetErrorCode.storageError);
          expect(Directory('${dir.path}/cfg.json5').existsSync(), isTrue,
              reason: 'the directory stands untouched');
          expect(File('${dir.path}/cfg.json5.back').existsSync(), isFalse,
              reason: 'no rotation ran either');
        }));
  });

  group('a name the filesystem rejects', () {
    test('ENAMETOOLONG is STORAGE_ERROR, not absence', () => run((dir) async {
          final deep = storageIn(dir, name: 'x' * 400);
          final failure = await captureError(deep.read());
          expect((failure! as AisetFailure).code, AisetErrorCode.storageError,
              reason: 'only ENOENT may answer "absent" (SPEC.md 11: a read failure is '
                  'never an absent document)');
        }));
  });

  group('size limit', () {
    test('an oversized document fails the read with PAYLOAD_TOO_LARGE',
        () => run((dir) async {
              File('${dir.path}/cfg.json5').writeAsStringSync('y' * 200);
              final storage = storageIn(dir,
                  settings: const AisetNativeFileSettings(limits: Limits(maxFileSize: 64)));
              final failure = await captureError(storage.read());
              expect((failure! as AisetFailure).code, AisetErrorCode.payloadTooLarge);
            }));

    test('an oversized candidate is rejected before touching the file',
        () => run((dir) async {
              final file = File('${dir.path}/cfg.json5')..writeAsStringSync('small');
              final storage = storageIn(dir,
                  settings: const AisetNativeFileSettings(limits: Limits(maxFileSize: 64)));
              final stored = await storage.read();
              final result =
                  await storage.compareAndSwap(expectedRevision: stored.revision, sourceText: 'z' * 5000);
              expect(result.status, AisetCommitStatus.rejected);
              expect(file.readAsStringSync(), 'small',
                  reason: 'a quota refusal MUST NOT damage the previous version');
              expect(fileNames(dir), isNot(contains('cfg.json5.back')),
                  reason: 'the refusal does not even rotate the chain');
            }));
  });

  group('external invalid edit through the pipeline', () {
    test('a violating external edit reports invalidOnDisk and is '
        'never silently rewritten by a later save', () => run((dir) async {
          final file = File('${dir.path}/cfg.json5')..writeAsStringSync('{ a: 1 }');
          final service = AisetService();
          service.register(AisetDocumentRegistration(
            documentId: 'cfg',
            storage: storageIn(dir),
            descriptorSource: testDescriptorSource,
          ));
          final clean = await service.load('cfg', principal: Principal.demo());
          expect(clean.invalidOnDisk, isFalse);

          // A foreign writer stores bytes that parse but violate the
          // descriptor (a: 900 > maximum 100).
          file.writeAsStringSync('{ a: 900 } // foreign');
          final dirty = await service.reread('cfg', principal: Principal.demo());
          expect(dirty.invalidOnDisk, isTrue);
          expect(dirty.loadedFrom, 'invalid');
          expect(dirty.sourceRevision, revisionOfBytes(utf8Bytes('{ a: 900 } // foreign')));
          // The adapter still stores the foreign bytes verbatim:
          // invalidity is a pipeline judgment, and the adapter
          // never quietly "fixes" or destroys a document.
          expect(file.readAsStringSync(), '{ a: 900 } // foreign');
        }));

    test('a corrupt (unparsable) external edit is a parse outcome, not a '
        'storage failure and not absence', () => run((dir) async {
          final file = File('${dir.path}/cfg.json5')..writeAsStringSync('{ a: 1 }');
          final service = AisetService();
          service.register(AisetDocumentRegistration(
            documentId: 'cfg',
            storage: storageIn(dir),
            descriptorSource: testDescriptorSource,
          ));
          await service.load('cfg', principal: Principal.demo());
          file.writeAsStringSync('{{{ total garbage');
          final error = await captureError(service.reread('cfg', principal: Principal.demo()));
          // This is the pipeline's (2D) answer for a source the
          // parser rejects, and the adapter's job is only to hand
          // the exact bytes up: NOT_FOUND and STORAGE_ERROR stay the
          // other, distinct outcomes (SPEC.md amendment 11).
          expect(error, isA<Json5SourceException>(),
              reason: 'parses as a source problem, not a storage failure — '
                  'and the corrupt bytes survive for the host to inspect');
          expect(file.readAsStringSync(), '{{{ total garbage');
        }));

    test('the revision pair of an invalid state cannot commit a blind '
        'overwrite of the corrupt bytes', () => run((dir) async {
          final file = File('${dir.path}/cfg.json5')..writeAsStringSync('{ a: 1 }');
          final service = AisetService();
          service.register(AisetDocumentRegistration(
            documentId: 'cfg',
            storage: storageIn(dir),
            descriptorSource: testDescriptorSource,
          ));
          final clean = await service.load('cfg', principal: Principal.demo());
          file.writeAsStringSync('{ a: 900 } // foreign violation');

          // A client still holding the OLD (pre-corruption)
          // revision is refused by the pipeline's
          // recheck against the adapter's fresh read (REV-01).
          final result = await service
              .setValue('cfg', '/a', '2', expected: clean.revisionPair, principal: Principal.demo());
          expect(result.stored, isFalse);
          expect(result.failure!.code, AisetErrorCode.revisionConflict);
          expect(file.readAsStringSync(), '{ a: 900 } // foreign violation',
              reason: 'a stale write never bulldozes the current bytes');
        }));
  });
}
