import 'package:aiset_core/aiset_core.dart';
import 'package:test/test.dart';

/// The postcondition of every accepted edit: the produced source re-parses
/// (SPEC.md amendment 3 write rules, `SPEC_.md` amendment 38).
///
/// The compatibility corpus pins the produced bytes; this suite pins the
/// invariant those bytes must satisfy. It is the check the Python baseline has
/// none of, and the reason its A1-A3 and A9 defects survived its own suite: the
/// operations returned successfully while handing back text the same library
/// could not read.
///
/// The pinned shapes below are separators next to trailing whitespace or a
/// trailing comment, in the inline and in the block layout. Since the re-baseline
/// to `d4adb45` the Python library handles the line-comment and
/// trailing-comma shapes correctly, but still
/// splices the comma after a block comment before a closing
/// terminator (`{ a: 1 /* c */ }`, `[\n 1 /* one */\n]`), producing source it cannot
/// read back. The Dart implementation puts the comma directly after the
/// previous value and the new entry after that trivia in every case, so the
/// comment keeps its owner and the text stays readable.
void main() {
  // Each entry: label, input, operation, pointer, value or target,
  // and the exact text the edit must produce.
  const edits = <(String, String, String, String, String?, String?)>[
    // -- inline object creation ---------------------------------------------
    ('inline, no trivia', '{ a: 1 }', 'set', '/b', '2', '{ a: 1, b: 2 }'),
    ('inline, space before the brace', '{ a: 1  }', 'set', '/b', '2', '{ a: 1, b: 2  }'),
    ('inline, trailing comma kept', '{ a: 1, }', 'set', '/b', '2',
        '{ a: 1, b: 2, }'),
    ('inline, trailing comment keeps its owner', '{ a: 1 /* c */ }', 'set', '/b', '2',
        '{ a: 1, /* c */ b: 2 }'),
    ('inline, last value is a container', '{ a: { x: 1 } }', 'add', '/b', '2',
        '{ a: { x: 1 }, b: 2 }'),
    ('inline, nested parent', '{ o: { a: 1 } }', 'set', '/o/b', '2', '{ o: { a: 1, b: 2 } }'),
    // -- inline array append -------------------------------------------------
    ('inline array, no trivia', '[1, 2]', 'add', '/-', '3', '[1, 2, 3]'),
    ('inline array, space before the bracket', '[1, 2 ]', 'add', '/-', '3', '[1, 2, 3 ]'),
    ('inline array, trailing comma kept', '[1, 2, ]', 'add', '/-', '3', '[1, 2, 3, ]'),
    ('inline array, trailing comment keeps its owner', '[1, 2 /* c */]', 'add', '/-', '3',
        '[1, 2, /* c */ 3]'),
    // -- block layout --------------------------------------------------------
    ('block, no comma and no trivia', '{\n  a: 1\n}', 'set', '/b', '2',
        '{\n  a: 1,\n  b: 2\n}'),
    ('block, no comma, line comment', '{\n  a: 1 // one\n}', 'set', '/b', '2',
        '{\n  a: 1, // one\n  b: 2\n}'),
    ('block, no comma, block comment', '{\n  a: 1 /* one */\n}', 'set', '/b', '2',
        '{\n  a: 1, /* one */\n  b: 2\n}'),
    ('block array, no comma, block comment', '[\n  1 /* one */\n]', 'add', '/-', '2',
        '[\n  1, /* one */\n  2\n]'),
    // -- the A1 corrections --------------------------------------------------
    ('equal-length array replacement is item-wise',
        '{\n  list: [\n    // first\n    "a",\n    "b", // second\n    "c",\n  ],\n}\n',
        'set', '/list', '["x", "y", "z"]',
        '{\n  list: [\n    // first\n    "x",\n    "y", // second\n    "z",\n  ],\n}\n'),
    ('nested equal-length array replacement is item-wise', '{\n  l: [[1], [2]],\n}\n',
        'set', '/l', '[[9], [8]]', '{\n  l: [[9], [8]],\n}\n'),
  ];

  group('an accepted edit produces source that re-parses', () {
    for (final (label, input, op, pointer, operand, expected) in edits) {
      test(label, () {
        final submitted = operand!;
        final document = parse(input);
        final produced = op == 'set'
            ? document.applySet(pointer, submitted)
            : document.applyAdd(pointer, submitted);
        if (expected != null) {
          expect(produced, equals(expected));
        }
        final reparsed = parse(produced);
        expect(reparsed.toSource(), equals(produced),
            reason: '$label: the produced text must round-trip');
        // The append marker is not a lookup token, so an appended
        // item is checked as the root array's last entry.
        final edited = pointer.endsWith('/-')
            ? (reparsed.root as ArrayNode).items.last.value
            : reparsed.find(pointer)!;
        expect(reparsed.storedValue(edited), equals(parse(submitted).storedValue()),
            reason: '$label: $pointer must hold the submitted value');
      });
    }

    test('every accepted operation over every authored document re-parses', () {
      // A sweep rather than a table: whatever the operation layer
      // accepts, the parser must accept again. A refused edit is not a
      // violation - it leaves the source byte-for-byte unchanged.
      const documents = <String>[
        '{ a: 1 }',
        '{ a: 1, }',
        '{ a: 1 /* c */ }',
        '{\n  a: 1,\n}\n',
        '{\n  // lead\n  a: 1, // trail\n  b: {\n    c: [1, 2],\n  },\n}\n',
        '[1, 2]',
        '[1, 2 ]',
        '[1, 2, ]',
        '[\n  1,\n  2\n  // end\n]\n',
        '{ list: [1, 2], other: { k: "v" } }',
        '{\r\n  a: 1,\r\n  list: [1, 2],\r\n}\r\n',
        '\u{FEFF}{ a: 1, list: [2] }\n',
        '{ emoji: "\u{1F680}", list: ["a", "b"] }',
      ];
      const operations = <(String, String, String?)>[
        ('set', '/a', '9'),
        ('set', '/b', '9'),
        ('set', '/list', '[7, 8]'),
        ('set', '/list/0', '7'),
        ('set', '/other', '{ deep: 1 }'),
        ('add', '/c', '3'),
        ('add', '/list/-', '4'),
        ('remove', '/a', null),
        ('remove', '/list/0', null),
        ('move', '/list/0', '/list/1'),
        ('rename', '/a', 'renamed'),
        ('rename', '/emoji', 'rocket'),
      ];
      var accepted = 0;
      for (final input in documents) {
        for (final (op, pointer, operand) in operations) {
          final document = parse(input);
          String produced;
          try {
            produced = switch (op) {
              'set' => document.applySet(pointer, operand!),
              'add' => document.applyAdd(pointer, operand!),
              'remove' => document.applyRemove(pointer),
              'move' => document.applyMove(pointer, operand!),
              'rename' => document.applyRename(pointer, operand!),
              _ => throw StateError('unknown op $op'),
            };
          } on Json5SourceException {
            expect(document.text, equals(input),
                reason: 'a refused $op must not change its document');
            continue;
          }
          accepted++;
          final reason = '$op $pointer ${operand ?? ''} over "$input"';
          expect(parse(produced).toSource(), equals(produced), reason: reason);
        }
      }
      expect(accepted, greaterThan(60),
          reason: 'the sweep must accept enough edits to prove anything ($accepted)');
    });
  });
}
