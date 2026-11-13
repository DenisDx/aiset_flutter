import 'dart:io';

import 'package:aiset_core/aiset_core.dart';
import 'package:test/test.dart';

/// The resolver contract that the executed baseline can pin
/// and the parts of `SPEC.md` amendments 2 and 6 that only this
/// product has (no ambient environment, immutability).
void main() {
  DescriptorNode rootOf(String descriptorSource) =>
      compileDescriptor(descriptorSource).root;

  const envDescriptor = '{ descriptor_version: "1.0", root: { type: "object", children: {'
      ' s: { type: "string", env: { allowed: true } },'
      ' i: { type: "int", env: { allowed: true, convert: "int" } },'
      ' b: { type: "bool", env: { allowed: true, convert: "bool" } },'
      ' plain: { type: "string" } } } }';

  const defaultedDescriptor =
      '{ descriptor_version: "1.0", root: { type: "object", children: {'
      ' a: { type: "string", default: "fb" } } } }';

  group('no ambient environment', () {
    test('a name the host did not inject resolves to empty, '
        'not to the machine', () {
      // PATH exists in every real process environment. If the
      // resolver ever read the machine, this would return that value.
      final result = resolveText(r'${PATH}', resolver: const Resolver());
      expect(result, isEmpty,
          reason: 'the resolver read the process environment');
    });

    test('HOME and the host name are not reachable either', () {
      for (final name in ['HOME', 'USER', 'HOSTNAME', 'PWD', 'AISET_PYTHON_BASELINE']) {
        expect(resolveText('\${$name}', resolver: const Resolver()), isEmpty,
            reason: '\$$name leaked from the machine');
      }
    });

    test('the resolver library never imports the platform', () {
      // A behavioural test can only show that a name is absent
      // today. This shows the code cannot read the
      // environment at all.
      final dir = Directory('lib/src/resolver');
      expect(dir.existsSync(), isTrue, reason: 'resolver sources missing');
      final files = dir.listSync(recursive: true).whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      expect(files, isNotEmpty);
      for (final file in files) {
        final source = file.readAsStringSync();
        expect(source, isNot(contains("import 'dart:io'")),
            reason: '${file.path} imports dart:io');
        expect(source, isNot(contains('Platform.environment')),
            reason: '${file.path} reads the process environment');

      }
    });

    test('the environment layer is injected, never defaulted', () {
      const resolver = Resolver(environment: {'PATH': 'injected'});
      expect(resolver.lookup('PATH').value, equals('injected'));
      expect(const Resolver().lookup('PATH').source,
          equals(VariableSource.empty));
    });
  });

  group('single pass', () {
    test('a resolved value is never scanned again', () {
      const resolver = Resolver(overrides: {'A': r'${B}', 'B': 'deep'});
      expect(resolveText(r'${A}', resolver: resolver), equals(r'${B}'));
    });

    test('an environment value cannot inject structure', () {
      final root = rootOf(envDescriptor);
      final result = buildEffective(
        {'s': r'${INJECT}'},
        root,
        const Resolver(overrides: {'INJECT': '{"plain": "injected"}'}),
      );
      expect((result.value! as Map<String, Object?>)['s'],
          equals('{"plain": "injected"}'));
      expect((result.value! as Map<String, Object?>).keys, equals(['s']),
          reason: 'the injected text must not become a member');
    });

    test('a value containing a placeholder does not extend the walk', () {
      final root = rootOf(envDescriptor);
      final result = buildEffective(
        {'s': r'${A}', 'plain': r'${B}'},
        root,
        const Resolver(overrides: {'A': r'${B}', 'B': 'never'}),
      );
      final effective = result.value! as Map<String, Object?>;
      expect(effective['s'], equals(r'${B}'));
      expect(effective['plain'], equals(r'${B}'),
          reason: 'a node without env.allowed keeps its own text');
    });
  });

  group('precedence', () {
    test('override beats environment beats dotenv beats inline default', () {
      const resolver = Resolver(
          overrides: {'V': 'o'}, environment: {'V': 'e'}, dotenv: {'V': 'd'});
      expect(resolver.lookup('V', inlineDefault: 'i').value, equals('o'));
      expect(const Resolver(environment: {'V': 'e'}, dotenv: {'V': 'd'})
          .lookup('V', inlineDefault: 'i')
          .value, equals('e'));
      expect(const Resolver(dotenv: {'V': 'd'}).lookup('V', inlineDefault: 'i').value,
          equals('d'));
      expect(const Resolver().lookup('V', inlineDefault: 'i').value, equals('i'));
      expect(const Resolver().lookup('V').value, isEmpty);
    });

    test('an empty value continues the chain only when a '
        'fallback exists', () {
      const resolver =
          Resolver(overrides: {'V': ''}, environment: {'V': 'e'});
      expect(resolver.lookup('V', inlineDefault: 'i').source,
          equals(VariableSource.environment));
      // Without a fallback there is nothing to compare against, so
      // the empty value at the top of the chain is the answer.
      expect(resolver.lookup('V').source, equals(VariableSource.override));
      expect(resolver.lookup('V').value, isEmpty);
      expect(const Resolver(overrides: {'V': ''}).lookup('V').source,
          equals(VariableSource.override));
      expect(
          const Resolver(overrides: {'V': ''})
              .lookup('V', inlineDefault: 'i')
              .source,
          equals(VariableSource.inlineDefault));
    });

    test('presence never exposes values', () {
      const resolver = Resolver(
          environment: {'SET': 'secret-value', 'BLANK': ''}, dotenv: {'D': 'x'});
      final presence = resolver.presence(['SET', 'BLANK', 'D', 'NOPE', 'bad name']);
      expect(presence, equals({'SET': true, 'BLANK': true, 'D': true, 'NOPE': false}));
      expect(presence.values.join(), isNot(contains('secret-value')));
    });
  });

  group('conversion', () {
    Object? resolveOne(String field, String value) {
      final result = buildEffective({
        field: r'${N}',
      }, rootOf(envDescriptor), Resolver(environment: {'N': value}));
      return (result.value! as Map<String, Object?>)[field];
    }

    test('int accepts ASCII decimal only', () {
      expect(resolveOne('i', '42'), equals(42));
      expect(resolveOne('i', '+42'), equals(42));
      expect(resolveOne('i', '-0'), equals(0));
      expect(resolveOne('i', ' 7 '), equals(7));
      expect(resolveOne('i', '1.0'), isNull);
      expect(resolveOne('i', '0x10'), isNull);
      expect(resolveOne('i', '1_0'), isNull,
          reason: 'Python literal grouping is not a config number');
      expect(resolveOne('i', '\u0662\u0660'), isNull,
          reason: 'the accepted digit set is ASCII (docs/grammars.md)');
    });

    test('int refuses values beyond the exact range', () {
      expect(resolveOne('i', '9007199254740991'), equals(9007199254740991));
      expect(resolveOne('i', '9007199254740992'), isNull);
      expect(resolveOne('i', '-9007199254740992'), isNull);
      final issues = buildEffective({
        'i': '\${N}'
      }, rootOf(envDescriptor), const Resolver(environment: {'N': '9007199254740992'})).issues;
      expect(issues.single.rule, equals('env_conversion'));
      expect(issues.single.path, equals('/i'));
    });

    test('number accepts decimal and exponent, refuses non-finite', () {
      expect(resolveOne('s', 'x'), equals('x'));
      expect(resolveOne('b', 'true'), isTrue);
      expect(resolveOne('b', 'false'), isFalse);
      expect(resolveOne('b', 'TRUE'), isNull);
      expect(resolveOne('b', '1'), isNull);
    });

    test('a conversion issue never carries the value', () {
      final result = buildEffective({
        'i': '\${SECRET}'
      }, rootOf(envDescriptor), const Resolver(environment: {'SECRET': 'hunter2'}));
      expect(result.issues.single.message, isNot(contains('hunter2')));
      expect(result.provenance['/i']!.toMap().containsValue('hunter2'), isFalse);
    });
  });

  group('the six leaf states', () {
    test('absent is the only state a default replaces', () {
      final root = rootOf(defaultedDescriptor);
      Map<String, Object?> effectiveOf(Object? stored) =>
          buildEffective(stored, root, const Resolver()).value!
              as Map<String, Object?>;

      expect(effectiveOf({})['a'], equals('fb'), reason: 'absent takes the default');
      expect(effectiveOf({'a': null})['a'], isNull, reason: 'explicit null survives');
      expect(effectiveOf({'a': false})['a'], isFalse, reason: 'false survives');
      expect(effectiveOf({'a': ''})['a'], isEmpty, reason: 'empty string survives');
      expect(effectiveOf({'a': 0})['a'], isZero, reason: 'zero survives');
      expect(effectiveOf({'a': 'set'})['a'], equals('set'));
    });

    test('zero and false survive on their own typed nodes', () {
      final root = rootOf('{ descriptor_version: "1.0", root: { type: "object", children: {'
          ' n: { type: "int", default: 9 }, f: { type: "bool", default: true } } } }');
      final effective = buildEffective({'n': 0, 'f': false}, root, const Resolver())
          .value! as Map<String, Object?>;
      expect(effective, equals({'n': 0, 'f': false}));
    });

    test('MISSING is distinct from every stored value', () {
      expect(isMissing(resolverMissing), isTrue);
      expect(isMissing(null), isFalse);
      expect(isMissing(false), isFalse);
      expect(isMissing(0), isFalse);
      expect(isMissing(''), isFalse);
      expect(isMissing(const <Object?>[]), isFalse);
    });

    test('effectiveAt returns MISSING only when nothing supplies a value', () {
      final descriptor = compileDescriptor(defaultedDescriptor);
      final absent =
          effectiveAt(resolverMissing, descriptor.nodeAt('/a'), const Resolver(), path: '/x');
      expect(absent.value, equals('fb'));
      expect(absent.provenance['/x']!.kind, equals(ProvenanceKind.defaultValue));
      final nullNode = compileDescriptor(
          '{ descriptor_version: "1.0", root: { type: "object", children: {'
          ' a: { type: "string" } } } }');
      final missing =
          effectiveAt(resolverMissing, nullNode.nodeAt('/a'), const Resolver(), path: '/x');
      expect(isMissing(missing.value), isTrue);
      expect(missing.provenance, isEmpty);
    });

    test('a placeholder whose source is empty is not treated as absent', () {
      final root = rootOf('{ descriptor_version: "1.0", root: { type: "object", children: {'
          ' a: { type: "string", env: { allowed: true }, default: "fb" } } } }');
      final result = buildEffective({
        'a': r'${V}'
      }, root, const Resolver(environment: {'V': ''}));
      expect((result.value! as Map<String, Object?>)['a'], isEmpty,
          reason: 'a stored placeholder resolves to empty; it does not '
              'fall through to the descriptor default');
      expect(result.provenance['/a']!.kind, equals(ProvenanceKind.environment));
    });
  });

  group('immutability', () {
    test('resolution does not mutate the stored tree', () {
      final document = parse('{ a: { b: "\${V}" }, list: [1, 2] }');
      final stored = document.storedValue();
      final snapshot = document.toSource();
      final root = rootOf(envDescriptor);
      buildEffective(stored, root, const Resolver(overrides: {'V': 'x'}));
      expect(document.toSource(), equals(snapshot),
          reason: 'the parsed document changed');
      expect(stored, equals(document.storedValue()),
          reason: 'the stored tree handed to the resolver changed');
      expect(identical(stored, document.storedValue()), isFalse);
    });

    test('the injected layers are not modified', () {
      final overrides = <String, String>{'V': 'x'};
      final environment = <String, String>{'W': 'y'};
      final dotenv = <String, String>{'Z': 'z'};
      final resolver =
          Resolver(overrides: overrides, environment: environment, dotenv: dotenv);
      final root = rootOf(envDescriptor);
      buildEffective({'s': r'${V}'}, root, resolver);
      expect(overrides, equals({'V': 'x'}));
      expect(environment, equals({'W': 'y'}));
      expect(dotenv, equals({'Z': 'z'}));
      expect(resolver.lookup('V').value, equals('x'));
    });

    test('the effective tree is a new structure', () {
      final stored = {'a': {'b': 'c'}};
      final root = rootOf('{ descriptor_version: "1.0", root: { type: "object", children: {'
          ' a: { type: "object", children: { b: { type: "string" } } } } } }');
      final result = buildEffective(stored, root, const Resolver());
      expect(result.value, equals(stored));
      expect(identical(result.value, stored), isFalse);
      expect(identical((result.value! as Map)['a'], stored['a']), isFalse);
    });

    test('a hand-built tree with narrow collection types still resolves', () {
      final stored = <String, Object?>{
        's': r'${V}',
        'list': <String>['a'],
      };
      final root = rootOf('{ descriptor_version: "1.0", root: { type: "object", children: {'
          ' s: { type: "string", env: { allowed: true } },'
          ' list: { type: "array", children: { type: "string" } } } } }');
      final result = buildEffective(stored, root, const Resolver(overrides: {'V': 'x'}));
      final effective = result.value! as Map<String, Object?>;
      expect(effective['s'], equals('x'));
      expect(effective['list'], equals(['a']));
    });

    test('filling a default does not write it into the stored tree', () {
      final stored = <String, Object?>{};
      final result = buildEffective(stored, rootOf(defaultedDescriptor), const Resolver());
      expect((result.value! as Map<String, Object?>)['a'], equals('fb'));
      expect(stored, isEmpty, reason: 'the default was materialized into the input');
    });
  });

  group('provenance shape', () {
    test('one variable keeps the compatible shape', () {
      final result = buildEffective({
        's': r'${V}'
      }, rootOf(envDescriptor), const Resolver(overrides: {'V': 'x'}));
      expect(result.provenance['/s']!.toMap(),
          equals({'kind': 'environment', 'variable': 'V', 'source': 'override'}));
    });

    test('the plain environment records no source', () {
      final result = buildEffective({
        's': r'${V}'
      }, rootOf(envDescriptor), const Resolver(environment: {'V': 'x'}));
      expect(result.provenance['/s']!.toMap(),
          equals({'kind': 'environment', 'variable': 'V'}));
    });

    test('several variables are all named, strongest source first', () {
      final result = buildEffective({
        's': r'${A}-${B}'
      }, rootOf(envDescriptor),
          const Resolver(overrides: {'A': '1'}, dotenv: {'B': '2'}));
      expect(result.provenance['/s']!.toMap(), equals({
        'kind': 'environment',
        'variable': 'A',
        'variables': ['A', 'B'],
        'source': 'override',
      }));
    });

    test('a stored value keeps file provenance', () {
      final result = buildEffective({'plain': 'x'}, rootOf(envDescriptor), const Resolver());
      expect(result.provenance['/plain']!.kind, equals(ProvenanceKind.file));
    });
  });
}
