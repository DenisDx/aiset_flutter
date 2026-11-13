/// Stable error codes and the structured failure type
/// (`SPEC.md` amendments 14 and 26).
///
/// The JSON5 source engine already carries its own positioned
/// exceptions (`Json5ParseException`), and the descriptor grammar its own
/// [DescriptorException]. Everything above them — authorization,
/// revisions, operations, the store port, callbacks — reports one
/// shared type, [AisetFailure], whose [AisetFailure.code] is
/// always one of the base codes of [AisetErrorCode]
/// (`SPEC.md` amendment 14: "Typed errors MUST keep Python-compatible codes;
/// the transport envelope and Dart exceptions share one source of codes").
///
/// An issue never quotes a configured value, so a
/// failure can be logged and shown without disclosing a
/// secret (`SPEC.md` amendments 6 and 26, SEC-01).
library;

import 'dart:collection';

part 'codes.dart';
part 'failure.dart';
