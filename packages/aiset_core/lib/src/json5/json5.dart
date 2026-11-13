/// Lossless JSON5 concrete syntax tree for Aiset.
///
/// The tree owns every code unit of the source text: whitespace runs and
/// comments are nodes too, so [Json5Document.toSource] reconstructs the
/// input byte-for-byte from the tree alone. Offsets are maintained in
/// both UTF-8 byte and UTF-16 code-unit space (SPEC.md amendment 3), and every
/// comment carries an ownership role and owner.
///
/// On top of the tree, [Json5Document] offers the localized edits
/// `applySet`, `applyAdd`, `applyRemove`, `applyMove` and `applyRename`
/// (SPEC.md amendment 8): each returns the full source text after one
/// splice, leaves every other byte untouched, and is pinned case by case by
/// the generated corpus under `fixtures/python_compat/`.
library;

import 'dart:typed_data';

part 'document.dart';
part 'mutations.dart';
part 'nodes.dart';
part 'offsets.dart';
part 'parser.dart';
part 'pointer.dart';
