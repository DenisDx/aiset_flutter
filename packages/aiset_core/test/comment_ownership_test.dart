import 'package:aiset_core/aiset_core.dart';
import 'package:test/test.dart';

import 'fixtures_io.dart';

List<String> _texts(List<CommentNode> comments) =>
    [for (final c in comments) c.text];

void main() {
  late PreservationCase ownershipCase;
  late PreservationCase mixedCase;
  late Json5Document ownership;
  late Json5Document mixed;

  setUpAll(() {
    ownershipCase = PreservationCase.loadAll().firstWhere((c) => c.id == 'comment_ownership');
    mixedCase = PreservationCase.loadAll().firstWhere((c) => c.id == 'mixed_types');
    ownership = parse(ownershipCase.inputText);
    mixed = parse(mixedCase.inputText);
  });

  group('baseline classification (mirrors the oracle test)', () {
    test('document comment before the root value', () {
      expect(ownership.documentComments, hasLength(1));
      expect(ownership.documentComments.single.text,
          equals('// Document comment (belongs to the whole document).'));
      expect(ownership.documentComments.single.owner, same(ownership));
    });

    test('element1 leading and trailing', () {
      final element1 = (ownership.root as ObjectNode).member('element1')!;
      expect(_texts(element1.leadingComments),
          equals(['// Leading comment for element1.']));
      expect(_texts(element1.trailingComments),
          equals(['// Trailing comment for element1.']));
      expect(element1.midComments, isEmpty);
    });

    test('element2 owns both trailing comments', () {
      final element2 = (ownership.root as ObjectNode).member('element2')!;
      // The comment right after the inner `{` is the container's opening
      // trivia but is owned as a trailing comment of the member,
      // exactly like the baseline; the comment after the inner `}`
      // joins it on the same line.
      expect(_texts(element2.trailingComments), equals([
        '// Trailing comment for element2.',
        "// Trailing comment for element2's closing brace.",
      ]));
      expect(element2.leadingComments, isEmpty);
    });

    test('inner members and block-end', () {
      final inner = (ownership.root as ObjectNode).member('element2')!.value as ObjectNode;
      final element3 = inner.member('element3')!;
      expect(_texts(element3.leadingComments), equals(['// Leading comment for element3.']));
      expect(_texts(element3.trailingComments), equals(['// Trailing comment for element3.']));
      final element4 = inner.member('element4')!;
      expect(_texts(element4.leadingComments), equals(['// Leading comment for element4.']));
      expect(_texts(element4.trailingComments), equals(['// Trailing comment for element4.']));
      expect(_texts(inner.ownedComments(CommentRole.blockEnd)),
          equals(['// Block-end comment for element2 (kept before the closing brace).']));
    });

    test('every comment is owned exactly once', () {
      for (final comment in ownership.comments) {
        expect(comment.role, isNotNull);
        expect(comment.owner, isNotNull);
      }
      // The union of per-owner views covers each comment exactly once.
      final owners = <Object>{
        ownership,
        ...ownership.descendants.where((n) => n is! CommentNode),
      };
      final owned = <CommentNode>[];
      for (final owner in owners) {
        if (owner is CstNode) {
          for (final role in CommentRole.values) {
            owned.addAll(owner.ownedComments(role));
          }
        } else if (owner is Json5Document) {
          owned.addAll(owner.documentComments);
          owned.addAll(owner.trailingComments);
        }
      }
      expect(owned, hasLength(ownership.comments.length));
      expect(owned.toSet(), hasLength(ownership.comments.length));
    });
  });

  group('mixed fixture trivia roles', () {
    test('leading comment on a quoted key', () {
      final root = mixed.root as ObjectNode;
      final quoted = root.member('single quoted')!;
      expect(_texts(quoted.leadingComments),
          equals(['// A quoted string with a placeholder and escapes.']));
      expect(quoted.key.quoted, isTrue);
      expect(quoted.key.raw, startsWith("'"));
    });

    test('block comment before a member is its leading trivia', () {
      final nested = (mixed.root as ObjectNode).member('nested')!.value as ObjectNode;
      final quotedKey = nested.member('quoted_key')!;
      expect(_texts(quotedKey.leadingComments),
          equals(['/* block comment inside an object */']));
    });

    test('array items keep leading and trailing comments', () {
      final nested = (mixed.root as ObjectNode).member('nested')!.value as ObjectNode;
      final list = nested.member('list')!.value as ArrayNode;
      expect(list.items, hasLength(3));
      expect(_texts(list.items[0].leadingComments), equals(['// First item.']));
      expect(_texts(list.items[1].trailingComments), equals(['// Second item.']));
      expect(_texts(list.items[2].leadingComments), isEmpty);
      // The "// Item object." comment is inside the third item's object,
      // leading for its `deep` member.
      final deep = (list.items[2].value as ObjectNode).member('deep')!;
      expect(_texts(deep.leadingComments), equals(['// Item object.']));
    });

    test('nested array member owns its leading comment', () {
      final nested = (mixed.root as ObjectNode).member('nested')!.value as ObjectNode;
      expect(_texts(nested.member('list')!.leadingComments),
          equals(['// Nested array with comments.']));
    });
  });

  group('removal keeps comments by ownership', () {
    test('detaching a member takes its owned comments and descendants', () {
      final root = ownership.root as ObjectNode;
      final element2 = root.member('element2')!;
      final ownedByElement2 = element2.comments.toSet();
      expect(ownedByElement2, hasLength(7)); // 2 own trailing + 5 inside

      element2.detach();

      expect(element2.parent, isNull);
      expect(root.member('element2'), isNull);
      // The detached subtree still carries every comment it owned.
      expect(element2.comments, hasLength(7));
      expect(element2.toSource(), contains('// Trailing comment for element2.'));
      expect(element2.toSource(), contains('// Leading comment for element3.'));
      expect(element2.toSource(),
          contains('// Block-end comment for element2 (kept before the closing brace).'));
      // The rest of the document keeps exactly the comments that were not
      // owned by the removed member.
      final remaining = ownership.comments.toSet();
      expect(remaining, hasLength(3));
      expect(_texts(remaining.toList()), unorderedEquals([
        '// Document comment (belongs to the whole document).',
        '// Leading comment for element1.',
        '// Trailing comment for element1.',
      ]));
      for (final comment in remaining) {
        expect(ownedByElement2, isNot(contains(comment)));
      }
    });

    test('detaching a member leaves the container block-end comment', () {
      final document = parse('{\n  a: 1,\n  // block end\n}\n');
      final root = document.root as ObjectNode;
      root.member('a')!.detach();
      expect(_texts(document.comments), equals(['// block end']));
      expect((document.root as ObjectNode).ownedComments(CommentRole.blockEnd), hasLength(1));
    });

    test('detaching an item leaves the next item leading comment', () {
      final document = parse('[\n  1, // trail of 1\n  // lead of 2\n  2,\n]\n');
      final array = document.root as ArrayNode;
      expect(_texts(array.items[0].trailingComments), equals(['// trail of 1']));
      expect(_texts(array.items[1].leadingComments), equals(['// lead of 2']));
      array.items[0].detach();
      expect(_texts(document.comments), equals(['// lead of 2']));
      expect(array.items, hasLength(1));
    });

    test('detaching an entry keeps comments owned by other entries', () {
      final document = parse('{\n  // lead a\n  a: 1, // trail a\n  // lead b\n  b: 2,\n}\n');
      final root = document.root as ObjectNode;
      root.member('a')!.detach();
      // Only b's leading comment survives; a's leading and trailing went with
      // the removed member.
      expect(_texts(document.comments), equals(['// lead b']));
    });
  });
}
