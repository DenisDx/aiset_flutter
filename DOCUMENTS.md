# DOCUMENTS.md — aiset-flutter

Catalog of documents in this project: path, purpose, and special restrictions. It does not track status;
statuses stay in their source documents.

---

## Instructions and requirements

| Path | Purpose | Restrictions |
|---|---|---|
| `AGENTS.md` | Universal agent workflow code, version 2.0.1 | Protected. Strictly read-only for every agent; corrections go to `AGENTS_.md` as proposals. **Git-ignored by user request — not versioned, so it does not travel with a clone** |
| `SPEC.md` | Baseline project specification: the full normative requirement set for aiset-flutter, 37 numbered sections (1-36 plus 24a) including the acceptance matrix | **Protected, strictly read-only for every agent.** Consolidated by the user on 2026-11-10 from the draft and the overlay, and committed as `f7bb62b`. Agents never create, edit, rename or merge into it; corrections and later approved amendments are proposed in the `SPEC_.md` overlay |
| `SPEC_.md` | Approved-amendment overlay per `AGENTS.md` | **Exists, empty**, created 2026-11-10 on the user's authorization after the previous overlay was consolidated. Numbering continues the baseline: the first recorded entry is amendment 37. Only approved or explicitly confirmed requirements go here; agents never merge it into `SPEC.md` |
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
| `https://github.com/DenisDx/aiset` @ `cbb74c7` | Python behavioral authority: modules, 406 tests, service contract. Newest commit wins (`SPEC.md` 32) | **Read-only.** Anonymous HTTPS read works; the container has no push credentials. Its own `SPEC.md`, `SPEC.md` and `SPEC_service.md` describe the Python project, not this one, and are not governing documents here |
| `/workspace/AGENTS.md` | Container runbook: toolchain paths, Flutter Web and emulator startup, Playwright and SearXNG MCP, safety rules | Applies to every project under `/workspace`; not a project specification |
| `/run/flutterdev/topology.json`, `fd-info` | Resolved non-secret runtime topology | Never guess addresses or ports; never print secret values |

## Planned directories

`packages/`, `examples/`, `fixtures/`, `tool/`, `docs/` — **do not exist yet.** Layout and boundaries are
normative in `SPEC.md` amendment 1 and described in `ARCHITECTURE.md` §1. `tool/` remains the planned home of
project code — the corpus generator and codegen utilities — and is unaffected by the operator-only
directory below.

| Path | Purpose | Restrictions |
|---|---|---|
| `local_tools/` | Tools of the agent system or of one developer's environment. The project builds and runs without them, and other authors are expected to bring their own (`ROADMAP.md` §1 rule 14, `SPEC_.md` 37) |
| `local_tools/run_retry.sh` | Operator-side helper: restarts stalled steps (timeouts, kills, transport errors) indefinitely with backoff, while refusing to retry a genuine failure | **Not project source and not versioned** — the `local_` prefix matches the `local_*` ignore rule, so a fresh clone does not carry it. Exit codes: 0 success, 1 real failure, 2 gave up on stalls, 3 usage. Behavior verified 2026-11-10 on all four paths. Where the helper is absent, the retry policy in `ROADMAP.md` §1 rule 13 still applies manually |
