import 'package:aiset_core/aiset_core.dart';
import 'package:test/test.dart';

/// Parses [text] expecting rejection, and returns the exception.
Json5ParseException expectRejected(String text) {
  late Json5ParseException error;
  try {
    parse(text);
    fail('expected Json5ParseException for: ${text.replaceAll('\n', '\\n')}');
  } on Json5ParseException catch (e) {
    error = e;
  }
  return error;
}

List<String> _texts(List<CommentNode> comments) => [for (final c in comments) c.text];

void main() {
  test('duplicate object keys are rejected with their position', () {
    final error = expectRejected('{\n  a: 1,\n  a: 2,\n}\n');
    expect(error.message, contains("Duplicate object key 'a'"));
    expect(error.line, equals(3));
    expect(error.column, equals(3));
    expect(error.offsetUnit, equals(12));
  });

  test('duplicate keys collide across quoting styles', () {
    expectRejected('{"a":1, a:2}');
  });

  test('trailing content after the root value is rejected', () {
    final error = expectRejected('{\n  a: 1,\n}\n{ b: 2 }');
    expect(error.message, contains('Trailing content'));
    expect(error.line, equals(4));
  });

  test('trailing content is rejected after a scalar root', () {
    expectRejected('42 43');
  });

  test('unsupported template operators are rejected', () {
    final error = expectRejected(r'{ a: ${VAR-default} }');
    expect(error.message, contains('Unsupported template token'));
    expect(error.offsetUnit, equals(5));
  });

  test('template names must start with a letter or underscore', () {
    expectRejected(r'{ a: ${1X} }');
    expectRejected(r'{ a: ${ A } }');
  });

  test('non-finite numbers are rejected', () {
    for (final text in [
      '{ a: NaN }',
      '{ a: Infinity }',
      '{ a: -Infinity }',
      '{ a: +NaN }',
    ]) {
      final error = expectRejected(text);
      expect(error.message, contains('not portable'), reason: text);
    }
  });

  test('unsupported literals are rejected', () {
    for (final raw in ['undefined', 'True', 'False']) {
      final error = expectRejected('{ a: $raw }');
      expect(error.message, contains("Unsupported literal '$raw'"), reason: raw);
    }
  });

  test('invalid value tokens are rejected', () {
    expect(expectRejected('{ a: 1_000 }').message, contains("Invalid value token '1_000'"));
    expect(expectRejected('{ a: 0x }').message, contains("Invalid value token '0x'"));
  });

  test('a comma must follow the value token directly', () {
    // Baseline grammar: `a: 1 , b: 2` is invalid, never
    // normalized. The error lands on the stray comma.
    final error = expectRejected('{ a: 1 , b: 2 }');
    expect(error.message, contains('Expected an object key'));
    expect(error.offsetUnit, equals(7));
  });

  test('a colon must follow the key token directly', () {
    expect(expectRejected('{ a : 1 }').message, contains("Expected ':' after an object key"));
    expect(expectRejected('{ a /*c*/: 1 }').message, contains("Expected ':' after an object key"));
  });

  test('a literal absorbs a directly adjacent block comment start', () {
    // `1/*t*/` is one invalid value token (baseline behaviour); with a
    // space the comment is a trailing comment instead.
    expect(expectRejected('{a: 1/*t*/}').message, contains("Invalid value token '1/*t*/'"));
    final ok = parse('{a: 1 /*t*/}');
    final member = (ok.root as ObjectNode).member('a')!;
    expect(_texts(member.trailingComments), equals(['/*t*/']));
  });

  test('unterminated constructs are rejected with position', () {
    expect(expectRejected('{ a: "x }').message, contains('Unterminated string'));
    expect(expectRejected('{a: 1 /* oops').message, contains('Unterminated block comment'));
    expect(expectRejected('{a: \${AB').message, contains('Unterminated template token'));
    expect(expectRejected('{a: "x\\').message, contains('Dangling escape character'));
  });

  test('bad escapes are rejected', () {
    expect(expectRejected('{ a: "\\q" }').message, contains('Unsupported escape sequence'));
    expect(expectRejected('{ a: "\\u12" }').message, contains(r'Malformed \u escape'));
    expect(expectRejected('{ a: "\\x1" }').message, contains(r'Malformed \x escape'));
    expect(expectRejected('{ a: "\\xZZ" }').message, contains(r'Malformed \x escape'));
  });

  test('raw line breaks inside strings are rejected', () {
    expect(expectRejected('{ a: "x\ny" }').message, contains('Unescaped line break in string'));
    expect(expectRejected('{ a: "x\u2028y" }').message, contains('Unescaped line break in string'));
  });

  test('empty and value-less documents are rejected', () {
    expect(expectRejected('').message, contains('Unexpected end of input'));
    expect(expectRejected('   ').message, contains('Unexpected end of input'));
    expect(expectRejected('// just a comment').message, contains('Unexpected end of input'));
  });

  test('truncated containers are rejected, never crash', () {
    // The baseline raises IndexError here; the Dart parser rejects with a
    // positioned error. The accept/reject outcome is identical.
    for (final text in ['{', '{a', '{a: 1', '{a: 1,', '[', '[1', '{a: {b:']) {
      expectRejected(text);
    }
  });

  test('astral characters do not break error positions', () {
    // One emoji (2 units, 4 bytes) precedes the bad token.
    final error = expectRejected('{\n  "\u{1F680}": 1,\n  b: NaN }');
    expect(error.message, contains('not portable'));
    expect(error.offsetByte - error.offsetUnit, equals(2),
        reason: 'byte and code-unit error offsets must differ by the astral width');
    expect(error.line, equals(3));
  });

  test('origin labels appear in errors', () {
    final error = Json5ParseException(
      message: 'test',
      text: '',
      offsets: OffsetMap.fromText(''),
      offsetUnit: 0,
      origin: 'settings.json5',
    );
    expect(error.toString(), contains('settings.json5'));
  });
}
