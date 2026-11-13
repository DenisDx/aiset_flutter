import 'dart:convert';

import 'package:aiset_core/aiset_core.dart';
import 'package:test/test.dart';

import 'corpus_expectations.dart';
import 'fixtures_io.dart';

/// Runs one corpus query against [document].
Object? runCorpusQuery(Json5Document document, String op, String pointer) {
  switch (op) {
    case 'stored_value':
      return document.storedValue(document.find(pointer));
    case 'value_text':
      return document.sliceOf(document.find(pointer)!);
    case 'format_of':
      return document.formatOf(document.find(pointer)!);
    case 'paths':
      return document.paths(pointer);
    default:
      throw StateError('unknown corpus query op: $op');
  }
}

/// Applies the corpus operation [operation] to [document] and returns the
/// produced source text.
String applyCorpusOperation(
    Json5Document document, Map<String, Object?> operation) {
  switch (operation['op']! as String) {
    case 'set':
      return document.applySet(
          operation['pointer']! as String, operation['value_text']! as String);
    case 'add':
      return document.applyAdd(
          operation['pointer']! as String, operation['value_text']! as String);
    case 'remove':
      return document.applyRemove(operation['pointer']! as String);
    case 'move':
      return document.applyMove(
          operation['source']! as String, operation['target']! as String);
    case 'rename':
      return document.applyRename(
          operation['pointer']! as String, operation['new_key']! as String);
    default:
      throw StateError('unknown corpus operation: $operation');
  }
}

void main() {
  final corpus = CompatCorpus.load();

  group('corpus integrity', () {
    test('fixtures/BASELINE records the baseline, generator and counts', () {
      final baseline = corpus.baseline();
      final source = baseline['baseline']! as Map<String, Object?>;
      expect(source['commit'], matches(RegExp(r'^[0-9a-f]{40}$')),
          reason: 'the corpus must be bound to a baseline commit SHA');
      final generator = baseline['generator']! as Map<String, Object?>;
      expect(generator['version'], isNotEmpty);
      expect(generator['sha256'], matches(RegExp(r'^[0-9a-f]{64}$')),
          reason: 'the generator must be identified by version and content hash');
      final counts = baseline['counts']! as Map<String, Object?>;
      for (final area in compatAreas) {
        expect(counts[area], isNotNull, reason: 'no count recorded for $area');
      }
      expect(baseline.containsKey('timestamp'), isFalse,
          reason: 'BASELINE must not carry a per-run timestamp: regenerating '
              'the corpus has to be byte-identical');
    });

    test('recorded counts match the committed case files', () {
      final counts = corpus.baseline()['counts']! as Map<String, Object?>;
      var total = 0;
      for (final area in compatAreas) {
        expect(counts[area], equals(corpus.area(area).length), reason: 'area $area');
        total += corpus.area(area).length;
      }
      expect(counts['total'], equals(total));
    });

    test('every case file is complete and stored in its own area', () {
      for (final area in compatAreas) {
        for (final testCase in corpus.area(area)) {
          expect(testCase.area, equals(area), reason: testCase.file.path);
          expect(testCase.id, isNotEmpty);
          expect(testCase.description, isNotEmpty);
          expect(testCase.classes, isNotEmpty);
          expect(testCase.expected, isNotEmpty);
        }
      }
    });

    test('a registered divergence asserts the correction and keeps the evidence', () {
      // SPEC_.md amendment 38: a wrong baseline output is never a skipped test.
      // The case asserts the corrected behavior, and the bytes the baseline
      // actually produced stay in the fixture as evidence.
      final divergent = [
        for (final area in compatAreas)
          for (final testCase in corpus.area(area))
            if (testCase.divergence != null) testCase,
      ];
      expect(divergent, isNotEmpty,
          reason: 'the corpus must still carry its registered divergences');
      for (final testCase in divergent) {
        final divergence = testCase.divergence!;
        expect(divergence['id'], isA<String>(), reason: '${testCase.id}: no id');
        expect(
            divergence['report'],
            matches(RegExp(
                r'^(?:[AF]\d+|PENDING-A\d+|SPEC5-FLUTTER-EXT|SPEC26-[A-Z]+)$')),
            reason: '${testCase.id}: amendment 38 requires the divergence block to '
                'name the item in the handoff notes for the Python team (a defect A, '
                'the agreed grammar extension F), the numbered placeholder for '
                'a defect not yet filed upstream (PENDING-A<NN>), or a named '
                'SPEC/docs anchor for a divergence the requirements fix '
                'differently from the baseline (SPEC5-FLUTTER-EXT, SPEC26-*). '
                'Anchors stay enumerated, not wildcarded');
        expect((divergence['note']! as String).length, greaterThan(40),
            reason: '${testCase.id}: the divergence must explain the defect');
        expect(divergence.containsKey('correctedOutput'), isFalse,
            reason: '${testCase.id}: the correction is asserted from `expected`; '
                'recording it twice lets the two copies drift');
        final evidence = testCase.baselineEvidence;
        expect(evidence, isNotNull,
            reason: '${testCase.id}: the baseline bytes must remain in the fixture');
        expect(testCase.expected['expectation'], equals('corrected'),
            reason: '${testCase.id}: an authored expectation must say so, so that '
                'no reader takes it for an observed baseline result');
        final asserted = {...testCase.expected}..remove('expectation');
        expect(describeMismatch(evidence, asserted), isNotNull,
            reason: '${testCase.id}: the correction equals the recorded '
                'baseline bytes, so the divergence is stale and must be removed');
      }
    });

    test('a set edit leaves the pointer holding the submitted value', () {
      // The requirement behind every `set`: the addressed position contains the
      // submitted value, and nothing else about the document is invented. Checked
      // against the operation itself, not against our code. (Re-baselined against
      // d4adb45, `operations` carries no divergence case, so the invariant
      // is asserted over the whole accepted `set` population instead of
      // only the corrected one.)
      var checked = 0;
      for (final testCase in corpus.area('operations')) {
        final operation = testCase.operation!;
        if (operation['op'] != 'set') continue;
        if (testCase.expected['ok'] != true) continue;
        checked++;
        final produced = applyCorpusOperation(parse(testCase.input), operation);
        final document = parse(produced);
        final held = document.storedValue(document.find(operation['pointer']! as String));
        final submitted = parse(operation['value_text']! as String).storedValue();
        final mismatch = describeMismatch(held, submitted);
        expect(mismatch, isNull,
            reason: '${testCase.id}: the pointer holds $mismatch');
      }
      expect(checked, greaterThan(0),
          reason: 'no accepted `set` case is registered, so this check would be vacuous');
    });

    test('the corpus covers the required splice behavior classes', () {
      final operations = corpus.area('operations');
      bool covers(bool Function(CompatCase) test) =>
          operations.any(test);
      expect(covers((c) => c.classes.contains('append-marker')), isTrue,
          reason: 'no case covers the append marker');
      expect(
          covers((c) => c.classes.contains('remove') && c.classes.contains('comments')),
          isTrue,
          reason: 'no case covers comment ownership on removal');
      expect(covers((c) => c.classes.contains('value-preserved')), isTrue,
          reason: 'no case covers a rename preserving the value text');
      expect(
          covers((c) => c.classes.contains('move') && c.classes.contains('nested')),
          isTrue,
          reason: 'no move case crosses nesting levels');
      expect(covers((c) => c.classes.contains('no-reserialize')), isTrue,
          reason: 'no case sets a placeholder value text verbatim');
      expect(covers((c) => c.classes.contains('astral')), isTrue,
          reason: 'no case covers astral-plane offsets');
    });
  });

  group('parser acceptance', () {
    for (final testCase in corpus.area('parse_accept')) {
      test('accepts ${testCase.id}', () {
        final document = parse(testCase.input);
        expect(document.toSource(), equals(testCase.input),
            reason: '${testCase.id}: the CST must reproduce its own input');

        final expected = testCase.expected;
        expect(expected['accepted'], isTrue);
        expect(document.sliceOf(document.root), equals(expected['rootText']),
            reason: '${testCase.id}: root span text');
        expect(describeMismatch(document.storedValue(), decodeTagged(expected['storedValue'])),
            isNull,
            reason: '${testCase.id}: stored value');
        expect(document.formatOf(document.root), equals(expected['formatOf']),
            reason: '${testCase.id}: format');
        expect(document.paths(), equals(expected['paths']! as List),
            reason: '${testCase.id}: pointer listing');
      });
    }
  });

  group('parser rejection', () {
    for (final testCase in corpus.area('parse_reject')) {
      test('rejects ${testCase.id}', () {
        expect(testCase.expected['accepted'], isFalse);
        expectCode(testCase.expected['errorCode'] as String?, () => parse(testCase.input));
      });
    }
  });

  group('parsed values', () {
    for (final testCase in corpus.area('values')) {
      test('value ${testCase.id}', () {
        final query = testCase.query!;
        final op = query['op']! as String;
        final pointer = query['pointer']! as String;
        final document = parse(testCase.input);
        final expected = testCase.expected;

        if (expected['ok'] != true) {
          expectCode(expected['errorCode'] as String?,
              () => runCorpusQuery(document, op, pointer));
          return;
        }
        final actual = runCorpusQuery(document, op, pointer);
        // Only stored values are tagged; texts and pointer lists are plain.
        final decoded =
            op == 'stored_value' ? decodeTagged(expected['result']) : expected['result'];
        if (decoded is List) {
          expect(actual, equals(decoded), reason: '${testCase.id}: $op $pointer');
        } else {
          expect(describeMismatch(actual, decoded), isNull,
              reason: '${testCase.id}: $op $pointer');
        }
      });
    }
  });

  group('operations produce the expected source text', () {
    for (final testCase in corpus.area('operations')) {
      test(testCase.id, () {
        final document = parse(testCase.input);
        final expected = testCase.expected;
        if (expected['ok'] != true) {
          expectCode(expected['errorCode'] as String?,
              () => applyCorpusOperation(document, testCase.operation!));
          expect(document.text, equals(testCase.input),
              reason: '${testCase.id}: a rejected edit must not change the '
                  'document it was made from');
          return;
        }
        final produced = applyCorpusOperation(document, testCase.operation!);
        final difference =
            firstByteDifference(utf8.encode(produced), utf8.encode(expected['output']! as String));
        expect(difference, isNull,
            reason: '${testCase.id}: ${difference ?? ''}\n'
                'produced: ${jsonEncode(produced)}\n'
                'expected: ${jsonEncode(expected['output'])}${testCase.divergence == null ? '' : ' (the baseline bytes, kept as evidence, differ: ${jsonEncode(testCase.baselineEvidence!['output'])})'}');

        // Postcondition of every accepted edit, asserted for every case:
        // the produced source re-parses, and the lossless tree reads it back
        // byte-for-byte. The baseline has no such check, which is how its
        // A1-A3 and A9 defects survived its own suite (SPEC_.md amendment 38).
        final reparsed = parse(produced);
        expect(reparsed.toSource(), equals(produced),
            reason: '${testCase.id}: the produced text must round-trip');

        // The untouched regions rule: where the baseline could read its own
        // result back, the produced text must decode to the same value.
        final reparse = expected['reparse'] as Map<String, Object?>?;
        if (reparse != null && reparse['ok'] == true) {
          expect(
              describeMismatch(reparsed.storedValue(), decodeTagged(reparse['storedValue'])),
              isNull,
              reason: '${testCase.id}: the produced text must reparse to the '
                  'baseline value');
          expect(reparsed.paths(), equals(reparse['paths']! as List),
              reason: '${testCase.id}: pointers of the produced text');
        }
      });
    }
  });
}
