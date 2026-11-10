# ARCHITECTURE.md — aiset-flutter

Implementation status: **no code exists yet.** This document therefore records the *target* architecture
approved in `SPEC.md`, so that agents have one place describing how the system will be organized. Per
`AGENTS.md` this file must describe the implemented architecture: each section carries a status marker and
MUST be rewritten to actual state as soon as the corresponding stage in `ROADMAP.md` lands. Until then
`Status: planned` means "not built", never "done".

Behavioral authority: the **newest commit** of Python `aiset`, with its code and tests preferred
over its prose documents (`S:32`). Snapshot examined for this document: `main` @
`cbb74c7d8cc1a1f3bb10f0661f6bc00514982cab` (2026-10-23).
Requirements source: `SPEC.md`; amendments are cited below as `S:n`.

---

## 1. Project file structure

```text
aiset-flutter/
  AGENTS.md                     Agent workflow code (protected, read-only).
  SPEC.md                      Normative requirements for this project (overlay, pending revision).
  ARCHITECTURE.md               This document.
  ROADMAP.md                    Stage plan, deferred directions, open decisions.
  TODO.md                       Near-term actionable tasks.
  DOCUMENTS.md                  Document catalog and restrictions.
  memory/                       Shared project memory (history.md, context.md).
  packages/                     Published artifacts. Status: planned.
    aiset_core/                   Pure Dart: JSON5 CST, descriptor compiler, resolver, validator,
                                  merge, pointer, service pipeline, memory store, error codes.
    aiset_flutter/                Widgets, AisetEditorController, typed bindings, theme, ARB
                                  localization, standalone shell.
    aiset_storage_io/             native_file and app_storage adapters, file lock,
                                  backup chain, LKG.
    aiset_storage_web/            web_local_storage and web_indexed_db adapters.
    aiset_remote/                 HTTP clients for the aiset_service and document_api profiles.
    aiset_storage_host/           Bridge to a host-provided AisetHostStorage implementation.
    aiset_ai/                     Assistant, tool loop, proposals, provider interfaces, AI panel.
    aiset_ai_openai/              OpenAI-compatible Chat Completions provider.
    aiset_mcp/                    Optional MCP facade over the same service. DEFERRED (S:33).
  examples/                       Runnable apps, also the product's living documentation.
    basic_editor/                   Zero-override quick start (S:24a).
    showcase/                       Declarative scenario registry over a library test harness.
    ai_assistant/                   Real model; read, validate, stage only.
    remote_editor/                  Against a real Python aiset backend, both profiles.
    extension_host/                 Fragments, primary, and each customization level.
  fixtures/                       Versioned parity corpus, generated from the baseline.
    python_compat/                  Expected inputs and outputs extracted from Python behavior.
    preservation/                   Source-preservation fixtures (comments, BOM, CRLF, Unicode).
    descriptors/                    Descriptor grammar and diagnostics fixtures.
  tool/                           Corpus generator and codegen utilities.
  local_tools/                    Operator-side helpers, e.g. the stall-retry wrapper. NOT project
                                  source and NOT versioned: the local_* ignore rule excludes it.
  docs/                           API reference, integration guide, grammars, compatibility report.
```

Not present and not yet created: `SPEC.md` (protected; consolidated by the user), `README.md`, `TEST.md`,
`.gitignore`, and any `.dart` file. `ROADMAP.md` §3 lists them as deliverables.

## 2. Logical component structure

Dependency direction is strictly inward: UI and adapters depend on core; core depends on nothing but
the Dart SDK (`S:1`, LIB-03).

These boundaries come from Dart and Flutter idioms and from real platform capability differences — pure
Dart core, widget layer, per-platform storage adapters, remote profiles — and NOT from the Python module
list. The Python project is a source of required behavior, not of structure (`S:30`).

| Boundary | Responsibility it encapsulates | Public surface | Must not know |
|---|---|---|---|
| core / json5 | Lossless JSON5 CST, byte-accurate splices, comment ownership, placeholder nodes | `parse`, `Document.find`, `applySet`, `applyAdd`, `applyRemove`, `applyMove`, `applyRename` | Flutter, files, HTTP |
| core / descriptor | Compile envelope 1.0 plus `x_aiset_flutter`, typedefs, fragments, structural rules, diagnostics | `compileDescriptor`, `validateDescriptor`, `nodeAt`, `revisionOf` | Storage, UI |
| core / resolver | `${VAR}` single-pass resolution, precedence chain, conversion, provenance | `resolveValue`, `buildEffective`, injected `Resolver` sources | Process environment, secret stores |
| core / validator | Type, constraint, limit, union and dynamic-key checks; structured issues | `validateValue`, `validateDocument`, `Limits` | Presentation |
| core / service | The one write path: authorize → revisions → candidate → resolve → validate → preserve → probe → recheck → commit → apply → audit (`S:8`) | `AisetService`, `AisetDocumentRegistration`, `openSession`, operations, doctor, rollback, subscribe | Transport details, widgets |
| core / storage port | Abstract adapter contract plus capability flags (`S:10`, `S:11`) | `AisetStorage`, `AisetStorageCapabilities` | Concrete backends |
| `aiset_storage_io` | File and app storage, locking, atomic replace, backup rotation, LKG | `native_file`, `app_storage` adapters | Descriptor semantics |
| `aiset_storage_web` | localStorage and IndexedDB adapters, quota and availability errors, envelope atomicity | same port | Cross-tab promises it cannot keep |
| `aiset_remote` | `aiset_service` and `document_api` profiles, envelope mapping, uncertain-outcome handling | same port plus profile config | Server-side file paths |
| `aiset_storage_host` | Calls the host object; never opens host files | `AisetHostStorage` bridge | Host storage internals |
| flutter / controller | Editor semantics: snapshots, staged operations, dirty state, validation, conflicts, permissions, proposal merge, commands | `AisetEditorController`, `AisetSubformSession` | Rendering |
| flutter / presentation | Default UI, slots, decorators, typed bindings, theme tokens, ARB strings, adaptive layout; hosts the assistant entry and panel when one is connected | `AisetEditor`, `AisetSettingsPage`, `AisetSettingsApp`, `AisetBoundField`, `AisetGeneratedSubform` | Private core shortcuts — it uses the same public contracts a host uses (`S:16`); it does not hard-depend on the AI layer (`S:31`) |
| `aiset_ai` | Bounded session, tool loop, proposals, approval binding, secret redaction; **the connection API that wires the assistant into the ready UI** (`S:31`) | `AisetAiProvider`, `AisetAiAssistant`, `AisetProposal`, `AisetAiPanel`, assistant connection entry point | Direct storage writes, which are forbidden (`S:21`) |
| `aiset_mcp` | **Deferred** (`S:33`): MCP facade over the existing service, permissions, revisions and codes, to be built only after Python ships one | optional entry point | A second validation path; building it ahead of the baseline |

Autonomy boundaries. `aiset_core` is independently executable as a Dart library and is the only package that
must compile without Flutter. Each storage adapter, the remote profiles, the AI packages and MCP are separately
deployable optional dependencies: an application that does not install them MUST still get a working editor
(`S:16`, LIB-02). For the AI layer this is two-sided: it is optional to install, yet when it is installed the
assistant is connected and rendered by library code, not reassembled by the host or an example (`S:31`,
AI-05, AI-06).

Extension points, all registry-based and reachable only from trusted Dart code (`S:23`): descriptor and data
contributions, custom editors and helpers, semantic validators, resolvers, storage adapters, AI providers.
Nothing is registered by data arriving from a server (`S:18`).

## 3. Data structures and data flows

### 3.1 Principal representations

- **JSON5 CST** — a `Document` owning the original text plus object, array, scalar and template nodes, with
  member and item records carrying leading, mid and trailing comment lists and comma position. Every node keeps
  source offsets. Offsets are maintained in both UTF-8 byte and UTF-16 code-unit space so a splice and an error
  position stay correct across emoji and surrogate pairs (`S:3`).
- **Compiled descriptor** — envelope metadata plus a node tree: type, constraints, default, enum, const,
  children map, key pattern or key enum, id field, env policy, secret, read-only, apply, validators, helper,
  hooks, ui, description, title. Carries `revision` (hash of descriptor source) and the recognized
  `x_aiset_flutter` extension keyed by data JSON Pointer (`S:5`).
- **Four value views** — stored source text and CST; effective tree plus provenance map; active snapshot (what
  the application applied); draft (ordered staged operations plus editing buffers). Six distinct leaf states:
  absent, explicit null, false, zero, empty string, default (`S:2`, DAT-01).
- **Operations** — `set`, `add`, `remove`, `move`, `rename`, `drop` with JSON Pointer paths and `valueText` held
  as JSON5 source text, so a placeholder or a number format survives a round trip (`S:8`).
- **Identity** — stable node identity for bindings and subform targets, derived from the descriptor `id` field,
  the pointer, and a session-local token for newly created items. A bare array index is never identity
  (`S:17`, `S:18`).
- **Issues** — path, rule or code, severity, message, optional line and column. Errors carry one of the 18
  stable codes shared by exceptions and transport envelopes (`S:26`).
- **Capabilities** — per node: edit, add, remove, reorder, add-child, remove-child, key options, key pattern,
  unsupported reason. Per adapter: persistent, conditional write, cross-context concurrency, source
  preservation, backup, history, load-LKG, change notifications, export access, validation authority
  (`S:11`, `S:15`).

### 3.2 Where data comes from and goes

| Flow | Input origin | Transformation | Durable output | Consumers |
|---|---|---|---|---|
| Initial load | Bootstrap parameters select an adapter; the adapter returns source text plus revision | parse → resolve → validate → build snapshots | none | Host, editor |
| Edit | User gesture or AI proposal | binding command → staged operation in the draft | none until Apply | Editor, validation |
| Apply | Draft plus expected revision pair | the full pipeline of `S:8` | one write through the selected adapter | Storage, audit, subscribers, host application handler |
| Remote read and write | Backend API | envelope mapping; for `document_api` the candidate is built and validated locally | backend storage | Same session contract as local |
| Export | Current saved version or validated candidate | secret policy applied; no reformatting | user-chosen file or browser download | User |
| Import | User-selected JSON5 file | size and encoding → parse → version → validate → diff review → confirm | revision-checked commit via the current adapter | Same as Apply |
| Doctor | Current document plus descriptor | report; explicitly enabled repair classes produce operations | only if the repaired candidate is valid | User, host |
| AI loop | Provider stream | tool calls limited to read, validate, stage | none — staging only | Proposal review UI, then Apply |

### 3.3 Invariants that cross boundaries

1. Only the service pipeline writes. Widgets, AI tools, extensions and the Config wrapper have no write path
   around it (`S:14`, `S:21`).
2. A rejected, failed or dry-run operation leaves the source byte-for-byte identical (`S:3`).
3. Every write is conditional on the source and descriptor revision pair (`S:8`).
4. Secrets are absent from effective payloads sent to clients, from the search index, from events to
   unpermitted principals, from the default export, and from every AI surface (`S:6`, `S:21`, SEC-01).
5. Presentation reads bindings and never reads storage; commands it emits are re-checked by the service
   (`S:17`, HUI-09).
6. An adapter reports only the guarantees it can honor; a missing capability is surfaced, not
   emulated (`S:11`).

## 4. Runtime object model (entry points)

```text
AisetService
  register(AisetDocumentRegistration) -> registration
  openSession(documentId, principal)  -> AisetSession
  listDocuments / load / reread / loadLkg / get / getTree
  validateValue / validateDocument / validateOperations / applyOperations
  doctor / rollback / subscribe / descriptor diagnostics
AisetSession            immutable per-load view plus the revision pair
AisetEditorController   stageOperations / getPendingOperations / validatePending / applyPending /
                        revert / reload / expandAll / collapseAll /
                        showAbsent / valuesAsText / search / revealPath
AisetSubformSession     target / field / validate / buildPatch / accept / cancel / dispose
Assistant connection    one library call or bootstrap parameter per controller or session attaches a
                        provider and assistant, and the ready UI then surfaces it (S:31). Per-instance,
                        never a process-wide singleton.
```

Ownership: the service owns adapters and registries; a session owns a snapshot; the controller owns the draft; a
subform session owns an isolated child draft. Disposal rules and the host-versus-internal controller ownership
split are normative in `S:14` and `S:18`.

## 5. Platform and toolchain constraints (verified 2026-11-10)

This table describes **one development environment**, not a requirement on a contributor's machine and
not the product's platform support matrix, which is `SPEC.md` amendment 25. It is recorded because it bounds
what the team here may honestly claim as verified. Nothing in the build or test path may depend on
the tooling named below (`SPEC_.md` 37).

| Capability | State in this container | Architectural consequence |
|---|---|---|
| Flutter 3.47.9 stable, Dart 3.13.7 | available | SDK floor for all packages |
| `flutter test` on the VM | available | Primary gate for core and widget tests |
| Android SDK 36, build-tools 36.0.0, AVD `flutterdev_api36`, adb, JDK 21 | available | Mobile target; `app_storage` and `native_file` verified on device |
| pub.dev and pub storage | reachable | Third-party packages may be fetched |
| Chrome, `--platform chrome` | absent | Web checks are compile-level here; browser runtime goes through the Playwright container only |
| Linux desktop toolchain (clang, cmake, ninja, pkg-config) | absent, no sudo | Linux desktop build and run cannot be verified; `native_file` is verified on the Dart VM and Android instead |
| iOS, macOS, Windows toolchains | absent | Not verifiable in this environment; residual risk in `ROADMAP.md` §6 |
| Playwright MCP browser container | configured | The only sanctioned Flutter Web runtime check |
| Live OpenAI-compatible endpoint | available, no authorization | Opt-in AI suite can run for real (AI-01, AI-05). Address and model are local-space data: they live in the git-ignored `.env` and are referenced by variable name only (`S:36`) |
| Verification scope agreed 2026-11-10 | Web and Android | "Verified" claims are limited to these two platforms until further toolchains exist |
| Python 3, ripgrep, jq, sqlite3 | available | Corpus generation from the baseline and fixture diffing |
| Git write access to the upstream repo | none; anonymous read only | Upstream is a fixed reference; parity data is vendored into `fixtures/` |

## 6. Python baseline: behavior index (not a target layout)

Read-only reference used to generate the compatibility corpus, verified against the pinned commit.
**This section is not a porting plan.** §1 and §2 are the only target structure. There is no expectation
that a Python module becomes a Dart file, package or class, and no line below authorizes copying a
Python internal design (`S:30`).

Each row names behavior that a fixture may pin, per `SPEC.md` amendments 24, 30 and 32, and is worth
consulting for tier 1 and tier 2 logic. Line counts belong to the baseline files and indicate only how
much behavior each area covers. Expectations come from **executing** the baseline, not from its prose.

| Python module | Lines | Observable behavior to pin | Corpus area (amendment 24) |
|---|---|---|---|
| `src/aiset/jsonsrc.py` | 1217 | JSON5 acceptance, rejection and values; comment ownership; byte-exact source text produced by each splice | parser; operation to resulting source text |
| `src/aiset/descriptor.py` | 1216 | Grammar acceptance and rejection, type and constraint semantics, defaults, unknown-metadata reporting | descriptor issues, types, defaults, unknown metadata |
| `src/aiset/validator.py` | 444 | Validation outcomes, `Limits`, exact-integer boundary, forbidden regex features | descriptor; authorization and error codes |
| `src/aiset/resolver.py` | 374 | Placeholder resolution, precedence chain, conversion, provenance | resolver precedence and conversion |
| `src/aiset/service.py` | 1736 | Pipeline outcomes, authorization, operation semantics, atomic batches, subscriptions | authorization and error codes; trees and atomic batches |
| `src/aiset/store.py` | 384 | Persistence guarantees: atomic replace, lock behavior, backup rotation, conflicted copy, LKG | LKG, backup and application behavior |
| `src/aiset/tree.py` | 462 | Source and effective tree shape, per-node capability reporting | source and effective trees |
| `src/aiset/doctor.py` | 595 | Report content, the three repair classes, skipped reasons | doctor reports and repairs |
| `src/aiset/merge.py` | 60 | Base-or-update preferred merge result, input immutability | merge base and update behavior |
| `src/aiset/pointer.py` | 110 | Pointer parse, escape, resolve, append marker | JSON Pointer and mount edge cases |
| `src/aiset/config_obj.py` | 284 | Host-facing read and write semantics, mount resolution and placement | resolver; merge |
| `src/aiset/errors.py` | 190 | The 18 stable codes and their HTTP mapping | authorization and error codes |
| `src/aiset/httpd.py`, `asgi.py` | 451, 207 | The HTTP contract a Dart client must satisfy against a real backend | remote interop, stage 7 |
| `src/aiset/cli.py` | 316 | Descriptor validation exit behavior and diagnostics | descriptor issues |
| `src/aiset/assets/*` | — | Evidence of which editor **capabilities** exist, not of their appearance or structure. The generated JS and CSS are **not** a source to translate and not a visual target: the Flutter editor is built from `S:15` and `S:16` with native widgets, the Flutter way (`S:32` tier 3) | editor feature checklist, manual verification |
| `demo2/agent.py` | 500 | Tool loop semantics, bounded content, the four tool contracts | AI tool contracts |
| `tests/` | 406 test functions in 12 modules | Regression evidence for every area above | `fixtures/python_compat` |

HTTP routes to satisfy client-side in `aiset_remote` — this is genuine interop and MUST match the
backend: `GET /descriptor`, `GET /tree`, `GET /documents`, `POST /validate`, `POST /document/doctor`,
`POST /document/validate`, `POST /operations`, `POST /operations/validate`, `POST /env`, `POST /load`,
`POST /load/lkg`, `POST /descriptor/validate`, plus `GET {base}/health` and `/assets/` static serving, with
`base` defaulting to `/api/settings`.

Python capabilities that do **not** exist upstream and MUST NOT be presented as parity — verified in the
baseline README and `SPEC_service.md` §11: the MCP adapter, and the descriptor lifecycle-hook dispatcher. Hook
grammar is accepted; binding execution returns `UNSUPPORTED_CAPABILITY`.

Where a Dart-native mechanism differs beneath the observable surface — CST node representation, isolate and
async concurrency, file locking strategy, widget and controller architecture, test framework — the
Dart-native design wins; only the pinned behavior above has to match (`S:30`).
