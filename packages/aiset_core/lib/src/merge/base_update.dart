part of 'merge.dart';

/// Who wins a merge conflict (`SPEC.md` amendment 7).
enum MergePreference {
  /// The base value survives every non-object conflict. The default.
  base('base'),

  /// The update value replaces the base on a conflict.
  update('update');

  const MergePreference(this.label);

  /// The name accepted on the wire.
  final String label;

  /// The mode named by [label], or `null` for an unknown name.
  static MergePreference? tryParse(String label) {
    for (final mode in MergePreference.values) {
      if (mode.label == label) return mode;
    }
    return null;
  }
}

/// Merges [update] onto [base] and returns the result.
///
/// A conflict is any pair of values that are not both objects: a
/// scalar, a list, a null, or two different kinds. [preference] says whose
/// value the result keeps for it. Two objects are not a conflict:
/// they are merged key by key, recursively, in either mode.
///
/// The walk is driven by the [base] structure: keys the base has are visited
/// in the base's own order and keys only the update adds follow it, so a
/// merged document keeps the layout the base was written
/// in. Both inputs are left exactly as they were, and the
/// returned tree shares no mutable node with either of them, so a caller
/// may write through the result without touching a document
/// (`SPEC_.md` amendment 38: the baseline aliases base subtrees into its
/// result; see the library comment).
///
/// A placeholder ([TemplateRef]) is one opaque value: it is never
/// resolved, compared field by field, or merged into text.
/// [resolverMissing] is not a value at all, so it is not merged —
/// [merge] is defined on stored trees, where an absent field is
/// simply a key that is not there.
///
/// An unknown [preference] name is a `BAD_REQUEST`
/// ([AisetFailure]), the same rejection a malformed operation argument gets;
/// the baseline raises a bare `ValueError` here, which is why
/// the preference is normally passed as the enum.
Object? merge(
  Object? base,
  Object? update, {
  MergePreference preference = MergePreference.base,
}) =>
    _merge(base, update, preference);

/// Merges [update] onto [base], selecting the preference by [label].
///
/// The wire form of [merge] for a host that carries the preference as
/// text (an HTTP body, an AI proposal). Only `base` and `update`
/// are names this accepts.
Object? mergeLabeled(
  Object? base,
  Object? update, {
  String preference = 'base',
}) {
  final parsed = MergePreference.tryParse(preference);
  if (parsed == null) {
    throw MergePreferenceError(preference);
  }
  return _merge(base, update, parsed);
}

Object? _merge(Object? base, Object? update, MergePreference prefer) {
  final baseIsObject = isObjectValue(base);
  final updateIsObject = isObjectValue(update);
  if (baseIsObject && updateIsObject) {
    final left = (base! as Map<Object?, Object?>).cast<Object?, Object?>();
    final right = (update as Map<Object?, Object?>).cast<Object?, Object?>();
    final merged = <String, Object?>{};
    for (final entry in left.entries) {
      final key = entry.key! as String;
      merged[key] =
          mapHas(right, key) ? _merge(entry.value, right[key], prefer) : _copy(entry.value);
    }
    for (final entry in right.entries) {
      final key = entry.key! as String;
      if (!mapHas(left, key)) merged[key] = _copy(entry.value);
    }
    return merged;
  }
  if (baseIsObject != updateIsObject) {
    // A type mismatch is a conflict like any other: the winner is copied.
    return _copy(prefer == MergePreference.base ? base : update);
  }
  if (isArrayValue(base) || isArrayValue(update) || !sameScalarValue(base, update)) {
    return _copy(prefer == MergePreference.base ? base : update);
  }
  return _copy(base);
}

/// An independent deep copy of a stored subtree.
Object? _copy(Object? value) => mutableCopy(value);

/// The refusal of an unknown merge preference name.
///
/// The merge library is deliberately independent of the
/// error-code library (a host may use it alone), so this carries the same
/// stable `BAD_REQUEST` code the pipeline
/// reports for a malformed operation argument
/// (`SPEC_.md` 38: the executed baseline raises a bare
/// `ValueError` with no code at all here).
final class MergePreferenceError implements Exception {
  /// Creates the refusal for the rejected [preference] name.
  MergePreferenceError(this.preference);

  /// The rejected name.
  final String preference;

  /// The stable error code.
  String get code => 'BAD_REQUEST';

  /// The short reason, in the baseline's own wording.
  String get message =>
      'prefer must be one of ("base", "update"), got \'$preference\'';

  @override
  String toString() => 'MergePreferenceError: $message';
}

/// Read-only views of a merge result, for hosts that must not write through it.
///
/// [mergeAsViews] returns the same data as [merge] wrapped in unmodifiable
/// views; a host that wants to keep editing the result uses
/// [merge].
Object? mergeAsViews(
  Object? base,
  Object? update, {
  MergePreference preference = MergePreference.base,
}) =>
    immutableTree(_merge(base, update, preference));

/// Whether [value] is unchanged from [before], structurally.
///
/// The pipeline uses this to prove that an operation batch or a
/// rejected write left the stored tree exactly as it was; a
/// reference-equality check would not say anything about a tree
/// rebuilt from the same text.
bool treeUnchanged(Object? before, Object? after) => sameTreeValue(before, after);
