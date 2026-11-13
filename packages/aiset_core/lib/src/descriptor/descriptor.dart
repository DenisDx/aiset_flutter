/// Descriptor grammar, compilation and diagnostics for Aiset.
///
/// A descriptor is a JSON5 document that declares the shape of a
/// settings file: an envelope (`descriptor_version`, `project`,
/// `config_version`, `root`) plus a tree of node definitions carrying a type,
/// constraints, defaults, key governance, environment policy and the
/// declarable capability bindings (`validators`, `helper`, `hooks`).
///
/// This library compiles that grammar into an immutable [CompiledDescriptor]
/// and reports grammar problems as [DescriptorIssue] diagnostics with the
/// source position of the offending property. The observable accept/reject
/// semantics are pinned by the generated corpus under
/// `fixtures/python_compat/descriptor_*/`; the implementation is
/// Dart-native (`SPEC.md` amendments 30 and 32), and a defect in the
/// baseline is corrected and reported instead of reproduced
/// (`SPEC_.md` amendment 38).
///
/// `description` and `title` accept the two forms of `SPEC_.md`
/// amendment 41: a string, which doubles as a translation key, or the
/// `{ default, text }` wrapper. See [DescriptorText].
library;

import 'dart:convert';
import 'dart:math' as math;

import '../json5/json5.dart';

part 'compile.dart';
part 'diagnostics.dart';
part 'grammar.dart';
part 'localized_text.dart';
part 'revision.dart';
part 'validate.dart';
