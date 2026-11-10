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
