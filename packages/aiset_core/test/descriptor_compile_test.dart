import 'package:aiset_core/aiset_core.dart';
import 'package:test/test.dart';

/// The parts of the descriptor contract that the Python baseline cannot pin,
/// because they are this product's own grammar (`SPEC.md`
/// amendment 5, `SPEC_.md` amendments 38 and 41).
void main() {
  String descriptor(String children) =>
      '{ descriptor_version: "1.0", root: { type: "object", children: { $children } } }';

  group('extension metadata', () {
    test('x_aiset_flutter is preserved and not interpreted', () {
      final compiled = compileDescriptor('{ descriptor_version: "1.0",'
          ' x_aiset_flutter: { extension_version: "1.0",'
          ' "/audio/strength": { primary: { all: ['
          '{ path: "/audio/denoise", op: "eq", value: true }] } } },'
          ' root: { type: "object", children: { audio: { type: "object",'
          ' children: { strength: { type: "int" }, denoise: { type: "bool" } } } } } }');
      final extension = compiled.flutterExtension!;
      expect(extension['extension_version'], equals('1.0'));
      expect(extension.containsKey('/audio/strength'), isTrue,
          reason: 'the per-node entries are carried uninterpreted');
      final diagnostic = validateDescriptor('{ descriptor_version: "1.0",'
          ' x_aiset_flutter: { extension_version: "1.0" },'
          ' root: { type: "object", children: {} } }');
      expect(diagnostic.issues, isEmpty,
          reason: 'the namespaced extension is known here, not unknown metadata');
    });

    test('a stray key next to the extension is still reported', () {
      final diagnostic = validateDescriptor(
          '{ descriptor_version: "1.0", x_aiset_flutter: { extension_version: "1.0" },'
          ' x_aiset_fluter: {}, root: { type: "object", children: {} } }');
      expect(
          diagnostic.issues.map((i) => i.path),
          contains('/x_aiset_fluter'),
          reason: 'a misspelled namespace is not silently accepted');
    });
  });

  group('rejections', () {
    test('the exception carries the diagnostics that refused it', () {
      Object? caught;
      try {
        compileDescriptor(descriptor('a: { type: "missing" }'));
      } catch (e) {
        caught = e;
      }
      final failure = caught! as DescriptorException;
      expect(failure.code, equals('INVALID_DESCRIPTOR'));
      expect(failure.issues, isNotEmpty);
      expect(failure.issues.single.code, equals('UNKNOWN_TYPE'));
      expect(failure.issues.single.path, equals('/root/children/a/type'));
      expect(failure.issues.single.line, isNotNull,
          reason: 'a descriptor diagnostic points the author at the line');
    });

    test('a syntax failure is a parse error, not a descriptor error', () {
      expect(() => compileDescriptor('{ descriptor_version: '),
          throwsA(isA<Json5ParseException>()
              .having((e) => e.code, 'code', equals('PARSE_ERROR'))));
      // The development operation reports it instead of raising.
      final diagnostic = validateDescriptor('{ descriptor_version: ');
      expect(diagnostic.valid, isFalse);
      expect(diagnostic.issues.single.code, equals('DESCRIPTOR_SYNTAX'));
    });

    test('strict mode refuses unknown metadata and default mode does not', () {
      final source = descriptor('a: { type: "string", requried: true }');
      expect(validateDescriptor(source).valid, isTrue);
      expect(validateDescriptor(source, strict: true).valid, isFalse);
      expect(compileDescriptor(source).root.children!.length, equals(1));
      expect(() => compileDescriptor(source, strict: true),
          throwsA(isA<DescriptorException>()));
    });
  });

  group('node resolution', () {
    test('escaped pointer tokens address keys containing a slash or tilde', () {
      final compiled = compileDescriptor(
          '{ descriptor_version: "1.0", root: { type: "object", children: {'
          ' "with/slash": { type: "int" }, "with~tilde": { type: "bool" } } } }');
      expect(compiled.nodeAt('/with~1slash')!.type, equals('int'));
      expect(compiled.nodeAt('/with~0tilde')!.type, equals('bool'));
      expect(compiled.nodeAt('/with/slash'), isNull);
    });

    test('a numeric object key is not an array index', () {
      final compiled =
          compileDescriptor('{ descriptor_version: "1.0", root: { type: "object", children: {'
              ' "0": { type: "int" } } } }');
      expect(compiled.nodeAt('/0')!.type, equals('int'));
    });

    test('a key_enum set admits only its members', () {
      final compiled = compileDescriptor(
          '{ descriptor_version: "1.0", root: { type: "object", children: {'
              ' s: { type: "object", key_enum: ["file"], additional_children: { type: "int" } } } } }');
      expect(compiled.nodeAt('/s/file')!.type, equals('int'));
      expect(compiled.nodeAt('/s/other'), isNull);
    });

    test('a key_pattern is matched as a prefix, not a full match', () {
      // The baseline tests keys with re.match, which anchors at the start
      // and lets the rest go unmatched. A pattern that must cover the whole key
      // says so with `$`.
      final compiled = compileDescriptor(
          '{ descriptor_version: "1.0", root: { type: "object", children: {'
              ' s: { type: "object", key_pattern: "^w", additional_children: { type: "int" } } } } }');
      expect(compiled.nodeAt('/s/worker')!.type, equals('int'));
      expect(compiled.nodeAt('/s/x-worker'), isNull);
      final anchored = compileDescriptor(
          '{ descriptor_version: "1.0", root: { type: "object", children: {'
              ' s: { type: "object", key_pattern: "^w\$", additional_children: { type: "int" } } } } }');
      expect(anchored.nodeAt('/s/w')!.type, equals('int'));
      expect(anchored.nodeAt('/s/worker'), isNull);
    });

    test('an empty key addresses a child named by the empty string', () {
      final compiled = compileDescriptor(
          '{ descriptor_version: "1.0", root: { type: "object", children: {'
              ' "": { type: "int" } } } }');
      expect(compiled.nodeAt('/')!.type, equals('int'));
    });
  });

  group('compiled tree', () {
    test('a child renamed with id is addressed by its field name', () {
      final compiled = compileDescriptor(
          '{ descriptor_version: "1.0", root: { type: "object", children: {'
              ' field_type: { id: "type", type: "string" } } } }');
      expect(compiled.root.children!.keys, equals(['type']));
      expect(compiled.root.children!['type']!.label, equals('field_type'));
      expect(compiled.nodeAt('/type')!.fieldName, equals('type'));
    });

    test('the document default language resolves a wrapper without a default', () {
      final compiled = compileDescriptor(
          '{ descriptor_version: "1.0", root: { type: "object", children: {'
              ' a: { type: "int", description: { text: { en: "Count", ru: "Число" } } } } } }',
          defaultLanguage: 'ru');
      final node = compiled.nodeAt('/a')!;
      expect(node.description!.defaultText, equals('Число'));
      expect(node.description!.resolve(language: 'en'), equals('Count'));
      expect(compiled.defaultLanguage, equals('ru'));
    });

    test('an array item node and a union alternative are both reachable', () {
      final compiled = compileDescriptor(
          '{ descriptor_version: "1.0", root: { type: "object", children: {'
              ' list: { type: "array", children: { type: "object", children: { x: { type: "int" } } } },'
              ' pick: { type: "union", children_options: [ { type: "string" },'
              ' { type: "object", children: { host: { type: "string" } } } ] } } } }');
      expect(compiled.nodeAt('/list/3/x')!.type, equals('int'));
      expect(compiled.nodeAt('/pick/host')!.type, equals('string'));
      expect(compiled.nodeAt('/pick/nope'), isNull);
    });

    test('hasDefault distinguishes an explicit null from no default', () {
      final compiled = compileDescriptor(
          '{ descriptor_version: "1.0", root: { type: "object", children: {'
              ' a: { type: "string", nullable: true, default: null },'
              ' b: { type: "string", nullable: true } } } }');
      expect(compiled.nodeAt('/a')!.hasDefault, isTrue);
      expect(compiled.nodeAt('/a')!.defaultValue, isNull);
      expect(compiled.nodeAt('/b')!.hasDefault, isFalse);
    });
  });
}
