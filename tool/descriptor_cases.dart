/// Descriptor corpus cases for `tool/generate_corpus.dart` (stage 2, slice 2A).
///
/// Every entry names a descriptor document plus, where relevant, one
/// `validate_descriptor` mode, one `compile_descriptor` call or one query over
/// the compiled tree. The cases are executed against the Python baseline by
/// `tool/python/corpus_driver.py`; the expectations are what the baseline
/// produced, never what its prose says.
///
/// Areas:
///
/// * `descriptor_validate`   — `validate_descriptor(source, mode)` diagnostics.
/// * `descriptor_compile`    — `compile_descriptor(...)` result or rejection.
/// * `descriptor_semantics`  — one query over a compiled descriptor (`node_at`,
///   `has_node`, `revision`).
///
/// A case whose baseline result is a defect carries a `divergence` block: the
/// fixture keeps the observed baseline result as `baselineEvidence` and asserts
/// the corrected expectation (`SPEC_.md` amendment 38; the report item lives in the
/// handoff notes for the Python team).
library;

import 'corpus_cases.dart';

// -- document builders ------------------------------------------------

/// A minimal envelope around [rootBody], which must be one node object body.
String envelope(String rootBody) =>
    '{\n  descriptor_version: "1.0",\n  root: { $rootBody },\n}\n';

/// A descriptor whose root object has a single child `a`
/// built from [nodeBody].
String withA(String nodeBody) =>
    envelope('type: "object", children: { a: { $nodeBody } }');

/// A descriptor whose root object has the given [children] body.
String withChildren(String children) =>
    envelope('type: "object", children: { $children }');

// -- case builders ----------------------------------------------------------------

CorpusCase _validate(
  String id,
  String description,
  List<String> classes,
  String source, {
  String mode = 'strict',
  Map<String, Object?>? divergence,
}) =>
    CorpusCase(
      id: id,
      description: description,
      classes: classes,
      kind: 'descriptor_validate',
      input: source,
      payload: {'mode': mode},
      divergence: divergence,
    );

CorpusCase _compile(
  String id,
  String description,
  List<String> classes,
  String source, {
  bool strict = true,
  List<String> typedefSources = const [],
  List<Map<String, String>> fragments = const [],
  Map<String, Object?>? divergence,
}) =>
    CorpusCase(
      id: id,
      description: description,
      classes: classes,
      kind: 'descriptor_compile',
      input: source,
      payload: {
        'strict': strict,
        if (typedefSources.isNotEmpty) 'typedefSources': typedefSources,
        if (fragments.isNotEmpty) 'fragments': fragments,
      },
      divergence: divergence,
    );

CorpusCase _query(
  String id,
  String description,
  List<String> classes,
  String source,
  Map<String, Object?> query, {
  bool strict = true,
  List<String> typedefSources = const [],
  List<Map<String, String>> fragments = const [],
  Map<String, Object?>? divergence,
}) =>
    CorpusCase(
      id: id,
      description: description,
      classes: classes,
      kind: 'descriptor_query',
      input: source,
      query: query,
      payload: {
        'strict': strict,
        if (typedefSources.isNotEmpty) 'typedefSources': typedefSources,
        if (fragments.isNotEmpty) 'fragments': fragments,
      },
      divergence: divergence,
    );

/// A divergence whose corrected expectation is authored
/// beside the baseline evidence.
Map<String, Object?> _corrected({
  required String id,
  required String report,
  required String note,
  required Map<String, Object?> corrected,
}) =>
    divergenceExpectation(id: id, report: report, note: note, corrected: corrected);

/// One corrected diagnostic: the fields a corrected case pins.
Map<String, Object?> _issue(
  String code,
  String severity,
  String path, {
  int? line,
  int? column,
}) =>
    {
      'code': code,
      'severity': severity,
      'path': path,
      'hasMessage': true,
      if (line != null) 'line': line,
      if (column != null) 'column': column,
    };

// -- shared descriptor documents ---------------------------------------------------

/// The minimal descriptor the baseline tests use.
final String minimal = envelope('type: "object", children: { a: { type: "string" } }');

/// A descriptor exercising templates, dynamic keys, unions and
/// inheritance at once; the semantics queries resolve pointers in it.
final String richDescriptor = '''
{
  descriptor_version: "1.0",
  project: "rich",
  config_version: "7",
  root: {
    type: "object",
    secret: false,
    apply: "reload",
    children: {
      worker: { typedef: "workerId", type: "string", pattern: "^[a-z]+\$" },
      alias: { type: "workerId", description: "Another worker" },
      tags: { type: "array", children: { type: "string" }, max_items: 4 },
      ports: { type: "array", children_options: [ { type: "int", minimum: 1 }, { type: "string" } ] },
      sinks: {
        type: "object",
        key_enum: ["file", "stdout"],
        additional_children: { type: "object", children: { target: { type: "string" } } },
      },
      dynamic: { type: "object", key_pattern: "^w-", additional_children: { type: "int" } },
      choice: {
        type: "union",
        children_options: [
          { type: "string" },
          { type: "object", children: { host: { type: "string" }, port: { type: "int" } } },
        ],
      },
      secretKey: { type: "string", secret: true, read_only: true },
      nested: { type: "object", children: { deep: { type: "int", default: 3 } } },
    },
  },
}
''';

/// An object template overridden by a reference that adds and replaces children.
final String mergeChildrenDescriptor = withChildren(
    'p: { typedef: "card", type: "object", children: {'
    ' a: { type: "int" }, b: { type: "string" } } },'
    ' q: { type: "card", children: { b: { type: "int", minimum: 3 }, c: { type: "bool" } } }');

/// An array template whose per-index alternatives are merged by index.
final String mergeOptionsDescriptor = withChildren(
    'p: { typedef: "u", type: "array", children_options:'
    ' [ { type: "int" }, { type: "string" } ] },'
    ' q: { type: "u", children_options: [ { type: "int", minimum: 5 } ] }');

/// A typedef source declaring a template the main descriptor references.
const String workerIdTypedefSource =
    '{ descriptor_version: "1.0", root: { type: "object", children: { '
    'declared: { typedef: "workerId", type: "string", min_length: 1 } } } }';

/// A fragment mounting a new field under an existing object.
const String extraFragmentRoot =
    '{ descriptor_version: "1.0", root: { type: "object", children: { extra: { type: "int" } } } }';

// -- validate: envelope --------------------------------------------------------------

List<CorpusCase> _envelopeCases() => [
      _validate('env_minimal', 'The smallest descriptor the grammar accepts.',
          const ['envelope', 'accept'], minimal),
      _validate('env_project_and_version', 'The optional envelope strings are accepted.',
          const ['envelope', 'accept'],
          '{\n  descriptor_version: "1.0",\n  project: "demo",\n  config_version: "2.1",\n'
              '  root: { type: "object", children: {} },\n}\n'),
      _validate('env_missing_version', 'A descriptor without a version is refused.',
          const ['envelope', 'version', 'rejection'],
          '{\n  root: { type: "object", children: {} },\n}\n'),
      _validate('env_wrong_version', 'An unknown descriptor version is refused.',
          const ['envelope', 'version', 'rejection'],
          envelope('type: "object", children: {}').replaceAll('"1.0"', '"2.0"')),
      _validate('env_version_number', 'A numeric version is refused.',
          const ['envelope', 'version', 'rejection'],
          envelope('type: "object", children: {}').replaceAll('"1.0"', '1.0')),
      _validate('env_missing_root', 'A descriptor without a root is refused.',
          const ['envelope', 'root', 'rejection'], '{ descriptor_version: "1.0" }'),
      _validate('env_root_scalar', 'A root that is not an object node is refused.',
          const ['envelope', 'root', 'rejection'],
          '{ descriptor_version: "1.0", root: "nope" }'),
      _validate('env_project_number', 'project must be a string.',
          const ['envelope', 'rejection'],
          '{ descriptor_version: "1.0", project: 7, root: { type: "object", children: {} } }'),
      _validate('env_config_version_object', 'config_version must be a string.',
          const ['envelope', 'rejection'],
          '{ descriptor_version: "1.0", config_version: { v: 1 },'
              ' root: { type: "object", children: {} } }'),
      _validate('env_syntax_error', 'Source that does not parse is reported, not raised.',
          const ['envelope', 'syntax', 'rejection'], '{ descriptor_version: '),
      _validate(
        'env_root_array',
        'A descriptor document whose root value is an array.',
        const ['envelope', 'root', 'rejection', 'A10'],
        '[1, 2]',
        divergence: _corrected(
          id: 'A10',
          report: 'A10',
          note: 'Upstream fixed the crash (d4adb45) but the intended '
              'DESCRIPTOR_SYNTAX issue is emitted with no line and column, because '
              '_validate_data() is called without the source text on this path. '
              'The Dart implementation locates the issue at the root value '
              'position.',
          corrected: {
            'ok': true,
            'valid': false,
            'issues': [_issue('DESCRIPTOR_SYNTAX', 'error', '', line: 1, column: 1)],
          },
        ),
      ),
      _validate(
        'env_root_string_document',
        'A descriptor document whose whole root value is a string.',
        const ['envelope', 'root', 'rejection', 'A10'],
        '"just a string"',
        divergence: _corrected(
          id: 'A10',
          report: 'A10',
          note: 'Same defect as env_root_array: the corrected diagnostic carries no '
              'source position, where the Dart implementation reports it at the root '
              'value.',
          corrected: {
            'ok': true,
            'valid': false,
            'issues': [_issue('DESCRIPTOR_SYNTAX', 'error', '', line: 1, column: 1)],
          },
        ),
      ),
      _validate(
        'env_unknown_key',
        'Unknown metadata outside the node tree.',
        const ['envelope', 'unknown-metadata'],
        '{\n  descriptor_version: "1.0",\n  language: "en",\n  x_whatever: 1,\n'
            '  root: { type: "object", children: {} },\n}\n',
        mode: 'default',
      ),
      _validate(
        'env_unknown_key_strict',
        'Strict mode turns unknown metadata into errors.',
        const ['envelope', 'unknown-metadata', 'strict', 'rejection'],
        '{ descriptor_version: "1.0", language: "en", root: { type: "object", children: {} } }',
      ),
      _validate(
        'env_flutter_extension_key',
        'The namespaced Flutter envelope key is recognized here.',
        const ['envelope', 'flutter-extension', 'SPEC5-FLUTTER-EXT'],
        '{\n  descriptor_version: "1.0",\n  x_aiset_flutter: { extension_version: "1.0", nodes: {} },\n'
            '  root: { type: "object", children: {} },\n}\n',
        divergence: _corrected(
          id: 'SPEC5-FLUTTER-EXT',
          report: 'SPEC5-FLUTTER-EXT',
          note: 'SPEC.md amendment 5 defines x_aiset_flutter as the namespaced envelope '
              'entry of the Flutter extensions and requires the Flutter compiler to recognize '
              'it; the descriptor grammar of the shared baseline has no entry of its '
              'own for the extension. Since d4adb45 the Python baseline reports '
              'the key as UNKNOWN_DESCRIPTOR_PROPERTY (an error in strict mode), which '
              'SPEC.md 5 explicitly anticipates: a legacy Python validator may report '
              'unknown metadata without the descriptor being incompatible. '
              'This is a required intentional divergence, not a baseline defect: the Dart '
              'implementation accepts the key, preserves it uninterpreted on '
              'CompiledDescriptor.flutterExtension, and does not emit '
              'the diagnostic.',
          corrected: {'ok': true, 'valid': true, 'issues': []},
        ),
      ),
    ];

// -- validate: node grammar ------------------------------------------------------

List<CorpusCase> _nodeCases() => [
      for (final type in const [
        'string', 'int', 'number', 'bool', 'null', 'object', 'array', 'any',
      ])
        if (type != 'array' && type != 'object')
          _validate('node_type_$type', 'A scalar node of type $type compiles.',
              const ['types', 'accept'], withA('type: "$type"'))
        else if (type == 'array')
          _validate('node_type_array', 'An array node with one item specification.',
              const ['types', 'accept'], withA('type: "array", children: { type: "string" }'))
        else
          _validate('node_type_object', 'An object node with one child.',
              const ['types', 'accept'], withA('type: "object", children: { b: { type: "int" } }')),
      _validate('node_type_union', 'A union with two alternatives.',
          const ['types', 'accept'],
          withA('type: "union", children_options: [ { type: "string" }, { type: "int" } ]')),
      _validate('node_missing_type', 'A node without a type is refused.',
          const ['node', 'type', 'rejection'], withA('description: "x"')),
      _validate('node_type_number_value', 'A numeric type name is refused.',
          const ['node', 'type', 'rejection'], withA('type: 5')),
      _validate('node_type_null_value', 'A null type is refused.',
          const ['node', 'type', 'rejection'], withA('type: null')),
      _validate('node_child_not_object', 'A child that is not a node object is refused.',
          const ['node', 'children', 'rejection'], withChildren('a: 5')),
      _validate('node_deep_child_not_object', 'The check recurses into nested children.',
          const ['node', 'children', 'rejection'],
          withA('type: "object", children: { b: "nope" }')),
      _validate('node_property_type_required_string', 'required must be a boolean.',
          const ['node', 'property-types', 'rejection'], withA('type: "string", required: "yes"')),
      _validate('node_property_type_secret_number', 'secret must be a boolean.',
          const ['node', 'property-types', 'rejection'], withA('type: "string", secret: 1')),
      _validate('node_property_type_min_length_string', 'min_length must be an integer.',
          const ['node', 'property-types', 'rejection'], withA('type: "string", min_length: "2"')),
      _validate('node_property_type_id_number', 'id must be a string.',
          const ['node', 'property-types', 'rejection'],
          withChildren('a: { type: "string", id: 7 }')),
      _validate('node_property_type_description_number', 'description must be text.',
          const ['node', 'property-types', 'rejection'], withA('type: "string", description: 5')),
      _validate('node_minimum_string', 'A numeric bound holding a string.',
          const ['node', 'property-types', 'constraints', 'rejection'],
          withA('type: "int", minimum: "abc"')),
      _validate('node_maximum_list', 'A numeric bound holding a list.',
          const ['node', 'property-types', 'constraints', 'rejection'],
          withA('type: "number", maximum: [1]')),
      _validate('node_enum_object', 'An enum written as an object instead of a list.',
          const ['node', 'property-types', 'enum', 'rejection'],
          withA('type: "string", enum: { x: 1 }')),
      _validate('node_required_with_default', 'required and default are incompatible.',
          const ['node', 'structure', 'rejection'],
          withA('type: "string", required: true, default: "x"')),
      _validate('node_enum_with_const', 'enum and const are incompatible.',
          const ['node', 'structure', 'rejection'],
          withA('type: "string", enum: ["a"], const: "a"')),
      _validate('node_enum_empty', 'An empty enum is refused.',
          const ['node', 'enum', 'rejection'], withA('type: "string", enum: []')),
      _validate('node_enum_duplicate', 'Duplicate enum members are refused.',
          const ['node', 'enum', 'rejection'], withA('type: "string", enum: ["a", "a"]')),
      _validate('node_enum_numbers', 'Numeric enum members are distinct from their text form.',
          const ['node', 'enum', 'accept'], withA('type: "any", enum: [1, "1", true]')),
      _validate('node_const_scalar', 'A const value is accepted.',
          const ['node', 'const', 'accept'], withA('type: "string", const: "fixed"')),
      _validate('node_const_object', 'A const may be a whole object.',
          const ['node', 'const', 'accept'], withA('type: "any", const: { a: 1 }')),
      _validate('node_min_length_negative', 'A negative length is refused.',
          const ['node', 'constraints', 'rejection'], withA('type: "string", min_length: -1')),
      _validate('node_min_above_max_length', 'min_length above max_length is refused.',
          const ['node', 'constraints', 'rejection'],
          withA('type: "string", min_length: 5, max_length: 2')),
      _validate('node_minimum_above_maximum', 'minimum above maximum is refused.',
          const ['node', 'constraints', 'rejection'],
          withA('type: "int", minimum: 10, maximum: 2')),
      _validate('node_min_items_above_max_items', 'min_items above max_items is refused.',
          const ['node', 'constraints', 'rejection'],
          withA('type: "array", children: { type: "int" }, min_items: 3, max_items: 1')),
      _validate('node_apply_valid_values', 'Each declared apply policy is accepted.',
          const ['node', 'apply', 'accept'],
          withChildren('a: { type: "int", apply: "live" }, b: { type: "int", apply: "reload" },'
              ' c: { type: "int", apply: "restart" }')),
      _validate('node_apply_invalid', 'An unknown apply policy is refused.',
          const ['node', 'apply', 'rejection'], withA('type: "int", apply: "immediately"')),
      _validate('node_id_outside_children', 'id is only meaningful on a child.',
          const ['node', 'id', 'rejection'], envelope('type: "object", id: "root", children: {}')),
      _validate('node_id_in_children', 'A child may rename its field with id.',
          const ['node', 'id', 'accept'], withChildren('field_type: { id: "type", type: "string" }')),
      _validate('node_duplicate_field_names', 'Two children cannot claim one field name.',
          const ['node', 'id', 'rejection'],
          withChildren('one: { id: "same", type: "string" }, two: { id: "same", type: "string" }')),
      _validate('node_duplicate_field_name_and_label',
          'A renamed child cannot collide with another child label.',
          const ['node', 'id', 'rejection'],
          withChildren('a: { id: "b", type: "string" }, b: { type: "string" }')),
      _validate('node_children_labels_are_not_unknown_properties',
          'Children named like grammar keywords are data, not metadata.',
          const ['node', 'unknown-metadata', 'accept'],
          envelope('type: "object", children: { type: { type: "string" },'
              ' children: { type: "int" }, required: { type: "bool" } }')),
      _validate('node_unknown_property_warning', 'An unknown node property is a warning by default.',
          const ['node', 'unknown-metadata', 'accept'],
          withA('type: "string", requried: true'), mode: 'default'),
      _validate('node_unknown_property_strict', 'Strict mode turns it into an error.',
          const ['node', 'unknown-metadata', 'strict', 'rejection'],
          withA('type: "string", requried: true')),
      _validate('node_two_unknown_properties', 'Each unknown property is reported separately.',
          const ['node', 'unknown-metadata'],
          withA('type: "string", requried: true, x_demo: { note: 1 }'), mode: 'default'),
      _validate('node_nested_unknown_property', 'The path points at the nested property.',
          const ['node', 'unknown-metadata', 'paths'],
          withA('type: "object", children: { b: { type: "int", oops: 1 } }')),
      _validate('node_opaque_metadata_not_traversed',
          'An unknown value is reported once, not walked into.',
          const ['node', 'unknown-metadata'],
          withA('type: "string", x_demo: { weird: { nested: 1 } }'), mode: 'default'),
      _validate('node_unknown_property_position',
          'Every issue carries the source position of the offending property.',
          const ['node', 'unknown-metadata', 'positions'],
          '{\n  descriptor_version: "1.0",\n  root: {\n    type: "object",\n    children: {\n'
              '      port: {\n        typo: "string",\n      },\n    },\n  },\n}\n'),
      _validate(
        'node_astral_column_position',
        'A diagnostic after astral characters counts columns in code points.',
        const ['node', 'positions', 'astral'],
        '{\n  descriptor_version: "1.0",\n  root: { type: "object", children: {\n'
            '    rocket: { type: "string", description: "\u{1F680}\u{1F680}", oops: 1 },\n'
            '  } },\n}\n',
        mode: 'default',
      ),
    ];

// -- validate: constraint-by-type table ------------------------------------------------

List<CorpusCase> _constraintByTypeCases() {
  const constraints = <String, String>{
    'min_length': '2',
    'max_length': '9',
    'pattern': '"^a"',
    'minimum': '1',
    'maximum': '9',
    'min_items': '1',
    'max_items': '9',
    'unique_items': 'true',
  };
  const allowed = <String, List<String>>{
    'string': ['min_length', 'max_length', 'pattern'],
    'int': ['minimum', 'maximum'],
    'number': ['minimum', 'maximum'],
    'array': ['min_items', 'max_items', 'unique_items'],
    'bool': <String>[],
    'null': <String>[],
    'any': <String>[],
    'object': <String>[],
  };
  final cases = <CorpusCase>[];
  allowed.forEach((type, permitted) {
    for (final entry in constraints.entries) {
      final applies = permitted.contains(entry.key);
      final body = type == 'array'
          ? 'type: "array", children: { type: "int" }, ${entry.key}: ${entry.value}'
          : 'type: "$type", ${entry.key}: ${entry.value}';
      cases.add(_validate(
        'constraint_${type}_${entry.key}',
        'The $entry.key constraint ${applies ? 'applies to' : 'does not apply to'} type $type.',
        ['constraint-by-type', type, entry.key, applies ? 'accept' : 'rejection'],
        withA(body),
      ));
    }
  });
  return cases;
}

// -- validate: composite structures --------------------------------------------------

List<CorpusCase> _structureCases() => [
      _validate('structure_object_children', 'An object maps labels to nodes.',
          const ['structure', 'object', 'accept'],
          withA('type: "object", children: { b: { type: "int" }, c: { type: "string" } }')),
      _validate('structure_object_children_string', 'children may name a template.',
          const ['structure', 'object', 'typedef'],
          withA('type: "object", children: "someTemplate"')),
      _validate('structure_object_children_list', 'children must not be a list.',
          const ['structure', 'object', 'rejection'], withA('type: "object", children: [1]')),
      _validate('structure_additional_children_missing', 'additional_children must be a node.',
          const ['structure', 'object', 'rejection'],
          withA('type: "object", additional_children: 5')),
      _validate('structure_key_pattern_and_key_enum', 'The two key constraints exclude each other.',
          const ['structure', 'keys', 'rejection'],
          withA('type: "object", key_pattern: "^a\$", key_enum: ["a"],'
              ' additional_children: { type: "int" }')),
      _validate('structure_key_enum_without_additional', 'key_enum needs a node to govern.',
          const ['structure', 'keys', 'rejection'], withA('type: "object", key_enum: ["a"]')),
      _validate('structure_key_pattern_without_additional',
          'A key pattern with nothing to govern is accepted by the baseline.',
          const ['structure', 'keys'], withA('type: "object", key_pattern: "^a\$"')),
      _validate('structure_key_enum_empty', 'An empty key_enum governs no key at all.',
          const ['structure', 'keys'], withA('type: "object", key_enum: [],'
              ' additional_children: { type: "int" }')),
      _validate('structure_array_without_item_spec', 'An array needs one item specification.',
          const ['structure', 'array', 'rejection'], withA('type: "array"')),
      _validate('structure_array_item_node', 'One node describes every item.',
          const ['structure', 'array', 'accept'],
          withA('type: "array", children: { type: "string" }')),
      _validate('structure_array_label_map_children',
          'An array item position cannot be a label map.',
          const ['structure', 'array', 'rejection'],
          withA('type: "array", children: { first: { type: "int" }, second: { type: "int" } }')),
      _validate('structure_array_children_options', 'An array may offer alternatives per index.',
          const ['structure', 'array', 'accept'],
          withA('type: "array", children_options: [ { type: "int" }, { type: "string" } ]')),
      _validate('structure_array_both_specifications',
          'children and children_options are mutually exclusive on arrays.',
          const ['structure', 'array', 'rejection'],
          withA('type: "array", children: { type: "int" },'
              ' children_options: [ { type: "int" } ]')),
      _validate('structure_array_empty_children_options', 'An empty alternatives list is refused.',
          const ['structure', 'array', 'rejection'], withA('type: "array", children_options: []')),
      _validate('structure_union_without_options', 'A union needs alternatives.',
          const ['structure', 'union', 'rejection'], envelope('type: "union"')),
      _validate('structure_union_empty_options', 'An empty alternatives list is refused.',
          const ['structure', 'union', 'rejection'], envelope('type: "union", children_options: []')),
      _validate('structure_union_with_children', 'A union describes alternatives only.',
          const ['structure', 'union', 'rejection'],
          envelope('type: "union", children_options: [ { type: "int" } ],'
              ' children: { type: "string" }')),
      _validate('structure_union_with_additional', 'additional_children is not valid on a union.',
          const ['structure', 'union', 'rejection'],
          envelope('type: "union", children_options: [ { type: "int" } ],'
              ' additional_children: { type: "string" }')),
      _validate('structure_scalar_with_children', 'A scalar cannot have children.',
          const ['structure', 'scalar', 'rejection'],
          withA('type: "string", children: { type: "int" }')),
      _validate('structure_scalar_with_key_pattern', 'Key constraints need an object.',
          const ['structure', 'scalar', 'rejection'], withA('type: "string", key_pattern: "^a\$"')),
      _validate('structure_any_plain', 'The opaque type carries no constraint of its own.',
          const ['structure', 'any', 'accept'], withA('type: "any"')),
      _validate('structure_any_with_children', 'The opaque type rejects composite keys.',
          const ['structure', 'any', 'rejection'], withA('type: "any", children: {}')),
      _validate('structure_any_with_key_enum', 'The opaque type rejects key constraints.',
          const ['structure', 'any', 'rejection'], withA('type: "any", key_enum: ["a"]')),
      _validate('structure_nested_recursion',
          'Errors inside a deep subtree are reported with their full path.',
          const ['structure', 'paths', 'accept'],
          withA('type: "object", children: { b: { type: "object",'
              ' children: { c: { type: "int", minimum: 0 } } } }')),
    ];

// -- validate: env, ui, helper, hooks, validators ------------------------------------------

List<CorpusCase> _capabilityCases() => [
      _validate('env_policy_allowed', 'A plain env policy.',
          const ['env', 'accept'], withA('type: "string", env: { allowed: true }')),
      _validate('env_policy_convert', 'An env policy with a conversion.',
          const ['env', 'accept'], withA('type: "int", env: { allowed: true, convert: "int" }')),
      _validate('env_policy_missing_allowed', 'allowed is required.',
          const ['env', 'rejection'], withA('type: "int", env: { convert: "int" }')),
      _validate('env_policy_allowed_string', 'allowed must be a boolean.',
          const ['env', 'rejection'], withA('type: "int", env: { allowed: "yes" }')),
      _validate('env_policy_convert_invalid', 'convert must name a supported conversion.',
          const ['env', 'rejection'], withA('type: "int", env: { allowed: true, convert: "date" }')),
      _validate('env_policy_unknown_key', 'An unknown env key is reported as unknown metadata.',
          const ['env', 'unknown-metadata'], withA('type: "int", env: { allowed: true, cast: "int" }'),
              mode: 'default'),
      _validate('ui_valid', 'The recognized ui keys are accepted.',
          const ['ui', 'accept'],
          withA('type: "string", ui: { label: "Name", group: "basic", order: 1,'
              ' help: "h", widget: "textarea", rows: 3, placeholder: "p" }')),
      _validate('ui_rows_zero', 'ui.rows must be a positive integer.',
          const ['ui', 'rejection'], withA('type: "string", ui: { rows: 0 }')),
      _validate('ui_rows_string', 'ui.rows must be a number.',
          const ['ui', 'rejection'], withA('type: "string", ui: { rows: "3" }')),
      _validate('ui_label_number', 'A text ui field must be a string.',
          const ['ui', 'rejection'], withA('type: "string", ui: { label: 3 }')),
      _validate('ui_unknown_key', 'An unknown ui key is reported as unknown metadata.',
          const ['ui', 'unknown-metadata'], withA('type: "string", ui: { colour: "red" }'),
              mode: 'default'),
      _validate('helper_valid', 'A helper binding with every optional field.',
          const ['helper', 'accept'],
          withA('type: "object", helper: { tag: "node_form", actions: ["create", "edit"],'
              ' presentation: "modal", settings: { x: 1 } }')),
      _validate('helper_missing_tag', 'helper.tag is required.',
          const ['helper', 'rejection'], withA('type: "object", helper: { actions: ["edit"] }')),
      _validate('helper_empty_tag', 'helper.tag must not be empty.',
          const ['helper', 'rejection'], withA('type: "object", helper: { tag: "", actions: ["edit"] }')),
      _validate('helper_missing_actions', 'helper.actions is required.',
          const ['helper', 'rejection'], withA('type: "object", helper: { tag: "t" }')),
      _validate('helper_actions_invalid', 'Only the declared actions are accepted.',
          const ['helper', 'rejection'],
          withA('type: "object", helper: { tag: "t", actions: ["destroy"] }')),
      _validate('helper_presentation_invalid', 'An unknown presentation is refused.',
          const ['helper', 'rejection'],
          withA('type: "object", helper: { tag: "t", actions: ["edit"], presentation: "drawer" }')),
      _validate('helper_unknown_key', 'An unknown helper key is reported as unknown metadata.',
          const ['helper', 'unknown-metadata'],
          withA('type: "object", helper: { tag: "t", actions: ["edit"], colour: "blue" }'),
              mode: 'default'),
      _validate('hooks_valid', 'A hook binding for a known event.',
          const ['hooks', 'accept'],
          withA('type: "object", hooks: { before_update: [ { tag: "audit", scope: "node" } ] }')),
      _validate('hooks_unknown_event', 'An unknown hook event is refused.',
          const ['hooks', 'rejection'],
          withA('type: "object", hooks: { before_destroy: [ { tag: "x" } ] }')),
      _validate('hooks_empty_bindings', 'A hook event needs at least one binding.',
          const ['hooks', 'rejection'], withA('type: "object", hooks: { before_update: [] }')),
      _validate('hooks_binding_not_object', 'A binding must be an object.',
          const ['hooks', 'rejection'], withA('type: "object", hooks: { before_update: ["x"] }')),
      _validate('hooks_binding_scope_invalid', 'scope must be node or subtree.',
          const ['hooks', 'rejection'],
          withA('type: "object", hooks: { before_update: [ { tag: "x", scope: "everything" } ] }')),
      _validate('hooks_binding_missing_tag', 'A binding must name its capability tag.',
          const ['hooks', 'rejection'],
          withA('type: "object", hooks: { before_update: [ { scope: "node" } ] }')),
      _validate('hooks_binding_unknown_key', 'An unknown binding key is reported as metadata.',
          const ['hooks', 'unknown-metadata'],
          withA('type: "object", hooks: { before_update: [ { tag: "x", when: "always" } ] }'),
              mode: 'default'),
      _validate('validators_valid', 'A list of validator ids is accepted.',
          const ['validators', 'accept'], withA('type: "string", validators: ["no_spaces"]')),
      _validate('validators_number', 'Validator ids must be strings.',
          const ['validators', 'rejection'], withA('type: "string", validators: [7]')),
      _validate('validators_empty_string', 'Validator ids must not be empty.',
          const ['validators', 'rejection'], withA('type: "string", validators: [""]')),
    ];

// -- validate: patterns -------------------------------------------------------------------

List<CorpusCase> _patternCases() => [
      _validate('pattern_valid', 'A portable pattern compiles.',
          const ['pattern', 'accept'], withA(r'type: "string", pattern: "^[a-z][a-z0-9]*$"')),
      _validate('pattern_broken', 'A pattern that does not compile is refused.',
          const ['pattern', 'rejection'], withA('type: "string", pattern: "("')),
      _validate('pattern_unbalanced_class', 'A malformed class is refused.',
          const ['pattern', 'rejection'], withA('type: "string", pattern: "[a-"')),
      _validate('pattern_key_pattern_broken', 'A malformed key_pattern.',
          const ['pattern', 'keys', 'rejection'],
          withA('type: "object", key_pattern: "(", additional_children: { type: "int" }')),
      _validate('pattern_empty_string', 'An empty pattern matches everything.',
          const ['pattern'], withA('type: "string", pattern: ""')),
    ];

// -- validate: defaults ----------------------------------------------------------------------

List<CorpusCase> _defaultCases() => [
      _validate('default_valid_int', 'A default inside the bounds is accepted.',
          const ['default', 'accept'], withA('type: "int", minimum: 1, maximum: 9, default: 5')),
      _validate('default_out_of_enum', 'A default outside the enum is refused.',
          const ['default', 'rejection'], withA('type: "string", enum: ["x", "y"], default: "z"')),
      _validate('default_wrong_type', 'A default of the wrong type is refused.',
          const ['default', 'rejection'], withA('type: "int", default: "abc"')),
      _validate('default_out_of_bounds', 'A default below the minimum is refused.',
          const ['default', 'rejection'], withA('type: "int", minimum: 10, default: 1')),
      _validate('default_null_on_non_nullable', 'A null default needs a nullable node.',
          const ['default', 'null', 'rejection'], withA('type: "string", default: null')),
      _validate('default_null_on_nullable', 'A nullable node may default to null.',
          const ['default', 'null', 'accept'],
          withA('type: "string", nullable: true, default: null')),
      _validate('default_null_type', 'A node of type null defaults to null.',
          const ['default', 'null', 'accept'], withA('type: "null", default: null')),
      _validate('default_bool_not_int', 'A boolean is not an integer default.',
          const ['default', 'bool', 'rejection'], withA('type: "int", default: true')),
      _validate('default_object_structure', 'An object default is checked against its children.',
          const ['default', 'object', 'rejection'],
          withA('type: "object", children: { b: { type: "int" } }, default: { b: "x" }')),
      _validate('default_object_valid', 'A matching object default is accepted.',
          const ['default', 'object', 'accept'],
          withA('type: "object", children: { b: { type: "int" } }, default: { b: 1 }')),
      _validate('default_undeclared_field', 'A default may not carry an undeclared field.',
          const ['default', 'object', 'rejection'],
          withA('type: "object", children: { b: { type: "int" } }, default: { c: 1 }')),
      _validate('default_array_items', 'An array default is checked item by item.',
          const ['default', 'array', 'rejection'],
          withA('type: "array", children: { type: "int" }, default: [1, "x"]')),
      _validate('default_array_valid', 'A matching array default is accepted.',
          const ['default', 'array', 'accept'],
          withA('type: "array", children: { type: "int" }, min_items: 1, default: [1, 2]')),
      _validate('default_union_alternative', 'A union default must match one alternative.',
          const ['default', 'union', 'accept'],
          withA('type: "union", children_options: [ { type: "int" }, { type: "string" } ],'
              ' default: "text"')),
      _validate('default_union_no_alternative', 'A union default matching nothing is refused.',
          const ['default', 'union', 'rejection'],
          withA('type: "union", children_options: [ { type: "int" } ], default: true')),
      _validate('default_any_accepts_everything', 'The opaque type accepts any default.',
          const ['default', 'any', 'accept'], withA('type: "any", default: { a: [1, null] }')),
      _validate('default_pattern_must_match', 'A default must satisfy the node pattern.',
          const ['default', 'pattern', 'rejection'],
          withA('type: "string", pattern: "^a", default: "b"')),
      _validate('default_unique_items', 'A default array must obey unique_items.',
          const ['default', 'array', 'rejection'],
          withA('type: "array", children: { type: "int" }, unique_items: true, default: [1, 1]')),
      _validate('default_template_typed_node',
          'A default on a node whose type names a template.',
          const ['default', 'typedef', 'rejection'],
          '{\n  descriptor_version: "1.0",\n  root: { type: "object", children: {\n'
              '    port: { typedef: "sp", type: "int", minimum: 1 },\n'
              '    bad: { type: "sp", default: "abc" },\n  } },\n}\n'),
    ];

// -- validate: typedefs ------------------------------------------------------------------------

List<CorpusCase> _typedefValidateCases() => [
      _validate('typedef_declare_and_use', 'A template may be declared and referenced.',
          const ['typedef', 'accept'],
          withChildren('p: { typedef: "port", type: "int", minimum: 1 },'
              ' q: { type: "port" }')),
      _validate('typedef_shadow_primitive', 'A template cannot shadow a primitive type.',
          const ['typedef', 'rejection'], withChildren('p: { typedef: "string", type: "int" }')),
      _validate('typedef_duplicate_name', 'A template name is declared once.',
          const ['typedef', 'rejection'],
          withChildren('p: { typedef: "tpl", type: "int" }, q: { typedef: "tpl", type: "string" }')),
      _validate('typedef_unknown_reference', 'An unknown type name is reported.',
          const ['typedef', 'rejection'], withA('type: "missing"')),
      _validate('typedef_cycle', 'A template that references itself is reported.',
          const ['typedef', 'rejection'], withChildren('p: { typedef: "tpl", type: "tpl" }')),
      _validate('typedef_indirect_cycle', 'A cycle through two templates is reported.',
          const ['typedef', 'rejection'],
          withChildren('p: { typedef: "a", type: "b" }, q: { typedef: "b", type: "a" }')),
      _validate('typedef_not_a_string', 'typedef must be a string.',
          const ['typedef', 'rejection'], withA('type: "int", typedef: 7')),
      _validate('typedef_used_in_array_item',
          'A template resolves in the single node that describes array items.',
          const ['typedef', 'array', 'accept'],
          withChildren('card: { typedef: "card", type: "object", children: { n: { type: "int" } } },'
              ' cards: { type: "array", children: { type: "card" } }')),
      _validate('typedef_used_in_additional_children',
          'A template resolves as the node governing dynamic keys.',
          const ['typedef', 'object', 'accept'],
          withChildren('card: { typedef: "card", type: "object", children: { n: { type: "int" } } },'
              ' named: { type: "object", additional_children: { type: "card" } }')),
    ];

// -- compile: shapes ------------------------------------------------------------------------

List<CorpusCase> _compileShapeCases() => [
      _compile('compile_minimal', 'The compiled shape of the minimal descriptor.',
          const ['compile', 'shape', 'accept'], minimal),
      _compile('compile_rich', 'Every node kind in one compiled tree.',
          const ['compile', 'shape', 'accept', 'nested'], richDescriptor),
      _compile('compile_scalar_defaults', 'Defaults and hasDefault per scalar type.',
          const ['compile', 'default', 'accept'],
          withChildren('s: { type: "string", default: "x" }, i: { type: "int", default: 0 },'
              ' n: { type: "number", default: 1.5 }, b: { type: "bool", default: false },'
              ' u: { type: "null" }, a: { type: "any", default: null }')),
      _compile('compile_explicit_null_default',
          'An explicit null default is distinct from no default.',
          const ['compile', 'default', 'null', 'accept'],
          withA('type: "string", nullable: true, default: null')),
      _compile('compile_enum_and_const', 'Enum members and a const value survive compilation.',
          const ['compile', 'enum', 'const', 'accept'],
          withChildren('e: { type: "string", enum: ["a", "b"] }, c: { type: "int", const: 7 }')),
      _compile('compile_numeric_bounds', 'Bounds keep their declared kind.',
          const ['compile', 'constraints', 'accept'],
          withChildren('i: { type: "int", minimum: -5, maximum: 5 },'
              ' n: { type: "number", minimum: 0.5, maximum: 1.25 }')),
      _compile('compile_string_constraints', 'Length and pattern constraints survive.',
          const ['compile', 'constraints', 'accept'],
          withA(r'type: "string", min_length: 1, max_length: 8, pattern: "^[a-z]+$"')),
      _compile('compile_array_constraints', 'Array constraints survive.',
          const ['compile', 'constraints', 'accept'],
          withA('type: "array", children: { type: "int" }, min_items: 1, max_items: 3,'
              ' unique_items: true')),
      _compile('compile_object_dynamic_keys', 'key_enum and key_pattern survive.',
          const ['compile', 'keys', 'accept'],
          withChildren('e: { type: "object", key_enum: ["a", "b"],'
              ' additional_children: { type: "int" } },'
              ' p: { type: "object", key_pattern: "^k-", additional_children: { type: "string" } }')),
      _compile('compile_id_field_name', 'The id property renames the field, label survives.',
          const ['compile', 'id', 'accept'],
          withChildren('field_type: { id: "type", type: "string" }')),
      _compile('compile_env_policy', 'The env policy survives compilation.',
          const ['compile', 'env', 'accept'],
          withChildren('a: { type: "string", env: { allowed: true } },'
              ' b: { type: "int", env: { allowed: true, convert: "int" } }')),
      _compile('compile_secret_read_only_apply', 'The protection flags survive compilation.',
          const ['compile', 'flags', 'accept'],
          withA('type: "string", secret: true, read_only: true, apply: "live"')),
      _compile('compile_inherited_flags',
          'secret, read_only and apply are inherited by descendants.',
          const ['compile', 'inheritance', 'accept'],
          '{ descriptor_version: "1.0", root: { type: "object", secret: true, read_only: true,'
              ' apply: "live", children: { a: { type: "object",'
              ' children: { b: { type: "int" } } } } } }'),
      _compile('compile_child_overrides_inherited',
          'A descendant may set its own apply policy.',
          const ['compile', 'inheritance', 'accept'],
          '{ descriptor_version: "1.0", root: { type: "object", apply: "restart", children: {'
              ' a: { type: "object", apply: "live", children: { b: { type: "int" } } } } } }'),
      _compile('compile_validators_ui_helper_hooks',
          'The declarable capability bindings survive compilation.',
          const ['compile', 'capabilities', 'accept'],
          withA('type: "object", validators: ["no_spaces"], ui: { label: "L", rows: 2 },'
              ' helper: { tag: "node_form", actions: ["edit"], presentation: "wizard" },'
              ' hooks: { before_update: [ { tag: "audit", scope: "subtree" } ] }')),
      _compile('compile_union_alternatives', 'Union alternatives are compiled in declaration order.',
          const ['compile', 'union', 'accept'],
          withA('type: "union", children_options: [ { type: "string" },'
              ' { type: "object", children: { host: { type: "string" } } } ]')),
      _compile('compile_array_options', 'Per-index array alternatives are compiled.',
          const ['compile', 'array', 'accept'],
          withA('type: "array", children_options: [ { type: "int" }, { type: "string" } ]')),
      _compile('compile_nested_arrays', 'An array of arrays keeps both item nodes.',
          const ['compile', 'array', 'nested', 'accept'],
          withA('type: "array", children: { type: "array", children: { type: "int" } }')),
      _compile('compile_description_and_title', 'Description and title text survive compilation.',
          const ['compile', 'description', 'accept'],
          withA('type: "string", description: "Retry count", title: "Retries"')),
      _compile('compile_unicode_description', 'Non-ASCII description text survives.',
          const ['compile', 'description', 'unicode', 'accept'],
          withA('type: "string", description: "Число повторов — ✓"')),
      _compile('compile_astral_description', 'An astral character in description text.',
          const ['compile', 'description', 'astral', 'accept'],
          withA('type: "string", description: "Rocket \u{1F680} launch"')),
      _compile('compile_empty_object_children', 'An object with no declared children compiles.',
          const ['compile', 'object', 'empty', 'accept'], envelope('type: "object", children: {}')),
      _compile('compile_any_node', 'The opaque type compiles as a leaf.',
          const ['compile', 'any', 'accept'], withA('type: "any", description: "free form"')),
      _compile('compile_project_and_config_version',
          'The envelope strings are carried onto the compiled descriptor.',
          const ['compile', 'envelope', 'accept'],
          '{ descriptor_version: "1.0", project: "demo", config_version: "3",'
              ' root: { type: "object", children: {} } }'),
    ];

// -- compile: typedef expansion -----------------------------------------------------------------

const String _templateHost = '''
{
  descriptor_version: "1.0",
  root: { type: "object", children: {
    port: { typedef: "service_port", type: "int", minimum: 1, maximum: 65535 },
    http_port: { type: "service_port", default: 8080 },
    admin_port: { type: "service_port", description: "Admin" },
  } },
}
''';

List<CorpusCase> _compileTypedefCases() => [
      _compile('compile_template_expansion', 'A reference inherits the template definition.',
          const ['compile', 'typedef', 'accept'], _templateHost),
      _compile('compile_template_override_description',
          'The referencing node keeps its own description.',
          const ['compile', 'typedef', 'override', 'accept'],
          withChildren('p: { typedef: "card", type: "object", description: "base",'
              ' children: { n: { type: "int" } } }, q: { type: "card", description: "One card" }')),
      _query(
        'merge_children_keeps_template_label',
        'A reference that adds a child keeps the template child.',
        const ['typedef', 'merge', 'object', 'A17'],
        mergeChildrenDescriptor,
        const {'op': 'has_node', 'pointer': '/q/a'},
        divergence: _corrected(
          id: 'A17',
          report: 'A17',
          note: 'The reported rejection closed on d4adb45, but the merged child keeps '
              'the base type, so the constraint the reference '
              'adds is refused against the wrong type and the descriptor is still '
              'rejected with INVALID_DESCRIPTOR before the merge produces '
              'the child. The Dart implementation lets the child override replace '
              'the base type, which is what the expander already '
              'implements for the item node of an array.',
          corrected: {'ok': true, 'result': true},
        ),
      ),
      _query(
        'merge_children_adds_new_label',
        'The label the reference adds is present.',
        const ['typedef', 'merge', 'object', 'A17'],
        mergeChildrenDescriptor,
        const {'op': 'has_node', 'pointer': '/q/c'},
        divergence: _corrected(
          id: 'A17',
          report: 'A17',
          note: 'Same residual as merge_children_keeps_template_label: the merged '
              'child keeps the base type, so the descriptor never compiles and the '
              'added label is never produced.',
          corrected: {'ok': true, 'result': true},
        ),
      ),
      _query(
        'merge_children_override_wins',
        'The bound declared on the reference wins over the template child.',
        const ['typedef', 'merge', 'object', 'A17'],
        mergeChildrenDescriptor,
        const {'op': 'node_field', 'pointer': '/q/b', 'field': 'minimum'},
        divergence: _corrected(
          id: 'A17',
          report: 'A17',
          note: 'Same residual as merge_children_keeps_template_label, on the field the '
              'reference adds: the merged child stays a string, so '
              'minimum: 3 is refused as misplaced.',
          corrected: {
            'ok': true,
            'result': {'k': 'int', 'v': '3'},
          },
        ),
      ),
      _query(
        'merge_options_by_index',
        'children_options merge with the alternative at the same index.',
        const ['typedef', 'merge', 'union', 'A17'],
        mergeOptionsDescriptor,
        const {'op': 'node_field', 'pointer': '/q/0', 'field': 'minimum'},
        divergence: _corrected(
          id: 'A17',
          report: 'A17',
          note: 'The reported rejection closed on d4adb45; the children_options-by-index '
              'merge still fails the same way report A18 described for item '
              'nodes: _merge_template computes `dict(base[key])` before '
              'branching on the key, so merging a list of alternatives raises '
              'ValueError (dictionary update sequence element #0 has length 1; 2 is required). On '
              'd4adb45 this crash is reachable from validate_descriptor '
              'itself, which now expands templates before checking them; the '
              'crash is not yet written up in the handoff notes. The Dart '
              'implementation merges the alternatives by index.',
          corrected: {
            'ok': true,
            'result': {'k': 'int', 'v': '5'},
          },
        ),
      ),
      _query(
        'merge_options_keep_other_alternative',
        'An alternative the reference does not mention survives.',
        const ['typedef', 'merge', 'union', 'A17'],
        mergeOptionsDescriptor,
        const {'op': 'node_field', 'pointer': '/q/1', 'field': 'type'},
        divergence: _corrected(
          id: 'A17',
          report: 'A17',
          note: 'Same residual as merge_options_by_index: the children_options merge '
              'crashes with ValueError before any alternative is produced.',
          corrected: {
            'ok': true,
            'result': {'k': 'string', 'v': 'string'},
          },
        ),
      ),

      _compile('compile_template_in_array_item',
          'A template resolves in the array item position and carries the helper with it.',
          const ['compile', 'typedef', 'array', 'accept'],
          withChildren('card: { typedef: "card", type: "object", description: "card",'
              ' helper: { tag: "node_form", actions: ["edit"], presentation: "modal" },'
              ' children: { n: { type: "int", minimum: 1 } } },'
              ' cards: { type: "array", children: { type: "card", description: "One card" } },'
              ' named: { type: "object", additional_children: { type: "card" } }')),
      _compile('compile_typedef_source_reference',
          'A template declared in another file resolves here.',
          const ['compile', 'typedef', 'typedef-sources', 'accept'],
          '{ descriptor_version: "1.0", root: { type: "object", children: {'
              ' workers: { type: "object", additional_children: { type: "worker" } } } } }',
          typedefSources: [workerIdTypedefSource.replaceFirst('workerId', 'worker')]),
      _compile('compile_typedef_duplicate_across_sources',
          'A name declared twice across files is refused.',
          const ['compile', 'typedef', 'rejection'],
          '{ descriptor_version: "1.0", root: { type: "object", children: {'
              ' w: { typedef: "worker", type: "int" },'
              ' x: { type: "worker", description: "d" } } } }',
          typedefSources: const [workerIdTypedefSource]),
      _compile('compile_unknown_template_reference',
          'A reference to a template that is nowhere declared is refused.',
          const ['compile', 'typedef', 'rejection'], withA('type: "nope"')),
    ];

// -- compile: fragments ---------------------------------------------------------------------------

List<CorpusCase> _fragmentCases() => [
      _compile('compile_fragment_mounts_child', 'A fragment adds one field to the root object.',
          const ['compile', 'fragment', 'accept'], minimal,
          fragments: const [
            {'source': extraFragmentRoot, 'mount': '/root/children/extra'},
          ]),
      _compile('compile_fragment_two_fragments', 'Two fragments mount side by side.',
          const ['compile', 'fragment', 'accept'], minimal,
          fragments: const [
            {'source': extraFragmentRoot, 'mount': '/root/children/extra'},
            {
              'source': '{ descriptor_version: "1.0", root: { type: "object",'
                  ' children: { other: { type: "bool" } } } }',
              'mount': '/root/children/other',
            },
          ]),
      _query(
        'compile_fragment_mount_deep',
        'A fragment mounted below an existing object.',
        const ['compile', 'fragment', 'mount', 'accept'],
        '{ descriptor_version: "1.0", root: { type: "object", children: {'
            ' g: { type: "object", children: {} } } } }',
        const {'op': 'has_node', 'pointer': '/g/z'},
        fragments: const [
          {
            'source': '{ descriptor_version: "1.0", root: { type: "object",'
                ' children: { z: { type: "int" } } } }',
            'mount': '/root/children/g/children/z',
          },
        ],
      ),
      _compile('compile_fragment_mount_collision',
          'Mounting onto an occupied position is refused.',
          const ['compile', 'fragment', 'rejection'],
          minimal,
          fragments: const [
            {'source': extraFragmentRoot, 'mount': '/root/children/a'},
          ]),
      _compile('compile_fragment_mount_bad_prefix',
          'A mount outside the descriptor root is refused.',
          const ['compile', 'fragment', 'rejection'],
          minimal,
          fragments: const [
            {'source': extraFragmentRoot, 'mount': '/children/extra'},
          ]),
      _compile('compile_fragment_mount_missing_intermediate',
          'A mount whose path does not exist is refused.',
          const ['compile', 'fragment', 'rejection'],
          minimal,
          fragments: const [
            {
              'source': extraFragmentRoot,
              'mount': '/root/children/nope/children/x',
            },
          ]),
      _compile('compile_fragment_without_root',
          'A fragment document that is only a node is refused.',
          const ['compile', 'fragment', 'rejection'],
          minimal,
          fragments: const [
            {'source': '{ type: "object", children: {} }', 'mount': '/root/children/x'},
          ]),
      _compile('compile_fragment_replaces_empty_root', 'A fragment may supply the root itself.',
          const ['compile', 'fragment', 'accept'],
          '{ descriptor_version: "1.0", root: { type: "object" } }',
          fragments: const [
            {'source': extraFragmentRoot, 'mount': '/root'},
          ]),
    ];

// -- compile: rejections ---------------------------------------------------------------------------

List<CorpusCase> _compileRejectCases() => [
      _compile('compile_reject_unknown_type', 'Compiling a descriptor with an unknown type fails.',
          const ['compile', 'rejection', 'typedef'], withA('type: "missing"')),
      _compile('compile_reject_invalid_default', 'Compiling a bad default fails.',
          const ['compile', 'rejection', 'default'],
          withA('type: "string", enum: ["x"], default: "z"')),
      _compile('compile_reject_strict_unknown_property',
          'Strict compilation refuses unknown metadata.',
          const ['compile', 'rejection', 'unknown-metadata', 'strict'],
          withA('type: "string", requried: true')),
      _compile('compile_reject_broken_pattern', 'A broken pattern refuses compilation.',
          const ['compile', 'rejection', 'pattern'], withA('type: "string", pattern: "["')),
      _compile('compile_reject_template_cycle', 'A cyclic template refuses compilation.',
          const ['compile', 'rejection', 'typedef'],
          withChildren('p: { typedef: "tpl", type: "tpl" }')),
      _compile('compile_reject_duplicate_field', 'A duplicate field name refuses compilation.',
          const ['compile', 'rejection', 'id'],
          withChildren('one: { id: "same", type: "string" }, two: { id: "same", type: "string" }')),
      _compile('compile_reject_missing_type', 'A node without a type refuses compilation.',
          const ['compile', 'rejection', 'node'], withA('description: "x"')),
      _compile('compile_reject_non_object_root',
          'A descriptor document that is not an object refuses compilation.',
          const ['compile', 'rejection', 'root'],
          '"nope"'),
      _compile('compile_reject_version', 'An unknown version refuses compilation.',
          const ['compile', 'rejection', 'version'],
          minimal.replaceAll('"1.0"', '"9.9"')),
      _compile('compile_non_strict_accepts_warnings',
          'Without strict mode, unknown metadata is a warning and compilation succeeds.',
          const ['compile', 'unknown-metadata', 'accept'],
          withA('type: "string", requried: true'),
          strict: false),
    ];

// -- semantics: node resolution -------------------------------------------------------------------

List<CorpusCase> _semanticsCases() {
  CorpusCase at(String id, String description, List<String> classes, String pointer,
          {String? source}) =>
      _query(id, description, classes, source ?? richDescriptor,
          {'op': 'node_at', 'pointer': pointer});

  return [
    at('at_child', 'A declared child resolves.', const ['node-at', 'object'], '/worker'),
    at('at_nested_child', 'A grandchild resolves.', const ['node-at', 'nested'], '/nested/deep'),
    at('at_dynamic_key', 'An undeclared key resolves through additional_children.',
        const ['node-at', 'dynamic'], '/dynamic/anything'),
    at('at_key_enum_member', 'A declared key_enum member resolves.',
        const ['node-at', 'key-enum'], '/sinks/file'),
    at('at_key_enum_other_member', 'Another declared key resolves to the same node.',
        const ['node-at', 'key-enum'], '/sinks/stdout'),
    at('at_array_item', 'An array item resolves through the single item node.',
        const ['node-at', 'array'], '/tags/7'),
    at('at_array_option_index', 'A children_options array clamps the index.',
        const ['node-at', 'array', 'options'], '/ports/1'),
    at('at_array_option_beyond_options', 'An index past the alternatives still resolves.',
        const ['node-at', 'array', 'options'], '/ports/9'),
    at('at_union_alternative_key', 'A key of the first union alternative resolves.',
        const ['node-at', 'union'], '/choice/host'),
    at('at_union_second_alternative', 'A key only the second alternative declares resolves.',
        const ['node-at', 'union'], '/choice/port'),
    at('at_missing_child', 'An undeclared key of a closed object resolves to nothing.',
        const ['node-at', 'absent'], '/nested/nope'),
    at('at_missing_root_key', 'An unknown top-level key resolves to nothing.',
        const ['node-at', 'absent'], '/nope'),
    at('at_through_scalar', 'A path through a scalar resolves to nothing.',
        const ['node-at', 'absent'], '/worker/deeper'),
    at('at_negative_index', 'A negative array index resolves to nothing.',
        const ['node-at', 'array'], '/tags/-1'),
    at('at_leading_zero_index', 'An index with a leading zero is not an index.',
        const ['node-at', 'array'], '/tags/01'),
    at('at_word_index', 'A word cannot address an array item.',
        const ['node-at', 'array'], '/tags/x'),
    at('at_template_alias', 'A node whose type names a template resolves to the expanded shape.',
        const ['node-at', 'typedef'], '/alias'),
    at('at_inherited_flags', 'A deep node reports the flags it inherited.',
        const ['node-at', 'inheritance'], '/nested/deep'),
    at('at_secret_child', 'A declared secret reports itself.', const ['node-at', 'secret'],
        '/secretKey'),
    at('at_root', 'The empty pointer resolves to the root node.', const ['node-at', 'root'], ''),
    _query('field_inherited_apply', 'A deep node reports the apply policy it inherited.',
        const ['inheritance', 'apply'], richDescriptor,
        const {'op': 'node_field', 'pointer': '/nested/deep', 'field': 'apply'}),
    _query('field_inherited_secret', 'A deep node reports the secret flag it inherited.',
        const ['inheritance', 'secret'],
        '{ descriptor_version: "1.0", root: { type: "object", secret: true, children: {'
            ' a: { type: "object", children: { b: { type: "int" } } } } } }',
        const {'op': 'node_field', 'pointer': '/a/b', 'field': 'secret'}),
    _query('field_default_present_flag',
        'An explicit null default is reported as a present default.',
        const ['default', 'null'], withA('type: "string", nullable: true, default: null'),
        const {'op': 'node_field', 'pointer': '/a', 'field': 'hasDefault'}),
    _query('field_default_absent_flag', 'A node without a default reports no default.',
        const ['default'], withA('type: "string"'),
        const {'op': 'node_field', 'pointer': '/a', 'field': 'hasDefault'}),
    _query('field_template_description',
        'The description of the referencing node wins over the template text.',
        const ['typedef', 'description'], richDescriptor,
        const {'op': 'node_field', 'pointer': '/alias', 'field': 'description'}),
    _query('field_template_constraint',
        'A constraint declared on the template reaches the referencing node.',
        const ['typedef', 'constraints'], richDescriptor,
        const {'op': 'node_field', 'pointer': '/alias', 'field': 'pattern'}),
      // -- template overrides: the reported A17/A18 cases close on
      // d4adb45; the five children/children_options merge cases below
      // stay open (see their notes).
      _validate('typedef_reference_overrides_children',
          'A template reference may override the composite keys of the node it resolves to.',
          const ['typedef', 'merge', 'accept'],
          '{\n  descriptor_version: "1.0",\n  root: { type: "object", children: {\n'
              '    t: { typedef: "ints", type: "array", children: { type: "int", minimum: 1 } },\n'
              '    u: { type: "ints", children: { type: "int", maximum: 9 } },\n  } },\n}\n'),
      _query('typedef_array_item_children_merge_maximum',
          'The item node of an array template merges with the reference override.',
          const ['typedef', 'merge', 'array', 'accept'],
          '{\n  descriptor_version: "1.0",\n  root: { type: "object", children: {\n'
              '    t: { typedef: "ints", type: "array", children: { type: "int", minimum: 1 } },\n'
              '    u: { type: "ints", children: { type: "int", maximum: 9 } },\n  } },\n}\n',
          const {'op': 'node_field', 'pointer': '/u/0', 'field': 'maximum'}),
      _query('typedef_array_item_children_merge_minimum',
          'The bound inherited from the template survives the merge.',
          const ['typedef', 'merge', 'array', 'accept'],
          '{\n  descriptor_version: "1.0",\n  root: { type: "object", children: {\n'
              '    t: { typedef: "ints", type: "array", children: { type: "int", minimum: 1 } },\n'
              '    u: { type: "ints", children: { type: "int", maximum: 9 } },\n  } },\n}\n',
          const {'op': 'node_field', 'pointer': '/u/0', 'field': 'minimum'}),
      _query('revision_stable', 'The revision is the hash of the descriptor source.',
        const ['revision'], minimal, const {'op': 'revision'}),
    _query('revision_other_document', 'A different source gives a different revision.',
        const ['revision'], withA('type: "string", description: "changed"'),
        const {'op': 'revision'}),
    _query('revision_whitespace_matters',
        'Whitespace is part of the hashed source.', const ['revision'],
        '{descriptor_version:"1.0",root:{type:"object",children:{}}}', const {'op': 'revision'}),
  ];
}

// -- description and title forms -----------------------------------------------------------------

List<CorpusCase> _descriptionCases() => [
      _validate('description_string_form', 'The string form is the compatible default.',
          const ['description', 'string', 'accept'],
          withA('type: "int", description: "Number of retry attempts"')),
      _validate('title_string_form', 'title behaves the same way.',
          const ['description', 'title', 'accept'], withA('type: "int", title: "Retries"')),
      _validate('description_object_form',
          'The language-tagged wrapper form.',
          const ['description', 'localized', 'accept'],
          withA('type: "int", description: { default: "en",'
              ' text: { en: "Retry count", ru: "Число попыток" } }')),
      _compile('description_string_compiles', 'A compiled node carries its description text.',
          const ['description', 'string', 'accept'],
          withA('type: "int", description: "Retry count", title: "Retries"')),
    ];

/// The complete descriptor catalog.
List<CorpusCase> descriptorCases() => [
      ..._envelopeCases(),
      ..._nodeCases(),
      ..._constraintByTypeCases(),
      ..._structureCases(),
      ..._capabilityCases(),
      ..._patternCases(),
      ..._defaultCases(),
      ..._typedefValidateCases(),
      ..._compileShapeCases(),
      ..._compileTypedefCases(),
      ..._fragmentCases(),
      ..._compileRejectCases(),
      ..._semanticsCases(),
      ..._descriptionCases(),
    ];
