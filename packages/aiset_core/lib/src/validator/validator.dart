/// Value validation against a compiled descriptor.
///
/// The validator turns a stored value tree (what
/// [Json5Document.storedValue] yields, placeholders
/// included) and a [DescriptorNode] tree into a list of
/// [ValidationIssue]s: type and null rules, per-type constraints,
/// `const`/`enum`, object and array recursion with dynamic-key
/// governance, union alternative selection, and the resource
/// limits of `SPEC.md` amendment 26.
///
/// Three properties are fixed by the requirements and pinned by
/// the generated corpus under `fixtures/python_compat/validator_*/`:
///
/// * **A violation is an issue, never a crash or a silent pass.** Every limit
///   produces a stable-coded [ValidationIssue]; nothing truncates a
///   collection or a string.
/// * **Inputs are never mutated.** Validation only reads the value and the node
///   tree (SPEC.md amendment 2).
/// * **An issue message never contains a value.** Type and null
///   messages name the *kind*, `const`/`enum`/`union` messages are
///   fixed text, so a secret is never echoed (`SPEC.md`
///   amendments 6 and 26, SEC-01).
///
/// The accepted regex dialect (`docs/grammars.md` §1) and the bounded-integer
/// range (§2) are enforced here for values; the placeholder
/// *conversion* side was done in 2B.
///
/// This is a port of the observable behavior of the executed baseline, not a
/// copy of its structure. `SPEC_.md` amendment 38 governs every place
/// the two differ: the baseline is corrected and reported, never
/// reproduced.
library;

import 'dart:collection';
import 'dart:typed_data';

import '../descriptor/descriptor.dart';
import '../json5/json5.dart';
import '../resolver/resolver.dart';

part 'issues.dart';
part 'limits.dart';
part 'numbers.dart';
part 'pattern.dart';
part 'validate.dart';
