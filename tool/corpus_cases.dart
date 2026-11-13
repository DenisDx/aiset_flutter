/// Corpus case catalog for `tool/generate_corpus.dart`.
///
/// Every entry names an input document plus, where relevant, one
/// query or one `apply_*` operation, and is fed to the Python baseline by
/// `tool/python/corpus_driver.py`. The catalog chooses which behavior the
/// corpus pins; the expectations themselves are
/// produced by executing the baseline, never written here.
///
/// Case ids are stable fixture identifiers: they become file
/// names under `fixtures/python_compat/<area>/`. Keep them unique.
library;

/// What the generator sends to the driver for one case.
class CorpusCase {
  /// Creates one catalog entry.
  const CorpusCase({
    required this.id,
    required this.description,
    required this.classes,
    required this.kind,
    required this.input,
    this.query,
    this.operation,
    this.payload,
    this.divergence,
  });

  /// Stable identifier.
  final String id;

  /// One-line human description of what the case pins.
  final String description;

  /// Behavior tags (append-marker, comment-ownership, astral, ...).
  final List<String> classes;

  /// `parse`, `query` or `operation`.
  final String kind;

  /// The document text fed to the baseline parser.
  final String input;

  /// Query payload for `kind == 'query'`.
  final Map<String, Object?>? query;

  /// Operation payload for `kind == 'operation'`.
  final Map<String, Object?>? operation;

  /// Extra job fields a case carries besides `input`, `query` and
  /// `operation`: the descriptor areas use `mode`, `strict`,
  /// `typedefSources` and `fragments`. The same fields are copied into the
  /// fixture so a test can replay the case without the catalog.
  final Map<String, Object?>? payload;

  /// Generator-side note that the baseline output is a known
  /// defect that the Dart implementation intentionally corrects
  /// (`SPEC.md` amendment 24, `SPEC_.md` amendment 38).
  ///
  /// The map is copied verbatim into the fixture, minus `correctedOutput`,
  /// which the generator moves into `expected.output` so the corpus
  /// test asserts the corrected behavior through the same path
  /// as every other case. The generator records the baseline's observed result
  /// in the fixture's `baselineEvidence` field, and the case is
  /// never skipped.
  ///
  /// Required keys: `id` (the registered divergence), `report` (the item in
  /// the handoff notes for the Python team), `note` and
  /// `correctedOutput`.
  final Map<String, Object?>? divergence;

  /// The job entry consumed by `tool/python/corpus_driver.py`.
  Map<String, Object?> toJobEntry() => {
        'id': id,
        'kind': kind,
        'input': input,
        if (query != null) 'query': query,
        if (operation != null) 'operation': operation,
        if (payload != null) ...payload!,
      };
}

/// Strips the newline that follows an opening `'''` so multi-line raw
/// document literals read like the file they represent.
String _doc(String raw) => raw.startsWith('\n') ? raw.substring(1) : raw;

// -- shared documents ------------------------------------------------------

/// The SPEC comment-classification document (same text as the preservation
/// fixture `comment_ownership`).
final String commentOwnership = _doc('''
// Document comment (belongs to the whole document).
{
  // Leading comment for element1.
  element1: 124, // Trailing comment for element1.
  element2: { // Trailing comment for element2.
    // Leading comment for element3.
    element3: 123, // Trailing comment for element3.
    // Leading comment for element4.
    element4: 111 // Trailing comment for element4.
    // Block-end comment for element2 (kept before the closing brace).
  } // Trailing comment for element2's closing brace.
}
''');

/// The mixed-type document of the baseline corpus.
final String mixedTypes = _doc('''
// Mixed-type fixture with quotes, trailing commas and templates.
{
  // A quoted string with a placeholder and escapes.
  'single quoted': "value with \${VAR:-default} and \\"escaped\\" quotes",
  number_int: 42,
  number_negative: -7,
  number_float: 1.5,
  flag_true: true,
  flag_false: false,
  explicit_null: null,
  // An unquoted whole-value template.
  port: \${PORT:-8080},
  nested: {
    // Nested array with comments.
    list: [
      // First item.
      1,
      2, // Second item.
      {
        // Item object.
        deep: 'yes',
      },
    ],
    /* block comment inside an object */
    quoted_key: 1,
    "dotted.key": 2,
    "with/slash": 3,
    "with~tilde": 4,
    "0": "numeric object key",
  },
}
''');

/// Compact containers on one line, plus empty ones.
final String singleLineObjects = _doc('''
{
  compact: { a: 1, b: 2 },
  empty_object: {},
  empty_array: [],
  single_array: [1, 2, 3],
}
''');

/// A document whose astral-plane key makes UTF-8 byte offsets and
/// UTF-16 code-unit offsets disagree for every node after it.
final String astralDoc = _doc('''
{
  "rocket \u{1F680}": "start",
  list: [
    "a",
    "b",
  ],
  tail: 1,
}
''');

final String crlfDoc = '{\r\n  a: 1,\r\n  b: {\r\n    c: 2,\r\n  },\r\n}\r\n';

final String bomDoc = '\uFEFF{\n  a: 1,\n}\n';

final String noFinalNewline = '{\n  a: 1,\n  b: 2\n}';

/// Multiline array whose items carry leading and trailing comments.
final String commentedList =
    '{\n  list: [\n    // first\n    "a",\n    "b", // second\n    "c",\n  ],\n}\n';

/// Object with a commented member followed by another member.
final String commentedMembers =
    '{\n  // lead a\n  a: 1, // trail a\n  b: 2,\n  c: 3,\n}\n';

/// Array whose opening bracket owns a same-line comment.
final String openingCommentList = '{\n  list: [ // open\n    "a",\n    "b",\n  ],\n}\n';

/// Array with a block-end comment before its closing bracket.
final String blockEndList = '{\n  list: [\n    1,\n    2\n    // end\n  ],\n}\n';

/// Array of nested multiline objects, for moves across nesting levels.
final String nestedObjectList = _doc('''
{
  workers: [
    {
      id: "web", // worker id
      ports: [
        8080,
        8081,
      ],
    },
    {
      id: "cache",
    },
  ],
}
''');

// -- parse acceptance --------------------------------------------------------

List<CorpusCase> _parseAcceptCases() => [
      CorpusCase(
        id: 'empty_object',
        description: 'An empty object root.',
        classes: const ['empty', 'object'],
        kind: 'parse',
        input: '{}',
      ),
      CorpusCase(
        id: 'empty_array',
        description: 'An empty array root.',
        classes: const ['empty', 'array'],
        kind: 'parse',
        input: '[]',
      ),
      CorpusCase(
        id: 'string_root',
        description: 'A quoted string as the whole document.',
        classes: const ['scalar-root', 'string'],
        kind: 'parse',
        input: r'"just a string"',
      ),
      CorpusCase(
        id: 'number_root',
        description: 'A number as the whole document.',
        classes: const ['scalar-root', 'number'],
        kind: 'parse',
        input: '-12.5e2',
      ),
      CorpusCase(
        id: 'template_root',
        description: 'A bare placeholder as the whole document.',
        classes: const ['scalar-root', 'placeholder'],
        kind: 'parse',
        input: r'${WHOLE_FILE}',
      ),
      CorpusCase(
        id: 'nested_empty_containers',
        description: 'Empty containers nested inside each other.',
        classes: const ['empty', 'nested'],
        kind: 'parse',
        input: '{\n  o: {},\n  a: [],\n  deep: { x: [ {}, [] ] },\n}\n',
      ),
      CorpusCase(
        id: 'document_comments_only_root',
        description: 'Document comments before an empty root object.',
        classes: const ['comments', 'document-comment', 'empty'],
        kind: 'parse',
        input: '// header\n{}\n',
      ),
      CorpusCase(
        id: 'inline_object_no_trailing_comma',
        description: 'Inline object whose last member has no comma.',
        classes: const ['inline', 'no-trailing-comma'],
        kind: 'parse',
        input: '{ a: 1, b: 2 }',
      ),
      CorpusCase(
        id: 'members_without_commas',
        description:
            'The baseline grammar needs no separator between members on separate lines.',
        classes: const ['no-comma', 'grammar'],
        kind: 'parse',
        input: '{\n  a: 1\n  b: 2\n}\n',
      ),
      CorpusCase(
        id: 'quoted_keys_both_styles',
        description: 'Single- and double-quoted keys side by side.',
        classes: const ['quoted-key', 'single-quote'],
        kind: 'parse',
        input: '{\n  \'one\': 1,\n  "two": 2,\n}\n',
      ),
      CorpusCase(
        id: 'special_unquoted_keys',
        description: 'Unquoted keys built from the baseline key character set.',
        classes: const ['key-chars', 'dotted-key', 'dash-key', 'dollar-key'],
        kind: 'parse',
        input: '{\n  a.b: 1,\n  a-b: 2,\n  \$c: 3,\n  _d: 4,\n  E1: 5,\n}\n',
      ),
      CorpusCase(
        id: 'empty_and_numeric_keys',
        description: 'Empty-string key and a numeric object key.',
        classes: const ['empty-key', 'numeric-key'],
        kind: 'parse',
        input: '{\n  "": 0,\n  "0": 1,\n  1: 2,\n}\n',
      ),
      CorpusCase(
        id: 'escaped_strings',
        description: 'Escape forms accepted by the baseline string scanner.',
        classes: const ['escapes', 'string'],
        kind: 'parse',
        input:
            '{\n  q: "a\\"b\'c",\n  s: \'x\\\'y\',\n  bs: "back\\\\slash",\n  solid: "a\\/b",\n  uni: "\\u00e9\\u0041",\n  hex: "\\x41\\x7a",\n  ctrl: "\\n\\t\\r\\b\\f\\v\\0",\n}\n',
      ),
      CorpusCase(
        id: 'astral_and_surrogate_escapes',
        description: 'Astral characters written raw and as surrogate-pair escapes.',
        classes: const ['astral', 'unicode', 'escapes'],
        kind: 'parse',
        input: '{\n  raw: "\u{1F680}\u{1F1FA}\u{1F1F8}",\n  escaped: "\\ud83d\\ude00",\n  bmp: "\u00fc\u00e9\u4e2d\u6587",\n}\n',
      ),
      CorpusCase(
        id: 'number_forms',
        description: 'Hex, leading-dot, trailing-dot, exponent and sign forms.',
        classes: const ['number', 'hex', 'float', 'exponent'],
        kind: 'parse',
        input: '{\n  hex: 0xFF,\n  negHex: -0x1a,\n  plusHex: +0x10,\n  plus: +5,\n  leadDot: .5,\n  trailDot: 5.,\n  exp: 1e3,\n  expPlus: 1E+3,\n  negFloat: -0.25,\n  leadingZero: 08,\n}\n',
      ),
      CorpusCase(
        id: 'huge_integers',
        description: 'Integers beyond the 64-bit range stay exact.',
        classes: const ['number', 'big-int', 'hex'],
        kind: 'parse',
        input: '{\n  big: 123456789012345678901234567890,\n  bigHex: 0xdeadbeefcafebabe1234,\n  negBig: -98765432109876543210,\n}\n',
      ),
      CorpusCase(
        id: 'overflowing_float',
        description: 'A float literal that overflows to infinity.',
        classes: const ['number', 'float', 'overflow'],
        kind: 'parse',
        input: '{\n  huge: 1e400,\n  tiny: 1e-400,\n}\n',
      ),
      CorpusCase(
        id: 'placeholder_forms',
        description: 'Bare and embedded placeholders, with and without defaults.',
        classes: const ['placeholder', 'template'],
        kind: 'parse',
        input:
            '{\n  bare: \${A},\n  emptyDefault: \${B:-},\n  withDefault: \${C:-x y},\n  embedded: "pre \${D} post \${E:-f}",\n  list: [\${F}, "\${G:-h}"],\n}\n',
      ),
      CorpusCase(
        id: 'whitespace_forms',
        description: 'The full baseline whitespace set, including NBSP, BOM and VT.',
        classes: const ['whitespace', 'nbsp', 'bom', 'vertical-tab'],
        kind: 'parse',
        input: '{\u00a0a:\u00a01,\u000b\u000cb:\t2\r\n}\uFEFF\n',
      ),
      CorpusCase(
        id: 'block_comments_everywhere',
        description: 'Block comments in every trivia slot.',
        classes: const ['comments', 'block-comment'],
        kind: 'parse',
        input: '{\n  /* doc-ish */\n  /* mid */ a: /* after colon */ 1, /* trail */\n  /* lead b */ b: 2, /* trail b */\n}\n',
      ),
      CorpusCase(
        id: 'multiline_block_comment',
        description: 'A block comment spanning several lines.',
        classes: const ['comments', 'block-comment', 'multiline'],
        kind: 'parse',
        input: '{\n  /*\n   * first\n   * second\n   */\n  a: 1,\n}\n',
      ),
      CorpusCase(
        id: 'empty_string_values',
        description: 'Empty strings and an empty default are distinct from absent.',
        classes: const ['string', 'empty'],
        kind: 'parse',
        input: '{\n  e: "",\n  q: \'\',\n  n: 0,\n  f: false,\n  z: null,\n}\n',
      ),
      CorpusCase(
        id: 'deep_nesting',
        description: 'Five levels of alternating containers.',
        classes: const ['nested', 'array', 'object'],
        kind: 'parse',
        input: '{\n  l1: {\n    l2: [\n      {\n        l3: [\n          { l4: "leaf" },\n        ],\n      },\n    ],\n  },\n}\n',
      ),
      CorpusCase(
        id: 'array_of_arrays',
        description: 'Nested arrays with trailing commas at both levels.',
        classes: const ['array', 'nested', 'trailing-commas'],
        kind: 'parse',
        input: '{\n  m: [\n    [1, 2,],\n    [3,],\n  ],\n}\n',
      ),
      CorpusCase(
        id: 'comment_before_close_only',
        description: 'A container holding nothing but a block-end comment.',
        classes: const ['comments', 'block-end', 'empty'],
        kind: 'parse',
        input: '{\n  o: {\n    // nothing here\n  },\n  a: [\n    // nothing here\n  ],\n}\n',
      ),
      CorpusCase(
        id: 'astral_document',
        description: 'The astral-plane document used by the splice cases.',
        classes: const ['astral', 'unicode'],
        kind: 'parse',
        input: astralDoc,
      ),
      CorpusCase(
        id: 'crlf_document',
        description: 'CRLF line endings throughout.',
        classes: const ['crlf'],
        kind: 'parse',
        input: crlfDoc,
      ),
      CorpusCase(
        id: 'bom_document',
        description: 'A leading byte-order mark, which the baseline treats as whitespace.',
        classes: const ['bom'],
        kind: 'parse',
        input: bomDoc,
      ),
      CorpusCase(
        id: 'no_final_newline_document',
        description: 'Document without a trailing newline.',
        classes: const ['no-final-newline'],
        kind: 'parse',
        input: noFinalNewline,
      ),
    ];

// -- parse rejection ---------------------------------------------------------

List<CorpusCase> _parseRejectCases() => [
      CorpusCase(
        id: 'empty_input',
        description: 'An empty document has no value to parse.',
        classes: const ['empty-input'],
        kind: 'parse',
        input: '',
      ),
      CorpusCase(
        id: 'whitespace_only',
        description: 'Whitespace only.',
        classes: const ['empty-input', 'whitespace'],
        kind: 'parse',
        input: '  \n\t \n',
      ),
      CorpusCase(
        id: 'comment_only',
        description: 'A comment but no value.',
        classes: const ['empty-input', 'comments'],
        kind: 'parse',
        input: '// only a comment\n',
      ),
      CorpusCase(
        id: 'trailing_content_object',
        description: 'A second value after the root object.',
        classes: const ['trailing-content'],
        kind: 'parse',
        input: '{\n  a: 1,\n}\n{ b: 2 }',
      ),
      CorpusCase(
        id: 'trailing_content_scalar',
        description: 'A second token after a scalar root.',
        classes: const ['trailing-content'],
        kind: 'parse',
        input: '42 43',
      ),
      CorpusCase(
        id: 'duplicate_key',
        description: 'The same key twice.',
        classes: const ['duplicate-key'],
        kind: 'parse',
        input: '{\n  a: 1,\n  a: 2,\n}\n',
      ),
      CorpusCase(
        id: 'duplicate_key_quoting_styles',
        description: 'A quoted and an unquoted spelling of one key collide.',
        classes: const ['duplicate-key', 'quoted-key'],
        kind: 'parse',
        input: '{"a": 1, a: 2}',
      ),
      CorpusCase(
        id: 'missing_colon',
        description: 'A key with no colon after it.',
        classes: const ['missing-colon'],
        kind: 'parse',
        input: '{ a }',
      ),
      CorpusCase(
        id: 'space_before_colon',
        description: 'The grammar allows no gap between key and colon.',
        classes: const ['missing-colon', 'whitespace'],
        kind: 'parse',
        input: '{ a : 1 }',
      ),
      CorpusCase(
        id: 'comment_before_colon',
        description: 'A comment between key and colon.',
        classes: const ['missing-colon', 'comments'],
        kind: 'parse',
        input: '{ a/* c */: 1 }',
      ),
      CorpusCase(
        id: 'space_before_comma',
        description: 'The grammar allows no gap between value and comma.',
        classes: const ['comma-placement'],
        kind: 'parse',
        input: '{ a: 1 , b: 2 }',
      ),
      CorpusCase(
        id: 'comment_before_comma',
        description: 'A comment between value and comma.',
        classes: const ['comma-placement', 'comments'],
        kind: 'parse',
        input: '{ a: 1/* c */, b: 2 }',
      ),
      CorpusCase(
        id: 'unterminated_string',
        description: 'A string that never closes.',
        classes: const ['unterminated', 'string'],
        kind: 'parse',
        input: '{ a: "oops }',
      ),
      CorpusCase(
        id: 'unescaped_line_break_in_string',
        description: 'A raw line break inside a string.',
        classes: const ['string', 'line-break'],
        kind: 'parse',
        input: '{ a: "first\nsecond" }',
      ),
      CorpusCase(
        id: 'unterminated_block_comment',
        description: 'A block comment without its terminator.',
        classes: const ['unterminated', 'comments'],
        kind: 'parse',
        input: '{ a: 1 /* never closed\n}\n',
      ),
      CorpusCase(
        id: 'dangling_escape',
        description: 'A backslash at end of input.',
        classes: const ['escapes', 'truncated'],
        kind: 'parse',
        input: '{ a: "x\\',
      ),
      CorpusCase(
        id: 'unsupported_escape',
        description: 'An escape the baseline does not define.',
        classes: const ['escapes'],
        kind: 'parse',
        input: r'{ a: "\q" }',
      ),
      CorpusCase(
        id: 'malformed_unicode_escape_short',
        description: 'A \\u escape with fewer than four hex digits.',
        classes: const ['escapes', 'unicode'],
        kind: 'parse',
        input: r'{ a: "\u12" }',
      ),
      CorpusCase(
        id: 'malformed_unicode_escape_digits',
        description: 'A \\u escape with non-hex digits.',
        classes: const ['escapes', 'unicode'],
        kind: 'parse',
        input: r'{ a: "\uZZZZ" }',
      ),
      CorpusCase(
        id: 'malformed_hex_escape',
        description: 'A \\x escape with non-hex digits.',
        classes: const ['escapes'],
        kind: 'parse',
        input: r'{ a: "\xzz" }',
      ),
      CorpusCase(
        id: 'truncated_after_comma',
        description: 'A comma where the next key is expected.',
        classes: const ['truncated'],
        kind: 'parse',
        input: '{a: 1,',
      ),
      CorpusCase(
        id: 'truncated_object_open',
        description: 'An object that never closes.',
        classes: const ['truncated', 'unterminated'],
        kind: 'parse',
        input: '{',
      ),
      CorpusCase(
        id: 'truncated_array_item',
        description: 'An array whose last item is cut off.',
        classes: const ['truncated', 'unterminated'],
        kind: 'parse',
        input: '[1,',
      ),
      CorpusCase(
        id: 'truncated_value_after_colon',
        description: 'A colon with nothing after it.',
        classes: const ['truncated'],
        kind: 'parse',
        input: '{ a: ',
      ),
      CorpusCase(
        id: 'mismatched_close_bracket',
        description: 'An array bracket closing an object.',
        classes: const ['mismatched-bracket'],
        kind: 'parse',
        input: '{ a: 1 ]',
      ),
      CorpusCase(
        id: 'colon_without_key',
        description: 'A colon where a key is required.',
        classes: const ['missing-key'],
        kind: 'parse',
        input: '{ : 1 }',
      ),
      CorpusCase(
        id: 'missing_value_in_array',
        description: 'A leading comma in an array leaves a value position empty.',
        classes: const ['missing-value'],
        kind: 'parse',
        input: '[,1]',
      ),
      CorpusCase(
        id: 'literal_undefined',
        description: 'The JavaScript undefined literal is not a value here.',
        classes: const ['literal'],
        kind: 'parse',
        input: '{ a: undefined }',
      ),
      CorpusCase(
        id: 'literal_python_style',
        description: 'Python-style True/False spellings are rejected.',
        classes: const ['literal'],
        kind: 'parse',
        input: '{ a: True }',
      ),
      CorpusCase(
        id: 'number_nan',
        description: 'NaN is not portable and is rejected.',
        classes: const ['number', 'non-finite'],
        kind: 'parse',
        input: '{ a: NaN }',
      ),
      CorpusCase(
        id: 'number_infinity',
        description: 'Infinity is not portable and is rejected.',
        classes: const ['number', 'non-finite'],
        kind: 'parse',
        input: '{ a: Infinity }',
      ),
      CorpusCase(
        id: 'number_negative_infinity',
        description: 'Negative Infinity is rejected too.',
        classes: const ['number', 'non-finite'],
        kind: 'parse',
        input: '{ a: -Infinity }',
      ),
      CorpusCase(
        id: 'number_signed_nan',
        description: 'A sign in front of NaN matches the shape but is not portable.',
        classes: const ['number', 'non-finite'],
        kind: 'parse',
        input: '{ a: +NaN }',
      ),
      CorpusCase(
        id: 'number_two_dots',
        description: 'A malformed decimal.',
        classes: const ['number', 'invalid'],
        kind: 'parse',
        input: '{ a: 1.2.3 }',
      ),
      CorpusCase(
        id: 'number_bare_hex',
        description: 'A hex prefix with no digits.',
        classes: const ['number', 'invalid', 'hex'],
        kind: 'parse',
        input: '{ a: 0x }',
      ),
      CorpusCase(
        id: 'number_dangling_exponent',
        description: 'An exponent marker with no digits.',
        classes: const ['number', 'invalid'],
        kind: 'parse',
        input: '{ a: 1e }',
      ),
      CorpusCase(
        id: 'number_double_sign',
        description: 'Two signs are one invalid token.',
        classes: const ['number', 'invalid'],
        kind: 'parse',
        input: '{ a: --1 }',
      ),
      CorpusCase(
        id: 'number_underscore_grouping',
        description: 'Digit grouping is not JSON5 here.',
        classes: const ['number', 'invalid'],
        kind: 'parse',
        input: '{ a: 1_000 }',
      ),
      CorpusCase(
        id: 'template_dash_operator',
        description: 'The \${VAR-default} spelling is not supported.',
        classes: const ['placeholder', 'unsupported-token'],
        kind: 'parse',
        input: r'{ a: ${VAR-default} }',
      ),
      CorpusCase(
        id: 'template_bad_name',
        description: 'A placeholder name may not start with a digit.',
        classes: const ['placeholder', 'unsupported-token'],
        kind: 'parse',
        input: r'{ a: ${1X} }',
      ),
      CorpusCase(
        id: 'template_spaced_name',
        description: 'A placeholder name may not contain spaces.',
        classes: const ['placeholder', 'unsupported-token'],
        kind: 'parse',
        input: r'{ a: ${ A } }',
      ),
      CorpusCase(
        id: 'template_unterminated',
        description: 'A placeholder with no closing brace.',
        classes: const ['placeholder', 'unterminated'],
        kind: 'parse',
        input: r'{ a: ${VAR',
      ),
      CorpusCase(
        id: 'bare_slash_value',
        description: 'A comment marker glued to a literal is one bad token.',
        classes: const ['comments', 'invalid'],
        kind: 'parse',
        input: '{ a: 1/* c */ }',
      ),
    ];

// -- parsed values -----------------------------------------------------------

List<CorpusCase> _valueCases() {
  CorpusCase value(String id, String description, List<String> classes, String input,
          String op, String pointer) =>
      CorpusCase(
        id: id,
        description: description,
        classes: classes,
        kind: 'query',
        input: input,
        query: {'op': op, 'pointer': pointer},
      );

  return [
    value('stored_root_mixed', 'The whole mixed document as stored data.',
        const ['stored-value', 'object'], mixedTypes, 'stored_value', ''),
    value('stored_template', 'A bare placeholder stays explicit, never resolved.',
        const ['stored-value', 'placeholder'], mixedTypes, 'stored_value', '/port'),
    value('stored_template_in_string', 'A placeholder embedded in a string value.',
        const ['stored-value', 'placeholder', 'string'], mixedTypes, 'stored_value',
        '/single quoted'),
    value('stored_float_and_int', 'Number kinds survive the round trip.',
        const ['stored-value', 'number'], mixedTypes, 'stored_value', '/number_float'),
    value('stored_negative', 'A negative integer.', const ['stored-value', 'number'],
        mixedTypes, 'stored_value', '/number_negative'),
    value('stored_null', 'An explicit null.', const ['stored-value', 'null'],
        mixedTypes, 'stored_value', '/explicit_null'),
    value('stored_true', 'A true literal.', const ['stored-value', 'bool'],
        mixedTypes, 'stored_value', '/flag_true'),
    value('stored_false', 'A false literal.', const ['stored-value', 'bool'],
        mixedTypes, 'stored_value', '/flag_false'),
    value('stored_nested_list', 'A nested array with a nested object item.',
        const ['stored-value', 'array', 'nested'], mixedTypes, 'stored_value',
        '/nested/list'),
    value('stored_nested_list_item', 'One object inside that array.',
        const ['stored-value', 'object'], mixedTypes, 'stored_value', '/nested/list/2'),
    value('stored_deep_leaf', 'A leaf five pointers deep.',
        const ['stored-value', 'nested'], mixedTypes, 'stored_value', '/nested/list/2/deep'),
    value('stored_numeric_object_key', 'A numeric key of an object, not an array index.',
        const ['stored-value', 'numeric-key', 'pointer'], mixedTypes, 'stored_value',
        '/nested/0'),
    value('stored_dotted_key', 'A key containing a dot, addressed unescaped.',
        const ['stored-value', 'dotted-key'], mixedTypes, 'stored_value', '/nested/dotted.key'),
    value('stored_escaped_slash_key', 'A key containing a slash, addressed with ~1.',
        const ['stored-value', 'pointer-escape'], mixedTypes, 'stored_value',
        '/nested/with~1slash'),
    value('stored_escaped_tilde_key', 'A key containing a tilde, addressed with ~0.',
        const ['stored-value', 'pointer-escape'], mixedTypes, 'stored_value',
        '/nested/with~0tilde'),
    value('value_text_scalar', 'The exact source text of a scalar.',
        const ['value-text', 'scalar'], mixedTypes, 'value_text', '/port'),
    value('value_text_container', 'The exact source text of a container, comments included.',
        const ['value-text', 'comments', 'nested'], mixedTypes, 'value_text', '/nested'),
    value('value_text_list', 'The exact source text of a commented array.',
        const ['value-text', 'comments', 'array'], mixedTypes, 'value_text', '/nested/list'),
    value('value_text_astral', 'Source text of a value under an astral key.',
        const ['value-text', 'astral'], astralDoc, 'value_text', '/rocket \u{1F680}'),
    value('value_text_root', 'The root container text without surrounding trivia.',
        const ['value-text', 'root'], commentOwnership, 'value_text', ''),
    value('format_template', 'A placeholder value reports json5-template.',
        const ['format', 'placeholder'], mixedTypes, 'format_of', '/port'),
    value('format_plain', 'A plain value reports json5.', const ['format'],
        mixedTypes, 'format_of', '/number_int'),
    value('format_nested_template', 'A container inherits the flag from a deep value.',
        const ['format', 'placeholder', 'nested'], mixedTypes, 'format_of', '/nested'),
    value('format_root', 'The root format of the mixed document.',
        const ['format', 'root'], mixedTypes, 'format_of', ''),
    value('paths_root', 'Every pointer of the mixed document.',
        const ['paths'], mixedTypes, 'paths', ''),
    value('paths_subtree', 'Pointers below one container.',
        const ['paths', 'nested'], mixedTypes, 'paths', '/nested'),
    value('paths_list', 'Pointers of an array and its items.',
        const ['paths', 'array'], mixedTypes, 'paths', '/nested/list'),
    value('paths_escaped_keys', 'Pointers escape slash and tilde in keys.',
        const ['paths', 'pointer-escape'], mixedTypes, 'paths', '/nested/with~1slash'),
    value('paths_absent', 'An absent pointer yields no paths.', const ['paths', 'absent'],
        mixedTypes, 'paths', '/absent_key'),
    value('paths_scalar', 'A scalar addresses exactly itself.',
        const ['paths', 'scalar'], mixedTypes, 'paths', '/number_int'),
    value('paths_astral', 'Pointers of the astral document.',
        const ['paths', 'astral'], astralDoc, 'paths', ''),
    value('find_rejects_append_marker', 'The append marker is not a lookup token.',
        const ['pointer', 'append-marker', 'rejection'], mixedTypes, 'value_text',
        '/nested/list/-'),
    value('find_rejects_bad_escape', 'A malformed pointer escape is rejected.',
        const ['pointer', 'rejection'], mixedTypes, 'value_text', '/~2'),
    value('find_rejects_missing_prefix', 'A path through a scalar is rejected.',
        const ['pointer', 'rejection'], mixedTypes, 'stored_value', '/number_int/deeper'),
    value('find_rejects_non_index', 'A non-numeric token cannot index an array.',
        const ['pointer', 'rejection'], mixedTypes, 'stored_value', '/nested/list/x'),
  ];
}

// -- operations --------------------------------------------------------------

CorpusCase _op(
  String id,
  String description,
  List<String> classes,
  String input,
  Map<String, Object?> operation, {
  Map<String, Object?>? divergence,
}) =>
    CorpusCase(
      id: id,
      description: description,
      classes: classes,
      kind: 'operation',
      input: input,
      operation: operation,
      divergence: divergence,
    );

/// The general form: [corrected] is the whole expectation the Dart
/// implementation asserts, while the fixture keeps the baseline's observed
/// result as `baselineEvidence`.
///
/// [report] names the authority the divergence is anchored to:
/// an item in the handoff notes for the `aiset` Python team (`A<NN>`,
/// `F<NN>`) or, for a difference the specification requires rather than
/// a baseline defect, a named SPEC anchor (`SPEC5-FLUTTER-EXT`).
Map<String, Object?> divergenceExpectation({
  required String id,
  required String report,
  required String note,
  required Map<String, Object?> corrected,
}) =>
    {
      'id': id,
      'report': report,
      'note': note,
      'corrected': corrected,
    };

List<CorpusCase> _operationCases() => [
      // -- apply_set: scalars and placeholders -----------------------------
      _op('set_scalar_multiline', 'Replace one scalar in a commented document.',
          const ['set', 'scalar', 'comments'], commentOwnership,
          {'op': 'set', 'pointer': '/element1', 'value_text': '125'}),
      _op('set_scalar_nested', 'Replace a scalar inside a nested commented object.',
          const ['set', 'scalar', 'nested', 'comments'], commentOwnership,
          {'op': 'set', 'pointer': '/element2/element3', 'value_text': '999'}),
      _op('set_template_to_number',
          'A placeholder value replaced by a plain number loses the token.',
          const ['set', 'placeholder'], mixedTypes,
          {'op': 'set', 'pointer': '/port', 'value_text': '9090'}),
      _op('set_number_to_placeholder',
          'A placeholder value text is spliced verbatim, never re-serialized.',
          const ['set', 'placeholder', 'no-reserialize'], mixedTypes,
          {'op': 'set', 'pointer': '/number_int', 'value_text': r'${NEW_VAR:-x y}'}),
      _op('set_placeholder_empty_default', 'A placeholder with an explicit empty default.',
          const ['set', 'placeholder'], mixedTypes,
          {'op': 'set', 'pointer': '/number_int', 'value_text': r'${A:-}'}),
      _op('set_string_with_escapes', 'A string value text keeps its escape bytes.',
          const ['set', 'string', 'escapes'], mixedTypes,
          {'op': 'set', 'pointer': '/flag_true', 'value_text': r'"a\"b\\c\nd"'}),
      _op('set_astral_string',
          'A value text containing astral characters is spliced verbatim.',
          const ['set', 'astral', 'string'], astralDoc,
          {'op': 'set', 'pointer': '/tail', 'value_text': '"\u{1F680} launch"'}),
      _op('set_astral_key_value',
          'Editing the value under an astral key splices at the right code-unit offset.',
          const ['set', 'astral'], astralDoc,
          {'op': 'set', 'pointer': '/rocket \u{1F680}', 'value_text': '"liftoff"'}),
      _op('set_value_text_surrounding_trivia',
          'Whitespace around the submitted value is not part of the value.',
          const ['set', 'value-text'], mixedTypes,
          {'op': 'set', 'pointer': '/number_int', 'value_text': '   42   '}),
      _op('set_crlf', 'A set in a CRLF document keeps every other byte.',
          const ['set', 'crlf'], crlfDoc, {'op': 'set', 'pointer': '/a', 'value_text': '9'}),
      _op('set_bom', 'A set in a BOM document keeps the mark.', const ['set', 'bom'],
          bomDoc, {'op': 'set', 'pointer': '/a', 'value_text': '2'}),
      _op('set_no_final_newline', 'A set in a document without a final newline.',
          const ['set', 'no-final-newline'], noFinalNewline,
          {'op': 'set', 'pointer': '/a', 'value_text': '9'}),
      _op('set_escaped_keys', 'A dotted key is addressed and replaced.',
          const ['set', 'dotted-key'], mixedTypes,
          {'op': 'set', 'pointer': '/nested/dotted.key', 'value_text': '22'}),
      _op('set_slash_key', 'A key containing a slash, addressed with ~1.',
          const ['set', 'pointer-escape'], mixedTypes,
          {'op': 'set', 'pointer': '/nested/with~1slash', 'value_text': '33'}),
      _op('set_tilde_key', 'A key containing a tilde, addressed with ~0.',
          const ['set', 'pointer-escape'], mixedTypes,
          {'op': 'set', 'pointer': '/nested/with~0tilde', 'value_text': '44'}),
      _op('set_numeric_object_key', 'A numeric object key is not an array index.',
          const ['set', 'numeric-key'], mixedTypes,
          {'op': 'set', 'pointer': '/nested/0', 'value_text': '"replaced"'}),
      _op('set_array_item', 'One array item by index keeps its sibling comments.',
          const ['set', 'array', 'comments'], mixedTypes,
          {'op': 'set', 'pointer': '/nested/list/1', 'value_text': '42'}),

      // -- apply_set: creating members --------------------------------------
      _op('set_create_member_multiline', 'Setting an absent key creates it with local indentation.',
          const ['set', 'create-member', 'indentation'], mixedTypes,
          {'op': 'set', 'pointer': '/created_leaf', 'value_text': '42'}),
      _op('set_create_member_inline', 'Creating a key in an inline object.',
          const ['set', 'create-member', 'inline'], '{ a: 1 }',
          {'op': 'set', 'pointer': '/b', 'value_text': '2'}),
      _op('set_create_in_empty_object_inline',
          'Creating the first key of an inline empty object replaces its inner text.',
          const ['set', 'create-member', 'empty', 'inline'], '{ empty: { } }',
          {'op': 'set', 'pointer': '/empty/x', 'value_text': '1'}),
      _op('set_create_in_empty_object_multiline',
          'Creating the first key of a block empty object.',
          const ['set', 'create-member', 'empty'], '{\n  empty: {\n  },\n}\n',
          {'op': 'set', 'pointer': '/empty/x', 'value_text': '1'}),
      _op('set_create_nested', 'Creating a key two levels down.',
          const ['set', 'create-member', 'nested'], nestedObjectList,
          {'op': 'set', 'pointer': '/workers/0/name', 'value_text': '"Web"'}),
      _op('set_create_after_commented_last',
          'A new key lands after the last member and its trailing comment.',
          const ['set', 'create-member', 'comments'], '{\n  a: 1, // one\n}\n',
          {'op': 'set', 'pointer': '/b', 'value_text': '2'}),

      // -- apply_set: containers ---------------------------------
      _op('set_object_to_object_uncommented',
          'Replacing a comment-free object reindents the submitted text.',
          const ['set', 'object', 'reindent'], '{\n  o: {\n    a: 1,\n  },\n}\n',
          {'op': 'set', 'pointer': '/o', 'value_text': '{ b: 2 }'}),
      _op('set_object_to_object_commented',
          'Replacing a commented object keeps the comments of surviving members.',
          const ['set', 'object', 'comments'], commentOwnership,
          {'op': 'set', 'pointer': '/element2', 'value_text': '{\n    element3: 500,\n    element4: 600,\n  }'}),
      _op('set_object_commented_child_same_comment',
          'A comment the client sent back is re-attached anyway, as the baseline does.',
          const ['set', 'object', 'comments', 'quirk'],
          '{\n  e: {\n    // lead\n    x: 1, // mid-trail\n  },\n}\n',
          {'op': 'set', 'pointer': '/e', 'value_text': '{\n  // lead\n  x: 5,\n}'}),
      _op('set_object_no_trailing_comma_style',
          'An object whose last member had no comma keeps that style.',
          const ['set', 'object', 'commas'], '{\n  e: {\n    // lead\n    x: 1\n  },\n}\n',
          {'op': 'set', 'pointer': '/e', 'value_text': '{ x: 5, z: 9 }'}),
      _op('set_object_block_end_only',
          'An object whose only comment is a block-end comment keeps it.',
          const ['set', 'object', 'comments', 'block-end'],
          '{\n  e: {\n    x: 1\n    // end\n  },\n}\n',
          {'op': 'set', 'pointer': '/e', 'value_text': '{ x: 5 }'}),
      _op('set_object_drops_opening_comment',
          'The replaced object\'s own opening comment is inside the replaced span.',
          const ['set', 'object', 'comments', 'opening'],
          '{\n  a: { // opening\n    b: 1,\n  },\n}\n',
          {'op': 'set', 'pointer': '/a', 'value_text': '{ c: 2 }'}),
      _op('set_scalar_to_multiline_object',
          'A multi-line submitted value is reindented by the baseline rule.',
          const ['set', 'object', 'reindent', 'multiline'], '{\n  a: 1,\n}\n',
          {'op': 'set', 'pointer': '/a', 'value_text': '{\n  b: 1,\n}'}),
      _op('set_object_to_scalar', 'Replacing a comment-free object with a scalar.',
          const ['set', 'object', 'scalar'], '{\n  o: {\n    a: 1,\n  },\n}\n',
          {'op': 'set', 'pointer': '/o', 'value_text': '5'}),
      _op('set_array_length_change_uncommented',
          'Changing the length of a comment-free array replaces its text.',
          const ['set', 'array', 'length-change'], singleLineObjects,
          {'op': 'set', 'pointer': '/single_array', 'value_text': '[1, 2, 3, 4, 5]'}),
      _op('set_array_equal_length_elementwise',
          'Equal-length array replacement edits item by item.',
          const ['set', 'array', 'elementwise', 'comments'], commentedList,
          {'op': 'set', 'pointer': '/list', 'value_text': '["x", "y", "z"]'}),
      _op('set_array_equal_length_nested',
          'Nested equal-length array replacement edits item by item.',
          const ['set', 'array', 'elementwise', 'nested'], '{\n  l: [[1], [2]],\n}\n',
          {'op': 'set', 'pointer': '/l', 'value_text': '[[9], [8]]'}),
      _op('set_array_item_by_index', 'Setting one item of a commented array.',
          const ['set', 'array', 'comments'], commentedList,
          {'op': 'set', 'pointer': '/list/0', 'value_text': '"first"'}),

      // -- apply_set: rejections ----------------------------------------------
      _op('set_reject_root_pointer', 'The root pointer is read-only.',
          const ['set', 'rejection', 'root'], mixedTypes,
          {'op': 'set', 'pointer': '', 'value_text': '{}'}),
      _op('set_reject_missing_parent', 'A path through an absent key is rejected.',
          const ['set', 'rejection', 'pointer'], mixedTypes,
          {'op': 'set', 'pointer': '/absent/leaf', 'value_text': '1'}),
      _op('set_reject_out_of_range_index', 'An array index past the end is rejected.',
          const ['set', 'rejection', 'array'], mixedTypes,
          {'op': 'set', 'pointer': '/nested/list/9', 'value_text': '1'}),
      _op('set_reject_non_numeric_index', 'A word cannot index an array.',
          const ['set', 'rejection', 'array'], mixedTypes,
          {'op': 'set', 'pointer': '/nested/list/x', 'value_text': '1'}),
      _op('set_reject_through_scalar', 'A path through a scalar is rejected.',
          const ['set', 'rejection', 'pointer'], mixedTypes,
          {'op': 'set', 'pointer': '/number_int/deeper', 'value_text': '1'}),
      _op('set_reject_append_marker', 'The append marker is not a set token.',
          const ['set', 'rejection', 'append-marker'], mixedTypes,
          {'op': 'set', 'pointer': '/nested/list/-', 'value_text': '1'}),
      _op('set_reject_bad_escape', 'A malformed pointer escape is rejected.',
          const ['set', 'rejection', 'pointer'], mixedTypes,
          {'op': 'set', 'pointer': '/~2', 'value_text': '1'}),
      _op('set_reject_empty_value_text', 'An empty value text is rejected.',
          const ['set', 'rejection', 'value-text'], mixedTypes,
          {'op': 'set', 'pointer': '/number_int', 'value_text': ''}),
      _op('set_reject_blank_value_text', 'A whitespace-only value text is rejected.',
          const ['set', 'rejection', 'value-text'], mixedTypes,
          {'op': 'set', 'pointer': '/number_int', 'value_text': '   \n '}),
      _op('set_reject_two_values', 'Two values in one text are rejected.',
          const ['set', 'rejection', 'value-text'], mixedTypes,
          {'op': 'set', 'pointer': '/number_int', 'value_text': '1 2'}),
      _op('set_reject_invalid_value_text', 'Malformed value text is rejected.',
          const ['set', 'rejection', 'value-text'], mixedTypes,
          {'op': 'set', 'pointer': '/number_int', 'value_text': '{ oops'}),
      _op('set_conflict_length_change_commented',
          'Changing a commented array length would drop comments.',
          const ['set', 'rejection', 'comment-conflict', 'array'], commentedList,
          {'op': 'set', 'pointer': '/list', 'value_text': '["only"]'}),
      _op('set_conflict_scalar_to_object_commented',
          'Replacing a commented scalar with a different structural type is refused.',
          const ['set', 'rejection', 'comment-conflict'], '{\n  a: 1, // c\n}\n',
          {'op': 'set', 'pointer': '/a', 'value_text': '{}'}),
      _op('set_conflict_drop_commented_member',
          'A replacement that drops a commented member is refused.',
          const ['set', 'rejection', 'comment-conflict', 'object'],
          '{\n  e: {\n    // lead\n    x: 1,\n  },\n}\n',
          {'op': 'set', 'pointer': '/e', 'value_text': '{ y: 2 }'}),
      _op('set_conflict_commented_child_type',
          'A replacement that changes a commented member\'s structural type is refused.',
          const ['set', 'rejection', 'comment-conflict', 'object'],
          '{\n  e: {\n    // lead\n    x: 1,\n  },\n}\n',
          {'op': 'set', 'pointer': '/e', 'value_text': '{ x: [1] }'}),

      // -- apply_add ----------------------------------------------------------
      _op('add_append_marker_multiline',
          'The append marker adds one item in the array\'s own layout.',
          const ['add', 'append-marker', 'array'],
          '{\n  list: [\n    "a",\n    // comment\n    "b",\n  ],\n}\n',
          {'op': 'add', 'pointer': '/list/-', 'value_text': '"c"'}),
      _op('add_append_marker_no_trailing_comma',
          'An array without a trailing comma gains the separator before the new item.',
          const ['add', 'append-marker', 'commas'], '{\n  list: [\n    "a"\n  ],\n}\n',
          {'op': 'add', 'pointer': '/list/-', 'value_text': '"b"'}),
      _op('add_append_empty_array_multiline', 'Appending to an empty block array.',
          const ['add', 'append-marker', 'empty'], '{\n  list: [\n  ],\n}\n',
          {'op': 'add', 'pointer': '/list/-', 'value_text': '1'}),
      _op('add_append_empty_array_inline', 'Appending to an empty inline array.',
          const ['add', 'append-marker', 'empty', 'inline'], '{\n  list: [],\n}\n',
          {'op': 'add', 'pointer': '/list/-', 'value_text': '1'}),
      _op('add_append_inline', 'Appending to an inline array keeps it inline.',
          const ['add', 'append-marker', 'inline'], '{\n  list: [1, 2],\n}\n',
          {'op': 'add', 'pointer': '/list/-', 'value_text': '3'}),
      _op('add_append_after_commented_last',
          'The new item lands after the last item and its trailing comment.',
          const ['add', 'append-marker', 'comments'],
          '{\n  l: [\n    1, // one\n    2, // two\n  ],\n}\n',
          {'op': 'add', 'pointer': '/l/-', 'value_text': '3'}),
      _op('add_append_block_end_comment',
          'Appending to an array with a block-end comment and no trailing comma.',
          const ['add', 'append-marker', 'comments', 'block-end'], blockEndList,
          {'op': 'add', 'pointer': '/list/-', 'value_text': '3'}),
      _op('add_append_object_value',
          'Appending a multiline object value reindents it into the array.',
          const ['add', 'append-marker', 'object', 'multiline'], nestedObjectList,
          {'op': 'add', 'pointer': '/workers/-', 'value_text': '{\n  id: "gpu",\n  ports: [80],\n}'}),
      _op('add_append_placeholder_value',
          'An appended placeholder keeps its token text exactly.',
          const ['add', 'append-marker', 'placeholder'],
          '{\n  list: [\n    "a",\n  ],\n}\n',
          {'op': 'add', 'pointer': '/list/-', 'value_text': r'${EXTRA:-}'}),
      _op('add_append_root_array', 'The append marker on the root array.',
          const ['add', 'append-marker', 'root'], '[\n  "a",\n]\n',
          {'op': 'add', 'pointer': '/-', 'value_text': '"b"'}),
      _op('add_append_astral', 'Appending an astral value after astral text.',
          const ['add', 'append-marker', 'astral'], astralDoc,
          {'op': 'add', 'pointer': '/list/-', 'value_text': '"\u{1F680}"'}),
      _op('add_append_reject_on_object', 'The append marker requires an array.',
          const ['add', 'rejection', 'append-marker'], '{\n  obj: { a: 1 },\n}\n',
          {'op': 'add', 'pointer': '/obj/-', 'value_text': '2'}),
      _op('add_append_reject_missing_container', 'The append marker needs an existing array.',
          const ['add', 'rejection', 'append-marker', 'pointer'], mixedTypes,
          {'op': 'add', 'pointer': '/absent/-', 'value_text': '2'}),
      _op('add_key_multiline', 'Adding a key to a block object.',
          const ['add', 'create-member'], '{\n  dyn: {\n    a: 1,\n  },\n}\n',
          {'op': 'add', 'pointer': '/dyn/b', 'value_text': '2'}),
      _op('add_key_quoted_label', 'A label that is not an identifier is quoted.',
          const ['add', 'create-member', 'quoted-key'],
          '{\n  o: {\n    a: 1,\n  },\n}\n',
          {'op': 'add', 'pointer': '/o/new key', 'value_text': '2'}),
      _op('add_key_needs_quoting_escapes',
          'A label with quote and backslash characters is escaped once.',
          const ['add', 'create-member', 'quoted-key', 'escapes'], '{\n  o: {},\n}\n',
          {'op': 'add', 'pointer': '/o/a"b\\c', 'value_text': '1'}),
      _op('add_key_astral_label', 'An astral label is not an identifier and is quoted.',
          const ['add', 'create-member', 'astral'], astralDoc,
          {'op': 'add', 'pointer': '/\u{1F680}pad', 'value_text': '"dock"'}),
      _op('add_key_empty_object', 'Adding the first key of an empty object.',
          const ['add', 'create-member', 'empty'], '{\n  o: {},\n}\n',
          {'op': 'add', 'pointer': '/o/x', 'value_text': '1'}),
      _op('add_key_duplicate_rejected', 'Adding an existing key is refused.',
          const ['add', 'rejection', 'duplicate-key'], '{\n  o: {\n    a: 1,\n  },\n}\n',
          {'op': 'add', 'pointer': '/o/a', 'value_text': '2'}),
      _op('add_key_on_array_rejected', 'A non-append token cannot address an array.',
          const ['add', 'rejection', 'array'], singleLineObjects,
          {'op': 'add', 'pointer': '/single_array/x', 'value_text': '2'}),
      _op('add_index_rejected', 'An array index is not an add target.',
          const ['add', 'rejection', 'array'], singleLineObjects,
          {'op': 'add', 'pointer': '/single_array/0', 'value_text': '2'}),
      _op('add_reject_root_pointer', 'Adding at the root pointer is refused.',
          const ['add', 'rejection', 'root'], '[1]',
          {'op': 'add', 'pointer': '', 'value_text': '2'}),
      _op('add_reject_missing_object', 'Adding below an absent container is refused.',
          const ['add', 'rejection', 'pointer'], mixedTypes,
          {'op': 'add', 'pointer': '/absent/x', 'value_text': '2'}),
      _op('add_reject_invalid_value_text', 'Malformed value text is refused before editing.',
          const ['add', 'rejection', 'value-text'], singleLineObjects,
          {'op': 'add', 'pointer': '/compact/z', 'value_text': 'nope!'}),

      // -- apply_remove ---------------------------------------------------------
      _op('remove_member_leading_comment',
          'Removing a member takes the comments it owns.',
          const ['remove', 'comments', 'leading'], commentedMembers,
          {'op': 'remove', 'pointer': '/a'}),
      _op('remove_member_trailing_comment_non_last',
          'A trailing comment of a removed non-last member survives on its own line.',
          const ['remove', 'comments', 'trailing', 'quirk'],
          '{\n  a: 1, // trail\n  b: 2,\n}\n',
          {'op': 'remove', 'pointer': '/a'}),
      _op('remove_last_member_absorbs_separator',
          'Removing the last member takes the separator that used to precede it.',
          const ['remove', 'commas'], '{\n  a: 1,\n  b: 2,\n}\n',
          {'op': 'remove', 'pointer': '/b'}),
      _op('remove_last_member_with_trailing_comment',
          'The last member and its trailing comment leave together.',
          const ['remove', 'comments', 'trailing'], '{\n  a: 1,\n  b: 2 // trail\n}\n',
          {'op': 'remove', 'pointer': '/b'}),
      _op('remove_middle_member', 'Removing a middle member leaves its neighbours intact.',
          const ['remove', 'object'], commentedMembers, {'op': 'remove', 'pointer': '/b'}),
      _op('remove_only_member', 'Removing the only member leaves an empty object.',
          const ['remove', 'empty'], '{\n  a: 1,\n}\n', {'op': 'remove', 'pointer': '/a'}),
      _op('remove_member_with_container_value',
          'Removing a member removes its whole value, comments included.',
          const ['remove', 'comments', 'nested'], commentOwnership,
          {'op': 'remove', 'pointer': '/element2'}),
      _op('remove_member_opening_comment_owned',
          'The opening comment of the removed value leaves with it.',
          const ['remove', 'comments', 'opening'],
          '{\n  a: { // opening\n    b: 1,\n  },\n  c: 2,\n}\n',
          {'op': 'remove', 'pointer': '/a'}),
      _op('remove_member_block_end_stays',
          'A block-end comment belongs to the container and stays.',
          const ['remove', 'comments', 'block-end'],
          '{\n  a: 1,\n  b: 2,\n  // keep me\n}\n',
          {'op': 'remove', 'pointer': '/b'}),
      _op('remove_nested_deep', 'Removing a member of a nested object.',
          const ['remove', 'nested'], commentOwnership,
          {'op': 'remove', 'pointer': '/element2/element3'}),
      _op('remove_astral_member', 'Removing a member after astral text.',
          const ['remove', 'astral'], astralDoc, {'op': 'remove', 'pointer': '/tail'}),
      _op('remove_crlf_member', 'Removing a member in a CRLF document.',
          const ['remove', 'crlf'], crlfDoc, {'op': 'remove', 'pointer': '/b'}),
      _op('remove_reject_missing_key', 'Removing an absent key is refused.',
          const ['remove', 'rejection', 'pointer'], mixedTypes,
          {'op': 'remove', 'pointer': '/absent'}),
      _op('remove_reject_root', 'Removing the root is refused.', const ['remove', 'rejection', 'root'],
          mixedTypes, {'op': 'remove', 'pointer': ''}),
      _op('remove_reject_out_of_range', 'Removing past the last index is refused.',
          const ['remove', 'rejection', 'array'], commentedList,
          {'op': 'remove', 'pointer': '/list/9'}),
      _op('remove_reject_through_scalar', 'A path through a scalar is refused.',
          const ['remove', 'rejection', 'pointer'], mixedTypes,
          {'op': 'remove', 'pointer': '/number_int/x'}),
      _op('remove_array_item_first_with_leading_comment',
          'Removing the first item takes its leading comment.',
          const ['remove', 'array', 'comments', 'leading'],
          '{\n  list: [\n    // first\n    "a",\n    "b",\n  ],\n}\n',
          {'op': 'remove', 'pointer': '/list/0'}),
      _op('remove_array_item_middle_inline',
          'Removing an inline item absorbs the separator space, as the baseline does.',
          const ['remove', 'array', 'inline', 'commas'],
          '{\n  list: ["a", "b", "c"],\n}\n',
          {'op': 'remove', 'pointer': '/list/1'}),
      _op('remove_array_item_last_absorbs_separator',
          'Removing the last item takes the preceding separator.',
          const ['remove', 'array', 'commas'], commentedList,
          {'op': 'remove', 'pointer': '/list/2'}),
      _op('remove_array_item_trailing_comment_survives',
          'A trailing comment of a removed non-last item stays behind, as in the baseline.',
          const ['remove', 'array', 'comments', 'trailing', 'quirk'],
          '{\n  l: [\n    1, // one\n    2,\n  ],\n}\n',
          {'op': 'remove', 'pointer': '/l/0'}),
      _op('remove_only_array_item', 'Removing the only item leaves an empty array.',
          const ['remove', 'array', 'empty'], '{\n  list: [\n    "a",\n  ],\n}\n',
          {'op': 'remove', 'pointer': '/list/0'}),
      _op('remove_array_item_no_comma_last',
          'The last item of a comma-less array leaves its line behind.',
          const ['remove', 'array', 'commas'], '{\n  l: [\n    1,\n    2\n  ],\n}\n',
          {'op': 'remove', 'pointer': '/l/1'}),
      _op('remove_array_item_no_comma_middle',
          'A middle item without a comma is removed with its line.',
          const ['remove', 'array', 'commas'], '{\n  l: [\n    1\n    2\n    3,\n  ],\n}\n',
          {'op': 'remove', 'pointer': '/l/1'}),
      _op('remove_nested_array_item', 'Removing an item of a nested array.',
          const ['remove', 'array', 'nested'], mixedTypes,
          {'op': 'remove', 'pointer': '/nested/list/0'}),
      _op('remove_astral_array_item', 'Removing an array item after astral text.',
          const ['remove', 'array', 'astral'], astralDoc,
          {'op': 'remove', 'pointer': '/list/0'}),
      _op('remove_crlf_array_item', 'Removing an item in a CRLF array.',
          const ['remove', 'array', 'crlf'],
          '{\r\n  list: [\r\n    "a",\r\n    "b",\r\n  ],\r\n}\r\n',
          {'op': 'remove', 'pointer': '/list/0'}),

      // -- apply_move -----------------------------------------------------------
      _op('move_multiline_keeps_comments',
          'A moved item carries its leading comment with it.',
          const ['move', 'comments', 'array'],
          '{\n  list: [\n    // first\n    "a",\n    // second\n    "b",\n  ],\n}\n',
          {'op': 'move', 'source': '/list/1', 'target': '/list/0'}),
      _op('move_inline', 'Moving inside an inline array keeps the inline layout.',
          const ['move', 'inline'], '{\n  list: [1, 2, 3],\n}\n',
          {'op': 'move', 'source': '/list/2', 'target': '/list/0'}),
      _op('move_to_end_position', 'Moving to the position past the last item.',
          const ['move', 'array'], '{\n  list: [\n    "a",\n    "b",\n  ],\n}\n',
          {'op': 'move', 'source': '/list/0', 'target': '/list/2'}),
      _op('move_across_nesting_levels',
          'A multiline object item with a nested array moves as one block, reindented.',
          const ['move', 'nested', 'multiline', 'comments'], nestedObjectList,
          {'op': 'move', 'source': '/workers/0', 'target': '/workers/1'}),
      _op('move_nested_item_up',
          'Moving the last item of a nested array to the front.',
          const ['move', 'nested', 'array'], nestedObjectList,
          {'op': 'move', 'source': '/workers/0/ports/1', 'target': '/workers/0/ports/0'}),
      _op('move_root_array_with_document_comment',
          'Moving inside the root array leaves the document comment outside '
          'the rebuilt container.',
          const ['move', 'root', 'comments'],
          '// header\n[\n  "a",\n  "b",\n]\n',
          {'op': 'move', 'source': '/0', 'target': '/1'}),
      _op('move_drops_array_opening_comment',
          'The array\'s own opening comment is inside the rebuilt span and leaves.',
          const ['move', 'comments', 'opening'], openingCommentList,
          {'op': 'move', 'source': '/list/0', 'target': '/list/1'}),
      _op('move_with_block_end_comment',
          'A block-end comment stays before the closing bracket.',
          const ['move', 'comments', 'block-end'], blockEndList,
          {'op': 'move', 'source': '/list/0', 'target': '/list/1'}),
      _op('move_inline_trailing_comma_kept',
          'An inline array keeps its trailing comma style through a move.',
          const ['move', 'inline', 'commas'], '{ list: [1, 2,], }\n',
          {'op': 'move', 'source': '/list/0', 'target': '/list/1'}),
      _op('move_multiline_no_trailing_comma',
          'A block array without a trailing comma stays without one.',
          const ['move', 'commas'], '{\n  l: [\n    1,\n    2\n  ],\n}\n',
          {'op': 'move', 'source': '/l/0', 'target': '/l/1'}),
      _op('move_target_uses_source_container',
          'Only the target index is read; the target container is ignored, as in the baseline.',
          const ['move', 'quirk', 'array'], '{\n  a: [1, 2],\n  b: [7],\n}\n',
          {'op': 'move', 'source': '/a/0', 'target': '/b/0'}),
      _op('move_astral_items', 'Moving items in an array that follows astral text.',
          const ['move', 'astral'], astralDoc,
          {'op': 'move', 'source': '/list/0', 'target': '/list/1'}),
      _op('move_crlf_items', 'Moving items in a CRLF array.', const ['move', 'crlf'],
          '{\r\n  list: [\r\n    "a",\r\n    "b",\r\n  ],\r\n}\r\n',
          {'op': 'move', 'source': '/list/0', 'target': '/list/1'}),
      _op('move_reject_object_parent', 'Only array items can be moved.',
          const ['move', 'rejection', 'object'], mixedTypes,
          {'op': 'move', 'source': '/number_int', 'target': '/number_float'}),
      _op('move_reject_out_of_range_target', 'The target position must exist.',
          const ['move', 'rejection', 'array'], commentedList,
          {'op': 'move', 'source': '/list/0', 'target': '/list/9'}),
      _op('move_reject_missing_source', 'The source must exist.',
          const ['move', 'rejection', 'pointer'], commentedList,
          {'op': 'move', 'source': '/list/7', 'target': '/list/0'}),
      _op('move_reject_non_numeric_source', 'A word cannot address an item.',
          const ['move', 'rejection', 'array'], commentedList,
          {'op': 'move', 'source': '/list/x', 'target': '/list/0'}),

      // -- apply_rename ---------------------------------------------------------
      _op('rename_keeps_value_and_comments',
          'Renaming changes the key bytes only; the value text is untouched.',
          const ['rename', 'comments', 'value-preserved'],
          '{\n  // leading\n  main: {\n    a: 1, // trailing\n  },\n  other: 2,\n}\n',
          {'op': 'rename', 'pointer': '/main', 'new_key': 'primary'}),
      _op('rename_template_value_untouched',
          'A placeholder value keeps its exact token text through a rename.',
          const ['rename', 'placeholder', 'value-preserved'], mixedTypes,
          {'op': 'rename', 'pointer': '/port', 'new_key': 'service_port'}),
      _op('rename_non_identifier_quotes', 'A label that is not an identifier is quoted.',
          const ['rename', 'quoted-key'], '{ main: 1 }',
          {'op': 'rename', 'pointer': '/main', 'new_key': 'main key'}),
      _op('rename_dotted_key', 'Renaming a key that contains a dot.',
          const ['rename', 'dotted-key', 'quoted-key'], '{\n  "a.b": 1,\n}\n',
          {'op': 'rename', 'pointer': '/a.b', 'new_key': 'c.d'}),
      _op('rename_to_dotted_key', 'Renaming to a key that needs quoting.',
          const ['rename', 'dotted-key'], '{\n  plain: 1,\n}\n',
          {'op': 'rename', 'pointer': '/plain', 'new_key': 'a.b'}),
      _op('rename_special_characters',
          'Quote and backslash characters in the new key are escaped once.',
          const ['rename', 'escapes', 'quoted-key'], '{ x: 1 }',
          {'op': 'rename', 'pointer': '/x', 'new_key': 'he said "hi"\\z'}),
      _op('rename_quoted_to_identifier',
          'Renaming a quoted key to an identifier drops the quotes.',
          const ['rename', 'quoted-key'], '{\n  "old": 1,\n}\n',
          {'op': 'rename', 'pointer': '/old', 'new_key': 'new'}),
      _op('rename_astral_key', 'An astral new key is quoted and spliced exactly.',
          const ['rename', 'astral'], astralDoc,
          {'op': 'rename', 'pointer': '/list', 'new_key': '\u{1F680}list'}),
      _op('rename_astral_value_untouched',
          'Renaming a key that follows astral text leaves the value bytes alone.',
          const ['rename', 'astral', 'value-preserved'], astralDoc,
          {'op': 'rename', 'pointer': '/tail', 'new_key': 'head'}),
      _op('rename_nested', 'Renaming a member of a nested object.',
          const ['rename', 'nested'], commentOwnership,
          {'op': 'rename', 'pointer': '/element2/element3', 'new_key': 'element33'}),
      _op('rename_same_key_noop', 'Renaming to the same key returns the source unchanged.',
          const ['rename', 'noop'], '{ a: 1 }',
          {'op': 'rename', 'pointer': '/a', 'new_key': 'a'}),
      _op('rename_crlf', 'Renaming in a CRLF document.', const ['rename', 'crlf'],
          crlfDoc, {'op': 'rename', 'pointer': '/a', 'new_key': 'z'}),
      _op('rename_reject_duplicate', 'Renaming onto an existing key is refused.',
          const ['rename', 'rejection', 'duplicate-key'], '{ a: 1, b: 2 }',
          {'op': 'rename', 'pointer': '/a', 'new_key': 'b'}),
      _op('rename_reject_empty_key', 'An empty new key is refused.',
          const ['rename', 'rejection'], '{ a: 1 }',
          {'op': 'rename', 'pointer': '/a', 'new_key': ''}),
      _op('rename_reject_missing_parent', 'Renaming below an absent key is refused.',
          const ['rename', 'rejection', 'pointer'], mixedTypes,
          {'op': 'rename', 'pointer': '/absent/x', 'new_key': 'y'}),
      _op('rename_reject_missing_key', 'Renaming an absent key is refused.',
          const ['rename', 'rejection', 'pointer'], mixedTypes,
          {'op': 'rename', 'pointer': '/absent', 'new_key': 'y'}),
      _op('rename_reject_array_parent', 'An array has no keys to rename.',
          const ['rename', 'rejection', 'array'], singleLineObjects,
          {'op': 'rename', 'pointer': '/single_array/0', 'new_key': 'y'}),
      _op('rename_reject_root', 'The root pointer cannot be renamed.',
          const ['rename', 'rejection', 'root'], '{ a: 1 }',
          {'op': 'rename', 'pointer': '', 'new_key': 'y'}),
    ];

/// The complete catalog.
List<CorpusCase> corpusCases() => [
      ..._parseAcceptCases(),
      ..._parseRejectCases(),
      ..._valueCases(),
      ..._operationCases(),
    ];
