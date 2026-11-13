import 'package:aiset_core/aiset_core.dart';
import 'package:test/test.dart';

import 'corpus_expectations.dart';

/// Replays every generated resolver case against the Dart resolver.
///
/// * `resolver_lookup`    — the precedence chain and `presence`.
/// * `resolver_text`        — substitution inside a string.
/// * `resolver_effective`   — a whole effective snapshot with defaults,
///   conversion, provenance and the six leaf states.
///
/// Only the fields a fixture actually records are compared, so a corrected
/// case can pin the part it is about without restating the rest.
void main() {
  final corpus = CompatCorpus.load();

  group('resolver corpus integrity', () {
    test('the resolver areas are present and counted in BASELINE', () {
      final counts = corpus.baseline()['counts']! as Map<String, Object?>;
      for (final area in [
        'resolver_lookup',
        'resolver_text',
        'resolver_effective',
      ]) {
        expect(counts[area], equals(corpus.area(area).length), reason: area);
        expect(counts[area]! as int, greaterThan(0), reason: area);
      }
    });

    test('the resolver corpus covers what amendment 6 names', () {
      bool any(List<CompatCase> cases, String tag) =>
          cases.any((c) => c.classes.contains(tag));
      final lookup = corpus.area('resolver_lookup');
      final text = corpus.area('resolver_text');
      final effective = corpus.area('resolver_effective');
      expect(any(lookup, 'precedence'), isTrue, reason: 'no precedence case');
      expect(any(lookup, 'inline-default'), isTrue, reason: 'no inline fallback case');
      expect(any(text, 'single-pass'), isTrue, reason: 'no single-pass case');
      expect(any(text, 'reject'), isTrue, reason: 'no malformed reference case');
      expect(any(text, 'provenance'), isTrue, reason: 'no provenance case');
      for (final kind in ['int', 'number', 'bool', 'string']) {
        expect(any(effective, 'convert') && effective.any((c) => c.classes.contains(kind)),
            isTrue,
            reason: 'no conversion case for $kind');
      }
      expect(any(effective, 'env-allowed'), isTrue, reason: 'no env.allowed case');
      expect(any(effective, 'six-states'), isTrue, reason: 'no leaf-state case');
      expect(any(effective, 'missing'), isTrue, reason: 'no MISSING case');
      expect(any(effective, 'default'), isTrue, reason: 'no default case');
      expect(any(effective, 'exact-range'), isTrue,
          reason: 'no bounded-integer conversion case');
    });

    test('no effective case lets resolution mutate its inputs', () {
      for (final testCase in corpus.area('resolver_effective')) {
        if (testCase.expected.containsKey('inputsUnchanged')) {
          expect(testCase.expected['inputsUnchanged'], isTrue,
              reason: '${testCase.id}: the baseline mutated an input, '
                  'so the case cannot pin immutability');
        }
      }
    });
  });

  group('variable lookup', () {
    for (final testCase in corpus.area('resolver_lookup')) {
      test(testCase.id, () {
        final resolver = readResolver(testCase);
        final query = testCase.query!;
        Object? actual;
        if (query['op'] == 'lookup') {
          final lookup = resolver.lookup(query['name']! as String,
              inlineDefault: query.containsKey('inlineDefault')
                  ? query['inlineDefault'] as String?
                  : null);
          actual = {'value': lookup.value, 'source': lookup.source.label};
        } else {
          actual = {
            'presence': resolver.presence((query['names']! as List).cast<String>()),
          };
        }
        expect(describeMismatch(actual, decodeTaggedTree(testCase.expected['result'])), isNull,
            reason: testCase.id);
      });
    }
  });

  group('placeholder substitution', () {
    for (final testCase in corpus.area('resolver_text')) {
      test(testCase.id, () {
        final resolver = readResolver(testCase);
        final issues = <ResolutionIssue>[];
        final provenance = <String, Provenance>{};
        final output = resolveText(
          testCase.input,
          resolver: resolver,
          path: testCase.body['path']! as String,
          issues: issues,
          provenance: provenance,
        );
        final expected = testCase.expected;
        expect(expected['ok'], isTrue, reason: testCase.id);
        expect(output, equals(expected['output']), reason: testCase.id);
        expectSameRules(issues, expected['issues'] as List?, testCase.id);
        expect(
            describeMismatch(
                {for (final e in provenance.entries) e.key: e.value.toMap()},
                decodeTaggedTree(expected['provenance'])),
            isNull,
            reason: '${testCase.id}: provenance');
      });
    }
  });

  group('effective snapshot', () {
    for (final testCase in corpus.area('resolver_effective')) {
      test(testCase.id, () {
        final resolver = readResolver(testCase);
        final descriptor = compileDescriptor(testCase.body['descriptor']! as String);
        final root = descriptor.root;
        final query = testCase.query;
        final expected = testCase.expected;

        final ResolutionResult result;
        if (query != null && query['op'] == 'effective_at') {
          final stored = query['stored'];
          result = effectiveAt(
            stored == 'MISSING' ? resolverMissing : stored,
            descriptor.nodeAt(query['pointer']! as String),
            resolver,
            path: query['path']! as String,
          );
        } else {
          final document = parse(testCase.input);
          final stored = document.storedValue();
          result = buildEffective(stored, root, resolver);
          // Resolution must not touch the tree it was handed, and the
          // document it came from.
          expect(document.storedValue(), equals(document.storedValue()),
              reason: '${testCase.id}: re-deriving the stored tree changed');
          expect(document.toSource(), equals(testCase.input),
              reason: '${testCase.id}: the parsed document changed');
        }

        expect(
            describeMismatch(result.value, decodeTaggedTree(expected['effective'])),
            isNull,
            reason: '${testCase.id}: effective value');
        expectSameRules(result.issues, expected['issues'] as List?, testCase.id);
        expect(
            describeMismatch(
                {for (final e in result.provenance.entries) e.key: e.value.toMap()},
                decodeTaggedTree(expected['provenance'])),
            isNull,
            reason: '${testCase.id}: provenance');
      });
    }
  });
}

/// The resolver the case was executed with. Every layer is named
/// explicitly, so no case can read the machine.
Resolver readResolver(CompatCase testCase) {
  final layers = testCase.body['layers']! as Map<String, Object?>;
  Map<String, String> read(String key) => {
        for (final entry in (layers[key]! as Map<String, Object?>).entries)
          entry.key: entry.value! as String,
      };
  return Resolver(
      overrides: read('overrides'),
      environment: read('environ'),
      dotenv: read('dotenv'));
}

/// Compares resolver issues as a set of (rule, path, severity), ignoring
/// order and any field the fixture does not record.
void expectSameRules(
    List<ResolutionIssue> actual, List<Object?>? expected, String reason) {
  if (expected == null) return;
  expect(actual.length, equals(expected.length),
      reason: '$reason: ${actual.map((i) => i.rule).toList()}');
  final remaining = [...expected];
  for (final issue in actual) {
    final match = remaining.indexWhere((candidate) {
      final e = candidate! as Map<String, Object?>;
      return (!e.containsKey('rule') || e['rule'] == issue.rule) &&
          (!e.containsKey('path') || e['path'] == issue.path) &&
          (!e.containsKey('severity') || e['severity'] == issue.severity.label) &&
          (!e.containsKey('hasMessage') ||
              (e['hasMessage']! as bool) == issue.message.isNotEmpty);
    });
    if (match < 0) {
      fail('$reason: unexpected issue $issue; expected $expected');
    }
    remaining.removeAt(match);
  }
  if (remaining.isNotEmpty) {
    fail('$reason: missing issues $remaining; got $actual');
  }
}
