# DOCUMENTS.md — aiset-flutter

Catalog of documents in this project: path, purpose, and special restrictions. It does not track status;
statuses stay in their source documents.

---

## Instructions and requirements

| Path | Purpose | Restrictions |
|---|---|---|
| `AGENTS.md` | Universal agent workflow code, version 2.0.1 | Protected. Strictly read-only for every agent; corrections go to `AGENTS_.md` as proposals. **Git-ignored by user request — not versioned, so it does not travel with a clone** |
| `SPEC.md` | Baseline project specification: the full normative requirement set for aiset-flutter, 37 numbered sections (1-36 plus 24a) including the acceptance matrix | **Protected, strictly read-only for every agent.** Consolidated by the user on 2026-11-10 from the draft and the overlay, and committed as `f7bb62b`. Agents never create, edit, rename or merge into it; corrections and later approved amendments are proposed in the `SPEC_.md` overlay |
| `SPEC_.md` | Approved-amendment overlay per `AGENTS.md` | **Exists; five amendments recorded (37-41)**, created 2026-11-10 on the user's authorization after the previous overlay was consolidated. Numbering continues the baseline. Only approved or explicitly confirmed requirements go here; agents never merge it into `SPEC.md`. It additionally requests eight acceptance IDs that are absent from the protected `SPEC.md` table |
| `AGENTS_.md` | Correction proposals for `AGENTS.md` | Not an active instruction. **Does not exist yet** |

The Russian specification draft `local_aiset_flutter_specification.md` v1.2 was **deleted on 2026-11-10** by
the user's instruction, after its content was consolidated into `SPEC.md`. It was git-ignored throughout,
so it never entered history. No document may reference it as a source.

No `local_AGENTS.md` or `local_SPEC.md` overrides exist; the unprefixed files are effective.

## Current project documentation

| Path | Purpose | Restrictions |
|---|---|---|
| `README.md` | User-facing installation, configuration, startup, usage | **Does not exist yet.** Must show the zero-override connection path; implementation facts separated from roadmap |
| `ARCHITECTURE.md` | File structure, logical component boundaries, data structures and flows | Describes the **target** architecture while nothing is implemented; each section carries a status marker and must be rewritten to actual state as stages land |
| `TEST.md` | Test protocols, prerequisites, commands, scenarios, expected outcomes | **Does not exist yet.** Created when the first runnable tests appear; execution results go to memory, not appended here |
| `commands.md` | Debugging, maintenance and service commands | **Does not exist yet.** Optional; must not duplicate installation and usage docs |
| `DOCUMENTS.md` | This catalog | Update when a document's inventory, path, purpose or restrictions change — not merely because a proposal closes |
| `docs/overview.md` | Human-readable description of how the system works — the readable counterpart of `SPEC.md` and `ARCHITECTURE.md`, linking to them for normative detail instead of restating it | **Planned** (`SPEC_.md` 39). Owned by the **documenter**; other agents report errors and gaps rather than rewriting |
| `docs/build-from-source.md` | How to clone and build the project locally, with examples; prerequisites in their own section | **Planned** (`SPEC_.md` 39). Owned by the documenter. Must contain no machine-specific path (`SPEC.md` 36) |
| `docs/integration.md` | How to embed the library in a host project: storage modes, bootstrap, editor embedding, permissions, localization hookup, extensions | **Planned** (`SPEC_.md` 39). Owned by the documenter |
| `docs/grammars.md` | Accepted regex dialect subset and the bounded-integer policy, with the measured native-versus-Web differences | **Implemented** (stage 1, S1-G). A technical record, not user documentation; the coordinator owns it, not the documenter |
| `packages/aiset_flutter/lib/l10n/*.arb` | Localization resources for library chrome: labels, hints, errors, confirmations | **Planned** (`SPEC_.md` 40). English primary; first-stage set English, Chinese (Simplified), Cantonese, Russian. No user-facing string literal may remain in code (HLP-02) |
| `README_ru.md` and other `*.lng.md` | Translations of the corresponding unprefixed file | Must be synchronized with the English source; they never define independent requirements. **None exist yet** |

## Plans and assignments

| Path | Purpose | Restrictions |
|---|---|---|
| `ROADMAP.md` | Stage plan, deliverables still to create, open decisions D-01..D-09, deferred directions, risks | Entries are not implementation authorization. New ideas are labeled as proposals; approved priorities are not changed without permission |
| `TODO.md` | Near-term actionable tasks T-01..T-23 with links to requirements | A new entry is not authorization to execute it; must not duplicate proposal checklists or serve as a long-term backlog |
| `proposal_*.md` | Scoped sub-specifications per approved change | **None exist yet.** One per implementation stage is the intended convention; editable only while `draft`, `approved` or `in_progress`; closed proposals become read-only |
| `IMPLEMENTATION_LOG.md` | Execution record for a specifically assigned implementation | **Does not exist yet.** Created only when a detailed execution protocol is requested or required |
| `TODO_<agent>.md` | Per-agent current assignments | **None exist yet.** Optional; does not override governing instructions or conflicting assignments |
| `spec_<name>.md` | Feature, protocol or solution specifications extending the baseline within a scope | **None exist yet.** Created only at the user's request |

## Project memory

| Path | Purpose | Restrictions |
|---|---|---|
| `memory/history.md` | Shared append-only log of meaningful requests, decisions, events and verification | Append-only; never rewritten or archived; no secrets, no full transcripts, no diff copies. **`memory/` is git-ignored by user request: shared memory is local to this working copy** |
| `memory/context.md` | Shared compact current knowledge | Compressed before exceeding 20 000 characters; must not duplicate history, specifications or plans |
| `memory/<agent>/` | Optional personal memory (`history.md`, `context.md`) | Project-relevant findings must never live only here; created only where agent instructions or an assignment permit |

## Repository files

| Path | Purpose | Restrictions |
|---|---|---|
| `.gitignore` | Excludes build output, IDE and OS junk, Python oracle caches, secrets, and the project-local meta files `memory/`, `AGENTS.md`, `.opencode/` and `local_*` | **The user owns git**: agents edit this file only when asked and never stage, commit or push (`ROADMAP.md` §1 rule 7). Editing it after the user has staged it creates index drift, so report the change and let the user re-add. Behavior verified with `git check-ignore` |
| `.env` | Machine-specific values: local endpoint address, model name, reference-clone path, any key | **Git-ignored, never committed** (`SPEC.md` 36). Not created by agents beyond the operator's own values |
| `.env.example` | Placeholder-only template listing the key names | Tracked on purpose via a `.gitignore` negation. Must contain no real address, host name or key — a template with a live value is a violation |
| `LICENSE` | MIT license text with the notice `Copyright (c) 2026 DenisDx` | Exists at the repository root; body verified identical to the SPDX MIT text. Per-package and per-example copies are still required (`SPEC.md` 34, TODO T-06) and must use the same notice verbatim |
| `local_tools/` | Tools of the agent system or of one developer's environment. The project builds and runs without them, and other authors are expected to bring their own (`ROADMAP.md` §1 rule 14, `SPEC_.md` 37) | Git-ignored by the `local_*` rule; not project source |
| `local_tools/run_retry.sh` | Operator-side helper: restarts stalled steps (timeouts, kills, transport errors) indefinitely with backoff, while refusing to retry a genuine failure | **Not versioned** — a fresh clone does not carry it, so the retry policy in `ROADMAP.md` §1 rule 13 still applies manually. Exit codes: 0 success, 1 real failure, 2 gave up on stalls, 3 usage. Verified by execution, including the give-up path |
| `local_aiset_python_notes.md` | **Live handoff report to the `aiset` Python team**: defects A22–A33 and alignment request F2, each reproduced against `d4adb45` | Git-ignored (`local_*`). Every entry must be reproduced by executing the baseline before it is written; a reading of the source is not a finding |
| `local_aiset_python_notes_1.md` | **Delivered batch**: defects A1–A21 and the multilingual-description design F1, frozen and handed to the Python team on 2026-11-11. **FROZEN 2026-11-11 — taken into work by the Python team; modification is prohibited.** A correction to a frozen item is a new entry in the live file that references its id | Git-ignored. Each item was re-verified by the coordinator against `cbb74c7` before handover, and re-checked against `d4adb45` after the Python team implemented the batch (21 of 21 defects and F1 confirmed fixed; residual details tracked as live-file items). Nothing in it changes `aiset-flutter` requirements by itself |

## Agent configuration

| Path | Purpose | Restrictions |
|---|---|---|
| `.opencode/agents/coordinator.md` | Coordinator role code | Changeable only on the user's direct instruction. **Not versioned: the user's `.gitignore` excludes all of `.opencode/`** |
| `.opencode/agents/coder.md` | Implementation agent | Same |
| `.opencode/agents/reviewer.md` | Code and design review | Same |
| `.opencode/agents/tester.md` | Functional testing and `TEST.md` | Same |
| `.opencode/agents/uitester.md` | UI, layout, behavior and accessibility testing | Same |
| `.opencode/agents/documenter.md` | User documentation consistency | Same |
| `.opencode/agents/debugger.md` | Scheduled runtime and log analysis | Same |
| `.opencode/` (other) | Local OpenCode state, `node_modules/`, lockfiles | Generated local tooling state, not project source; excluded by `.gitignore` |

Agent-system and operator files are excluded because they belong to one author's setup, not because
they are disposable: the requirement that the project work without them is `SPEC_.md` amendment 37.

## External references

| Reference | Purpose | Restrictions |
|---|---|---|
| `https://github.com/DenisDx/aiset` @ `d4adb45` | Python behavioral authority: modules, 436 library tests + 55 demo tests, service contract. Newest commit wins (`SPEC.md` 32) | **Read-only.** Anonymous HTTPS read works; the container has no push credentials. Its own `SPEC.md`, `SPEC.md` and `SPEC_service.md` describe the Python project, not this one, and are not governing documents here |
| *(operator environment)* container runbook | Toolchain paths, Flutter Web and emulator startup, browser and search MCP, safety rules | Lives outside this repository and is named here without a path (`SPEC.md` 36). Applies to every project in that environment; it is not a project specification |
| `/run/flutterdev/topology.json`, `fd-info` | Resolved non-secret runtime topology | Never guess addresses or ports; never print secret values |

## Repository directories

`examples/` — **does not exist yet.** `packages/`, `fixtures/`, `tool/` and `docs/` exist since stage 1.
Layout and boundaries are normative in `SPEC.md` amendment 1 and described in `ARCHITECTURE.md` §1.
`tool/` is project code — the corpus generator and codegen utilities — and is unrelated to
the operator-only `local_tools/` directory listed further down.

| Path | Purpose | Restrictions |
|---|---|---|
| `tool/generate_corpus.dart` | Entry point that derives the compatibility corpus by executing the Python baseline | Project code, tracked. Takes the clone from `AISET_PYTHON_BASELINE` or `--baseline`; must contain no machine path. Any edit changes the recorded generator sha256, so the corpus must be regenerated |
| `tool/corpus_cases.dart` | The case catalog the generator walks | Project code, tracked. Same sha256 rule as the generator |
| `tool/python/corpus_driver.py` | Thin driver running the baseline over a JSON protocol | Project code, tracked. Runs with `PYTHONDONTWRITEBYTECODE=1` and no pytest cache so the reference clone stays pristine |
| `fixtures/preservation/` | 29 source-preservation cases with a manifest recording the baseline commit | Committed data. Every `expected` file is byte-identical to its `input`; that equality is the property under test |
| `fixtures/python_compat/` | 271 generated cases: parse_accept 58, parse_reject 43, values 35, operations 135 | Generated data, committed so checks run without Python. Expectations are the baseline's output; a deliberate difference keeps the baseline bytes under `baselineEvidence`, names the upstream report item in `divergence`, and **asserts the corrected behavior** (`SPEC_.md` 38) |
| `fixtures/BASELINE` | Provenance: baseline commit and branch, generator version and sha256, oracle and per-area counts | No generation timestamp by design — it would break byte-identical regeneration |
| `docs/` | User documentation and technical records, listed in the table above | Three user documents are the documenter's responsibility (`SPEC_.md` 39) |
