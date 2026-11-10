# TODO.md — aiset-flutter

Near-term actionable tasks only. Detailed plans stay in `SPEC.md` (requirements), `ROADMAP.md`
(stages, open decisions D-01..D-09) and future `proposal_*.md` files. Adding an entry here is a record, not
authorization to execute it.

Blocked until the user answers `ROADMAP.md` §4, except the tasks marked **unblocked**.

---

## Now

- [ ] **T-01 (unblocked)** Close open decisions D-01..D-09 with the user. Authority: `ROADMAP.md` §4.
- [x] **T-02** Repository: `git init` done by the **user** on 2026-11-10; `.gitignore` created and verified
      with `git check-ignore`. Agents commit, push and configure nothing (ROADMAP §1 rule 7).
- [ ] **T-03 (unblocked)** Review pass over `SPEC.md` by the user; on approval it is consolidated into
      `SPEC.md` externally. Until then no requirement here is frozen.
- [ ] **T-04 (unblocked)** Create the persistent reference clone at `/workspace/aiset-python` (D-02 resolved),
      re-fetch it before each corpus generation, and record the commit SHA used in `fixtures/BASELINE` and
      `ARCHITECTURE.md` §6. The path is supplied through `.env` (`AISET_PYTHON_BASELINE`), not hardcoded.
- [x] **T-05** Specification draft deleted 2026-11-10 on the user's instruction, after `SPEC.md` was
      consolidated. It was git-ignored, so no history rewrite was needed; a grep confirmed no document
      references it as a source.
- [x] **T-06** Root `LICENSE` written 2026-11-10: canonical MIT text, notice `Copyright (c) 2026 DenisDx`,
      body verified identical to the SPDX MIT license text. **Remaining:** copy the same `LICENSE` into each
      package under `packages/` and each example as they are scaffolded, and set `license:` in
      every `pubspec.yaml` (`SPEC.md` 34).
- [ ] **T-07** Add the attribution notice with the MIT text beside any verbatim upstream material in
      `fixtures/python_compat/` (`SPEC.md` 34).

## Stage 1 prerequisites

- [ ] **T-10** Scaffold `packages/aiset_core` as a pure Dart package and prove `dart test` runs with no
      Flutter dependency (acceptance LIB-03).
- [ ] **T-11** Write the corpus generator in `tool/`: derive expectations by **executing** the Python
      baseline (it imports with zero runtime dependencies) and running its 406 tests — never by
      transcribing Python prose documents (`S:32`). Cover parser, descriptor, resolver, pointer, operation,
      merge, doctor and error-code behavior into `fixtures/python_compat/`. Inputs and expected outputs only;
      no internal Python structures are captured.
- [ ] **T-12** Re-express the `tests/fixtures/preservation.py` corpus as Dart-side fixture data in
      `fixtures/preservation/`, unchanged in meaning: comment ownership, CRLF, BOM, no-final-newline,
      Unicode. Data and expected bytes only — no Python code or test-runner is carried over (`S:30`).
- [ ] **T-13** JSON5 CST prototype with dual UTF-8 byte and UTF-16 offset model; prove byte-identical
      round-trip of every preservation fixture before any editing operation is added.
- [ ] **T-14** Decide and document the regex dialect subset and the bounded-int range policy
      (`SPEC.md` amendments 25, 26) — implementation choice, not a requirement change.
- [ ] **T-15** Build the bidirectional descriptor compatibility harness for TPL-01: Python-accepted
      descriptors load in Dart with the same meaning, and Dart descriptors using only shared
      grammar load in Python (`S:32` tier 1).
- [ ] **T-16** Re-fetch the baseline before each corpus generation and record the commit SHA used alongside
      the fixtures; a tier 1 change upstream is an explicit re-baseline event (`S:32`).
- [ ] **T-17** Add the leak check to the test suite: scan tracked content for private-range address
      literals, host names, key and token shapes and local absolute paths, and fail on a hit (`S:36`,
      SEC-02). The manual equivalent was run on 2026-11-10 and reported zero hits.
- [ ] **T-18** Extend that same scan to neutrality. Scope is **executable** content only:
      `pubspec.yaml`, build and test scripts, sources, fixtures and any command line a user is told to
      run. A hit on `AGENTS.md`, `memory/`, `.opencode/` or `local_tools/` there is a
      violation (`SPEC_.md` 37, LIB-04). Prose in `ROADMAP.md`, `TODO.md`, `DOCUMENTS.md` and
      `ARCHITECTURE.md` MAY name those paths — it does so precisely to state the exclusion policy, and
      naming a path is not depending on it. Verify the property for real by building and testing a
      clone with those paths absent.

## Stage 6 (AI)

- [ ] **T-22** Implement the assistant connection entry point in the Flutter layer so that one library call
      attaches a provider and the ready UI surfaces the assistant (S:31, AI-05). The example configures
      only provider, options and credentials.
- [ ] **T-23** Prove absence behavior: build and test the standard editor with no AI layer installed and
      with the layer installed but not connected — no affordance, no dead control, no error (AI-06, LIB-02).
- [ ] **T-24** Opt-in AI suite reads its endpoint from the git-ignored `.env` (keys listed in
      `.env.example`), skips with an explicit reason when the file is absent instead of failing or hanging,
      and sends no `Authorization` header when no key is configured (`S:36`, AI-01).

## Reporting hygiene

- [ ] **T-20** Create `TEST.md` with the actual commands and the environment limits from
      `ARCHITECTURE.md` §5, when the first runnable tests exist. Every long or network-bound step is
      documented as a **policy** — stalled or transport-failed steps are restarted until they
      pass, genuine failures are not — with the note that each author may satisfy it with their
      own tooling. The helper used in this environment is `local_tools/run_retry.sh`, deliberately not part of
      the repository (`SPEC_.md` 37).
- [ ] **T-21** Keep `ARCHITECTURE.md` `Status: planned` markers honest: rewrite a section to
      implemented state only after its checks run.
