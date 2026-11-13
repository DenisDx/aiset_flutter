/// Value-validator corpus cases for `tool/generate_corpus.dart` (slice 2C).
///
/// Every entry names a descriptor, a stored value document and the limits
/// the case runs under, and is executed against the Python baseline by
/// `tool/python/corpus_driver.py`. The expectations are what the
/// baseline produced, never what prose says.
///
/// Areas:
///
/// * `validator_profile` — the baseline's default `Limits` numbers, pinned
///   so the Dart profile cannot drift.
/// * `validator_value`   — type and null rules, per-type constraints,
///   `const`/`enum`, object, array and union recursion, dynamic-key
///   governance, the accepted regex dialect and the resource limits.
///
/// A case whose baseline result is a defect or a documented, specified
/// difference carries a `divergence` block: the fixture keeps the observed
/// baseline result as `baselineEvidence` and asserts the corrected
/// expectation (`SPEC_.md` amendment 38). `report` is either a handoff-notes
/// item (`A25`), a placeholder for a newly reproduced defect not yet filed
/// upstream (`A34`, `A35` — the coordinator files them as
/// A34+), or a document anchor for a divergence the specification requires
/// rather than a baseline defect (`SPEC26-DIALECT`:
/// `docs/grammars.md` §1.2/§1.3 assigns a construct to a layer or an engine
/// reading that the executed baseline does not share). It is recorded here so
/// the difference is visible rather than hidden.
///
/// Which case is a divergence was decided by **executing** the baseline, not
/// by reading its source: `val_bounds_huge_above` for instance compares a
/// numeric bound with Python's exact integer `>`, so it agrees with us
/// and is an ordinary case, while `val_enum_huge_int_collision` goes through
/// `_same()`'s `float()` coercion and does not.
///
/// Every regex `pattern` and every string `value` is embedded through
/// `dart:convert` `jsonEncode`, so the JSON5 the baseline parses holds
/// exactly the intended characters — the escaping is mechanical, not
/// hand-counted, on both engines.
library;

import 'dart:convert';

import 'corpus_cases.dart';

// -- assertion helpers (for authored corrections) --------------------------

/// One asserted validation issue. The corpus pins rule, path and severity;
/// the message text is never compared.
Map<String, Object?> issue(String rule, String path, {String severity = 'error'}) => {
      'rule': rule,
      'path': path,
      'severity': severity,
      'hasMessage': true,
    };

/// The corrected expectation for a case this product refuses at the
/// descriptor: a pattern the engine cannot compile, or a construct
/// `docs/grammars.md` §1.2 assigns to the descriptor, is `INVALID_PATTERN` and
/// the whole descriptor is refused (`INVALID_DESCRIPTOR`).
Map<String, Object?> rejectedDescriptor() =>
    const {'ok': false, 'errorCode': 'INVALID_DESCRIPTOR'};

/// Empirical-loop switch. `false` while the executed baseline for each
/// candidate divergence is being observed; every case is then an
/// ordinary one and the generator records the baseline as `expected`.
/// `true` once each divergence block below carries an observed, not a
/// predicted, baseline result.
const bool _registerDivergences = true;

Map<String, Object?>? _corrected({
  required String id,
  required String report,
  required String note,
  required Map<String, Object?> corrected,
}) =>
    _registerDivergences
        ? divergenceExpectation(id: id, report: report, note: note, corrected: corrected)
        : null;

/// Tagged plain string value for the direct entry point (same
/// encoding the resolver catalog uses).
Map<String, Object?> tStr(String v) => {'k': 'string', 'v': v};

// -- case builders ---------------------------------------------------------------

/// A document whose only declared child is [childBody].
String oneChild(String childBody) =>
    '{ descriptor_version: "1.0", root: { type: "object", children: '
    '{ $childBody } } }';

/// A child body for the scalar type [type], with optional extra descriptor
/// properties (given with their own leading comma).
String typed(String type, [String extra = '']) => 'a: { type: "$type"$extra }';

/// A JSON5 string literal holding exactly [text] (a pattern or a
/// value string), so the baseline parses the intended characters.
String _json5(String text) => jsonEncode(text);

CorpusCase _val(
  String id,
  String description,
  List<String> classes, {
  required String descriptor,
  required String value,
  Map<String, Object?>? limits,
  Map<String, Object?>? divergence,
}) =>
    CorpusCase(
      id: id,
      description: description,
      classes: classes,
      kind: 'validator_value',
      input: value,
      payload: {
        'area': 'validator_value',
        'descriptor': descriptor,
        'value': value,
        if (limits != null) 'limits': limits,
      },
      divergence: divergence,
    );

/// A string node carrying [pattern] (raw regex text, JSON5-encoded here),
/// validated against a string child whose content is [valueText].
CorpusCase _patternCase(
  String id,
  String description,
  List<String> classes, {
  required String pattern,
  required String valueText,
  Map<String, Object?>? limits,
  Map<String, Object?>? divergence,
}) =>
    _val(id, description, classes,
        descriptor: oneChild('a: { type: "string", pattern: ${_json5(pattern)} }'),
        value: '{ a: ${_json5(valueText)} }',
        limits: limits,
        divergence: divergence);

/// A case run through the direct value entry point: a tagged value,
/// a node pointer (or none for an undeclared path) and the `present` flag.
CorpusCase _direct(
  String id,
  String description,
  List<String> classes, {
  String childBody = 'a: { type: "string" }',
  required Map<String, Object?> value,
  String? pointer = '/a',
  String path = '/a',
  bool present = true,
  Map<String, Object?>? divergence,
}) =>
    CorpusCase(
      id: id,
      description: description,
      classes: classes,
      kind: 'validator_value',
      input: '',
      payload: {
        'area': 'validator_value',
        'descriptor': oneChild(childBody),
        'direct': true,
        'query': {
          'pointer': pointer,
          'value': value,
          'path': path,
          'present': present,
        },
      },
      divergence: divergence,
    );

const String _dialect = 'SPEC26-DIALECT';
const String _dialectPrefix =
    'docs/grammars.md §1.2 and §1.3 fix which layer reports each regex '
    'construct, and §1.2 states that the two implementations can name the same '
    'problem at different layers while the outcome (refused, named, never '
    'guessed at) does not differ. This is a documented, intentional '
    'divergence from the executed baseline under that rule '
    '(SPEC.md amendment 26), not a baseline defect. ';

// -- profile ---------------------------------------------------------------------

List<CorpusCase> _profileCases() => [
      const CorpusCase(
        id: 'val_profile_limits',
        description: 'The baseline default Limits profile, pinned as data.',
        classes: ['limits', 'profile'],
        kind: 'validator_profile',
        input: '',
      ),
    ];

// -- types -----------------------------------------------------------------------

List<CorpusCase> _typeCases() {
  CorpusCase c(String id, String description, List<String> classes, String body, String value) =>
      _val(id, description, classes, descriptor: oneChild(body), value: value);
  return [
    c('val_string_ok', 'A string satisfies a string node.',
        const ['type', 'string', 'accept'], typed('string'), '{ a: "hello" }'),
    c('val_string_wrong_type', 'A number is not a string.',
        const ['type', 'string', 'rejection'], typed('string'), '{ a: 1 }'),
    c('val_int_ok', 'An integer satisfies an int node.',
        const ['type', 'int', 'accept'], typed('int'), '{ a: 42 }'),
    c('val_int_bool_rejected', 'A boolean is never an int.',
        const ['type', 'int', 'bool', 'rejection'], typed('int'), '{ a: true }'),
    c('val_int_fractional_rejected', 'A fractional double is not an int.',
        const ['type', 'int', 'rejection'], typed('int'), '{ a: 1.5 }'),
    c('val_int_integral_double_rejected', 'An integral double is a number, not an int.',
        const ['type', 'int', 'rejection'], typed('int'), '{ a: 1.0 }'),
    c('val_int_string_rejected', 'A numeric string is not an int.',
        const ['type', 'int', 'rejection'], typed('int'), '{ a: "5" }'),
    c('val_number_int_ok', 'An integer is a valid number.',
        const ['type', 'number', 'accept'], typed('number'), '{ a: 2 }'),
    c('val_number_double_ok', 'A double is a valid number.',
        const ['type', 'number', 'accept'], typed('number'), '{ a: 1.5 }'),
    c('val_number_bool_rejected', 'A boolean is never a number.',
        const ['type', 'number', 'bool', 'rejection'], typed('number'), '{ a: true }'),
    c('val_number_huge_int_ok', 'A huge integer is a valid number (no exact bound).',
        const ['type', 'number', 'big-int', 'accept'], typed('number'),
        '{ a: 10000000000000000000000000000000000000000 }'),
    c('val_bool_true_ok', 'true satisfies a bool node.',
        const ['type', 'bool', 'accept'], typed('bool'), '{ a: true }'),
    c('val_bool_false_ok', 'false satisfies a bool node.',
        const ['type', 'bool', 'accept'], typed('bool'), '{ a: false }'),
    c('val_bool_int_rejected', '1 is not a bool.',
        const ['type', 'bool', 'rejection'], typed('bool'), '{ a: 1 }'),
    c('val_null_type_ok', 'null satisfies a null node.',
        const ['type', 'null', 'accept'], typed('null'), '{ a: null }'),
    c('val_null_type_rejects_value', 'A string is not null.',
        const ['type', 'null', 'rejection'], typed('null'), '{ a: "x" }'),
    c('val_object_ok', 'An object satisfies an object node.',
        const ['type', 'object', 'accept'],
        'o: { type: "object", children: { b: { type: "int" } } }', '{ o: { b: 1 } }'),
    c('val_array_ok', 'An array satisfies an array node.',
        const ['type', 'array', 'accept'],
        'l: { type: "array", children: { type: "int" } }', '{ l: [1, 2] }'),
    c('val_any_accepts_string', 'The opaque type accepts a string.',
        const ['type', 'any', 'accept'], typed('any'), '{ a: "x" }'),
    c('val_any_accepts_object', 'The opaque type accepts an object.',
        const ['type', 'any', 'accept'], typed('any'), '{ a: { deep: [1, null] } }'),
    c('val_any_skips_type_rule', 'The opaque type is checked before any type rule.',
        const ['type', 'any', 'accept'], typed('any'), '{ a: true }'),
  ];
}

// -- null and leaf states --------------------------------------------------------

List<CorpusCase> _nullCases() {
  CorpusCase c(String id, String description, List<String> classes, String body, String value) =>
      _val(id, description, classes, descriptor: oneChild(body), value: value);
  return [
    c('val_null_plain_rejected', 'null on a non-nullable node is a nullable issue.',
        const ['null', 'rejection'], typed('string'), '{ a: null }'),
    c('val_null_nullable_ok', 'A nullable node admits an explicit null.',
        const ['null', 'accept'], typed('string', ', nullable: true'), '{ a: null }'),
    c('val_any_null_short_circuit', 'The opaque type is checked before the null rule.',
        const ['null', 'any', 'accept'], typed('any'), '{ a: null }'),
    c('val_zero_present', 'zero is a present value.',
        const ['leaf-state', 'int', 'accept'], typed('int'), '{ a: 0 }'),
    c('val_empty_string_present', 'The empty string is a present value.',
        const ['leaf-state', 'string', 'empty', 'accept'], typed('string'), '{ a: "" }'),
  ];
}

// -- exact integer range and bounds ----------------------------------------------

List<CorpusCase> _boundsCases() {
  CorpusCase c(String id, String description, List<String> classes, String body, String value,
          {Map<String, Object?>? divergence}) =>
      _val(id, description, classes,
          descriptor: oneChild(body), value: value, divergence: divergence);
  return [
    c('val_exact_max_ok', 'The exact maximum is accepted for int.',
        const ['exact-range', 'int', 'accept'], typed('int'), '{ a: 9007199254740991 }'),
    c('val_exact_min_ok', 'The exact minimum is accepted for int.',
        const ['exact-range', 'int', 'accept'], typed('int'), '{ a: -9007199254740991 }'),
    c('val_exact_over_rejected', 'Just above the exact maximum is refused.',
        const ['exact-range', 'int', 'rejection'], typed('int'), '{ a: 9007199254740992 }'),
    c('val_exact_under_rejected', 'Just below the exact minimum is refused.',
        const ['exact-range', 'int', 'rejection'], typed('int'), '{ a: -9007199254740992 }'),
    c('val_exact_huge_rejected', 'A forty-digit integer is refused for int.',
        const ['exact-range', 'int', 'big-int', 'rejection'], typed('int'),
        '{ a: 10000000000000000000000000000000000000000 }'),
    c('val_minimum_boundary', 'A value at minimum passes.',
        const ['bounds', 'minimum', 'accept'], typed('int', ', minimum: 5'), '{ a: 5 }'),
    c('val_minimum_below', 'A value under minimum fails.',
        const ['bounds', 'minimum', 'rejection'], typed('int', ', minimum: 5'), '{ a: 4 }'),
    c('val_maximum_boundary', 'A value at maximum passes.',
        const ['bounds', 'maximum', 'accept'], typed('int', ', maximum: 5'), '{ a: 5 }'),
    c('val_maximum_over', 'A value over maximum fails.',
        const ['bounds', 'maximum', 'rejection'], typed('int', ', maximum: 5'), '{ a: 6 }'),
    c('val_bounds_integral_double', 'An integral double satisfies a number bound.',
        const ['bounds', 'number', 'accept'], typed('number', ', minimum: 0.5'), '{ a: 1 }'),
    c('val_bounds_fractional_below', 'A fractional bound rejects a smaller value.',
        const ['bounds', 'number', 'rejection'], typed('number', ', minimum: 0.5'),
        '{ a: 0.25 }'),
    c('val_bounds_nonfinite_number', 'A non-finite number on a number node is a finite issue.',
        const ['bounds', 'finite', 'number', 'rejection'], typed('number'), '{ a: 1e400 }'),
    c('val_bounds_nonfinite_any', 'A non-finite number under the opaque type is caught by the walk.',
        const ['bounds', 'finite', 'any', 'rejection'], typed('any'), '{ a: -1e400 }'),
    c('val_bounds_huge_below', 'A value below a huge integer bound passes.',
        const ['bounds', 'big-int', 'exact', 'accept'],
        typed('number', ', maximum: 9007199254740993'), '{ a: 9007199254740992 }'),
    c(
      'val_bounds_huge_above',
      'A value above a huge integer bound fails, even when both round '
          'to the same double. Executed-baseline evidence: Python compares an '
          'int-to-int bound with exact integer `>`, so it already refuses this '
          'value; only the enum/const path (`_same`, float()) '
          'has the collision (val_enum_huge_int_collision).',
      const ['bounds', 'big-int', 'exact', 'rejection'],
      typed('number', ', maximum: 9007199254740993'),
      '{ a: 9007199254740994 }',
    ),
  ];
}

// -- const and enum --------------------------------------------------------------

List<CorpusCase> _constEnumCases() {
  CorpusCase c(String id, String description, List<String> classes, String body, String value,
          {Map<String, Object?>? divergence}) =>
      _val(id, description, classes,
          descriptor: oneChild(body), value: value, divergence: divergence);
  return [
    c('val_const_match', 'A value equal to const passes.',
        const ['const', 'accept'], typed('string', ', const: "x"'), '{ a: "x" }'),
    c('val_const_mismatch', 'A different value fails const.',
        const ['const', 'rejection'], typed('string', ', const: "x"'), '{ a: "y" }'),
    c('val_const_bool_vs_int', 'true is not the integer 1.',
        const ['const', 'bool', 'rejection'], typed('any', ', const: true'), '{ a: 1 }'),
    c('val_const_int_vs_bool', '1 is not true.',
        const ['const', 'bool', 'rejection'], typed('any', ', const: 1'), '{ a: true }'),
    c('val_const_integral_double_number', 'An integral double equals a number-node const.',
        const ['const', 'number', 'accept'], typed('number', ', const: 2'), '{ a: 2.0 }'),
    c('val_const_nested_object', 'A whole nested object can be the fixed value.',
        const ['const', 'object', 'accept'], typed('any', ', const: {k: [1, {m: 2}]}'),
        '{ a: {k: [1, {m: 2}]} }'),
    c('val_const_dict_key_order', 'Object const ignores key order.',
        const ['const', 'object', 'accept'], typed('any', ', const: {x: 1, y: 2}'),
        '{ a: {y: 2, x: 1} }'),
    c('val_const_null', 'null can be the fixed value of a null node.',
        const ['const', 'null', 'accept'], typed('null', ', const: null'), '{ a: null }'),
    c('val_enum_match', 'A value inside the enum passes.',
        const ['enum', 'accept'], typed('string', ', enum: ["a", "b"]'), '{ a: "b" }'),
    c('val_enum_mismatch', 'A value outside the enum fails.',
        const ['enum', 'rejection'], typed('string', ', enum: ["a", "b"]'), '{ a: "c" }'),
    c('val_enum_number_vs_string', 'A number is not a listed string.',
        const ['enum', 'rejection'], typed('any', ', enum: [1]'), '{ a: "1" }'),
    c('val_enum_object_member', 'An object can be an enum member.',
        const ['enum', 'object', 'accept'], typed('any', ', enum: [{k: 1}]'), '{ a: {k: 1} }'),
    c('val_enum_list_member', 'A list can be an enum member.',
        const ['enum', 'array', 'accept'], typed('any', ', enum: [[1, 2]]'), '{ a: [1, 2] }'),
    c(
      'val_enum_huge_int_collision',
      'Distinct integers past 2^53 are distinct enum members.',
      const ['enum', 'big-int', 'exact-range', 'A34'],
      typed('number', ', enum: [9007199254740993]'),
      '{ a: 9007199254740992 }',
      divergence: _corrected(
        id: 'A34',
        report: 'A34',
        note: 'The baseline compares every numeric const/enum member through float(), so two '
            'distinct integers above the exactly representable range collapse to the same double: '
            'an enum of [9007199254740993] accepts the value 9007199254740992. docs/grammars.md '
            '§2 forbids silent rounding; the Dart implementation compares exactly and '
            'rejects the different integer.',
        corrected: {
          'ok': true,
          'valid': false,
          'issues': [issue('enum', '/a')],
        },
      ),
    ),
  ];
}

// -- union selection -------------------------------------------------------------

List<CorpusCase> _unionCases() {
  CorpusCase c(String id, String description, List<String> classes, String body, String value,
          {Map<String, Object?>? divergence}) =>
      _val(id, description, classes,
          descriptor: oneChild(body), value: value, divergence: divergence);
  const union = 'u: { type: "union", children_options: '
      '[ { type: "int", minimum: 10 }, { type: "string", min_length: 5 } ] }';
  return [
    c('val_union_first_alt', 'A value matching the first alternative passes.',
        const ['union', 'accept'], union, '{ u: 42 }'),
    c('val_union_second_alt', 'A value matching the second alternative passes.',
        const ['union', 'accept'], union, '{ u: "hello" }'),
    c('val_union_none_rejected', 'A value matching no alternative fails.',
        const ['union', 'rejection'], union, '{ u: "hi" }'),
    c('val_union_nested_alt_fails', 'A failing object alternative reports the union.',
        const ['union', 'rejection', 'object'],
        'u: { type: "union", children_options: '
            '[ { type: "object", children: { a: { type: "int" } } } ] }',
        '{ u: { a: "x" } }'),
    c('val_union_single_alt_reports_union',
        'A single failing alternative still reports the aggregated union issue.',
        const ['union', 'rejection'],
        'u: { type: "union", children_options: [ { type: "int", minimum: 10 } ] }',
        '{ u: 5 }'),
    c('val_union_null_rejected_when_none_admits',
        'A null value with no null-admitting alternative is refused.',
        const ['union', 'null', 'rejection'],
        'u: { type: "union", children_options: [ { type: "int" }, { type: "string" } ] }',
        '{ u: null }'),
    c(
      'val_union_null_admits_null_alternative',
      'A null value is admitted when an alternative is null-typed.',
      const ['union', 'null', 'accept', 'A35'],
      'u: { type: "union", children_options: [ { type: "null" }, { type: "int" } ] }',
      '{ u: null }',
      divergence: _corrected(
        id: 'A35',
        report: 'A35',
        note: 'The baseline applies the null rule to the union node itself, before it ever '
            'consults the alternatives, so a union of {null} and {int} rejects null with a '
            'nullable issue even though one alternative is exactly null. The Dart '
            'implementation lets a null reach the alternatives, so the null-typed member '
            'admits it.',
        corrected: {'ok': true, 'valid': true, 'issues': []},
      ),
    ),
    c(
      'val_union_null_admits_nullable_alternative',
      'A null value is admitted when an alternative is nullable.',
      const ['union', 'null', 'accept', 'A35'],
      'u: { type: "union", children_options: [ { type: "int" }, '
          '{ type: "string", nullable: true } ] }',
      '{ u: null }',
      divergence: _corrected(
        id: 'A35',
        report: 'A35',
        note: 'Same root cause as val_union_null_admits_null_alternative: the baseline refuses '
            'null at the union node before consulting the nullable alternative.',
        corrected: {'ok': true, 'valid': true, 'issues': []},
      ),
    ),
  ];
}

// -- object governance -----------------------------------------------------------

List<CorpusCase> _objectCases() {
  CorpusCase c(String id, String description, List<String> classes, String body, String value,
          {Map<String, Object?>? limits, Map<String, Object?>? divergence}) =>
      _val(id, description, classes,
          descriptor: oneChild(body), value: value,
          limits: limits, divergence: divergence);
  return [
    c('val_object_undeclared_field', 'An extra field on a closed object is undeclared.',
        const ['object', 'rejection', 'undeclared'],
        'o: { type: "object", children: { a: { type: "int" } } }',
        '{ o: { a: 1, b: 2 } }'),
    c('val_object_dynamic_key_ok', 'additional_children governs an undeclared key.',
        const ['object', 'dynamic', 'accept'],
        'o: { type: "object", additional_children: { type: "int" } }',
        '{ o: { any: 1 } }'),
    c('val_object_dynamic_key_bad_value', 'A governed dynamic key still checks its value.',
        const ['object', 'dynamic', 'rejection'],
        'o: { type: "object", additional_children: { type: "int" } }',
        '{ o: { any: "x" } }'),
    c('val_object_key_enum_reject', 'A key outside key_enum is reported and its value still checked.',
        const ['object', 'key-enum', 'rejection'],
        'o: { type: "object", key_enum: ["ok"], additional_children: { type: "int" } }',
        '{ o: { no: "x" } }'),
    c('val_object_key_enum_allow', 'A declared key_enum member is governed.',
        const ['object', 'key-enum', 'accept'],
        'o: { type: "object", key_enum: ["ok"], additional_children: { type: "int" } }',
        '{ o: { ok: 1 } }'),
    c('val_object_key_pattern_prefix_ok', 'A key that starts with the pattern is governed.',
        const ['object', 'key-pattern', 'accept'],
        'o: { type: "object", key_pattern: "^w", additional_children: { type: "int" } }',
        '{ o: { worker: 1 } }'),
    c('val_object_key_pattern_reject', 'A key the pattern cannot match is refused.',
        const ['object', 'key-pattern', 'rejection'],
        'o: { type: "object", key_pattern: "^w", additional_children: { type: "int" } }',
        '{ o: { nohit: 1 } }'),
    c('val_object_key_pattern_empty_enum_allows',
        'An empty key_enum constrains nothing (falsy, like the baseline).',
        const ['object', 'key-enum', 'accept'],
        'o: { type: "object", key_enum: [], additional_children: { type: "int" } }',
        '{ o: { whatever: 1 } }'),
    c('val_object_declared_child_wins', 'A declared child takes precedence over key constraints.',
        const ['object', 'key-enum', 'accept'],
        'o: { type: "object", children: { a: { type: "string" } }, key_enum: ["b"], '
            'additional_children: { type: "int" } }',
        '{ o: { a: "s" } }'),
    c('val_object_required_missing', 'A missing required field is reported.',
        const ['object', 'required', 'rejection'],
        'o: { type: "object", children: { a: { type: "int", required: true } } }',
        '{ o: {} }'),
    c('val_object_required_present', 'A present required field passes.',
        const ['object', 'required', 'accept'],
        'o: { type: "object", children: { a: { type: "int", required: true } } }',
        '{ o: { a: 1 } }'),
    c('val_object_required_escaped_path', 'A required key with a slash escapes its path.',
        const ['object', 'required', 'paths', 'rejection'],
        'o: { type: "object", children: { "a/b": { type: "int", required: true } } }',
        '{ o: {} }'),
    c('val_object_required_tilde_path', 'A required key with a tilde escapes its path.',
        const ['object', 'required', 'paths', 'rejection'],
        'o: { type: "object", children: { "a~b": { type: "int", required: true } } }',
        '{ o: {} }'),
    c('val_object_nested_paths', 'Nested issues report their full pointer.',
        const ['object', 'array', 'paths', 'rejection'],
        'o: { type: "object", additional_children: { type: "array", children: { '
            'type: "object", children: { "k/1": { type: "int" } } } } }',
        '{ o: { s: [ { "k/1": "x", c: 1 } ] } }'),
    c(
      'val_object_key_pattern_search_vs_prefix',
      'A non-anchored key_pattern governs by prefix, not by an interior match.',
      const ['object', 'key-pattern', 'governance', 'A25'],
      'o: { type: "object", key_pattern: "worker", additional_children: { type: "int" } }',
      '{ o: { xworker: 1 } }',
      divergence: _corrected(
        id: 'A25',
        report: 'A25',
        note: 'Report A25 is the baseline answering which keys an object governs differently '
            'in different places. The validator governs the key with re.search, so '
            'key_pattern "worker" accepts the key "xworker", while node_at and the resolver '
            'use a prefix match and refuse it. The Dart implementation uses one prefix '
            'predicate everywhere, so an object never governs a key its own node lookup '
            'rejects.',
        corrected: {
          'ok': true,
          'valid': false,
          'issues': [issue('key_pattern', '/o/xworker')],
        },
      ),
    ),
    c(
      'val_object_key_pattern_dialect',
      'A lookaround in key_pattern is refused as a dialect issue here; the baseline reports a plain key mismatch.',
      const ['object', 'key-pattern', 'dialect', _dialect],
      'o: { type: "object", key_pattern: "(?=worker)x", additional_children: { type: "int" } }',
      '{ o: { xworker: 1 } }',
      divergence: _corrected(
        id: _dialect,
        report: _dialect,
        note: '$_dialectPrefix docs/grammars.md §1.3 requires key_pattern to be checked the same '
            'way as pattern. The baseline key check calls the regex directly without the '
            'portability screen, so a lookaround key_pattern is judged only by its (search) match '
            'result and reported against the data. Here the dialect check names the construct '
            'first, as a `pattern` issue. Both refuse the key; the rule and the explanation differ.',
        corrected: {
          'ok': true,
          'valid': false,
          'issues': [issue('pattern', '/o/xworker')],
        },
      ),
    ),
    c(
      'val_object_key_pattern_too_long',
      'An over-long key_pattern reports pattern_length here; the baseline reports a plain key mismatch.',
      const ['object', 'key-pattern', 'pattern-length', _dialect],
      'o: { type: "object", key_pattern: "xxxxxxxxx", additional_children: { type: "int" } }',
      '{ o: { y: 1 } }',
      limits: const {'max_pattern_length': 5},
      divergence: _corrected(
        id: _dialect,
        report: _dialect,
        note: '$_dialectPrefix docs/grammars.md §1.3 checks the pattern length before the pattern '
            'is compiled or matched, and key_pattern is checked the same way as pattern. The '
            'baseline applies the length bound only to a value pattern; an over-long key_pattern '
            'is handed to the engine and reported as an ordinary key mismatch, which reads as a '
            'data problem rather than a descriptor problem.',
        corrected: {
          'ok': true,
          'valid': false,
          'issues': [issue('pattern_length', '/o/y')],
        },
      ),
    ),
  ];
}

// -- array -----------------------------------------------------------------------

List<CorpusCase> _arrayCases() {
  CorpusCase c(String id, String description, List<String> classes, String body, String value) =>
      _val(id, description, classes, descriptor: oneChild(body), value: value);
  return [
    c('val_array_item_type', 'An item of the wrong type reports its index path.',
        const ['array', 'type', 'rejection'],
        'l: { type: "array", children: { type: "int" } }',
        '{ l: [1, "x", 3] }'),
    c('val_array_min_items_boundary', 'An array of exactly min_items passes.',
        const ['array', 'min-items', 'accept'],
        'l: { type: "array", children: { type: "int" }, min_items: 2 }', '{ l: [1, 2] }'),
    c('val_array_min_items_below', 'One item short of min_items fails.',
        const ['array', 'min-items', 'rejection'],
        'l: { type: "array", children: { type: "int" }, min_items: 2 }', '{ l: [1] }'),
    c('val_array_max_items_boundary', 'An array of exactly max_items passes.',
        const ['array', 'max-items', 'accept'],
        'l: { type: "array", children: { type: "int" }, max_items: 2 }', '{ l: [1, 2] }'),
    c('val_array_max_items_over', 'One item over max_items fails.',
        const ['array', 'max-items', 'rejection'],
        'l: { type: "array", children: { type: "int" }, max_items: 2 }', '{ l: [1, 2, 3] }'),
    c('val_array_unique_ok', 'Distinct items pass unique_items.',
        const ['array', 'unique-items', 'accept'],
        'l: { type: "array", children: { type: "int" }, unique_items: true }', '{ l: [1, 2, 3] }'),
    c('val_array_unique_dup_first_index', 'A duplicate is reported at the first index.',
        const ['array', 'unique-items', 'rejection'],
        'l: { type: "array", children: { type: "int" }, unique_items: true }', '{ l: [5, 5, 5] }'),
    c('val_array_unique_dup_nonadjacent', 'A non-adjacent duplicate is still found.',
        const ['array', 'unique-items', 'rejection'],
        'l: { type: "array", children: { type: "int" }, unique_items: true }', '{ l: [1, 2, 3, 2] }'),
    c('val_array_unique_number_vs_double', '1 and 1.0 are the same value for uniqueness.',
        const ['array', 'unique-items', 'number', 'rejection'],
        'l: { type: "array", children: { type: "any" }, unique_items: true }', '{ l: [1, 1.0] }'),
    c('val_array_unique_bool_vs_int', 'true and 1 are distinct for uniqueness.',
        const ['array', 'unique-items', 'bool', 'accept'],
        'l: { type: "array", children: { type: "any" }, unique_items: true }', '{ l: [true, 1] }'),
    c('val_array_unique_objects', 'Equal nested objects are duplicates.',
        const ['array', 'unique-items', 'object', 'rejection'],
        'l: { type: "array", children: { type: "any" }, unique_items: true }',
        '{ l: [{a: 1}, {a: 1}] }'),
    c('val_array_heterogeneous_alternatives',
        'Each item of a children_options array is checked against every alternative.',
        const ['array', 'union', 'accept'],
        'l: { type: "array", children_options: [ { type: "object", '
            'children: { op: { type: "string" } } }, { type: "int" } ] }',
        '{ l: [ { op: "run" }, 3 ] }'),
    c('val_array_heterogeneous_none_match',
        'An item that matches no array alternative reports the union.',
        const ['array', 'union', 'rejection'],
        'l: { type: "array", children_options: [ { type: "int" }, { type: "bool" } ] }',
        '{ l: ["x"] }'),
    c('val_array_empty_ok', 'An empty array satisfies an item node.',
        const ['array', 'accept'], 'l: { type: "array", children: { type: "int" } }', '{ l: [] }'),
    c('val_array_nested_arrays', 'Arrays of arrays keep index paths.',
        const ['array', 'nested', 'rejection'],
        'm: { type: "array", children: { type: "array", children: { type: "int" } } }',
        '{ m: [[1], ["x"]] }'),
  ];
}

// -- string length ---------------------------------------------------------------

List<CorpusCase> _stringLengthCases() {
  CorpusCase c(String id, String description, List<String> classes, String body, String value) =>
      _val(id, description, classes, descriptor: oneChild(body), value: value);
  return [
    c('val_string_min_length_ok', 'A string at min_length passes.',
        const ['string', 'min-length', 'accept'], typed('string', ', min_length: 3'),
        '{ a: "abc" }'),
    c('val_string_min_length_below', 'A shorter string fails min_length.',
        const ['string', 'min-length', 'rejection'], typed('string', ', min_length: 3'),
        '{ a: "ab" }'),
    c('val_string_max_length_ok', 'A string at max_length passes.',
        const ['string', 'max-length', 'accept'], typed('string', ', max_length: 3'),
        '{ a: "abc" }'),
    c('val_string_max_length_over', 'A longer string fails max_length.',
        const ['string', 'max-length', 'rejection'], typed('string', ', max_length: 3'),
        '{ a: "abcd" }'),
    c('val_string_length_astral_code_points',
        'Astral characters count as one code point toward max_length.',
        const ['string', 'max-length', 'astral', 'accept'], typed('string', ', max_length: 3'),
        '{ a: "\u{1F680}\u{1F680}\u{1F680}" }'),
    c('val_string_length_astral_over', 'A fourth astral character exceeds max_length 3.',
        const ['string', 'max-length', 'astral', 'rejection'], typed('string', ', max_length: 3'),
        '{ a: "\u{1F680}\u{1F680}\u{1F680}\u{1F680}" }'),
  ];
}

// -- accepted regex constructs ---------------------------------------------------

List<CorpusCase> _acceptedPatternCases() {
  return [
    _patternCase('val_pattern_literal_ok', 'An accepted anchored pattern matches.',
        const ['pattern', 'accept'], pattern: r'^ab+$', valueText: 'abbb'),
    _patternCase('val_pattern_literal_mismatch', 'A value the accepted pattern rejects fails.',
        const ['pattern', 'rejection'], pattern: r'^b', valueText: 'abc'),
    _patternCase('val_pattern_unanchored_search', 'An unanchored pattern matches anywhere.',
        const ['pattern', 'accept'], pattern: r'b', valueText: 'abc'),
    _patternCase('val_pattern_dot', 'A dot matches any non-line-break character.',
        const ['pattern', 'accept'], pattern: r'a.b', valueText: 'aXb'),
    _patternCase('val_pattern_class_range', 'A character class range is accepted.',
        const ['pattern', 'accept'], pattern: r'^[a-f]+$', valueText: 'cde'),
    _patternCase('val_pattern_class_negated', 'A negated class is accepted.',
        const ['pattern', 'accept'], pattern: r'^[^0-9]+$', valueText: 'abc'),
    _patternCase('val_pattern_quantifier_range', 'A bounded quantifier is accepted.',
        const ['pattern', 'accept'], pattern: r'a{2,3}', valueText: 'aaa'),
    _patternCase('val_pattern_quantifier_open_range', 'An open quantifier range is accepted.',
        const ['pattern', 'accept'], pattern: r'a{2,}', valueText: 'aaaa'),
    _patternCase('val_pattern_lazy_quantifier', 'A lazy quantifier is accepted.',
        const ['pattern', 'accept'], pattern: r'a+?b', valueText: 'aab'),
    _patternCase('val_pattern_noncapture', 'A non-capturing group is accepted.',
        const ['pattern', 'accept'], pattern: r'(?:ab)+', valueText: 'abab'),
    _patternCase('val_pattern_capture_no_ref', 'A capturing group with no backreference is accepted.',
        const ['pattern', 'accept'], pattern: r'(ab)c', valueText: 'abc'),
    _patternCase('val_pattern_alternation', 'Alternation is accepted.',
        const ['pattern', 'accept'], pattern: r'cat|dog', valueText: 'dog'),
    _patternCase('val_pattern_word_boundary', 'A word boundary is accepted.',
        const ['pattern', 'accept'], pattern: r'\bword\b', valueText: 'a word here'),
    _patternCase('val_pattern_digit_class_ascii', 'An ASCII digit value matches the digit class.',
        const ['pattern', 'shorthand', 'accept'], pattern: r'^\d+$', valueText: '12'),
    _patternCase('val_pattern_hex_escape', 'A hex escape is accepted.',
        const ['pattern', 'accept'], pattern: r'\x41', valueText: 'A'),
    _patternCase('val_pattern_escaped_brace', 'An escaped brace is a literal.',
        const ['pattern', 'accept'], pattern: r'\{a\}', valueText: '{a}'),
    _patternCase('val_pattern_empty_skipped', 'An empty pattern constrains nothing.',
        const ['pattern', 'empty', 'accept'], pattern: '', valueText: 'anything'),
  ];
}

// -- rejected regex constructs the baseline also refuses -----------------------

List<CorpusCase> _agreedRejectionCases() {
  return [
    _patternCase('val_pattern_lookahead_agrees', 'A lookahead is refused as a dialect issue by both.',
        const ['pattern', 'dialect', 'lookaround', 'agree'], pattern: r'(?=x)y', valueText: 'xy'),
    _patternCase('val_pattern_lookbehind_agrees', 'A lookbehind is refused as a dialect issue by both.',
        const ['pattern', 'dialect', 'lookaround', 'agree'], pattern: r'(?<=x)y', valueText: 'xy'),
    _patternCase('val_pattern_backref_agrees', 'A numeric backreference is refused as a dialect issue by both.',
        const ['pattern', 'dialect', 'backreference', 'agree'], pattern: r'(a)\1', valueText: 'aa'),
    _patternCase('val_pattern_python_named_backref_agrees',
        'The Python-spelled named backreference is refused at the descriptor by both engines.',
        const ['pattern', 'dialect', 'named-backreference', 'descriptor', 'agree'],
        pattern: r'(a)(?P=1)', valueText: 'aa'),
    _patternCase('val_pattern_posix_literal_set_agrees',
        'A POSIX class reads as a literal set on both engines, and the value matches on neither.',
        const ['pattern', 'dialect', 'posix', 'agree'], pattern: r'[[:alpha:]]+', valueText: 'abc'),
    _patternCase('val_pattern_nested_unbounded_agrees',
        'A nested unbounded repetition is refused here before matching; the value needs a trailing b that neither engine finds.',
        const ['pattern', 'dialect', 'budget', 'agree'], pattern: r'(a+)+b', valueText: 'aaa'),
    _patternCase('val_pattern_octal_escape_agrees',
        'A multi-digit octal escape reads as the backspace character on both engines, and the value matches on both.',
        const ['pattern', 'escape', 'octal', 'agree'], pattern: r'\010', valueText: '\b'),
  ];
}

// -- constructs the accepted dialect refuses; the baseline accepts or
//    refuses at a different layer. Documented, executed-verified divergences.
//
// Every split below was decided by **executing** the baseline and this
// implementation on the same case, not by reading either source:
// `docs/grammars.md` §1.2 fixes the layer, and where the
// executed baseline lands on the other layer the case is a
// `SPEC26-DIALECT` divergence asserting this product's §1.2 position.
List<CorpusCase> _dialectDivergenceCases() {
  return [
    // -- constructs the baseline engine compiles and this one does not:
    //    refused at the descriptor here, loaded and matched there.
    _patternCase(
      'val_pattern_inline_flag_split',
      'A bare inline flag is refused at the descriptor here; the baseline compiles it and matches.',
      const ['pattern', 'dialect', 'inline-flag', _dialect],
      pattern: r'(?i)abc',
      valueText: 'ABC',
      divergence: _corrected(
        id: _dialect,
        report: _dialect,
        note: '$_dialectPrefix This engine cannot compile a bare inline flag, so the '
            'descriptor compiler refuses the whole descriptor with INVALID_PATTERN, the layer '
            'docs §1.2 and §1.3 name for it (the baseline engine compiles the flag and '
            'applies it, so the file loads and matches there).',
        corrected: rejectedDescriptor(),
      ),
    ),
    _patternCase(
      'val_pattern_python_named_group_split',
      'A Python-spelled named group is refused at the descriptor here; the baseline compiles and matches.',
      const ['pattern', 'dialect', 'named-group', 'python', _dialect],
      pattern: r'(?P<n>a)',
      valueText: 'a',
      divergence: _corrected(
        id: _dialect,
        report: _dialect,
        note: '$_dialectPrefix This engine cannot compile the Python spelling of a named group, so '
            'the descriptor compiler refuses with INVALID_PATTERN — exactly the layer docs §1.2 '
            'names. The baseline compiles it and accepts the match.',
        corrected: rejectedDescriptor(),
      ),
    ),
    _patternCase(
      'val_pattern_comment_split',
      'A pattern comment is refused at the descriptor here; the baseline compiles and matches.',
      const ['pattern', 'dialect', 'comment', _dialect],
      pattern: r'(?#c)abc',
      valueText: 'abc',
      divergence: _corrected(
        id: _dialect,
        report: _dialect,
        note: '$_dialectPrefix This engine cannot compile a pattern comment, so the descriptor '
            'compiler refuses with INVALID_PATTERN. The baseline compiles the comment and drops it, '
            'accepting the match.',
        corrected: rejectedDescriptor(),
      ),
    ),
    _patternCase(
      'val_pattern_conditional_split',
      'A conditional pattern is refused at the descriptor here; the baseline compiles and matches.',
      const ['pattern', 'dialect', 'conditional', _dialect],
      pattern: r'(a)(?(1)b|c)',
      valueText: 'ab',
      divergence: _corrected(
        id: _dialect,
        report: _dialect,
        note: '$_dialectPrefix This engine cannot compile a conditional pattern, so the descriptor '
            'compiler refuses with INVALID_PATTERN. The baseline engine supports it and accepts the '
            'match.',
        corrected: rejectedDescriptor(),
      ),
    ),
    // -- constructs the baseline engine cannot compile (so its descriptor
    //    check refuses the file) but this one compiles: the dialect scan
    //    names them at validation, the layer docs §1.2 assigns them to.
    _patternCase(
      'val_pattern_ecma_named_group_split',
      'A named group in ECMAScript spelling is refused by the baseline descriptor and by validation here.',
      const ['pattern', 'dialect', 'named-group', 'ecma', _dialect],
      pattern: r'(?<n>a)',
      valueText: 'a',
      divergence: _corrected(
        id: _dialect,
        report: _dialect,
        note: '$_dialectPrefix The baseline engine cannot compile the ECMAScript named group, '
            'so its descriptor compile check refuses the file; this engine '
            'compiles it, so the dialect scan names it at validation as the docs §1.2 '
            'named-group row prescribes (that row assigns the construct to the '
            'validation `pattern` reading precisely because only one engine can '
            'compile it). Both refuse the pattern and neither matches data with it; '
            'the layer differs, per §1.2.',
        corrected: {
          'ok': true,
          'valid': false,
          'issues': [issue('pattern', '/a')],
        },
      ),
    ),
    _patternCase(
      'val_pattern_ecma_named_backref_split',
      'An ECMAScript named backreference is refused by the baseline descriptor and by validation here.',
      const ['pattern', 'dialect', 'named-backreference', 'ecma', _dialect],
      pattern: r'(?<n>a)\k<n>',
      valueText: 'aa',
      divergence: _corrected(
        id: _dialect,
        report: _dialect,
        note: '$_dialectPrefix Same documented row as val_pattern_ecma_named_group_split, on the '
            'named backreference: the baseline cannot compile it (descriptor refusal), this '
            'engine can and names it at validation.',
        corrected: {
          'ok': true,
          'valid': false,
          'issues': [issue('pattern', '/a')],
        },
      ),
    ),
    _patternCase(
      'val_pattern_group_reference_split',
      'A replacement-spelling group reference is refused by the baseline descriptor and by validation here.',
      const ['pattern', 'dialect', 'group-reference', _dialect],
      pattern: r'(a)\g<1>',
      valueText: 'aa',
      divergence: _corrected(
        id: _dialect,
        report: _dialect,
        note: '$_dialectPrefix The baseline engine reads \\g as a bad escape, so '
            'its descriptor compile check refuses the file; this engine reads a literal g, so the '
            'dialect scan names the construct at validation as the docs §1.2 group-reference '
            'row prescribes.',
        corrected: {
          'ok': true,
          'valid': false,
          'issues': [issue('pattern', '/a')],
        },
      ),
    ),
    _patternCase(
      'val_pattern_property_class_split',
      'A Unicode property class is refused by the baseline descriptor and by validation here.',
      const ['pattern', 'dialect', 'property-class', _dialect],
      pattern: r'\p{L}',
      valueText: 'x',
      divergence: _corrected(
        id: _dialect,
        report: _dialect,
        note: '$_dialectPrefix The baseline `re` engine reads \\p as a bad escape, so its '
            'descriptor compile check refuses the file; this engine compiles a real property '
            'class, so the dialect scan refuses it at validation as the docs §1.2 '
            'property-class row prescribes (the engines read the same text '
            'differently, which is why the row exists).',
        corrected: {
          'ok': true,
          'valid': false,
          'issues': [issue('pattern', '/a')],
        },
      ),
    ),
    _patternCase(
      'val_pattern_undefined_backref_split',
      'A numeric backreference to an undefined group is refused by the baseline descriptor and by validation here.',
      const ['pattern', 'dialect', 'backreference', 'undefined', _dialect],
      pattern: r'(a)\2',
      valueText: 'aab',
      divergence: _corrected(
        id: _dialect,
        report: _dialect,
        note: '$_dialectPrefix The baseline engine refuses an undefined group reference '
            'at compile time, so its descriptor check refuses the file; this engine compiles it, so '
            'the dialect scan names the backreference at validation as the docs §1.2 '
            'numeric-backreference row prescribes. Both refuse; the layer differs.',
        corrected: {
          'ok': true,
          'valid': false,
          'issues': [issue('pattern', '/a')],
        },
      ),
    ),
    // -- constructs both engines compile but only the baseline applies:
    //    refused at validation here, loaded and matched there.
    _patternCase(
      'val_pattern_anchor_a_split',
      'A Python start anchor is refused at validation here; the baseline anchors the match.',
      const ['pattern', 'dialect', 'anchor', _dialect],
      pattern: r'\Aabc',
      valueText: 'abc',
      divergence: _corrected(
        id: _dialect,
        report: _dialect,
        note: '$_dialectPrefix This engine compiles \\A as a literal A, so the value does not '
            'match and the dialect scan names it as outside the dialect (a `pattern` issue). The '
            'baseline treats \\A as a start anchor and reports no issue. Both refuse the '
            'file eventually; docs §1.2 assigns this row to the validation `pattern` '
            'reading, which this product applies.',
        corrected: {
          'ok': true,
          'valid': false,
          'issues': [issue('pattern', '/a')],
        },
      ),
    ),
    _patternCase(
      'val_pattern_anchor_z_split',
      'A Python end anchor is refused at validation here; the baseline anchors the match.',
      const ['pattern', 'dialect', 'anchor', _dialect],
      pattern: r'abc\Z',
      valueText: 'abc',
      divergence: _corrected(
        id: _dialect,
        report: _dialect,
        note: 'Same documented row as val_pattern_anchor_a_split, on the end anchor.',
        corrected: {
          'ok': true,
          'valid': false,
          'issues': [issue('pattern', '/a')],
        },
      ),
    ),
    _patternCase(
      'val_pattern_scoped_flag_split',
      'A scoped inline flag is refused at validation here; the baseline applies the flag and matches.',
      const ['pattern', 'dialect', 'inline-flag', 'scoped', _dialect],
      pattern: r'(?i:abc)',
      valueText: 'ABC',
      divergence: _corrected(
        id: _dialect,
        report: _dialect,
        note: '$_dialectPrefix This engine compiles the scoped inline flag, so the dialect scan '
            'refuses it at validation as an inline flag (docs §1.2 excludes inline flags, '
            'the scoped form included). The baseline applies the flag and reports no issue for a '
            'value that matches only case-insensitively.',
        corrected: {
          'ok': true,
          'valid': false,
          'issues': [issue('pattern', '/a')],
        },
      ),
    ),
    _patternCase(
      'val_pattern_posix_value_split',
      'A value the accidental POSIX reading matches is refused here as outside the dialect.',
      const ['pattern', 'dialect', 'posix', _dialect],
      pattern: r'[[:alpha:]]+',
      valueText: 'a]',
      divergence: _corrected(
        id: _dialect,
        report: _dialect,
        note: '$_dialectPrefix Both engines read [[:alpha:]] as a class of the literal '
            'characters bracket, colon, a, l, p, h plus a stray bracket, so the pattern silently '
            'means something other than what it appears to say. Here the pattern itself is named as '
            'outside the dialect before any match; the baseline has no dialect gate and accepts the '
            'value this accidental reading matches.',
        corrected: {
          'ok': true,
          'valid': false,
          'issues': [issue('pattern', '/a')],
        },
      ),
    ),
    _patternCase(
      'val_pattern_unicode_shorthand_digit_split',
      'Arabic-Indic digits are classified differently by the two engines.',
      const ['pattern', 'dialect', 'unicode', 'shorthand', _dialect],
      pattern: r'^\d+$',
      valueText: '\u0662\u0660',
      divergence: _corrected(
        id: _dialect,
        report: _dialect,
        note: '$_dialectPrefix docs/grammars.md §1.1 records the measured semantic difference: the '
            'shorthand classes are ASCII in this product and Unicode-aware in the baseline engine. '
            'The pattern is accepted by both, but Arabic-Indic digits match there and not here. '
            'The document fixes the ASCII reading and tells an author who must classify non-ASCII '
            'text to state the ranges; the difference is intentional and document-anchored.',
        corrected: {
          'ok': true,
          'valid': false,
          'issues': [issue('pattern', '/a')],
        },
      ),
    ),
    _patternCase(
      'val_pattern_unicode_shorthand_word_split',
      'A Cyrillic word is classified differently by the two engines.',
      const ['pattern', 'dialect', 'unicode', 'shorthand', _dialect],
      pattern: r'^\w+$',
      valueText: '\u043f\u0440\u0438\u0432\u0435\u0442',
      divergence: _corrected(
        id: _dialect,
        report: _dialect,
        note: 'Same documented shorthand row as val_pattern_unicode_shorthand_digit_split, on the '
            'word class and a non-ASCII-letter value.',
        corrected: {
          'ok': true,
          'valid': false,
          'issues': [issue('pattern', '/a')],
        },
      ),
    ),
    _patternCase(
      'val_pattern_dollar_trailing_newline_split',
      'A trailing newline matches the end anchor in the baseline but not here.',
      const ['pattern', 'dialect', 'anchor', 'newline', _dialect],
      pattern: r'^a$',
      valueText: 'a\n',
      divergence: _corrected(
        id: _dialect,
        report: _dialect,
        note: '$_dialectPrefix docs/grammars.md §1.1 records the difference: the baseline end anchor '
            'also matches immediately before a single trailing newline, this engine does not, and an '
            'anchored pattern must not depend on that behavior. The baseline accepts the value; this '
            'product refuses it.',
        corrected: {
          'ok': true,
          'valid': false,
          'issues': [issue('pattern', '/a')],
        },
      ),
    ),
  ];
}

// -- misplaced constraints ---------------------------------------------------

/// A constraint declared on a type that does not carry it is refused by the
/// descriptor compiler in both engines — the value walk
/// never sees it. Recorded here to show the 2C contract
/// (which layer rejects a misplaced constraint) rather
/// than duplicating the descriptor corpus.
List<CorpusCase> _misplacedConstraintCases() {
  CorpusCase c(String id, String description, List<String> classes, String body) =>
      _val(id, description, classes, descriptor: oneChild(body), value: '{ a: 1 }');
  return [
    c('val_misplaced_string_minimum', 'A numeric bound on a string node is refused at the descriptor.',
        const ['misplaced', 'constraint-by-type', 'string', 'rejection'],
        'a: { type: "string", minimum: 5 }'),
    c('val_misplaced_int_pattern', 'A pattern on an int node is refused at the descriptor.',
        const ['misplaced', 'constraint-by-type', 'int', 'rejection'],
        'a: { type: "int", pattern: "x" }'),
    c('val_misplaced_array_min_length', 'A string length on an array node is refused at the descriptor.',
        const ['misplaced', 'constraint-by-type', 'array', 'rejection'],
        'a: { type: "array", children: { type: "int" }, min_length: 2 }'),
    c('val_misplaced_number_unique_items', 'Item uniqueness on a number node is refused at the descriptor.',
        const ['misplaced', 'constraint-by-type', 'number', 'rejection'],
        'a: { type: "number", unique_items: true }'),
  ];
}

// -- resource limits -------------------------------------------------------------

List<CorpusCase> _limitCases() {
  CorpusCase c(String id, String description, List<String> classes, String body, String value,
          Map<String, Object?> limits) =>
      _val(id, description, classes,
          descriptor: oneChild(body), value: value, limits: limits);
  return [
    c('val_limit_depth_at', 'A tree exactly at max_depth passes.',
        const ['limits', 'depth', 'at', 'accept'], typed('any'), '{ a: {n: {n: 1}} }',
        const {'max_depth': 3}),
    c('val_limit_depth_under', 'A tree just under max_depth passes.',
        const ['limits', 'depth', 'under', 'accept'], typed('any'), '{ a: {n: {n: 1}} }',
        const {'max_depth': 4}),
    c('val_limit_depth_over', 'One level past max_depth reports the over-deep node.',
        const ['limits', 'depth', 'over', 'rejection'], typed('any'), '{ a: {n: {n: {n: 1}}}}',
        const {'max_depth': 2}),
    c('val_limit_depth_root', 'The root counts as depth 0.',
        const ['limits', 'depth', 'over', 'rejection'], typed('any'), '{ a: 1 }', const {'max_depth': 0}),
    c('val_limit_collection_object_under', 'An object under max_collection_size passes.',
        const ['limits', 'collection', 'object', 'under', 'accept'], typed('any'),
        '{ o: {a: 1, b: 2} }', const {'max_collection_size': 3}),
    c('val_limit_collection_object_at', 'An object at max_collection_size passes.',
        const ['limits', 'collection', 'object', 'at', 'accept'], typed('any'),
        '{ o: {a: 1, b: 2, c: 3} }', const {'max_collection_size': 3}),
    c('val_limit_collection_object_over', 'One key past the limit reports the container.',
        const ['limits', 'collection', 'object', 'over', 'rejection'], typed('any'),
        '{ o: {a: 1, b: 2, c: 3, d: 4} }', const {'max_collection_size': 3}),
    c('val_limit_collection_array_at', 'An array at max_collection_size passes.',
        const ['limits', 'collection', 'array', 'at', 'accept'], typed('any'),
        '{ l: [1, 2, 3] }', const {'max_collection_size': 3}),
    c('val_limit_collection_array_under', 'An array under max_collection_size passes.',
        const ['limits', 'collection', 'array', 'under', 'accept'], typed('any'),
        '{ l: [1, 2] }', const {'max_collection_size': 3}),
    c('val_limit_collection_array_over', 'An oversized array reports the container path.',
        const ['limits', 'collection', 'array', 'over', 'rejection'], typed('any'),
        '{ l: [1, 2, 3, 4] }', const {'max_collection_size': 3}),
    c('val_limit_two_collections', 'Every oversized container is reported.',
        const ['limits', 'collection', 'over', 'rejection'], typed('any'),
        '{ o: {inner: [1, 2, 3, 4, 5]} }', const {'max_collection_size': 4}),
    c('val_limit_string_value_under', 'A string under max_string_length passes.',
        const ['limits', 'string', 'under', 'accept'], typed('any'), '{ a: "ab" }',
        const {'max_string_length': 3}),
    c('val_limit_string_value_at', 'A string at max_string_length passes.',
        const ['limits', 'string', 'at', 'accept'], typed('any'), '{ a: "abc" }',
        const {'max_string_length': 3}),
    c('val_limit_string_value_over', 'A long string value reports at its path.',
        const ['limits', 'string', 'over', 'rejection'], typed('any'), '{ a: "abcd" }',
        const {'max_string_length': 3}),
    c('val_limit_string_key_over', 'An oversized object key reports at the container path.',
        const ['limits', 'string', 'key', 'over', 'rejection'], typed('any'), '{ o: {toolong: 1} }',
        const {'max_string_length': 3}),
    c('val_limit_string_astral_code_points',
        'Astral characters count as one code point toward max_string_length.',
        const ['limits', 'string', 'at', 'astral', 'accept'], typed('any'),
        '{ a: "\u{1F680}\u{1F680}\u{1F680}" }', const {'max_string_length': 3}),
    c('val_limit_short_circuit',
        'A limit violation returns only the limit issues, not the constraint walk.',
        const ['limits', 'short-circuit', 'rejection'], typed('int', ', minimum: 100'),
        '{ a: 1, "b": 2 }', const {'max_depth': 0}),
    c('val_limit_pattern_length_under', 'A pattern under max_pattern_length is accepted.',
        const ['limits', 'pattern-length', 'under', 'accept'], typed('string', ', pattern: "xxxx"'),
        '{ a: "xxxx" }', const {'max_pattern_length': 5}),
    c('val_limit_pattern_length_at', 'A pattern at max_pattern_length is accepted.',
        const ['limits', 'pattern-length', 'at', 'accept'], typed('string', ', pattern: "xxxxx"'),
        '{ a: "xxxxx" }', const {'max_pattern_length': 5}),
    c('val_limit_pattern_length_over', 'A pattern past max_pattern_length reports pattern_length.',
        const ['limits', 'pattern-length', 'over', 'rejection'], typed('string', ', pattern: "xxxxxx"'),
        '{ a: "x" }', const {'max_pattern_length': 5}),
  ];
}

// -- direct entry-point cases ----------------------------------------------------

List<CorpusCase> _directCases() {
  const anyBody = 'a: { type: "any" }';
  return [
    _direct('val_direct_present_false', 'An absent field is not validated.',
        const ['present', 'accept'], value: tStr('x'), present: false),
    _direct('val_direct_present_false_const', 'present=False short-circuits even a const check.',
        const ['present', 'const', 'accept'],
        childBody: 'a: { type: "string", const: "z" }', value: tStr('x'), present: false),
    _direct('val_direct_undeclared_path', 'A null node reports undeclared_path.',
        const ['object', 'undeclared', 'rejection'], pointer: null, path: '/zzz', value: tStr('x')),
    _direct('val_direct_undeclared_path_present_false',
        'present=False does not hide an undeclared path.',
        const ['object', 'undeclared', 'present', 'rejection'],
        pointer: null, path: '/zzz', value: tStr('x'), present: false),
    _direct('val_direct_template_unresolved', 'A placeholder value is never validated as data.',
        const ['unresolved-template', 'rejection'],
        value: const {'template': {'name': 'V', 'default': null}}),
    _direct('val_direct_template_under_any',
        'Even the opaque type reports an unresolved placeholder.',
        const ['unresolved-template', 'any', 'rejection'], childBody: anyBody,
        value: const {'template': {'name': 'V', 'default': null}}),
    _direct('val_direct_template_present_false',
        'present=False does not hide an unresolved placeholder.',
        const ['unresolved-template', 'present', 'rejection'],
        value: const {'template': {'name': 'V', 'default': 'd'}}, present: false),
    _direct('val_direct_missing_under_any', 'The absence marker passes under the opaque type.',
        const ['missing', 'any', 'accept'], childBody: anyBody,
        value: const {'missing': true}),
    _direct('val_direct_missing_typed_rejects',
        'The absence marker under a typed node is a type error.',
        const ['missing', 'type', 'rejection'], childBody: 'a: { type: "int" }',
        value: const {'missing': true}),
  ];
}

/// The complete validator catalog.
List<CorpusCase> validatorCases() => [
      ..._profileCases(),
      ..._typeCases(),
      ..._nullCases(),
      ..._boundsCases(),
      ..._constEnumCases(),
      ..._unionCases(),
      ..._objectCases(),
      ..._arrayCases(),
      ..._stringLengthCases(),
      ..._acceptedPatternCases(),
      ..._agreedRejectionCases(),
      ..._dialectDivergenceCases(),
      ..._misplacedConstraintCases(),
      ..._limitCases(),
      ..._directCases(),
    ];
