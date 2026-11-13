/// Resolver corpus cases for `tool/generate_corpus.dart` (stage 2, slice 2B).
///
/// Each entry names the injected value layers plus one resolver call, and is
/// executed against the Python baseline by `tool/python/corpus_driver.py`. The
/// expectations are what the baseline produced, never what prose says.
///
/// Every case passes all three layers explicitly. The baseline's own default
/// for `environ` is the process environment, so a corpus that relied on the
/// default would depend on the machine it ran on — and reading the host
/// environment is exactly what `SPEC.md` amendment 6 forbids here.
///
/// Areas:
///
/// * `resolver_lookup`    — the precedence chain and `presence`.
/// * `resolver_text`        — placeholder syntax inside a string, single-pass
///   substitution, provenance of one text value.
/// * `resolver_effective`   — a whole effective snapshot: conversion, `env.allowed`,
///   defaults, the six leaf states, union and array node selection, provenance.
library;

import 'corpus_cases.dart';

// -- tagged value builders (for authored corrections) -------------------

Map<String, Object?> tNull() => const {'k': 'null'};
Map<String, Object?> tMissing() => const {'k': 'missing'};
Map<String, Object?> tBool(bool v) => {'k': 'bool', 'v': v};
Map<String, Object?> tInt(String decimal) => {'k': 'int', 'v': decimal};
Map<String, Object?> tNum(double v) => {'k': 'double', 'v': v};
Map<String, Object?> tStr(String v) => {'k': 'string', 'v': v};
Map<String, Object?> tObj(Map<String, Map<String, Object?>> entries) => {
      'k': 'object',
      'v': [
        for (final entry in entries.entries) [entry.key, entry.value],
      ],
    };
Map<String, Object?> tArr(List<Map<String, Object?>> items) =>
    {'k': 'array', 'v': items};

/// One provenance entry, in the shape the baseline records.
Map<String, Object?> prov({
  required String kind,
  String? variable,
  String? source,
  List<String>? variables,
}) =>
    tObj({
      'kind': tStr(kind),
      if (variable != null) 'variable': tStr(variable),
      if (variables != null) 'variables': tArr([for (final v in variables) tStr(v)]),
      if (source != null) 'source': tStr(source),
    });

/// A corrected provenance map for a value built from several variables.
Map<String, Object?> multiProv(String path, List<String> names, {String? source}) =>
    tObj({
      path: tObj({
        'kind': tStr('environment'),
        'variable': tStr(names.first),
        'variables': tArr([for (final name in names) tStr(name)]),
        if (source != null) 'source': tStr(source),
      }),
    });

Map<String, Object?> issue(
  String rule,
  String path, {
  String severity = 'error',
}) =>
    {
      'rule': rule,
      'path': path,
      'severity': severity,
      'hasMessage': true,
    };

// -- case builders ---------------------------------------------------------

/// The three injected layers. Omitted layers are empty, never the machine.
Map<String, Object?> valueLayers({
  Map<String, String> overrides = const {},
  Map<String, String> environ = const {},
  Map<String, String> dotenv = const {},
}) =>
    {
      'overrides': overrides,
      'environ': environ,
      'dotenv': dotenv,
    };

CorpusCase _lookup(
  String id,
  String description,
  List<String> classes,
  Map<String, Object?> layers,
  Map<String, Object?> query, {
  Map<String, Object?>? divergence,
}) =>
    CorpusCase(
      id: id,
      description: description,
      classes: classes,
      kind: 'resolver_lookup',
      input: '',
      query: query,
      payload: {'layers': layers},
      divergence: divergence,
    );

CorpusCase _lookupVar(
  String id,
  String description,
  List<String> classes, {
  Map<String, Object?> layers = const {'overrides': {}, 'environ': {}, 'dotenv': {}},
  String name = 'V',
  String? inlineDefault,
  bool passDefault = true,
}) =>
    _lookup(id, description, classes, layers, {
      'op': 'lookup',
      'name': name,
      if (passDefault) 'inlineDefault': inlineDefault,
    });

CorpusCase _text(
  String id,
  String description,
  List<String> classes,
  String input,
  Map<String, Object?> layers, {
  String path = '/value',
  Map<String, Object?>? divergence,
}) =>
    CorpusCase(
      id: id,
      description: description,
      classes: classes,
      kind: 'resolver_text',
      input: input,
      payload: {'layers': layers, 'path': path},
      divergence: divergence,
    );

CorpusCase _effective(
  String id,
  String description,
  List<String> classes, {
  required String descriptor,
  required String config,
  Map<String, Object?> layers = const {
    'overrides': {},
    'environ': {},
    'dotenv': {},
  },
  Map<String, Object?>? query,
  Map<String, Object?>? divergence,
}) =>
    CorpusCase(
      id: id,
      description: description,
      classes: classes,
      kind: 'resolver_effective',
      input: config,
      payload: {
        'descriptor': descriptor,
        'config': config,
        'layers': layers,
        if (query != null) 'query': query,
      },
      divergence: divergence,
    );

Map<String, Object?> _corrected({
  required String id,
  required String report,
  required String note,
  required Map<String, Object?> corrected,
}) =>
    divergenceExpectation(id: id, report: report, note: note, corrected: corrected);

// -- shared descriptors ------------------------------------------------

/// The shared descriptor. It declares **no defaults**: a materialized default
/// would appear in every case's effective value and provenance, so each
/// case would have to restate it. The cases that are about defaults build
/// their own one-field descriptor with [singleField].
final String resolverDescriptor = '''
{
  descriptor_version: "1.0",
  root: {
    type: "object",
    children: {
      plain: { type: "string" },
      templated: { type: "string", env: { allowed: true, convert: "string" } },
      noconvert: { type: "string", env: { allowed: true } },
      number: { type: "int", env: { allowed: true, convert: "int" } },
      real: { type: "number", env: { allowed: true, convert: "number" } },
      flag: { type: "bool", env: { allowed: true, convert: "bool" } },
      not_allowed: { type: "string" },
      list: { type: "array", children: { type: "string", env: { allowed: true } } },
      dynamic: { type: "object", additional_children: { type: "string", env: { allowed: true } } },
      patterned: { type: "object", key_pattern: "^ok", additional_children: { type: "string", env: { allowed: true } } },
      opaque: { type: "any" },
    },
  },
}
''';

/// A root object with exactly one declared child, so a case's effective
/// value and provenance stay small enough to read.
String singleField(String fieldBody) =>
    '{ descriptor_version: "1.0", root: { type: "object", children: { $fieldBody } } }';

/// An object whose dynamic keys are limited by `key_enum`.
final String keyEnumDescriptor = '''
{ descriptor_version: "1.0", root: { type: "object", children: {
    s: { type: "object", key_enum: ["ok"], additional_children: { type: "object",
        children: { x: { type: "string", default: "X" } } } },
} } }
''';

/// An object whose dynamic keys are limited by `key_pattern`.
final String keyPatternDescriptor = '''
{ descriptor_version: "1.0", root: { type: "object", children: {
    s: { type: "object", key_pattern: "^ok",
         additional_children: { type: "string", env: { allowed: true } } },
} } }
''';

/// A union whose two alternatives declare the same key with different
/// conversions; the case where resolution has to pick one.
final String unionDescriptor = '''
{
  descriptor_version: "1.0",
  root: { type: "object", children: {
    items: { type: "object", additional_children: { type: "union", children_options: [
      { type: "object", children: { port: { type: "int", env: { allowed: true, convert: "int" } } } },
      { type: "object", children: { port: { type: "string", env: { allowed: true, convert: "string" } } } },
    ] } },
  } },
}
''';

/// A union where each key is declared by exactly one alternative, as the
/// baseline tests write it.
final String disjointUnionDescriptor = '''
{
  descriptor_version: "1.0",
  root: { type: "object", children: {
    items: { type: "object", additional_children: { type: "union", children_options: [
      { type: "object", children: { enabled: { type: "bool" } } },
      { type: "object", children: {
          label: { type: "string", env: { allowed: true, convert: "string" } },
          port: { type: "int", env: { allowed: true, convert: "int" } },
        } },
    ] } },
  } },
}
''';

/// A heterogeneous array: one alternative per position.
final String heterogeneousDescriptor = '''
{
  descriptor_version: "1.0",
  root: { type: "object", children: {
    steps: { type: "array", children_options: [
      { type: "object", children: { a: { type: "string", default: "A" } } },
      { type: "object", children: { b: { type: "string", default: "B" } } },
      { type: "int" },
    ] },
  } },
}
''';

/// A homogeneous array whose single item node allows env.
final String homogeneousDescriptor = '''
{
  descriptor_version: "1.0",
  root: { type: "object", children: {
    tags: { type: "array", children: { type: "string", env: { allowed: true } } },
  } },
}
''';

// -- resolver_lookup ----------------------------------------------------------

List<CorpusCase> _lookupCases() => [
      _lookupVar('lookup_override_only', 'A value from the host override layer.',
          const ['precedence', 'override'], layers: valueLayers(overrides: {'V': 'from-override'})),
      _lookupVar('lookup_override_beats_env', 'The override layer wins over the environment.',
          const ['precedence', 'override', 'env'],
          layers: valueLayers(overrides: {'V': 'override'}, environ: {'V': 'env'})),
      _lookupVar('lookup_env_beats_dotenv', 'The environment wins over the dotenv mapping.',
          const ['precedence', 'env', 'dotenv'],
          layers: valueLayers(environ: {'V': 'env'}, dotenv: {'V': 'dotenv'})),
      _lookupVar('lookup_dotenv_beats_inline', 'The dotenv mapping wins over the inline default.',
          const ['precedence', 'dotenv', 'inline-default'],
          layers: valueLayers(dotenv: {'V': 'dotenv'}), inlineDefault: 'inline'),
      _lookupVar('lookup_inline_default_when_unset',
          'With nothing set, the inline default is used.', const ['inline-default'],
          inlineDefault: 'inline'),
      _lookupVar('lookup_empty_when_unset',
          'With nothing set and no default, the value is the empty string.',
          const ['empty']),
      _lookupVar('lookup_explicit_empty_inline_default',
          'An explicit empty inline default is still a default.',
          const ['inline-default', 'empty'], inlineDefault: ''),
      _lookupVar('lookup_override_empty_env_set_with_default',
          'An empty override does not stop the chain when a default exists.',
          const ['precedence', 'empty-value'],
          layers: valueLayers(overrides: {'V': ''}, environ: {'V': 'env'}), inlineDefault: 'fb'),
      _lookupVar('lookup_override_empty_env_set_no_default',
          'An empty override with a set lower layer yields the lower value.',
          const ['precedence', 'empty-value'],
          layers: valueLayers(overrides: {'V': ''}, environ: {'V': 'env'})),
      _lookupVar('lookup_override_empty_nothing_else_with_default',
          'An empty override falls through to the inline default.',
          const ['empty-value', 'inline-default'],
          layers: valueLayers(overrides: {'V': ''}), inlineDefault: 'fb'),
      _lookupVar('lookup_override_empty_nothing_else_no_default',
          'An empty override with nothing below reports the override as its source.',
          const ['empty-value', 'precedence'], layers: valueLayers(overrides: {'V': ''})),
      _lookupVar('lookup_env_empty_with_default',
          'An empty environment value falls through to the inline default.',
          const ['empty-value', 'inline-default'],
          layers: valueLayers(environ: {'V': ''}), inlineDefault: 'fb'),
      _lookupVar('lookup_env_empty_no_default',
          'An empty environment value with no default is empty, sourced env.',
          const ['empty-value'], layers: valueLayers(environ: {'V': ''})),
      _lookupVar('lookup_dotenv_empty_with_default',
          'An empty dotenv value falls through to the inline default.',
          const ['empty-value', 'inline-default'],
          layers: valueLayers(dotenv: {'V': ''}), inlineDefault: 'fb'),
      _lookupVar('lookup_value_is_data_not_template',
          'A value containing a placeholder is returned verbatim.',
          const ['single-pass'], layers: valueLayers(overrides: {'V': '\${OTHER}'})),
      _lookupVar('lookup_value_with_json_structure',
          'A value that looks like a document stays text.', const ['single-pass'],
          layers: valueLayers(overrides: {'V': '{"injected": true}'})),
      _lookupVar('lookup_unicode_value', 'A non-ASCII value passes through unchanged.',
          const ['unicode'], layers: valueLayers(environ: {'V': 'значение — ✓'})),
      _lookupVar('lookup_astral_value', 'An astral value passes through unchanged.',
          const ['astral'], layers: valueLayers(environ: {'V': 'rocket \u{1F680}'})),
      _lookupVar('lookup_value_with_spaces',
          'Surrounding spaces are kept by lookup.', const ['whitespace'],
          layers: valueLayers(environ: {'V': '  spaced  '})),
      _lookupVar('lookup_name_not_prefix_matched',
          'A longer name does not answer for a shorter one.', const ['names'],
          layers: valueLayers(environ: {'VARS': 'x'}), name: 'VAR'),
      _lookupVar('lookup_case_sensitive_name',
          'Names are case-sensitive.', const ['names'],
          layers: valueLayers(environ: {'var': 'lower'}), name: 'VAR'),
      _lookupVar('lookup_multiline_value', 'A value with a line break passes through.',
          const ['whitespace'], layers: valueLayers(environ: {'V': 'a\nb'})),
      _lookup(
        'lookup_underscore_name',
        'A name starting with an underscore is a valid name.',
        const ['names'],
        valueLayers(environ: {'_PRIVATE': 'p'}),
        const {'op': 'lookup', 'name': '_PRIVATE', 'inlineDefault': null},
      ),
      _lookup('presence_mixed', 'Presence reports set and unset without exposing values.',
          const ['presence'],
          valueLayers(environ: {'A': 'x', 'B': ''}, dotenv: {'C': 'y'}),
          const {'op': 'presence', 'names': ['A', 'B', 'C', 'D']}),
      _lookup('presence_skips_invalid_names',
          'A name that is not an identifier is left out of the answer.',
          const ['presence', 'names'],
          valueLayers(environ: {'OK': 'x'}),
          const {'op': 'presence', 'names': ['OK', 'not a name', '1BAD', 'also_ok', '', 'a-b']}),
      _lookup('presence_empty_list', 'Asking for no names answers with nothing.',
          const ['presence'], valueLayers(), const {'op': 'presence', 'names': []}),
    ];

// -- resolver_text ----------------------------------------------------------

List<CorpusCase> _textCases() {
  CorpusCase t(String id, String description, List<String> classes, String input,
          Map<String, Object?> layers, {
          String path = '/value',
          Map<String, Object?>? divergence}) =>
      _text(id, description, [...classes], input, layers, path: path, divergence: divergence);

  const one = {'V': 'x'};
  return [
    t('text_simple', 'One placeholder in an otherwise empty string.',
        const ['syntax', 'accept'], '\${V}', valueLayers(environ: one)),
    t('text_inside_words', 'A placeholder surrounded by text.', const ['syntax'],
        'a-\${V}-b', valueLayers(environ: one)),
    t('text_with_inline_default', 'An inline default is used when the variable is unset.',
        const ['inline-default'], '\${V:-fb}', valueLayers()),
    t('text_with_empty_inline_default', 'An explicit empty inline default resolves to empty.',
        const ['inline-default', 'empty'], '\${V:-}', valueLayers()),
    t('text_default_with_spaces', 'The inline default keeps its spaces.',
        const ['inline-default', 'whitespace'], '\${V:-a b}', valueLayers()),
    t(
      'text_adjacent_placeholders',
      'Two placeholders with nothing between them.',
      const ['syntax', 'adjacent', 'provenance', 'A22'],
      '\${A}\${B}',
      valueLayers(environ: {'A': '1', 'B': '2'}),
      divergence: _corrected(
        id: 'A22',
        report: 'A22',
        note: 'The baseline records provenance inside the substitution loop, so only the last '
            'placeholder of a string survives: this value is attributed to B alone. The Dart '
            'implementation names every contributing variable and keeps '
            'the single-variable shape byte-identical.',
        corrected: {
          'ok': true,
          'output': '12',
          'issues': <Object?>[],
          'provenance': multiProv('/value', ['A', 'B']),
        },
      ),
    ),
    t('text_repeated_placeholder', 'The same variable twice.', const ['repeated'],
        '\${V}/\${V}', valueLayers(environ: one)),
    t(
      'text_many_placeholders',
      'Three placeholders in one string.',
      const ['adjacent', 'provenance', 'A22'],
      '\${A}-\${B}-\${C}',
      valueLayers(environ: {'A': '1', 'B': '2', 'C': '3'}),
      divergence: _corrected(
        id: 'A22',
        report: 'A22',
        note: 'Same defect as text_adjacent_placeholders: three variables contribute, one is '
            'recorded.',
        corrected: {
          'ok': true,
          'output': '1-2-3',
          'issues': <Object?>[],
          'provenance': multiProv('/value', ['A', 'B', 'C']),
        },
      ),
    ),
    t(
      'text_nested_placeholder',
      'A placeholder whose default opens another placeholder.',
      const ['syntax', 'nested', 'A23'],
      '\${A:-\${B}}',
      valueLayers(environ: {'A': 'V'}),
      divergence: _corrected(
        id: 'A23',
        report: 'A23',
        note: 'The baseline placeholder pattern takes any run of non-} characters as the '
            'default, so it matches the prefix "\${A:-\${B}" of a nested reference, substitutes '
            'A and leaves the trailing brace: the value becomes "V}". A malformed '
            'reference is therefore silently mangled instead of being left '
            'alone. The Dart implementation treats a default that opens another placeholder as '
            'not a placeholder at all, so the text is returned verbatim.',
        corrected: {
          'ok': true,
          'output': '\${A:-\${B}}',
          'issues': [],
          'provenance': tObj({}),
        },
      ),
    ),
    t('text_nested_placeholder_unset',
      'The same nested reference with the outer variable unset.',
      const ['syntax', 'nested', 'A23'],
      '\${A:-\${B}}',
      valueLayers(),
      divergence: _corrected(
        id: 'A23',
        report: 'A23',
        note: 'With A unset the baseline substitutes the literal broken default "\${B" and appends '
            'the leftover brace, producing "\${B}". The corrected behaviour leaves the text '
            'untouched.',
        corrected: {
          'ok': true,
          'output': '\${A:-\${B}}',
          'issues': [],
          'provenance': tObj({}),
        },
      ),
    ),
    t('text_single_pass', 'A resolved value is not scanned again.',
        const ['single-pass'], '\${A}', valueLayers(overrides: {'A': '\${B}', 'B': 'deep'})),
    t(
      'text_single_pass_default',
      'A nested inline default is not a reference and is not scanned again.',
      const ['single-pass', 'nested', 'A23'],
      '\${A:-\${B}}',
      valueLayers(overrides: {'B': 'deep'}),
      divergence: _corrected(
        id: 'A23',
        report: 'A23',
        note: 'The baseline matches the prefix "\${A:-\${B}" of the nested reference and '
            'substitutes the broken default as text, producing "\${B}" for a reference the '
            'grammar does not define. The Dart implementation leaves the construct alone.',
        corrected: {
          'ok': true,
          'output': '\${A:-\${B}}',
          'issues': <Object?>[],
          'provenance': tObj({}),
        },
      ),
    ),
    t('text_dollar_before_placeholder', 'A literal dollar sign stays.',
        const ['syntax'], '\$\${A}', valueLayers(environ: one)),
    t('text_dollar_space_name', 'A dollar sign with a space is not a reference.',
        const ['syntax', 'reject'], '\$ {A}', valueLayers(environ: {'A': 'x'})),
    t('text_unterminated', 'A reference with no closing brace is left alone.',
        const ['syntax', 'reject'], '\${A', valueLayers(environ: one)),
    t('text_bad_operator', 'Only the :- operator exists; anything else is literal text.',
        const ['syntax', 'reject'], '\${A-x}', valueLayers(environ: one)),
    t('text_empty_name', 'An empty name is not a reference.', const ['syntax', 'reject'],
        '\${}', valueLayers(environ: one)),
    t('text_only_dash_name', 'A name cannot start with a dash.', const ['syntax', 'reject'],
        '\${-}', valueLayers(environ: one)),
    t('text_digit_name', 'A name cannot start with a digit.', const ['syntax', 'reject'],
        '\${1A}', valueLayers(environ: one)),
    t('text_spaced_name', 'A name cannot contain a space.', const ['syntax', 'reject'],
        '\${A B}', valueLayers(environ: one)),
    t('text_dollar_in_name', 'A dollar sign is not a name character.',
        const ['syntax', 'reject'], '\${A\$B}', valueLayers(environ: one)),
    t('text_default_with_brace_inside', 'A default cannot contain a closing brace.',
        const ['syntax', 'reject'], '\${A:-x}y}', valueLayers()),
    t('text_no_placeholder', 'A plain string is returned unchanged.', const ['no-placeholder'],
        'just text', valueLayers(environ: one)),
    t('text_empty_string', 'An empty string has nothing to substitute.', const ['empty'],
        '', valueLayers(environ: one)),
    t('text_placeholders_around_empty_value',
        'A variable set to the empty string contributes nothing.', const ['empty-value'],
        '[\${A}]', valueLayers(environ: {'A': ''})),
    t('text_provenance_env_has_no_source',
        'A value from the environment records no source key.', const ['provenance'],
        '\${A}', valueLayers(environ: {'A': '1'})),
    t(
      'text_provenance_multiple_variables',
      'Provenance of a string built from two variables.',
      const ['provenance', 'multiple', 'A22'],
      'x \${A} y \${B} z',
      valueLayers(overrides: {'A': '1'}, environ: {'B': '2'}),
      divergence: _corrected(
        id: 'A22',
        report: 'A22',
        note: 'The baseline assigns provenance inside the substitution loop, so only the LAST '
            'placeholder survives: the entry says the value came from variable B and records '
            'nothing about A, which came from an explicit host override. SPEC.md 6 requires '
            'provenance to say which layer supplied a value, and the answer here is two layers. '
            'The Dart implementation records every contributing variable and the highest-precedence '
            'source among them, keeping the single-variable shape byte-identical to the baseline.',
        corrected: {
          'ok': true,
          'output': 'x 1 y 2 z',
          'issues': [],
          'provenance': tObj({
            '/value': tObj({
              'kind': tStr('environment'),
              'variable': tStr('A'),
              'variables': tArr([tStr('A'), tStr('B')]),
              'source': tStr('override'),
            }),
          }),
        },
      ),
    ),
    t('text_provenance_override', 'An override is named as the source.',
        const ['provenance'], '\${A}', valueLayers(overrides: {'A': '1'})),
    t('text_provenance_dotenv', 'The dotenv mapping is named as the source.',
        const ['provenance'], '\${A}', valueLayers(dotenv: {'A': '1'})),
    t('text_provenance_inline_default', 'The inline fallback is named as the source.',
        const ['provenance'], '\${A:-fb}', valueLayers()),
    t('text_provenance_empty', 'An unset variable with no default is named as empty.',
        const ['provenance'], '\${A}', valueLayers()),
    t('text_provenance_root_path',
        'The empty path is recorded under the empty key.', const ['provenance', 'paths'],
        '\${A}', valueLayers(environ: {'A': '1'}), path: ''),
    t('text_provenance_nested_path', 'A deep path is recorded verbatim.',
        const ['provenance', 'paths'], '\${A}', valueLayers(environ: {'A': '1'}),
        path: '/servers/a~1b/port'),
    t('text_no_placeholder_no_provenance',
        'A string with no reference records nothing here.', const ['provenance'],
        'plain', valueLayers(environ: {'A': '1'})),
  ];
}

// -- resolver_effective -------------------------------------------------------

List<CorpusCase> _conversionCases() {
  CorpusCase c(String id, String description, List<String> classes, String config,
          Map<String, Object?> layers, {Map<String, Object?>? divergence}) =>
      _effective(id, description, classes,
          descriptor: resolverDescriptor,
          config: config,
          layers: layers,
          divergence: divergence);

  return [
    c('conv_int_bare', 'A bare placeholder converted to int.', const ['convert', 'int'],
        '{ number: \${N} }', valueLayers(environ: {'N': '42'})),
    c('conv_int_quoted', 'The quoted form converts identically.',
        const ['convert', 'int'], '{ number: "\${N}" }', valueLayers(environ: {'N': '42'})),
    c('conv_int_plus_sign', 'A leading plus is an integer.', const ['convert', 'int'],
        '{ number: "\${N}" }', valueLayers(environ: {'N': '+42'})),
    c('conv_int_negative', 'A negative integer.', const ['convert', 'int'],
        '{ number: "\${N}" }', valueLayers(environ: {'N': '-7'})),
    c('conv_int_surrounding_spaces', 'The value is stripped before conversion.',
        const ['convert', 'int', 'whitespace'], '{ number: "\${N}" }',
        valueLayers(environ: {'N': ' 42 '})),
    c('conv_int_fraction_rejected', 'A fractional text is not an int.',
        const ['convert', 'int', 'rejection'], '{ number: "\${N}" }',
        valueLayers(environ: {'N': '1.0'})),
    c('conv_int_hex_rejected', 'Hexadecimal text is not an int.',
        const ['convert', 'int', 'rejection'], '{ number: "\${N}" }',
        valueLayers(environ: {'N': '0x10'})),
    c('conv_int_word_rejected', 'Non-numeric text is not an int.',
        const ['convert', 'int', 'rejection'], '{ number: "\${N}" }',
        valueLayers(environ: {'N': 'abc'})),
    c('conv_int_empty_rejected', 'An empty value cannot become an int.',
        const ['convert', 'int', 'rejection', 'empty'], '{ number: "\${N}" }',
        valueLayers(environ: {'N': ''})),
    c('conv_int_above_exact_range',
        'An integer above 2^53-1 is refused, never rounded.',
        const ['convert', 'int', 'rejection', 'exact-range'], '{ number: "\${N}" }',
        valueLayers(environ: {'N': '9007199254740992'})),
    c('conv_int_at_exact_max', 'The exact maximum is accepted.',
        const ['convert', 'int', 'exact-range'], '{ number: "\${N}" }',
        valueLayers(environ: {'N': '9007199254740991'})),
    c('conv_int_at_exact_min', 'The exact minimum is accepted.',
        const ['convert', 'int', 'exact-range'], '{ number: "\${N}" }',
        valueLayers(environ: {'N': '-9007199254740991'})),
    c('conv_int_below_exact_range', 'Below the exact minimum is refused.',
        const ['convert', 'int', 'rejection', 'exact-range'], '{ number: "\${N}" }',
        valueLayers(environ: {'N': '-9007199254740992'})),
    c('conv_int_huge_rejected', 'A thirty-digit integer is refused.',
        const ['convert', 'int', 'rejection', 'exact-range'], '{ number: "\${N}" }',
        valueLayers(environ: {'N': '123456789012345678901234567890'})),
    c('conv_number_decimal', 'A decimal becomes a number.', const ['convert', 'number'],
        '{ real: \${N} }', valueLayers(environ: {'N': '1.5'})),
    c('conv_number_exponent', 'Exponent notation is accepted.', const ['convert', 'number'],
        '{ real: "\${N}" }', valueLayers(environ: {'N': '1e5'})),
    c('conv_number_integer_text', 'An integer text is a valid number.',
        const ['convert', 'number'], '{ real: "\${N}" }', valueLayers(environ: {'N': '3'})),
    c('conv_number_nan_rejected', 'NaN is refused.', const ['convert', 'number', 'rejection'],
        '{ real: "\${N}" }', valueLayers(environ: {'N': 'nan'})),
    c('conv_number_infinity_rejected', 'Infinity is refused.',
        const ['convert', 'number', 'rejection'], '{ real: "\${N}" }',
        valueLayers(environ: {'N': 'Infinity'})),
    c('conv_number_negative_infinity_rejected', 'Negative Infinity is refused.',
        const ['convert', 'number', 'rejection'], '{ real: "\${N}" }',
        valueLayers(environ: {'N': '-Infinity'})),
    c('conv_number_word_rejected', 'Non-numeric text is refused.',
        const ['convert', 'number', 'rejection'], '{ real: "\${N}" }',
        valueLayers(environ: {'N': 'abc'})),
    c('conv_bool_true', 'The literal true becomes a boolean.', const ['convert', 'bool'],
        '{ flag: \${B} }', valueLayers(environ: {'B': 'true'})),
    c('conv_bool_false', 'The literal false becomes a boolean.', const ['convert', 'bool'],
        '{ flag: "\${B}" }', valueLayers(environ: {'B': 'false'})),
    c('conv_bool_capitalized_rejected', 'True is not true.',
        const ['convert', 'bool', 'rejection'], '{ flag: "\${B}" }',
        valueLayers(environ: {'B': 'True'})),
    c('conv_bool_yes_rejected', 'Only the two literals convert.',
        const ['convert', 'bool', 'rejection'], '{ flag: "\${B}" }',
        valueLayers(environ: {'B': 'yes'})),
    c('conv_bool_one_rejected', 'The digit one is not a boolean.',
        const ['convert', 'bool', 'rejection'], '{ flag: "\${B}" }',
        valueLayers(environ: {'B': '1'})),
    c('conv_bool_empty_rejected', 'An empty value is not a boolean.',
        const ['convert', 'bool', 'rejection', 'empty'], '{ flag: "\${B}" }',
        valueLayers(environ: {'B': ''})),
    c('conv_int_underscore_grouping',
        'Python literal underscore grouping is not an integer here.',
        const ['convert', 'int', 'number-grammar', 'rejection'],
        '{ number: "\${N}" }',
        valueLayers(environ: {'N': '1_0'})),
    c(
      'conv_number_underscore_grouping',
      'A number written with Python literal underscore grouping.',
      const ['convert', 'number', 'number-grammar', 'A28'],
      '{ real: "\${N}" }',
      valueLayers(environ: {'N': '1_0'}),
      divergence: _corrected(
        id: 'A28',
        report: 'A28',
        note: 'The number conversion calls float() with no format check of its own, and '
            'Python\'s float() accepts the underscore grouping of its literal syntax, so the '
            'settings value "1_0" silently means ten. The integer conversion refuses the same '
            'text through its explicit pattern, so the two numeric types disagree about one '
            'format. The Dart implementation applies one ASCII decimal grammar to '
            'both and reports env_conversion.',
        corrected: {
          'ok': true,
          'effective': tObj({'real': tNull()}),
          'issues': [issue('env_conversion', '/real')],
          'provenance': tObj({
            '/real': prov(kind: 'environment', variable: 'N'),
          }),
          'inputsUnchanged': true,
        },
      ),
    ),
    c(
      'conv_int_unicode_digits',
      'A number written with Arabic-Indic digits.',
      const ['convert', 'int', 'number-grammar', 'A29'],
      '{ number: "\${N}" }',
      valueLayers(environ: {'N': '\u0662\u0660'}),
      divergence: _corrected(
        id: 'A29',
        report: 'A29',
        note: 'The integer pattern uses \d, which is Unicode-aware in Python, and '
            'int() then accepts the digits, so "\u0662\u0660" converts to 20. '
            'docs/grammars.md fixes \d as ASCII for this product, and a value one engine '
            'reads as a number and the other refuses breaks mutual readability of the same '
            'file. The Dart implementation refuses it with env_conversion.',
        corrected: {
          'ok': true,
          'effective': tObj({'number': tNull()}),
          'issues': [issue('env_conversion', '/number')],
          'provenance': tObj({
            '/number': prov(kind: 'environment', variable: 'N'),
          }),
          'inputsUnchanged': true,
        },
      ),
    ),
    c(
      'conv_number_unicode_digits',
      'A decimal number written with Arabic-Indic digits.',
      const ['convert', 'number', 'number-grammar', 'A29'],
      '{ real: "\${N}" }',
      valueLayers(environ: {'N': '\u0661\u0662.5'}),
      divergence: _corrected(
        id: 'A29',
        report: 'A29',
        note: 'Same item as conv_int_unicode_digits, on the number conversion, which has no '
            'pattern at all and goes straight to float().',
        corrected: {
          'ok': true,
          'effective': tObj({'real': tNull()}),
          'issues': [issue('env_conversion', '/real')],
          'provenance': tObj({
            '/real': prov(kind: 'environment', variable: 'N'),
          }),
          'inputsUnchanged': true,
        },
      ),
    ),
    c('conv_string_keeps_spaces', 'A string conversion does not strip.',
        const ['convert', 'string', 'whitespace'], '{ templated: "\${V}" }',
        valueLayers(environ: {'V': '  spaced  '})),
    c('conv_no_convert_field_is_string',
        'env.allowed without a conversion resolves to text.', const ['convert', 'string'],
        '{ noconvert: "\${V}" }', valueLayers(environ: {'V': '42'})),
    c('conv_text_with_surrounding_words',
        'A number node whose text has other words cannot convert.',
        const ['convert', 'int', 'rejection'], '{ number: "port: \${N}" }',
        valueLayers(environ: {'N': '42'})),
    c('conv_inline_default_converted', 'The inline default goes through the conversion.',
        const ['convert', 'int', 'inline-default'], '{ number: "\${N:-7}" }', valueLayers()),
    c('conv_inline_default_bad_value', 'A bad inline default is reported like a bad variable.',
        const ['convert', 'int', 'rejection', 'inline-default'], '{ number: "\${N:-abc}" }',
        valueLayers()),
    c('conv_from_override', 'The layer does not change conversion.',
        const ['convert', 'int', 'override'], '{ number: "\${N}" }',
        valueLayers(overrides: {'N': '5'})),
    c('conv_from_dotenv', 'The dotenv layer converts too.',
        const ['convert', 'int', 'dotenv'], '{ number: "\${N}" }',
        valueLayers(dotenv: {'N': '6'})),
    c(
      'conv_multiple_in_one_string',
      'Two references in one string converted to int.',
      const ['convert', 'int', 'multiple', 'provenance', 'A22'],
      '{ number: "\${A}\${B}" }',
      valueLayers(environ: {'A': '1', 'B': '2'}),
      divergence: _corrected(
        id: 'A22',
        report: 'A22',
        note: 'The converted value came from two variables; the baseline provenance names only '
            'the last one.',
        corrected: {
          'ok': true,
          'effective': tObj({'number': tInt('12')}),
          'issues': <Object?>[],
          'provenance': multiProv('/number', ['A', 'B']),
          'inputsUnchanged': true,
        },
      ),
    ),
  ];
}

List<CorpusCase> _allowedCases() => [
      _effective('allowed_bare_requires_env',
          'A bare placeholder under a node without env.allowed is an error.',
          const ['env-allowed', 'rejection'],
          descriptor: resolverDescriptor,
          config: '{ not_allowed: \${V} }',
          layers: valueLayers(environ: {'V': 'x'})),
      _effective('allowed_quoted_stays_literal',
          'A quoted placeholder under a node without env.allowed is literal text.',
          const ['env-allowed'],
          descriptor: resolverDescriptor,
          config: '{ not_allowed: "\${V}" }',
          layers: valueLayers(environ: {'V': 'x'})),
      _effective('allowed_plain_text_untouched',
          'A plain string is returned as stored.', const ['file'],
          descriptor: resolverDescriptor,
          config: '{ plain: "text" }',
          layers: valueLayers(environ: {'V': 'x'})),
      _effective('allowed_undeclared_key_quoted',
          'A placeholder under an undeclared key stays literal.',
          const ['env-allowed', 'undeclared'],
          descriptor: resolverDescriptor,
          config: '{ undeclared: "\${V}" }',
          layers: valueLayers(environ: {'V': 'x'})),
      _effective('allowed_undeclared_key_bare',
          'A bare placeholder under an undeclared key is an error.',
          const ['env-allowed', 'undeclared', 'rejection'],
          descriptor: resolverDescriptor,
          config: '{ undeclared: \${V} }',
          layers: valueLayers(environ: {'V': 'x'})),
      _effective('allowed_inside_dynamic_key',
          'A value under additional_children resolves when allowed.',
          const ['env-allowed', 'dynamic'],
          descriptor: resolverDescriptor,
          config: '{ dynamic: { any: "\${V}" } }',
          layers: valueLayers(environ: {'V': 'x'})),
      _effective('allowed_inside_array',
          'Each item of a homogeneous array resolves.', const ['array'],
          descriptor: homogeneousDescriptor,
          config: '{ tags: ["\${A}", "b", "\${C}"] }',
          layers: valueLayers(environ: {'A': '1', 'C': '3'})),
      _effective('allowed_opaque_node',
          'The opaque type has no env policy, so a quoted placeholder stays literal.',
          const ['any'],
          descriptor: resolverDescriptor,
          config: '{ opaque: "\${V}" }',
          layers: valueLayers(environ: {'V': 'x'})),
      _effective('allowed_opaque_bare_placeholder',
          'A bare placeholder under the opaque type needs env.allowed.',
          const ['any', 'rejection'],
          descriptor: resolverDescriptor,
          config: '{ opaque: \${V} }',
          layers: valueLayers(environ: {'V': 'x'})),
      _effective('allowed_deep_object_path',
          'Resolution reaches a nested object.', const ['nested'],
          descriptor: resolverDescriptor,
          config: '{ nested: { inner: \${N} } }',
          layers: valueLayers(environ: {'N': '3'})),
    ];

List<CorpusCase> _leafStateCases() {
  CorpusCase stored(String id, String description, List<String> classes, String fieldBody,
          String config,
          {Map<String, Object?>? layerValues, Map<String, Object?>? divergenceOverride}) =>
      _effective(id, description, classes,
          descriptor: singleField(fieldBody),
          config: config,
          layers: layerValues ?? valueLayers(),
          divergence: divergenceOverride);

  /// A case whose whole point is a materialized default. The
  /// baseline reports such a value as `file` in `build_effective`
  /// while `effective_at` reports it as `default`, so the provenance is a
  /// registered correction (A27) and the effective value is not.
  CorpusCase materialized(String id, String description, List<String> classes,
          String fieldBody, String config, Map<String, Object?> effective, String path) =>
      stored(id, description, [...classes, 'A27'], fieldBody, config,
          divergenceOverride: _corrected(
            id: 'A27',
            report: 'A27',
            note: 'build_effective fills defaults and then walks the result, and the '
                'walk records every leaf it passes as "file" — including the value the '
                'descriptor just supplied. The same field read through effective_at is '
                'recorded as "default", so the baseline gives two answers to one '
                'question. SPEC.md 6 requires provenance to distinguish a default from a '
                'stored value, and SPEC.md 2 keeps the six leaf states apart; the Dart '
                'implementation keeps the default provenance.',
            corrected: {
              'ok': true,
              'effective': effective,
              'issues': <Object?>[],
              'provenance': tObj({path: prov(kind: 'default')}),
              'inputsUnchanged': true,
            },
          ));

  return [
    stored('leaf_absent_without_default', 'An absent field with no default stays absent.',
        const ['absent'], 'plain: { type: "string" }', '{ other: 1 }'),
    stored('leaf_explicit_null', 'An explicit null is not absent and is not defaulted.',
        const ['null', 'six-states'], 'a: { type: "string", default: "fb" }',
        '{ a: null }'),
    stored('leaf_false', 'false is a value, not an absence.',
        const ['bool', 'six-states'], 'a: { type: "bool", default: true }', '{ a: false }'),
    stored('leaf_zero', 'zero is a value, not an absence.',
        const ['int', 'six-states'], 'a: { type: "int", default: 5 }', '{ a: 0 }'),
    stored('leaf_empty_string', 'The empty string is a value, not an absence.',
        const ['string', 'six-states', 'empty'], 'a: { type: "string", default: "fb" }',
        '{ a: "" }'),
    stored('leaf_present_beats_default',
        'A present value wins over the default, even when it resolves to empty.',
        const ['default', 'empty-value'],
        'a: { type: "string", env: { allowed: true }, default: "fb" }',
        '{ a: "\${V}" }', layerValues: valueLayers(environ: {'V': ''})),
    stored('leaf_absent_parent_not_created',
        'A default below an absent object does not create the parent.',
        const ['default', 'absent'],
        'nested: { type: "object", children: { inner: { type: "int", default: 7 } } }',
        '{}'),
    stored('leaf_null_inside_array', 'An explicit null item stays null.',
        const ['null', 'array'],
        'tags: { type: "array", children: { type: "string" } }', '{ tags: [null, "a"] }'),
    stored('leaf_null_under_dynamic_key',
        'An explicit null under a dynamic key stays null.', const ['null', 'dynamic'],
        'd: { type: "object", additional_children: { type: "string" } }',
        '{ d: { k: null } }'),
    materialized('leaf_absent_with_default',
        'An absent field takes the descriptor default.', const ['default'],
        'a: { type: "string", default: "fb" }', '{}',
        tObj({'a': tStr('fb')}), '/a'),
    materialized('leaf_default_zero', 'A zero default is applied to an absent field.',
        const ['default', 'int'], 'a: { type: "int", default: 0 }', '{}',
        tObj({'a': tInt('0')}), '/a'),
    materialized('leaf_default_false', 'A false default is applied to an absent field.',
        const ['default', 'bool'], 'a: { type: "bool", default: false }', '{}',
        tObj({'a': tBool(false)}), '/a'),
    materialized('leaf_default_empty_string',
        'An empty-string default is applied and stays visible.', const ['default', 'empty'],
        'a: { type: "string", default: "" }', '{}',
        tObj({'a': tStr('')}), '/a'),
    materialized('leaf_default_null', 'A null default is applied to an absent field.',
        const ['default', 'null'], 'a: { type: "string", nullable: true, default: null }',
        '{}', tObj({'a': tNull()}), '/a'),
    materialized('leaf_present_empty_parent_fills_child',
        'An empty present object gets its child default.', const ['default', 'nested'],
        'nested: { type: "object", children: { inner: { type: "int", default: 7 } } }',
        '{ nested: {} }',
        tObj({'nested': tObj({'inner': tInt('7')})}), '/nested/inner'),
    _effective('leaf_default_containing_placeholder',
        'A default that is itself a placeholder is resolved.',
        const ['default', 'inline-default'],
        descriptor: singleField('a: { type: "string", env: { allowed: true }, default: "\${DEF}" }'),
        config: '{}',
        layers: valueLayers(environ: {'DEF': 'from-default'})),
    _effective('leaf_default_placeholder_unset',
        'An unresolved default placeholder yields the empty string.',
        const ['default', 'empty'],
        descriptor: singleField('a: { type: "string", env: { allowed: true }, default: "\${DEF}" }'),
        config: '{}',
        layers: valueLayers()),
  ];
}

List<CorpusCase> _effectiveAtCases() {
  const descriptor = '{ descriptor_version: "1.0", root: { type: "object", children: {'
      ' a: { type: "string", default: "fb" },'
      ' plain: { type: "string" },'
      ' templated: { type: "string", env: { allowed: true } },'
      ' n: { type: "int", default: 0 },'
      ' z: { type: "string", nullable: true, default: null } } } }';

  CorpusCase at(String id, String description, List<String> classes, String pointer,
          Object? stored, Map<String, Object?> layerValues, {String path = '/x'}) =>
      _effective(id, description, classes,
          descriptor: descriptor,
          config: '{}',
          layers: layerValues,
          query: {
            'op': 'effective_at',
            'pointer': pointer,
            'stored': stored,
            'path': path,
          });

  return [
    at('at_missing_with_default', 'MISSING with a defaulted node yields the default.',
        const ['missing', 'default'], '/a', 'MISSING', valueLayers()),
    at('at_missing_without_default', 'MISSING with no default stays MISSING.',
        const ['missing'], '/plain', 'MISSING', valueLayers()),
    at('at_missing_null_default', 'A null default is returned for MISSING.',
        const ['missing', 'null'], '/z', 'MISSING', valueLayers()),
    at('at_absent_pointer_missing', 'A pointer the descriptor does not declare is MISSING.',
        const ['missing', 'undeclared'], '/nope', 'MISSING', valueLayers()),
    at('at_value_null', 'An explicit null is returned as null, not defaulted.',
        const ['null', 'six-states'], '/a', null, valueLayers()),
    at('at_value_false', 'false is returned as false.', const ['bool', 'six-states'],
        '/n', false, valueLayers()),
    at('at_value_zero', 'zero is returned as zero.', const ['int', 'six-states'],
        '/n', 0, valueLayers()),
    at('at_value_empty_string', 'The empty string is returned as itself.',
        const ['string', 'empty', 'six-states'], '/a', '', valueLayers()),
    at('at_value_placeholder', 'A placeholder value resolves.',
        const ['placeholder'], '/templated', '\${V}', valueLayers(environ: {'V': 'x'})),
    at('at_root_path_default', 'The root path is recorded under the key "/".',
        const ['default', 'paths'], '/a', 'MISSING', valueLayers(), path: ''),
  ];
}

List<CorpusCase> _unionArrayCases() => [
      _effective('union_disjoint_key_int',
          'A key declared by one alternative resolves through it.',
          const ['union'],
          descriptor: disjointUnionDescriptor,
          config: '{ items: { a: { port: \${P} } } }',
          layers: valueLayers(environ: {'P': '9'})),
      _effective('union_disjoint_key_string',
          'A key only another alternative declares resolves through that one.',
          const ['union'],
          descriptor: disjointUnionDescriptor,
          config: '{ items: { a: { label: "\${L}" } } }',
          layers: valueLayers(environ: {'L': 'x'})),
      _effective('union_plain_value_by_shape',
          'A stored value selects the alternative whose type fits it.',
          const ['union'],
          descriptor: unionDescriptor,
          config: '{ items: { a: { port: 9 } } }',
          layers: valueLayers()),
      _effective('union_plain_string_value',
          'A string value is resolved by the string alternative.',
          const ['union'],
          descriptor: unionDescriptor,
          config: '{ items: { a: { port: "text" } } }',
          layers: valueLayers()),
      _effective(
        'union_bare_placeholder_text_value',
        'A bare placeholder whose resolved text fits a later alternative.',
        const ['union', 'placeholder', 'A26'],
        descriptor: unionDescriptor,
        config: '{ items: { a: { port: \${P} } } }',
        layers: valueLayers(environ: {'P': 'text'}),
        divergence: _corrected(
          id: 'A26',
          report: 'A26',
          note: 'A bare placeholder has no type before resolution, so the baseline takes the first '
              'alternative that declares the key, converts "text" to int, fails, and reports '
              'env_conversion with a null value — for a document the descriptor '
              'permits through its second alternative. The Dart implementation resolves the '
              'placeholder against each candidate alternative in declaration order and keeps the '
              'first one that succeeds.',
          corrected: {
            'ok': true,
            'effective': tObj({
              'items': tObj({
                'a': tObj({'port': tStr('text')}),
              }),
            }),
            'issues': <Object?>[],
            'provenance': tObj({
              '/items/a/port': tObj({
                'kind': tStr('environment'),
                'variable': tStr('P'),
              }),
            }),
            'inputsUnchanged': true,
          },
        ),
      ),
      _effective(
        'union_quoted_placeholder_numeric_text',
        'A quoted placeholder whose resolved text fits an earlier alternative.',
        const ['union', 'placeholder', 'A26'],
        descriptor: unionDescriptor,
        config: '{ items: { a: { port: "\${P}" } } }',
        layers: valueLayers(environ: {'P': '9'}),
        divergence: _corrected(
          id: 'A26',
          report: 'A26',
          note: 'The baseline classifies the stored text "\${P}" as a string and therefore '
              'picks the string alternative, so the same document means 9 when written bare '
              'and "9" when written quoted. The Dart implementation resolves the '
              'placeholder first and then keeps the first alternative the resolved value fits.',
          corrected: {
            'ok': true,
            'effective': tObj({
              'items': tObj({
                'a': tObj({'port': tInt('9')}),
              }),
            }),
            'issues': <Object?>[],
            'provenance': tObj({
              '/items/a/port': tObj({
                'kind': tStr('environment'),
                'variable': tStr('P'),
              }),
            }),
            'inputsUnchanged': true,
          },
        ),
      ),
      _effective(
        'heterogeneous_array_positional_resolution',
        'Each position of a heterogeneous array resolves with its own alternative.',
        const ['array', 'union', 'A24'],
        descriptor: heterogeneousDescriptor,
        config: '{ steps: [ { a: "\${A}" }, { b: "x" }, 3 ] }',
        layers: valueLayers(environ: {'A': '1'}),
        divergence: _corrected(
          id: 'A24',
          report: 'A24',
          note: 'Resolution is positional in the baseline and correct here; default filling is '
              'not, so the baseline also materializes the first alternative\'s default into the '
              'second item (see heterogeneous_array_defaults_are_positional).',
          corrected: {
            'ok': true,
            'effective': tObj({
              'steps': tArr([
                tObj({'a': tStr('\${A}')}),
                tObj({'b': tStr('x')}),
                tInt('3'),
              ]),
            }),
            'issues': <Object?>[],
            'provenance': tObj({
              '/steps/0/a': prov(kind: 'file'),
              '/steps/1/b': prov(kind: 'file'),
              '/steps/2': prov(kind: 'file'),
            }),
            'inputsUnchanged': true,
          },
        ),
      ),
      _effective('heterogeneous_array_index_clamped',
          'An item beyond the last alternative uses the last one.',
          const ['array', 'union'],
          descriptor: heterogeneousDescriptor,
          config: '{ steps: [ 1, 2, 3, 4, 5 ] }',
          layers: valueLayers()),
      _effective(
        'heterogeneous_array_defaults_are_positional',
        'Defaults below a heterogeneous array come from the alternative of that position.',
        const ['array', 'union', 'default', 'A24'],
        descriptor: heterogeneousDescriptor,
        config: '{ steps: [ {}, {} ] }',
        layers: valueLayers(),
        divergence: _corrected(
          id: 'A24',
          report: 'A24',
          note: 'The baseline has two helpers for the same question and they disagree: resolution '
              'uses the alternative at the item index, while default filling '
              'always uses alternative 0. Both items therefore receive the first '
              'alternative\'s default, and the provenance names a field of the wrong '
              'alternative. The Dart implementation uses the positional alternative in both places.',
          corrected: {
            'ok': true,
            'effective': tObj({
              'steps': tArr([
                tObj({'a': tStr('A')}),
                tObj({'b': tStr('B')}),
              ]),
            }),
            'issues': <Object?>[],
            'provenance': tObj({
              '/steps/0/a': prov(kind: 'default'),
              '/steps/1/b': prov(kind: 'default'),
            }),
            'inputsUnchanged': true,
          },
        ),
      ),
      _effective('array_of_objects_placeholders',
          'Placeholders inside array item objects resolve.', const ['array', 'nested'],
          descriptor: '{ descriptor_version: "1.0", root: { type: "object", children: {'
              ' list: { type: "array", children: { type: "object", children: {'
              ' v: { type: "string", env: { allowed: true } } } } } } } }',
          config: '{ list: [ { v: "\${A}" }, { v: "plain" } ] }',
          layers: valueLayers(environ: {'A': '1'})),
    ];

List<CorpusCase> _provenanceCases() => [
      _effective('prov_file_for_stored_values',
          'A stored value is provenanced as file.', const ['provenance', 'file'],
          descriptor: resolverDescriptor,
          config: '{ plain: "x", number: 5 }',
          layers: valueLayers()),
      _effective('prov_environment_for_resolved',
          'A resolved value names its variable.', const ['provenance', 'environment'],
          descriptor: resolverDescriptor,
          config: '{ templated: "\${V}" }',
          layers: valueLayers(environ: {'V': 'x'})),
      _effective('prov_override_source',
          'An override is named as the source.', const ['provenance', 'override'],
          descriptor: resolverDescriptor,
          config: '{ templated: "\${V}" }',
          layers: valueLayers(overrides: {'V': 'x'})),
      _effective(
        'prov_default_for_absent',
        'A materialized default is provenanced as default.',
        const ['provenance', 'default', 'A27'],
        descriptor: singleField('a: { type: "string", default: "fb" }'),
        config: '{}',
        layers: valueLayers(),
        divergence: _corrected(
          id: 'A27',
          report: 'A27',
          note: 'build_effective records the materialized default and then overwrites it '
              'with "file" while walking the filled tree, so the snapshot claims a value the '
              'document never stored. effective_at reports the same field as "default"; the Dart '
              'implementation agrees with that one.',
          corrected: {
            'ok': true,
            'effective': tObj({'a': tStr('fb')}),
            'issues': <Object?>[],
            'provenance': tObj({'/a': prov(kind: 'default')}),
            'inputsUnchanged': true,
          },
        ),
      ),
      _effective('prov_mixed_document',
          'One document mixes file, environment and default provenance.',
          const ['provenance'],
          descriptor: resolverDescriptor,
          config: '{ plain: "p", templated: "\${V}", not_allowed: "lit" }',
          layers: valueLayers(environ: {'V': 'x'})),
      _effective('prov_escaped_key_path',
          'A key containing a slash is escaped in the provenance path.',
          const ['provenance', 'paths'],
          descriptor: '{ descriptor_version: "1.0", root: { type: "object",'
              ' additional_children: { type: "string", env: { allowed: true } } } }',
          config: '{ "with/slash": "\${V}", "with~tilde": "\${W}" }',
          layers: valueLayers(environ: {'V': '1', 'W': '2'})),
      _effective('prov_empty_path_for_root',
          'The root itself carries no provenance entry.', const ['provenance', 'paths'],
          descriptor: '{ descriptor_version: "1.0", root: { type: "string" } }',
          config: '"plain"',
          layers: valueLayers()),
      _effective('prov_scalar_root_default',
          'A defaulted scalar root is recorded under "/".',
          const ['provenance', 'default'],
          descriptor: '{ descriptor_version: "1.0", root: { type: "string", default: "roott" } }',
          config: 'null',
          layers: valueLayers()),
      _effective('prov_secret_value_not_included',
          'Provenance names the variable, never its value.', const ['provenance', 'secret'],
          descriptor: '{ descriptor_version: "1.0", root: { type: "object", children: {'
              ' key: { type: "string", env: { allowed: true }, secret: true } } } }',
          config: '{ key: "\${API}" }',
          layers: valueLayers(environ: {'API': 'super-secret-value'})),
    ];

List<CorpusCase> _governedKeyCases() => [
      _effective(
        'governed_key_enum_allowed',
        'A declared key_enum member is governed by additional_children.',
        const ['keys', 'key-enum', 'A27'],
        descriptor: keyEnumDescriptor,
        config: '{ s: { ok: {} } }',
        layers: valueLayers(),
        divergence: _corrected(
          id: 'A27',
          report: 'A27',
          note: 'The governed key behaves the same in both implementations; the difference is '
              'only the provenance of the default materialized under it (see '
              'prov_default_for_absent).',
          corrected: {
            'ok': true,
            'effective': tObj({
              's': tObj({'ok': tObj({'x': tStr('X')})}),
            }),
            'issues': <Object?>[],
            'provenance': tObj({
              '/s/ok/x': prov(kind: 'default'),
            }),
            'inputsUnchanged': true,
          },
        ),
      ),
      _effective(
        'governed_key_enum_forbidden_gets_no_default',
        'A key outside key_enum is not governed, so no default is materialized for it.',
        const ['keys', 'key-enum', 'A25'],
        descriptor: keyEnumDescriptor,
        config: '{ s: { forbidden: {} } }',
        layers: valueLayers(),
        divergence: _corrected(
          id: 'A25',
          report: 'A25',
          note: 'The baseline implements "which keys does this object govern" three times with '
              'three answers. Default filling ignores key_enum, so a key the '
              'descriptor forbids receives a materialized default and provenance that claims it '
              'came from a default; node selection for resolution ignores key_pattern, so a '
              'key outside the pattern is still substituted. The Dart implementation applies the '
              'same governed-key rule in both places.',
          corrected: {
            'ok': true,
            'effective': tObj({
              's': tObj({'forbidden': tObj({})}),
            }),
            'issues': <Object?>[],
            'provenance': tObj({
              '/s/forbidden': prov(kind: 'file'),
            }),
            'inputsUnchanged': true,
          },
        ),
      ),
      _effective(
        'governed_key_pattern_mismatch_not_resolved',
        'A key that fails key_pattern is not governed, so its placeholder stays literal.',
        const ['keys', 'key-pattern', 'A25'],
        descriptor: keyPatternDescriptor,
        config: '{ s: { badA: "\${V}" } }',
        layers: valueLayers(environ: {'V': 'x'}),
        divergence: _corrected(
          id: 'A25',
          report: 'A25',
          note: 'Same item as governed_key_enum_forbidden_gets_no_default: resolution ignores '
              'key_pattern, so a key the descriptor does not govern has its '
              'placeholder substituted while node lookup and validation both refuse the '
              'key.',
          corrected: {
            'ok': true,
            'effective': tObj({
              's': tObj({'badA': tStr('\${V}')}),
            }),
            'issues': <Object?>[],
            'provenance': tObj({
              '/s/badA': prov(kind: 'file'),
            }),
            'inputsUnchanged': true,
          },
        ),
      ),
      _effective('governed_key_pattern_match_resolved',
          'A key that matches key_pattern is governed and resolved.',
          const ['keys', 'key-pattern'],
          descriptor: keyPatternDescriptor, config: '{ s: { okA: "\${V}" } }',
          layers: valueLayers(environ: {'V': 'x'})),
    ];

/// The complete resolver catalog.
List<CorpusCase> resolverCases() => [
      ..._lookupCases(),
      ..._textCases(),
      ..._conversionCases(),
      ..._allowedCases(),
      ..._leafStateCases(),
      ..._effectiveAtCases(),
      ..._unionArrayCases(),
      ..._provenanceCases(),
      ..._governedKeyCases(),
    ];
