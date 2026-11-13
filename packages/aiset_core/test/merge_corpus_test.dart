import 'dart:collection';
import 'dart:convert';

import 'package:aiset_core/aiset_core.dart';
import 'package:test/test.dart';

import 'corpus_expectations.dart';

/// Replays every generated merge and revision case against the Dart
/// implementation.
///
/// * `merge_base` / `merge_update` — the result of merging two stored
///   trees in the two precedence modes of `SPEC.md` amendment 7.
/// * `merge_immutability` — whether the merge left its inputs alone and
///   whether the result is a tree of its own.
/// * `revision_compute` — the source and descriptor revision of a text.
///
/// A case with a `divergence` block asserts the corrected expectation and
/// keeps the baseline's own result under `baselineEvidence`
/// (`SPEC_.md` amendment 38); the replay asserts the same expectation the
/// fixture carries, which is what turns a registered
/// divergence into a proof rather than a note.
void main() {
  final corpus = CompatCorpus.load();

  group('merge and revision corpus integrity', () {
    test('the merge and revision areas are present and counted in BASELINE', () {
      final counts = corpus.baseline()['counts']! as Map<String, Object?>;
      for (final area in const [
        'merge_base',
        'merge_update',
        'merge_immutability',
        'pipeline_revisions',
      ]) {
        expect(counts[area], equals(corpus.area(area).length), reason: area);
        expect(counts[area]! as int, greaterThan(0), reason: area);
      }
    });

    test('the merge corpus covers what amendment 7 and MRG-01 name', () {
      final cases = [...corpus.area('merge_base'), ...corpus.area('merge_update')];
      bool covers(String tag) => cases.any((c) => c.classes.contains(tag));
      for (final kind in ['scalar', 'object', 'array', 'null', 'placeholder']) {
        expect(covers(kind), isTrue, reason: 'no merge case for a $kind value');
      }
      expect(covers('type-mismatch'), isTrue, reason: 'no type-conflict case');
      expect(covers('nested'), isTrue, reason: 'no recursive merge case');
      expect(covers('new-key') || covers('add'), isTrue,
          reason: 'no update-only-key case');
      expect(covers('keep'), isTrue, reason: 'no base-only-key case');
      expect(covers('layering'), isTrue, reason: 'no plugin-defaults case');
      expect(covers('equal'), isTrue, reason: 'no equal-value case');
      // Both precedence modes are pinned for the same inputs.
      final baseIds = corpus.area('merge_base').map((c) => c.id).toSet();
      for (final testCase in corpus.area('merge_update')) {
        final counterpart =
            testCase.id.replaceAll(RegExp(r'_update$'), '_base');
        expect(baseIds, contains(counterpart),
            reason: '${testCase.id} has no prefer-base counterpart');
      }
    });

    test('the revision corpus covers the byte-level rules', () {
      final cases = corpus.area('pipeline_revisions');
      bool covers(String tag) => cases.any((c) => c.classes.contains(tag));
      for (final tag in const ['source', 'descriptor', 'bom', 'crlf', 'astral', 'unicode',
        'comments', 'order', 'whitespace', 'newline']) {
        expect(covers(tag), isTrue, reason: 'no $tag revision case');
      }
    });
  });

  group('merge result', () {
    for (final area in const ['merge_base', 'merge_update']) {
      for (final testCase in corpus.area(area)) {
        test(testCase.id, () {
          final expected = testCase.expected;
          if (expected['ok'] != true) {
            final code = expected['errorCode'] as String?;
            expect(
              () => mergeLabeled(
                decodeTagged(testCase.body['base']! as Map<String, Object?>),
                decodeTagged(testCase.body['update']! as Map<String, Object?>),
                preference: testCase.body['prefer']! as String,
              ),
              code == null
                  ? throwsA(anyOf(
                      isA<MergePreferenceError>(),
                      isA<Json5SourceException>(),
                    ))
                  : throwsA(isA<MergePreferenceError>()
                      .having((e) => e.code, 'code', equals(code))),
              reason: '${testCase.id}: expected a $code refusal',
            );
            return;
          }
          final base = decodeTagged(testCase.body['base']! as Map<String, Object?>);
          final update = decodeTagged(testCase.body['update']! as Map<String, Object?>);
          final merged = mergeLabeled(base, update,
              preference: testCase.body['prefer']! as String);
          expect(
            describeMismatch(merged, decodeTaggedTree(expected['merged'])),
            isNull,
            reason: '${testCase.id}: ${testCase.description}',
          );
          // The fixture's own immutability record, asserted rather than
          // trusted: a merge that wrote to its inputs cannot pin MRG-01.
          expect(expected['inputsUnchanged'], isTrue, reason: testCase.id);
        });
      }
    }
  });

  group('merge purity', () {
    for (final testCase in corpus.area('merge_immutability')) {
      test(testCase.id, () {
        final base = decodeTagged(testCase.body['base']! as Map<String, Object?>);
        final update = decodeTagged(testCase.body['update']! as Map<String, Object?>);
        final frozenBase = _freezeDeep(base);
        final frozenUpdate = _freezeDeep(update);
        final preference = testCase.body['prefer']! as String;
        final merged = mergeLabeled(frozenBase, frozenUpdate, preference: preference);
        final expected = testCase.expected;

        // The inputs are unchanged, structurally. Writing to a
        // frozen input would throw, which is the same guarantee
        // the corpus records for the baseline.
        expect(describeMismatch(frozenBase, decodeTaggedTree(testCase.body['base']! as Map<String, Object?>)),
            isNull,
            reason: '${testCase.id}: the merge changed its base input');
        expect(
            describeMismatch(frozenUpdate,
                decodeTaggedTree(testCase.body['update']! as Map<String, Object?>)),
            isNull,
            reason: '${testCase.id}: the merge changed its update input');
        expect(expected['inputsUnchanged'], isTrue, reason: testCase.id);

        // The Dart result shares no mutable node with either input,
        // proven by object identity on the tree this very call produced.
        final baseIds = _identitySet(base);
        final updateIds = _identitySet(update);
        final shared = [
          for (final node in _mutableNodes(merged))
            if (baseIds.contains(identityHashCode(node)) ||
                updateIds.contains(identityHashCode(node)))
              node,
        ];
        expect(shared, isEmpty,
            reason: '${testCase.id}: the result aliases an input subtree, so a '
                'write through it would change a document the caller still holds '
                '(SPEC.md amendment 7 requires a pure merge)');
        // And the fixture's expectation, which for a divergence case
        // is the corrected answer and for an ordinary case the baseline's.
        expect(expected['aliased'], isFalse, reason: testCase.id);
        expect(expected['sharesBaseNodes'], equals(0), reason: testCase.id);
        expect(expected['sharesUpdateNodes'], equals(0), reason: testCase.id);
      });
    }
  });

  group('revisions', () {
    for (final testCase in corpus.area('pipeline_revisions')) {
      test(testCase.id, () {
        final expected = testCase.expected;
        expect(expected['ok'], isTrue, reason: testCase.id);
        final text = testCase.input;
        if (expected['op'] == 'source') {
          expect(sourceRevisionOfText(text), equals(expected['revision']),
              reason: '${testCase.id}: ${testCase.description}');
          // The revision is a function of the bytes, so the
          // recorded UTF-8 and UTF-16 lengths are part of what pins it.
          expect(utf8.encode(text).length, equals(expected['utf8Length']),
              reason: '${testCase.id}: UTF-8 length');
          expect(text.length, equals(expected['utf16Length']),
              reason: '${testCase.id}: UTF-16 length');
          expect(text.startsWith('\uFEFF'), equals(expected['hasBom']),
              reason: '${testCase.id}: byte order mark');
        } else {
          final compiled = compileDescriptor(text);
          expect(compiled.revision, equals(expected['revision']),
              reason: '${testCase.id}: ${testCase.description}');
          expect(sourceRevisionOfText(text), equals(expected['bytesRevision']),
              reason: '${testCase.id}: a descriptor revision is the revision of its bytes');
        }
      });
    }
  });
}

// -- helpers -------------------------------------------------------------------

/// The value tag of [value], in the encoding the corpus uses.
///
/// Dart reads `1` as an `int` and `1.0` as a `double`, and
/// a very large integer as a `BigInt`, so the kind is recorded the
/// same way the driver records the baseline's.
Map<String, Object?> encodeTagged(Object? value) => switch (value) {
      null => const {'k': 'null'},
      final TemplateRef t => {
          'k': 'template',
          'v': {'name': t.name, 'default': t.defaultText},
        },
      final bool b => {'k': 'bool', 'v': b},
      final int i => {'k': 'int', 'v': '$i'},
      final BigInt b => {'k': 'int', 'v': '$b'},
      final double d => {'k': 'double', 'v': d},
      final String s => {'k': 'string', 'v': s},
      final Map<Object?, Object?> m => {
          'k': 'object',
          'v': [
            for (final entry in m.entries) [entry.key, encodeTagged(entry.value)],
          ],
        },
      final List<Object?> l => {'k': 'array', 'v': [for (final i in l) encodeTagged(i)]},
      _ => throw StateError('unencodable value: ${value.runtimeType}'),
    };

/// The identity hashes of every mutable container reachable from [value].
Set<int> _identitySet(Object? value) =>
    {for (final node in _mutableNodes(value)) identityHashCode(node)};

List<Object> _mutableNodes(Object? value) {
  final out = <Object>[];
  void walk(Object? node) {
    if (node is Map<Object?, Object?>) {
      out.add(node);
      for (final item in node.values) {
        walk(item);
      }
    } else if (node is List<Object?>) {
      out.add(node);
      for (final item in node) {
        walk(item);
      }
    }
  }

  walk(value);
  return out;
}

/// Wraps every map and list in an unmodifiable view, so a merge that wrote
/// to the tree it was handed throws instead of passing silently.
Object? _freezeDeep(Object? value) {
  if (value is Map) {
    return UnmodifiableMapView<String, Object?>(<String, Object?>{
      for (final entry in value.entries) entry.key! as String: _freezeDeep(entry.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable([for (final item in value) _freezeDeep(item)]);
  }
  return value;
}
