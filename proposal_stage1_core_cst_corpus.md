# Stage 1 — core scaffold, JSON5 CST, compatibility corpus

Status: completed
Approval: user instruction 2026-11-10 "давайте начинать, запускайте исполнение первой stage";
stage scope from `ROADMAP.md` §2 stage 1 and `TODO.md` T-10..T-18.

## Scope and requirements

**In scope:** T-10 scaffold `packages/aiset_core`; T-13 JSON5 CST prototype with dual offset model;
T-12 preservation fixtures re-expressed as Dart data; T-11 + T-16 corpus generator that **executes** the
baseline and records its SHA; T-17 and T-18 tracked-content scans; T-14 the regex-dialect and
bounded-integer decisions, written down.

**Out of scope (stage 2+):** descriptor compiler, resolver, validator, service pipeline,
storage adapters, UI. T-15 / TPL-01 (bidirectional descriptor harness) is deferred here because it needs
the descriptor compiler.

**Requirements:** `SPEC.md` amendments 3 (parsing and source preservation), 8 (operations and revisions),
24 (compatibility corpus), 30 and 32 (parity tiers — corpus pins behavior only), 36 (no local-space data in
git), 37 (author neutrality). Acceptance IDs: LIB-03, SRC-01, DSC-01, RES-01, SEC-02, LIB-04.

## Verified baseline facts (2026-11-10)

- Reference clone `the reference clone (`AISET_PYTHON_BASELINE` in the git-ignored `.env`)` @ `cbb74c7d8cc1a1f3bb10f0661f6bc00514982cab` (`main`, 2026-10-23),
  41 `.py` files. Path is supplied through the git-ignored `.env` (`AISET_PYTHON_BASELINE`), never
  hardcoded in scripts.
- `aiset` imports with **zero runtime dependencies**; a venv with pytest 9.2.0 exists at
  `the reference clone (`AISET_PYTHON_BASELINE` in the git-ignored `.env`)/.venv`.
- Library suite `tests/`: **408 passed in 3.96 s**. This is the corpus source.
- `demo2/tests`: 54 passed, 1 failed. `test_launcher_seeds_missing_files_without_overwrite` fails because
  the test's own `run_launcher` helper hardcodes `timeout=30` with a stripped environment
  (`PATH=/usr/bin:/bin`, `HOME=workspace`), so the launcher is killed while serving. The limit is an
  upstream constant, not our queue — retrying cannot help. **Excluded from the corpus scope**:
  the demo launcher is not library behavior. Recorded here so nobody re-litigates it.
- Mutation contract our CST must be behaviorally compatible with (`aiset.jsonsrc`):
  `parse(text, *, origin='<memory>') -> Document`;
  `Document.apply_set(pointer, value_text, *, indent_unit=None) -> str`,
  `apply_add(pointer, value_text) -> str`, `apply_remove(pointer) -> str`,
  `apply_move(source, target) -> str`, `apply_rename(pointer, new_key) -> str`;
  `find`, `find_parent`, `paths`, `source_of`, `value_text`, `stored_value`, `format_of`,
  `line_col`, `line_indent`, `base_indent_at`.
  Node types: `ObjectNode`, `ArrayNode`, `Member`, `Item`, `ScalarNode` variants
  (`StringNode`, `NumberNode`, `BooleanNode`, `NullNode`), `TemplateNode`, `TemplateRef`,
  `Comment`. Helpers: `parse_fragment`, `parse_pointer`, `escape`, `quote_key`, `has_placeholder`,
  `block_of`, `deindent`, `reindent`, `index_of_member`, `parent_path`, `APPEND_MARKER`.

## Implementation plan

- [x] **S1-A** Scaffold `packages/aiset_core`: pure Dart `pubspec.yaml` (no Flutter), `analysis_options.yaml`,
      `lib/aiset_core.dart` exporting the public surface, empty `test/`. Prove `dart test` runs.
- [x] **S1-B** JSON5 CST: lexer + parser producing a lossless tree where every node owns its source
      span, comments are attached as leading / mid / trailing with ownership rules, and offsets are maintained
      in **both** UTF-8 byte and UTF-16 code-unit space. Round-trip `parse(text).toSource() == text`
      byte-for-byte.
- [x] **S1-C** Re-express `tests/fixtures/preservation.py` as Dart-side fixture data under
       `fixtures/preservation/` (input file + expected bytes + case metadata). Data and expected
       bytes only — no Python code, no pytest machinery.
- [x] **S1-D** Corpus generator: run the baseline in-process, emit
      `fixtures/python_compat/` for parser acceptance, rejection and values; write
      `fixtures/BASELINE` with the commit SHA, generation timestamp and the generator's own
      version. Re-running must be deterministic.
- [x] **S1-E** `apply_*` splices on the CST, byte-exact against generated corpus cases, including
      the append marker, comment ownership on removal, and Unicode/surrogate positions.
- [x] **S1-F** Scans as tests: local-space data leak check (SEC-02) and author-neutrality check (LIB-04)
      over tracked content, scoped to executable content and documented commands.
- [x] **S1-G** Record the accepted regex dialect subset and the bounded-integer policy in
      `docs/grammars.md` (T-14) — implementation decisions, not requirement changes.

## Acceptance and verification

Observable criteria, all run from a clean checkout:

1. `cd packages/aiset_core && dart test` → green, and `pubspec.yaml` has no `flutter` dependency
   (LIB-03).
2. `dart run tool/generate_corpus.dart` (or the equivalent under `tool/`) → `fixtures/python_compat/` and
   `fixtures/BASELINE` produced; a second run changes nothing (determinism).
3. Round-trip test over every `fixtures/preservation/` case → byte-identical (SRC-01 precondition).
4. Splice tests over `fixtures/python_compat/` → produced source text equals the baseline's output.
5. Scan tests → no local-space data, no operator-path dependency in executable content (SEC-02, LIB-04).
6. `dart analyze` → no errors.

Long or network-bound steps follow `ROADMAP.md` §1 rule 13: generous budgets (30–45 min for
Flutter steps), stalls retried, genuine failures never retried into green.

## Progress

- 2026-11-10 T-04 done: reference clone created and verified, baseline SHA recorded above, `.env` key added.
- 2026-11-10 Oracle health established: `tests/` 408 passed; demo2 failure explained and excluded.
- 2026-11-10 **S1-A/S1-B/S1-C done** (coder): `packages/aiset_core` scaffolded (pure Dart, no `flutter:`
  dependency); lossless JSON5/template CST in `lib/src/json5/` with dual UTF-8/UTF-16 spans,
  whitespace and comments as leaves, and baseline comment-ownership roles
  (document/opening/leading/mid/trailing/block-end); `fixtures/preservation/` holds 29 cases
  (7 verbatim from the baseline corpus, 22 authored for the remaining edge classes), every case
  validated to parse under the baseline engine before its bytes were written; manifest is
  data-only. Verification: `dart pub get`, `dart analyze` → no issues; `dart test` → 167 passed
  (round-trip byte identity, leaf-partition losslessness, dual-offset agreement with
  `dart:convert`, ownership + detach, rejection positions).
  Behavior notes for S1-D/S1-E: the baseline crashes (`IndexError`/`ValueError`) on truncated input
  where a key is expected and on malformed `\x` escapes — the Dart parser rejects with a positioned
  `Json5ParseException` instead (same accept/reject outcome; exception types are tier 3);
  the baseline overwrites the root container's own opening-comment attribute — the Dart tree keeps
  those comments classified as `opening` on the root (no round-trip or entry-ownership impact;
  revisit when `apply_move` corpus cases land).
- 2026-11-10 **independent verification by the coordinator**, not taken from the agent report:
  `dart analyze` → *No issues found*; `dart test` → *+167: All tests passed*; `pubspec.yaml` carries no
  `flutter:` dependency (LIB-03); all 29 `expected` files are byte-identical to their `input` files, which is
  the correct shape for a preservation fixture.
- 2026-11-10 differential grammar check, Dart against the **executed** Python baseline, 49 inputs
  (29 fixtures + 20 adversarial: missing colon, truncated container, mid-value comment, hex and leading-dot
  numbers, `Infinity`/`NaN`, astral-plane string, malformed escape, empty and whitespace-only source):
  **verdicts identical — 39 accepted, 10 rejected** — and every accepted input round-trips
  byte-for-byte on the Dart side.
- Asymmetry noted, not a defect: the baseline `Document` stores its source text and has no
  `to_source()`, so byte-identity of a *reconstruction* cannot be compared against Python. Our CST derives
  source from the tree, which is what amendment 3 requires; the preservation fixtures are the authority.
- 2026-11-10 neutrality and local-data scans over tracked and to-be-added content: zero hits for private
  addresses, the local endpoint host and local absolute paths, and zero references to `local_tools/`,
  `.opencode/`, `memory/` or `AGENTS.md` in executable content. Three prose files did carry
  absolute paths of the development machine, rewritten to name the `.env` key instead
  (`SPEC.md` 36).
- 2026-11-11 **S1-D done** (coder): `tool/generate_corpus.dart` + `tool/corpus_cases.dart` +
  `tool/python/corpus_driver.py`. The generator **executes** the baseline (`PYTHONPATH=<clone>/src`,
  driver over stdin/stdout JSON) and writes the observed results; expectations are never transcribed.
  It first runs the baseline's own suite (`pytest -q tests`) and refuses to generate from an
  unhealthy oracle (SPEC.md 32). `fixtures/BASELINE` records the commit SHA + branch, the generator
  version **and** its content sha256, the oracle counts and the per-area case counts.
  Counts: **parse_accept 58, parse_reject 43, values 35, operations 135 — 271 cases**.
  Determinism: two consecutive runs are byte-identical, and a fresh run reproduces the committed
  corpus byte-for-byte (proved by `diff -r` and asserted by `test/corpus_generator_test.dart`).
  **Deviation from the S1-D wording:** `BASELINE` deliberately carries **no generation
  timestamp** — a per-run timestamp makes "re-running must be deterministic" untestable. Provenance is
  the commit SHA plus the generator content hash instead. Recorded here for ratification.
  Neutrality and clone integrity: the clone path arrives only through `AISET_PYTHON_BASELINE` or
  `--baseline`; nothing inside the clone is written (`PYTHONDONTWRITEBYTECODE=1`,
  `-p no:cacheprovider`, verified with `git status`); no tracked file contains a local absolute path.
- 2026-11-11 **S1-E done** (coder): the mutation layer in `lib/src/json5/pointer.dart` and
  `lib/src/json5/mutations.dart`, exposed as `Json5Document.find`, `findParent`, `paths`,
  `valueText`, `baseIndentAt`, `lineIndent`, `applySet`, `applyAdd`, `applyRemove`, `applyMove`,
  `applyRename` (each returns the new source text and never mutates the document, so a rejected or
  dry-run edit leaves the source byte-identical). Errors carry the stable codes:
  `Json5ParseException` = `PARSE_ERROR`, `Json5PathException` = `BAD_REQUEST`,
  `Json5CommentConflictException` = `COMMENT_PRESERVATION_CONFLICT`.
  `test/compat_corpus_test.dart` runs the corpus: **269 of 271 cases byte-exact, 2 skipped as
  divergence F3** below; 440 package tests pass, `dart analyze` reports no issues.
  Covered splice classes: append marker `/…/-`, comment ownership on removal (leading travels,
  container block-end stays, a non-last entry's trailing comment survives — the baseline's own rule),
  rename preserving the value bytes, move across nesting levels, `set` with a
  placeholder value text spliced verbatim, and astral-plane documents where UTF-8 byte
  and UTF-16 code-unit offsets differ. Baseline quirks reproduced deliberately and pinned:
  opening comments of a replaced or moved container leave with it; a move inside the **root**
  array re-emits the document comments; a comment the client sends back is re-attached anyway;
  an inline removal absorbs the separator space; `_reindent` prefixes the continuation indent to lines
  that already carry their own.
- 2026-11-11 **Divergence F3** (registered per SPEC.md 24, **pending decision**, tests skipped with a
  reason): `apply_set` with an **equal-length array** replacement. The baseline's
  `_array_replacement` element-wise branch returns the whole **document** text and `_replace_node`
  then splices that document into the array position, so the result contains a copy of itself.
  - Case `set_array_equal_length_elementwise`, input
    `{\n  list: [\n    // first\n    "a",\n    "b", // second\n    "c",\n  ],\n}\n`, value_text `["x", "y", "z"]`.
    Baseline: `{\n  list: {\n  list: [\n    // first\n    "x",\n    "y", // second\n    "z",\n  ],\n}\n,\n}\n`.
    Dart: `{\n  list: [\n    // first\n    "x",\n    "y", // second\n    "z",\n  ],\n}\n`.
  - Case `set_array_equal_length_nested`, input `{\n  l: [[1], [2]],\n}\n`, value_text `[[9], [8]]`:
    the baseline output embeds two further document copies; the Dart output is `{\n  l: [[9], [8]],\n}\n`.
  - Analysis: the **baseline is wrong**. Its own test
    (`test_equal_length_array_replacement_is_elementwise`) asserts only substrings, which the
    corrupted text satisfies by accident; the intended behavior is the item-by-item
    replacement, which is what the Dart side implements. The corpus keeps the baseline bytes as
    the recorded expectation, so the correction is visible rather than hidden.
- 2026-11-11 Tier-3 exception-type differences (accepted, listed): the baseline crashes with
  `IndexError` on a truncated key position and with `ValueError` on a malformed `\x`
  escape; the Dart parser rejects both with a positioned `Json5ParseException` (same accept/reject
  outcome, no stable code on either baseline crash). These are pinned as `parse_reject` cases
  `truncated_after_comma` and `malformed_hex_escape` with `errorCode: null`, `baselineCrash: true`.
  `PathError`/`CommentPreservationConflict` map to `Json5PathException`/`Json5CommentConflictException`
  with identical stable codes; only the class names and message texts differ.
- 2026-11-11 Not pinned on purpose (no case authored): the baseline accepts Unicode-digit
  pointer tokens and then crashes on conversion, and its rename identifier regex treats a
  trailing newline as an identifier end. Both are Python artifacts with no Dart analogue; the Dart side
  rejects non-ASCII index digits and does not treat a trailing newline as an identifier.
- 2026-11-10 S1-D and S1-E implemented by the coder agent, then **independently verified by the
  coordinator**: `dart analyze` → *No issues found*; `dart test` with the baseline → *+443, 2 skipped,
  All tests passed*; `dart test` with `AISET_PYTHON_BASELINE` unset → *+441, 3 skipped, All tests passed*
  — the generator suite skips with a printed reason instead of failing (`SPEC.md` 36).
- Corpus: 271 committed cases — parse_accept 58, parse_reject 43, values 35, operations 135 — matching
  `fixtures/BASELINE` exactly. Two independent fresh generations are byte-identical to each other **and**
  to the committed fixtures, including `BASELINE`.
- The reference clone was verified pristine after generation, and no `.py` file exists under `packages/`
  (`SPEC.md` 24).
- **Ratified by the coordinator:** `fixtures/BASELINE` carries no generation timestamp. The step wording asked
  for one, but a per-run timestamp makes the determinism criterion untestable. Provenance is instead the
  baseline commit and branch, the generator version and its content sha256, and the oracle and per-area
  counts, with a test asserting no volatile field. The step wording is corrected above.
- **Ratified by the coordinator:** the generator does not re-fetch the clone. Amendment 32's
  re-fetch rule and "never modify the reference clone" are reconciled by recording the SHA actually executed,
  so a later operator fetch is reflected automatically.
- **Escalated to the user — finding F3 (high).** Two corpus cases are skipped with a recorded divergence: the
  baseline's equal-length array `apply_set` splices the whole-document result back into the array position,
  producing a document that contains a copy of itself; the baseline's own test asserts only substrings, so the
  corruption passes there. Dart performs the intended item-wise replacement.
  **Resolved 2026-11-10 by the user:** the defect is not reproduced; the corrected behavior is the
  requirement. Recorded as `SPEC_.md` amendment 38 and reported upstream as item **A1** in
  `local_aiset_python_notes.md`. Follow-up in stage 1 scope: the two cases must stop being skipped
  and instead assert the corrected output while keeping the baseline bytes as evidence.
- Follow-up added to S1-F: convert the two A1 divergence cases from skipped to asserted against
  the corrected output, keeping the baseline bytes in the fixture as evidence (`SPEC_.md` 38).
- 2026-11-10 **S1-F and S1-G implemented and verified by the coordinator. Stage 1 is complete.**
  `dart analyze` → *No issues found*; `dart test` → *+467: All tests passed* with the baseline, and
  *+466, 1 skipped* without it (the generator suite skips with a printed reason). The two A1 divergence
  cases are now asserted against the corrected output and keep the baseline bytes under
  `baselineEvidence`, with `divergence.report` pointing at item A1 of the upstream notes.
- Scan effectiveness proven, not assumed: a planted file containing a private address, a
  a home-directory path, a key-shaped string and a reference to the operator tooling directory made both the SEC-02 and the LIB-04
  tests fail with the offending rule named; after removing the plant both pass again. The scans
  walk the directory tree rather than querying git, so they run in a checkout without git.
- Corpus regeneration after the fixture changes: two fresh runs byte-identical to each other and to the
  committed fixtures and `fixtures/BASELINE`; the reference clone remained pristine.
- The native-versus-Web integer table in `docs/grammars.md` was independently reproduced by the
  coordinator with `dart compile js` and node: `9007199254740993` → `9007199254740992`,
  `9223372036854775807` → `9223372036854776000`, a 30-digit literal → `1.2345678901234568e+29`,
  `BigInt` exact, and the VM exact in all cases where the document says so.
- Stage 1 exit criteria met: round-trip byte identity on the preservation fixtures, and
  `dart test` green in `aiset_core`.
