import 'dart:collection';

import 'package:aiset_core/aiset_core.dart';
import 'package:test/test.dart';

import 'corpus_expectations.dart';

/// Replays every generated validator case against the executed baseline.
///
/// * `validator_profile` — the baseline's default `Limits` numbers.
/// * `validator_value`     — one validation run: the stored value tree
///   against a compiled descriptor, with the fixture's limits, and the
///   resulting issues.
///
/// Issues are compared as a multiset of (rule, path, severity):
/// which problems are reported and where is the contract, the order the
/// walk produced them in is not. A divergence case asserts the corrected
/// expectation and keeps the baseline result as evidence
/// (`SPEC_.md` amendment 38); the replay asserts the same
/// expectation the fixture carries.
void main() {
  final corpus = CompatCorpus.load();

  group('validator corpus integrity', () {
    test('the validator areas are present and counted in BASELINE', () {
      final counts = corpus.baseline()['counts']! as Map<String, Object?>;
      for (final area in ['validator_profile', 'validator_value']) {
        expect(counts[area], equals(corpus.area(area).length), reason: area);
        expect(counts[area]! as int, greaterThan(0), reason: area);
      }
    });

    test('the validator corpus covers what amendment 26 and 2C name', () {
      final cases = corpus.area('validator_value');
      bool covers(String tag) => cases.any((c) => c.classes.contains(tag));
      for (final type in ['string', 'int', 'number', 'bool', 'null', 'object', 'array', 'any']) {
        expect(covers(type), isTrue, reason: 'no case for type $type');
      }
      expect(covers('null'), isTrue, reason: 'no null rule case');
      expect(covers('exact-range'), isTrue, reason: 'no exact-integer case');
      expect(covers('const'), isTrue, reason: 'no const case');
      expect(covers('enum'), isTrue, reason: 'no enum case');
      expect(covers('union'), isTrue, reason: 'no union case');
      expect(covers('misplaced'), isTrue,
          reason: 'no misplaced-constraint case');
      expect(covers('key-enum'), isTrue, reason: 'no key-enum case');
      expect(covers('key-pattern'), isTrue, reason: 'no key-pattern case');
      expect(covers('pattern'), isTrue, reason: 'no pattern case');
      expect(covers('dialect'), isTrue, reason: 'no dialect case');
      for (final limit in ['depth', 'collection', 'string', 'pattern-length']) {
        expect(covers('limits') && covers(limit), isTrue,
            reason: 'no $limit boundary case');
      }
      // Every limit has an at/under/over triple.
      for (final limit in ['depth', 'collection', 'string', 'pattern-length']) {
        final tagged = cases.where((c) => c.classes.contains(limit)).toList();
        for (final boundary in ['at', 'under', 'over']) {
          expect(tagged.any((c) => c.classes.contains(boundary)), isTrue,
              reason: 'no $boundary case for the $limit limit');
        }
        expect(tagged.any((c) => c.classes.contains('accept')), isTrue,
            reason: 'no accepting case for $limit');
        expect(tagged.any((c) => c.classes.contains('rejection')), isTrue,
            reason: 'no rejecting case for $limit');
      }
    });

    test('no case lets validation mutate the stored tree it was handed', () {
      for (final testCase in corpus.area('validator_value')) {
        if (testCase.expected.containsKey('inputsUnchanged')) {
          expect(testCase.expected['inputsUnchanged'], isTrue,
              reason: '${testCase.id}: the baseline mutated an input, so the case '
                  'cannot pin immutability');
        }
      }
    });

    test('an issue message never carries the value it was produced from', () {
      // SEC-01 (`SPEC.md` amendments 6 and 26): a validated document may hold
      // a secret, and no rule may echo it back through a message. Every
      // message-producing rule is driven with one marker string in every
      // position a value can occupy (string, const, enum member,
      // pattern subject, array item, union subject, key, placeholder name,
      // out-of-range integer).
      const marker = 'Sup3rS3cretValueDoNotEcho';
      final compiled = compileDescriptor('''
{ descriptor_version: "1.0", root: { type: "object", children: {
    lenMin: { type: "string", min_length: 50 },
    lenMax: { type: "string", max_length: 1 },
    patMatch: { type: "string", pattern: "^zzz\$" },
    patLong: { type: "string", pattern: "xxxxxxxxxx" },
    patDialect: { type: "string", pattern: "(?=x)" },
    constNode: { type: "string", const: "$marker" },
    enumNode: { type: "string", enum: ["$marker"] },
    minB: { type: "number", minimum: 5 },
    maxB: { type: "number", maximum: 0.5 },
    nullN: { type: "string" },
    closed: { type: "object", children: { a: { type: "int" } } },
    keyEnum: { type: "object", key_enum: ["ok"], additional_children: { type: "int" } },
    keyPat: { type: "object", key_pattern: "^w", additional_children: { type: "int" } },
    req: { type: "object", children: { need: { type: "int", required: true } } },
    itemsMin: { type: "array", children: { type: "int" }, min_items: 5 },
    itemsMax: { type: "array", children: { type: "int" }, max_items: 1 },
    uniq: { type: "array", children: { type: "any" }, unique_items: true },
    uni: { type: "union", children_options: [ { type: "int" } ] },
    bigI: { type: "int" },
    typeErr: { type: "int" },
  } } }''');
      final stored = <String, Object?>{
        'lenMin': marker,
        'lenMax': marker,
        'patMatch': marker,
        'patLong': marker,
        'patDialect': 'xy',
        'constNode': 'other',
        'enumNode': 'other',
        'minB': 1.0,
        'maxB': 9.0,
        'nullN': null,
        'closed': {marker: 1},
        'keyEnum': {marker: 1},
        'keyPat': {marker: 1},
        'req': <String, Object?>{},
        'itemsMin': [1],
        'itemsMax': [1, 2],
        'uniq': [marker, marker],
        'uni': marker,
        'bigI': BigInt.parse('1${'0' * 40}'),
        'typeErr': marker,
      };
      final issues = validateDocument(
              stored, compiled.root,
              limits: const Limits(maxPatternLength: 5))
          .issues;
      expect(issues.map((i) => i.rule).toSet(), containsAll(const [
        'min_length', 'max_length', 'pattern', 'pattern_length',
        'const', 'enum', 'minimum', 'maximum', 'nullable', 'undeclared_field',
        'key_enum', 'key_pattern', 'required', 'min_items', 'max_items',
        'unique_items', 'union', 'exact_range', 'type',
      ]), reason: 'the walk must exercise every message-producing rule');
      for (final issue in issues) {
        expect(issue.message, isNot(contains(marker)),
            reason: '${issue.rule}: the message echoes the validated value');
      }
      // The direct entry points: the placeholder name and an
      // undeclared path are about the value, and neither
      // message may quote it.
      for (final issue in validateValue(
          TemplateRef(marker), compiled.nodeAt('/lenMin'), '/$marker')) {
        expect(issue.message, isNot(contains(marker)),
            reason: '${issue.rule}: unresolved placeholder');
      }
      for (final issue in validateValue(marker, null, '/$marker')) {
        expect(issue.message, isNot(contains(marker)),
            reason: '${issue.rule}: undeclared path');
      }
    });

    test('the limit rules report every violation kind without a value', () {
      final issues = checkLimits({
        'deep': {
          'deeper': {'deep': 1}
        },
        'big': ['a', 'b', 'c'],
        'long': 'abcdef',
      }, limits: const Limits(maxDepth: 1, maxCollectionSize: 2, maxStringLength: 3));
      expect(issues.map((i) => i.rule).toSet(),
          containsAll(const ['max_depth', 'max_collection_size', 'max_string_length']));
      for (final issue in issues) {
        expect(issue.message, isNot(contains('abcdef')),
            reason: '${issue.rule}: the message echoes the value');
      }
    });
  });

  group('limits profile', () {
    for (final testCase in corpus.area('validator_profile')) {
      test(testCase.id, () {
        final expected =
            (testCase.expected['limits']! as Map).cast<String, Object?>();
        const limits = Limits();
        expect(limits.maxFileSize, equals(expected['max_file_size']));
        expect(limits.maxBodySize, equals(expected['max_body_size']));
        expect(limits.maxDepth, equals(expected['max_depth']));
        expect(limits.maxCollectionSize, equals(expected['max_collection_size']));
        expect(limits.maxStringLength, equals(expected['max_string_length']));
        expect(limits.maxPatternLength, equals(expected['max_pattern_length']));
        expect(limits.regexBudgetMs, equals(expected['regex_timeout_ms']));
      });
    }
  });

  group('value validation', () {
    for (final testCase in corpus.area('validator_value')) {
      test(testCase.id, () {
        final expected = testCase.expected;
        final body = testCase.body;
        final descriptorSource = body['descriptor']! as String;
        final direct = body['direct'] == true;
        final limits = _limitsFrom(body['limits']);

        /// The (valid, issues) pair the fixture
        /// records, produced by the same pipeline the baseline ran.
        (bool, List<ValidationIssue>) run() {
          final compiled = compileDescriptor(descriptorSource);
          if (direct) {
            final query = body['query']! as Map<String, Object?>;
            final pointer = query['pointer'] as String?;
            final node = pointer == null ? null : compiled.nodeAt(pointer);
            // Frozen deeply: if validation wrote to the tree it was
            // handed, the mutation throws instead of passing
            // silently.
            final issues = validateValue(
              _freezeDeep(_decodeValueTag(query['value'])),
              node,
              query['path']! as String,
              present: query['present'] != false,
              limits: limits,
            );
            return (
              !issues.any((i) => i.severity == ValidationSeverity.error),
              issues,
            );
          }
          final document = parse(testCase.input);
          final stored = document.storedValue();
          final outcome = validateDocument(stored, compiled.root, limits: limits);
          // Validation reads its inputs; the parsed document
          // still yields the same stored tree and source.
          expect(describeMismatch(document.storedValue(), stored), isNull,
              reason: '${testCase.id}: validation mutated the stored tree');
          expect(document.toSource(), equals(testCase.input),
              reason: '${testCase.id}: validation changed the parsed document');
          return (outcome.valid, outcome.issues);
        }

        if (expected['ok'] != true) {
          final error = expected['errorCode'] as String?;
          if (error == null) {
            // The baseline escaped with an interpreter error and no stable
            // code. The corrected behaviour is a failure with a stable
            // code, which is what the divergence block asserts (see the
            // catalog). `.having` needs a `TypeMatcher`, so each alternative
            // is checked separately rather than the `anyOf`
            // result.
            expect(
                () => run(),
                throwsA(anyOf(
                  isA<DescriptorException>().having((e) => e.code, 'code', isNotEmpty),
                  isA<Json5SourceException>().having((e) => e.code, 'code', isNotEmpty),
                )),
                reason: '${testCase.id}: an unregistered baseline crash');
            return;
          }
          expect(() => run(),
              throwsA(anyOf(
                isA<DescriptorException>().having((e) => e.code, 'code', equals(error)),
                isA<Json5SourceException>().having((e) => e.code, 'code', equals(error)),
              )),
              reason: '${testCase.id}: expected a $error failure');
          return;
        }

        final (valid, issues) = run();
        expect(valid, equals(expected['valid']),
            reason: '${testCase.id}: valid; got ${_describe(issues)}');
        _expectSameRules(issues,
            (expected['issues']! as List).cast<Map<String, Object?>>(), testCase.id);
      });
    }
  });
}

// -- fixture plumbing --------------------------------------------------------

/// Wraps every map and list in [value] in an unmodifiable view, so a
/// write to the tree under validation throws instead of
/// passing unnoticed. Leaves (scalars, `BigInt`, placeholders, the
/// absence marker) are returned unchanged.
Object? _freezeDeep(Object? value) {
  if (value is Map) {
    return UnmodifiableMapView<String, Object?>(<String, Object?>{
      for (final entry in value.entries)
        entry.key as String: _freezeDeep(entry.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable([for (final item in value) _freezeDeep(item)]);
  }
  return value;
}

Limits _limitsFrom(Object? raw) {
  if (raw is! Map) return Limits.defaultProfile;
  final limits = raw.cast<String, Object?>();
  int? read(String key) => limits[key] == null ? null : limits[key]! as int;
  return Limits(
    maxDepth: read('max_depth') ?? Limits.defaultProfile.maxDepth,
    maxCollectionSize:
        read('max_collection_size') ?? Limits.defaultProfile.maxCollectionSize,
    maxStringLength:
        read('max_string_length') ?? Limits.defaultProfile.maxStringLength,
    maxPatternLength:
        read('max_pattern_length') ?? Limits.defaultProfile.maxPatternLength,
  );
}

/// The mirror of the driver's fixture-value decoder: a tagged map
/// for a placeholder or the absence marker, plain JSON
/// otherwise.
Object? _decodeValueTag(Object? tagged) {
  if (tagged is Map) {
    final map = tagged.cast<String, Object?>();
    if (map['missing'] == true) return resolverMissing;
    final template = map['template'];
    if (template is Map) {
      final ref = template.cast<String, Object?>();
      return TemplateRef(ref['name']! as String, ref['default'] as String?);
    }
    return <String, Object?>{
      for (final entry in map.entries) entry.key: _decodeValueTag(entry.value),
    };
  }
  if (tagged is List) return [for (final item in tagged) _decodeValueTag(item)];
  return tagged;
}

void _expectSameRules(
    List<ValidationIssue> actual, List<Map<String, Object?>> expected, String reason) {
  expect(actual.length, equals(expected.length),
      reason: '$reason: ${_describe(actual)}');
  final remaining = [...expected];
  for (final issue in actual) {
    final match = remaining.indexWhere((candidate) =>
        candidate['rule'] == issue.rule &&
        candidate['path'] == issue.path &&
        (!candidate.containsKey('severity') ||
            candidate['severity'] == issue.severity.label) &&
        (!candidate.containsKey('hasMessage') ||
            (candidate['hasMessage']! as bool) == issue.message.isNotEmpty));
    if (match < 0) {
      fail('$reason: unexpected issue ${issue.rule} at ${issue.path}; '
          'expected ${_renderExpected(expected)}');
    }
    remaining.removeAt(match);
  }
  if (remaining.isNotEmpty) {
    fail('$reason: missing issues ${_renderExpected(remaining)}; '
        'got ${_describe(actual)}');
  }
}

String _describe(List<ValidationIssue> issues) =>
    '[${issues.map((i) => '${i.rule}@${i.path}').join(', ')}]';

String _renderExpected(List<Map<String, Object?>> expected) =>
    '[${expected.map((e) => '${e['rule']}@${e['path']}').join(', ')}]';
