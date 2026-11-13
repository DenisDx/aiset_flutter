part of 'json5.dart';

/// A parsed, source-preserving JSON5 document.
///
/// The instance keeps the original text for slicing and error
/// positions, but [toSource] is rebuilt from the CST, which makes the
/// losslessness of the tree observable rather than assumed.
final class Json5Document {
  /// Parses [text] into a lossless CST.
  ///
  /// [origin] labels the source of the text in error messages.
  /// Throws [Json5ParseException] when the text is not a single valid
  /// JSON5/template value; an unsupported token is never silently
  /// normalized.
  factory Json5Document(String text, {String origin = '<memory>'}) =>
      _Parser(text, origin).run();

  Json5Document._({
    required this.text,
    required this.origin,
    required this.offsets,
    required this.leading,
    required this.root,
    required this.trailing,
  });

  /// The original source text, verbatim.
  final String text;

  /// Label of where the text came from, used in errors.
  final String origin;

  /// The UTF-16-to-UTF-8 offset mapping for this text.
  final OffsetMap offsets;

  /// Whitespace and document comments before the root value, in source order.
  final List<CstNode> leading;

  /// The root value node.
  final ValueNode root;

  /// Whitespace and comments after the root value, in source order.
  final List<CstNode> trailing;

  /// The whole input as a span in both offset spaces.
  SourceSpan get span => SourceSpan(0, text.length, 0, offsets.byteLength);

  /// Reconstructs the source from the CST. For a document produced by
  /// parsing, this equals [text] exactly.
  String toSource() {
    final buffer = StringBuffer();
    for (final node in leading) {
      buffer.write(node.toSource());
    }
    buffer.write(root.toSource());
    for (final node in trailing) {
      buffer.write(node.toSource());
    }
    return buffer.toString();
  }

  /// Every node of this document below the document itself, in source order.
  Iterable<CstNode> get descendants sync* {
    for (final node in leading) {
      yield* node.descendants;
    }
    yield* root.descendants;
    for (final node in trailing) {
      yield* node.descendants;
    }
  }

  /// Every comment in the document, in source order.
  List<CommentNode> get comments =>
      descendants.whereType<CommentNode>().toList(growable: false);

  /// Comments before the root value; they belong to the whole document.
  List<CommentNode> get documentComments =>
      comments.where((c) => c.role == CommentRole.documentLeading).toList(growable: false);

  /// Comments after the root value; they belong to the whole document.
  List<CommentNode> get trailingComments =>
      comments.where((c) => c.role == CommentRole.documentTrailing).toList(growable: false);

  /// The exact source slice covered by [node]: the value text of the
  /// baseline's `source_of`/`value_text` contract.
  String sliceOf(CstNode node) =>
      text.substring(node.span.startUnit, node.span.endUnit);

  /// The 1-based `(line, column)` of a code-unit offset, counting
  /// lines by `\n` exactly like the baseline.
  (int line, int column) lineCol(int unitOffset) => _lineCol(text, unitOffset);

  /// Decodes the stored value of [node] (default: the root) into plain
  /// Dart data, keeping placeholders explicit as [TemplateRef].
  ///
  /// Objects become insertion-ordered `Map<String, Object?>`, arrays
  /// `List<Object?>`, strings `String`, numbers `int`/`BigInt`/`double`,
  /// booleans `bool`, `null` literals `null`.
  Object? storedValue([CstNode? node]) {
    final target = node ?? root;
    switch (target) {
      case final TemplateNode t:
        return t.reference;
      case final StringNode s:
        return s.value;
      case final NumberNode n:
        return n.value;
      case final BooleanNode b:
        return b.value;
      case final NullNode _:
        return null;
      case final ObjectNode o:
        final map = <String, Object?>{};
        for (final member in o.members) {
          map[member.label] = storedValue(member.value);
        }
        return map;
      case final ArrayNode a:
        return [for (final item in a.items) storedValue(item.value)];
      default:
        throw ArgumentError('storedValue() needs a value node, got '
            '${target.runtimeType}');
    }
  }

  /// The format label of the subtree at [node]: `json5-template` when it
  /// carries a placeholder anywhere, `json5` otherwise.
  String formatOf(CstNode node) =>
      node is ValueNode && node.hasTemplate ? 'json5-template' : 'json5';

  // -- navigation ----------------------------------------------------------

  /// The value addressed by the JSON Pointer [pointer], or `null`
  /// when it is absent.
  ///
  /// Throws [Json5PathException] when the pointer is malformed, uses the
  /// append marker, or walks through a value that is not a container.
  ValueNode? find(String pointer) {
    ValueNode node = root;
    for (final token in parsePointer(pointer)) {
      if (node is ObjectNode) {
        final member = node.member(token);
        if (member == null) return null;
        node = member.value;
      } else if (node is ArrayNode) {
        if (!isIndexToken(token)) {
          throw Json5PathException(
              "Array index expected, got '$token' in '$pointer'");
        }
        final index = indexValue(token);
        if (index == null || index >= node.items.length) return null;
        node = node.items[index].value;
      } else {
        throw Json5PathException(
            "Path segment '$token' does not address a container in '$pointer'");
      }
    }
    return node;
  }

  /// The container addressed by all but the last token of
  /// [pointer], plus that last token.
  ///
  /// The returned container may be a scalar: callers that require a
  /// container report the same `BAD_REQUEST` the baseline does.
  /// Throws [Json5PathException] for the root pointer or a broken path.
  ({ValueNode parent, String token}) findParent(String pointer) {
    final tokens = parsePointer(pointer);
    if (tokens.isEmpty) {
      throw Json5PathException('The root pointer is read-only in v1');
    }
    var parent = root;
    for (final token in tokens.take(tokens.length - 1)) {
      if (parent is ObjectNode) {
        final member = parent.member(token);
        if (member == null) {
          throw Json5PathException("Missing object key '$token' in '$pointer'");
        }
        parent = member.value;
      } else if (parent is ArrayNode) {
        final index = indexValue(token);
        if (!isIndexToken(token) || index == null || index >= parent.items.length) {
          throw Json5PathException("Missing array index '$token' in '$pointer'");
        }
        parent = parent.items[index].value;
      } else {
        throw Json5PathException(
            "Path segment '$token' does not address a container in '$pointer'");
      }
    }
    return (parent: parent, token: tokens.last);
  }

  /// Every pointer present under [pointer], the given pointer included.
  List<String> paths([String pointer = '']) {
    final node = find(pointer);
    if (node == null) return const [];
    final out = <String>[pointer];
    void walk(String prefix, ValueNode current) {
      if (current is ObjectNode) {
        for (final member in current.members) {
          final child = '$prefix/${escapeToken(member.label)}';
          out.add(child);
          walk(child, member.value);
        }
      } else if (current is ArrayNode) {
        for (var index = 0; index < current.items.length; index++) {
          final child = '$prefix/$index';
          out.add(child);
          walk(child, current.items[index].value);
        }
      }
    }

    walk(pointer, node);
    return out;
  }

  /// The leading spaces and tabs of the line containing the code-unit
  /// offset [unitOffset].
  String baseIndentAt(int unitOffset) => _baseIndentAt(text, unitOffset);

  /// The indentation prefix of the line containing [unitOffset], or the
  /// empty string when something other than whitespace precedes it.
  String lineIndent(int unitOffset) => _lineIndent(text, unitOffset);

  // -- localized edits -------------------------------------------------------

  /// The source text after replacing the value at [pointer] with
  /// [valueText], or creating that key when its parent object lacks it.
  ///
  /// [valueText] must hold exactly one JSON5/template value and is
  /// spliced as written: a placeholder is never re-serialized. Every byte
  /// outside the replaced value stays identical, and comments keep their
  /// owner. [indentUnit] is accepted for contract parity with the baseline and
  /// is reserved: indentation is derived from the surrounding source.
  ///
  /// Throws [Json5PathException] for an unaddressable pointer or an
  /// invalid [valueText], [Json5ParseException] when [valueText] is not valid
  /// source, and [Json5CommentConflictException] when the replacement would
  /// detach comments. The document is unchanged in every
  /// one of those cases.
  String applySet(String pointer, String valueText, {String? indentUnit}) =>
      _Editor(this).applySet(pointer, valueText, indentUnit: indentUnit);

  /// The source text after appending one array item (the `-` token) or
  /// creating one object key, in the container's own layout and comma style.
  ///
  /// Throws [Json5PathException] when the pointer does not address a
  /// creatable position, and [Json5CommentConflictException] never: an add
  /// only inserts.
  String applyAdd(String pointer, String valueText) =>
      _Editor(this).applyAdd(pointer, valueText);

  /// The source text after removing one array item or object member together
  /// with the comments it owns. Comments owned by the container or by a
  /// neighbour stay.
  String applyRemove(String pointer) => _Editor(this).applyRemove(pointer);

  /// The source text after moving the array item at [source] to the
  /// position addressed by [target], carrying its comments along.
  ///
  /// As in the baseline only the index token of [target] is used: the position
  /// applies to the array that holds [source].
  String applyMove(String source, String target) =>
      _Editor(this).applyMove(source, target);

  /// The source text after renaming the object key at [pointer] to
  /// [newKey]. The value's original text and all comments are preserved
  /// byte-for-byte; a rename is never performed as remove plus add.
  String applyRename(String pointer, String newKey) =>
      _Editor(this).applyRename(pointer, newKey);
}

/// Failures of the JSON5/template source engine that carry one of the
/// stable error codes (SPEC.md amendment 26).
///
/// The exception hierarchy itself is tier 3 and Dart-native; the
/// [code] is the pinned observable part.
abstract interface class Json5SourceException implements Exception {
  /// The stable error code of this failure.
  String get code;

  /// Short human-readable reason.
  String get message;
}

/// A malformed JSON Pointer, an unaddressable path, or a rejected
/// operation argument.
final class Json5PathException implements Json5SourceException {
  /// Creates a path failure with reason [message].
  Json5PathException(this.message);

  @override
  final String message;

  @override
  String get code => 'BAD_REQUEST';

  @override
  String toString() => 'Json5PathException: $message';
}

/// A replacement that would detach the comments of the value it
/// replaces (SPEC.md amendment 3 write rule 6).
final class Json5CommentConflictException implements Json5SourceException {
  /// Creates a preservation-conflict failure with reason [message].
  Json5CommentConflictException(this.message);

  @override
  final String message;

  @override
  String get code => 'COMMENT_PRESERVATION_CONFLICT';

  @override
  String toString() => 'Json5CommentConflictException: $message';
}

/// An explicit `${VAR}` / `${VAR:-default}` placeholder kept
/// unresolved in the stored tree.
final class TemplateRef {
  /// Creates a placeholder reference.
  const TemplateRef(this.name, [this.defaultText]);

  /// The environment variable name.
  final String name;

  /// The default text after `:-`, or `null` when absent. An explicit empty
  /// default is the empty string.
  final String? defaultText;

  /// The canonical token text; a parsed document preserves the
  /// original bytes on the [TemplateNode] itself.
  String get sourceText =>
      defaultText == null ? '\${$name}' : '\${$name:-$defaultText}';

  @override
  bool operator ==(Object other) =>
      other is TemplateRef &&
      other.name == name &&
      other.defaultText == defaultText;

  @override
  int get hashCode => Object.hash(name, defaultText);

  @override
  String toString() => 'TemplateRef(name: $name, default: $defaultText)';
}

/// Parses [text] into a [Json5Document].
///
/// Shorthand for the document constructor, matching the baseline
/// `parse(text, *, origin)` contract.
Json5Document parse(String text, {String origin = '<memory>'}) =>
    Json5Document(text, origin: origin);

/// Rejection of invalid JSON5/template source, with the position in
/// both offset spaces plus the baseline's line/column convention.
final class Json5ParseException implements Json5SourceException {
  /// Creates a parse error at code-unit offset [offsetUnit] in [text].
  Json5ParseException({
    required this.message,
    required this.text,
    required this.offsets,
    required this.offsetUnit,
    required this.origin,
  })  : offsetByte =
            offsets.byteOf(offsetUnit > text.length ? text.length : offsetUnit),
        _lineColumn = _lineCol(text, offsetUnit);

  /// Short human-readable reason.
  @override
  final String message;

  /// The rejected source text.
  final String text;

  /// Offset mapping of the rejected text.
  final OffsetMap offsets;

  /// UTF-16 code-unit offset of the offending position.
  final int offsetUnit;

  /// UTF-8 byte offset of the offending position.
  final int offsetByte;

  final (int, int) _lineColumn;

  /// 1-based line number (lines counted by `\n`).
  int get line => _lineColumn.$1;

  /// 1-based column number.
  int get column => _lineColumn.$2;

  /// Label of the text source.
  final String origin;

  @override
  String get code => 'PARSE_ERROR';

  @override
  String toString() =>
      'Json5ParseException: $message (line $line, column $column) in $origin';
}

/// Baseline line/column convention: lines counted by `\n`, column 1-based
/// after the last `\n` strictly before the offset.
(int, int) _lineCol(String text, int unitOffset) {
  final clamped = unitOffset > text.length ? text.length : unitOffset;
  final line = '\n'.allMatches(text.substring(0, clamped)).length + 1;
  final lastNewline = clamped == 0 ? -1 : text.lastIndexOf('\n', clamped - 1);
  return (line, clamped - lastNewline);
}
