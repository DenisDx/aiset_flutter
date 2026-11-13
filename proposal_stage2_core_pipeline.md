# Stage 2 — descriptor, resolver, validator, merge, service and storage modes

Status: in_progress
Approval: user instruction 2026-11-11 to resume subagent work and continue; stage scope from
`ROADMAP.md` §2 stage 2 and `SPEC.md` amendments 5–13.

Depends on stage 1 (`proposal_stage1_core_cst_corpus.md`, completed): the lossless CST, the
`apply_*` splices and the corpus generator are the substrate this stage builds on.

## Scope and requirements

**In scope:** the pure-Dart core below the UI — descriptor grammar and compiler, resolver with
provenance, validator with limits and the accepted regex dialect, merge, revisions and the single write
pipeline, the memory store, the storage adapter port with declared capabilities, the concrete adapters
(`native_file`, `app_storage`, `web_local_storage`, `web_indexed_db`, the two remote profiles, the host
bridge), and bootstrap source selection.

**Out of scope:** all presentation (`aiset_flutter` widgets, hints, ARB) — stage 3 and 5;
AI — stage 6; the descriptor-compatibility harness across implementations (T-15) beyond what
the corpus already gives; MCP and the lifecycle-hook dispatcher (`SPEC_.md` 33).

**Requirements:** `SPEC.md` amendments 2 (views and immutability), 4 (pointer and mount grammar),
5 (descriptor grammar and Flutter extensions), 6 (resolver, variables, provenance),
7 (merge, mounts, contribution), 8 (revisions, concurrency, pipeline), 9 (callbacks,
subscriptions, capabilities), 10 (three storage modes), 11 (bootstrap, backup, restore),
12 (Save As, export, import), 13 (doctor and migrations), 26 (errors and limits),
plus `SPEC_.md` 36, 37, 38 and 41. Acceptance IDs targeted: DSC-01, RES-01, MRG-01, REV-01, OPS-01,
STO-01..STO-06, LKG-01, IO-01..IO-06, SEC-01, DSC-02, DSC-03.

## Slices

Each slice is a separate sequential delegation: one writer at a time, one model, no parallel runs.

- [x] **2A** Descriptor grammar: extend the corpus generator with descriptor cases from the baseline
      (acceptance, rejection, defaults, unknown metadata, typedefs, fragments, constraint-by-type);
      implement the descriptor compiler and diagnostics in `aiset_core`; resolve
      `description` and `title` in both forms per `SPEC_.md` 41 (string key with verbatim fallback;
      `{ default, text }` wrapper; locale-unaware readers get the default-language string).
- [x] **2B** Resolver: single-pass `${VAR}` resolution, precedence chain, conversion, provenance,
      `MISSING` semantics; no process-environment access by default (`SPEC.md` 6).
- [x] **2C** Validator: types, constraints, limits, union and dynamic keys; the accepted regex dialect and
      the bounded-integer policy exactly as recorded in `docs/grammars.md`.
- [x] **2D** Merge, revisions and the pipeline: base-or-update merge with input immutability; the three
      revisions plus internal layer revisions; authorize → revisions → candidate → resolve → validate →
      preserve → probe → recheck → commit → apply → audit; dry-run and failure leave the source
      byte-identical; subscriptions and callbacks with timeout and ordering.
- [ ] **2E** Storage port, adapters and bootstrap: capability model that reports what an adapter
      cannot do; `native_file` with lock, atomic replace, backup chain and LKG;
      `app_storage`; `web_local_storage` and `web_indexed_db` with their real, different
      guarantees; the two remote profiles; the host bridge; bootstrap source selection before the main
      config is read.

## Acceptance and verification

Run from the repository root:

1. `cd packages/aiset_core && dart analyze` → no issues; `dart test` → all pass, with and without
   `AISET_PYTHON_BASELINE` (generator-dependent checks skip with a printed reason).
2. Descriptor corpus regenerated from the executed baseline is byte-identical across two runs and matches
   the committed fixtures; `fixtures/BASELINE` records the SHA actually used.
3. Every descriptor case that the baseline accepts compiles in Dart to the same meaning, and
   every case it rejects produces the same stable error code — this is DSC-01.
4. Resolver, merge and pipeline cases are proven against generated corpus data, not against
   hand-written expectations copied from prose.
5. Each adapter's declared capabilities are matched by tests: a capability an adapter cannot honor is
   reported as absent, never emulated (`SPEC.md` 11).
6. The core still compiles and tests without Flutter and without any native-only API (LIB-03).
7. Hygiene scans keep passing: no local-space data in tracked content (SEC-02), no dependency on
   operator tooling in executable content (LIB-04).
8. A divergence from the baseline is never resolved by copying a defect: the corrected
   behavior is asserted, the baseline bytes are kept as evidence, and an entry is added to
   `local_aiset_python_notes.md` (`SPEC_.md` 38).

## Sequencing and constraints

2A → 2B → 2C → 2D → 2E. 2D depends on 2A–2C because the pipeline calls resolve, validate and
preserve in that order. 2E depends on 2D because adapters are exercised through the pipeline's conditional
write, not in isolation. Stage 3 (the vertical slice with a real editor) is blocked until 2E lands.

## Progress

- 2026-11-11 proposal created; no slice started.
- 2026-11-11 **2A done** (coder): descriptor grammar corpus, compiler, diagnostics and the
  two-form `description`/`title`.
  **Corpus.** `tool/descriptor_cases.dart` (new) joins `tool/corpus_cases.dart` as a catalog the
  generator executes; `tool/python/corpus_driver.py` gained three runners. New areas under
  `fixtures/python_compat/`: **descriptor_validate 215** (64 accepted, 151 refused),
  **descriptor_compile 48** (34 compiled to a full node tree, 14 refused),
  **descriptor_semantics 37** (`node_at`, `has_node`, `node_field`, `revision`). Corpus total
  271 → **571 cases**; `fixtures/BASELINE` counts updated, same recorded SHA
  `cbb74c7…`, new generator sha256. Regeneration is byte-identical across two runs and matches the
  committed fixtures (asserted by `test/corpus_generator_test.dart`).
  Coverage of the amendment 24 list for this slice: acceptance, rejection with the
  stable code, per-node type and constraint semantics, the full constraint-by-type table
  (8 types × 8 constraints), defaults, unknown metadata (node, env, ui, helper, hook binding and
  envelope), typedefs (declaration, override, merge, cycle, shadowing, cross-file sources),
  fragments (mount, collision, deep mount, missing path), and the
  `apply`/`env`/`secret`/`read_only`/`validators`/`helper`/`hooks`/`ui` capability shapes.
  **Compiler.** `packages/aiset_core/lib/src/descriptor/` — `descriptor.dart` (library), `grammar.dart`
  (vocabulary and property table), `diagnostics.dart` (`DescriptorIssue`, `DescriptorDiagnostic`,
  `DescriptorException` with `INVALID_DESCRIPTOR`), `validate.dart` (the grammar walk and
  source positions), `compile.dart` (template expansion and merge, fragment composition, `DescriptorNode`,
  `CompiledDescriptor.nodeAt`), `localized_text.dart` (`SPEC_.md` 41), `revision.dart` (pure-Dart
  SHA-256 + `descriptorRevision`). Public surface exported from `lib/aiset_core.dart`.
  Diagnostics are compared as a set of (code, severity, path, line, column): which properties are
  reported and where is the contract, the order the rules ran in is not. Columns
  count Unicode code points, per `docs/grammars.md` §1.4 and matching the baseline exactly —
  pinned by `node_astral_column_position`.
  **Revision.** `descriptorRevision(source)` reproduces the baseline's
  `sha256:` + first 32 hex digits of the source's UTF-8 bytes, so a Flutter client and a
  Python backend agree on the compare-and-set token. Pinned by 48 compile cases plus 3 semantics
  cases; `test/descriptor_revision_test.dart` adds the published SHA-256 vectors,
  determinism, sensitivity to whitespace/BOM/line endings, and the fact that key order changes the
  revision without changing the meaning.
  **Divergences (36 cases, all asserted, none skipped).** Every one names its item in
  `local_aiset_python_notes.md`, which gained **A9–A21** (A9 was already referenced by a stage-1 case and
  is now written up). By report item: A10 ×3 (a descriptor document that is not an object raises
  `AttributeError`; the library's own guard is unreachable), A11 ×3 (`minimum`/`maximum`/`enum` skip the
  property-type check — a bad bound later crashes the validator with `TypeError`, a bad enum silently
  disappears), A12 ×4 (composition failures raise `DescriptorError`, a `ValueError`
  with no stable code), A13 ×1 (fragment mounts deeper than one level are refused with a false
  "collides"), A14 ×2 (unknown envelope metadata is never reported, in any mode), A15 ×1 (`key_pattern`
  is not compile-checked, so a malformed one matches no key), A16 ×1 (a default on a template-typed node
  is checked before expansion, i.e. never), A17 ×6 (a template reference cannot override composite keys,
  which makes the library's own children-merge unreachable), A18 ×2 (merging an array item-node template
  raises `ValueError`), A19 ×12 (a misplaced numeric bound is reported twice because `int` and
  `number` both declare it), F1 ×1 (the localized-text wrapper form, the agreed grammar extension).
  A20 (post-composition issues located in a generated JSON dump) and A21 (the
  typedef-source origin label) are corrected in the implementation but cannot be pinned by a case: the
  first would need a composed descriptor that fails validation, whose positions the baseline
  computes from a dump we deliberately do not produce, and the second only affects
  message text, which the corpus does not pin.
- 2026-11-11 **DSC-01 status after 2A:** the descriptor **grammar** half is covered — every
  accepted corpus case compiles to the same meaning (type, constraints, default and `hasDefault`,
  enum, const, children, key pattern/enum, id field, env policy, secret, read-only, apply, validators,
  helper, hooks, ui, description, title, plus the nested tree) and every rejected case
  produces the same stable code. Not yet covered, and owned by later slices: the `x_aiset_flutter`
  **per-node semantics** (the envelope entry is preserved and uninterpreted here; primary flags and
  friends land with the Flutter layer), **legacy export** that strips the extension and flattens a
  localized description, the **tree snapshot and capability projection** (`describe()`), the
  **mount grammar for data** (`SPEC.md` 4/7, slice 2D), and the **cross-implementation file round trip**
  of TPL-01/DSC-01, which needs the descriptor writer plus the Python side of F1.
- 2026-11-11 Verification: `dart analyze` → No issues found; `dart test` → **828 passed, 0 skipped**
  with `AISET_PYTHON_BASELINE` set and **827 passed, 1 skipped** without it (the skip is the
  generator suite, with a printed reason naming amendment 36). Hygiene scans (SEC-02, LIB-04)
  pass and were re-proven effective by planting a home-directory path and a private address into
  `tool/descriptor_cases.dart`, which the scan caught before the file was restored. The reference clone
  stayed pristine (`git status --porcelain` empty after generation, with
  `PYTHONDONTWRITEBYTECODE=1` and `-p no:cacheprovider`).
- 2026-11-11 **2B done** (coder): the resolver, proven by the executed baseline.
  **Corpus.** `tool/resolver_cases.dart` (new) plus three driver runners. New areas under
  `fixtures/python_compat/`: **resolver_lookup 26** (precedence chain, empty-value
  semantics, `presence`), **resolver_text 34** (placeholder syntax accepted and left
  literal, single-pass substitution, provenance of one text value), **resolver_effective 99**
  (conversion outcomes, `env.allowed`, defaults, the six leaf states, union and
  heterogeneous-array node selection, provenance per path, input immutability).
  Corpus total 571 → **730 cases**; `fixtures/BASELINE` counts and generator sha256 updated, same
  executed SHA `cbb74c7…`. Two consecutive runs are byte-identical and a fresh run reproduces the
  committed fixtures (`diff -r`, and asserted by `test/corpus_generator_test.dart`).
  Every case passes all three layers explicitly: the baseline's own default for `environ`
  is the process environment, so a corpus that relied on it would depend on
  the machine.
  **Implementation.** `packages/aiset_core/lib/src/resolver/` — `resolver.dart` (library),
  `layers.dart` (`Resolver`, `VariableSource`, `VariableLookup`, `presence`),
  `provenance.dart` (`Provenance`, `ProvenanceKind`), `resolve.dart` (`resolverMissing`,
  `isMissing`, `resolveText`, `resolveValue`, `buildEffective`, `effectiveAt`, conversion).
  Exported from `lib/aiset_core.dart`.
  **No ambient input (requirement 1).** `Resolver` takes three injected mappings and no default
  consults the machine. Proven two ways: behaviourally (`${PATH}`, `${HOME}`, `${USER}`,
  `${HOSTNAME}`, `${PWD}` all resolve to empty) and structurally (a test reads every file under
  `lib/src/resolver/` and fails on `import 'dart:io'` or `Platform.environment`), so the
  guarantee does not depend on which variables happen to exist on the runner.
  **Immutability (requirement 5).** Resolution builds a new tree; the stored tree, the
  parsed document and all three injected maps are asserted unchanged, both in the Dart tests and in
  the corpus (`inputsUnchanged` recorded for every effective case).
  **Divergences (24 cases, all asserted, none skipped).** New report items **A22–A29** in the live
  `local_aiset_python_notes.md`, each re-verified by executing the calls above it:
  A22 ×4 (provenance of a multi-placeholder string names only the last variable),
  A23 ×3 (a nested reference is half-matched and the value comes out mangled),
  A24 ×2 (array item defaults always taken from alternative 0 while resolution is positional),
  A25 ×2 (`key_enum` ignored by default filling and `key_pattern` ignored by resolution, so
  three call sites disagree about which keys an object governs),
  A26 ×2 (a placeholder in a union member is resolved by its **unresolved** shape, so a valid
  document is refused and the same text means `9` bare and `"9"` quoted),
  A27 ×8 (**high**: `build_effective` overwrites a materialized default's provenance with `file`
  while `effective_at` reports `default` for the same field),
  A28 ×1 (the number conversion accepts Python's literal underscore grouping, `1_0` → 10.0, while
  the integer conversion refuses the same text),
  A29 ×2 (both numeric conversions accept Unicode decimal digits, against the ASCII dialect recorded
  in `docs/grammars.md` §1.1). `local_aiset_python_notes_1.md` was not touched.
- 2026-11-11 **RES-01 status after 2B:** covered — single-pass substitution, the full
  precedence chain including the empty-value rule, `presence` without value exposure, conversion for
  `string`/`int`/`number`/`bool` with the exact-integer bound, `env.allowed` gating for
  bare and quoted references, default materialization, the six leaf states, provenance per
  pointer for file / environment / default, and input immutability.
  Not yet covered, by slice: the **effective view of a registered document** with owning-layer
  attribution and secret redaction (2D, where the pipeline and `layer` provenance meet);
  **limits** applied to resolved values (2C); the **mount grammar for data** and layer
  precedence (2D); and the **cross-implementation** half — a file written here must
  load in the current Python release, which the corpus now supports
  for every case it pins.
- 2026-11-11 Verification for 2B: `dart analyze` → No issues found; `dart test` → **1019 passed,
  0 skipped** with `AISET_PYTHON_BASELINE` set, **1018 passed, 1 skipped** without it (the skip is the
  generator suite, with a printed reason). Hygiene scans keep passing and were re-proven by planting
  a violation. The reference clone stayed pristine after every run.
- 2026-11-11 **Upstream update and corpus re-baseline** (coder): the reference clone was
  pulled to `main` @ `d4adb45cff867811e69c7439f22a9df93b0d01a9` ("regression fix", fast-forward
  from `cbb74c7`; the pull touches `src/aiset/{jsonsrc,descriptor,tree,errors,service,httpd}.py` and tests,
  and adds `LICENSE`). Both suites verified green on the new commit:
  library **436 passed**, `demo2/tests` **55 passed, 0 failed** (the A8 launcher case now passes via
  the new `--seed-only` mode). `pyproject.toml` unchanged: `dependencies = []` still holds.
  Executing the frozen batch's own reproduction snippets on `d4adb45`:
  **A1–A21 and F1 are implemented and verified fixed**, with two residual details (A10:
  the `DESCRIPTOR_SYNTAX` diagnostic now lacks its source position; A17: a template override cannot
  change a merged child's declared type, and the `children_options` merge still raises the
  A18-shape `ValueError` — now reachable from `validate_descriptor` itself). The live batch
  **A22–A30 is not implemented**: the pull touched neither `resolver.py` nor
  `validator.py`, and every live snippet still reproduces verbatim.
  **Reconciliation before re-baselining.** UP-1: the Dart `applyMove` no longer re-emits document
  comments inside a rebuilt root container (`_baselineOpeningOf` now keeps only comments
  that start inside the container, mirroring the upstream `c.start > parent.start`
  filter); the corpus case `move_root_array_with_document_comment` lost its `quirk` tag and is re-pinned
  to the corrected output as an ordinary case. UP-2: `env_flutter_extension_key` is registered as a
  divergence with id/report `SPEC5-FLUTTER-EXT` — SPEC.md amendment 5 treats
  `x_aiset_flutter` as known envelope metadata; the re-baselined Python reports it as
  `UNKNOWN_DESCRIPTOR_PROPERTY`, which amendment 5 explicitly permits for a legacy validator. This
  is a required intentional divergence, not an upstream defect (it is **not** A31, which is a different
  envelope-key problem already reported upstream).
  **Re-baseline.** The corpus was regenerated against `d4adb45`: `fixtures/BASELINE` now records the
  new commit, oracle `436 passed / 0 failed`, the updated generator sha256, and the same
  **730** cases (58/43/35/135/215/48/37/26/34/99). Two consecutive runs are byte-identical and
  match the committed fixtures. Divergence blocks went **63 → 32**: the 32 frozen-batch cases whose
  baseline output now equals what we had been calling "corrected" (A1×2, A9×1, A10×1 compile-side,
  A11×3, A12×4, A13×1, A14×2, A15×1, A16×1, A17×1, A18×2, A19×12, F1×1) collapsed into ordinary
  accepted/rejected cases — for these the baseline now agrees with us byte-for-byte (or, where our
  authored expectation deliberately omits diagnostic positions, on every field the
  case pins). The remaining 32 are correctly accounted: **24 live-batch resolver
  cases** (A22×4, A23×3, A24×2, A25×2, A26×2, A27×8, A28×1, A29×2 — unfixed upstream, they keep asserting
  the corrected behavior against fresh `baselineEvidence`), **7 frozen residuals** (A10×2 position
  nuance — our expectation asserts line/column 1:1 and the new baseline emits none;
  A17×5 merged-children/children_options residuals, notes refreshed to the `d4adb45` evidence), and the
  **1 new `SPEC5-FLUTTER-EXT`** divergence above. The corpus-integrity guard that
  fails on a stale divergence block passes, unchanged in force.
  Related test adjustments: the report-anchoring pattern accepts the named SPEC
  anchor next to `A<NN>`/`F<NN>`; the "corrected `set` holds its submitted value" invariant now runs
  over every accepted `set` case (the operations area carries no divergence blocks after the
  re-baseline, so restricting to divergent cases would make the check vacuous). Stale comments that
  described the pre-fix baseline (`mutations.dart` F3 note, the postcondition suite's header, the
  amendment-41 test header) were corrected to the re-baselined state.
  Verification: `dart analyze` → No issues found; `dart test` → **1019 passed, 0 skipped** with
  `AISET_PYTHON_BASELINE`, **1018 passed, 1 skipped** without it; hygiene scans pass; the reference clone is
  pristine after every generation (`git status --porcelain` empty).
- 2026-11-11 **Coordinator follow-ups after the re-baseline** (all verified by
  executing the `d4adb45` baseline before being written):
  - `local_aiset_python_notes.md` gained **A32** (the A9 fix misses a block comment before
    the inserted comma — four reproduced inputs whose result no longer re-parses, referencing frozen A9)
    and **A33** (`children_options` template override raises `ValueError` from
    `validate_descriptor` — A18's root cause via A17's fix, referencing both frozen items,
    reproduced with both an equal-length and a shorter override list).
  - **Self-correction:** the earlier draft of A31 claimed the web editor ships a
    `typedefs` control, citing `aiset_tree.js`. Grepping `d4adb45` shows that claim is unsupported
    (the only `typedef` mention in that file is a code comment). The entry now carries the
    verified rationale only, with the correction itself noted in the file.
  - Re-verification of the live batch on `d4adb45`: A22 and A23 reproduce verbatim by
    direct call; A24–A29 are attested by the 24 divergence fixtures whose fresh `baselineEvidence`
    re-encodes the baseline's current output per generation (the corpus-integrity
    staleness guard fails if any of it goes stale — currently green).
  - F2's two claims verified: `normalize_language_tag('english')` returns `'english'` upstream
    (we reject), and tree.py accepts a `locale` parameter while node-level resolution exact-matches
    (we truncate per RFC-4647).
  - Tracked-reference updates: `ARCHITECTURE.md` header, `ROADMAP.md` §1 authority
    line, and `DOCUMENTS.md` (external references row, frozen/live notes rows) now
    name `d4adb45` as the current pin with `cbb74c7` retained as the historical initial snapshot.
  - `dart analyze` → No issues found; `dart test` → **1019 passed, 0 skipped** re-confirmed after
    all edits (the suite regenerates the corpus twice itself and diffs against the
    committed fixtures, so a stale fixture or divergence fails the run, not just my
    manual diff).
- 2026-11-13 **2C done** (coder, finishing a half-done slice): the value
  validator, proven by the executed baseline.
  **Corpus.** `tool/validator_cases.dart` (pre-existing, unfinished) now compiles and is
  executed by two driver runners. New areas under `fixtures/python_compat/`:
  **validator_profile 1** (the baseline's default `Limits`, pinned as data) and
  **validator_value 174** (80 accept / 67 reject / 27 dialect rows: 7 both-refuse
  agreements, 18 documented layer splits, the A25 governance and the A34
  enum-collision divergences):
  per-type constraint accept/reject, misplaced constraints (4, refused at the
  descriptor by both engines), `const`/`enum`, union selection and array
  `children_options`, object/array recursion and paths, dynamic-key governance
  (`additional_children`, `key_enum`, `key_pattern`), the accepted regex dialect
  (16 accepted constructs, 7 both-refuse agreements, 18 documented layer splits),
  the resource limits at a full at/under/over triple each (depth, collection, string
  length, pattern length), and the 9 direct-entry cases (`present`, `undeclared_path`,
  unresolved placeholder, the `MISSING` marker). Corpus total **730 → 905**; `fixtures/BASELINE`
  counts updated, same executed SHA `d4adb45`, oracle **436/0**, new generator
  sha256, no timestamp. Two consecutive runs are byte-identical and a fresh run reproduces
  the committed fixtures; the 730 pre-existing fixtures are **byte-for-byte unchanged**
  (the new areas only add).
  **Implementation** (pre-existing, verified + one fix): `lib/src/validator/` — `validator.dart`
  (library), `issues.dart`, `limits.dart` (`Limits`, `checkLimits`), `numbers.dart`
  (exact int/BigInt/double comparison), `pattern.dart` (the accepted-dialect scanner),
  `validate.dart` (`validateDocument`, `validateValue`). Exported from `lib/aiset_core.dart`.
  **Fix found by execution:** `_classifyGroup` rejected `(?:…)` — a non-capturing group,
  a §1.1 *accepted* construct — by treating any `(?…:` as an inline flag. The corpus
  case `val_pattern_noncapture` (`(?:ab)+`) caught it. The scan now accepts
  `(?:` and detects a real scoped inline flag by its flag-letter run (`_scopedInlineFlag`).
  **Divergences (22 cases, all asserted, none skipped), each decided by executing the
  baseline rather than reading it** (the prior draft's prose-derived claims
  were wrong on several rows — see findings). Report anchors: **PENDING-A34** ×1 (the `enum`/`const`
  `_same()` `float()` collision past 2^53; the *bound* comparison is exact and NOT a
  divergence — `val_bounds_huge_above` was demoted to an ordinary agreeing case), **PENDING-A35** ×2
  (null under `union` is refused with `nullable` before the alternatives are consulted),
  **A25** ×1 (the validator's `key_pattern` uses `re.search` governance while node lookup
  and the resolver use a prefix match; one prefix predicate everywhere here), and **SPEC26-DIALECT** ×18
  (docs/grammars.md §1.2/§1.3 layer splits: constructs this engine cannot compile and refuses at
  the descriptor that the baseline loads, and vice versa). `local_aiset_python_notes*.md`
  was NOT touched (PENDING-A34/A35 are for the coordinator to file as A34+).
  **`compat_corpus_test.dart`** widened the divergence `report` regex
  (explicit, not wildcarded) to accept `PENDING-A<NN>` and `SPEC26-*` alongside
  `[AF]<NN>`/`SPEC5-FLUTTER-EXT`. `validator_corpus_test.dart` had a genuine
  compile error (`.having` applied to the `Matcher` returned by `anyOf`, not a
  `TypeMatcher`); fixed by applying `.having` to each typed alternative, checking the
  thrown exception's `code` is a non-empty stable string (no weakening).
  **DSC-01 status after 2C:** the validator half is covered — every accepted
  case validates identically in Dart and every rejected case yields the same stable rule,
  path and severity class (issue multiset, order-independent), including
  the amendment-26 limits and the `docs/grammars.md` §1 dialect and §2
  bounded-integer policy. Not yet covered, by slice: applying limits to **resolved**
  values inside the pipeline and the effective-view/layer attribution (2D), and the
  cross-implementation file round trip (needs the descriptor writer).
  Verification: `dart analyze` → No issues found (whole repo); `dart test` → **1197 passed, 0 skipped**
  with `AISET_PYTHON_BASELINE`, **1196 passed, 1 skipped** without it (the skip is the generator
  suite, with its printed reason). Hygiene scans (SEC-02, LIB-04) pass. The reference clone
  stayed pristine (`git -C <clone> status --porcelain` empty after generation, run with
  `PYTHONDONTWRITEBYTECODE=1` and `-p no:cacheprovider`).
- 2026-11-13 **2D done** (coder, s2d-finish-adjudicate): merge, revisions and the pipeline,
  proven by the observe → diff → adjudicate loop over the **executed** baseline.
  **Corpus.** `tool/merge_cases.dart` + `tool/pipeline_cases.dart` (new) join the catalog; the
  driver gained seven runners (merge, revision, pipeline_revision_pair, pipeline_case,
  pipeline_view, pipeline_callback). New areas: **merge_base 31**,
  **merge_update 30**, **merge_immutability 8**, **pipeline_revisions 14**,
  **pipeline_operations 29**, **pipeline_dry_run 8**, **pipeline_rejections 49**,
  **pipeline_revision_pair 5**, **pipeline_views 12**, **pipeline_callbacks 9**. Corpus total
  905 → **1100**; `fixtures/BASELINE` same executed SHA `d4adb45`, oracle **436/0**, new
  generator sha256 `581beb54…`, no timestamp. Two consecutive runs are byte-identical, a fresh
  run reproduces the committed fixtures, and the 905 pre-existing fixtures are byte-for-byte
  unchanged.
  **Adjudication.** Ten pipeline cases failed at handover; every one and every
  speculative `PENDING-A36..A39` anchor was decided by executing the baseline (probes in
  `/tmp/dev-probe/s2d`). Confirmed real: **A36** merge aliases base subtrees into the
  result, **A37** the unknown `prefer` raises a bare `ValueError`, **A38** the staged path
  bypasses the read-only/secret protections its direct path enforces (3 cases),
  **A39** a drop-only batch reports `applied` and advances the active revision. False (removed,
  the ordinary executed behavior asserted instead): the A38 claims that the baseline stores a
  direct secret write or a const-descendant write — it refuses both. New
  confirmed upstream defects, anchored **PENDING-A40** (`load()` discloses the secret values
  and their provenance to a principal without the secret read permission while
  `get()` denies the same pointer — SEC-01) and **PENDING-A41** (a subscription delivers a
  changed event for a secret path to a subscriber who may not read it — amendment 9).
  **Filing and re-anchoring complete 2026-11-11 (coordinator):** A36–A41 were re-verified by
  direct baseline calls bypassing our driver — A36 (merge aliases base-only subtrees; writing
  through the result mutates the caller's input), A37 (unknown `prefer` raises a bare
  `ValueError`, not an `AisetError`), A38 (three batch-bypass cases over read-only/secret
  descendants, with the direct path refusing the same value),
  A39 (drop of an existing undeclared path stores, reports `application_state='applied'`
  and advances the active revision — contradicting `_apply_change`'s own docstring, quoted in
  the entry), A40 (`load()` returns the secret value and provenance to a no-read-secret
  principal while `get()` raises `SecretAccessDenied` on the same pointer), A41 (one event
  with `changed_paths=['/secret_token']` delivered to a no-read-secret subscriber). All six
  entries are filed in the live `local_aiset_python_notes.md` (status line
  updated: twenty defects A22–A41 + F2). The catalog anchors
  `PENDING-A36..A41` were re-anchored to `A36..A41` in `tool/merge_cases.dart` and
  `tool/pipeline_cases.dart`, the corpus regenerated from the catalog
  (oracle check on), and final verification passed: `dart analyze` clean
  (package + `tool/`); `dart test` **1403 passed, 0 failed** with the clone and **1402 + 1
  printed-reason skip** without it; two regenerations byte-identical; the 905
  pre-existing fixtures byte-identical against the pre-2D snapshot; no `PENDING-A`
  anchors remain anywhere; reference clone left pristine.
  Lesson recorded from this slice: a probe reading dataclass fields by
  guessed names (`getattr(r,'application',None)` where the field is
  `application_state`) silently yields `None` and can misread a confirmed defect as
  a non-reproduction. Check attribute names against the dataclass before believing `None`.
  **Dart fixes found by execution:** `AisetOperation.fromMap` marked every known op
  unknown (all staged batches vetoed); a dry run reported changed paths the executed baseline
  leaves empty; the secret/read-only descendant rule refused a byte-identical
  re-submission and answered a changed const descendant with `FORBIDDEN` where the
  executed answer is the validator's `const` issue; `set /list/-` escaped the pipeline as
  a raw path exception instead of the central append-token veto; rename checked
  the empty `to` before the node protections (the executed order answers `FORBIDDEN` for a fixed
  declared child).
  **Coverage.** MRG-01: the merge pairs pin conflict precedence and recursion, the
  immutability area pins that inputs are unchanged and (as a corrected
  divergence) that the result aliases neither input. REV-01: the revision areas pin the byte-level
  source/descriptor revisions (BOM, CRLF, astral, order), and the CAS area pins the
  revision-pair contract between two services over one document: fresh pairs
  store in turn, a stale source or descriptor pair is `REVISION_CONFLICT`, an absent pair
  is `REVISION_REQUIRED`, and a foreign write keeps its bytes (a rejected write never
  reports stored bytes; the rejection-shape invariant is asserted over the whole
  corpus). OPS-01: every operation kind stores through one batch,
  sequential visibility and create-then-fill are pinned, the append marker
  is `add`-only, and the rejection area pins each refusal reason with its stable
  code (`REVISION_*`, `FORBIDDEN`, `SECRET_ACCESS_DENIED`, `VALIDATION_ERROR`, `BAD_REQUEST`)
  and the amendment-26 limits. APP-01: `live`/`reload`/`restart`, the strictest-policy
  rule, the undeclared-means-`restart` rule (corrected from the executed
  `applied` under A39), dry-run byte-identity, probe veto and probe timeout
  (`CALLBACK_TIMEOUT`, file unchanged), application failure with `stored = true` and
  `apply_failed`, after-save failure logged only, ordered subscriptions with the path
  filter and cancellation. SEC-01: the secret value never appears in an issue or event;
  the no-read-secret snapshot carries no secret path (a derived invariant test over every
  views case), and the two leaked surfaces are pinned as A40/A41 divergences.
  **Not yet covered:** the concrete storage adapters and bootstrap (2E). The
  host's public confirmation `confirmApplied` exists in the implementation
  (a stale confirmation is `REVISION_CONFLICT`) but no corpus case and no
  library test pin it — the executed baseline exposes no equivalent call, so
  it cannot be corpus-pinned. Flagged as an open test gap for the
  coordinator; the amendment-8 sentence it implements ("the host
  calls a public confirmation … after which the active snapshot is updated")
  is otherwise covered indirectly by `activeMatchesRevision` in the
  operations and A39 cases.
  Verification: `dart analyze` clean (package + `tool/`); `dart test` → **1403 passed, 0 skipped**
  with `AISET_PYTHON_BASELINE`, **1402 passed, 1 skipped** without (the generator suite, printed
  reason). Hygiene scans (SEC-02, LIB-04) pass and cover both new tool catalogs (re-proven
  by a planted local path). The reference clone stayed pristine after every generation.
- 2026-11-13 **Q1 resolved by the user:** defaults are not materialized under a union-typed
  node — keep the baseline behavior. Nothing in 2A–2D changes (current code and corpus already
  agree with the executed baseline here). Pinning as TODO **T-42**: add
  generated corpus cases in a resolver area that fix the union/default
  behavior (union-node default on missing stored value; object-alternative child defaults
  not filled under the union; scalar union with stored value), each expected produced by
  executing the baseline. The pin lands with the first 2E session so a later refactor
  cannot drift from the decision unnoticed.
