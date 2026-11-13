import 'package:aiset_core/aiset_core.dart';
import 'package:test/test.dart';

import 'corpus_expectations.dart';

/// Replays every generated descriptor case against the Dart compiler.
///
/// * `descriptor_validate`  — the diagnostics [validateDescriptor]
///   produces for the same source.
/// * `descriptor_compile`         — the compiled tree, its revision and
///   envelope values, or the stable code of the rejection.
/// * `descriptor_semantics`       — one query over a compiled descriptor.
///
/// Diagnostics are compared as a set of (code, severity, path, position):
/// which properties are reported and where is the contract, the order the rules
/// happened to run in is not.
void main() {
  final corpus = CompatCorpus.load();

  group('descriptor corpus integrity', () {
    test('the descriptor areas are present and counted in BASELINE', () {
      final counts = corpus.baseline()['counts']! as Map<String, Object?>;
      for (final area in [
        'descriptor_validate',
        'descriptor_compile',
        'descriptor_semantics',
      ]) {
        expect(counts[area], equals(corpus.area(area).length), reason: area);
        expect(counts[area]! as int, greaterThan(0), reason: area);
      }
    });

    test('the descriptor corpus covers the areas amendment 24 names', () {
      final validate = corpus.area('descriptor_validate');
      bool covers(bool Function(CompatCase) test) => validate.any(test);
      expect(covers((c) => c.classes.contains('accept')), isTrue,
          reason: 'no accepted descriptor case');
      expect(covers((c) => c.classes.contains('rejection')), isTrue,
          reason: 'no rejected descriptor case');
      expect(covers((c) => c.classes.contains('default')), isTrue,
          reason: 'no default case');
      expect(covers((c) => c.classes.contains('unknown-metadata')), isTrue,
          reason: 'no unknown-metadata case');
      expect(covers((c) => c.classes.contains('typedef')), isTrue,
          reason: 'no typedef case');
      expect(covers((c) => c.classes.contains('constraint-by-type')), isTrue,
          reason: 'the constraint-by-type table is not covered');
      expect(
          corpus.area('descriptor_compile').any((c) => c.classes.contains('fragment')),
          isTrue,
          reason: 'no fragment case');
    });

    test('the constraint-by-type table is covered for every type and constraint', () {
      final cases = corpus
          .area('descriptor_validate')
          .where((c) => c.classes.contains('constraint-by-type'))
          .toList();
      const types = [
        'string', 'int', 'number', 'bool', 'null', 'array', 'any', 'object',
      ];
      const constraints = [
        'min_length', 'max_length', 'pattern', 'minimum', 'maximum', //
        'min_items', 'max_items', 'unique_items',
      ];
      for (final type in types) {
        for (final constraint in constraints) {
          expect(
              cases.any((c) =>
                  c.classes.contains(type) && c.classes.contains(constraint)),
              isTrue,
              reason: 'no case for $constraint on type $type');
        }
      }
    });
  });

  group('descriptor diagnostics', () {
    for (final testCase in corpus.area('descriptor_validate')) {
      test(testCase.id, () {
        final strict = testCase.body['mode'] == 'strict';
        final diagnostic =
            validateDescriptor(testCase.input, strict: strict);
        final expected = testCase.expected;
        expect(diagnostic.valid, equals(expected['valid']),
            reason: '${testCase.id}: valid; issues '
                '${diagnostic.issues.map((i) => i.code).toList()}');
        expectSameIssues(diagnostic.issues,
            (expected['issues']! as List).cast<Map<String, Object?>>(),
            testCase.id);
      });
    }
  });

  group('descriptor compilation', () {
    for (final testCase in corpus.area('descriptor_compile')) {
      test(testCase.id, () {
        final expected = testCase.expected;
        final request = testCase.request;
        CompiledDescriptor compile() => compileDescriptor(
              testCase.input,
              strict: request['strict'] == true,
              typedefSources: [
                for (final source in (request['typedefSources'] as List? ?? const []))
                  source! as String,
              ],
              fragments: [
                for (final fragment
                    in (request['fragments'] as List? ?? const []))
                  DescriptorFragment(
                      source: fragment!['source']! as String,
                      mount: fragment['mount']! as String),
              ],
            );

        if (expected['ok'] != true) {
          expectDescriptorCode(expected['errorCode'] as String?, compile);
          return;
        }
        final compiled = compile();
        expect(compiled.revision, equals(expected['revision']),
            reason: '${testCase.id}: revision');
        expect(compiled.project, equals(expected['project']),
            reason: '${testCase.id}: project');
        expect(compiled.configVersion, equals(expected['configVersion']),
            reason: '${testCase.id}: config_version');
        expect(
            describeMismatch(
                projectShape(compiled.root),
                decodeTaggedTree(expected['shape']! as Map<String, Object?>)),
            isNull,
            reason: '${testCase.id}: compiled node tree');
      });
    }
  });

  group('descriptor semantics', () {
    for (final testCase in corpus.area('descriptor_semantics')) {
      test(testCase.id, () {
        final expected = testCase.expected;
        final query = testCase.query!;
        final request = testCase.request;
        Object? run() {
          final compiled = compileDescriptor(
            testCase.input,
            strict: request['strict'] == true,
            typedefSources: [
              for (final source
                  in (request['typedefSources'] as List? ?? const []))
                source! as String,
            ],
            fragments: [
              for (final fragment in (request['fragments'] as List? ?? const []))
                DescriptorFragment(
                    source: fragment!['source']! as String,
                    mount: fragment!['mount']! as String),
            ],
          );
          switch (query['op']! as String) {
            case 'revision':
              return compiled.revision;
            case 'has_node':
              return compiled.hasNode(query['pointer']! as String);
            case 'node_field':
              final node = compiled.nodeAt(query['pointer']! as String);
              if (node == null) {
                throw StateError('no node at ${query['pointer']}');
              }
              return nodeField(node, query['field']! as String);
            default:
              final node = compiled.nodeAt(query['pointer']! as String);
              return node == null ? null : {'node': projectShape(node)};
          }
        }

        if (expected['ok'] != true) {
          expectDescriptorCode(expected['errorCode'] as String?, run);
          return;
        }
        expect(describeMismatch(run(), decodeTaggedTree(expected['result'])), isNull,
            reason: '${testCase.id}: ${query['op']} ${query['pointer']}');
      });
    }
  });
}

/// The observable meaning of one compiled node, in the same shape the corpus
/// records.
Map<String, Object?> projectShape(DescriptorNode node) => {
      'type': node.type,
      'path': node.path,
      'label': node.label,
      'fieldName': node.fieldName,
      'typedefName': node.typedefName,
      'description': node.description?.defaultText,
      'title': node.title?.defaultText,
      'required': node.required,
      'nullable': node.nullable,
      'hasDefault': node.hasDefault,
      'hasConst': node.hasConst,
      'default': node.defaultValue,
      'enum': node.enumValues,
      'const': node.hasConst ? node.constValue : null,
      'minimum': node.minimum,
      'maximum': node.maximum,
      'minLength': node.minLength,
      'maxLength': node.maxLength,
      'pattern': node.pattern,
      'minItems': node.minItems,
      'maxItems': node.maxItems,
      'uniqueItems': node.uniqueItems,
      'keyPattern': node.keyPattern,
      'keyEnum': node.keyEnum,
      'envAllowed': node.envAllowed,
      'envConvert': node.envConvert,
      'secret': node.secret,
      'readOnly': node.readOnly,
      'apply': node.apply,
      'validators': node.validators,
      'ui': node.ui,
      'helper': node.helper,
      'hooks': node.hooks,
      'children': node.children == null
          ? null
          : [
              for (final entry in node.children!.entries)
                [entry.key, entry.value.label, projectShape(entry.value)],
            ],
      'additionalChildren':
          node.additionalChildren == null ? null : projectShape(node.additionalChildren!),
      'itemNode': node.itemNode == null ? null : projectShape(node.itemNode!),
      'optionNodes': node.optionNodes == null
          ? null
          : [for (final option in node.optionNodes!) projectShape(option)],
    };

/// One attribute of a compiled node, as a `node_field` query reads it.
Object? nodeField(DescriptorNode node, String field) => switch (field) {
      'type' => node.type,
      'label' => node.label,
      'fieldName' => node.fieldName,
      'typedefName' => node.typedefName,
      'description' => node.description?.defaultText,
      'title' => node.title?.defaultText,
      'required' => node.required,
      'nullable' => node.nullable,
      'hasDefault' => node.hasDefault,
      'default' => node.defaultValue,
      'enum' => node.enumValues,
      'const' => node.constValue,
      'minimum' => node.minimum,
      'maximum' => node.maximum,
      'minLength' => node.minLength,
      'maxLength' => node.maxLength,
      'pattern' => node.pattern,
      'minItems' => node.minItems,
      'maxItems' => node.maxItems,
      'uniqueItems' => node.uniqueItems,
      'keyPattern' => node.keyPattern,
      'keyEnum' => node.keyEnum,
      'envAllowed' => node.envAllowed,
      'envConvert' => node.envConvert,
      'secret' => node.secret,
      'readOnly' => node.readOnly,
      'apply' => node.apply,
      'validators' => node.validators,
      'ui' => node.ui,
      'helper' => node.helper,
      'hooks' => node.hooks,
      _ => throw StateError('unknown node field: $field'),
    };

/// Asserts that [body] fails with the stable error [code], or - when the
/// baseline escaped with an interpreter error that carries no code - that it
/// fails at all.
void expectDescriptorCode(String? code, void Function() body) {
  if (code == null) {
    expect(body, throwsA(anyOf(isA<DescriptorException>(), isA<Json5ParseException>())));
    return;
  }
  expect(
    body,
    throwsA(anyOf(
      isA<DescriptorException>().having((e) => e.code, 'code', equals(code)),
      isA<Json5SourceException>().having((e) => e.code, 'code', equals(code)),
    )),
  );
}
