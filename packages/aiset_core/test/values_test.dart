import 'package:aiset_core/aiset_core.dart';
import 'package:test/test.dart';

import 'fixtures_io.dart';

void main() {
  late Json5Document mixed;

  setUpAll(() {
    final mixedCase = PreservationCase.loadAll().firstWhere((c) => c.id == 'mixed_types');
    mixed = parse(mixedCase.inputText);
  });

  test('stored value keeps templates explicit', () {
    final value = mixed.storedValue()! as Map<String, Object?>;
    expect(value['port'], equals(const TemplateRef('PORT', '8080')));
    expect(value['explicit_null'], isNull);
    expect(value['number_float'], equals(1.5));
    expect(value['number_int'], equals(42));
    expect(value['number_negative'], equals(-7));
    expect(value['flag_true'], isTrue);
    expect(value['flag_false'], isFalse);
    final list = (value['nested']! as Map<String, Object?>)['list']! as List<Object?>;
    expect(list[2], isA<Map<String, Object?>>());
    expect((list[2]! as Map<String, Object?>)['deep'], equals('yes'));
    expect(value['single quoted'],
        equals(r'value with ${VAR:-default} and "escaped" quotes'));
  });

  test('quoted and special keys decode', () {
    final nested = (mixed.root as ObjectNode).member('nested')!.value as ObjectNode;
    expect(nested.member('dotted.key'), isNotNull);
    expect(nested.member('with/slash'), isNotNull);
    expect(nested.member('with~tilde'), isNotNull);
    expect(nested.member('0'), isNotNull);
    expect(nested.member('0')!.key.quoted, isTrue);
    expect(nested.member('quoted_key')!.key.quoted, isFalse);
  });

  test('number forms parse to the baseline values', () {
    final document = parse('{\n  hex: 0xFF,\n  negHex: -0x1a,\n  plusHex: +0x10,\n'
        '  plus: +5,\n  leadDot: .5,\n  trailDot: 5.,\n  exp: 1e3,\n  expPlus: 1E+3,\n'
        '  negFloat: -0.25,\n  leadingZero: 08,\n}\n');
    final value = document.storedValue()! as Map<String, Object?>;
    expect(value['hex'], equals(255));
    expect(value['negHex'], equals(-26));
    expect(value['plusHex'], equals(16));
    expect(value['plus'], equals(5));
    expect(value['leadDot'], equals(0.5));
    expect(value['trailDot'], equals(5.0));
    expect(value['exp'], equals(1000.0));
    expect(value['expPlus'], equals(1000.0));
    expect(value['negFloat'], equals(-0.25));
    expect(value['leadingZero'], equals(8));
  });

  test('overflowing floats and huge integers', () {
    // The baseline accepts 1e400 as inf; literals Infinity/NaN stay rejected.
    final overflow = parse('{ a: 1e400 }').storedValue()! as Map<String, Object?>;
    expect(overflow['a'], equals(double.infinity));
    // Beyond int64 the value is kept exactly as a BigInt (the baseline keeps
    // an exact Python int; the raw source text is preserved either way).
    // TODO(S1-G): bounded-integer policy.
    final huge = parse('{ a: 99999999999999999999 }').storedValue()! as Map<String, Object?>;
    expect(huge['a'], equals(BigInt.parse('99999999999999999999')));
  });

  test('string escapes decode like the baseline', () {
    final document = parse('{\n  hex: "\\x41",\n  uni: "\\u00e9",\n  pair: "\\ud83d\\ude80",\n'
        '  slash: "a\\/b",\n  cont: "ab\\\ncd",\n  nul: "\\0",\n  said: "he said \\"hi\\"",\n}\n');
    final value = document.storedValue()! as Map<String, Object?>;
    expect(value['hex'], equals('A'));
    expect(value['uni'], equals('é'));
    expect(value['pair'], equals('\u{1F680}'));
    expect(value['slash'], equals('a/b'));
    expect(value['cont'], equals('abcd'));
    expect(value['nul'], equals('\x00'));
    expect(value['said'], equals('he said "hi"'));
    // The raw text keeps the escapes verbatim.
    final pair = (document.root as ObjectNode).member('pair')!;
    expect(pair.value.toSource(), equals(r'"\ud83d\ude80"'));
  });

  test('template forms', () {
    final document = parse('{\n  bare: \${A},\n  def: \${B:-x y},\n  empty: \${C:-},\n'
        '  inStr: "pre \${D:-1} post",\n  fake: "\${1N0T} a placeholder",\n'
        '  unterminatedish: "x \${VAR y",\n}\n');
    final value = document.storedValue()! as Map<String, Object?>;
    expect(value['bare'], equals(const TemplateRef('A')));
    expect(value['def'], equals(const TemplateRef('B', 'x y')));
    expect(value['empty'], equals(const TemplateRef('C', '')));
    expect(value['inStr'], equals(r'pre ${D:-1} post'));
    final root = document.root as ObjectNode;
    expect((root.member('inStr')!.value as StringNode).hasPlaceholder, isTrue);
    expect((root.member('fake')!.value as StringNode).hasPlaceholder, isFalse);
    expect((root.member('unterminatedish')!.value as StringNode).hasPlaceholder, isFalse);
    expect(root.member('bare')!.value, isA<TemplateNode>());
    expect((root.member('bare')!.value as TemplateNode).defaultText, isNull);
  });

  test('format detection', () {
    final root = mixed.root as ObjectNode;
    expect(mixed.formatOf(root.member('port')!.value), equals('json5-template'));
    expect(mixed.formatOf(root.member('single quoted')!.value), equals('json5-template'));
    expect(mixed.formatOf(root.member('number_int')!.value), equals('json5'));
    expect(mixed.formatOf(root), equals('json5-template'));
    expect(parse('{ a: { b: 1 } }').formatOf(parse('{ a: { b: 1 } }').root),
        equals('json5'));
  });

  test('scalar and template root documents', () {
    expect(parse(' 42  ').storedValue(), equals(42));
    expect(parse(' 42  ').toSource(), equals(' 42  '));
    expect(parse('\${VAR:-x}\n').storedValue(), equals(const TemplateRef('VAR', 'x')));
    expect(parse('null').storedValue(), isNull);
    expect(parse('"s"').storedValue(), equals('s'));
    expect(parse('[1, 2]').storedValue(), equals([1, 2]));
  });

  test('unicode fixture decodes', () {
    final unicodeCase = PreservationCase.loadAll().firstWhere((c) => c.id == 'unicode');
    final value = parse(unicodeCase.inputText).storedValue()! as Map<String, Object?>;
    expect(value['ключ'], equals('значение — ✓ ünïcøde'));
    expect(value['multiline'], equals('first\nsecond'));
  });

  test('astral fixture keys and values survive the decode', () {
    final astralCase = PreservationCase.loadAll().firstWhere((c) => c.id == 'astral_emoji');
    final value = parse(astralCase.inputText).storedValue()! as Map<String, Object?>;
    expect(value['rocket \u{1F680} key'], equals('lift \u{1F680} \u{1F680}'));
    expect(value['plain'], equals(1));
  });
}
