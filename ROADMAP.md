# ROADMAP.md — aiset-flutter

Directions, the staged plan and deferred work. Entries here are **not** implementation
authorization. Normative requirements live in `SPEC_.md`; near-term tasks in `TODO.md`; component layout in
`ARCHITECTURE.md`.

---

## 1. Where the project stands

Nothing is implemented. The repository holds the agent workflow (`AGENTS.md`), the starter document
set produced on 2026-11-10 (`SPEC_.md`, `ARCHITECTURE.md`, `ROADMAP.md`, `TODO.md`, `DOCUMENTS.md`), shared
memory, and the specification draft that is scheduled for deletion. There is no git repository, no
`pubspec.yaml`, no `SPEC.md`, `README.md` or `TEST.md`.

### Standing rules (user, 2026-11-10)

Normative text: `SPEC_.md` amendments 30, 32, 33.

1. The **newest commit** of Python `aiset` is the most correct description of required behavior; the
   practical implementation prevails over documentation, and code and tests outrank Python prose.
2. `aiset-flutter` is **not a fork**. It is written from scratch.
3. Required: **mutually compatible descriptor templates and config files**, and a **close**
   functional profile — automatic editor construction, embedding and so on — realized the Flutter way.
4. Parity is **not** a goal. Interface specifics and anything Flutter does differently go the Flutter path,
   not an imitation of the Python sample. Functionality is similar, not identical.
5. A capability Python `aiset` does **not** implement is **not** implemented here for now. This library does
   not run ahead of the Python project; when Python gains such a feature it becomes in scope later.
6. As of 2026-11-10 no newer Python branch exists, so the newest public commit is the whole authority.
7. **Git belongs to the user.** `git init` was performed outside the container on 2026-11-10. Agents stage,
   commit, push and configure nothing; the container has no credentials and no remote is set. The user
   commits and pushes from the host machine. Until the user says otherwise, **nothing is
   committed by an agent**.
8. The project is **open, MIT-licensed** (`SPEC_.md` amendment 34). Publication to pub.dev is not planned now
   but is not excluded later.
9. **English only** for everything this project produces — code, comments, documentation, memory,
   generated artifacts — with the single exception of localization and translation files, which are written in
   their target language. Dialogue with the user is in the language the user chose.
10. **`aiui` is not part of the MVP.** Generic mechanisms are built; the aiui host
    integration surface is deferred (`SPEC_.md` amendment 35).

The upstream Python behavioral authority is reachable read-only at
`https://github.com/DenisDx/aiset` (`main` @ `cbb74c7`, 2026-10-23). The container has no push
credentials, so upstream is a fixed input, not a collaboration target.

## 2. Stage plan (derived from `SPEC_.md` amendment 29)

Each stage is a candidate for its own `proposal_<name>.md` once the user approves starting it.

| Stage | Outcome | Exit condition |
|---|---|---|
| 0 | Documentation package, toolchain report, decision log closed | User accepts `SPEC_.md` and answers §4 |
| 1 | Compatibility corpus generator, JSON5 CST and source-preservation prototype, package skeletons with `pubspec.yaml` | Round-trip byte identity on the preservation fixtures; `dart test` green in `aiset_core` |
| 2 | Pure Dart core plus all three storage modes and bootstrap; revisions, descriptor, resolver, merge; core tests | Core compiles and tests without Flutter; each adapter's declared capabilities match its tests |
| 3 | Vertical slice: `basic_editor` with real persistence and the generated tree, no throwaway UI | LIB-01, LIB-02, UI-01, STO-04, DEM-01 |
| 4 | Structural operations, raw source editor, doctor, LKG, subscriptions, Save As and Import, `showcase` | OPS-01, SRC-01, SRC-02, DOC-01, LKG-01, IO-01..IO-06, REV-01, APP-01 |
| 5 | Simple and advanced modes, theme and localization, fragments and extensions, `extension_host` | SIM-01, LOC-01, EXT-01, HUI-01..HUI-12 |
| 6 | Optional AI module, OpenAI provider, reusable AI panel, **library-level assistant connection wired into the ready UI**, `ai_assistant` | AI-01..AI-06, SEC-01 |
| 7 | Remote Python compatibility, browser concurrency, full platform matrix; MCP stays deferred (`SPEC_.md` 33) | REM-01, STO-01, STO-02, TPL-01, plus the compatibility report: tier 1 and tier 2 coverage and declared divergences |

Sequencing constraints: stage 1 blocks everything because the corpus defines "correct"; stage 2
blocks stage 3 because the vertical slice must use the real pipeline; stage 6 blocks any AI claim in
documentation; stage 7 blocks any statement of tier 1 mutual compatibility with a specific backend version.

## 3. Deliverables still to be created

- `SPEC.md` — created and consolidated by the user from `SPEC_.md`, never by an agent.
- `README.md` plus translations: short connection path with no host renderer or backend.
- `TEST.md`: test invocation protocols, and `test.sh` if the user wants the convenience runner.
- `proposal_*.md` per approved stage; `IMPLEMENTATION_LOG.md` only if a detailed execution protocol is
  requested for a stage.
- `LICENSE` — MIT text plus the copyright line, one per package (D-04 resolved, `SPEC_.md` 34).
- ~~`.gitignore` and repository initialization~~ — done 2026-11-10: the user ran `git init`,
  the coordinator added `.gitignore`.
- `fixtures/` corpus, `tool/` generator, `docs/` reference set.

## 4. Open decisions requiring the user

These block stage 0 exit. Nothing below was decided silently; `SPEC_.md` states the requirement
while the choice of means is here.

**Resolved 2026-11-10 — D-01.** The newest commit of Python `aiset` is authoritative, and code
plus tests outrank Python prose documents. The corpus is generated by executing the baseline and
re-fetched per run, recording the SHA used; `cbb74c7` is kept in `SPEC_.md` as the snapshot examined,
not as a pin of truth. Normative text: `SPEC_.md` amendment 32. This also settles the mechanism half of
D-02 — the reference clone must be a fetchable working tree, not a frozen archive.

| ID | Question | Why it matters | Coordinator default if unanswered |
|---|---|---|---|
| ~~D-01~~ | ~~Is `main` @ `cbb74c7` the parity baseline?~~ **RESOLVED** — newest commit wins, code over prose (`SPEC_.md` 32); user confirmed on 2026-11-10 that no newer branch exists | Was: corpus correctness depended on the pin | Superseded by the re-fetch rule; no residual gap assumed |
| ~~D-02~~ | **RESOLVED 2026-11-10** — reference clone at `/workspace/aiset-python`, re-fetched per generation with the SHA recorded; generated fixtures ARE committed. | Was: reproducibility of stage 1 without a Python install | Closed; the clone itself is created by T-04, the SHA file by T-16 |
| ~~D-03~~ | ~~Which package identity is canonical?~~ **RESOLVED 2026-11-10** — see §4.1 for the verified naming scheme | Was: affected every `pubspec.yaml` and import path | Superseded by the measured result |
| ~~D-04~~ | **RESOLVED 2026-11-10** — MIT, the project is open. My original premise was wrong: upstream declares `license = { text = "MIT" }` in `pyproject.toml` but ships no `LICENSE` file. | Was: blocked `pubspec.yaml` metadata | Policy in `SPEC_.md` amendment 34; the `LICENSE` file is still to be written and needs the exact copyright holder string (T-06) |
| ~~D-05~~ | **RESOLVED 2026-11-10** — the user ran `git init` from the host; no remote is configured in the container and agents never commit or push (standing rule 7). `.gitignore` was created by the coordinator and verified with `git check-ignore`. | Was: a commit-based workflow | Branch is currently `master`; renaming it to `main` is the user's call, not an agent action |
| D-06 | Platform priority for CI: Android emulator and Flutter Web via the browser container are available; Linux desktop, iOS, macOS and Windows are not buildable here. | Determines what "verified" may honestly mean | Gate on `dart test`, `flutter test`, Android emulator, Web compile plus browser-container smoke; record the rest as residual risk |
| D-07 | Is a live OpenAI-compatible endpoint available for the opt-in AI suite (stage 6), or only the deterministic offline provider? | AI-01 requires a real model; without an endpoint that ID cannot close | Ship stage 6 with the offline provider and mark AI-01 unverified |
| ~~D-08~~ | **RESOLVED 2026-11-10** — `aiui` support is **not** built in the MVP. The generic mechanisms it relies on stay in scope; the aiui-specific surface is deferred (`SPEC_.md` amendment 35). | Was: how much of amendments 7 and 23 to build early | Closed; deferred list in §5 |
| ~~D-09~~ | **RESOLVED 2026-11-10** — English is mandatory for everything in this project: code, comments, documentation, memory, tool artifacts. The only exceptions are localization and translation files, written in their target language. Conversation with the user follows the language the user used. | Was: affected every document | Closed; the Russian specification draft is transient and git-ignored, and no document may cite it as a source |

### 4.1 Naming scheme (D-03, resolved by measurement)

Verified with the installed toolchain rather than by convention alone:

| Slot | Form | Evidence |
|---|---|---|
| Dart package `name:` | `aiset_flutter`, `aiset_core`, `aiset_ai`, … | `name: aiset-flutter` → `dart pub get` fails: *"'name' field must be a valid Dart identifier"*. `name: hk.emertech.aiset_flutter` passes `pub get` but `dart pub publish --dry-run` fails: *"Package name … may only contain letters, numbers, and underscores"* — a dotted name is unpublishable, and the validator also demands `lib/<name>.dart` match |
| pub.dev publisher | `emertech.hk` | dart.dev "Create a verified publisher": a publisher is identified by a **domain** you verify through Search Console, not by a reverse-DNS string |
| Android `applicationId` / iOS bundle identifier of the example apps | `hk.emertech.aiset_flutter_example` | This is the traditional home of the reverse-DNS form the user normally uses; dots are expected here |
| Repository and directory name | `aiset-flutter` | Hyphens are conventional for a repo and legal outside `name:` |

So the draft's either/or between `hk.emertech.aiset-flutter` and `hk.emertech.aiset_flutter` dissolves: neither
is the package name. Import path is `package:aiset_flutter/…`; the `hk.emertech.` prefix belongs to bundle
identifiers, and `emertech.hk` to the publisher.

Note before the first publish: pub.dev treats a package name as permanent — publishing is forever and
unpublishing is disallowed except in narrow cases — and a `LICENSE` file is required to publish, which ties
into D-04.

## 5. Deferred directions and ideas (not approved work)

- **`aiui` host integration surface**: the single `AppConfig` document convention, `plugins.<id>.settings`
  placement and `ui.settingsEditor` wiring are deferred out of the MVP by `SPEC_.md` amendment 35. The
  generic multi-document registration, merge roles, fragments, registry and bootstrap they depend on remain
  in scope.
- **MCP facade** (`aiset_mcp`): deferred by the standing rule 5 in §1 and `SPEC_.md` amendment 33 —
  upstream has no MCP implementation, so nothing is inherited and nothing is built ahead of it. Revisit only
  after Python ships one, and then also only after the service contract is stable.
- **Remote gateway** for shared AI accounts in Web, with its own authentication model, as
  distinct from BYOK.
- **Cross-tab coordination** beyond the restricted localStorage mode: BroadcastChannel plus
  Web Locks, or IndexedDB transactions as the default for concurrent Web editing.
- **Lossless big-integer extension** beyond the ±9007199254740991 interoperable range.
- **Bounded regex engine or isolate-backed evaluation** to replace the upstream practice of forbidding
  lookarounds and backreferences outright.
- **Virtualized huge-tree rendering** beyond the resource limits themselves.
- **Schema migration pipeline** as a first-class trusted API with its own fixtures; the draft requires the
  contract but no real migration exists yet.
- **Descriptor and extension grammar reference** in `docs/`, generated from the compiler rather than
  hand-maintained.
- **Performance baseline harness** for parse, splice and tree-build on the 8 MiB limit.
- **Native HTTP server adapter** in Dart as an optional package, only if a host needs to embed aiset
  service semantics rather than talk to Python.

## 6. Risks tracked at roadmap level

| Risk | Impact | Mitigation on record |
|---|---|---|
| Byte-exact preservation is far harder than a normal JSON editor | Stage 1 slips; SRC-01/SRC-02 unmet | Prototype first, corpus before any UI work, UTF-8 versus UTF-16 offset model designed up front |
| Dart Web integer and string semantics differ from native and Python | Silent data corruption on Web | Dedicated native-versus-Web-versus-Python comparison tests in stage 1 and 2 |
| localStorage cannot honor the concurrency promise | STO-01, STO-05 | Capability flags plus an explicitly restricted mode; IndexedDB suggested |
| Uncertain commit outcome on remote and native writes | Lost or duplicated writes | `CommitReport.uncertain`, reread instead of blind retry, revision checks |
| Secret leakage through search, events, diagnostics or AI | SEC-01 fail | Redaction enforced at the binding and tool layer, plus a dedicated security suite |
| UI scope creep before core parity | Both late | Stage gating: no presentation API is called stable before the three integration paths work together |
| Environment cannot verify desktop and mobile platform matrix | Overstated readiness | Honest reporting per D-06; unverified platforms listed in `README.md` and the compatibility report |
| Parity mistaken for a structural port, reproducing Python internals for no benefit | Wasted effort, unidiomatic Dart, blocked Flutter-native choices | `SPEC_.md` amendments 30 and 32 fix the boundary; `ARCHITECTURE.md` §6 is labeled a behavior index, not a layout |
| "Newest commit wins" makes the oracle a moving target | Fixtures silently regenerate under a changed implementation and break bisectability | Record the SHA per generation; treat a tier 1 change upstream as an explicit re-baseline event, not an automatic refresh |
| Compatibility scope read too wide again, forcing identity where only similarity is required | Over-claiming and wasted parity work on UI and naming | Tier 3 in `SPEC_.md` amendment 32 states that no acceptance ID requires identity there |

## 7. Out of scope

- Rewriting or re-reviewing the protected `AGENTS.md` and `SPEC.md`.
- Modifying the upstream Python `aiset` repository (no access, and it is not the goal).
- Building the `aiui` application itself, and its host integration surface for the MVP (`SPEC_.md`
  amendment 35); only the library and its examples are in scope.
- Domain-specific runtime effects of applying settings — the host owns application, the library reports state.
- A file-for-file or module-for-module port of Python `aiset`, and any reuse of its implementation
  artifacts: source, generated JS and CSS editor assets, test-runner machinery. Parity is behavioral and
  interop-level only (`SPEC_.md` amendment 30).
- Implementing features that Python `aiset` does not implement (standing rule 5, `SPEC_.md` amendment 33) —
  including the MCP facade and the lifecycle-hook dispatcher for now.
- Visual or interaction imitation of the Python web editor, and an identical feature set. Interface
  specifics go the Flutter way; functionality must be similar, not the same (`SPEC_.md` amendment 32 tier 3).
