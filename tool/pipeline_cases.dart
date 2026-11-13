/// Write-pipeline corpus cases for `tool/generate_corpus.dart` (slice 2D).
///
/// Every entry names a descriptor, one initial document and one staged batch
/// of operations, and is **executed against the Python baseline**
/// by `tool/python/corpus_driver.py`. The expectations are what the
/// baseline produced, never what prose says; a case becomes a registered
/// divergence only after the executed baseline is diffed against a
/// Dart replay of the same case.
///
/// Areas:
///
/// * `pipeline_operations`    — the batches that store: every operation kind,
///   sequential visibility inside one batch, create-then-fill, the reported
///   changed paths, the strictest `apply` policy.
/// * `pipeline_dry_run`       — a valid and an invalid dry run, each
///   pinning that the stored source and the service's own state text stay
///   byte-identical (`SPEC.md` amendment 3 write rule 7).
/// * `pipeline_rejections`    — each documented rejection reason with its
///   stable code (`SPEC.md` amendments 8 and 26).
/// * `pipeline_revision_pair` — the revision-pair CAS contract between two
///   independent writers over one document (`SPEC.md` amendment 8, REV-01).
/// * `pipeline_views`         — the stored, effective and active views of a
///   registered document, with provenance and the six leaf states.
///
/// The resolver layers of every case are passed explicitly, and mostly
/// empty: the baseline's own default for `environ` is the process
/// environment, so a corpus that relied on the default would depend on the
/// machine it ran on.
///
/// Arrays in these fixtures are single-line. The baseline's `_append_item`
/// splices `", {item}"` before the closing bracket while its own parser
/// rejects whitespace before a comma, so appending to an array whose last item
/// ends with whitespace emits source that no longer re-parses — the
/// already-filed A9/A32 shape. The pipeline cases use
/// the layout the baseline round-trips so that they pin the pipeline rather
/// than that splice defect.
library;

import 'corpus_cases.dart';

// -- divergence switch ---------------------------------------------------------

/// Empirical-loop switch. `false` while the executed baseline for each
/// candidate divergence is being observed; `true` once every divergence block
/// below carries an observed, not a predicted, baseline result.
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

// -- the shared document --------------------------------------------------------

/// The descriptor every pipeline case registers.
///
/// It declares one of each protection the amendment names (`required`, `const`,
/// `read_only`, `secret`, fixed children, dynamic children governed
/// by `key_enum` and `key_pattern`), all three `apply` policies plus a node
/// with none, an array, a union, and a placeholder-accepting string so
/// that "a placeholder is not replaced by a resolved secret on
/// save" is observable.
const String descriptorSource = '''
{ descriptor_version: "1.0", project: "pipeline", config_version: "1",
  root: {
    type: "object",
    children: {
      port:  { type: "int", minimum: 1, maximum: 65535, apply: "live" },
      host:  { type: "string", default: "localhost", apply: "reload" },
      label: { type: "string", env: { allowed: true }, apply: "restart" },
      heavy: { type: "string", apply: "restart" },
      plain: { type: "string" },
      ro:    { type: "string", read_only: true },
      fixed: { type: "string", const: "nope" },
      need:  { type: "int", required: true },
      secret_token: { type: "string", secret: true },
      zero:  { type: "int", default: 0 },
      flag:  { type: "bool", default: false },
      nothing: { type: "string", nullable: true },
      list:  { type: "array", children: { type: "int" } },
      obj:   { type: "object", additional_children: { type: "string" } },
      closed: { type: "object", children: { a: { type: "int" } } },
      boxed: { type: "object", children: {
                 inner_ro: { type: "string", read_only: true },
                 secret_inner: { type: "string", secret: true },
                 inner:  { type: "string" } } },
      keyed: { type: "object", key_enum: ["ok"],
               additional_children: { type: "int" } },
      masked: { type: "object", key_pattern: "^w",
                additional_children: { type: "int" } },
      uni:   { type: "union", children_options: [
                 { type: "object", children: { a: { type: "int" } } },
                 { type: "object", read_only: true, children: { b: { type: "int" } } } ] },
    },
  },
}
''';

/// The initial document every case starts from.
///
/// It is valid against [descriptorSource] as loaded, so the pipeline is
/// exercised on a healthy state and no case depends on an invalid-on-disk
/// recovery path. `list` and `obj` keep the layout the baseline's own
/// operations round-trip (see the library comment).
const String initialSource = '''
{
  // The service port the operator changed last week.
  port: 1,
  host: "localhost",
  label: \${LABEL},
  ro: "keep",
  fixed: "nope",
  need: 7,
  secret_token: "s3cr3t",
  zero: 3,
  flag: true,
  nothing: null,
  plain: "p",
  heavy: "h",
  list: [1, 2],
  obj: { a: "b", second: "c" },
  closed: { a: 1 },
  boxed: { inner_ro: "in", secret_inner: "shh", inner: "x" },
  keyed: { ok: 1 },
  masked: { w1: 2 },
  uni: { a: 1 },
}
''';

/// The resolver layers, always explicit.
const Map<String, Object?> emptyLayers = {
  'overrides': {},
  'environ': {},
  'dotenv': {},
};

const Map<String, Object?> labelLayer = {
  'overrides': {},
  'environ': {'LABEL': 'from-env'},
  'dotenv': {},
};

// -- case builders ---------------------------------------------------------------

CorpusCase _case(
  String id,
  String description,
  List<String> classes, {
  required String area,
  required List<Map<String, Object?>> operations,
  bool dryRun = false,
  String? expectedRevisions,
  String principal = 'demo',
  String config = initialSource,
  String descriptor = descriptorSource,
  Map<String, Object?> layers = emptyLayers,
  Map<String, Object?>? limits,
  Map<String, Object?>? divergence,
}) =>
    CorpusCase(
      id: id,
      description: description,
      classes: [...classes, 'pipeline'],
      kind: 'pipeline_case',
      input: config,
      payload: {
        'area': area,
        'descriptor': descriptor,
        'config': config,
        'operations': operations,
        'layers': layers,
        'principal': principal,
        if (dryRun) 'dryRun': true,
        if (expectedRevisions != null) 'expectedRevisions': expectedRevisions,
        if (limits != null) 'limits': limits,
      },
      divergence: divergence,
    );

Map<String, Object?> _op(String kind,
        {String path = '', String? valueText, String? from, String? to}) =>
    {
      'op': kind,
      'path': path,
      if (valueText != null) 'value_text': valueText,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    };

/// An append to the shared `list`.
Map<String, Object?> _append(String valueText) =>
    _op('add', path: '/list/-', valueText: valueText);

CorpusCase _view(
  String id,
  String description,
  List<String> classes,
  Map<String, Object?> query, {
  String principal = 'demo',
  Map<String, Object?> layers = emptyLayers,
  String config = initialSource,
  String? secretMarker,
  Map<String, Object?>? divergence,
}) =>
    CorpusCase(
      id: id,
      description: description,
      classes: [...classes, 'view'],
      kind: 'pipeline_view',
      input: config,
      payload: {
        'area': 'pipeline_views',
        'descriptor': descriptorSource,
        'config': config,
        'query': query,
        'layers': layers,
        'principal': principal,
        if (secretMarker != null) 'secretMarker': secretMarker,
      },
      divergence: divergence,
    );

// -- 1. the batches that store ----------------------------------------------------

List<CorpusCase> _storedCases() => [
      // -- set ----------------------------------------------------------------
      _case('op_set_int', 'A set of an int stores the new text.',
          const ['set', 'scalar', 'live'],
          area: 'pipeline_operations',
          operations: [_op('set', path: '/port', valueText: '8080')]),
      _case('op_set_string', 'A set of a quoted string keeps the quotes.',
          const ['set', 'scalar', 'reload'],
          area: 'pipeline_operations',
          operations: [_op('set', path: '/host', valueText: '"other"')]),
      _case('op_set_creates_dynamic_key', 'A set can create a governed dynamic key.',
          const ['set', 'create', 'dynamic-key'],
          area: 'pipeline_operations',
          operations: [_op('set', path: '/obj/new', valueText: '"v"')]),
      _case('op_set_preserves_placeholder',
          'A set of a neighbour leaves the placeholder text intact.',
          const ['set', 'placeholder', 'preserve'],
          area: 'pipeline_operations',
          operations: [_op('set', path: '/port', valueText: '15')],
          layers: labelLayer),
      _case('op_set_placeholder_node_itself',
          'Replacing the placeholder value itself stores the submitted text.',
          const ['set', 'placeholder'],
          area: 'pipeline_operations',
          operations: [_op('set', path: '/label', valueText: '"plain"')]),
      _case('op_set_container_untouched_readonly_child',
          'Replacing a whole object may leave its read-only child intact.',
          const ['set', 'read-only', 'container', 'preserve'],
          area: 'pipeline_operations',
          operations: [
            _op('set', path: '/boxed',
                valueText: '{ inner_ro: "in", secret_inner: "shh", inner: "new" }'),
          ]),
      _case('rej_readonly_descendant_write',
          'A container write that changes a read-only descendant is refused.',
          const ['read-only', 'container', 'rejection'],
          area: 'pipeline_rejections',
          operations: [
            _op('set', path: '/boxed',
                valueText: '{ inner_ro: "changed", secret_inner: "shh", inner: "x" }'),
          ],
          divergence: _corrected(
            id: 'PIPE-PROTECTION-BYPASS',
            report: 'A38',
            note: 'A staged batch changes a read-only descendant: the baseline '
                'checks descendant protections (`_check_editable`) only on its '
                'single-pointer write path, so replacing the whole object '
                'that contains a read-only field rewrites that field, while the '
                'same write through the direct path is refused FORBIDDEN. '
                'SPEC.md amendment 8 requires the read_only restriction to carry '
                'over to operations and to the whole affected subtree; the '
                'corrected answer is the same FORBIDDEN the direct path gives.',
            corrected: {
              'result': 'rejected',
              'errorCode': 'FORBIDDEN',
              'stored': false,
              'fileUnchanged': true,
              'stateTextUnchanged': true,
            },
          )),
      _case('rej_const_descendant_write',
          'A container write that changes a const descendant is refused.',
          const ['const', 'container', 'rejection'],
          area: 'pipeline_rejections',
          descriptor: _constBoxDescriptor,
          config: '{ port: 1, box: { fixed: "F", keep: "k" } }\n',
          // Executed baseline (d4adb45): the batch is refused
          // with VALIDATION_ERROR and the `const` issue at
          // /box/fixed, the file unchanged. That is the
          // amendment-8 answer the requirements want too, so the
          // case is ordinary; the earlier A38 note claimed the
          // baseline *stores* this write, which re-execution disproved.
          operations: [
            _op('set', path: '/box', valueText: '{ fixed: "G", keep: "k" }'),
          ]),
      _case('op_set_null_and_absent_states',
          'A nullable value accepts an explicit null.',
          const ['set', 'null', 'six-states'],
          area: 'pipeline_operations',
          operations: [_op('set', path: '/nothing', valueText: 'null')]),

      // -- add ----------------------------------------------------------------
      _case('op_append_int', 'An append adds one array item.',
          const ['add', 'append', 'array'],
          area: 'pipeline_operations', operations: [_append('3')]),
      _case('op_append_twice', 'Two appends in one batch add two items.',
          const ['add', 'append', 'sequential'],
          area: 'pipeline_operations', operations: [_append('3'), _append('4')]),
      _case('op_add_new_key', 'An add creates one governed object key.',
          const ['add', 'create', 'dynamic-key'],
          area: 'pipeline_operations',
          operations: [_op('add', path: '/obj/created', valueText: '"v"')]),
      _case('op_add_key_enum', 'An add outside key_enum is refused.',
          const ['add', 'key-enum', 'rejection'],
          area: 'pipeline_rejections',
          operations: [_op('add', path: '/keyed/bad', valueText: '1')]),
      _case('op_add_key_pattern', 'An add outside key_pattern is refused.',
          const ['add', 'key-pattern', 'rejection'],
          area: 'pipeline_rejections',
          operations: [_op('add', path: '/masked/zz', valueText: '1')]),
      _case('op_add_not_permitted', 'An add to a closed object is refused.',
          const ['add', 'closed', 'rejection'],
          area: 'pipeline_rejections',
          operations: [_op('add', path: '/boxed/extra', valueText: '"v"')]),

      // -- remove --------------------------------------------------------------
      _case('op_remove_item', 'A remove takes one array item out.',
          const ['remove', 'array'],
          area: 'pipeline_operations', operations: [_op('remove', path: '/list/0')]),
      _case('op_remove_optional_dynamic_key',
          'A remove of an optional dynamic key works.', const ['remove', 'dynamic-key'],
          area: 'pipeline_operations', operations: [_op('remove', path: '/obj/a')]),
      _case('op_remove_required', 'A required value cannot be removed.',
          const ['remove', 'required', 'rejection'],
          area: 'pipeline_rejections', operations: [_op('remove', path: '/need')]),
      _case('op_remove_readonly', 'A read-only value cannot be removed.',
          const ['remove', 'read-only', 'rejection'],
          area: 'pipeline_rejections', operations: [_op('remove', path: '/ro')]),
      _case('op_remove_const', 'A const value cannot be removed.',
          const ['remove', 'const', 'rejection'],
          area: 'pipeline_rejections', operations: [_op('remove', path: '/fixed')]),

      // -- rename ---------------------------------------------------------------
      _case('op_rename_dynamic_key', 'A rename changes the key in place.',
          const ['rename', 'dynamic-key'],
          area: 'pipeline_operations',
          operations: [_op('rename', path: '/obj/a', to: 'renamed')]),
      _case('op_rename_onto_existing', 'A rename that would collide is refused.',
          const ['rename', 'duplicate-key', 'rejection'],
          area: 'pipeline_rejections',
          operations: [_op('rename', path: '/obj/a', to: 'second')]),
      _case('op_rename_required', 'A required value cannot be renamed.',
          const ['rename', 'required', 'rejection'],
          area: 'pipeline_rejections', operations: [_op('rename', path: '/need', to: 'n2')]),
      _case('op_rename_readonly', 'A read-only value cannot be renamed.',
          const ['rename', 'read-only', 'rejection'],
          area: 'pipeline_rejections', operations: [_op('rename', path: '/ro', to: 'ro2')]),
      _case('op_rename_const', 'A const value cannot be renamed.',
          const ['rename', 'const', 'rejection'],
          area: 'pipeline_rejections', operations: [_op('rename', path: '/fixed', to: 'f2')]),
      _case('op_rename_empty_key', 'A rename needs a non-empty key.',
          const ['rename', 'rejection'],
          area: 'pipeline_rejections', operations: [_op('rename', path: '/port', to: '')]),
      _case('op_rename_fixed_declared_child',
          'A declared child of a closed object is fixed.',
          const ['rename', 'closed', 'rejection'],
          area: 'pipeline_rejections',
          operations: [_op('rename', path: '/closed/a', to: 'b')]),

      // -- move -------------------------------------------------------------------
      _case('op_move_item', 'A move reorders one array item.',
          const ['move', 'array'],
          area: 'pipeline_operations',
          operations: [_op('move', from: '/list/0', path: '/list/1')]),
      _case('op_move_non_array', 'A move of a non-array item is refused.',
          const ['move', 'scalar', 'rejection'],
          area: 'pipeline_rejections',
          // Executed baseline (d4adb45): the source check
          // refuses with `BadRequest`, which the batch reports as
          // one `operation` issue, so the whole call is
          // VALIDATION_ERROR and nothing is stored. This
          // matches the amendment-8 rule ("only array items
          // move"), so it is an ordinary case, not a divergence: the
          // previously registered A37 note claimed the
          // baseline *stores* such a move, which re-execution disproved.
          operations: [_op('move', from: '/port', path: '/port')]),
      _case('op_move_missing_source', 'A move of an absent item is refused.',
          const ['move', 'rejection'],
          area: 'pipeline_rejections',
          operations: [_op('move', from: '/list/9', path: '/list/0')]),

      // -- drop ---------------------------------------------------------------------
      _case('op_drop_declared', 'drop never replaces remove.',
          const ['drop', 'rejection'],
          area: 'pipeline_rejections', operations: [_op('drop', path: '/port')]),
      _case('op_drop_absent', 'Dropping a key that is not there is refused.',
          const ['drop', 'rejection'],
          area: 'pipeline_rejections', operations: [_op('drop', path: '/junk')]),
      _case('op_drop_under_closed_object',
          'A drifted key inside a closed object is what drop removes.',
          const ['drop', 'accept'],
          area: 'pipeline_operations',
          descriptor: _closedDescriptor,
          config: '{ closed: { a: 1, junk: 2 } }\n',
          operations: [_op('drop', path: '/closed/junk')],
          divergence: _corrected(
            id: 'PIPE-UNDECLARED-PATH-APPLIED',
            report: 'A39',
            note: 'A batch whose changed paths are all undeclared reports '
                '`applied` and advances the active revision: '
                'the baseline reduces the strictest apply policy over the '
                'changed paths starting from `live`, and a path with no '
                'governing node contributes nothing, so a repair that only '
                'removes a drifted key pretends to be live. Its own docstring '
                'states that `live` is the policy a node without an explicit '
                'apply must not get. SPEC.md amendment 8 fixes undeclared as '
                '`restart`; the corrected answer is `restart_required` with the '
                'active revision left where the application actually is.',
            corrected: {
              'result': 'stored',
              'application': 'restart_required',
              'activeMatchesRevision': false,
            },
          )),
      _case('op_drop_governed_dynamic_key',
          'A key the descriptor governs is removed with remove, not drop.',
          const ['drop', 'rejection'],
          area: 'pipeline_rejections', operations: [_op('drop', path: '/obj/a')]),
      _case('op_drop_union_drifted_key',
          'A drifted key whose parent is a union with a read-only shape is denied.',
          const ['drop', 'union', 'rejection'],
          area: 'pipeline_rejections',
          operations: [_op('drop', path: '/uni/junk')],
          config: _replaceIn(initialSource, 'uni: { a: 1 }', 'uni: { a: 1, junk: 2 }')),

      // -- sequential visibility and atomicity ---------------------------------------------
      _case(
          'op_batch_create_then_fill',
          'A later operation sees the key an earlier one created.',
          const ['batch', 'create-then-fill', 'sequential'],
          area: 'pipeline_operations',
          operations: [
            _op('add', path: '/obj/deep', valueText: '"first"'),
            _op('set', path: '/obj/deep', valueText: '"second"'),
          ],
      ),
      _case(
          'op_batch_create_object_then_fill',
          'A container created by operation one is filled by operation two.',
          const ['batch', 'create-then-fill', 'sequential'],
          area: 'pipeline_operations',
          descriptor: _fillDescriptor,
          config: '{ port: 1 }\n',
          operations: [
            _op('set', path: '/fresh', valueText: '{}'),
            _op('set', path: '/fresh/x', valueText: '"v"'),
          ],
      ),
      _case(
          'op_batch_append_then_set',
          'An item appended by operation one is addressable by operation two.',
          const ['batch', 'append', 'sequential'],
          area: 'pipeline_operations',
          operations: [_append('9'), _op('set', path: '/list/2', valueText: '10')],
      ),
      _case(
          'op_batch_remove_then_add_then_rename',
          'Three operations compose into one stored document.',
          const ['batch', 'sequential', 'rename'],
          area: 'pipeline_operations',
          operations: [
            _op('remove', path: '/obj/a'),
            _op('add', path: '/obj/keep', valueText: '"v"'),
            _op('rename', path: '/obj/keep', to: 'kept'),
          ],
      ),
      _case('op_batch_second_fails_stores_nothing',
          'A refused operation aborts the batch and stores nothing.',
          const ['batch', 'atomic', 'rejection'],
          area: 'pipeline_rejections',
          operations: [_append('7'), _op('set', path: '/nothere/deep', valueText: '1')]),
      _case('op_batch_third_fails_stores_nothing',
          'The first two operations of an aborted batch are not stored either.',
          const ['batch', 'atomic', 'rejection'],
          area: 'pipeline_rejections',
          operations: [
            _op('set', path: '/port', valueText: '8080'),
            _append('3'),
            _op('set', path: '/nope', valueText: '1'),
          ]),
      _case('op_batch_empty', 'An empty batch is a request error.',
          const ['batch', 'rejection'], area: 'pipeline_rejections', operations: const []),
      _case('op_batch_unknown_kind', 'An unknown operation kind is refused.',
          const ['batch', 'rejection'],
          area: 'pipeline_rejections', operations: [_op('frobnicate', path: '/port')]),
      _case('op_append_token_on_set', 'The append marker is only valid for add.',
          const ['rejection', 'append'],
          area: 'pipeline_rejections', operations: [_op('set', path: '/list/-', valueText: '3')]),

      // -- application state and the reported paths -------------------------------------------
      _case('op_live_change', 'A change under a live node reports applied.',
          const ['apply', 'live'],
          area: 'pipeline_operations', operations: [_op('set', path: '/port', valueText: '80')]),
      _case('op_reload_change', 'A change under a reload node reports reload_required.',
          const ['apply', 'reload'],
          area: 'pipeline_operations',
          operations: [_op('set', path: '/host', valueText: '"h2"')]),
      _case('op_restart_change', 'A change under a restart node reports restart_required.',
          const ['apply', 'restart'],
          area: 'pipeline_operations',
          operations: [_op('set', path: '/heavy', valueText: '"v"')]),
      _case('op_undeclared_apply_policy_is_restart',
          'A node with no declared apply policy asks for a restart, never claims live.',
          const ['apply', 'default', 'restart'],
          area: 'pipeline_operations',
          operations: [_op('set', path: '/plain', valueText: '"p"')]),
      _case('op_batch_strictest_policy_wins',
          'A batch mixing live and restart reports the strictest policy.',
          const ['apply', 'batch', 'strictest'],
          area: 'pipeline_operations',
          operations: [
            _op('set', path: '/port', valueText: '81'),
            _op('set', path: '/heavy', valueText: '"y"'),
          ],
      ),
      _case('op_changed_paths_include_subtree',
          'A replace reports the addressed node and every descendant.',
          const ['changed-paths', 'container'],
          area: 'pipeline_operations',
          operations: [
            _op('set', path: '/boxed',
                valueText: '{ inner_ro: "in", secret_inner: "shh", inner: "n2" }'),
          ]),
      _case('op_changed_paths_append_includes_container',
          'An append reports the container and the new item.',
          const ['changed-paths', 'append'],
          area: 'pipeline_operations', operations: [_append('5')]),
      _case('op_changed_paths_rename_includes_new_key',
          'A rename reports the old and the new pointer.',
          const ['changed-paths', 'rename'],
          area: 'pipeline_operations',
          operations: [_op('rename', path: '/obj/a', to: 'renamed')]),
      _case('op_changed_paths_sorted', 'The changed paths of a batch are reported sorted.',
          const ['changed-paths', 'batch'],
          area: 'pipeline_operations',
          operations: [
            _op('set', path: '/port', valueText: '70'),
            _op('set', path: '/heavy', valueText: '"z"'),
          ],
      ),
    ];

/// A document with the defaulted and optional nodes absent, so that
/// `default_applied` and the `MISSING` leaf state are observable.
const String _sparseConfig = '''
{
  port: 1,
  host: "localhost",
  ro: "keep",
  fixed: "nope",
  need: 7,
  secret_token: "s3cr3t",
  list: [1, 2],
  obj: { a: "b", second: "c" },
  closed: { a: 1 },
  boxed: { inner_ro: "in", secret_inner: "shh", inner: "x" },
  keyed: { ok: 1 },
  masked: { w1: 2 },
  uni: { a: 1 },
}
''';

/// The same document with a stored `false`.
const String _falseConfig = '''
{
  port: 1,
  host: "localhost",
  flag: false,
  ro: "keep",
  fixed: "nope",
  need: 7,
  secret_token: "s3cr3t",
  list: [1, 2],
  obj: { a: "b", second: "c" },
  closed: { a: 1 },
  boxed: { inner_ro: "in", secret_inner: "shh", inner: "x" },
  keyed: { ok: 1 },
  masked: { w1: 2 },
  uni: { a: 1 },
}
''';

/// The same document with a stored empty string.
const String _emptyConfig = '''
{
  port: 1,
  host: "localhost",
  heavy: "",
  ro: "keep",
  fixed: "nope",
  need: 7,
  secret_token: "s3cr3t",
  list: [1, 2],
  obj: { a: "b", second: "c" },
  closed: { a: 1 },
  boxed: { inner_ro: "in", secret_inner: "shh", inner: "x" },
  keyed: { ok: 1 },
  masked: { w1: 2 },
  uni: { a: 1 },
}
''';

/// A box with one const and one ordinary child.
const String _constBoxDescriptor = '''
{ descriptor_version: "1.0", root: { type: "object", children: {
    port: { type: "int" },
    box: { type: "object", children: {
             fixed: { type: "string", const: "F" },
             keep: { type: "string" } } },
  } } }
''';

/// A closed object plus the drifted key the `drop` rule addresses.
const String _closedDescriptor = '''
{ descriptor_version: "1.0", root: { type: "object", children: {
    closed: { type: "object", children: { a: { type: "int" } } },
  } } }
''';

/// A descriptor with one dynamic-key object, for the
/// create-the-container-then-fill-it batch.
const String _fillDescriptor = '''
{ descriptor_version: "1.0", root: { type: "object", children: {
    port: { type: "int" },
    fresh: { type: "object", additional_children: { type: "string" } },
  } } }
''';

/// [source] with the first occurrence of [from] replaced by [to].
String _replaceIn(String source, String from, String to) {
  final index = source.indexOf(from);
  if (index < 0) throw StateError('fixture text not found: $from');
  return source.substring(0, index) + to + source.substring(index + from.length);
}

// -- 2. dry runs ---------------------------------------------------------------------

List<CorpusCase> _dryRunCases() => [
      _case('dry_run_valid_batch', 'A valid dry run stores nothing and reports no issue.',
          const ['dry-run', 'accept'], dryRun: true,
          area: 'pipeline_dry_run',
          operations: [_op('set', path: '/port', valueText: '80')]),
      _case('dry_run_invalid_value', 'A dry run reports the validation issue without writing.',
          const ['dry-run', 'rejection'], dryRun: true,
          area: 'pipeline_dry_run',
          operations: [_op('set', path: '/port', valueText: '999999')]),
      _case('dry_run_refused_operation', 'A dry run reports a refused operation without writing.',
          const ['dry-run', 'rejection', 'operation'], dryRun: true,
          area: 'pipeline_dry_run',
          operations: [_op('set', path: '/nope', valueText: '1')]),
      _case('dry_run_partial_batch', 'A dry run of a batch whose second operation fails.',
          const ['dry-run', 'atomic'], dryRun: true,
          area: 'pipeline_dry_run',
          operations: [_append('3'), _op('set', path: '/nope', valueText: '1')]),
      _case('dry_run_permission_denial_propagates',
          'A dry run reports a permission denial as the call itself refuses.',
          const ['dry-run', 'rejection', 'read-only'], dryRun: true,
          area: 'pipeline_dry_run',
          operations: [_op('set', path: '/ro', valueText: '"x"')]),
      _case('dry_run_create_then_fill', 'A dry run resolves the whole batch.',
          const ['dry-run', 'create-then-fill'], dryRun: true,
          area: 'pipeline_dry_run',
          operations: [
            _op('add', path: '/obj/x', valueText: '"1"'),
            _op('set', path: '/obj/x', valueText: '"2"'),
          ]),
      _case('dry_run_needs_only_validate_permission',
          'A dry run is allowed for a principal with no write permission.',
          const ['dry-run', 'permission'], dryRun: true, principal: 'no_write',
          area: 'pipeline_dry_run',
          operations: [_op('set', path: '/port', valueText: '80')]),
      _case('dry_run_stale_revision_still_refused',
          'A dry run still requires a live revision pair.', const ['dry-run', 'revision'],
          dryRun: true, expectedRevisions: 'stale_source',
          area: 'pipeline_dry_run',
          operations: [_op('set', path: '/port', valueText: '80')]),
    ];

// -- 3. rejections and stable codes -------------------------------------------------------

List<CorpusCase> _rejectionCases() => [
      _case('rej_missing_revision_pair', 'An absent revision pair is REVISION_REQUIRED.',
          const ['revision', 'rejection'], expectedRevisions: 'absent',
          area: 'pipeline_rejections', operations: [_op('set', path: '/port', valueText: '80')]),
      _case('rej_stale_source_revision', 'A stale source revision is REVISION_CONFLICT.',
          const ['revision', 'rejection'], expectedRevisions: 'stale_source',
          area: 'pipeline_rejections', operations: [_op('set', path: '/port', valueText: '80')]),
      _case('rej_stale_descriptor_revision', 'A stale descriptor revision is REVISION_CONFLICT.',
          const ['revision', 'rejection'], expectedRevisions: 'stale_descriptor',
          area: 'pipeline_rejections', operations: [_op('set', path: '/port', valueText: '80')]),
      _case('rej_no_write_permission', 'A principal without the write permission is FORBIDDEN.',
          const ['permission', 'rejection'], principal: 'no_write',
          area: 'pipeline_rejections', operations: [_op('set', path: '/port', valueText: '80')]),
      _case('rej_secret_write_without_permission',
          'A write to a secret subtree is denied without the edit permission.',
          const ['secret', 'rejection'], principal: 'no_secret_edit',
          area: 'pipeline_rejections',
          // Executed baseline (d4adb45): SECRET_ACCESS_DENIED, nothing
          // stored. That is the correct SEC-01 answer, so the
          // case is ordinary. The earlier A38 note claimed the
          // baseline stores a write to a position
          // inside the secret subtree, which re-execution
          // disproved (see the `secret` cases for what the batch path
          // really bypasses: a secret *descendant*).
          operations: [_op('set', path: '/secret_token', valueText: '"stolen"')]),
      _case('rej_root_pointer', 'The root pointer is refused.',
          const ['rejection', 'root'], area: 'pipeline_rejections',
          operations: [_op('set', path: '', valueText: '1')]),
      _case('rej_undeclared_path', 'A path the descriptor does not declare is refused.',
          const ['rejection', 'undeclared'], area: 'pipeline_rejections',
          operations: [_op('set', path: '/nope', valueText: '1')]),
      _case('rej_undeclared_nested_path',
          'A position under an undeclared key has no governing node.',
          const ['rejection', 'undeclared'], area: 'pipeline_rejections',
          operations: [_op('set', path: '/nope/deep', valueText: '1')]),
      _case('rej_constraint_violation', 'A bound violation is VALIDATION_ERROR with the rule.',
          const ['rejection', 'constraint'], area: 'pipeline_rejections',
          operations: [_op('set', path: '/port', valueText: '999999')]),
      _case('rej_const_violation', 'A const violation is reported by the const rule.',
          const ['rejection', 'const'], area: 'pipeline_rejections',
          operations: [_op('set', path: '/fixed', valueText: '"other"')]),
      _case('rej_type_violation', 'A wrong type is reported by the type rule.',
          const ['rejection', 'type'], area: 'pipeline_rejections',
          operations: [_op('set', path: '/port', valueText: '"text"')]),
      _case('rej_nullable_violation', 'A non-nullable value rejects an explicit null.',
          const ['rejection', 'null'], area: 'pipeline_rejections',
          operations: [_op('set', path: '/heavy', valueText: 'null')]),
      _case('rej_empty_value_text', 'A blank value_text is refused.',
          const ['rejection', 'value-text'], area: 'pipeline_rejections',
          operations: [_op('set', path: '/port', valueText: '')]),
      _case('rej_blank_value_text', 'A whitespace-only value_text is refused.',
          const ['rejection', 'value-text'], area: 'pipeline_rejections',
          operations: [_op('set', path: '/port', valueText: '   ')]),
      _case('rej_unparseable_value_text', 'An invalid value_text is a parse error.',
          const ['rejection', 'value-text'], area: 'pipeline_rejections',
          operations: [_op('set', path: '/port', valueText: 'oops(')]),
      _case('rej_missing_array_index', 'A set of an absent array index is refused.',
          const ['rejection', 'array'], area: 'pipeline_rejections',
          operations: [_op('set', path: '/list/9', valueText: '1')]),
      _case('rej_required_removed_by_batch',
          'A batch may not remove a value the descriptor requires.',
          const ['rejection', 'required'], area: 'pipeline_rejections',
          operations: [
            _op('set', path: '/port', valueText: '80'),
            _op('remove', path: '/need'),
          ]),
      _case('rej_limit_depth', 'A candidate past the depth limit is refused.',
          const ['rejection', 'limits', 'depth'],
          area: 'pipeline_rejections', limits: const {'max_depth': 3},
          operations: [_op('set', path: '/obj', valueText: '{ a: { b: { c: "1" } } }')]),
      _case('rej_limit_collection', 'A candidate past the collection limit is refused.',
          const ['rejection', 'limits', 'collection'],
          area: 'pipeline_rejections', limits: const {'max_collection_size': 2},
          operations: [_op('set', path: '/list', valueText: '[1, 2, 3]')]),
      _case('rej_limit_string', 'A candidate past the string limit is refused.',
          const ['rejection', 'limits', 'string'],
          area: 'pipeline_rejections', limits: const {'max_string_length': 3},
          operations: [_op('set', path: '/heavy', valueText: '"abcdef"')]),
      _case('rej_placeholder_without_env_permission',
          'A bare placeholder under a node that forbids env is an issue.',
          const ['rejection', 'placeholder'], area: 'pipeline_rejections',
          operations: [_op('set', path: '/heavy', valueText: r'${OTHER}')]),

      // -- the read-only and secret bypasses of the batch path -----------------
      _case('rej_readonly_identical_rewrite',
          'Re-submitting a read-only value verbatim is refused as a write to it.',
          const ['read-only', 'rejection'],
          area: 'pipeline_rejections',
          operations: [_op('set', path: '/ro', valueText: '"keep"')],
          divergence: _corrected(
            id: 'PIPE-PROTECTION-BYPASS',
            report: 'A38',
            note: 'The staged-operations path does not run the '
                'descendant-protection check its single-pointer write path does, so '
                'a staged batch rewrites a read-only or secret node that '
                'the same value written through the direct path refuses '
                '(FORBIDDEN, or SECRET_ACCESS_DENIED without the secret edit '
                'permission). Executed baseline (d4adb45): '
                'the identical re-submission of the read-only value '
                'STORES (a no-diff commit that still advances the '
                'revision and emits an event) while the direct write of the '
                'same value raises Forbidden. SPEC.md amendment 8 requires the '
                'required/const/read_only/secret restrictions to '
                'carry over to operations, and amendment 9 with SEC-01 requires '
                'the secret rule to hold for every surface. The corrected answer '
                'is the same refusal the direct path gives, and a changed '
                'read-only/secret descendant gets it too.',
            corrected: {
              'result': 'rejected',
              'errorCode': 'FORBIDDEN',
              'stored': false,
              'fileUnchanged': true,
              'stateTextUnchanged': true,
            },
          )),
      _case('rej_readonly_changed_rewrite',
          'A changed write to a read-only node is refused.',
          const ['read-only', 'rejection'],
          area: 'pipeline_rejections',
          operations: [_op('set', path: '/ro', valueText: '"changed"')]),
      _case('rej_secret_descendant_write_without_permission',
          'A container write that changes a secret descendant is denied.',
          const ['secret', 'rejection', 'container'], principal: 'no_secret_edit',
          area: 'pipeline_rejections',
          operations: [
            _op('set', path: '/boxed',
                valueText: '{ inner_ro: "in", secret_inner: "taken", inner: "x" }'),
          ],
          divergence: _corrected(
            id: 'PIPE-PROTECTION-BYPASS',
            report: 'A38',
            note: 'A staged batch overwrites a secret descendant without the '
                'secret edit permission: the baseline checks `secret` only on '
                'the addressed node of an operation, so replacing the whole '
                'object that contains the secret bypasses it. SPEC.md amendments 8 '
                'and 26 (SEC-01) require the permission to hold for every '
                'affected descendant; the corrected answer is '
                'SECRET_ACCESS_DENIED.',
            corrected: {
              'result': 'rejected',
              'errorCode': 'SECRET_ACCESS_DENIED',
              'stored': false,
              'fileUnchanged': true,
              'stateTextUnchanged': true,
            },
          )),
    ];

// -- 3b. the batch path that must NOT refuse ---------------------
//
// This case lives in `pipeline_operations` because
// the executed baseline stores it: a staged batch that leaves a
// secret descendant byte-identical is not a write to that
// secret, so it does not require the secret edit
// permission. The `preserve` class makes that rule explicit, and it
// is the counterpart to `rej_secret_descendant_write_
// without_permission`, where the value does change.
List<CorpusCase> _secretPathCases() => [
      _case('rej_secret_descendant_unchanged_write_without_permission',
          'A container write that leaves the secret descendant intact is allowed.',
          const ['secret', 'container', 'preserve'], principal: 'no_secret_edit',
          area: 'pipeline_operations',
          operations: [
            _op('set', path: '/boxed',
                valueText: '{ inner_ro: "in", secret_inner: "shh", inner: "new" }'),
          ]),
    ];

// -- 4. the revision-pair CAS contract ---------------------------------------------------

const String _pairDescriptor = '''
{ descriptor_version: "1.0", root: { type: "object", children: {
    port: { type: "int", minimum: 1, maximum: 65535 },
    host: { type: "string" },
  } } }
''';

const String _pairConfig = '{ port: 1, host: "localhost" }\n';

CorpusCase _pair(
  String id,
  String description,
  List<String> classes,
  String scenario, {
  Map<String, Object?>? divergence,
}) =>
    CorpusCase(
      id: id,
      description: description,
      classes: [...classes, 'cas'],
      kind: 'pipeline_revision_pair',
      input: _pairConfig,
      payload: {
        'area': 'pipeline_revision_pair',
        'scenario': scenario,
        'descriptor': _pairDescriptor,
        'config': _pairConfig,
      },
      divergence: divergence,
    );

List<CorpusCase> _casCases() => [
      _pair('cas_fresh_pair_two_writers',
          'Two writers that each present the current pair store in turn.',
          const ['cas', 'accept'], 'fresh_pair'),
      _pair('cas_stale_pair_refused',
          'The writer whose pair went stale is refused and the winner keeps the bytes.',
          const ['cas', 'rejection'], 'stale_pair'),
      _pair('cas_absent_pair_refused', 'A write with no revision pair at all is refused.',
          const ['cas', 'rejection'], 'absent'),
      _pair('cas_wrong_descriptor_half_refused',
          'A write presenting the wrong descriptor revision is refused.',
          const ['cas', 'rejection'], 'wrong_descriptor'),
      _pair('cas_external_writer_wins',
          'A document replaced outside the service refuses the next stale commit.',
          const ['cas', 'rejection', 'external'], 'external_writer'),
    ];

// -- 5. the four views ------------------------------------------------------------

List<CorpusCase> _viewCases() => [
      _view('view_effective_snapshot',
          'The effective view of a registered document, with defaults.',
          const ['effective', 'default'], {'op': 'effective'}, layers: labelLayer),
      _view('view_effective_provenance',
          'Provenance names the file, the variable and the default separately.',
          const ['provenance'], {'op': 'effective'}),
      _view('view_get_default_applied',
          'An absent value with a declared default reports default_applied.',
          const ['six-states', 'default'], {'op': 'get', 'pointer': '/zero'},
          config: _sparseConfig),
      _view('view_get_explicit_null', 'An explicit null is not absence.',
          const ['six-states', 'null'], {'op': 'get', 'pointer': '/nothing'}),
      _view('view_get_zero_value', 'A stored zero is a value of its own.',
          const ['six-states', 'zero'], {'op': 'get', 'pointer': '/zero'}),
      _view('view_get_false_value', 'A stored false is a value of its own.',
          const ['six-states', 'false'], {'op': 'get', 'pointer': '/flag'},
          config: _falseConfig),
      _view('view_get_placeholder_resolved',
          'The effective value of a placeholder names the variable, not the secret.',
          const ['placeholder', 'provenance'], {'op': 'get', 'pointer': '/label'},
          layers: labelLayer),
      _view('view_get_absent_no_default',
          'An absent value with no default reports exists false and no value.',
          const ['six-states', 'missing'], {'op': 'get', 'pointer': '/heavy'},
          config: _sparseConfig),
      _view('view_get_empty_string', 'A stored empty string is a value of its own.',
          const ['six-states', 'empty'], {'op': 'get', 'pointer': '/heavy'},
          config: _emptyConfig),
      _view('view_get_secret_denied',
          'A read of a secret subtree without the permission is denied.',
          const ['secret', 'rejection'], {'op': 'get', 'pointer': '/secret_token'},
          principal: 'no_secret_read'),
      _view('view_effective_secret_denied',
          'The whole effective snapshot of a document with an inaccessible secret.',
          const ['secret', 'rejection'], {'op': 'effective'},
          principal: 'no_secret_read',
          secretMarker: 's3cr3t',
          divergence: _corrected(
            id: 'VIEW-SECRET-LEAK',
            report: 'A40',
            note: 'The executed baseline hands the WHOLE effective snapshot, '
                'secret values included, to a principal without '
                '`settings_read_secret`: `load()` checks only the read '
                'permission and returns one shared tree, while `get()` on '
                'the very same pointer denies that principal with '
                'SECRET_ACCESS_DENIED. SPEC.md amendment 2 (a snapshot is '
                'what the principal may see) and amendment 9 '
                'with SEC-01 require a secret subtree to be unavailable '
                'without the permission on EVERY surface; the corrected view '
                'leaves every inaccessible secret subtree out of the '
                'effective tree and out of its provenance, so the secret '
                'value is not visible to this principal.',
            corrected: {
              'result': 'viewed',
              'secretVisible': false,
            },
          )),
      _view('view_get_secret_allowed',
          'The same read is answered for a principal with the secret permission.',
          const ['secret', 'accept'], {'op': 'get', 'pointer': '/secret_token'}),
    ];


// -- 6. callbacks, subscriptions and their bounds -------------------------------

CorpusCase _callback(
  String id,
  String description,
  List<String> classes,
  String scenario, {
  String path = '/port',
  String value = '8080',
  List<String> paths = const ['/port'],
  String? other,
  Map<String, Object?>? divergence,
}) =>
    CorpusCase(
      id: id,
      description: description,
      classes: [...classes, 'callback'],
      kind: 'pipeline_callback',
      input: initialSource,
      payload: {
        'area': 'pipeline_callbacks',
        'scenario': scenario,
        'descriptor': descriptorSource,
        'config': initialSource,
        'path': path,
        'value': value,
        'paths': paths,
        if (other != null) 'other': other,
        'layers': emptyLayers,
      },
      divergence: divergence,
    );

List<CorpusCase> _callbackCases() => [
      _callback('cb_probe_vetoes_before_commit',
          'A pre-commit probe may refuse the candidate and nothing is stored.',
          const ['probe', 'veto', 'rejection'], 'veto'),
      _callback('cb_probe_timeout_refuses_write',
          'A probe that outlives its bound refuses the write with CALLBACK_TIMEOUT.',
          const ['probe', 'timeout', 'rejection'], 'timeout'),
      _callback('cb_application_failure_keeps_commit',
          'A failing application handler still reports the commit.',
          const ['application', 'apply_failed'], 'application_fail',
          path: '/host', value: '"h2"'),
      _callback('cb_application_not_called_for_restart',
          'A restart-only change calls no application handler.',
          const ['application', 'restart'], 'application_fail',
          path: '/heavy', value: '"v"'),
      _callback('cb_after_save_failure_keeps_commit',
          'A post-commit observer cannot cancel a committed result.',
          const ['after_save', 'observer'], 'after_save_fail'),
      _callback('cb_subscription_delivers_matching_event',
          'A subscription is notified for a write under its watched path.',
          const ['subscription', 'accept'], 'subscribe_paths', paths: ['/port']),
      _callback('cb_subscription_path_filter',
          'A subscription is not notified for a write outside its watched paths.',
          const ['subscription', 'filter'], 'subscribe_paths',
          paths: ['/boxed'], other: '/port'),
      _callback('cb_unsubscription_stops_events',
          'A cancelled handle receives no further events.',
          const ['subscription', 'cancel'], 'unsubscribe', paths: ['/port']),
      _callback('cb_secret_event_not_delivered',
          'A subscription of a principal with no secret access gets no event for a '
          'secret path.',
          const ['subscription', 'secret', 'rejection'], 'secret_event',
          path: '/secret_token', value: '"changed"', paths: ['/secret_token'],
          divergence: _corrected(
            id: 'CB-SECRET-EVENT-LEAK',
            report: 'A41',
            note: 'The executed baseline delivers a change event naming '
                'the secret path `/secret_token` to a subscriber without '
                '`settings_read_secret`: `subscribe()` records '
                'the paths and `_notify` matches them with no permission '
                'filter, so a subscription becomes a channel that '
                'reveals which secret subtree changed and when. '
                'SPEC.md amendment 9 states it directly: Permission filtering '
                'MUST NOT leak a secret subtree through events; SEC-01 '
                'requires the subtree to be unavailable on every '
                'surface. The corrected behavior delivers no event to a '
                'subscriber who could not read the changed path.',
            corrected: {
              'events': <Object?>[],
            },
          )),
    ];

/// The complete pipeline catalog.
List<CorpusCase> pipelineCases() => [
      ..._storedCases(),
      ..._dryRunCases(),
      ..._rejectionCases(),
      ..._secretPathCases(),
      ..._casCases(),
      ..._viewCases(),
      ..._callbackCases(),
    ];
