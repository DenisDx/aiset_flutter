/// Environment placeholder resolution for Aiset.
///
/// A settings document may hold `${VAR}` and `${VAR:-default}`
/// references, either as a whole value or inside a string. This library turns
/// a stored tree into an effective value: it substitutes each
/// reference once, converts the text to the type the descriptor node
/// declares, fills descriptor defaults for absent fields, and records where
/// every value came from.
///
/// Two properties are deliberate (`SPEC.md` amendments 2 and 6):
///
/// * **No ambient input.** Values come only from the [Resolver] layers the
///   host injects. This library never reads a process environment or a `.env`
///   file, so the same document resolves identically on every machine and
///   a Web build cannot reach the user's environment.
/// * **Single pass.** A resolved value is data. It is never scanned again for
///   placeholders, so an environment value cannot inject structure
///   or another variable.
///
/// The observable behavior is pinned by the generated corpus under
/// `fixtures/python_compat/resolver_*/`.
library;

import '../descriptor/descriptor.dart';
import '../json5/json5.dart';


part 'layers.dart';
part 'provenance.dart';
part 'resolve.dart';
