import 'dart:convert';

import 'package:aiset_core/aiset_core.dart';
import 'package:test/test.dart';

import 'fixtures_io.dart';

Iterable<CstNode> _allNodes(Json5Document document) => [
      ...document.leading,
      document.root,
      ...document.trailing,
    ].expand((node) => node.descendants);

void main() {
  test('ASCII-only text: byte and code-unit offsets coincide', () {
    final document = parse('{\n  "key": 1,\n  b: "two", // c\n}\n');
    for (final node in _allNodes(document)) {
      expect(node.span.startByte, equals(node.span.startUnit),
          reason: 'start mismatch for ${node.runtimeType}');
      expect(node.span.endByte, equals(node.span.endUnit),
          reason: 'end mismatch for ${node.runtimeType}');
    }
  });

  test('astral characters: byte and code-unit offsets differ correctly', () {
    const rocket = '\u{1F680}'; // 2 UTF-16 code units, 4 UTF-8 bytes
    final document = parse('{\n  "rocket $rocket": 1,\n  after: 2,\n}\n');
    final root = document.root as ObjectNode;
    expect(root.members, hasLength(2));

    final emojiKey = root.members.first.key;
    // The key token itself contains the emoji: 2 extra bytes over units.
    expect(emojiKey.span.lengthUnits + 2, equals(emojiKey.span.lengthBytes));

    final afterKey = root.members[1].key;
    // One astral character precedes this node: its byte offset is 2
    // larger than its code-unit offset. The two spaces are not conflated.
    expect(afterKey.span.startByte - afterKey.span.startUnit, equals(2));
    expect(afterKey.span.startByte, isNot(equals(afterKey.span.startUnit)));
    expect(document.sliceOf(afterKey), equals('after'));

    // The byte offsets address the encoded document exactly.
    final encoded = utf8.encode(document.text);
    final bytesOfAfter =
        utf8.decode(encoded.sublist(afterKey.span.startByte, afterKey.span.endByte));
    expect(bytesOfAfter, equals('after'));

    // And the code-unit offsets address the string exactly (already shown
    // by sliceOf); the two models stay distinct.
    expect(document.offsets.byteOf(afterKey.span.startUnit),
        equals(afterKey.span.startByte));
    expect(document.offsets.byteLength, equals(encoded.length));
  });

  test('multi-byte BMP characters shift bytes only', () {
    // 'ü', 'ï', 'ø' are one UTF-16 code unit but two UTF-8 bytes each.
    final document = parse('{ a: "ünïcøde", b: 1 }');
    final root = document.root as ObjectNode;
    final bKey = root.member('b')!.key;
    // Compare against dart:convert's encoder, an independent implementation
    // of the same mapping the OffsetMap computes arithmetically.
    final expectedBytes =
        utf8.encode(document.text.substring(0, bKey.span.startUnit)).length;
    expect(bKey.span.startByte, equals(expectedBytes));
    expect(bKey.span.startByte, greaterThan(bKey.span.startUnit));
  });

  test('BOM counts as 3 bytes and 1 code unit', () {
    final document = parse('\uFEFF{ a: 1 }');
    final root = document.root;
    expect(root.span.startUnit, equals(1));
    expect(root.span.startByte, equals(3));
  });

  for (final testCase in PreservationCase.loadAll()) {
    test('dual offsets agree with dart:convert: ${testCase.id}', () {
      final document = parse(testCase.inputText);
      List<int> encoded;
      try {
        encoded = utf8.encode(document.text);
      } on FormatException {
        // Lone surrogates have no UTF-8 encoding; the table still
        // counts them WTF-8 style, checked separately.
        return;
      }
      expect(document.offsets.byteLength, equals(encoded.length));
      for (final node in _allNodes(document)) {
        expect(node.span.startByte,
            equals(utf8.encode(document.text.substring(0, node.span.startUnit)).length),
            reason: 'start byte of ${node.runtimeType} in ${testCase.id}');
        expect(decodeUtf8PreserveBom(encoded.sublist(node.span.startByte, node.span.endByte)),
            equals(node.toSource()),
            reason: 'byte slice of ${node.runtimeType} in ${testCase.id}');
      }
    });
  }
}
