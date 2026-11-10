# SPEC_.md — aiset-flutter specification overlay

Purpose: normative requirements for `aiset-flutter` — a standalone Dart/Flutter settings library
compatible with the Python `aiset` project at its observable surface, with a native Flutter settings
editor. Compatibility means behavior and interop, not structure: see amendment 30.
This is the specification overlay defined in `AGENTS.md`. After user revision it is consolidated into
`SPEC.md` by the user or an external process, never by an agent.

Behavioral authority: the **newest commit** of Python `aiset` at
`https://github.com/DenisDx/aiset` (`main`), and its code and tests take precedence over its prose
documents (amendment 32). Snapshot in force when these documents were written: `main` @
`cbb74c7d8cc1a1f3bb10f0661f6bc00514982cab` (2026-10-23) — a record of what was examined, not a pin of
truth; it is re-checked and recorded per corpus generation. Behavior index: `ARCHITECTURE.md` §6 —
a semantic reference, **not** a target file layout.

Modality: **MUST** = mandatory, **SHOULD** = recommended, **MAY** = optional. Dart snippets are design
contracts for a future implementation, not existing API.

Status: pending revision. Nothing is implemented, so every amendment below has
`State: confirmed requirement (not yet implemented)`. Open decisions requiring user input are collected
in `ROADMAP.md` §4.

---

## 1. Purpose, portability and project boundaries
Affected: new baseline sections "Purpose", "Boundaries", "Repository and packages".
Approval: user instruction 2026-11-10 to form the starter document set from the reviewed specification draft v1.2 (2026-11-09).
State: confirmed requirement (not yet implemented)
Change:
- The library MUST be connectable without copying its sources, without a separate Python backend and
  without mandatory AI. It MUST run in mobile and desktop Flutter apps and in Flutter Web. The core
  MUST be usable from pure Dart.
- The library MUST own: source parsing and editing; descriptor compilation, value resolution and
  validation; revisions and the write pipeline; staged changes, tree, search and editors; storage and
  transport adapters; the API for connecting helpers, validators, AI providers and extensions; and the
  library AI assistant when the optional AI package is installed.
- The host MUST own its domain code, authentication, document placement, permission granting, runtime
  application of settings and credential delivery through the resolver. The host MUST NOT duplicate
  library algorithms.
- A minimal application MUST consist of: bootstrap connection parameters for one of the three storage
  modes, config and descriptor assets, localization and style parameters, and explicitly connected AI
  modules. For the standard editor the host MUST NOT need to write its own settings screen.
- Repository layout (package names normative; the physical split may be refined before implementation
  without changing architectural boundaries): `packages/aiset_core` (pure Dart: parser, descriptor,
  service, memory store), `packages/aiset_flutter` (widgets, controllers, theme, localization, app
  shell), `packages/aiset_storage_io` (file store, locks, backups; native only),
  `packages/aiset_storage_web` (localStorage and IndexedDB, different guarantees),
  `packages/aiset_remote` (`aiset_service` and `document_api` HTTP profiles),
  `packages/aiset_storage_host` (bridge to a provided host storage API), `packages/aiset_ai`
  (assistant, tools, proposals, provider interfaces), `packages/aiset_ai_openai` (OpenAI-compatible
  provider), `packages/aiset_mcp` (optional MCP facade); `examples/basic_editor`, `examples/showcase`,
  `examples/ai_assistant`, `examples/remote_editor`, `examples/extension_host`;
  `fixtures/python_compat`, `fixtures/preservation`, `fixtures/descriptors`; `tool/`; `docs/`.
- Package dependencies MUST point from adapters and UI toward core, never the reverse. `aiset_flutter`
  MUST provide convenient exports for ordinary consumers but MUST NOT pull AI, native file APIs or a
  server as mandatory dependencies. Production code MUST NOT import examples. Examples MUST import the
  public API only; access to `lib/src` is forbidden.
Reference: acceptance IDs LIB-01, LIB-02, LIB-03.

## 2. Document model, views and immutability
Affected: new baseline section "Document model".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- One `AisetService` MUST be able to register several allowlisted documents. For the `aiui` host exactly
  one main `AppConfig` document is registered; UI, AI, provider and plugin settings are branches of it
  (that aiui-specific convention is deferred by amendment 35; the multi-document capability is not).
  Other documents are permitted only by explicit host architecture, never as hidden independent
  per-module settings.
- Registration MUST carry documentId, storage mode (`remote_api`, `host_api` or `local`), adapter
  reference, descriptor source, typedef sources, fragments, resolver and access policy. User-facing APIs
  MUST accept a documentId, never an arbitrary file path.
- The library MUST distinguish four views: stored/source (original JSON5, comments, placeholders);
  effective (computed values, defaults, provenance); active (values applied by the application); draft
  (unsaved editor operation sequence).
- Absent, explicit null, `false`, zero, empty string and default are six distinct states. Metadata and
  provenance MUST NOT be written into user values.
- A snapshot MUST be immutable from the consumer's point of view; changes MUST go through the service
  pipeline, never by mutating a returned `Map`.
Reference: acceptance IDs DAT-01, STO-06.

## 3. JSON5 parsing and source preservation
Affected: new baseline section "JSON5 and source preservation".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- A lossless syntax-tree/token model bound to the source text is mandatory. Plain decode → Map → encode
  is NOT an acceptable JSON5 editor.
- Supported constructs, fixed by the compatibility corpus: `//` and block comments, single and double
  quotes, unquoted keys, trailing commas, Unicode, escaped strings, CRLF/LF, BOM, missing final newline,
  and quoted or unquoted `${VAR}` / `${VAR:-default}` placeholders.
- An unsupported token MUST be rejected with its position, never silently normalized. Duplicate keys are
  an error. Non-finite numbers MUST NOT reach ordinary JSON transport without an explicitly agreed
  representation.
- Write rules, all mandatory:
  1. Unchanged regions keep the original UTF-8 bytes.
  2. Comments keep their ownership of the corresponding field or element.
  3. Moving an array element moves its comments with it.
  4. Rename changes the key in place and is not performed as remove plus add.
  5. A placeholder is not replaced by a resolved secret on save.
  6. If safe preservation is impossible, return `COMMENT_PRESERVATION_CONFLICT`.
  7. A dry run and any pre-commit failure leave the source byte-for-byte unchanged.
- The offset model MUST explicitly separate UTF-8 byte offsets from UTF-16 string offsets; error
  positions and splices MUST NOT break on emoji and surrogate pairs.
Reference: acceptance IDs SRC-01, SRC-02.

## 4. Addressing: JSON Pointer and mount grammar
Affected: new baseline section "Addressing".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- The editing API MUST address nodes with JSON Pointer: root is the empty string, `/` is a key with an
  empty name, `~0` and `~1` escapes are supported. A numeric object key is not an array index. Dotted
  paths MUST NOT be used instead of Pointers in operations.
- The additional mount grammar MUST stay compatible: `workers.myworker`, `workers.items.[id=myworker]`,
  and escaped dots inside a key. Zero or multiple matches for an identity selector are an explicit error.
- Mount grammar and JSON Pointer are different API types and MUST be documented as such; conversion
  between them MUST be explicit.
Reference: acceptance IDs OPS-01.

## 5. Descriptor grammar and Flutter extensions
Affected: new baseline sections "Descriptor grammar", "Flutter descriptor extension".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- The base envelope MUST stay compatible with Python `descriptor_version: "1.0"` (`descriptor_version`,
  `project`, `config_version`, `root`).
- Portable constructs: types `string`, `int`, `number`, `bool`, `null`, `object`, `array`, `union`,
  `any`; `required`, `nullable`, `default`, `enum`, `const`; `minimum`, `maximum`, `min_length`,
  `max_length`, `pattern`; `min_items`, `max_items`, `unique_items`; `children`, `children_options`,
  `additional_children`, `key_pattern`, `key_enum`, `id`; `description`, `title`, `ui`, `env.allowed`,
  `env.convert`; `secret`, `read_only`, `apply`; `typedef` and `typedef_sources`; descriptor
  fragments; validators, helper and hooks as declarable capability bindings.
- All structural restrictions carry over from the Python compiler and tests, including: `required` with
  `default` is incompatible, `enum` with `const` is incompatible, `key_pattern` with `key_enum` is
  incompatible, constraints inappropriate for scalar types are forbidden, typedef collision and
  cycle detection are errors, and shadowing of primitive types is not allowed.
- Unknown project metadata MUST be preserved, MUST NOT be executed, and MUST emit
  `UNKNOWN_DESCRIPTOR_PROPERTY` in development diagnostics. Strict validation turns unknown properties
  into errors. Arbitrary metadata MUST NOT be recursively interpreted as commands.
- New Flutter fields MUST NOT be presented as base Python 1.0 grammar. They use the namespaced envelope
  metadata `x_aiset_flutter` with its own `extension_version` and per-node entries keyed by data JSON
  Pointer, e.g. `"/audio/strength": {"primary": {"all": [{"path": "/audio/denoise", "op": "eq",
  "value": true}]}}`. The Flutter compiler recognizes the extension; a legacy Python validator may
  report unknown metadata, which does not mean the descriptor is fully compatible. Export to legacy mode removes the
  extension metadata from a separate export copy, never from the original.
Reference: acceptance IDs DSC-01, SIM-01, HUI-11.

## 6. Resolver, variables and provenance
Affected: new baseline section "Resolver".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- Compatible tokens: `${VAR}` and `${VAR:-default}`. Resolution is single-pass: a variable value is data,
  not a re-executable template.
- Precedence: explicit host overrides → injected environment → injected dotenv mapping → inline fallback →
  descriptor or config default where applicable. `${VAR}` with an unset or empty variable yields an empty
  string; `:-` selects the inline default when the variable is unset or empty. Absent-versus-default
  behavior is verified by separate fixtures and is not conflated with the empty string.
- Resolution is allowed only when `env.allowed`. Conversion supports string, int, number and bool with
  exact format and range checks. The library MUST NOT read the global environment or a `.env` file without
  a host adapter. In Web, the environment mapping is a host-supplied source, not access to the user
  machine's environment. Server secrets MUST NOT be sent to the client to compute the effective view
  locally.
- Every effective value MUST carry provenance — source, default, override or environment, plus owning
  layer — without disclosing secret values.
Reference: acceptance IDs RES-01, SEC-01.

## 7. Merge, mounts and component contribution
Affected: new baseline section "Merge and contribution".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- `merge(base, update, prefer: base)` MUST be a pure function. Objects merge recursively; on scalar, list,
  null or type conflict `base` wins by default, and `prefer: update` selects update explicitly. Arrays are
  not merged automatically by id. Merge does not delete keys, does not preserve comments and does not
  replace the editing API. Merge MUST NOT mutate its inputs.
- For `aiui` the main config is `base` and a plugin's defaults are `update`, so user settings win — deferred
  with the rest of the aiui surface by amendment 35. The host defines the layer list and order; the library
  MUST NOT impose a universal policy.
- Descriptor fragments mount at descriptor coordinates (`/root/children/...`) with a free-space check. Data
  mounts are separate. Ordinary fragment composition MUST NOT overwrite an existing descriptor node.
- Intentional overrides are issued only through a separate trusted contribution API carrying target, owner,
  priority and explicit permission. A conflict without a resolving rule is forbidden. Changing the resulting
  descriptor changes `descriptor_revision` and invalidates stale drafts.
- Plugin effective defaults MUST NOT be silently materialized into source. Editing an inherited value
  creates an override in the main document; resetting an override returns to inheritance. Which operation
  applies depends on descriptor capability and node origin.
Reference: acceptance IDs MRG-01, EXT-01.

## 8. Revisions, concurrency and the write pipeline
Affected: new baseline sections "Revision model", "Write pipeline and operations", "Save and application".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- Separate `source_revision`, `descriptor_revision` and `active_revision` are mandatory. Internal
  layer, resolver and registry revisions are captured when a candidate is prepared and verified before
  commit.
- Writing and revision-bound validation require the expected source and descriptor revisions. Absent →
  `REVISION_REQUIRED`; mismatch → `REVISION_CONFLICT`. Automatically applying a stale draft over a fresh
  document is forbidden. The UI keeps the draft and offers reread, diff, rebase or cancel; after a rebase a
  new validation and a new confirmation of the changed candidate are required.
- In local mode these rules apply between two controllers or windows as well. An adapter claiming
  concurrent-write support MUST provide CAS or coordination across tabs, not only an in-memory mutex of
  one isolate. A restricted localStorage mode MUST explicitly declare the absence of that guarantee.
- Pipeline order is mandatory: authorize → check revisions → parse operations → build candidate → resolve →
  validate descriptor and semantic checks → verify preservation → pre-commit probe → recheck snapshot →
  commit → application handling → audit and subscriptions → result.
- Operation envelopes stay Python-compatible: `set` (`value_text`), `add` (`value_text`, `/…/-` append),
  `remove`, `move` (`from`, `path`), `rename` (`path`, `to`), `drop` (`path`). Operations apply
  sequentially to one candidate so later ones see earlier ones, including create-container-then-fill inside
  a single batch. The whole batch is saved by one write or not at all; this is not a distributed transaction
  and not a rollback of external actions.
- Permissions and restrictions for `required`, `const`, `read_only`, `secret` and fixed children carry over.
  `drop` is valid for an undeclared key and does not replace ordinary `remove`. `drop` admissibility inside a
  union considers all alternatives, and all affected descendants are checked.
- `apply` values are `live`, `reload`, `restart`; undeclared means `restart`; the strictest policy among
  changed paths determines the result. Result states: `applied`, `reload_required`, `restart_required`,
  `apply_failed`.
- A successful save is not a successful runtime apply. If a post-commit callback failed, the result MUST be
  `stored = true` with `apply_failed`; the library MUST NOT report as though the file were unsaved.
  `CommitReport` contains `committed`, `uncertain`, `revision`, `detail`; on uncertainty the state is
  re-read rather than the write blindly repeated.
- The host calls a public confirmation of a successful reload or restart, after which the active snapshot is
  updated. A no-op domain application is allowed only if the host genuinely uses the new live snapshots. The
  UI MUST show pending application separately from validation errors.
Reference: acceptance IDs OPS-01, REV-01, APP-01, STO-01.

## 9. Callbacks, subscriptions and capabilities
Affected: new baseline section "Callbacks and capabilities".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- Public pre-commit probes MAY reject a candidate before the write; post-commit observers MUST NOT cancel a
  committed result. All callbacks are bounded by timeout and cancellation semantics with a documented order.
  A long asynchronous probe MUST NOT hold a global storage lock; the snapshot is rechecked before writing.
- Subscriptions are filtered by document and path and return a cancellation handle. Events include changed
  paths, previous and current revision, application state and active revision. Permission filtering MUST NOT
  leak a secret subtree through events.
- Descriptor hooks and semantic validators execute only through the trusted registry. An unknown or
  unsupported mandatory binding MUST yield `UNSUPPORTED_CAPABILITY`, never silent success. Grammar
  acceptance and execution capability are different things.
Reference: acceptance IDs SEC-01, HUI-11.

## 10. Three persistent storage modes
Affected: new baseline section "Storage modes".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- Each document selects exactly one mode and one authoritative source: `remote_api` (document on a remote
  backend, read and saved by the backend through an API); `host_api` (document in a host-defined place,
  read and saved by the host through a provided API); `local` (file or persistent device/browser storage,
  read and saved by a built-in adapter). The same editor and controller MUST work with all modes. Cache,
  effective snapshot and draft are not additional authoritative copies. The memory store remains for
  tests and temporary documents and is not a fourth persistent user mode.
- The persisted form is the original JSON5 text, not only a map of computed values; comments, placeholders
  and source formatting follow the preservation contract. Runtime state, resolved secrets and provenance are
  not written into user values automatically.
- `remote_api` MUST support two profiles. `aiset_service`: the backend provides aiset operations, tree,
  validation, revisions and apply. `document_api`: the backend provides source JSON5, a revision and a
  conditional save of the full candidate, while the library builds and validates the candidate locally.
  Local validation is not protection of the backend against an arbitrary client: server-side validation and
  access policy are a mandatory integration contract. If a backend performs no descriptor validation, that
  MUST be a declared capability and MUST NOT be presented as full `aiset_service` compatibility. The backend owns
  access, authoritative revisions, persistence and concurrent writes; backups, history and LKG
  exist only when the API declares support.
- In `remote_api` an offline draft is allowed with explicit indication. A network failure MUST NOT be
  treated as an absent document or as a successful save. After an indeterminate outcome the state is checked
  instead of a blind retry. Automatic fallback to local storage creating a second authoritative copy is
  forbidden.
- `host_api` minimal contract (names may change at API review, semantics are mandatory):
  `abstract interface class AisetHostStorage { Future<AisetStoredDocument> read();
  Future<AisetCommitResult> compareAndSwap({required String expectedRevision, required String sourceText});
  AisetStorageCapabilities get capabilities; }`. `AisetStoredDocument` carries sourceText, revision and
  permitted metadata. `AisetCommitResult` distinguishes committed, revision conflict, rejected and
  uncertain outcomes. Secret physical paths are not added to UI or AI metadata automatically. The host
  either provides atomic conditional write or honestly declares its absence; `read` plus unconditional write
  is not a safe concurrent write. Conditional write is mandatory for durable production storage; a legacy
  single-writer adapter is allowed only as an explicitly limited mode that must not claim
  concurrency protection. Backups, notifications and history are optional capability interfaces. The host
  MUST NOT reimplement the parser, descriptor validation, staged editor or AI tool loop.
- `local` backends: `native_file` (PC file, or a file in a directory accessible to a mobile app),
  `app_storage` (persistent private app storage on mobile or desktop), `web_local_storage` (source JSON5
  text in browser localStorage), `web_indexed_db` (additional browser persistent storage with
  transactions). localStorage support is mandatory as one Web option and IndexedDB does not cancel it. The
  backend is chosen explicitly, with no hidden substitution.
- For `native_file` the path and access policy are set at bootstrap; shipped assets are a seed only and never
  a mutable user file. For `app_storage` a namespace and document ID are set and no user-visible path is
  required. For Web, storage keys include the app namespace and document ID, JSON5 is stored as a string
  without decode-encode reformatting, and the adapter handles storage unavailability, quota and write
  errors. The UI MUST NOT show "saved" before the write is confirmed.
- localStorage MUST NOT claim multi-key transactionality. Where source, revision and backup metadata need an
  atomic update they are stored as one consistent envelope, or another explicitly chosen backend is used.
  Cross-tab writes are coordinated by a supported mechanism; a storage notification is not a lock. Full
  concurrent-write mode is allowed only with proven CAS or coordination capability; otherwise the documented
  single-writer/restricted mode applies, or IndexedDB is suggested. Silently promising no lost updates is
  forbidden.
- The physical location and durability boundary are reflected in the UI (browser storage, private app
  storage, or file). Clearing user storage MUST NOT be described as impossible data loss; export is the
  backup path.
Reference: acceptance IDs STO-01, STO-02, STO-03, STO-04.

## 11. Bootstrap, initial load, backup and restore
Affected: new baseline sections "Bootstrap", "Initial load", "Capabilities", "Backup and restore".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- Because the app must know which adapter to use before it can load the main `AppConfig`, bootstrap
  parameters are passed by the host when the runtime is created: storage mode, document ID, namespace, path
  or endpoint, credential references, and required descriptor references. Bootstrap is not a second
  independent store of functional settings.
- The host decides the bootstrap source — compile-time parameters, launch options, its own
  connection-choice storage, or onboarding — and the concrete method is documented. An endpoint needed
  before the first read MUST NOT depend solely on the contents of a file that has not been loaded yet. For
  `host_api` an adapter object is passed, not JSON containing executable code.
- Switching the source through the UI: verify the new connection → decide open-existing versus copy-current
  policy → show consequences → confirm → atomically switch the session binding. On error the previous source
  stays active. An unsaved draft requires an explicit user decision.
- Initial load sequence: select adapter from bootstrap → read source and revision → parse, resolve and
  validate against the chosen descriptor → build source and effective snapshots → hand results to the host
  and the editor.
- An absent document, an invalid source, a forbidden access and a network or storage failure are four
  different results. Seed or defaults are written only on a confirmed absence with an allowed initial-create
  policy; a read error never authorizes overwriting a document with defaults. Initial create uses
  create-if-absent or an equivalent so two launches do not overwrite each other. Descriptor defaults need
  not materialize into source before an explicit operation.
- Each adapter MUST declare `persistent`, `conditional_write`, `cross_context_concurrency`,
  `source_preservation`, `backup`, `history`, `load_lkg`, `change_notifications`, export access, and its
  validation authority level. A missing capability MUST NOT be imitated by an empty successful result; the UI
  explains the limitation. A remote or host backend without backup gets no LKG promise from a local
  non-authoritative cache. The memory store is explicitly marked ephemeral. Document size and storage quota
  are not conflated: a valid document within the library limit may not fit the chosen storage, which returns
  a storage error without damaging the previous version.
- Backup: depth is configurable for supporting adapters, with default 5 for native parity. A backup is
  created no more than once per editing session, where load or reload — not a widget rebuild — defines the
  boundary. `load` and `loadLkg` are separate calls. A fallback is reported to the host and MUST NOT
  overwrite an invalid current source; with no valid backup the result is `NO_VALID_BACKUP`. The host may
  request LKG after a failed domain startup probe. Destructive rollback and explicit history restore are
  different commands; restore is revision-checked and audit-logged. The browser equivalent preserves the
  chain and LKG meaning without promising `.back` files on disk. For `remote_api` and
  `host_api` physical backup is performed by the storage owner through its declared API.
Reference: acceptance IDs STO-05, STO-06, LKG-01.

## 12. Save As, Export and Import
Affected: new baseline section "Export and import".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- Action semantics: Apply and Save — apply the draft and save to the current authoritative source; Save As /
  Export JSON5 — write an external copy of the document; Import JSON5 — load an external file as the
  candidate for the current document; Open as document — optionally open a separate document without
  replacing the current one; Use as working file — optionally switch the native source to the selected file.
- Save As means export by default, not an adapter switch. Export and import are mandatory in all three
  storage modes. In Web export is a user-initiated download; native and mobile use the platform save or share
  mechanism. Cancelling the file picker is not an error and does not change state.
- Export emits the source document with comments, placeholders and formatting where the security policy
  allows. Resolved environment values, runtime state and secret-store contents are excluded. With a pending
  draft the user chooses the saved version or the validated candidate; exporting a candidate does not commit
  it. An invalid candidate is exported only by a separate "Export draft" command with a warning,
  never as an ordinary valid config.
- Direct secrets written as literal source values require a secret export policy and a separate permission.
  The standard safe export excludes them or replaces them per a confirmed scheme; if that breaks the
  descriptor, the result is explicitly marked a redacted template and requires filling on import. It is
  forbidden to promise both byte-identical source and removal of literal secrets. Credential references are
  exported as references. Secrets are never sent to a model to prepare an export. For a remote source,
  permissions are checked by the backend and export does not bypass a source or secret read ban.
- A successful export changes neither the revision, nor active settings, nor the authoritative source. An
  error or cancellation does not mark the draft saved.
- Import sequence: file selection → size and encoding check → JSON5 parse → version check → descriptor,
  resolver and semantic validation → candidate diff and review → confirmation → revision-checked commit
  through the current adapter → application policy live, reload or restart.
- Import replaces the whole document by default. Merge is a separate action with an explicitly chosen
  base/update policy and a preview; replacement and merge MUST NOT be mixed without indication. Candidate
  source is not reformatted unnecessarily; when the whole source changes the user explicitly sees that the
  old file's comments may be replaced by the imported file's comments — a confirmed whole-document
  replacement does not violate the preservation contract for unrelated edits.
- Checked on import: supported version, allowed keys, types, limits, required values, references, and
  `read_only`, `const`, `secret` boundaries. Import grants no additional permissions. In remote mode the
  mandatory available server-side checks run, not only client-side ones. If the environment or server-only
  validators are unavailable, incomplete validation is displayed rather than unconditional validity; an
  ordinary commit requires the necessary authoritative checks to complete. Migrations are used
  only through the trusted migration pipeline.
- On error the current source, revision and active settings are unchanged, and the candidate can be fixed
  without losing the working configuration. If the revision goes stale after review, a reread and re-review
  are required, not an overwrite. Import never bypasses the remote or host API and never saves only to a
  local cache in secret. After commit, post-commit or application failure is reported honestly: `stored =
  true` may combine with `apply_failed`, and that is not called a cancelled import.
- Automatic AI repair is not started. Fixing through AI is a separate command with the usual proposal,
  validation and Apply.
Reference: acceptance IDs IO-01, IO-02, IO-03, IO-04, IO-05, IO-06.

## 13. Doctor and migrations
Affected: new baseline section "Doctor and migrations".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- Doctor is read-only by default. Repair classes are `clamp`, `coerce` and `drop_unknown`; `coerce` and
  `drop_unknown` are enabled explicitly and no class is applied without a user or host command.
- A fully repaired document is saved only if the result is valid. Parse errors, ambiguous unions, a missing
  `required` without default and other report-only cases are not fixed with invented values. `secret`,
  `read_only` and `const` ancestors are protected.
- Schema migrations are a separate trusted API: version gate → backup → dry run and diff → validation →
  atomic commit. A descriptor version change and a config version change are different events. A migration is
  not a hidden AI repair.
Reference: acceptance IDs DOC-01.

## 14. Public Dart API
Affected: new baseline section "Public API".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- Mandatory high-level contract (names may be refined at API review; semantics are mandatory): construct
  `AisetService()`, `register(AisetDocumentRegistration(id, storage, descriptorSource, resolver))`,
  `openSession(documentId, principal)`, `session.load()`, then `AisetEditorController(session)`.
  Asynchronous storage MUST NOT block the UI. Resource ownership and `close`/`dispose` MUST be explicitly
  defined.
- Mandatory operations: `register`, `listDocuments`, `load`, `reread`, `loadLkg`, `get`, `getTree`,
  `validateValue`, `validateDocument`, `validateOperations`, `applyOperations`, `doctor`, `rollback`,
  `subscribe`, and descriptor diagnostics. `merge` and `resolve` MUST be usable without UI.
- The Config wrapper MUST provide immutable data, origin, revision, descriptorRevision, update and merge,
  mounts, reload, save through the service, and subscribe. The wrapper MUST NOT perform a raw bypass write.
- Typed errors MUST keep Python-compatible codes; the transport envelope and Dart exceptions share one
  source of codes. Optional transport adapters MUST NOT change validation semantics.
Reference: `ARCHITECTURE.md` §4; acceptance IDs LIB-01, LIB-03.

## 15. Generated Flutter editor — mandatory feature set
Affected: new baseline section "Generated editor".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- Main widgets: `AisetEditor`, `AisetSettingsPage`, `AisetSettingsApp`. A separate host screen or router is
  not required. The controller is separated from the widgets.
- Mandatory features: expandable objects and arrays with type-aware scalar controls; staged batch with
  Apply, Validate, Revert and Reload; add, remove, move and rename according to snapshot capabilities;
  absent-keys view and values-as-text view; raw source editor; explicit-null switch and
  restore-declared-default; placeholder editor with variable and inline fallback edited separately; union
  shape chooser with object and array alternatives using full child controls; read-only, secret, origin,
  apply, default and description indicators; errors with path and reveal/focus; search over keys, paths,
  scalars and descriptions without secret values; programmatic `search`, `focusSearch`, `revealPath` and a
  context breadcrumb; preservation of focus, scroll and expanded state across updates; a warning when
  leaving with an unsaved draft.
- A template value and a resolved value MUST NOT share one editable field. An unavailable helper MUST NOT
  break ordinary editing where that is safe and permitted.
- The controller MUST expose `stageOperations`, `getPendingOperations`, `validatePending`, `applyPending`,
  `revert`, `reload`, `expandAll`, `collapseAll`, `showAbsent`, `valuesAsText`, `search`, `revealPath`. The
  editor model MUST NOT depend on a specific host state-management framework.
Reference: acceptance IDs UI-01, UI-02.

## 16. Ready default UI and headless editor architecture
Affected: new baseline sections "Default UI", "Headless editor".
Approval: as amendment 1; reinforced by specification draft v1.2.
State: confirmed requirement (not yet implemented)
Change:
- The library MUST provide a fully working standard editor and standard scenarios for display, input,
  checking, review and saving. The host MAY control appearance, layout, navigation and interaction
  scenarios but MUST NOT be required to. No override, custom renderer, custom helper, wizard or own design
  system is required for a standard connection: the absence of user builders means library components are
  used, not an error or an empty screen.
- Minimal embedded integration after creating a session and controller is `AisetEditor(controller:
  controller)`; a ready page is `AisetSettingsPage(controller: controller)`. Embedded widgets MUST NOT create
  a mandatory `MaterialApp`, router or global theme. A separate opt-in `AisetSettingsApp` provides a
  ready standalone shell for examples and simple apps. Settings, descriptor and the chosen storage are
  mandatory by their own contracts; needing a host storage adapter in `host_api` does not mean needing
  host UI.
- Layering: service, core and storage → `AisetEditorController` with typed bindings and draft → default UI,
  partial overrides, or fully custom host UI. The controller owns editor semantics (snapshots, staged
  operations, dirty state, validation, conflicts, permissions, proposal merging, commands); presentation
  owns rendering and user gestures.
- The standard UI MUST be built on the same public controller and binding contracts available to the host.
  If the standard editor needs a new contract, it is added to the public SDK rather than kept as a
  privileged private path. The host MUST NOT have to reproduce the parser, resolver, tree construction,
  null/absent/default/template semantics, revisions, storage pipeline, AI tool loop or conflict detection in
  order to change appearance. A fully custom UI is allowed but not required; it uses public commands, and a
  visible button never replaces a service check.
- When an AI assistant is connected, the ready UI MUST present it without host-written glue
  (amendment 31); when none is connected, the editor MUST be complete and show no assistant
  affordance.
- Four independent, combinable customization levels: **Theme** (colors, typography, spacing, density, radii,
  motion — the library keeps all components and behavior); **Components and slots** (individual controls,
  rows, headers, toolbar, feedback — the controller and remaining defaults stay); **Subforms and
  helpers** (editor for one node, a special form or wizard — the library keeps bindings, local draft,
  validation, staged acceptance); **Full presentation** (whole screen and scenario — the library keeps the
  headless controller and shared service contract). A new library version MUST provide defaults for new
  optional UI slots without editing every host.
- `AisetTheme` defines semantic design tokens; `AisetUiDelegate` and `AisetUiOverrides` define component
  construction. Changing theme values MUST NOT require custom builders, and substituting a builder MUST NOT
  require replacing the whole theme. The standard Flutter skin MAY integrate with `ThemeData` and
  `ThemeExtension`, but the public presentation contract MUST NOT require specific Material controls. The
  `theme` and `ui` parameters are optional; a passed override acts in the local editor area and does not
  change other instances through a hidden global registry — a shared registry may be passed to several
  instances explicitly.
Reference: acceptance IDs HUI-01, HUI-02, HUI-03, HUI-04.

## 17. Typed bindings, slots, decorators and renderer selection
Affected: new baseline sections "Presentation bindings", "Renderer selection".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- A builder receives a typed binding, not a name and value pair. The common part carries
  `stableNodeIdentity`, `path`, `label`, `description`, `sourceValue`, `effectiveValue`, `draftValue`,
  `presence`, `provenance`, `isDirty`, `isReadOnly`, `isSecret`, `issues`, `validationState`,
  `capabilities`. Presentation bindings are for UI and never contain values forbidden to the principal.
  Nullable, absent and permission-denied are distinct states, not one shared null reference.
- Typed variants: text, number, bool, enum, template, union, object, array. Commands expose only actions
  available to the variant — `editText`, `setValue`, `setNull`, `restoreDefault`, `resetOverride`, structural
  commands — and they change the draft without writing storage.
- Incomplete local input, for example a lone minus sign in a number field, is kept as an editing buffer and
  need not become a valid semantic value immediately. A snapshot refresh MUST NOT destroy input.
  Asynchronous validation results are bound to an edit revision; a stale result MUST NOT
  overwrite a newer one.
- Stable identity and binding lifecycle MUST be defined for reorder, rename and reload; a plain array index
  is not a permanent identity. The host MUST be able to use standard stateful bound fields instead of
  managing its own text controllers.
- Minimum slot groups: shell and layout, navigation, toolbar and actions; node header, section container,
  object row, array item row; scalar, enum, null and template and union editors; description, origin,
  default, apply, read-only and secret indicators; validation issues, loading, error and conflict panels;
  structural actions, Apply, Revert, import and export UI; search, breadcrumbs and reveal; AI activity,
  proposal, diff and approval presentation.
- A decorator MUST be able to wrap `defaultContent` without copying the internal implementation. Renderer
  selection MUST be deterministic in this order: explicit per-instance or per-node override; explicit
  registered editor ID from trusted presentation metadata; registered editor semantic role or type; standard
  editor. A generic override MUST NOT accidentally intercept an explicit editor ID. A conflict of equal
  priorities, or a target without a resolving rule, is a diagnostic error, not a
  random winner by import order.
- Fallback is computed by the library. A wrapper MUST NOT call its own override again and MUST NOT create
  recursion. An unknown optional editor ID shows diagnostics and the default editor where ordinary editing
  is permitted. An unknown required editor or helper needed to uphold a mandatory constraint blocks
  the action with `UNSUPPORTED_CAPABILITY`; this is not hidden by default UI. The presence of custom UI
  does not change permissions, and the service re-validates every command.
Reference: acceptance IDs HUI-02, HUI-04, HUI-09, HUI-11.

## 18. Custom subforms, wizards and isolated drafts
Affected: new baseline sections "Subforms", "Wizards", "Host actions".
Approval: as amendment 1; introduced by specification draft v1.2.
State: confirmed requirement (not yet implemented)
Change:
- A subform is presentation plus a local editing session for a specific target; a helper is a registered
  create or edit scenario. The registry belongs to trusted Dart host or extension code. A descriptor
  contains only references and parameters, never executable code. The base helper grammar is preserved
  (`tag`, `actions`, `presentation`); new fields such as a required presentation capability or editor IDs are
  expressed through the versioned Flutter extension of amendment 5, not added to legacy grammar.
- Default helpers and a generic generated subform are provided by the library. The host registers a special
  wizard only when needed. Modal and wizard presentation adapts to width — dialog, sheet or separate screen —
  through a default presenter. The host MAY override the presenter and navigation but
  MUST NOT be obliged to write them. Registering a custom helper does not mean the standard editor is
  hidden: availability of the ordinary path is decided by capabilities and descriptor, not by a visual
  preference for the helper.
- Draft nesting is stored source → main editor draft → isolated subform draft, with a single common Apply.
- The subform session MUST provide target and descriptor, an initial draft snapshot, a local draft,
  `field(relativePointer)`, `validate`, `buildPatch`, `accept` and `cancel`, using the same editor semantics
  as the main editor. Mandatory rules: opening changes neither the main draft nor the source; a subform
  starts from the current main draft, not only the last saved document; all changes are local until
  accept; cancel and closing without confirmation do not change the main draft; accept validates the
  patch and adds it to the main draft as one logical group while storage is still unchanged; the
  common Apply saves the whole candidate through the current adapter; dispose cancels pending
  validation and actions and removes subscriptions.
- A result accepted into the parent draft MUST NOT be called saved. The standard button label is "Done" or
  "Add to changes", never an ambiguous "Save".
- Creating a new array item uses a temporary identity. An empty object MUST NOT be added to the main draft
  merely to open a wizard. After accept the library forms the correct add and related operation group. A
  whole-object set is allowed only with explicit consequences for comment preservation and protected
  descendants. Nested subforms use the same semantics — accept into the immediate parent draft, never
  directly into storage — and nested sessions are limited by a configurable depth.
- A session records `sourceRevision`, `descriptorRevision` and `parentDraftRevision`. While a wizard is open
  the parent draft may change manually or through AI. Accept returns a minimal patch and checks overlap by
  affected paths and structural effects. Non-overlapping changes merge after re-validation. An overlap
  requires review or conflict resolution; silent whole-object replacement is forbidden. Parent
  reorder, rename or delete requires resolving the target by stable identity or an explicit conflict. A
  deleted target, a changed union shape or a changed descriptor revision must not allow writing a
  patch by a stale index.
- A local subform may remain provisionally invalid between steps. Before accept, its patch is validated in
  the current whole-document candidate, including cross-field and semantic checks. Required remote
  checks run through the available dry-run contract; where no authoritative check is available this
  is shown explicitly. Draft acceptance does not guarantee a future commit: the common Apply
  re-checks the whole document and current revisions. It is forbidden to claim "valid"
  after checking only widgets or ignoring protected descendants. Where no independent subtree validation
  exists, a whole-document dry run is used.
- The library MUST provide `AisetBoundField` and `AisetGeneratedSubform` so a custom form can reuse standard
  controls, theme and validation feedback. Paths are relative to the session target and use JSON Pointer
  semantics; arbitrary escape from scope is forbidden, and editing several permitted areas requires explicit
  session scopes. Generated sections and custom fields share one local draft. Control names do not
  become a new addressing mechanism for settings. Wizard steps MAY use standard Next, Back, Cancel,
  Done, progress, issues summary and adaptive presentation without a host implementation.
- Extra host actions inside a wizard — test connection, list models, discover device — run through
  registered action services, separate from draft mutation. They have capabilities, bounded input and
  output, timeout and cancellation, and stale-result protection. `CredentialResolver` gives a secret only to
  the permitted transport or action, not necessarily to a widget, diff or AI prompt. Checking an endpoint does
  not save the document and does not prove full domain validity. Actions with external side effects
  require corresponding confirmation. Cancelling the form does not promise to roll back an already
  created external resource; that result is tracked separately. The default UI MUST be able to show pending,
  error and success and allow retry, so the host is not obliged to write its own action feedback.
- Full visual control is a capability of a trusted host, not an obligation and not a right to bypass the
  core. Read-only, secret and permission rules are enforced independently of presentation. UI
  registries and callbacks are passed at bootstrap or registration and are never serialized into
  `AppConfig`; the single config stores theme values, chosen IDs and declarative
  options. JSON from a server MUST NOT install renderers or execute Dart. The default UI
  covers accessibility, localization, focus and error display, and custom widgets must satisfy the same
  presentation contract. A theme or renderer update MUST NOT recreate service or storage
  connections and MUST NOT reset the draft. Controller ownership is explicit: a host-provided controller is
  not disposed by the editor automatically, while an internal controller of the convenience shell is
  released by it.
Reference: acceptance IDs HUI-05, HUI-06, HUI-07, HUI-08, HUI-09, HUI-10, HUI-12.

## 19. Simple and advanced modes, primary flags
Affected: new baseline section "Simple and advanced".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- Advanced shows every permitted setting. Simple shows entries with `primary: true` or a true
  primary condition. Ancestors remain as navigation containers. A setting that is not shown is neither
  deleted nor changed.
- Conditions are declarative: `any`, `all`, `not`, and comparisons by JSON Pointer against typed JSON
  values. The string `"true"` is not equal to boolean `true`. An absent path differs from null.
  Arbitrary expression evaluation is forbidden.
- Conditions are evaluated over the validated draft projection; when a draft field is invalid the last valid
  projection is retained and the error is displayed. Cyclic or undefined dependencies are diagnosed.
  `primary` is not an authorization mechanism.
Reference: acceptance IDs SIM-01.

## 20. UI, themes and localization
Affected: new baseline section "UI, themes and localization".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- The Flutter UI MUST be adaptive for compact, medium and expanded widths and usable with mouse, keyboard and
  touch. Theme tokens cover spacing scale, semantic palette, typography, density, radii, borders, motion
  and layout breakpoints. The theme integrates with the host and MUST NOT overwrite it globally.
- ARB localization MUST ship Russian, English and Simplified Chinese. First launch uses the system locale,
  with a manual override in settings, a fallback locale and runtime switching. The AI
  answer language is chosen separately from the UI language.
- Descriptor text MAY carry locale keys through Flutter extension metadata, with the key-to-string resolver
  supplied by the host or extension; the original description remains the fallback. JSON paths, provider IDs
  and source text are not translated.
- The settings UI of the library itself MAY be placed in the `ui.settingsEditor` branch of the host
  main object. The library MUST NOT require a second hidden persistent config.
Reference: acceptance IDs LOC-01, UI-01.

## 21. AI modules
Affected: new baseline sections "AI modules", "AI tools and approvals", "Web security".
Approval: as amendment 1; deliberate boundary change from Python, where the provider loop is
host-owned in `demo2/agent.py`.
State: confirmed requirement (not yet implemented)
Change:
- AI functionality is an optional library layer, not per-example code, and its connection is a library
  feature of the Flutter layer: the host configures a provider, the library wires the assistant into the
  ready UI (amendment 31). Contracts: `AisetAiProvider`
  (completion and stream, tool calls, cancellation, capabilities); `AisetAiAssistant` (bounded
  sessions, instruction and skill context, tool loop); `AisetProposal` (operations plus
  source and descriptor revisions plus author and note); `AisetAiPanel` (reusable chat, activity,
  proposal UI); `CredentialResolver` (the secret is received by the transport adapter, not by the prompt
  builder).
- The first real integration is OpenAI-compatible Chat Completions. Other providers MUST connect without
  editor changes. A remote gateway is supported separately; the presence of a client endpoint does not make a
  key safe in Web.
- Provider failure, timeouts and malformed tool calls are explicit errors. In the standard mode tool
  arguments are accepted as strict JSON; tolerant parsing MAY exist only as a limited mode that executes no
  code.
- The minimum tool set matches the Python demo agent: `settings_get`, `settings_get_tree`,
  `settings_validate_operations`, `settings_stage_operations`. The agent principal has read source, read
  effective and validate by default — no write and no secret read or edit. Tool content
  is bounded by depth and length, and truncation is reported explicitly.
- Flow: read → propose → validate → stage → the user sees a diff → Apply through the service. AI MUST NOT
  write storage directly. Staging is not confirmation. Approval is bound to the exact operations and the
  revision pair; after the candidate changes, a new confirmation is required.
- AI proposals MUST NOT overwrite an existing manual draft: a conflict is shown and resolved
  explicitly. Cancellation applies nothing. Prompt injection from comments or descriptions MUST NOT extend
  permissions. Rounds, history, tokens, cost and time limits and the tool allowlist are configurable. Secrets
  MUST NOT reach the model through values, errors, provenance, diff or activity log.
- Production browser UI MUST NOT embed a server master API key. A shared provider account uses a gateway with
  authentication. BYOK is allowed only as an explicit mode that explains the key is
  available to the client runtime. Secret masking in the UI does not turn a client key into a server
  secret.
Reference: acceptance IDs AI-01, AI-02, AI-03, AI-04, SEC-01.

## 22. Remote HTTP and MCP
Affected: new baseline section "Remote and MCP".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- `aiset_remote` MUST connect the Flutter UI to Python `aiset` through its existing endpoints and envelopes.
  Before full compatibility is promised, an API version and capability matrix plus a pinned corpus are fixed.
  A mandatory handshake that is absent from the Python implementation MUST NOT be invented: where it is
  absent, explicit configuration and compatibility tests are used.
- Local and remote MUST use one `EditorSession` contract. In remote mode the backend is authoritative and
  client-side validation MUST NOT substitute for server validation; an incomplete local check is marked
  advisory. The generic `document_api` uses the contract of amendment 10 and is not presented as full
  `aiset_service`. The host API bridge does not depend on the host having HTTP.
- An HTTP server written in Dart is an optional native-only adapter, not a Web UI dependency. The MCP facade
  is a new optional capability using the same service, permissions, revisions and errors; it MUST NOT
  be called an already finished Python MCP adapter (upstream states the MCP adapter and the
  lifecycle-hook dispatcher are not implemented). Because upstream has no implementation, the MCP facade is
  **deferred by amendment 33**; nothing in this amendment authorizes building it in the current scope.
- Auth, TLS, CORS and CSRF belong to the external host or transport integration and are documented
  explicitly. A demo principal MUST NOT be selected automatically in production.
Reference: acceptance IDs REM-01, STO-02.

## 23. Extensions and aiui plugin integration
(aiui-specific placement deferred by amendment 35; the registry requirements below are unaffected.)
Affected: new baseline section "Extensions".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- The public registry MUST support descriptor and data contributions, custom editors and helpers, validators,
  resolvers, storage adapters and AI modules. An extension is registered by trusted Dart code.
- An aiui plugin's settings are placed in `plugins.<id>.settings` of the single `AppConfig`.
  Connecting an extension MUST NOT require forking `aiset_flutter`. A plugin does not gain secret access
  merely because it provides UI.
- Disable or unregister completes subscriptions and invalidates the corresponding descriptor snapshot.
  Data of a removed extension is not deleted automatically; the unknown or orphan branch policy is chosen
  explicitly by the host.
- Namespaced IDs, version ranges, dependencies and deterministic registration are mandatory. Shared process
  memory is not considered a sandbox.
Reference: acceptance IDs EXT-01.

## 24. Compatibility corpus and parity checks
Affected: new baseline section "Compatibility".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- A versioned corpus is generated from the behavioral baseline by **executing it** — importing the
  library and running its test suite — and not by transcribing Python prose documents;
  where prose and code disagree, code wins (amendment 32). Runtime Python implementation files MUST NOT
  be copied into the Dart library. Each generated fixture set records the baseline commit SHA it was
  produced from, which MAY be newer than the snapshot named in this file's header.
- Checked areas: parser acceptance, rejection and values; descriptor issues, types, defaults and unknown
  metadata; resolver precedence and conversion; JSON Pointer and mount edge cases; operation to resulting
  source text; authorization and error codes; source and effective trees and atomic batches; merge
  base and update behavior and input immutability; LKG, backup and application behavior; doctor reports and
  repairs.
- Known Python defects are not carried over for bug-for-bug equivalence. Any divergence is registered as an
  intentional correction with a fixture and a migration note. An older contradicting specification is not
  used to justify an unexpected change.
- The corpus pins **observable behavior only**. Matching a fixture never justifies reproducing a
  Python internal structure, name or mechanism; see amendment 30.
- The corpus covers the tier 1 and tier 2 areas of amendment 32. Presentation, interaction, API naming and
  other tier 3 matters are not corpus-pinned and MUST NOT be added to it to chase Python.
Reference: `ROADMAP.md` §2 stage 1; acceptance IDs DSC-01, RES-01.

## 24a. Test applications as part of the product
Affected: new baseline section "Examples".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- All examples MUST run standalone on supported platforms, use the real packages and separate
  runtime storage. Tracked fixtures MUST NOT be modified by running an example. A seed is copied only when
  user state is absent.
- `basic_editor`: minimal connection and persist across restart; host content limited to main,
  descriptor and config, storage selection. `showcase`: all types, source preservation, operations, doctor,
  conflict and LKG; fixtures and declarative scenarios, with orchestration in a reusable harness.
  `ai_assistant`: a real model, read, validate and stage, review and apply; provider config, credential
  references, instructions, module registration. `remote_editor`: a real Python aiset backend; endpoint and
  auth config and bootstrap. `extension_host`: fragments, primary, helper and custom widget and plugin
  settings; the example extension is a separate package.
- An AI example MUST NOT contain a Dart copy of the Python demo agent inside the example. The tool
  loop, protocol handling, history, staging and AI panel live in the library's optional modules, and the
  assistant is attached to the editor by the library connection path of amendment 31, not by example glue. A normal
  consumer example contains only settings, descriptors, resources and glue over the public API. The
  extension test demonstrates a user implementation of an extension but does not copy the core.
  Special fault injectors live in test support, not in production example logic.
- Examples MUST demonstrate real application of live, reload and restart and side-panel state, not only file
  saving. `showcase` uses the library test harness with a declarative scenario registry, and the full scenario
  catalog lists requirement IDs and verification methods. `showcase` allows running a scenario and seeing
  source, effective, active and draft plus a report; it is not limited to static screenshots.
- `showcase` MUST include storage mode selection and display, a host-backed scenario, a localStorage
  scenario, Save As, invalid import, valid import with preview, stale import, and quota and error injection.
  The remote example checks `aiset_service` and the generic `document_api` separately.
- Without credentials the AI example starts with the editor and an explicit "AI not configured" state. An
  offline deterministic provider is used in CI and is not presented as live AI. A
  separate opt-in suite checks the real endpoint, and its results record provider, model and date without
  keys. Basic and showcase need no model, backend, account or Python. The remote example requires an
  explicitly chosen real server and must not start one implicitly on library import.
- `basic_editor` MUST work with no theme override, no builder, no custom helper and no presentation code of
  its own; this path is the primary quick start, not a reduced demo mode. `extension_host` adds separate
  scenarios: standard editor without overrides; theme tokens only; one replaced scalar control with the
  rest standard; a decorator around the default node; an own design system across several slots; a
  custom model-connection wizard using standard bound fields plus a special model picker; and a
  fully custom presentation over the public controller. All scenarios use one library implementation, and
  moving from the first to later ones requires no fork, no copied renderer and no new persistence
  implementation. The wizard example contains only domain markup, steps and action-service registration; local
  draft, conflict detection and validate, accept and cancel are provided by the library.
Reference: acceptance IDs LIB-02, AI-04, AI-05, AI-06, DEM-01, DEM-02, HUI-01, HUI-02, HUI-03, HUI-05.

## 25. Test matrix
Affected: new baseline section "Test matrix".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- **Core**: Unicode, surrogate pairs, quotes, comments, templates, CRLF, BOM, missing final newline,
  duplicate keys, zero, false, null, absent and default, bounds, unions, dynamic keys, cycles, arrays, `any`
  and limits. Exact integer safety is verified between Dart native, Dart Web and Python: values
  outside the safe portable range MUST NOT be silently rounded. The default interoperable integer range is
  −9007199254740991 to 9007199254740991; larger values require an explicit lossless extension.
- **Storage and fault injection**: three storage modes and both remote profiles, bootstrap and source
  switching, Save As and import cancellation, invalid import, stale import, literal-secret export policy,
  host callback faults, localStorage availability and quota, two writers and two tabs for declared
  concurrency backends, stale descriptor and resolver snapshots, cancelled writes, lock timeout,
  interrupted commit, uncertain outcome, quota exceeded, read-only location, corrupt source, invalid
  backup, external edit. Both bytes and the observable guarantees of each adapter are verified.
- **Widget and integration**: every supported type, control and action, staged batches, AI proposals,
  search and reveal, absent, default, null, template, union object and array, unknown repair, responsive
  layout, text scaling, keyboard and focus, ARB switching, theme and host embedding. Disposal
  leaves no listeners.
- **Host presentation and subforms**: the standard path without overrides and every customization level.
  Mandatory checks include fallback of a missing optional override, local scope and
  deterministic priorities; absence of recursive decorator or fallback calls;
  typed null, absent, template and union semantics and the invalid editing buffer; retention of focus, scroll
  and draft across theme and renderer changes; create-wizard without adding an empty element to the parent
  draft; cancel with no change and accept with no storage write; child draft conflicts with manual input and
  AI proposals; parent reorder, rename, delete and descriptor change while the form is open; nested session
  lifecycle, stale async results and disposal; protected descendants and subtree scope enforcement; default
  presenter on compact and expanded, localization and accessibility; and one wizard contract across all
  three storage modes.
- **Security**: a secret under a union, array or subtree does not leak through an ancestor read, the search
  index, annotations, diagnostics, AI tools or logs. An unauthorized direct service call is rejected
  regardless of a hidden button. Read-only descendants are checked on composite replace. A remote client does
  not choose a server file path.
Reference: `TEST.md` (to be created), acceptance IDs in §Acceptance.

## 26. Errors, limits and observability
Affected: new baseline section "Errors and limits".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- Base stable codes, identical to the Python `errors.py` set: `BAD_REQUEST`, `PARSE_ERROR`,
  `UNAUTHORIZED`, `FORBIDDEN`, `NOT_FOUND`, `REVISION_REQUIRED`, `REVISION_CONFLICT`,
  `COMMENT_PRESERVATION_CONFLICT`, `PAYLOAD_TOO_LARGE`, `VALIDATION_ERROR`, `INVALID_DESCRIPTOR`,
  `SECRET_ACCESS_DENIED`, `LOCK_TIMEOUT`, `CALLBACK_TIMEOUT`, `NO_VALID_BACKUP`, `STORAGE_ERROR`,
  `UNSUPPORTED_CAPABILITY`, `INTERNAL_ERROR`.
- Network errors and AI errors have their own namespaced codes and are not masked as validation failures. A
  structured issue contains path, rule or code, severity, message and source location where
  available. User-facing messages are localized by code; technical detail need not be translated and MUST
  NOT contain secrets.
- Measurable resource limits carry over. Initial compatibility profile: document or body up to 8 MiB, depth
  64, collection size 100000, string length 1048576, pattern length 512. The unit semantics of length
  values are documented. These limits do not guarantee instant rendering of a huge tree; the UI uses
  bounded or lazy snapshots and virtualization.
- Regex validation MUST NOT promise a safe timeout through an ordinary `Future`: the implementation
  chooses a bounded engine or worker, or refuses a potentially dangerous unsupported pattern. Restrictions of
  the regex dialect are fixed by the parity corpus; the Python baseline forbids lookarounds, named-group
  backreferences and numeric backreferences in descriptor patterns.
Reference: acceptance IDs IO-06, SEC-01.

## 27. Deliverables and documentation
Affected: new baseline section "Deliverables".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- Mandatory deliverables: the packages, a public API reference, an integration guide, the descriptor and
  extension grammar, storage guarantees, a permissions guide, an AI module guide, a migration and
  compatibility report, the examples, fixtures, automated tests, and reproducible run and check commands.
- `README.md` MUST show the short connection path without a host renderer or backend.
  Facts about the actual implementation are separated from the roadmap. Tests are not considered passed
  because test files exist: a report contains the commands actually run and their results.
Reference: `AGENTS.md` "Testing and document validation".

## 28. Acceptance criteria
Affected: new baseline section "Acceptance criteria".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change: each ID below is a mandatory, observable proof. A version is ready only against this matrix plus
documented exceptions and working examples — never because a similar UI exists.

| ID | Mandatory proof |
|---|---|
| LIB-01 | Package and standard editor connect without copying sources |
| LIB-02 | Basic and showcase examples run without Python and without AI |
| LIB-03 | Core does not depend on Flutter or native-only APIs |
| DAT-01 | Absent, null, default, false and zero are distinguishable |
| SRC-01 | An accepted edit preserves unrelated bytes, comments and placeholders |
| SRC-02 | A preservation conflict does not cause full reserialization |
| DSC-01 | Portable Python descriptors pass the versioned corpus |
| TPL-01 | Descriptor templates round-trip between Python `aiset` and `aiset_flutter` over the shared grammar with the same meaning, in both directions |
| RES-01 | Resolver precedence and conversion match the corpus |
| MRG-01 | Base-first default and explicit update-first do not mutate inputs |
| OPS-01 | All six operations and a create-then-fill batch work atomically |
| REV-01 | Missing or stale revision pairs are rejected |
| STO-01 | Adapters with declared concurrency support lose no changes with two writers or Web tabs; limited adapters are marked explicitly |
| STO-02 | `remote_api` loads and saves through an API with a revision check; both API profiles verified |
| STO-03 | `host_api` uses the provided host adapter with no direct aiset access to host files |
| STO-04 | `local` supports native and mobile storage and Web localStorage; backend guarantees are shown |
| STO-05 | API or storage unavailability is not treated as a missing file and does not cause a seed overwrite |
| STO-06 | Bootstrap determines the source before the main AppConfig is read |
| IO-01 | Save As exports JSON5 in all three modes and does not change the working source |
| IO-02 | Export of saved or candidate does not commit a draft; secret policy is respected |
| IO-03 | Import passes parse, version, descriptor and semantic validation, diff and confirmation |
| IO-04 | An invalid or stale import changes neither the current source nor active settings |
| IO-05 | Import in remote or host mode is saved only through the selected API |
| IO-06 | Cancelling the file picker changes nothing; a storage or quota failure does not damage the old source |
| APP-01 | Stored and active differ; a callback error does not hide the commit |
| LKG-01 | Fallback does not overwrite an invalid current source |
| DOC-01 | Doctor does not save a partially repaired invalid candidate |
| UI-01 | The editor is driven by the public controller and works in all layouts |
| UI-02 | Search, reveal, raw, template, nullable, union, absent and default are covered by integration tests |
| HUI-01 | The standard editor and page work without a single host UI override |
| HUI-02 | The host replaces one component; the rest use ready defaults |
| HUI-03 | Fully custom UI uses the same public controller without private imports |
| HUI-04 | Theme tokens and renderer overrides are independent, local and do not reset the draft |
| HUI-05 | A custom wizard reuses bound fields, generic sections and the standard presenter |
| HUI-06 | Subform Cancel changes neither parent draft nor source; accept changes only the parent draft |
| HUI-07 | Parent or AI changes during a wizard are neither lost nor overwritten by a stale snapshot |
| HUI-08 | A temporary new element does not appear in the main draft before accept |
| HUI-09 | Required validation and permissions apply to any host renderer |
| HUI-10 | The application need not implement wizard layout or navigation when using defaults |
| HUI-11 | An unknown optional helper allows a safe fallback; a required capability is not ignored |
| HUI-12 | One subform contract works in all three storage modes |
| SIM-01 | Primary conditions change visibility, not data or permissions |
| LOC-01 | ARB, system and manual locale with runtime switching work |
| AI-01 | A real model reads, validates and proposes staged operations |
| AI-02 | Source bytes are unchanged before Apply |
| AI-03 | A changed or stale proposal requires a new review |
| AI-04 | An example contains no own agent-loop implementation |
| AI-05 | One library connection call gives the standard editor a working assistant; no example code builds a panel, tool loop or proposal review |
| AI-06 | With no AI layer installed or connected, the standard editor is complete and shows no assistant affordance |
| SEC-01 | A secret subtree is unavailable without permissions on every surface |
| REM-01 | The remote example works with Python aiset through public endpoints |
| EXT-01 | A new plugin branch, widget and AI provider connect without changing library source |
| DEM-01 | Examples seed state only when absent and never modify tracked assets |
| DEM-02 | Every public capability has a runnable example scenario |

## 29. Implementation stages
Affected: new baseline section "Implementation stages".
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
1. Fix the compatibility corpus, the parser and source-preservation prototype, and the package boundaries.
2. Implement the pure Dart core, the three storage modes and bootstrap — memory for tests,
   native and app storage, Web localStorage and IndexedDB, the host API bridge and the remote
   contracts — plus revisions, descriptor, resolver, merge and core tests.
3. Release a working vertical slice: `basic_editor` with real persistence and the generated tree, with no
   throwaway UI.
4. Complete structural operations, the source editor, doctor, LKG, subscriptions, the mandatory Save As and
   Import JSON5, and `showcase`, up to tier 1 and tier 2 corpus coverage.
5. Add simple and advanced modes, theme and localization, fragments and extensions, and `extension_host`.
6. Add the optional AI module, the OpenAI provider, the reusable AI panel and the real `ai_assistant` app.
7. Verify remote Python compatibility, browser concurrency and the full platform matrix. MCP
   stays deferred under amendment 33 while Python has no implementation.
- A working default integration is preserved at every UI stage. A headless API is never a reason to shift
  the duty of drawing an editor onto the host. Before the presentation API is declared stable, three things
  must work together: the zero-override basic editor, a single-component override, and an isolated custom
  wizard. A fully custom UI is an additional extensibility check, not the primary connection path.
- Unexecuted hooks and validators are honestly marked unsupported; if they belong to a declared capability of a
  version, real implementation and tests are required.
Reference: `ROADMAP.md` §2.

---

## 30. Parity boundary: observable behavior, not Python structure
Affected: `SPEC.md` "Purpose" and "Compatibility"; qualifies amendments 1, 24 and 29.
Approval: user instruction 2026-11-10 — the implementation MUST NOT repeat `aiset` at file level;
files and technological decisions may differ; use what is native to Flutter rather than to Python.
State: confirmed requirement (not yet implemented)
Change:
- Parity binds the **observable surface**, never the implementation beneath it. The surface is
  graded in three tiers by amendment 32, which governs wherever the two amendments differ: the settings
  file format and the semantic result of each operation — byte-identity with the text Python would produce
  is not required; what the descriptor grammar accepts and rejects and what a node means; resolution,
  precedence, conversion and provenance results; merge results; validation outcomes and limits; the
  stable error codes; the HTTP transport envelope on the remote path; and revision and CAS behavior
  against a real backend.
- Everything beneath that surface is **free and MUST be designed natively for Dart and Flutter**: package,
  library, file and directory layout; class, function and module names; internal data structures,
  including the CST representation and snapshot layout; algorithms, provided observable results and
  documented limits hold; the concurrency and locking model, using async and isolates rather than threads;
  the test framework and fixture format; the widget, controller and theming architecture; and the
  regular-expression engine within the accepted dialect subset.
- Conflict rule: a property that a host application, a settings file or a backend client can observe MUST be
  reproduced and proven by a corpus fixture. A property that exists only because of how Python `aiset`
  happens to be implemented MUST NOT be inherited. "Python does it this way" is not an argument for a Dart
  design decision, and no Dart API is shaped to mirror a Python name where an idiomatic design differs.
- Explicit non-goals: no file-for-file or module-for-module port; no reuse of Python source, of the
  generated web tree editor JS and CSS assets, or of Python test-runner machinery; no translation of
  Python idioms that have no Dart analogue.
- The mandatory editor feature set of amendment 15 is a behavioral requirement. It MUST be
  built from Flutter widgets, controllers and theming, and MUST NOT attempt to reproduce the Python web
  editor's DOM or JavaScript structure.
- Where a Dart-native design changes an observable surface, that is an intentional divergence and follows the
  registration rule of amendment 24.
Reference: `ARCHITECTURE.md` §1 and §2 are the target structure; §6 indexes behavior only.

## 31. AI assistant connection is a library feature of the Flutter layer
Affected: `SPEC.md` "AI modules" and "Default UI"; qualifies amendments 1, 16, 21, 23 and 24a.
Approval: user instruction 2026-11-10 — connecting the AI assistant must be supported by the library
itself in the Flutter version, not live in an example.
State: confirmed requirement (not yet implemented)
Change:
- The library MUST provide the connection path for the assistant. One explicit library call or bootstrap
  parameter attaches a provider and assistant to a controller or session, and from that moment the
  ready UI presents the assistant: an entry in the toolbar and actions slot plus the chat, activity and
  proposal surface. The host MUST NOT have to assemble any of it.
- The host and the examples MUST only choose a provider, configure it, and supply credentials through
  `CredentialResolver`. The panel, chat and activity views, proposal review and diff presentation, the tool
  loop, staging, approval binding, conflict handling and redaction are library-owned. An example that
  re-implements any of them is a defect, not a demonstration.
- Dependency shape is unchanged from amendment 1: `aiset_flutter` MUST NOT hard-depend on `aiset_ai` or
  `aiset_ai_openai`. The AI layer contributes its UI through the same public slot, delegate and registry
  contracts of amendments 16, 17 and 23 that a host or extension uses — there is no privileged private path
  from the default editor into the assistant.
- Absence behavior: when no assistant is connected, the standard editor is fully functional and shows
  no assistant affordance. A dead button, an empty panel, a placeholder error or a configuration prompt
  imposed by the library is not acceptable. Guidance shown because the host deliberately offers an
  assistant setup screen — the AI example without credentials in amendment 24a is that case — is host
  content, not a library affordance, and does not weaken this rule.
- The connection MUST work for the headless path as well, so a host with fully custom presentation
  gets the same assistant through the controller contract; the assistant is not bound to the
  default skin. `AisetSettingsApp` MUST host it on the same terms.
- Connection is per controller or session, never a hidden process-wide singleton:
  two editors in one process MAY have different providers or none.
- New acceptance IDs AI-05 and AI-06 are additions relative to the reviewed draft, introduced by this
  amendment.
Reference: acceptance IDs AI-01..AI-06, SEC-01, HUI-01, LIB-02.

## 32. Compatibility scope and behavioral authority
Affected: `SPEC.md` "Purpose" and "Compatibility"; governs amendments 24 and 30 where they differ.
Approval: user instruction 2026-11-10 — the newest Python `aiset` commit is the most correct; the
practical implementation prevails over documentation; correct means how Python `aiset` behaves;
`aiset-flutter` is not a fork and is written from scratch; required are mutually compatible
descriptor templates and the same logic (automatic editor construction, embedding and so on) in
Flutter form; interface specifics and anything Flutter does differently go the Flutter way;
functionality must be similar, not even identical.
State: confirmed requirement (not yet implemented)
Change:
### Behavioral authority
- The authoritative statement of required behavior is the **newest commit of Python `aiset`**. Where Python
  prose (`README.md`, `SPEC.md`, `SPEC_.md`, `SPEC_service.md`, `AGENT_INTEGRATION.md`) contradicts Python
  code or tests, **code and tests win**, and the contradiction is reported rather than resolved
  in favor of the document.
- Expectations are derived by executing the baseline. It imports with zero runtime dependencies, so
  the generator in `tool/` calls it directly and also runs its test suite; prose only names
  which areas to cover.
- The baseline is re-fetched before each corpus generation and the commit SHA actually used is recorded with
  the produced fixtures.
### Compatibility tiers
- **Tier 1 — mutual compatibility, mandatory.** Descriptor templates MUST be mutually compatible: a descriptor
  Python `aiset` accepts MUST be accepted by `aiset_flutter` with the same meaning, and a Flutter descriptor
  using only shared grammar MUST be accepted by Python. The settings document format
  belongs to the same tier: JSON5 acceptance and values, placeholders, JSON Pointer and mount grammar,
  resolution and precedence, conversion, provenance, merge, validation outcomes and limits. A file written by
  one implementation MUST remain readable by the other.
- **Tier 2 — same logic, Flutter-native means.** The behavioral role MUST be preserved while the mechanism is
  Dart and Flutter native: descriptor-driven automatic construction of the editing interface, the embedding
  and integration model, one service write pipeline, revisions and CAS, staged operations and drafts,
  capability reporting, doctor, LKG and backups, subscriptions and permissions.
- **Tier 3 — no parity obligation.** Presentation and interaction, widget and controller architecture, public
  API naming, exception hierarchy and message text, concurrency and locking, storage and test frameworks, and
  the breadth of the feature set. Functionality MUST be similar to Python `aiset`; it MUST NOT be assumed
  identical, and no acceptance criterion requires identity in this tier. A Flutter-appropriate capability
  with no Python analogue is in scope as a platform vehicle, and a Python capability that is a DOM or
  CPython artifact is not. Net-new functional features are governed by amendment 33, not by this bullet.
- Remote interop is a wire contract, not a parity claim: a Flutter client addressing a running Python backend
  MUST match that backend's envelope and error codes on the path it uses. Byte-for-byte identity between a
  Flutter edit result and the result Python would produce for the same operation is not required; semantic
  equivalence plus the preservation guarantees of amendments 3 and 8 is.
- The 18 stable error codes are adopted as this library's own error vocabulary in their own right, and MUST
  match Python wherever tier 1 or the remote path depends on it.
Reference: acceptance IDs TPL-01, DSC-01, RES-01, MRG-01, REM-01; `ARCHITECTURE.md` §6.

## 33. Feature scope follows the Python implementation state
Affected: `SPEC.md` "Purpose", "Compatibility", "Remote and MCP"; governs amendments 22 and 32.
Approval: user instruction 2026-11-10 — no newer Python branch exists today; features described as
unimplemented will be implemented in the future, but features that Python `aiset` does not implement are
not implemented here either for now; this is recorded as general roadmap logic. Parity is not required —
compatible configs and close functionality are.
State: confirmed requirement (not yet implemented)
Change:
- **General rule.** A capability that the current Python `aiset` implementation does not have is out of
  scope for `aiset-flutter` for now. This library does not run ahead of the Python project. When Python
  implements such a capability later, it becomes in scope here under the tier rules of amendment 32, and the
  compatibility report records the baseline version it was taken from.
- Parity is **not** a goal in itself. The obligations are tier 1 configuration and descriptor compatibility
  and a close functional profile.
- Deferred by this rule, because upstream has no implementation: the **MCP facade** (`packages/aiset_mcp`)
  and the **descriptor lifecycle-hook dispatcher**. Hooks keep the upstream behavior exactly: the grammar is
  accepted and compiled, and execution is reported `UNSUPPORTED_CAPABILITY`.
- A deferred capability MUST NOT be presented as supported anywhere: not in `README.md`, not in the API
  reference, not in capability flags, not as a disabled control in the editor.
- Platform vehicles are not new features. Where Flutter requires a different mechanism for the same
  capability — widgets instead of a DOM, isolates and async instead of threads, an adapter object instead of
  a module-level singleton — that is tier 2 mechanism work and stays in scope. Net-new functional
  features with no Python counterpart are not.
Reference: `ROADMAP.md` §5 and §7; amendments 22, 32.

## 34. License and dependency-license policy
Affected: `SPEC.md` "Repository and packages", "Compatibility"; extends amendment 27.
Approval: user instruction 2026-11-10 — MIT is acceptable, the project is open; publication to pub.dev is
not planned now but is possible in the future.
State: confirmed requirement (not yet implemented)
Change:
- The project is licensed under the **MIT license**. Every package under `packages/` and every example
  carries a `LICENSE` file with the MIT text and the copyright line, plus the matching
  `license:` field in `pubspec.yaml`. A `LICENSE` file is also a hard requirement of pub.dev publishing,
  so it is present from the first commit of each package rather than added at release time.
- The upstream Python `aiset` declares MIT in `pyproject.toml` but ships no `LICENSE` file. Where this
  project reproduces upstream material verbatim — test fixture inputs and expected outputs in
  `fixtures/python_compat/` — it MUST keep an attribution notice with the copyright line and the
  MIT text alongside that material. Reproduced behavior needs no attribution; reproduced files do.
- **MIT does not restrict which dependencies this project may use.** The obligation runs the other way: MIT
  governs what recipients may do with this code, while each dependency's license governs what this project
  must do when distributing it. The policy below follows from that.
- Dependency license policy:
  - **Accepted without review** in any package: MIT, BSD-2-Clause, BSD-3-Clause, Apache-2.0, ISC, Zlib.
  - **Requires review** before adding: MPL-2.0 and other file-level weak copyleft, LGPL, any dependency
    that links native code (Kotlin, Swift, Objective-C, C, C++), and anything with a copyleft
    clause whose scope is unclear for a source-distributed Flutter library.
  - **Not permitted** in `aiset_core`, `aiset_flutter`, the storage and remote packages or
    `aiset_ai`: GPL, AGPL, SSPL, and licenses restricting field of use or commercial use. Such a
    dependency would impose source-availability or relinking obligations that MIT distribution
    cannot honor.
  - An example or a `tool/` script MAY take a stricter dependency only when it is not redistributed as
    part of a published package, and the reason is recorded next to the dependency.
- Vendoring is not a loophole: copying third-party source into this repository keeps its original
  license obligations attached, so the same tiers apply to vendored code.
- No secret, credential or signing key is ever committed; this is enforced by `.gitignore`
  and by review.
Reference: `ROADMAP.md` §4 D-04; amendment 27.

## 35. aiui host integration deferred from the MVP
Affected: `SPEC.md` "Purpose", "Extensions", "Repository and packages"; qualifies amendments 1, 7
and 23.
Approval: user instruction 2026-11-10 — `aiui` support is not implemented in the MVP.
State: confirmed requirement (not yet implemented)
Change:
- The `aiui` host integration surface is out of the first implementation increment: the
  single `AppConfig` document convention, the `plugins.<id>.settings` placement, and the
  `ui.settingsEditor` wiring.
- Deferred provisions, named exactly: amendment 1 "For the `aiui` host exactly one main `AppConfig` document is
  registered…"; amendment 7 "For `aiui` the main config is `base` and a plugin's defaults are `update`…";
  amendment 23 "An aiui plugin's settings are placed in `plugins.<id>.settings` of the single `AppConfig`."
- Still mandatory, because these are generic mechanisms and not aiui policy: registering several allowlisted
  documents in one service; merge with host-defined base and update roles; descriptor and data fragments
  mounting at coordinates with a free-space check; the public contribution registry; bootstrap source
  selection before the main config is read (STO-06); and the rule that UI registries and callbacks are
  never serialized into config data.
- No `aiui`-specific name, path or default may enter the library API, fixtures or documentation on the strength
  of a deferred integration. Where a generic contract needs an example, an example under `examples/` is used,
  not an `aiui` shape.
- When the user schedules `aiui` work, the deferred provisions above become active without
  changing the generic contracts. Until then they are confirmed requirements that are not implemented and MUST
  NOT be counted toward acceptance or described as supported.
Reference: `ROADMAP.md` §1 rule 10, §5 and §7; amendments 1, 7, 23.

## Consolidation notes for `SPEC.md`
- Amendments 1-35 including 24a are self-contained: no other project document is required to read them.
- The acceptance matrix has 54 IDs: 51 from the reviewed draft, plus AI-05 and AI-06 (amendment 31) and TPL-01 (amendment 32).
- On consolidation, the behavioral authority snapshot in the header MUST be re-checked and, if the user
  pins a different commit, updated here first.
- Deviations from Python behavior that are intentional corrections (for example the resolver no longer
  reading the process environment by default, and registration by document ID instead of file path)
  MUST be recorded in the compatibility report with a fixture, per amendment 24.

## Known intentional differences from the Python baseline
Affected: amendment 14 (public API), amendment 6 (resolver), amendment 10 (storage modes).
Approval: as amendment 1.
State: confirmed requirement (not yet implemented)
Change:
- Python `Service.register(document_id, path, descriptor_source, ...)` binds a document to a
  file path. The Dart contract MUST bind it to a storage adapter object instead, which is what makes
  `host_api` and `remote_api` first-class modes rather than file storage plus a proxy.
- Python `Resolver` defaults `environ` to the process environment. The Dart core MUST NOT read any
  environment implicitly; the mapping is injected by the host.
- Python ships one durable backend, a file `Store` with `.back` rotation and a file lock. The
  Dart port generalizes this into the adapter capability model of amendment 11; the native file
  adapter MUST reproduce the Python guarantees, including the default backup depth of 5.
- Python exposes a generated web editor as static assets. The Flutter editor is a native reimplementation of
  the same tree and capability contract, not a WebView wrapper around those assets.
Reference: `ARCHITECTURE.md` §6.




