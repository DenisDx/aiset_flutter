part of 'pipeline.dart';

/// The authorization of one staged operation
/// (`SPEC.md` amendments 4, 7, 8 and 9, SEC-01).
///
/// Permissions and restrictions for `required`, `const`, `read_only`,
/// `secret` and fixed children carry over from the descriptor, and they are
/// checked against the document as it stands at that point in the batch, so an
/// operation cannot address a position a previous operation of the same batch
/// has not created.
///
/// Two kinds of refusal come out of this code and the difference is
/// observable:
///
/// * an [AisetVeto] is a problem with the operation itself — an undeclared
///   path, a key the grammar does not permit, a malformed pointer, a blank
///   `value_text`. The batch reports it as one `operation` issue naming the
///   operation's 1-based position, and the whole batch is refused.
/// * an [AisetFailure] is a denial of the actor's rights — `FORBIDDEN` for a
///   `required`/`const`/`read_only`/fixed node, `SECRET_ACCESS_DENIED` for a
///   secret subtree. That code is the answer of the whole call, because it is
///   about who is asking and not about what the document declares.
///
/// A batch that addresses a secret path is refused
/// whole and redacted: neither the issue list nor the audit
/// record repeats the submitted text
/// (`SPEC.md` amendments 6 and 26).
/// The reason one staged operation was refused.
///
/// [preservationConflict] marks the one refusal that must be answered with
/// `COMMENT_PRESERVATION_CONFLICT` rather than with a generic validation
/// error, so the UI can offer a re-serialization path instead of a
/// "wrong value" message (`SPEC.md` amendments 3 and 26).
final class AisetVeto implements Exception {
  /// Creates an operation refusal.
  AisetVeto(this.message, {this.preservationConflict = false});

  /// The short reason, reported inside the `operation` issue. It never
  /// contains a submitted value.
  final String message;

  /// Whether the refusal is a comment preservation conflict.
  final bool preservationConflict;

  @override
  String toString() => 'AisetVeto: $message';
}

/// Authorizes and applies one [operation] to [text].
///
/// [base] is the document the batch started from: it is what tells an edit of
/// an existing value apart from the creation of a new one, and what the
/// descendant-protection comparison reads the untouched source out of.
String _applyAuthorized(
  String text,
  Json5Document base,
  AisetOperation operation,
  AisetDocumentRegistration registration,
  Principal principal,
) {
  final descriptor = registration.descriptor;
  final document = Json5Document(text, origin: registration.documentId);
  if (operation.unknownName != null) {
    throw AisetVeto('Unknown operation \'${operation.unknownName}\'');
  }
  // The append token belongs to `add` and to nothing else: every other
  // operation naming `/…/-` is refused here, the same central rule
  // the executed baseline applies before an operation ever reaches a pointer
  // lookup (`SPEC.md` amendment 8).
  if (operation.kind != AisetOperationKind.add && operation.path.endsWith('/$appendMarker')) {
    throw AisetVeto('The append token is only valid for an add operation');
  }
  switch (operation.kind) {
    case AisetOperationKind.set:
      final valueText = _requireValueText(operation);
      _authorizeWrite(document, base, descriptor, operation.path, valueText, principal);
      return _splice(document, () => document.applySet(operation.path, valueText));

    case AisetOperationKind.add:
      _requireValueText(operation);
      _authorizeAdd(document, descriptor, operation.path, principal);
      return _splice(document, () => document.applyAdd(operation.path, operation.valueText!));

    case AisetOperationKind.remove:
      final (:parentPointer, :token) = splitPointer(operation.path);
      if (!addressesNode(document, operation.path)) {
        throw AisetVeto('Path \'${operation.path}\' does not exist');
      }
      final node = _governedNode(descriptor, operation.path,
          parentPointer: parentPointer, token: token);
      _authorizeRemoval(node, _parentNode(descriptor, parentPointer), operation.path,
          token: token, principal: principal);
      return _splice(document, () => document.applyRemove(operation.path));

    case AisetOperationKind.drop:
      _authorizeDrop(descriptor, document, operation.path, principal);
      return _splice(document, () => document.applyRemove(operation.path));

    case AisetOperationKind.move:
      _authorizeMove(descriptor, document, operation, principal);
      return _splice(
          document, () => document.applyMove(operation.from ?? '', operation.path));

    case AisetOperationKind.rename:
      return _applyRename(document, descriptor, principal, operation);
  }
}

String _applyRename(
  Json5Document document,
  CompiledDescriptor descriptor,
  Principal principal,
  AisetOperation operation,
) {
  final newKey = operation.to;
  final (:parentPointer, :token) = splitPointer(operation.path);
  if (!addressesNode(document, operation.path)) {
    throw AisetVeto('Path \'${operation.path}\' does not exist');
  }
  final parent = _nodeAtOrThrow(descriptor, parentPointer);
  if (parent.type != 'object') throw AisetVeto('Only object keys can be renamed');
  final node = descriptor.nodeAt(operation.path) ?? _arrayItemFallback(parent, token);
  if (node == null) {
    throw AisetVeto('Path \'${operation.path}\' is not declared by the descriptor');
  }
  // The node protections are answered before the argument check: the
  // executed baseline refuses a rename of a required/read-only/const/fixed
  // node with FORBIDDEN even when the `to` key is empty, so
  // the value of the rename never hides who is not allowed to do it.
  if (node.required) {
    throw AisetFailure(AisetErrorCode.forbidden,
        'Path \'${operation.path}\' is required and cannot be renamed');
  }
  if (node.readOnly) {
    throw AisetFailure(
        AisetErrorCode.forbidden, 'Path \'${operation.path}\' is read-only');
  }
  if (node.hasConst) {
    throw AisetFailure(
        AisetErrorCode.forbidden, 'Path \'${operation.path}\' has a fixed value');
  }
  if (parent.children != null &&
      parent.children!.containsKey(token) &&
      parent.additionalChildren == null) {
    throw AisetFailure(
        AisetErrorCode.forbidden, 'Path \'${operation.path}\' is a fixed declared child');
  }
  if (node.secret && !principal.has(AisetPermission.editSecret)) {
    throw AisetFailure(AisetErrorCode.secretAccessDenied,
        'Path \'${operation.path}\' is a secret subtree');
  }
  if (newKey == null || newKey.isEmpty) {
    throw AisetVeto('rename requires a non-empty "to" key');
  }
  if (newKey != token && !(parent.children?.containsKey(newKey) ?? false)) {
    _authorizeNewKey(parent, newKey, parentPointer, principal);
  }
  // The renamed key must not collide, and the value it carries keeps
  // its own source bytes; `applyRename` refuses a duplicate.
  final renamed = _splice(document, () => document.applyRename(operation.path, newKey));
  // The renamed key is a value the batch created at its new
  // pointer, so the protections of that position apply to it.
  _authorizeCreatedValue(descriptor, '$parentPointer/${escapeToken(newKey)}', principal);
  return renamed;
}

/// Runs one splice and turns its failures into the pipeline's own refusal
/// shapes.
String _splice(Json5Document document, String Function() edit) {
  try {
    return edit();
  } on Json5CommentConflictException catch (error) {
    throw AisetVeto(error.message, preservationConflict: true);
  } on Json5SourceException catch (error) {
    throw AisetVeto(error.message);
  }
}

String _requireValueText(AisetOperation operation) {
  final valueText = operation.valueText;
  if (valueText == null || valueText.trim().isEmpty) {
    throw AisetVeto('value_text is required');
  }
  return valueText;
}

/// The node governing a dynamic key, when the parent declares one and the
/// key's governance admits it.
DescriptorNode? _dynamicKeyNode(
    CompiledDescriptor descriptor, String parentPointer, String token) {
  final parent = _parentNode(descriptor, parentPointer);
  if (parent == null) return null;
  if (parent.type == 'array') return null;
  if (parent.additionalChildren == null || !_governsKey(parent, token)) return null;
  return parent.additionalChildren;
}

/// The node governing an array item position.
DescriptorNode? _arrayItemGovernor(
    CompiledDescriptor descriptor, String parentPointer, String token) {
  final parent = _parentNode(descriptor, parentPointer);
  if (parent == null) return null;
  return _arrayItemFallback(parent, token);
}

/// The rules for `set`: one protection walk over the addressed node and over
/// every node inside the submitted value.
///
/// * The addressed position is either declared by the descriptor, a dynamic
///   key its `additional_children` governs, or an array item the array's
///   item node governs. Anything else is refused here rather than reported as
///   an `undeclared_path` by the validation stage: a write must never
///   introduce a key the descriptor does not govern
///   (`SPEC.md` amendment 8).
/// * A `secret` node may not be written without the secret edit
///   permission, and neither may a secret descendant of the submitted value.
/// * A `read_only` node may not be rewritten. A re-submission that spells
///   the stored text byte for byte is refused too: `read_only` says this
///   value is not this caller's to change, not that the change has to be
///   visible — the answer the executed baseline gives for its single-pointer
///   write, and the batch path gets the same rule here so that a staged
///   edit cannot bypass a protection the direct write enforces
///   (`SPEC_.md` 38; see the pipeline corpus).
/// * A `read_only`/`const` descendant may not change value; see
///   [_authorizeSubmittedSubtree].
void _authorizeWrite(
  Json5Document document,
  Json5Document base,
  CompiledDescriptor descriptor,
  String pointer,
  String valueText,
  Principal principal,
) {
  if (pointer.isEmpty) throw AisetVeto('The root pointer is read-only in v1');
  final (:parentPointer, :token) = splitPointer(pointer);
  final node = descriptor.nodeAt(pointer) ??
      _dynamicKeyNode(descriptor, parentPointer, token) ??
      _arrayItemGovernor(descriptor, parentPointer, token);
  if (node == null) {
    throw AisetVeto('Path \'$pointer\' is not declared by the descriptor');
  }
  if (node.secret && !principal.has(AisetPermission.editSecret)) {
    throw AisetFailure(
        AisetErrorCode.secretAccessDenied, 'Path \'$pointer\' is a secret subtree');
  }
  if (node.readOnly && addressesNode(document, pointer)) {
    throw AisetFailure(AisetErrorCode.forbidden, 'Path \'$pointer\' is read-only');
  }
  if (node.hasConst && !addressesNode(document, pointer)) {
    throw AisetFailure(AisetErrorCode.forbidden, 'Path \'$pointer\' has a fixed value');
  }
  _authorizeSubmittedSubtree(base, descriptor, pointer, valueText, principal);
}

/// A `set` of a whole container must not slip a change past the protections
/// of a descendant (`SPEC.md` amendment 8).
///
/// Every path inside the submitted value is looked up in the
/// descriptor and, when the write actually changes the value stored
/// there, is subject to its `secret`/`read_only` protection: a
/// `secret` descendant requires the secret edit permission and
/// a `read_only` descendant is refused outright. Leaving a protected
/// subtree byte-identical is not a modification of it, which is what lets a host
/// replace a whole object that happens to contain an untouched read-only or
/// secret field (the executed baseline's own `_check_editable` rule, and
/// `SPEC.md` amendment 8: the restriction "carries over" to a write only where
/// that write would change the protected value). A `const`
/// descendant is not refused here: a changed fixed value is the validator's
/// `const` rule (`VALIDATION_ERROR`), the same answer the executed
/// baseline gives for the same batch.
void _authorizeSubmittedSubtree(
  Json5Document base,
  CompiledDescriptor descriptor,
  String pointer,
  String valueText,
  Principal principal,
) {
  final Object? submitted;
  try {
    submitted = Json5Document(valueText, origin: '<value_text>').storedValue();
  } on Json5SourceException {
    // An unparseable submission is refused by the splice with
    // `PARSE_ERROR`; authorization does not invent a different answer for
    // the same text.
    return;
  }
  if (!isObjectValue(submitted) && submitted is! List) return;
  final Json5Document candidate;
  try {
    candidate = Json5Document(base.applySet(pointer, valueText), origin: base.origin);
  } on Object {
    // The splice is refused on its own terms; there is no candidate
    // to compare descendants against.
    return;
  }
  final before = base.storedValue();
  final after = candidate.storedValue();
  for (final path in submittedPaths(pointer, submitted)) {
    if (path == pointer) continue;
    final node = descriptor.nodeAt(path);
    if (node == null) continue;
    // A descendant the write leaves byte-identical is not
    // modified, so no protection of it is engaged.
    if (sameTreeValue(lookupStored(before, path), lookupStored(after, path))) continue;
    if (node.secret && !principal.has(AisetPermission.editSecret)) {
      throw AisetFailure(
          AisetErrorCode.secretAccessDenied, 'Path \'$path\' is a secret subtree');
    }
    if (node.readOnly) {
      throw AisetFailure(AisetErrorCode.forbidden, 'Path \'$path\' is read-only');
    }
  }
}

/// The rules for `add`: appending one array item or creating one object
/// key.
void _authorizeAdd(
  Json5Document document,
  CompiledDescriptor descriptor,
  String pointer,
  Principal principal,
) {
  final appended = pointer.endsWith('/$appendMarker');
  final containerPointer =
      appended ? pointer.substring(0, pointer.length - '/-'.length) : parentPointerText(pointer);
  final container = _nodeAtOrThrow(descriptor, containerPointer);
  if (appended) {
    if (!addressesNode(document, containerPointer)) {
      throw AisetVeto('Missing object key \'${splitPointer(containerPointer).token}\'');
    }
    if (container.type != 'array') {
      throw AisetVeto('The append token \'-\' requires an array at \'$containerPointer\'');
    }
    _authorizeCreatedValueAt(container, containerPointer, principal);
    return;
  }
  if (container.type == 'array') {
    throw AisetVeto('Path \'$pointer\' addresses an array; '
        'use the \'-\' append token to add an item');
  }
  if (container.type != 'object') {
    throw AisetVeto('Cannot add to ${container.type} at \'$containerPointer\'');
  }
  final key = unescapePointerToken(pointer.substring(containerPointer.length + 1));
  _authorizeNewKey(container, key, containerPointer, principal);
}

/// The rules for a key an operation creates.
void _authorizeNewKey(
  DescriptorNode parent,
  String key,
  String parentPointer,
  Principal principal,
) {
  final declared = parent.children?[key];
  if (declared == null && parent.additionalChildren == null) {
    throw AisetVeto('Key \'$key\' is not permitted at \'$parentPointer\'');
  }
  if (declared == null) {
    final allowed = parent.keyEnum;
    if (allowed != null && allowed.isNotEmpty && !allowed.contains(key)) {
      throw AisetVeto('Key \'$key\' is not in key_enum');
    }
    final pattern = parent.keyPattern;
    if (pattern != null && pattern.isNotEmpty && !keyMatchesPattern(pattern, key)) {
      throw AisetVeto('Key \'$key\' does not match key_pattern');
    }
  }
  _authorizeCreatedValueAt(declared ?? parent.additionalChildren!, parentPointer, principal);
}

/// The protections a newly created value is subject to.
///
/// A `read_only` or `secret` declaration governs the value, so
/// creating one requires the same permission editing one
/// would. The executed baseline checks neither for `add`, which
/// lets a principal without the secret permission create a
/// value under a secret-governed node; this product requires it
/// (`SPEC.md` amendments 8, 9 and 26, SEC-01).
void _authorizeCreatedValueAt(DescriptorNode child, String parentPointer, Principal principal) {
  if (child.readOnly) {
    throw AisetFailure(AisetErrorCode.forbidden,
        'Path \'$parentPointer\' declares read-only children');
  }
  if (subtreeHasSecret(child) && !principal.has(AisetPermission.editSecret)) {
    throw AisetFailure(AisetErrorCode.secretAccessDenied,
        'Path \'$parentPointer\' is a secret subtree');
  }
}

/// The protections of the value a batch just created at [newPointer].
void _authorizeCreatedValue(
    CompiledDescriptor descriptor, String newPointer, Principal principal) {
  final node = descriptor.nodeAt(newPointer);
  if (node == null) return;
  _authorizeCreatedValueAt(node, parentPointerText(newPointer), principal);
}

/// The permissions that block removing [node].
void _authorizeRemoval(
  DescriptorNode node,
  DescriptorNode? parent,
  String pointer, {
  required String token,
  required Principal principal,
}) {
  if (node.required) {
    throw AisetFailure(AisetErrorCode.forbidden,
        'Path \'$pointer\' is required and cannot be removed');
  }
  if (node.readOnly) {
    throw AisetFailure(AisetErrorCode.forbidden, 'Path \'$pointer\' is read-only');
  }
  if (node.hasConst) {
    throw AisetFailure(AisetErrorCode.forbidden, 'Path \'$pointer\' has a fixed value');
  }
  final fixedDeclaredChild = parent != null &&
      parent.type == 'object' &&
      (parent.children?.containsKey(token) ?? false) &&
      parent.additionalChildren == null;
  if (fixedDeclaredChild) {
    throw AisetFailure(
        AisetErrorCode.forbidden, 'Path \'$pointer\' is a fixed declared child');
  }
  if (node.secret && !principal.has(AisetPermission.editSecret)) {
    throw AisetFailure(
        AisetErrorCode.secretAccessDenied, 'Path \'$pointer\' is a secret subtree');
  }
}

/// The rules for `drop`, the doctor's operation on a key the descriptor
/// does not declare.
///
/// A declared path is refused: `drop` never replaces `remove`.
/// Inside a union no alternative declares the key, so removing it cannot make
/// the value match any alternative worse; a read-only shape or a secret
/// subtree still blocks it. Admissibility considers
/// every alternative, as the amendment requires.
void _authorizeDrop(
  CompiledDescriptor descriptor,
  Json5Document document,
  String pointer,
  Principal principal,
) {
  if (pointer.isEmpty) throw AisetVeto('The root pointer cannot be dropped');
  final (:parentPointer, :token) = splitPointer(pointer);
  if (descriptor.nodeAt(pointer) != null) {
    throw AisetVeto('Path \'$pointer\' is declared; use remove, not drop');
  }
  final parent = _nodeAtOrThrow(descriptor, parentPointer);
  if (parent.type == 'union') {
    final options = parent.optionNodes ?? const <DescriptorNode>[];
    if (options.any((option) => option.readOnly || option.hasConst)) {
      throw AisetFailure(AisetErrorCode.forbidden,
          'Path \'$parentPointer\' contains a read-only shape');
    }
    if (subtreeHasSecret(parent) && !principal.has(AisetPermission.editSecret)) {
      throw AisetFailure(
          AisetErrorCode.secretAccessDenied, 'Path \'$parentPointer\' is a secret subtree');
    }
    if (!addressesNode(document, pointer)) {
      throw AisetVeto('Missing object key \'$token\'');
    }
    return;
  }
  if (parent.type != 'object') {
    throw AisetVeto('Cannot drop a key from ${parent.type} at \'$pointer\'');
  }
  if (parent.readOnly) {
    throw AisetFailure(
        AisetErrorCode.forbidden, 'Path \'$parentPointer\' is read-only');
  }
  if (subtreeHasSecret(parent) && !principal.has(AisetPermission.editSecret)) {
    throw AisetFailure(
        AisetErrorCode.secretAccessDenied, 'Path \'$parentPointer\' is a secret subtree');
  }
  if (!addressesNode(document, pointer)) {
    throw AisetVeto('Missing object key \'$token\'');
  }
}

/// The rules for `move`: only array items move, and only into an array index.
///
/// A move reorders the container and carries the item's comments with
/// it. The item's own `read_only` and `const` flags do not block a
/// reorder of the container they sit in, because the value keeps its
/// source bytes; a `read_only` or `const` **array** may not be
/// reordered at all, and a secret item may only be moved by a principal
/// that may edit that subtree.
void _authorizeMove(
  CompiledDescriptor descriptor,
  Json5Document document,
  AisetOperation operation,
  Principal principal,
) {
  final source = operation.from;
  if (source == null || source.isEmpty) throw AisetVeto('move requires a "from" pointer');
  if (!addressesNode(document, source)) {
    throw AisetVeto('Path \'$source\' does not exist');
  }
  final (:parentPointer, :token) = splitPointer(source);
  final parent = _nodeAtOrThrow(descriptor, parentPointer);
  if (parent.type != 'array') throw AisetVeto('Only array items can be moved');
  final target = _nodeAtOrThrow(descriptor, splitPointer(operation.path).parentPointer);
  if (target.type != 'array') throw AisetVeto('A move target must be an array index');
  if (parent.readOnly) {
    throw AisetFailure(
        AisetErrorCode.forbidden, 'Path \'$parentPointer\' is read-only');
  }
  if (parent.hasConst) {
    throw AisetFailure(
        AisetErrorCode.forbidden, 'Path \'$parentPointer\' has a fixed value');
  }
  final item = descriptor.nodeAt(source) ?? _arrayItemFallback(parent, token);
  if (item == null) {
    throw AisetVeto('Path \'$source\' is not declared by the descriptor');
  }
  if (item.secret && !principal.has(AisetPermission.editSecret)) {
    throw AisetFailure(
        AisetErrorCode.secretAccessDenied, 'Path \'$source\' is a secret subtree');
  }
}

/// The node the descriptor governs at [pointer]: the declared node, an
/// admitted dynamic key, or the governing array item.
DescriptorNode _governedNode(
  CompiledDescriptor descriptor,
  String pointer, {
  required String parentPointer,
  required String token,
}) {
  final node = descriptor.nodeAt(pointer) ??
      _dynamicKeyNode(descriptor, parentPointer, token) ??
      _arrayItemGovernor(descriptor, parentPointer, token);
  if (node == null) {
    throw AisetVeto('Path \'$pointer\' is not declared by the descriptor');
  }
  return node;
}

/// The node governing the array item at [token]: the declared item node, or
/// the last declared alternative for an index past them.
DescriptorNode? _arrayItemFallback(DescriptorNode parent, String token) {
  if (parent.type != 'array' || !isIndexToken(token)) return null;
  return parent.itemNode ??
      (parent.optionNodes == null || parent.optionNodes!.isEmpty
          ? null
          : parent.optionNodes!.last);
}

/// The node the descriptor declares at [pointer].
DescriptorNode _nodeAtOrThrow(CompiledDescriptor descriptor, String pointer) {
  if (pointer.isEmpty) return descriptor.root;
  final node = descriptor.nodeAt(pointer);
  if (node == null) {
    throw AisetVeto('Path \'$pointer\' is not declared by the descriptor');
  }
  return node;
}

/// The declared node of [parentPointer], or `null` when the descriptor says
/// nothing there.
DescriptorNode? _parentNode(CompiledDescriptor descriptor, String parentPointer) =>
    parentPointer.isEmpty ? descriptor.root : descriptor.nodeAt(parentPointer);

/// Whether an object governs undeclared [key] through its dynamic children.
///
/// One predicate answers the governance question everywhere in this product —
/// `SPEC_.md` 38, report A25: the baseline implements it three times, with
/// `re.search` in the validator and a prefix match in the node lookup and the
/// resolver, so the three call sites disagree about which keys an object
/// governs.
bool _governsKey(DescriptorNode node, String key) {
  if (node.additionalChildren == null) return false;
  final allowed = node.keyEnum;
  if (allowed != null && allowed.isNotEmpty && !allowed.contains(key)) return false;
  final pattern = node.keyPattern;
  if (pattern != null && pattern.isNotEmpty && !keyMatchesPattern(pattern, key)) return false;
  return true;
}

/// Whether [pattern] admits [key]: a match at the start of the key, in the
/// accepted dialect of `docs/grammars.md` §1.
bool keyMatchesPattern(String pattern, String key) {
  if (!checkPatternDialect(pattern).ok) return false;
  try {
    return RegExp(pattern).matchAsPrefix(key) != null;
  } on FormatException {
    return false;
  }
}

/// Whether the subtree under [node] declares a secret anywhere.
///
/// The question the write pipeline and the event filter both have to
/// answer: a read-only or secret descendant of the
/// position being written is protected even when the addressed node
/// itself is not (`SPEC.md` amendments 8, 9 and 26, SEC-01).
bool subtreeHasSecret(DescriptorNode? node) {
  if (node == null) return false;
  if (node.secret) return true;
  for (final child in (node.children ?? const <String, DescriptorNode>{}).values) {
    if (subtreeHasSecret(child)) return true;
  }
  if (subtreeHasSecret(node.additionalChildren)) return true;
  for (final option in node.optionNodes ?? const <DescriptorNode>[]) {
    if (subtreeHasSecret(option)) return true;
  }
  return subtreeHasSecret(node.itemNode);
}

/// The identity index of [document]: each entry node, value node
/// and the document itself mapped to the pointer that addresses it.
///
/// The CST records comment ownership by node identity, so turning
/// "which comments does this entry own" into "which comments
/// lie outside the paths this batch addressed" needs this map. It is
/// built by one walk and holds no state of its own.
Map<Object, String> pointerIndex(Json5Document document) {
  final out = <Object, String>{document: '', document.root: ''};
  void walk(ValueNode node, String pointer) {
    out[node] = pointer;
    if (node is ObjectNode) {
      for (final member in node.members) {
        final child = '$pointer/${escapeToken(member.label)}';
        out[member] = child;
        walk(member.value, child);
      }
    } else if (node is ArrayNode) {
      for (var index = 0; index < node.items.length; index++) {
        final item = node.items[index];
        final child = '$pointer/$index';
        out[item] = child;
        walk(item.value, child);
      }
    }
  }

  walk(document.root, '');
  return out;
}
