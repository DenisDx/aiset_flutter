# SPEC_.md — aiset-flutter specification overlay

Accumulated approved amendments intended for later consolidation into `SPEC.md` by the user or an external
process. An explicitly identified approved amendment takes precedence over the corresponding `SPEC.md`
provision; every unaffected baseline provision stays in force. Agents never merge this file into
`SPEC.md` and never delete it as part of a merge.

Status: **empty** — no amendments recorded. Created 2026-11-10 on the user's authorization, after the
previous overlay was consolidated into `SPEC.md` (commit `f7bb62b`).

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
