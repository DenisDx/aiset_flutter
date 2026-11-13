import 'dart:convert';
import 'dart:io';

import 'package:aiset_core/aiset_core.dart';
import 'package:aiset_storage_io/aiset_storage_io.dart';
import 'package:test/test.dart';

import 'test_utils/helpers.dart';

/// The adapter through the real write pipeline of
/// `aiset_core` (`SPEC.md` amendment 8): the candidate the
/// pipeline builds is what lands on disk, byte-exact
/// with its comments; a rejected pipeline
/// run touches nothing; the revision pair
/// is the precondition between two independent services on
/// one file; and a reload boundary
/// (`beginEditingSession`) is what re-arms the session backup.
///
/// This is the slice-2E contract from 2D: "adapters are exercised
/// through the pipeline's conditional write, not in isolation."
void main() {
  late Directory dir;
  late File file;
  late AisetService service;
  late AisetNativeFileStorage storage;
  final demo = Principal.demo();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('aiset_io_pipeline');
    file = File('${dir.path}/cfg.json5')..writeAsStringSync(_config);
    storage = storageIn(dir);
    service = AisetService();
    service.register(AisetDocumentRegistration(
      documentId: 'cfg',
      storage: storage,
      descriptorSource: testDescriptorSource,
    ));
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('a pipeline batch commits one atomic file write', () async {
    final pair = await service.revisionPair('cfg', principal: demo);
    final result = await service.applyOperations('cfg', const [
      AisetOperation(kind: AisetOperationKind.set, path: '/a', valueText: '7'),
      AisetOperation(kind: AisetOperationKind.set, path: '/name', valueText: '"seven"'),
    ], expected: pair, principal: demo);
    expect(result.stored, isTrue, reason: '${result.failure}');
    expect(result.changedPaths, ['/a', '/name']);
    // The candidate is exactly what the file holds now:
    // one write for the batch, byte-identical to the
    // pipeline's own text.
    expect(file.readAsStringSync(), result.candidateText);
    expect(result.revision, currentRevision(dir));
  });

  test('a rejected pipeline run leaves the file byte-for-byte unchanged',
      () async {
    final before = file.readAsBytesSync();
    final pair = await service.revisionPair('cfg', principal: demo);
    final result = await service
        .setValue('cfg', '/a', '900', expected: pair, principal: demo); // over maximum
    expect(result.stored, isFalse);
    expect(result.failure!.code, AisetErrorCode.validationError);
    expect(file.readAsBytesSync(), before);
    expect(fileNames(dir), isNot(contains('cfg.json5.back')),
        reason: 'nothing was written, so nothing rotated');
  });

  test('comments and formatting survive a pipeline edit', () async {
    final pair = await service.revisionPair('cfg', principal: demo);
    await service.setValue('cfg', '/a', '9', expected: pair, principal: demo);
    final text = file.readAsStringSync();
    expect(text, contains('// the integer'),
        reason: 'preservation: comments ride through the CST edit');
    expect(text, contains('name: "demo"'), reason: 'untouched member keeps its text');
  });

  test('two independent services on one file: the revision pair decides',
      () async {
    // The SPEC.md amendment 8 rule between two
    // controllers: the second writer's stale
    // pair is refused, and after a reread it wins on
    // the fresh revision — the first result is not lost
    // silently, it is a conflict the client can rebase on.
    final serviceB = AisetService();
    serviceB.register(AisetDocumentRegistration(
      documentId: 'cfg',
      storage: storageIn(dir),
      descriptorSource: testDescriptorSource,
    ));
    final pairA = await service.revisionPair('cfg', principal: demo);
    final first =
        await service.setValue('cfg', '/a', '11', expected: pairA, principal: demo);
    expect(first.stored, isTrue);

    final staleB = RevisionPair(source: pairA.source, descriptor: pairA.descriptor);
    final refused =
        await serviceB.setValue('cfg', '/a', '222', expected: staleB, principal: demo);
    expect(refused.stored, isFalse);
    expect(refused.failure!.code, AisetErrorCode.revisionConflict);

    final pairB = await serviceB.revisionPair('cfg', principal: demo);
    expect(pairB.source, first.revision, reason: 'B re-reads A\'s committed revision');
    final second =
        await serviceB.setValue('cfg', '/name', '"kept"', expected: pairB, principal: demo);
    expect(second.stored, isTrue, reason: '${second.failure}');
    expect(file.readAsStringSync(), contains('a: 11'),
        reason: 'A\'s value is still there: B did not bulldoze it');
  });

  test('the service\'s snapshot after a commit reads back from '
      'the file', () async {
    final pair = await service.revisionPair('cfg', principal: demo);
    final result = await service.setValue('cfg', '/a', '3', expected: pair, principal: demo);
    expect(result.stored, isTrue);
    final snapshot = await service.reread('cfg', principal: demo);
    expect(snapshot.sourceRevision, result.revision);
    expect(snapshot.storedAt('/a'), 3);
    expect(snapshot.invalidOnDisk, isFalse);
  });

  test('each reload-boundary commits rotate the session chain',
      () async {
    // Simulates the bootstrap's session discipline:
    // beginEditingSession marks the load/reread boundary;
    // the first committed edit of that session takes the
    // backup slot.
    file.writeAsStringSync('{ a: 1 }');
    final texts = ['{ a: 2 }', '{ a: 3 }', '{ a: 4 }'];
    var revision = revisionOfBytes(utf8Bytes('{ a: 1 }'));
    for (final text in texts) {
      storage.beginEditingSession();
      final result = await storage.compareAndSwap(expectedRevision: revision, sourceText: text);
      expect(result.status, AisetCommitStatus.committed);
      revision = result.revision!;
    }
    final chain = storage.backupChain();
    expect(chain.map((e) => _textOf(e.bytes)), ['{ a: 3 }', '{ a: 2 }', '{ a: 1 }'],
        reason: 'one slot per session, newest first');
    expect(file.readAsStringSync(), '{ a: 4 }');
  });
}

String _textOf(List<int> bytes) =>
    bytes.every((b) => b < 0x80) ? String.fromCharCodes(bytes) : utf8.decode(bytes);

/// A small config with a comment, used by the
/// pipeline tests.
const String _config = '''
{
  // the integer
  a: 1,
  name: "demo",
}
''';
