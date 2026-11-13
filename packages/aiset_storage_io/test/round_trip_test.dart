import 'dart:io';
import 'dart:typed_data';

import 'package:aiset_core/aiset_core.dart';

import 'package:test/test.dart';

import 'test_utils/helpers.dart';

/// Byte identity through the adapter, including the byte order mark,
/// and the separation of the four "no document" outcome classes at
/// the port boundary.
///
/// Baseline facts baked in here — each verified by executing the
/// pinned reference clone during slice 2E-a (commands and outputs in
/// the slice report; nothing here invokes Python):
///
/// * `revision_of_bytes(b'hello')` ==
///   `sha256:2cf24dba5fb0a30e26e83b2ac5b9e29e`: "sha256:" plus the
///   first 32 hex of SHA-256 over the RAW bytes, BOM included. The
///   core's `sourceRevisionOfBytes` is the same function, so revision
///   strings agree by construction.
/// * `decode`/`encode` strip and re-add the mark, so the
///   STORE can round-trip a BOM — but the SERVICE decides the
///   flag from `current_text.startswith(BOM)` on the ALREADY-decoded
///   (mark-stripped) string, which is always false, and the first
///   save LOSES the BOM (executed: a BOM'd file saved through
///   `Service.set` came back without the mark bytes). This adapter
///   keeps the mark as the first character of the text, so a write
///   round-trips byte-identically (PENDING-A42a — a Python defect we
///   do not reproduce).
/// * `read_bytes` of an absent file raises `StorageError`
///   ("does not exist") — never an empty document.
void main() {
  group('round-trip byte identity', () {
    test('a plain file reads, rewrites and keeps its bytes', () => run((dir) async {
          final source = '// keep me\n{ a: 1,\n  name: "x" }  // tail\n';
          final original = utf8Bytes(source);
          File('${dir.path}/cfg.json5').writeAsBytesSync(original);

          final storage = storageIn(dir);
          final stored = await storage.read();
          expect(stored.sourceText, source, reason: 'the text is the exact decode');
          expect(stored.revision, revisionOfBytes(original));
          expect(stored.loadedFrom, 'file');

          final result = await storage.compareAndSwap(
            expectedRevision: stored.revision,
            sourceText: stored.sourceText, // a no-change write
          );
          expect(result.status, AisetCommitStatus.committed);
          expect(result.revision, stored.revision);
          expect(File('${dir.path}/cfg.json5').readAsBytesSync(), original,
              reason: 'a no-change CAS is byte-identical');
        }));

    test('a BOM is stored, hashed and written back unchanged', () => run((dir) async {
          final body = utf8Bytes('{ a: 1 }');
          final original = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...body]);
          File('${dir.path}/cfg.json5').writeAsBytesSync(original);

          final storage = storageIn(dir);
          final stored = await storage.read();
          expect(stored.sourceText.codeUnitAt(0), 0xFEFF,
              reason: 'the mark survives as the first character');
          expect(stored.revision, revisionOfBytes(original),
              reason: 'the revision is the hash of the RAW bytes, BOM included');

          final result = await storage.compareAndSwap(
            expectedRevision: stored.revision,
            sourceText: stored.sourceText,
          );
          expect(result.status, AisetCommitStatus.committed);
          expect(File('${dir.path}/cfg.json5').readAsBytesSync(), original,
              reason: 'PENDING-A42a: the BOM must survive a save');
        }));

    test('CRLF, bare-CR and trailing-newline content survive a round trip',
        () => run((dir) async {
              for (final source in [
                '{ a: 1 }\r\n// x\r\n',
                '{ a: 1 }\r// x\r',
                '{ a: 1 }\n\n\n',
              ]) {
                final file = File('${dir.path}/cfg.json5')..writeAsBytesSync(utf8Bytes(source));
                final storage = storageIn(dir);
                final stored = await storage.read();
                final result = await storage.compareAndSwap(
                  expectedRevision: stored.revision,
                  sourceText: stored.sourceText,
                );
                expect(result.status, AisetCommitStatus.committed, reason: source);
                expect(file.readAsBytesSync(), utf8Bytes(source),
                    reason: 'line endings stay byte-exact: ${source.codeUnits}');
              }
            }));

    test('multi-byte and non-BMP content round-trips', () => run((dir) async {
          final source = '{ name: "h\u00e9llo \u2014 \u65e5\u672c\u8a9e \u{1F600}" }';
          File('${dir.path}/cfg.json5').writeAsBytesSync(utf8Bytes(source));
          final storage = storageIn(dir);
          final stored = await storage.read();
          expect(stored.sourceText, source);
          final result = await storage.compareAndSwap(
              expectedRevision: stored.revision, sourceText: stored.sourceText);
          expect(result.isCommitted, isTrue);
          expect(File('${dir.path}/cfg.json5').readAsBytesSync(), utf8Bytes(source));
        }));

    test('an empty file reads as empty text with the zero-bytes revision',
        () => run((dir) async {
          File('${dir.path}/cfg.json5').writeAsBytesSync(Uint8List(0));
          final storage = storageIn(dir);
          final stored = await storage.read();
          expect(stored.sourceText, '');
          expect(stored.revision, revisionOfBytes(const <int>[]));
        }));

    test('the atomic replace leaves no temp debris and keeps the sidecar',
        () => run((dir) async {
          File('${dir.path}/cfg.json5').writeAsBytesSync(utf8Bytes('{ a: 1 }'));
          final storage = storageIn(dir);
          final first = await storage.read();
          final second = await storage.compareAndSwap(
              expectedRevision: first.revision, sourceText: '{ a: 2 }');
          expect(second.isCommitted, isTrue);
          await Future<void>.delayed(const Duration(milliseconds: 30));
          final names = fileNames(dir);
          expect(names.any((n) => n.endsWith('.tmp')), isFalse, reason: 'leftovers: $names');
          // The document, its lock sidecar (created on first use and
          // never deleted, like the baseline), and the session's
          // .back slot holding the pre-edit bytes.
          expect(names, containsAll(<String>['cfg.json5', 'cfg.json5.lock', 'cfg.json5.back']));
        }));
  });

  group('absent, unreadable and corrupt are different outcomes', () {
    test('an absent document reads NOT_FOUND, never empty', () => run((dir) async {
          final storage = storageIn(dir);
          final failure = await captureError(storage.read());
          expect(failure, isA<AisetFailure>());
          expect((failure! as AisetFailure).code, AisetErrorCode.notFound);
          expect(File('${dir.path}/cfg.json5.lock').existsSync(), isFalse,
              reason: 'a read does not create the sidecar; only a write does');
        }));

    test('a directory standing at the document path is a storage error, not absence',
        () => run((dir) async {
          Directory('${dir.path}/cfg.json5').createSync();
          final storage = storageIn(dir);
          final failure = await captureError(storage.read());
          expect(failure, isA<AisetFailure>());
          expect((failure! as AisetFailure).code, AisetErrorCode.storageError);
        }));

    test('an unreadable file is a storage error, never an empty document', () => run((dir) async {
          // Only meaningful where the filesystem enforces modes.
          if (Platform.isWindows) return;
          final file = File('${dir.path}/cfg.json5')..writeAsStringSync('{ a: 1 }');
          chmod(file.path, '000');
          try {
            final storage = storageIn(dir);
            final failure = await captureError(storage.read());
            expect(failure, isA<AisetFailure>());
            expect((failure! as AisetFailure).code, AisetErrorCode.storageError,
                reason: 'a read that FAILS is never absence (SPEC.md 11, STO-05)');
          } finally {
            chmod(file.path, '644');
          }
        }));
  });
}
