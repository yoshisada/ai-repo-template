# Specifier Friction Notes — plugin-naming-consistency

## PRD clarity

The PRD was unusually clean for a rename feature — the full rename table was in the PRD (FR-005, FR-006), collision resolutions were explicit (FR-001, FR-002), and cutover semantics were unambiguous (hard cutover, no shims). No ambiguity required to punt to `/clarify`.

One soft ambiguity: FR-004 says "move the logic … into helpers that `/kiln:fix` calls inline" — this could mean (a) inline the prose into `fix/SKILL.md` or (b) factor into separate bash scripts. Either is valid. The plan defers the call to the Phase K implementer based on post-absorption size; flagged as a decision point, not a spec gap.

## Rename table completeness

The PRD's tables covered 25 skill renames + 2 skill deletions (3 including create-repo) + 6 workflow renames. Survey of the plugin directories confirmed the tables are exhaustive — no additional skills or workflows require renaming. Specifically:

- Kiln's `kiln-cleanup` and `kiln-doctor` skills have the `kiln-` prefix but are NOT in the FR-005 table. Explicit decision: leave as-is for this feature (the PRD lists only "redundant prefix" — `kiln-doctor` reads as an action name, not a redundant prefix). Noted in Table 1 commentary so implementers don't "fix" these by accident.
- Trim's `trim-library-sync.json` workflow needed a decision. Chose to rename to `library-sync.json` since the owning skill `trim:library` has a "sync" sub-mode — filename reflects mode, acceptable FR-006 variant. Noted in Table 2 commentary.
- Wheel's `example.json` and shelf's `propose-manifest-improvement.json` are correctly flagged unchanged.

## Clay-sync open question

Resolved from file survey alone. Key findings:
1. `plugin-clay/skills/clay-sync/` does not exist (never existed).
2. No other workflow or skill dispatches `clay-sync.json` programmatically (grep across plugin-clay returned only the workflow itself + one prose reference in `create-repo/SKILL.md:165` + one in `clay-list/SKILL.md:40`, both just narrative).
3. The workflow is user-invoked via `wheel:run clay-sync` only.

Decision landed in Table 2: rename to `sync.json`, update the `"name"` field, do NOT create a new owning skill (out of scope per FR-009 rename-only rule). User invokes via `wheel:run clay:sync`.

This matches PRD option (a) "orphaned workflow → delete it" in spirit but keeps it rather than deleting since it's functional and user-facing. Alternative (c) "create a new owning skill" was rejected as scope creep.

## Cross-reference hotspot coverage

Table 3 is comprehensive based on repo-wide grep. Scanned:
- Every plugin's SKILL.md and workflow JSON
- Plugin-kiln agents, bin, scaffold
- Plugin-wheel lib and hooks
- Plugin-trim templates
- Repo-root CLAUDE.md, tests/, workflows/, .shelf-sync.json, .claude/agents/

Most likely gaps are in `plugin-wheel/lib/*.sh` (hard to predict without reading each script) — flagged in TW5 as "audit each" rather than enumerated. Implementer grep will catch anything missed.

## One thing I would change about the PRD

The PRD's SC-001 grep pattern used `\b` word boundaries only for some terms (`shelf-sync\b`) but not for others. For consistency and to avoid false positives (e.g., `shelf-sync-v2` directory names under `specs/` matching `shelf-sync`), I rewrote the grep gate in `tasks.md` X6 to use explicit `:skill` prefixed patterns for the primary gate, plus a looser bare-name grep as a secondary pass. Either may fire on historical artifacts in `specs/`, which is why the spec's SC-001 and tasks.md X6 both enumerate exclusion directories.

## What would have blocked a purely-parallel implementation

Two cross-cutting concerns forced me to add Phase X (auditor-owned):
1. `CLAUDE.md` is a single file referencing skills from all five plugins. Splitting its edits across four parallel implementers would cause merge conflicts.
2. `plugin-kiln/agents/continuance.md` references skills across all plugins. Same problem.

Compromise: agent briefs stay in Phase K (since they live under plugin-kiln/), but CLAUDE.md + scaffold + top-level workflows + tests go to Phase X. This keeps plugin-internal work parallelizable while serializing the global edits.

## Task-count sanity check

- Phase K: 7 tasks, covers 2 deletions + 2 workflow renames + kiln-wide cross-ref updates.
- Phase C: 5 tasks, 1 rename + 1 rename + 1 workflow rename + cross-refs.
- Phase S: 6 tasks, 7 skill renames + 3 workflow renames + cross-refs.
- Phase TW: 6 tasks, 17 skill renames + 8 workflow renames + cross-refs.
- Phase X: 8 tasks, 1 gate + 1 smoke test + global edits.

Phase TW is the heaviest; if the implementer wants to split to two people (one trim, one wheel), the tasks are already labeled by plugin.
