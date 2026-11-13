part of 'json5.dart';

/// Localized, source-preserving edits over a parsed document
/// (SPEC.md amendments 3 and 8).
///
/// Every operation returns the full source text after the edit and never
/// touches the document it was created from, so a rejected or dry-run
/// operation cannot change a byte. The observable results — the text each
/// operation produces, which comments travel with a node, and when a
/// preservation conflict is refused — match the executed Python baseline and
/// are pinned by `fixtures/python_compat/operations/`. The algorithms and data
/// structures here are Dart-native (SPEC.md amendments 24 and 30).
final class _Editor {
  /// Creates an editor over the parsed [document].
  _Editor(this.document);

  /// The document being edited; it is never mutated.
  final Json5Document document;

  String get _text => document.text;

  // -- applySet -----------------------------------------------------------

  /// Replaces the value at [pointer], or creates the key when its parent is
  /// an object that does not have it yet.
  ///
  /// [indentUnit] is accepted for contract parity with the baseline
  /// and is reserved: the baseline ignores it too, deriving all
  /// indentation from the surrounding source.
  String applySet(String pointer, String valueText, {String? indentUnit}) {
    final tokens = parsePointer(pointer);
    if (tokens.isEmpty) {
      throw Json5PathException('The root pointer is read-only in v1');
    }
    final fragment = _parseFragment(valueText);
    final (:parent, :token) = document.findParent(pointer);
    if (parent is ObjectNode) {
      final member = parent.member(token);
      if (member == null) return _createMember(parent, token, fragment);
      return _replaceNode(member.value, fragment, [
        ..._leadingOf(member),
        ..._midOf(member),
        ..._trailingOf(member),
      ], pointer);
    }
    if (parent is ArrayNode) {
      if (!isIndexToken(token)) {
        throw Json5PathException("Array index expected, got '$token' in '$pointer'");
      }
      final index = indexValue(token);
      if (index == null || index >= parent.items.length) {
        throw Json5PathException('Setting an array element requires an existing index');
      }
      final item = parent.items[index];
      return _replaceNode(item.value, fragment, [
        ..._leadingOf(item),
        ..._trailingOf(item),
      ], pointer);
    }
    throw Json5PathException("Path '$pointer' does not address a container");
  }

  // -- applyAdd -----------------------------------------------------------

  /// Appends one array item (the `-` token) or creates one object
  /// key, in the container's own layout.
  String applyAdd(String pointer, String valueText) {
    final tokens = parsePointer(pointer, allowAppend: true);
    if (tokens.isEmpty) {
      throw Json5PathException('The root pointer is read-only');
    }
    final fragment = _parseFragment(valueText);
    final container = document.find(textualParentPointer(pointer));
    if (tokens.last == appendMarker) {
      if (container is! ArrayNode) {
        throw Json5PathException("The append token '$appendMarker' requires an array");
      }
      return _appendItem(container, fragment);
    }
    if (container is! ObjectNode) {
      throw Json5PathException("Path '$pointer' does not address an object");
    }
    return _createMember(container, tokens.last, fragment);
  }

  // -- applyRemove --------------------------------------------------------

  /// Removes one array item or object member together with the comments it
  /// owns, keeping the comments of its container and neighbours.
  String applyRemove(String pointer) {
    final (:parent, :token) = document.findParent(pointer);
    if (parent is ArrayNode) {
      final index = _arrayIndex(parent, token, pointer);
      final item = parent.items[index];
      final leading = _leadingOf(item);
      var start = _lineStartFor(_text, leading.isNotEmpty ? leading.first.span.startUnit : item.value.span.startUnit);
      var end = _itemEnd(item);
      final last = index == parent.items.length - 1;
      if (last && parent.items.length > 1) {
        start = _absorbPreviousSeparator(_text, start, parent.span.startUnit);
        return _splice(start, end, '');
      }
      if (item.comma != null) {
        end = item.comma!.span.startUnit + 1;
      } else if (!last) {
        end = _afterComma(_text, end);
      }
      final (from, to) = _tidyInline(_text, start, end);
      return _splice(from, _extendLine(_text, to), '');
    }
    if (parent is ObjectNode) {
      final member = parent.member(token);
      if (member == null) {
        throw Json5PathException("Missing object key '$token'");
      }
      final leading = _leadingOf(member);
      var start = _lineStartFor(_text, leading.isNotEmpty ? leading.first.span.startUnit : member.key.span.startUnit);
      var end = _memberEnd(member);
      var position = -1;
      for (var i = 0; i < parent.members.length; i++) {
        if (parent.members[i].label == token) {
          position = i;
          break;
        }
      }
      final last = position == parent.members.length - 1;
      if (last && parent.members.length > 1) {
        start = _absorbPreviousSeparator(_text, start, parent.span.startUnit);
        return _splice(start, end, '');
      }
      if (member.comma != null) {
        end = member.comma!.span.startUnit + 1;
      } else if (!last) {
        end = _afterComma(_text, end);
      }
      final (from, to) = _tidyInline(_text, start, end);
      return _splice(from, _extendLine(_text, to), '');
    }
    throw Json5PathException("Path '$pointer' does not address a container");
  }

  // -- applyMove ----------------------------------------------------------

  /// Reorders one array item to [target], taking its comments with it and
  /// rebuilding the array in its own layout.
  ///
  /// As in the baseline, only the index token of [target] is used: the
  /// position is applied to the array that holds [source].
  String applyMove(String source, String target) {
    final (:parent, :token) = document.findParent(source);
    if (parent is! ArrayNode) {
      throw Json5PathException('Only array items can be moved');
    }
    final index = _arrayIndex(parent, token, source);
    final targetToken = document.findParent(target).token;
    final position = _arrayIndex(parent, targetToken, target, allowEnd: true);
    final blocks = [for (final item in parent.items) _blockOf(item)];
    final moved = blocks.removeAt(index);
    // A position past the end means "last", as a Python insert does.
    blocks.insert(position > blocks.length ? blocks.length : position, moved);

    final baseIndent = _baseIndentAt(_text, parent.span.startUnit);
    final body = _renderArrayBody(parent, blocks, baseIndent, _indentUnit(_text, parent));
    return _splice(parent.span.startUnit, parent.span.endUnit, body);
  }

  // -- applyRename --------------------------------------------------------

  /// Changes one object key in place. The value bytes and every
  /// comment are left exactly as they were; a rename is never remove plus
  /// add.
  String applyRename(String pointer, String newKey) {
    if (newKey.isEmpty) {
      throw Json5PathException('A new key is required');
    }
    final (:parent, :token) = document.findParent(pointer);
    if (parent is! ObjectNode) {
      throw Json5PathException("Path '$pointer' does not address an object key");
    }
    final member = parent.member(token);
    if (member == null) {
      throw Json5PathException("Missing object key '$token'");
    }
    if (newKey == token) return _text;
    if (parent.member(newKey) != null) {
      throw Json5PathException("Duplicate object key '$newKey'");
    }
    final keyText = isUnquotedKey(newKey) ? newKey : quoteKey(newKey);
    return _splice(member.key.span.startUnit, member.key.span.endUnit, keyText);
  }

  // -- value replacement ---------------------------------------------------

  /// Parses exactly one submitted value. A blank text is a path failure; an
  /// invalid one is rejected by the parser with its position.
  static Json5Document _parseFragment(String valueText) {
    if (_pyStrip(valueText).isEmpty) {
      throw Json5PathException('value_text must contain exactly one JSON5 value');
    }
    return Json5Document(valueText, origin: '<value_text>');
  }

  String _replaceNode(
          ValueNode old, Json5Document fragment, List<CommentNode> trivia, String pointer) =>
      _splice(old.span.startUnit, old.span.endUnit,
          _replacementText(old, fragment, fragment.root, trivia, pointer));

  /// The replacement text for one value, preserving attached comments.
  String _replacementText(ValueNode old, Json5Document fragment, ValueNode submitted,
      List<CommentNode> trivia, String pointer) {
    final oldKind = _kindOf(old);
    final newKind = _kindOf(submitted);
    if (oldKind == _Kind.object && newKind == _Kind.object) {
      return _objectReplacement(old as ObjectNode, fragment, submitted as ObjectNode, pointer);
    }
    if (oldKind == _Kind.array && newKind == _Kind.array) {
      return _arrayReplacement(old as ArrayNode, fragment, submitted as ArrayNode, pointer);
    }
    if (oldKind != newKind && (trivia.isNotEmpty || _commentedInside(old))) {
      throw Json5CommentConflictException(
          'Replacing the commented value at $pointer with a different structural '
          'type would detach its comments');
    }
    return _reindent(submitted.toSource(), _continuationIndent(old));
  }

  String _objectReplacement(ObjectNode old, Json5Document fragment, ObjectNode submitted,
      String pointer) {
    final oldText = old.toSource();
    if (!_commentedInside(old)) {
      return _reindent(submitted.toSource(), _continuationIndent(old));
    }
    final keepComma = old.members.isNotEmpty && old.members.last.comma != null;
    final oldMembers = {for (final member in old.members) member.label: member};
    final chunks = <String>[];
    final used = <String>{};
    final lastIndex = submitted.members.length - 1;
    for (var index = 0; index < submitted.members.length; index++) {
      final newMember = submitted.members[index];
      final comma = index == lastIndex && !keepComma ? '' : ',';
      final oldMember = oldMembers[newMember.label];
      if (oldMember == null || !_memberCommented(oldMember)) {
        chunks.add(_submittedChunk(fragment, newMember, comma));
        continue;
      }
      if (_kindOf(oldMember.value) != _kindOf(newMember.value)) {
        throw Json5CommentConflictException(
            "Cannot change the structural type of commented member "
            "'${newMember.label}' at $pointer");
      }
      used.add(newMember.label);
      chunks.add(_chunkWithOldComments(fragment, oldMember, newMember, comma));
    }
    final missing = [
      for (final entry in oldMembers.entries)
        if (_memberCommented(entry.value) && !used.contains(entry.key)) entry.key,
    ]..sort();
    if (missing.isNotEmpty) {
      throw Json5CommentConflictException(
          'Replacement drops commented members: ${missing.join(', ')}');
    }
    final multiline =
        oldText.contains('\n') || submitted.toSource().contains('\n');
    return _buildObjectBody(
      old,
      chunks,
      multiline,
      _baseIndentAt(_text, old.span.startUnit),
      _indentUnit(_text, old),
    );
  }

  String _arrayReplacement(
      ArrayNode old, Json5Document fragment, ArrayNode submitted, String pointer) {
    if (old.items.length != submitted.items.length) {
      final commented = old.items.any(_itemCommented) || _commentedInside(old);
      if (commented) {
        throw Json5CommentConflictException(
            'Changing the array length would remove, insert or reorder commented items');
      }
      return _reindent(submitted.toSource(), _continuationIndent(old));
    }
    // Element-wise: each submitted value replaces the
    // old item at the same position, and the array's own text is
    // rebuilt locally. (The baseline now does the same; report A1 in
    // the frozen handoff notes was fixed in `d4adb45`.)
    final edits = <(int, int, String)>[];
    for (var i = 0; i < old.items.length; i++) {
      final oldItem = old.items[i];
      final replacement = _replacementText(oldItem.value, fragment, submitted.items[i].value, [
        ..._leadingOf(oldItem),
        ..._trailingOf(oldItem),
      ], pointer);
      edits.add((oldItem.value.span.startUnit, oldItem.value.span.endUnit, replacement));
    }
    final offset = old.span.startUnit;
    edits.sort((a, b) => b.$1.compareTo(a.$1));
    var result = old.toSource();
    for (final (start, end, replacement) in edits) {
      result = result.substring(0, start - offset) +
          replacement +
          result.substring(end - offset);
    }
    return result;
  }

  // -- structural creation -------------------------------------------------

  String _createMember(ObjectNode parent, String label, Json5Document fragment) {
    if (parent.members.any((member) => member.label == label)) {
      throw Json5PathException("Duplicate object key '$label'");
    }
    final submitted = fragment.root;
    final keyText = isUnquotedKey(label) ? label : quoteKey(label);
    final baseIndent = _baseIndentAt(_text, parent.span.startUnit);
    final multiline = parent.toSource().contains('\n');
    final unit = _indentUnit(_text, parent);
    final valueText = _reindent(submitted.toSource(), '$baseIndent$unit');
    if (multiline) {
      final entry = '${_innerIndent(parent, baseIndent, unit)}$keyText: $valueText';
      if (parent.members.isEmpty) {
        final at = _afterOpen(parent);
        return _splice(at, at, '\n$entry');
      }
      final last = parent.members.last;
      if (last.comma == null) {
        return _appendAfterUnseparated(
          valueEnd: last.value.span.endUnit,
          entryEnd: _memberEnd(last),
          gap: '\n',
          entry: entry,
        );
      }
      final at = _max(last.comma!.span.startUnit + 1, _memberEnd(last));
      return _splice(at, at, '\n$entry,');
    }
    final entry = '$keyText: $valueText';
    if (parent.members.isEmpty) {
      return _splice(parent.span.startUnit + 1, parent.span.endUnit - 1, entry);
    }
    final last = parent.members.last;
    if (last.comma != null) {
      // The container already ends in a comma: the new
      // member joins directly after the previous value and the trailing
      // comma stays the container's last separator.
      return _splice(last.value.span.endUnit, last.value.span.endUnit, ', $entry');
    }
    return _appendAfterUnseparated(
      valueEnd: last.value.span.endUnit,
      entryEnd: _memberEnd(last),
      gap: ' ',
      entry: entry,
    );
  }

  /// Appends one entry after a last entry that carries no separator comma.
  ///
  /// The comma goes directly after the previous value: the accepted dialect
  /// takes no whitespace or comment before a separator, so placing it after the
  /// trailing trivia - what the baseline does - produces source that neither
  /// engine can re-parse (report A9, SPEC.md amendment 38). The new entry lands
  /// after that trivia, so existing comment ownership is preserved.
  String _appendAfterUnseparated({
    required int valueEnd,
    required int entryEnd,
    required String gap,
    required String entry,
  }) {
    final withComma = _splice(valueEnd, valueEnd, ',');
    final at = entryEnd + 1;
    return withComma.substring(0, at) + gap + entry + withComma.substring(at);
  }

  String _appendItem(ArrayNode parent, Json5Document fragment) {
    final baseIndent = _baseIndentAt(_text, parent.span.startUnit);
    final unit = _indentUnit(_text, parent);
    final multiline = parent.toSource().contains('\n');
    final block = _reindent(fragment.root.toSource(), '$baseIndent$unit');
    if (!multiline) {
      if (parent.items.isEmpty) {
        return _splice(parent.span.startUnit + 1, parent.span.endUnit - 1, block);
      }
      // Same rule as object creation: the comma follows the last value
      // directly, so an inline `[1, 2 ]` grows to `[1, 2, 3 ]`
      // instead of the baseline's unparseable `[1, 2 , 3]` (report A9).
      final last = parent.items.last;
      if (last.comma != null) {
        return _splice(last.value.span.endUnit, last.value.span.endUnit, ', $block');
      }
      return _appendAfterUnseparated(
        valueEnd: last.value.span.endUnit,
        entryEnd: _itemEnd(last),
        gap: ' ',
        entry: block,
      );
    }
    final entryIndent = _innerIndent(parent, baseIndent, unit);
    final keepComma = parent.items.isNotEmpty &&
        _hasTrailingComma(_text, _itemEnd(parent.items.last));
    final entry = entryIndent + block;
    if (parent.items.isEmpty) {
      final at = _afterOpen(parent);
      return _splice(at, at, '\n$entry${keepComma ? ',' : ''}');
    }
    final last = parent.items.last;
    if (last.comma != null) {
      // Insert after the item and its comments so trailing trivia stays put.
      final at = _max(last.comma!.span.startUnit + 1, _itemEnd(last));
      return _splice(at, at, '\n$entry,');
    }
    return _appendAfterUnseparated(
      valueEnd: last.value.span.endUnit,
      entryEnd: _itemEnd(last),
      gap: '\n',
      entry: entry,
    );
  }

  String _renderArrayBody(
      ArrayNode parent, List<(String, String)> blocks, String baseIndent, String unit) {
    final keepComma = parent.items.isNotEmpty &&
        _hasTrailingComma(_text, _itemEnd(parent.items.last));
    final opening = _baselineOpeningOf(parent);
    final blockEnd = _blockEndOf(parent);
    if (blocks.isEmpty) {
      if (opening.isEmpty && blockEnd.isEmpty) return '[]';
      return _renderArrayTail(parent, baseIndent, unit);
    }
    if (!parent.toSource().contains('\n')) {
      // An inline array keeps its inline layout.
      final lastIndex = blocks.length - 1;
      final parts = <String>[
        for (var index = 0; index < blocks.length; index++)
          _withSeparator(blocks[index], keepComma && index == lastIndex),
      ];
      final openingText =
          opening.isEmpty ? '' : '${[for (final c in opening) c.text].join(' ')} ';
      final tail = blockEnd.isEmpty
          ? ''
          : ' ${[for (final c in blockEnd) c.text].join(' ')}';
      return '[$openingText${parts.join(', ')}$tail]';
    }
    final entryIndent = _innerIndent(parent, baseIndent, unit);
    final lines = <String>['['];
    if (opening.isNotEmpty) {
      lines.last += ' ${[for (final c in opening) c.text].join(' ')}';
    }
    for (var index = 0; index < blocks.length; index++) {
      final last = index == blocks.length - 1;
      final rendered = _withSeparator(blocks[index], keepComma || !last);
      lines.add([for (final line in rendered.split('\n')) '$entryIndent$line'].join('\n'));
    }
    for (final comment in blockEnd) {
      lines.add('$entryIndent${comment.text}');
    }
    lines.add('$baseIndent]');
    return lines.join('\n');
  }

  String _renderArrayTail(ArrayNode parent, String baseIndent, String unit) {
    final entryIndent = baseIndent + unit;
    final lines = <String>['['];
    for (final comment in _blockEndOf(parent)) {
      lines.add('$entryIndent${comment.text}');
    }
    lines.add('$baseIndent]');
    return lines.join('\n');
  }

  // -- comment ownership --------------------------------------------

  bool _memberCommented(MemberNode member) =>
      _leadingOf(member).isNotEmpty ||
      _midOf(member).isNotEmpty ||
      _trailingOf(member).isNotEmpty ||
      _commentedInside(member.value);

  bool _itemCommented(ItemNode item) =>
      _leadingOf(item).isNotEmpty ||
      _trailingOf(item).isNotEmpty ||
      _commentedInside(item.value);

  /// Comments the baseline treats as attached to a node, as
  /// opposed to the Dart tree roles; see [Json5Document] ownership notes.
  List<CommentNode> _leadingOf(CstNode entry) => entry.ownedComments(CommentRole.leading);
  List<CommentNode> _midOf(CstNode entry) => entry.ownedComments(CommentRole.mid);
  List<CommentNode> _trailingOf(CstNode entry) => entry.ownedComments(CommentRole.trailing);
  List<CommentNode> _blockEndOf(CstNode container) =>
      container.ownedComments(CommentRole.blockEnd);

  /// The baseline's `opening_comments` set: empty for every nested container
  /// (those comments are owned by the entry that holds the value) and, for the
  /// root, only the comments that physically sit inside the
  /// root container. A comment before the root value
  /// (a document comment) is not an opening comment of the
  /// container, so a rebuild of the container does not re-emit it.
  /// The upstream baseline applied the same offset filter after
  /// report A2 in `local_aiset_python_notes_1.md`.
  List<CommentNode> _baselineOpeningOf(CstNode container) {
    final all = identical(container, document.root)
        ? document.documentComments
        : const <CommentNode>[];
    return [
      for (final c in all)
        if (c.span.startUnit > container.span.startUnit) c,
    ];
  }

  static bool _commentedInside(CstNode node) => node.comments.isNotEmpty;

  // -- member rendering ------------------------------------------------

  String _submittedChunk(Json5Document fragment, MemberNode member, String comma) {
    final value = _deindent(
      member.value.toSource(),
      _baseIndentAt(fragment.text, member.key.span.startUnit).length,
    ).split('\n');
    final mid = [for (final c in _midOf(member)) '${c.text} '].join();
    final trailing = [for (final c in _trailingOf(member)) ' ${c.text}'].join();
    value[0] = '${member.key.raw}: $mid${value[0]}';
    value[value.length - 1] = '${value[value.length - 1]}$comma$trailing';
    return [...[for (final c in _leadingOf(member)) c.text], ...value].join('\n');
  }

  String _chunkWithOldComments(
      Json5Document fragment, MemberNode oldMember, MemberNode newMember, String comma) {
    final submitted = newMember.value.toSource();
    final value = _deindent(
      submitted,
      _baseIndentAt(fragment.text, newMember.value.span.startUnit).length,
    ).split('\n');
    final mid = [
      for (final c in _keepOnlyAbsent(_midOf(oldMember), submitted)) '${c.text} '
    ].join();
    final trailing = [
      for (final c in _keepOnlyAbsent(_trailingOf(oldMember), submitted)) ' ${c.text}'
    ].join();
    value[0] = '${newMember.key.raw}: $mid${value[0]}';
    value[value.length - 1] = '${value[value.length - 1]}$comma$trailing';
    final lines = <String>[
      ...[for (final c in _leadingOf(newMember)) c.text],
      ...[
        for (final c in _keepOnlyAbsent(_leadingOf(oldMember), submitted)) c.text
      ],
      ...value,
    ];
    return lines.join('\n');
  }

  /// Re-attaches an original comment unless the submitted text
  /// already carries it, so a comment the client sent back is not duplicated.
  static List<CommentNode> _keepOnlyAbsent(List<CommentNode> comments, String submitted) => [
        for (final comment in comments)
          if (!submitted.contains(comment.text)) comment,
      ];

  String _buildObjectBody(ObjectNode old, List<String> chunks, bool multiline,
      String baseIndent, String unit) {
    if (!multiline) {
      final body = [
        for (final chunk in chunks) _pyStrip(chunk.replaceAll('\n', ' '))
      ].join(' ');
      return '{$body}';
    }
    final entryIndent = _innerIndent(old, baseIndent, unit);
    final lines = <String>['{'];
    for (final chunk in chunks) {
      lines.add([for (final line in chunk.split('\n')) '$entryIndent$line'].join('\n'));
    }
    for (final comment in _blockEndOf(old)) {
      lines.add('$entryIndent${comment.text}');
    }
    lines.add('$baseIndent}');
    return lines.join('\n');
  }

  // -- array item blocks ---------------------------------------------------

  /// Splits one array item into (value source, trailing comments). The
  /// item's own comma is excluded, so a rebuilt array can place the
  /// separator after the value and before any trailing comment.
  (String, String) _blockOf(ItemNode item) {
    final leading = _leadingOf(item);
    final start = leading.isNotEmpty ? leading.first.span.startUnit : item.value.span.startUnit;
    final value = _deindent(
      _text.substring(start, item.value.span.endUnit),
      _baseIndentAt(_text, start).length,
    );
    final comments = [for (final c in _trailingOf(item)) ' ${c.text}'].join();
    return (value, comments);
  }

  static String _withSeparator((String, String) block, bool needed) =>
      '${block.$1}${needed ? ',' : ''}${block.$2}';

  // -- spans and layout --------------------------------------------------

  String _splice(int start, int end, String replacement) =>
      _text.substring(0, start) + replacement + _text.substring(end);

  int _arrayIndex(ArrayNode parent, String token, String pointer, {bool allowEnd = false}) {
    if (!isIndexToken(token)) {
      throw Json5PathException("Array index expected, got '$token' in '$pointer'");
    }
    final index = indexValue(token);
    final limit = parent.items.length + (allowEnd ? 1 : 0);
    if (index == null || index >= limit) {
      throw Json5PathException("Array index out of range in '$pointer'");
    }
    return index;
  }

  int _afterOpen(CstNode container) {
    var offset = container.span.startUnit + 1;
    for (final comment in _baselineOpeningOf(container)) {
      offset = _max(offset, comment.span.endUnit);
    }
    return offset;
  }

  int _itemEnd(ItemNode item) {
    var offset = item.value.span.endUnit;
    for (final comment in _trailingOf(item)) {
      offset = _max(offset, comment.span.endUnit);
    }
    return offset;
  }

  int _memberEnd(MemberNode member) {
    var offset = member.value.span.endUnit;
    for (final comment in _trailingOf(member)) {
      offset = _max(offset, comment.span.endUnit);
    }
    return offset;
  }

  /// The indentation unit inferred from the source around [node].
  static String _indentUnit(String text, CstNode node) {
    final outer = _baseIndentAt(text, node.span.startUnit);
    int? innerOffset;
    if (node is ObjectNode && node.members.isNotEmpty) {
      innerOffset = node.members.first.key.span.startUnit;
    } else if (node is ArrayNode && node.items.isNotEmpty) {
      innerOffset = node.items.first.value.span.startUnit;
    }
    if (innerOffset != null) {
      final inner = _baseIndentAt(text, innerOffset);
      if (inner.startsWith(outer) && inner.length > outer.length) {
        final tail = inner.substring(outer.length);
        return tail.isEmpty ? '  ' : tail;
      }
    }
    return '  ';
  }

  String _continuationIndent(ValueNode node) =>
      _baseIndentAt(_text, node.span.startUnit) + _indentUnit(_text, node);

  /// Indentation of the first child of a block, derived from the source.
  String _innerIndent(CstNode parent, String baseIndent, String unit) {
    var indent = '';
    if (parent is ObjectNode && parent.members.isNotEmpty) {
      indent = _baseIndentAt(_text, parent.members.first.key.span.startUnit);
    } else if (parent is ArrayNode && parent.items.isNotEmpty) {
      final first = parent.items.first;
      final leading = _leadingOf(first);
      indent = _baseIndentAt(
          _text, leading.isNotEmpty ? leading.first.span.startUnit : first.value.span.startUnit);
    }
    return indent.isEmpty ? baseIndent + unit : indent;
  }
}

// -- text utilities ------------------------------------------------------

/// The structural kind a replacement compares: containers stay distinct from
/// every scalar form.
enum _Kind { object, array, scalar }

_Kind _kindOf(CstNode node) => switch (node) {
      ObjectNode() => _Kind.object,
      ArrayNode() => _Kind.array,
      _ => _Kind.scalar,
    };

/// Leading spaces and tabs of the line that contains [offset].
String _baseIndentAt(String text, int offset) {
  final start = _lastNewlineBefore(text, offset) + 1;
  final prefix = text.substring(start, offset);
  var end = 0;
  while (end < prefix.length && (prefix[end] == ' ' || prefix[end] == '\t')) {
    end++;
  }
  return prefix.substring(0, end);
}

/// The whole indentation prefix of the line containing [offset], when nothing
/// but whitespace precedes it there.
String _lineIndent(String text, int offset) {
  final start = _lastNewlineBefore(text, offset) + 1;
  final prefix = text.substring(start, offset);
  return _pyStrip(prefix).isEmpty ? prefix : '';
}

int _lastNewlineBefore(String text, int offset) {
  final limit = offset > text.length ? text.length : offset;
  return limit <= 0 ? -1 : text.lastIndexOf('\n', limit - 1);
}

/// Start of the line when only whitespace precedes [offset], else [offset].
int _lineStartFor(String text, int offset) {
  final lineStart = _lastNewlineBefore(text, offset) + 1;
  return _pyStrip(text.substring(lineStart, offset)).isEmpty ? lineStart : offset;
}

/// Swallows the rest of the line when only whitespace follows
/// [offset].
int _extendLine(String text, int offset) {
  final newline = text.indexOf('\n', offset);
  if (newline >= 0 && _pyStrip(text.substring(offset, newline)).isEmpty) {
    return newline + 1;
  }
  return offset;
}

int _afterComma(String text, int offset) {
  var probe = offset;
  while (probe < text.length && (text[probe] == ' ' || text[probe] == '\t')) {
    probe++;
  }
  return probe < text.length && text[probe] == ',' ? probe + 1 : offset;
}

bool _hasTrailingComma(String text, int offset) => _afterComma(text, offset) > offset;

/// Removes the separator space left behind by an inline removal.
int _absorbPreviousSpace(String text, int start) {
  if (start <= 0 || text[start - 1] != ' ') return start;
  final previous = start >= 2 ? text[start - 2] : '';
  return previous == '[' || previous == ',' ? start - 1 : start;
}

/// Uses the comma before a removed last entry instead of leaving a gap.
int _absorbPreviousSeparator(String text, int start, int containerStart) {
  final region = text.substring(containerStart, start);
  final position = region.lastIndexOf(',');
  if (position < 0) return start;
  return _absorbPreviousSpace(text, containerStart + position);
}

/// Drops the separator space an inline removal leaves behind.
(int, int) _tidyInline(String text, int start, int end) {
  final from = _absorbPreviousSpace(text, start);
  var to = end;
  if (to < text.length &&
      text[to] == ' ' &&
      from > 0 &&
      (text[from - 1] == '[' || text[from - 1] == ',')) {
    to++;
  }
  return (from, to);
}

/// Shifts continuation lines so a spliced value matches its new location.
String _reindent(String source, String continuationIndent) {
  if (!source.contains('\n')) return source;
  final lines = source.split('\n');
  final firstIndent = _leadingBlankCount(lines[0]);
  final delta = continuationIndent.length - firstIndent;
  final out = <String>[lines[0]];
  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];
    if (delta >= 0) {
      out.add(continuationIndent + line);
    } else {
      final strip = _min(-delta, _leadingBlankCount(line));
      out.add(line.substring(strip));
    }
  }
  return out.join('\n');
}

/// Removes up to [amount] leading whitespace characters from every line.
String _deindent(String source, int amount) {
  if (amount <= 0) return source;
  return [
    for (final line in source.split('\n')) line.substring(_leadingBlankCount(line).clamp(0, amount))
  ].join('\n');
}

int _leadingBlankCount(String line) {
  var count = 0;
  while (count < line.length) {
    final unit = line.codeUnitAt(count);
    if (unit != 0x20 && unit != 0x09) break;
    count++;
  }
  return count;
}

/// Strips the whitespace set the baseline's `str.strip()` uses, which is
/// wider than the Dart `trim()` set.
String _pyStrip(String source) =>
    source.replaceFirst(_pyLeading, '').replaceFirst(_pyTrailing, '');

final RegExp _pyLeading = RegExp('^[$_pyWhitespace]+');
final RegExp _pyTrailing = RegExp('[$_pyWhitespace]+\$');

/// Characters Python treats as whitespace when stripping.
const String _pyWhitespace =
    '\t\n\u000b\u000c\r \u001c\u001d\u001e\u001f\u0085\u00a0\u1680'
    '\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a'
    '\u2028\u2029\u202f\u205f\u3000';

int _max(int a, int b) => a > b ? a : b;
int _min(int a, int b) => a < b ? a : b;
