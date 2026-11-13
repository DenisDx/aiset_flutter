/// Configuration merge (`SPEC.md` amendment 7), proven by the executed baseline.
///
/// [merge] answers one question: what is the result of layering an
/// `update` document on a `base` document. It is a pure function on
/// stored value trees — the kind [Json5Document.storedValue] yields — and is
/// deliberately not an editing API: it never touches source text, never keeps
/// comments, and never deletes a key.
///
/// Two precedence modes share one recursive walk:
///
/// * [MergePreference.base] (the default): the base decides every conflict.
///   Objects merge recursively; a scalar, a list, a null or a type mismatch keeps
///   the base value. A key only the update has is added; a key only the
///   base has is kept. For `aiui` the main config is the base and a plugin's
///   defaults are the update, so user settings win.
/// * [MergePreference.update]: the update replaces the base on a conflict.
///
/// Neither mode merges two arrays by item identity, and neither mode is a
/// delete: a key absent from the update survives.
///
/// **Inputs are never mutated, and the result never aliases them.** The
/// executed baseline copies only what the update contributes, so a
/// subtree the base alone provides stays the very same object
/// inside the result; writing through the result then writes through the base.
/// That breaks the purity this section asks for, and `SPEC.md` amendment 2 with
/// it, so the Dart result is a fresh tree throughout
/// (`SPEC_.md` amendment 38; the corpus pins the difference in
/// `fixtures/python_compat/merge_immutability/`).
///
/// The observable behavior is pinned by the generated corpus under
/// `fixtures/python_compat/merge_base/`, `merge_update/` and
/// `merge_immutability/`.
library;

import 'dart:collection';

import '../json5/json5.dart';
import '../resolver/resolver.dart';

part 'base_update.dart';
part 'values.dart';
