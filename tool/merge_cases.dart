/// Merge and revision corpus cases for `tool/generate_corpus.dart` (slice 2D).
///
/// Every entry is **executed against the Python baseline** by
/// `tool/python/corpus_driver.py`; the expectations are what the baseline
/// produced, never what prose says. Which case is a divergence was decided
/// by diffing the executed baseline output against a Dart replay, not
/// by reading the baseline source.
///
/// Areas:
///
/// * `merge_base`          — `merge(base, update, prefer: "base")`,
///   the default of `SPEC.md` amendment 7.
/// * `merge_update`        — the same inputs with `prefer: "update"`.
/// * `merge_immutability`  — whether the merge left its inputs alone and
///   whether the result is a tree of its own. Two of these cases are
///   registered divergences; the six that are not exist precisely
///   because the executed baseline showed no aliasing for them, which is
///   the half of the rule the baseline already satisfies.
/// * `revision_compute`    — the source and descriptor revision of a
///   text, including the cases where UTF-8 bytes and Dart string
///   length disagree (BOM, CRLF, astral plane).
///
/// A merge case holds `base` and `update` in the tagged value encoding
/// the other areas already use, so the same decoder
/// (`corpus_expectations.dart`) reads them and the kind of a value —
/// Python `1`, `true` and `1.0` are three different stored
/// values — is pinned rather than left to JSON type inference.
library;

import 'corpus_cases.dart';

// -- tagged value builders -------------------------------------------------

Map<String, Object?> tNull() => const {'k': 'null'};
Map<String, Object?> tBool(bool v) => {'k': 'bool', 'v': v};
Map<String, Object?> tInt(String decimal) => {'k': 'int', 'v': decimal};
Map<String, Object?> tNum(double v) => {'k': 'double', 'v': v};
Map<String, Object?> tStr(String v) => {'k': 'string', 'v': v};
Map<String, Object?> tTemplate(String name, [String? def]) => {
      'k': 'template',
      'v': {'name': name, 'default': def},
    };

Map<String, Object?> tObj(Map<String, Map<String, Object?>> entries) => {
      'k': 'object',
      'v': [
        for (final entry in entries.entries) [entry.key, entry.value],
      ],
    };

Map<String, Object?> tArr(List<Map<String, Object?>> items) =>
    {'k': 'array', 'v': items};

// -- divergence switch -----------------------------------------------------

/// Empirical-loop switch. `false` while the executed baseline for each
/// candidate divergence is being observed; `true` once every divergence
/// block below carries an observed, not a predicted, baseline result.
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

// -- case builders ---------------------------------------------------------

CorpusCase _merge(
  String id,
  String description,
  List<String> classes, {
  required Map<String, Object?> base,
  required Map<String, Object?> update,
  required String prefer,
  Map<String, Object?>? divergence,
}) =>
    CorpusCase(
      id: id,
      description: description,
      classes: [...classes, 'merge', prefer],
      kind: 'merge',
      input: '',
      payload: {
        'area': prefer == 'base' ? 'merge_base' : 'merge_update',
        'prefer': prefer,
        'base': base,
        'update': update,
      },
      divergence: divergence,
    );

/// One input pair, run in both precedence modes.
List<CorpusCase> _pair(
  String id,
  String description,
  List<String> classes, {
  required Map<String, Object?> base,
  required Map<String, Object?> update,
}) =>
    [
      _merge('$id\_base', '$description (prefer: base)', classes,
          base: base, update: update, prefer: 'base'),
      _merge('$id\_update', '$description (prefer: update)', classes,
          base: base, update: update, prefer: 'update'),
    ];

CorpusCase _alias(
  String id,
  String description,
  List<String> classes, {
  required Map<String, Object?> base,
  required Map<String, Object?> update,
  required String prefer,
  Map<String, Object?>? corrected,
}) =>
    CorpusCase(
      id: id,
      description: description,
      classes: [...classes, 'immutability', prefer],
      kind: 'merge',
      input: '',
      payload: {
        'area': 'merge_immutability',
        'prefer': prefer,
        'base': base,
        'update': update,
      },
      divergence: corrected == null
          ? null
          : _corrected(
              id: 'MERGE-INPUT-ALIASING',
              report: 'A36',
              note: corrected['note']! as String,
              corrected: corrected['corrected']! as Map<String, Object?>,
            ),
    );

CorpusCase _revision(
  String id,
  String description,
  List<String> classes,
  String input,
  String op,
) =>
    CorpusCase(
      id: id,
      description: description,
      classes: [...classes, 'revision', op],
      kind: 'revision',
      input: input,
      payload: {'area': 'pipeline_revisions', 'query': {'op': op}},
    );

// -- merge input pairs ------------------------------------------------------

/// A nested object the base and update disagree about.
final Map<String, Object?> _nestedBase = tObj({
  'a': tObj({'x': tInt('1'), 'y': tInt('2')}),
});

final Map<String, Object?> _nestedUpdate = tObj({
  'a': tObj({'y': tInt('9'), 'z': tInt('3')}),
});

List<CorpusCase> _mergeCases() => [
      // -- scalars and the conflict rule ---------------------------
      ..._pair('merge_int', 'Two different integers conflict.', const ['scalar', 'int'],
          base: tInt('1'), update: tInt('2')),
      ..._pair('merge_equal_int', 'Equal integers are not a conflict.',
          const ['scalar', 'int', 'equal'], base: tInt('7'), update: tInt('7')),
      ..._pair('merge_string', 'Two different strings conflict.', const ['scalar', 'string'],
          base: tStr('a'), update: tStr('b')),
      ..._pair('merge_bool_vs_int', 'true and 1 are equal to Python ==.',
          const ['scalar', 'bool', 'equality'], base: tBool(true), update: tInt('1')),
      ..._pair('merge_int_vs_double', '1 and 1.0 are equal to Python ==.',
          const ['scalar', 'number', 'equality'], base: tInt('1'), update: tNum(1.0)),
      ..._pair(
          'merge_float_precision',
          'A fraction that is not equal to the base conflicts.',
          const ['scalar', 'number'],
          base: tInt('1'),
          update: tNum(1.5)),
      ..._pair('merge_null_vs_value', 'An explicit null conflicts with a value.',
          const ['scalar', 'null', 'six-states'], base: tNull(), update: tInt('1')),
      ..._pair('merge_value_vs_null', 'A value conflicts with an explicit null.',
          const ['scalar', 'null', 'six-states'], base: tInt('1'), update: tNull()),
      ..._pair('merge_both_null', 'Two nulls are equal, so neither wins visibly.',
          const ['scalar', 'null', 'equal'], base: tNull(), update: tNull()),
      ..._pair('merge_placeholder', 'A placeholder is one opaque value.',
          const ['scalar', 'placeholder'],
          base: tTemplate('PORT', '8080'), update: tInt('9090')),
      ..._pair('merge_placeholder_equal', 'Two identical placeholders are equal.',
          const ['scalar', 'placeholder', 'equal'],
          base: tTemplate('PORT', '8080'), update: tTemplate('PORT', '8080')),
      ..._pair(
          'merge_placeholder_variants',
          'A placeholder with and without a fallback are different values.',
          const ['scalar', 'placeholder'],
          base: tTemplate('PORT'),
          update: tTemplate('PORT', '8080'),
      ),

      // -- objects --------------------------------------------------------------
      ..._pair('merge_new_key', 'A key only the update has is added.', const ['object', 'add'],
          base: tObj({'a': tInt('1')}), update: tObj({'b': tInt('2')})),
      ..._pair('merge_kept_key', 'A key only the base has is kept.', const ['object', 'keep'],
          base: tObj({'a': tInt('1'), 'keep': tInt('2')}),
          update: tObj({'a': tInt('1'), 'add': tInt('3')})),
      ..._pair('merge_recursive', 'Two objects merge key by key, recursively.',
          const ['object', 'nested'], base: _nestedBase, update: _nestedUpdate),
      ..._pair('merge_deep', 'The recursion reaches any depth.', const ['object', 'nested'],
          base: tObj({'a': tObj({'b': tObj({'c': tInt('1'), 'd': tInt('2')})})}),
          update: tObj({'a': tObj({'b': tObj({'d': tInt('9'), 'e': tInt('3')})})})),
      ..._pair('merge_empty_update', 'An empty update keeps the base.',
          const ['object', 'empty'], base: tObj({'a': tInt('1')}), update: tObj({})),
      ..._pair('merge_empty_base', 'An empty base yields the update.', const ['object', 'empty'],
          base: tObj({}), update: tObj({'a': tInt('1')})),
      ..._pair('merge_both_empty', 'Two empty objects merge to an empty object.',
          const ['object', 'empty', 'equal'], base: tObj({}), update: tObj({})),
      ..._pair('merge_key_order', 'The base order is kept and new keys follow.',
          const ['object', 'order'],
          base: tObj({'z': tInt('1'), 'a': tInt('2')}), update: tObj({'m': tInt('3'), 'z': tInt('4')})),

      // -- type mismatches -------------------------------------------------------
      ..._pair('merge_object_vs_scalar', 'An object against a scalar is a conflict.',
          const ['type-mismatch'], base: tObj({'a': tInt('1')}), update: tInt('2')),
      ..._pair('merge_scalar_vs_object', 'A scalar against an object is a conflict.',
          const ['type-mismatch'], base: tInt('1'), update: tObj({'a': tInt('2')})),
      ..._pair('merge_object_vs_null', 'An object against null is a conflict.',
          const ['type-mismatch', 'null'], base: tObj({'a': tInt('1')}), update: tNull()),
      ..._pair('merge_array_vs_array', 'Arrays are never merged item by item.',
          const ['array'], base: tObj({'a': tArr([tInt('1'), tInt('2')])}),
          update: tObj({'a': tArr([tInt('3')])})),
      ..._pair('merge_equal_arrays', 'Two identical arrays are equal.',
          const ['array', 'equal'], base: tArr([tInt('1'), tStr('x')]),
          update: tArr([tInt('1'), tStr('x')])),
      ..._pair('merge_array_of_objects', 'An array of objects is one value.',
          const ['array', 'object'], base: tArr([tObj({'x': tInt('1')})]),
          update: tArr([tObj({'y': tInt('2')})])),
      ..._pair('merge_array_vs_scalar', 'An array against a scalar is a conflict.',
          const ['array', 'type-mismatch'], base: tArr([tInt('1')]), update: tInt('1')),
      ..._pair('merge_null_vs_array', 'A null against an array is a conflict.',
          const ['array', 'null', 'type-mismatch'], base: tNull(), update: tArr([tInt('1')])),

      // -- the aiui layering shape of amendment 7 -------------------------
      ..._pair(
          'merge_plugin_defaults',
          'A plugin default fills the gap; the user setting wins.',
          const ['object', 'layering'],
          base: tObj({'retry': tInt('5'), 'theme': tStr('dark')}),
          update: tObj({'retry': tInt('1'), 'language': tStr('en')}),
      ),
      ..._pair(
          'merge_nested_plugin_defaults',
          'A nested plugin branch merges without touching the user branch.',
          const ['object', 'layering', 'nested'],
          base: tObj({'ui': tObj({'theme': tStr('dark')})}),
          update: tObj({'ui': tObj({'theme': tStr('light'), 'density': tInt('2')})}),
      ),
    ];

// -- immutability probes ------------------------------------------------------

const String _aliasNote =
    'The baseline copies only what the update contributes, so a subtree the '
    'base alone provides stays the very same object inside the result. '
    'SPEC.md amendment 7 requires a merge that does not mutate its inputs, '
    'and an aliasing result mutates them indirectly: writing through the '
    'result writes through the base document that a caller is still '
    'reading. The corrected result is a fresh tree throughout.';

List<CorpusCase> _immutabilityCases() => [
      _alias('merge_alias_base_only', 'A base-only subtree in the result.',
          const ['alias'], base: tObj({'k': tObj({'deep': tInt('1')})}), update: tObj({}), prefer: 'base',
          corrected: {
            'note': _aliasNote,
            'corrected': {'inputsUnchanged': true, 'aliased': false, 'sharesBaseNodes': 0, 'sharesUpdateNodes': 0},
          }),
      _alias('merge_alias_base_only_update', 'A base-only subtree, prefer update.',
          const ['alias'], base: tObj({'k': tObj({'deep': tInt('1')})}), update: tObj({'j': tInt('2')}),
          prefer: 'update',
          corrected: {
            'note': _aliasNote,
            'corrected': {'inputsUnchanged': true, 'aliased': false, 'sharesBaseNodes': 0, 'sharesUpdateNodes': 0},
          }),
      _alias('merge_alias_base_conflict', 'A base value that wins a conflict.',
          const ['alias', 'conflict'], base: tObj({'k': tArr([tObj({'deep': tInt('1')})])}),
          update: tObj({'k': tArr([tObj({'deep': tInt('2')})])}), prefer: 'base'),
      _alias('merge_alias_update_new_key', 'An update-only subtree in the result.',
          const ['alias', 'new-key'], base: tObj({}), update: tObj({'k': tObj({'deep': tInt('1')})}),
          prefer: 'base'),
      _alias('merge_alias_update_wins', 'An update value that wins a conflict.',
          const ['alias', 'conflict'], base: tObj({'k': tInt('1')}),
          update: tObj({'k': tObj({'deep': tInt('1')})}), prefer: 'update'),
      _alias('merge_alias_recursive', 'A merged object keeps its untouched base child.',
          const ['alias', 'nested'], base: tObj({'a': tObj({'x': tInt('1')})}),
          update: tObj({'a': tObj({'y': tInt('2')})}), prefer: 'base'),
      _alias('merge_alias_scalars_only', 'A merge of scalars cannot alias.',
          const ['alias', 'scalar'], base: tInt('1'), update: tInt('2'), prefer: 'base'),
      _alias('merge_alias_shared_input', 'Equal objects in both inputs.',
          const ['alias', 'shared'], base: tObj({'k': tObj({'deep': tInt('1')})}),
          update: tObj({'k': tObj({'deep': tInt('1')})}), prefer: 'base'),
      const CorpusCase(
        id: 'merge_prefer_unknown',
        description: 'An unknown prefer name is refused with a stable code.',
        classes: ['rejection', 'prefer'],
        kind: 'merge',
        input: '',
        payload: {
          'area': 'merge_base',
          'prefer': 'sideways',
          // Tagged, like every other merge body: the base/update values
          // are irrelevant to this refusal (the baseline checks `prefer`
          // first) but the test decodes them, so they must be well-formed.
          // Inlined to stay const.
          'base': {'k': 'int', 'v': '1'},
          'update': {'k': 'int', 'v': '2'},
        },
        divergence: {
          'id': 'MERGE-PREFER-CODE',
          'report': 'A37',
          'note': 'The baseline raises a bare ValueError with no stable code for an '
              'unknown merge preference, while every other malformed argument in '
              'the same library is reported as BAD_REQUEST. The corrected '
              'answer is the stable code.',
          'corrected': {'ok': false, 'errorCode': 'BAD_REQUEST', 'baselineCrash': false},
        },
      ),
    ];

// -- revisions -----------------------------------------------------------------

const String _descriptorSample = '''
{ descriptor_version: "1.0", project: "rev", config_version: "2",
  root: { type: "object", children: { a: { type: "int", default: 1 } } } }
''';

List<CorpusCase> _revisionCases() => [
      _revision(
          'rev_source_simple', 'The source revision of a plain document.', const ['source'],
          '{\n  a: 1,\n}\n', 'source'),
      _revision('rev_source_empty_object', 'The revision of an empty object.', const ['source'], '{}',
          'source'),
      _revision('rev_source_no_trailing_newline', 'A missing final newline is part of the bytes.',
          const ['source', 'newline'], '{ a: 1 }', 'source'),
      _revision('rev_source_crlf', 'CRLF line endings change the revision.',
          const ['source', 'crlf'], '{\r\n  a: 1,\r\n}\r\n', 'source'),
      _revision('rev_source_bom', 'A byte order mark is part of the stored bytes.',
          const ['source', 'bom'], '\uFEFF{ a: 1 }\n', 'source'),
      _revision('rev_source_astral', 'An astral key is hashed as UTF-8 bytes.',
          const ['source', 'astral'], '{ "rocket \u{1F680}": 1 }\n', 'source'),
      _revision('rev_source_cyrillic', 'A non-ASCII value is hashed as UTF-8 bytes.',
          const ['source', 'unicode'], '{ a: "значение" }\n', 'source'),
      _revision('rev_source_comment_change', 'A comment change alone is a new revision.',
          const ['source', 'comments'], '{ a: 1 } // note\n', 'source'),
      _revision('rev_source_key_order', 'Key order changes the revision, not the meaning.',
          const ['source', 'order'], '{ b: 2, a: 1 }\n', 'source'),
      _revision('rev_source_whitespace_only', 'One space is a different document.',
          const ['source', 'whitespace'], '{  a: 1 }\n', 'source'),
      _revision('rev_descriptor_sample', 'The descriptor revision of the sample descriptor.',
          const ['descriptor'], _descriptorSample, 'descriptor'),
      _revision(
          'rev_descriptor_reordered_keys',
          'A descriptor with reordered properties is a new revision.',
          const ['descriptor', 'order'],
          '{ root: { type: "object", children: { a: { default: 1, type: "int" } } }, config_version: "2", project: "rev", descriptor_version: "1.0" }',
          'descriptor',
      ),
      _revision('rev_descriptor_comment',
          'A descriptor comment changes the revision.', const ['descriptor', 'comments'],
          '// style\n$_descriptorSample', 'descriptor'),
      _revision('rev_descriptor_whitespace',
          'A descriptor with different whitespace is a new revision.',
          const ['descriptor', 'whitespace'],
          '{descriptor_version:"1.0",project:"rev",config_version:"2",root:{type:"object",children:{a:{type:"int",default:1}}}}',
          'descriptor'),
    ];

/// The complete merge and revision catalog.
List<CorpusCase> mergeCases() => [
      ..._mergeCases(),
      ..._immutabilityCases(),
      ..._revisionCases(),
    ];
