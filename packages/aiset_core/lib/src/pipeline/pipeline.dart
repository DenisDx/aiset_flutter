/// The single write pipeline, its revisions, authorization, callbacks,
/// subscriptions and atomic batches (`SPEC.md` amendments 8, 9, 10 and 14).
///
/// One document has one authoritative source and one write path:
/// [AisetService.applyOperations]. The editor's draft, an AI
/// proposal, a doctor repair and a host integration all reach storage
/// through the same eleven stages, in the order
/// `SPEC.md` amendment 8 fixes as normative:
///
/// ```text
/// authorize → revisions → candidate → resolve → validate → preserve
///           → probe → recheck → commit → apply → audit
/// ```
///
/// What the stages guarantee:
///
/// * **A dry run or any pre-commit failure leaves the stored
///   source byte-for-byte unchanged.** Nothing before commit
///   touches the store; a dry run stops after validate/preserve and runs
///   no probe, no notification and no audit of a write
///   that did not happen (`SPEC.md` amendment 3 write rule 7).
/// * **The whole batch is one write or none.** Operations
///   apply sequentially to a single candidate so a later one
///   sees an earlier one — create-the-container-then-fill-it
///   works inside one batch. This is not a distributed
///   transaction and no external action is rolled back.
/// * **The revision pair is a precondition.** An absent pair is
///   `REVISION_REQUIRED`, a stale one is `REVISION_CONFLICT`, and the
///   store is re-read and the exact candidate re-validated immediately
///   before the conditional write, so a long asynchronous probe never holds a
///   storage lock and never lets a stale candidate win.
/// * **A successful save is not a successful runtime apply.**
///   A failed application handler answers `stored = true` with
///   `apply_failed`; `active_revision` then differs
///   from `revision` until the host confirms the reload or
///   restart (APP-01).
///
/// The library speaks to storage through the [AisetStorage] port and the
/// adapter's declared [AisetStorageCapabilities]; a capability an
/// adapter cannot honour is reported absent and never emulated, which is
/// why a write through an adapter with no conditional write is refused unless
/// the host explicitly registered the limited single-writer
/// mode. Concrete adapters and bootstrap are slice 2E.
///
/// The observable behavior is pinned by the generated corpus
/// under `fixtures/python_compat/merge_*/`, `revision_cas/`,
/// `pipeline_operations/` and `pipeline_rejections/`.
library;

import 'dart:async';

import '../descriptor/descriptor.dart';
import '../errors/errors.dart';
import '../json5/json5.dart';
import '../merge/merge.dart';
import '../resolver/resolver.dart';
import '../revision/revision.dart';
import '../subscription/subscription.dart';
import '../validator/validator.dart';

part 'authorization.dart';
part 'candidate.dart';
part 'layers.dart';
part 'memory_storage.dart';
part 'operations.dart';
part 'principal.dart';
part 'results.dart';
part 'service.dart';
part 'storage.dart';
part 'views.dart';
