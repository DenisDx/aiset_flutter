# SPEC_.md — aiset-flutter specification overlay

Accumulated approved amendments intended for later consolidation into `SPEC.md` by the user or an external
process. An explicitly identified approved amendment takes precedence over the corresponding `SPEC.md`
provision; every unaffected baseline provision stays in force. Agents never merge this file into
`SPEC.md` and never delete it as part of a merge.

Status: **one amendment recorded.** Created 2026-11-10 on the user's authorization, after the previous
overlay was consolidated into `SPEC.md` (commit `f7bb62b`).

## 37. Repository neutrality toward other authors and their tools
Affected: `SPEC.md` "Repository and packages", "Deliverables and documentation", "Test matrix".
Approval: user instruction 2026-11-10 — operator and agent-system tooling is excluded because the project
builds and runs without it, and, in the user's words, other authors may have their own tools.
State: confirmed requirement (not yet implemented)
Change:
- The repository is **tool-neutral and author-neutral**. Files that serve one developer's agent system,
  editor, shell helper or operating environment MUST NOT be required to build, test, run or document the
  project, and are kept out of version control.
- Formally: a fresh clone MUST build and pass its test suite with none of `AGENTS.md`, `memory/`,
  `.opencode/` or `local_tools/` present. No build script, test, fixture, `pubspec.yaml` or documented
  command may depend on them. The check applies to executable content and to commands a user is
  told to run; project prose MAY name these paths in order to state the exclusion policy, because naming a path
  is not depending on it.
- Where a development convenience exists only outside the repository, the tracked documentation
  describes the **policy it implements**, not the private path, and states that other authors may satisfy
  the policy with their own tools.
- This does not weaken reproducibility: everything that defines correct behavior — the
  generated corpus, fixtures, the recorded baseline commit, and the commands that run the checks —
  stays versioned.
- **LIB-04 is a new acceptance ID**, absent from the consolidated `SPEC.md` matrix, which
  currently ends at LIB-03. On consolidation the matrix grows from 55 to 56 IDs. Agents do not edit
  `SPEC.md`, so the ID is requested here rather than added there.
Reference: `SPEC.md` amendment 1 (package boundaries), amendment 25 (test matrix);
`ROADMAP.md` §1 rule 14.


## 38. Python defects are never reproduced; they are reported upstream
Affected: `SPEC.md` "Compatibility"; qualifies amendments 24, 30 and 32.
Approval: user instruction 2026-11-10 — the project does not attempt to repeat Python `aiset`, still less
its errors or poor decisions; the product is compatible with it and reproduces its
functionality. Where the baseline is wrong, `aiset-flutter` does it correctly, and a notice and a
request are written to the handoff notes for the Python developers. The same applies to every future
divergence of this kind.
State: confirmed requirement (not yet implemented)
Change:
- A defect, crash path, misleading error or bad decision in the Python baseline MUST NOT be
  reproduced in `aiset-flutter`. "The baseline does it this way" is never a reason to copy the behavior;
  it is a reason to file a report.
- When the compatibility corpus records a baseline output that is wrong, the case keeps the baseline
  bytes as evidence, carries a `divergence` block naming the report entry, and **asserts the corrected
  behavior**. A divergence is never left as a skipped test once the correct behavior is known, and
  an expectation is never weakened to match a broken baseline.
- Each such finding is written up as a notice and a request in the handoff notes for the `aiset`
  Python team — a local, unversioned file named in `memory/context.md`, because it is
  correspondence about another project, not a source of this one.
- The report entry must be reproducible by executing the baseline, and must
  state the call, the actual result, why it is wrong and the requested change.
- Tier 1 compatibility is unaffected: descriptor and configuration formats, and the observable semantics
  of valid input, still have to match.
Reference: `ROADMAP.md` §1 rule 4; amendments 24, 32; acceptance IDs DSC-01, SRC-01.

## 39. User documentation is in-app help plus three documents in `docs/`
Affected: `SPEC.md` "Deliverables and documentation"; extends amendment 27.
Approval: user instruction 2026-11-11 — user documentation consists of the in-program help system
(through ARB files) and Markdown user documents in `docs/`; the three named documents live in `docs/`
and the documenter works on them.
State: confirmed requirement (not yet implemented)
Change:
- User-facing documentation has exactly two channels: **in-app help**, rendered from the library's
  localization resources (amendment 40), and **Markdown user documents** under `docs/`.
- `docs/` MUST contain these three documents:
  1. **`docs/overview.md`** — a human-readable description of how the system is built and behaves:
     the readable counterpart of `SPEC.md` and `ARCHITECTURE.md`. It links to them for
     normative detail instead of restating it, and it is written for a person who will use the library,
     not for an agent that implements it.
  2. **`docs/build-from-source.md`** — how to clone the repository and build and run it locally, with
     examples. Prerequisites — toolchain versions, Android SDK and emulator, browser access, Python for
     the corpus — are described in their own section, separately from the build steps.
  3. **`docs/integration.md`** — how to integrate the library into a host project: the three storage
     modes, bootstrap, embedding the editor, permissions, localization hookup and extensions.
- The **documenter** agent owns these three documents. Other agents report errors,
  gaps or stale statements in them; they do not rewrite them.
- `README.md` remains the short entry point and links to the three documents rather than duplicating them.
- `docs/grammars.md` is a technical record of accepted grammar subsets and limits, not user documentation,
  and stays outside this set.
- Originals are written in English. Translations follow the existing rule and are named
  `docs/<name>.<lng>.md`; whether all three are translated into every shipped language at the first stage
  is an open question recorded in `memory/context.md`, not a silent decision.
Reference: acceptance IDs HLP-01, HLP-02; amendment 27.

## 40. Built-in localization and a hint on every interactive control
Affected: `SPEC.md` "UI, themes and localization"; extends amendment 20 and acceptance ID LOC-01.
Approval: user instruction 2026-11-11 — built-in localization and ARB files are required, and every
button must have a hint shown on long tap.
State: confirmed requirement (not yet implemented)
Change:
- `aiset_flutter` ships its own localization resources in ARB format. The primary language is
  **English**; the first-stage language set is **English, Chinese (Simplified), Cantonese and Russian**.
  Adding a language must not require editing library code.
- **No user-facing string literal may live in library code.** Every label, hint, error text,
  confirmation prompt and empty-state message comes from the resources, and a
  missing translation is a build-time or check-time finding, not a runtime English fallback in a
  localized build.
- **Every interactive control in the generated UI MUST expose a hint.** The hint appears on
  long-press on touch devices and on hover with a pointer device, using the platform tooltip
  mechanism, and is additionally published to accessibility so it is available to screen readers.
- A hint is never the only carrier of meaning: the control also has a visible label and a semantics
  value, and disabling, errors and progress remain perceivable without discovering a hint.
- Locale selection order: an explicit host parameter, then the platform locale, then English. When the
  requested locale is unavailable, the fallback is reported through the library diagnostics and
  the UI states that content is shown in another language; it is never silent.
- Language tags are normalized to BCP-47. The tag used for Cantonese and whether a
  separate Traditional Chinese resource is also required is an open question
  recorded in `memory/context.md`; the implementation must not hardcode a choice that
  forecloses it.
Reference: acceptance IDs LOC-01, LOC-02, LOC-03, HLP-02; amendment 20.

## 41. Multilingual descriptions of settings elements
Affected: `SPEC.md` "Descriptor grammar and Flutter extensions", "UI, themes and localization";
extends amendments 5 and 40.
Approval: user instruction 2026-11-11 — descriptions of UI elements must be multilingual;
this does not exist in Python `aiset`, so the invented design is also written up as a request
to the Python team.
State: confirmed requirement (not yet implemented)
Change:
- The descriptor `description` field accepts **two forms**:
  1. a **string**;
  2. an **object** mapping a normalized language tag to a string, for example
     `{"en": "Retry count", "ru": "Число повторов"}`.
- **String form.** The text doubles as the lookup key for the active locale, so an untranslated
  descriptor still displays its own text. When no translation is found, the string is shown
  verbatim; this is the documented behavior and not an error.
- **Object form.** The entry for the active locale is used. If it is absent, the entry for the
  descriptor's declared default language is used. The object MUST contain that default-language
  entry; an object without it is a descriptor error with a diagnostic pointing at the field.
- **Resolution order** for the description shown to a user: the object entry for the active locale;
  otherwise a host-supplied translation for the string key in the active locale; otherwise the
  default-language entry of the object; otherwise the string itself. A resolved value is never
  re-translated again.
- **A locale-unaware reader still gets a string.** A command-line tool, a health endpoint, a log line or a
  legacy consumer resolves the object to its default-language text; `description` is a string after
  resolution in every such path.
- **Comments stay a single-language source.** A source comment may still provide a
  description, as in the baseline, but it is treated as default-language text and is never translated.
  Where both a `description` field and a comment exist, the field wins, matching the baseline.
- **Host translation hook.** A host may supply a translator callback so descriptor text can come from
  its own resource store. The library's own ARB resources cover library chrome — labels, buttons,
  hints, errors — and are not a place to put descriptor content.
- **Compatibility.** The Python implementation will reproduce this capability — confirmed by
  the user on 2026-11-11 — so the object form is a **shared grammar extension**, not a one-sided
  deviation. The cross-project design note, including the error table and the test matrix both
  implementations must share was delivered as item **F1** of `local_aiset_python_notes_1.md` on 2026-11-11.
  Until the Python side lands, the object form is not mutually readable, so descriptors intended for the
  current Python release stay in the string form; the compatibility corpus keeps its present baseline
  pin and gains object-form cross-implementation cases on the normal re-baseline path after the
  upstream change. Export to legacy mode flattens a multilingual description to its
  default-language string in an exported copy, never in the original file.
- **Concrete shape of the object.** A bare language map is ambiguous with a legitimate
  object-valued setting and offers no way to name a default language, so the accepted form is a
  wrapper with `text` and an optional `default`, and a bare map is rejected:
  `{ default: 'en', text: { en: '…', ru: '…' } }`. Unknown keys inside the wrapper are a descriptor
  error, so a misspelled `default` cannot silently disable the default-language rule. This refines the
  shape proposed by the user and **confirmed by the user on 2026-11-11**.
- The same two-form treatment applies to `title`, so the mechanism is uniform for user-facing
  descriptor text.
Reference: acceptance IDs DSC-02, DSC-03, LOC-04; amendments 5, 20, 40; delivered feature
request F1 in `local_aiset_python_notes_1.md`.

## 42. User help and developer documentation are separate channels for separate audiences
Affected: `SPEC.md` "Deliverables and documentation", "Default UI", "UI, themes and localization";
qualifies amendments 15, 39, 40.
Approval: user instruction 2026-11-13 — the markdown documents in `docs/` are documentation FOR
DEVELOPERS integrating the library (how the system works, how to embed it,
examples, and a minimal working example of a few lines); hints and ARB files are help for
the USERS of the program, so that they can understand what each config parameter is
responsible for; these are completely different things for different users and travel
different paths; a browser of md articles can never exist — those articles are not for users and
will not be present in a product release at all; "no browsers, and there will not be any"; the
Python editor does it right: search over title, description and value; contextual mini-help is a
good thing and is needed, with English as the base language and an English fallback acceptable
for now, everything to be translated in the ideal.
State: confirmed requirement (not yet implemented)
Change:
- `docs/` documents are developer and integrator documentation: system principles, integration
  guide, runnable examples, and a minimal working example that MUST fit in a few lines.
  They MUST NOT be treated as user-facing help, and a product release is complete without
  them.
- The application MUST NOT contain a browser, viewer, renderer or search over `docs/`
  markdown, and MUST NOT load or package those files into the running app. This prohibition is
  permanent, not a phase: user help travels only the ARB channel (amendment 40).
- User-facing help is exactly three layers: chrome strings and hints on every interactive control
  (amendment 40), and **contextual mini-help** — short localized explanations for each
  screen, section, primary action, and each error class, drawn only from ARB resources.
- Mini-help language scope for the first stage: English is the base; a missing translation
  falls back to English explicitly rather than silently omitting help. Full translation of help
  strings remains a requirement, just not a blocker.
- Search scope is clarified to match the Python editor: search MUST match the node
  `title`, the `description`, the key/path and the stored value text. Matching text of the
  current locale MUST match; matching the descriptor's default language in
  addition SHOULD match; matching all available localized languages MAY be implemented if
  it is not complex. Secret values remain excluded (amendment 15).
Reference: acceptance HLP-01, HLP-02; `ROADMAP.md` D-12 resolved.

## 43. Language tags follow the open standard, parsed leniently, resolved with fallback
Affected: `SPEC.md` "Descriptor grammar", "UI, themes and localization"; qualifies
amendments 40 and 41.
Approval: user instruction 2026-11-13 — follow the standard rules, not Flutter-narrow rules (a general
strategy); match more freely when parsing (`RU`, `ru`, and better to understand
more complex codes), basing on ISO 639; understanding extended tags like `yue` and `zh-Hant` is
very good.
State: confirmed requirement (not yet implemented)
Change:
- Tag grammar follows the open standard (BCP-47 / RFC 5646 syntax over
  ISO 639 language subtags), not any platform's narrower subset. Parsing is lenient
  within the standard grammar and case-normalized per the standard; complex
  registered-style tags (`yue`, `zh-Hant`, `sr-Latn-RS`) MUST be understood. A
  syntactically valid 5–8 letter primary subtag (the `english` case of cross-project item F2)
  is accepted per RFC 5646, closing F2 on our side; the request to upstream to
  adopt the same standard grammar stays in the handoff notes.
- Lookup uses the standard truncation fallback chain (`ru-RU` → `ru`),
  then the descriptor default language, then the literal string
  (amendment 41 precedence).
- Cantonese is tagged `yue` (script variants like `yue-Hant` resolve through truncation);
  `zh-Hant` is a Traditional-Chinese script tag and MUST NOT be used as a stand-in for
  Cantonese. This closes the open language-tag question recorded in amendment 40 (D-10).
Reference: `ROADMAP.md` D-10 resolved; handoff notes item F2; amendments 40, 41.

## Recording rules

- One `##` section per amendment, in the format defined in `AGENTS.md`: `Affected`, `Approval`, `State`,
  `Change`, `Reference`.
- Numbering continues the baseline sequence, so the first entry recorded here is **amendment 37**.
- Record only implemented approved changes, or product requirements that the user explicitly confirmed.
  Development plans and idea backlogs belong to `ROADMAP.md` and `proposal_*.md`, not here.
- `Approval` must cite the user's instruction or the accepted proposal, not an agent's reasoning.
- When an amendment changes behavior described in an existing `spec_<name>.md`, that specification is
  updated with it.
- Implementation alone does not establish approval, and unimplemented behavior recorded
  here is a confirmed requirement, never a claim that it ships.
