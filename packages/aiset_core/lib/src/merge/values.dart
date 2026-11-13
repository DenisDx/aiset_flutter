part of 'merge.dart';

/// Shared value helpers for the merge and the write pipeline.
///
/// A stored tree (what [Json5Document.storedValue] yields) is
/// built from plain `Map<String, Object?>`/`List<Object?>` literals, and the
/// engine also accepts trees that arrived as JSON
/// (so `Map<Object?, Object?>`) or as immutable views. These helpers read
/// such a tree without assuming more than [Map] and [List], and never
/// write to it.

/// Reads [key] from [map] regardless of the map's static key type.
///
/// Returns the stored entry, or `null` when absent; use
/// [mapHas] when an explicit null has to be told apart from a missing key.
Object? mapValue(Map<Object?, Object?> map, String key) {
  final value = map[key];
  return value is String ||
          value is bool ||
          value is num ||
          value is BigInt ||
          value is Map ||
          value is List ||
          value is TemplateRef ||
          value == null
      ? value
      : null;
}

/// Whether [map] holds [key] at all, explicit null included
/// (`SPEC.md` amendment 2: absent and null are distinct states).
bool mapHas(Map<Object?, Object?> map, String key) {
  for (final entry in map.entries) {
    if (entry.key == key) return true;
  }
  return false;
}

/// The entries of [map] with string keys, in insertion order.
///
/// Keys that are not strings are not part of a settings tree this
/// product produces; they are dropped rather than reinterpreted, so a
/// merge result never grows a key the baseline would not name.
Map<String, Object?> stringKeyed(Map<Object?, Object?> map) => <String, Object?>{
      for (final entry in map.entries)
        if (entry.key is String) entry.key! as String: entry.value,
    };

/// Whether [value] is a JSON object (a map keyed by strings).
///
/// An empty map counts, as it does in the baseline; a map with non-string
/// keys is data this product cannot have produced from a settings
/// document, so it is not an object either.
bool isObjectValue(Object? value) =>
    value is Map && (value.isEmpty || value.keys.every((k) => k is String));

/// Whether [value] is a JSON array.
bool isArrayValue(Object? value) => value is List;

/// Whether [value] is one of the two placeholder representations.
///
/// [TemplateRef] is what the JSON5 engine stores; the resolver's
/// [resolvedPlaceholder] is the placeholder it produced inside a
/// string. Both are structural placeholders, not text.
bool isPlaceholderValue(Object? value) =>
    value is TemplateRef || value.runtimeType.toString() == '_Placeholder';

/// The resolved text of a placeholder, or `null` for any other
/// value kind.
///
/// Detection is structural rather than by an
/// exported type: the resolver's placeholder is a private class
/// deliberately, because it is an intermediate of one
/// resolution and not something a caller is meant to build.
String? placeholderTextOf(Object? value) {
  if (value is! TemplateRef) return null;
  return value.defaultText == null
      ? '\${${value.name}}'
      : '\${${value.name}:-${value.defaultText}}';
}

/// An immutable snapshot of [value]: nested maps and lists are copied into
/// unmodifiable views.
///
/// A view of the stored tree is handed to host callbacks, so a
/// host that writes to what it was given gets an error instead of
/// quietly corrupting the service state (`SPEC.md` amendment 2: a snapshot is
/// immutable from the consumer's point of view). Leaves — scalars,
/// `BigInt`, placeholders — are returned unchanged.
Object? immutableTree(Object? value) {
  if (isObjectValue(value)) {
    final map = (value as Map<Object?, Object?>).cast<Object?, Object?>();
    return UnmodifiableMapView<String, Object?>(<String, Object?>{
      for (final entry in map.entries)
        entry.key! as String: immutableTree(entry.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable([for (final item in value) immutableTree(item)]);
  }
  return value;
}

/// A placeholder-free copy of [value], with maps normalized to
/// `Map<String, Object?>` and lists to plain `List<Object?>`.
///
/// This is the *active* view: the placeholders a document declares are
/// the values the application actually runs on, so
/// each is replaced by its resolved text, exactly as it was substituted
/// into the effective tree. Everything else, including [resolverMissing], is
/// carried unchanged.
Object? activeValueView(Object? value) {
  if (isObjectValue(value)) {
    final map = (value as Map<Object?, Object?>).cast<Object?, Object?>();
    return <String, Object?>{
      for (final entry in map.entries)
        entry.key! as String: activeValueView(entry.value),
    };
  }
  if (value is List) {
    return [for (final item in value) activeValueView(item)];
  }
  return placeholderTextOf(value) ?? value;
}

/// A deep copy of [value] into mutable plain Dart data.
Object? mutableCopy(Object? value) {
  if (isObjectValue(value)) {
    final map = (value as Map<Object?, Object?>).cast<Object?, Object?>();
    return <String, Object?>{
      for (final entry in map.entries)
        entry.key! as String: mutableCopy(entry.value),
    };
  }
  if (value is List) {
    return [for (final item in value) mutableCopy(item)];
  }
  return value;
}

/// Whether the two trees hold the same data, structurally.
///
/// `int`, `BigInt` and `double` compare by numeric value where that is exact
/// (`1` equals `1.0`, as the baseline's `==` does), a non-finite
/// double equals only itself-or-another-non-finite of the same
/// sign, [TemplateRef] compares by name and default, and the absence
/// marker compares by identity. A map and a list are never equal.
bool sameTreeValue(Object? a, Object? b) {
  if (isMissing(a) || isMissing(b)) return identical(a, b);
  if (a is TemplateRef || b is TemplateRef) {
    return a is TemplateRef && b is TemplateRef && a == b;
  }
  if (isObjectValue(a) || isObjectValue(b)) {
    if (!isObjectValue(a) || !isObjectValue(b)) return false;
    final left = (a! as Map<Object?, Object?>).cast<Object?, Object?>();
    final right = (b as Map<Object?, Object?>).cast<Object?, Object?>();
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      final key = entry.key! as String;
      if (!mapHas(right, key)) return false;
      if (!sameTreeValue(entry.value, right[key])) return false;
    }
    return true;
  }
  if (a is List || b is List) {
    if (a is! List || b is! List) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!sameTreeValue(a[i], b[i])) return false;
    }
    return true;
  }
  return sameScalarValue(a, b);
}

/// Whether two scalars are the same value, using the baseline's
/// numeric equality (`true == 1` and `1 == 1.0` hold in Python).
bool sameScalarValue(Object? a, Object? b) {
  if (a == b) return true;
  final left = _numeric(a);
  final right = _numeric(b);
  if (left == null || right == null) return false;
  if (left.isNaN || right.isNaN) return false;
  return left == right;
}

double? _numeric(Object? value) => switch (value) {
      final int i => i.toDouble(),
      final BigInt b => b.toDouble(),
      final double d => d,
      final bool flag => flag ? 1 : 0,
      _ => null,
    };

/// A stable rendering of one stored value, used in the corpus encoding
/// and in the service's audit payload.
String renderStoredValue(Object? value) => switch (value) {
      null => 'null',
      _ when isMissing(value) => '<missing>',
      final TemplateRef t => t.sourceText,
      final bool b => b ? 'true' : 'false',
      final int i => '$i',
      final BigInt b => '$b',
      final double d => d.toString(),
      final String s => s,
      _ => '$value',
    };
