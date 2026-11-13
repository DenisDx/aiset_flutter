import 'package:aiset_core/aiset_core.dart';
import 'package:test/test.dart';

import 'fixtures_io.dart';

/// Collects the leaves (nodes without children) of a subtree in source order.
List<CstNode> _leaves(Iterable<CstNode> roots) {
  final out = <CstNode>[];
  void walk(CstNode node) {
    if (node.children.isEmpty) {
      out.add(node);
    } else {
      for (final child in node.children) {
        walk(child);
      }
    }
  }

  for (final root in roots) {
    walk(root);
  }
  return out;
}

void main() {
  final cases = PreservationCase.loadAll();

  for (final testCase in cases) {
    test('lossless leaf partition: ${testCase.id}', () {
      final document = parse(testCase.inputText);
      final text = testCase.inputText;
      final leaves = _leaves([...document.leading, document.root, ...document.trailing]);

      expect(leaves, isNotEmpty);
      expect(leaves.first.span.startUnit, 0, reason: 'text before the first leaf');
      var cursor = 0;
      final buffer = StringBuffer();
      for (final leaf in leaves) {
        expect(leaf.span.startUnit, cursor,
            reason: 'gap or overlap before leaf at $cursor (${leaf.toSource().isEmpty ? 'empty' : 'text'})');
        buffer.write(leaf.toSource());
        cursor = leaf.span.endUnit;
      }
      expect(cursor, text.length, reason: 'text after the last leaf');
      expect(buffer.toString(), equals(text),
          reason: 'leaf concatenation must reproduce the source');

      // Every comment is a leaf exactly once and carries ownership.
      final commentLeaves = leaves.whereType<CommentNode>().toList();
      expect(commentLeaves, hasLength(document.comments.length));
      for (final comment in document.comments) {
        expect(comment.role, isNotNull, reason: 'unclassified comment: ${comment.text}');
        expect(comment.owner, isNotNull, reason: 'unowned comment: ${comment.text}');
      }
    });

    test('node spans slice consistently: ${testCase.id}', () {
      final document = parse(testCase.inputText);
      final nodes = [
        ...document.leading,
        document.root,
        ...document.trailing,
      ].expand((n) => n.descendants).toList();
      for (final node in nodes) {
        expect(document.sliceOf(node), equals(node.toSource()),
            reason: 'span of ${node.runtimeType} does not match its subtree text');
      }
    });
  }
}
