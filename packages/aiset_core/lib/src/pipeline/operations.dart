part of 'pipeline.dart';

/// One staged operation, in the Python-compatible envelope shape
/// (`SPEC.md` amendment 8).
///
/// The six kinds are [AisetOperationKind]; each carries the target [path]
/// and, per kind, a [valueText], a [from] source or a [to]
/// key. Dotted paths are not accepted here: the editing API addresses nodes
/// with JSON Pointer and the mount grammar is a separate address type with one
/// explicit conversion, [mountToPointer] (`SPEC.md` amendment 4).
enum AisetOperationKind {
  /// Replaces (or creates) the value at [AisetOperation.path].
  set('set'),

  /// Appends one array item at `/…/-`, or creates one object key.
  add('add'),

  /// Removes one declared array item or object member.
  remove('remove'),

  /// Reorders one array item to [AisetOperation.path].
  move('move'),

  /// Renames the object key at [AisetOperation.path] to
  /// [AisetOperation.to], in place, and not as remove plus add.
  rename('rename'),

  /// Removes a key the descriptor does not declare. It never replaces
  /// [remove] (`SPEC.md` amendment 8).
  drop('drop');

  const AisetOperationKind(this.label);

  /// The wire spelling.
  final String label;

  /// The kind named by [label], or `null` for an unknown name.
  static AisetOperationKind? tryParse(String label) {
    for (final kind in AisetOperationKind.values) {
      if (kind.label == label) return kind;
    }
    return null;
  }
}

/// One staged operation.
final class AisetOperation {
  /// Creates an operation.
  const AisetOperation({
    required this.kind,
    this.path = '',
    this.valueText,
    this.from,
    this.to,
    this.unknownName,
  });

  /// Decodes the wire shape `{ op, path, value_text, from, to }`.
  ///
  /// An unknown `op` name does not throw here: it becomes
  /// [unknownName], so the batch reports it as the operation's own
  /// failure with `BAD_REQUEST` semantics rather than
  /// failing the decode of a whole draft.
  factory AisetOperation.fromMap(Map<String, Object?> map) {
    final name = map['op'];
    final kind = name is String ? AisetOperationKind.tryParse(name) : null;
    return AisetOperation(
      kind: kind ?? AisetOperationKind.set,
      unknownName: kind == null ? '$name' : null,
      path: map['path'] as String? ?? '',
      valueText: map['value_text'] as String?,
      from: map['from'] as String?,
      to: map['to'] as String?,
    );
  }

  /// The wire form.
  Map<String, Object?> toMap() => {
        'op': unknownName ?? kind.label,
        'path': path,
        if (valueText != null) 'value_text': valueText,
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      };

  /// The operation kind.
  final AisetOperationKind kind;

  /// The JSON Pointer the operation addresses.
  final String path;

  /// The submitted value text for `set` and `add`.
  final String? valueText;

  /// The source pointer of a `move`.
  final String? from;

  /// The new key of a `rename`.
  final String? to;

  /// The unrecognized `op` name a decoded batch carried, or
  /// `null` for a known kind.
  final String? unknownName;

  /// The pointer the authorization and the edit protections are about:
  /// the target, except for `move`, whose addressed node is its source.
  String get checkedPath => kind == AisetOperationKind.move ? (from ?? '') : path;

  /// A `move` addresses two positions; this is the target index, or
  /// `null` for every other kind.
  String? get secondaryPath => kind == AisetOperationKind.move ? path : null;

  @override
  String toString() => 'AisetOperation(${unknownName ?? kind.label} $path)';
}

// -- pointer helpers --------------------------------------------------------

/// The pointer of the container of [pointer], textually so escaped keys
/// survive: `/a~1b/c` has the parent `/a~1b`.
String parentPointerText(String pointer) => textualParentPointer(pointer);

/// Splits [pointer] into the pointer of its container and its unescaped last
/// token.
///
/// The root pointer has no parent and an empty token; a pointer that
/// does not start with `/` is refused with an [AisetVeto]
/// carrying the baseline's `BAD_REQUEST` wording.
({String parentPointer, String token}) splitPointer(String pointer) {
  if (pointer.isEmpty) return (parentPointer: '', token: '');
  if (!pointer.startsWith('/')) {
    throw AisetVeto('Path must be empty or start with \'/\': \'$pointer\'');
  }
  final index = pointer.lastIndexOf('/');
  return (
    parentPointer: index == 0 ? '' : pointer.substring(0, index),
    token: unescapePointerToken(pointer.substring(index + 1)),
  );
}

/// Unescapes one pointer token; only `~0` and `~1`
/// are escapes (`SPEC.md` amendment 4).
String unescapePointerToken(String raw) {
  if (!raw.contains('~')) return raw;
  final out = StringBuffer();
  var index = 0;
  while (index < raw.length) {
    final char = raw[index];
    if (char == '~') {
      final next = index + 1 < raw.length ? raw[index + 1] : '';
      if (next == '0') {
        out.write('~');
      } else if (next == '1') {
        out.write('/');
      } else {
        throw AisetVeto('Malformed escape in path segment: \'$raw\'');
      }
      index += 2;
      continue;
    }
    out.write(char);
    index++;
  }
  return out.toString();
}

/// Builds a pointer from unescaped [tokens].
String pointerOfTokens(Iterable<String> tokens) =>
    [for (final token in tokens) '/${escapeToken(token)}'].join();

/// Every ancestor pointer of [pointer], the pointer itself last.
///
/// A hook binding on an ancestor governs a change in a descendant, so the
/// pipeline examines the whole prefix chain (`SPEC.md` amendments 5 and 9).
List<String> pointerPrefixes(String pointer) {
  final tokens = parsePointer(pointer);
  return [
    for (var index = 0; index <= tokens.length; index++) pointerOfTokens(tokens.take(index)),
  ];
}

/// The pointers present in [document] at or below [pointer].
///
/// Returns nothing instead of throwing when the path is absent or crosses a
/// scalar: a batch may create a container and then address a child of it, and
/// the base document does not have that container yet.
List<String> pathsSafely(Json5Document document, String pointer) {
  try {
    return document.paths(pointer);
  } on Json5SourceException {
    return const [];
  }
}

/// The [pointer] itself plus every pointer inside the submitted [value].
///
/// A `set` of a whole object replaces every descendant, so the descendant
/// protections — a `read_only` or `secret` child — have to be checked
/// against the submitted subtree and not only against the addressed node
/// (`SPEC.md` amendment 8).
List<String> submittedPaths(String pointer, Object? value) {
  final paths = <String>[pointer];
  if (isObjectValue(value)) {
    final map = (value! as Map<Object?, Object?>).cast<Object?, Object?>();
    for (final entry in map.entries) {
      paths
          .addAll(submittedPaths('$pointer/${escapeToken(entry.key! as String)}', entry.value));
    }
  } else if (value is List) {
    for (var index = 0; index < value.length; index++) {
      paths.addAll(submittedPaths('$pointer/$index', value[index]));
    }
  }
  return paths;
}

/// Whether [pointer] addresses an existing node of [document].
bool addressesNode(Json5Document document, String pointer) {
  try {
    return document.find(pointer) != null;
  } on Json5SourceException {
    return false;
  }
}

/// The value node at [pointer], or `null`.
ValueNode? nodeAt(Json5Document document, String pointer) {
  try {
    return document.find(pointer);
  } on Json5SourceException {
    return null;
  }
}

/// The exact source slice at [pointer], or `null` when the path is absent or
/// crosses a scalar.
String? sourceSliceAt(Json5Document document, String pointer) {
  final node = nodeAt(document, pointer);
  return node == null ? null : document.sliceOf(node);
}

/// The 1-based source position of [pointer] in [document], or `null`.
({int line, int column})? locatePointer(Json5Document document, String pointer) {
  final node = pointer.isEmpty ? document.root : nodeAt(document, pointer);
  if (node == null) return null;
  final (line, column) = document.lineCol(node.span.startUnit);
  return (line: line, column: column);
}

// -- mount grammar ----------------------------------------------------------

/// The identity fields a `[field=value]` selector may
/// use.
const List<String> mountIdentityFields = ['id', 'name', 'key'];

/// A mount grammar position, in the shape the amendment requires:
/// the JSON Pointer it addresses and the array index a selector resolved
/// to, when it used one.
final class MountPointer {
  /// Creates a conversion result.
  const MountPointer({required this.pointer, required this.segments});

  /// The JSON Pointer the mount addresses.
  final String pointer;

  /// The unescaped token of each segment, in order.
  final List<String> segments;

  @override
  String toString() => 'MountPointer($pointer)';
}

/// Converts the mount grammar expression [mount] into a JSON
/// Pointer against [document]
/// (`SPEC.md` amendment 4).
///
/// The grammar is `segment ("." segment)*`, where a segment is a plain key
/// with a literal dot written as `\.`, or an identity selector
/// `[field=value]` that picks the array element whose [field]
/// equals [value]. A selector that matches zero or several elements is an
/// explicit refusal: the library never guesses an ambiguous mount.
///
/// The two address types stay distinct; this function is the
/// documented, one-way conversion the amendment requires, and it
/// needs the document because an identity selector resolves to
/// a position.
MountPointer mountToPointer(String mount, Json5Document document) {
  final segments = _splitMount(mount);
  if (segments.isEmpty) {
    throw AisetVeto('Mount must not be empty');
  }
  final tokens = <String>[];
  Object? cursor = document.storedValue();
  for (final segment in segments) {
    if (segment.startsWith('[') && segment.endsWith(']')) {
      final inner = segment.substring(1, segment.length - 1);
      final split = inner.indexOf('=');
      if (split <= 0 || split == inner.length - 1) {
        throw AisetVeto('Malformed identity selector \'$segment\' in \'$mount\'');
      }
      final field = inner.substring(0, split);
      final expected = inner.substring(split + 1);
      if (cursor is! List) {
        throw AisetVeto('Selector [$field=$expected] in \'$mount\' requires an array');
      }
      final matches = <int>[];
      for (var index = 0; index < cursor.length; index++) {
        final item = cursor[index];
        if (!isObjectValue(item)) continue;
        final map = (item! as Map<Object?, Object?>).cast<Object?, Object?>();
        if (!mapHas(map, field)) continue;
        if (renderStoredValue(map[field]) == expected) matches.add(index);
      }
      if (matches.isEmpty) {
        throw AisetVeto('Selector [$field=$expected] matches no element in \'$mount\'');
      }
      if (matches.length > 1) {
        throw AisetVeto('Selector [$field=$expected] is ambiguous in \'$mount\': '
            '${matches.length} matches');
      }
      tokens.add('${matches.first}');
      cursor = cursor[matches.first];
      continue;
    }
    if (cursor is List) {
      throw AisetVeto('Segment \'$segment\' at position ${tokens.length} '
          'requires a selector in \'$mount\'');
    }
    if (!isObjectValue(cursor)) {
      throw AisetVeto('Mount \'$mount\' does not address a container');
    }
    final map = (cursor! as Map<Object?, Object?>).cast<Object?, Object?>();
    if (!mapHas(map, segment)) {
      throw AisetVeto('Missing mount segment \'$segment\' in \'$mount\'');
    }
    tokens.add(segment);
    cursor = map[segment];
  }
  return MountPointer(pointer: pointerOfTokens(tokens), segments: segments);
}

/// Splits a mount expression into its segments, honouring `\.`.
List<String> _splitMount(String mount) {
  if (mount.isEmpty) return const [];
  final segments = <String>[];
  final current = StringBuffer();
  var index = 0;
  while (index < mount.length) {
    final char = mount[index];
    if (char == r'\' && index + 1 < mount.length) {
      current.write(mount[index + 1]);
      index += 2;
      continue;
    }
    if (char == '.') {
      segments.add(current.toString());
      current.clear();
      index++;
      continue;
    }
    current.write(char);
    index++;
  }
  segments.add(current.toString());
  if (segments.any((segment) => segment.isEmpty)) {
    throw AisetVeto('Empty mount segment in \'$mount\'');
  }
  return segments;
}
