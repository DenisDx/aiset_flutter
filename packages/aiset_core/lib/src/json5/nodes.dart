part of 'json5.dart';

/// The comment syntax a [CommentNode] was written in.
enum CommentKind {
  /// `// ...` up to, but not including, the line break.
  line,

  /// `/* ... */`, possibly spanning lines.
  block,
}

/// The role a comment plays for the node that owns it.
///
/// The classification reproduces the observable ownership semantics of
/// the baseline engine: which comments belong to which member, item or
/// container when the owner is edited or removed.
enum CommentRole {
  /// Before the root value; owned by the document.
  documentLeading,

  /// After the root value; owned by the document.
  documentTrailing,

  /// On the same line right after the opening bracket of the
  /// root container; owned by that container. For a nested
  /// container these comments are re-owned as `trailing` of the member or
  /// item holding the value, matching the baseline.
  opening,

  /// Before a member key or an item value; owned by that entry.
  leading,

  /// Between a member's `:` and its value; owned by that member.
  mid,

  /// On the same line after a member/item value or comma, plus the
  /// opening comments of the entry's own container value; owned by the
  /// entry.
  trailing,

  /// Before a container's closing bracket; owned by the container.
  blockEnd,
}

/// The base class of every concrete-syntax-tree node.
///
/// The tree is lossless: the leaves ([WhitespaceNode], [CommentNode],
/// [TokenNode], [KeyNode] and the scalar value nodes) partition the
/// source text, and [toSource] of any node is derived from its children,
/// never from a stored copy of the document string.
sealed class CstNode {
  /// Creates a node covering [span].
  CstNode({required this.span});

  /// The exact source region this node covers, in both offset spaces.
  final SourceSpan span;

  /// The source text of this subtree, reconstructed from the tree itself.
  String toSource();

  /// The direct children of this node in source order. Leaves have none.
  List<CstNode> get children;

  /// This node and everything below it, in source order.
  Iterable<CstNode> get descendants sync* {
    yield this;
    for (final child in children) {
      yield* child.descendants;
    }
  }

  /// The comments inside this subtree, in source order.
  List<CommentNode> get comments =>
      descendants.whereType<CommentNode>().toList(growable: false);

  /// The comments owned by this node with the given [role], in source
  /// order.
  List<CommentNode> ownedComments(CommentRole role) => comments
      .where((c) => c.owner == this && c.role == role)
      .toList(growable: false);
}

/// A maximal run of source whitespace (including BOM and NBSP, exactly the
/// baseline whitespace set). Whitespace is a leaf so that no byte of the
/// input is unaccounted for.
final class WhitespaceNode extends CstNode {
  /// Creates a whitespace leaf with its exact [text].
  WhitespaceNode(this.text, {required super.span});

  /// The whitespace characters, verbatim.
  final String text;

  @override
  String toSource() => text;

  @override
  List<CstNode> get children => const [];
}

/// A source comment: a first-class node with an exact span, verbatim text
/// and an ownership classification assigned by the parser.
final class CommentNode extends CstNode {
  /// Creates a comment leaf; the parser attaches ownership afterwards.
  CommentNode(this.kind, this.text, {required super.span});

  /// Whether this is a `//` line or a `/* */` block comment.
  final CommentKind kind;

  /// The comment text verbatim, delimiters included.
  final String text;

  /// The role this comment plays, or `null` before the parser has attached
  /// it to an owner.
  CommentRole? get role => _role;
  CommentRole? _role;

  /// The document, entry or container that owns this comment, or `null`
  /// while unattached.
  Object? get owner => _owner;
  Object? _owner;

  /// Whether the comment text contains a line break (block comments may).
  bool get isMultiline => text.contains('\n') || text.contains('\r');

  @override
  String toSource() => text;

  @override
  List<CstNode> get children => const [];

  void _attach(CommentRole role, Object owner) {
    _role = role;
    _owner = owner;
  }

  @override
  String toString() => 'CommentNode(${kind.name}, ${_role?.name}, $span)';
}

/// A fixed punctuation token: `{`, `}`, `[`, `]`, `:` or `,`.
final class TokenNode extends CstNode {
  /// Creates a punctuation leaf with its single-character [text].
  TokenNode(this.text, {required super.span});

  /// The character, verbatim.
  final String text;

  @override
  String toSource() => text;

  @override
  List<CstNode> get children => const [];
}

/// The key of an object member, quoted or unquoted.
final class KeyNode extends CstNode {
  /// Creates a key leaf with its raw source [raw] and decoded [label].
  KeyNode(this.raw, this.label, {required this.quoted, required super.span});

  /// The key exactly as written, quotes included when quoted.
  final String raw;

  /// The decoded key text: escape-resolved for quoted keys, [raw] otherwise.
  final String label;

  /// Whether the key was written as a quoted string.
  final bool quoted;

  @override
  String toSource() => raw;

  @override
  List<CstNode> get children => const [];
}

/// The base class of values: scalars, templates and containers.
sealed class ValueNode extends CstNode {
  /// Creates a value node covering [span].
  ValueNode({required super.span});

  /// Whether this subtree contains a placeholder or template.
  bool get hasTemplate;
}

/// A quoted string value.
final class StringNode extends ValueNode {
  /// Creates a string leaf.
  StringNode({
    required this.raw,
    required this.value,
    required this.hasPlaceholder,
    required super.span,
  });

  /// The string token exactly as written, quotes and escapes included.
  final String raw;

  /// The decoded string value.
  final String value;

  /// Whether the raw text contains at least one `${VAR}` or
  /// `${VAR:-default}` placeholder.
  final bool hasPlaceholder;

  @override
  bool get hasTemplate => hasPlaceholder;

  @override
  String toSource() => raw;

  @override
  List<CstNode> get children => const [];
}

/// A number value. [value] is an `int`, a `BigInt` (decimal or hex integer
/// beyond the 64-bit range) or a `double`, chosen from the raw form.
final class NumberNode extends ValueNode {
  /// Creates a number leaf.
  NumberNode({required this.raw, required this.value, required super.span});

  /// The number token exactly as written.
  final String raw;

  /// The parsed numeric value.
  ///
  /// TODO(S1-G): the bounded-integer policy (baseline `MAX_EXACT_INT`) is
  /// an open stage-1 decision; until it lands, integers that do not
  /// fit the Dart 64-bit `int` are kept exactly as `BigInt`.
  final Object value;

  @override
  bool get hasTemplate => false;

  @override
  String toSource() => raw;

  @override
  List<CstNode> get children => const [];
}

/// A `true`/`false` literal.
final class BooleanNode extends ValueNode {
  /// Creates a boolean leaf.
  BooleanNode({required this.raw, required this.value, required super.span});

  /// The literal exactly as written.
  final String raw;

  /// The decoded value.
  final bool value;

  @override
  bool get hasTemplate => false;

  @override
  String toSource() => raw;

  @override
  List<CstNode> get children => const [];
}

/// A `null` literal.
final class NullNode extends ValueNode {
  /// Creates a null leaf.
  NullNode({required this.raw, required super.span});

  /// The literal exactly as written.
  final String raw;

  @override
  bool get hasTemplate => false;

  @override
  String toSource() => raw;

  @override
  List<CstNode> get children => const [];
}

/// A bare `${VAR}` / `${VAR:-default}` placeholder used as a whole value.
final class TemplateNode extends ValueNode {
  /// Creates a template leaf.
  TemplateNode({
    required this.raw,
    required this.name,
    required this.defaultText,
    required super.span,
  });

  /// The token exactly as written.
  final String raw;

  /// The environment variable name.
  final String name;

  /// The default text after `:-`, or `null` when the token has no `:-` part.
  /// An explicit empty default (`${VAR:-}`) is the empty string, not `null`.
  final String? defaultText;

  /// The placeholder as a value object.
  TemplateRef get reference => TemplateRef(name, defaultText);

  @override
  bool get hasTemplate => true;

  @override
  String toSource() => raw;

  @override
  List<CstNode> get children => const [];
}

/// An object value: `{` members `}` with the trivia between and around
/// them kept in ordered child lists.
final class ObjectNode extends ValueNode {
  /// Creates an object node.
  ObjectNode({
    required this.open,
    required this.afterOpen,
    required List<MemberNode> members,
    required this.beforeClose,
    required this.close,
    required super.span,
  }) : _members = members {
    for (final member in members) {
      member._parent = this;
    }
  }

  /// The `{` token.
  final TokenNode open;

  /// Whitespace and opening comments right after `{`, in source order.
  final List<CstNode> afterOpen;

  /// The members in source order.
  List<MemberNode> get members => _members;
  final List<MemberNode> _members;

  /// Whitespace and block-end comments before `}`, in source order.
  final List<CstNode> beforeClose;

  /// The `}` token.
  final TokenNode close;

  /// The member with this exact [label], or `null`.
  MemberNode? member(String label) {
    for (final member in _members) {
      if (member.label == label) return member;
    }
    return null;
  }

  @override
  bool get hasTemplate => members.any((m) => m.value.hasTemplate);

  @override
  String toSource() {
    final buffer = StringBuffer()..write(open.toSource());
    for (final node in afterOpen) {
      buffer.write(node.toSource());
    }
    for (final member in _members) {
      buffer.write(member.toSource());
    }
    for (final node in beforeClose) {
      buffer.write(node.toSource());
    }
    buffer.write(close.toSource());
    return buffer.toString();
  }

  @override
  List<CstNode> get children => [
        open,
        ...afterOpen,
        ..._members,
        ...beforeClose,
        close,
      ];
}

/// An array value: `[` items `]` with all trivia retained.
final class ArrayNode extends ValueNode {
  /// Creates an array node.
  ArrayNode({
    required this.open,
    required this.afterOpen,
    required List<ItemNode> items,
    required this.beforeClose,
    required this.close,
    required super.span,
  }) : _items = items {
    for (final item in items) {
      item._parent = this;
    }
  }

  /// The `[` token.
  final TokenNode open;

  /// Whitespace and opening comments right after `[`, in source order.
  final List<CstNode> afterOpen;

  /// The items in source order.
  List<ItemNode> get items => _items;
  final List<ItemNode> _items;

  /// Whitespace and block-end comments before `]`, in source order.
  final List<CstNode> beforeClose;

  /// The `]` token.
  final TokenNode close;

  @override
  bool get hasTemplate => items.any((i) => i.value.hasTemplate);

  @override
  String toSource() {
    final buffer = StringBuffer()..write(open.toSource());
    for (final node in afterOpen) {
      buffer.write(node.toSource());
    }
    for (final item in _items) {
      buffer.write(item.toSource());
    }
    for (final node in beforeClose) {
      buffer.write(node.toSource());
    }
    buffer.write(close.toSource());
    return buffer.toString();
  }

  @override
  List<CstNode> get children => [
        open,
        ...afterOpen,
        ..._items,
        ...beforeClose,
        close,
      ];
}

/// One `key: value` pair with its comma and owned trivia.
final class MemberNode extends CstNode {
  /// Creates a member node; the parser sets the parent link.
  MemberNode({
    required this.leadingTrivia,
    required this.key,
    required this.colon,
    required this.midTrivia,
    required this.value,
    required this.comma,
    required this.trailingTrivia,
    required super.span,
  });

  /// Whitespace and leading comments before the key, in source order.
  final List<CstNode> leadingTrivia;

  /// The key token.
  final KeyNode key;

  /// The `:` token; the baseline grammar allows no gap between the key and
  /// the colon.
  final TokenNode colon;

  /// Whitespace and mid comments between `:` and the value, in source order.
  final List<CstNode> midTrivia;

  /// The value node.
  final ValueNode value;

  /// The `,` token immediately after the value, or `null` when the member has
  /// no comma (the baseline grammar only accepts a comma directly after the
  /// value token).
  final TokenNode? comma;

  /// Whitespace and same-line trailing comments after the value/comma, in
  /// source order.
  final List<CstNode> trailingTrivia;

  /// The object holding this member, or `null` after [detach].
  ObjectNode? get parent => _parent;
  ObjectNode? _parent;

  /// The decoded key text.
  String get label => key.label;

  /// Comments owned by this member as leading comments.
  List<CommentNode> get leadingComments => ownedComments(CommentRole.leading);

  /// Comments owned by this member between `:` and the value.
  List<CommentNode> get midComments => ownedComments(CommentRole.mid);

  /// Comments owned by this member as trailing comments, in source order;
  /// includes the opening comments of this member's own container value.
  List<CommentNode> get trailingComments => ownedComments(CommentRole.trailing);

  /// Removes this member from its parent object's CST.
  ///
  /// The comments this member owns (leading, mid and trailing, including the
  /// re-owned opening comments of its container value) leave the tree with
  /// it; comments owned by the parent container (opening, block-end) or by
  /// other entries stay. This is the tree-level ownership semantic;
  /// byte-level source splices for removal are stage S1-E work.
  void detach() {
    _parent?._members.remove(this);
    _parent = null;
  }

  @override
  String toSource() {
    final buffer = StringBuffer();
    for (final node in leadingTrivia) {
      buffer.write(node.toSource());
    }
    buffer.write(key.toSource());
    buffer.write(colon.toSource());
    for (final node in midTrivia) {
      buffer.write(node.toSource());
    }
    buffer.write(value.toSource());
    buffer.write(comma?.toSource() ?? '');
    for (final node in trailingTrivia) {
      buffer.write(node.toSource());
    }
    return buffer.toString();
  }

  @override
  List<CstNode> get children => [
        ...leadingTrivia,
        key,
        colon,
        ...midTrivia,
        value,
        ?comma,
        ...trailingTrivia,
      ];
}

/// One array element with its comma and owned trivia.
final class ItemNode extends CstNode {
  /// Creates an item node; the parser sets the parent link.
  ItemNode({
    required this.leadingTrivia,
    required this.value,
    required this.comma,
    required this.trailingTrivia,
    required super.span,
  });

  /// Whitespace and leading comments before the value, in source order.
  final List<CstNode> leadingTrivia;

  /// The value node.
  final ValueNode value;

  /// The `,` token immediately after the value, or `null`.
  final TokenNode? comma;

  /// Whitespace and same-line trailing comments after the value/comma.
  final List<CstNode> trailingTrivia;

  /// The array holding this item, or `null` after [detach].
  ArrayNode? get parent => _parent;
  ArrayNode? _parent;

  /// Comments owned by this item as leading comments.
  List<CommentNode> get leadingComments => ownedComments(CommentRole.leading);

  /// Comments owned by this item as trailing comments, including the re-owned
  /// opening comments of the item's own container value.
  List<CommentNode> get trailingComments => ownedComments(CommentRole.trailing);

  /// Removes this item from its parent array's CST, taking its owned comments
  /// with it (see [MemberNode.detach]).
  void detach() {
    _parent?._items.remove(this);
    _parent = null;
  }

  @override
  String toSource() {
    final buffer = StringBuffer();
    for (final node in leadingTrivia) {
      buffer.write(node.toSource());
    }
    buffer.write(value.toSource());
    buffer.write(comma?.toSource() ?? '');
    for (final node in trailingTrivia) {
      buffer.write(node.toSource());
    }
    return buffer.toString();
  }

  @override
  List<CstNode> get children => [
        ...leadingTrivia,
        value,
        ?comma,
        ...trailingTrivia,
      ];
}
