# Auditor Friction Notes — plugin-naming-consistency

## Grep gate results (SC-001)

**Final status: PASS** (after auditor's Phase X fixes).

### Actionable hits fixed by auditor
Phase X touched files the per-plugin implementers couldn't reach:

- `CLAUDE.md` — Quick Start line 19, architecture tree lines ~48–56, and Available Commands lines 187–201. Removed `/debug-diagnose`, `/debug-fix`, and `/create-repo` entries; rewrote architecture tree to drop `debug*/` and `create-repo/` entries.
- `.claude/agents/wheel-runner.md` — `/wheel:wheel-run` → `/wheel:run`, `/wheel-stop` → `/wheel:stop` in the agent brief's operating instructions.
- `tests/integration/caller-wiring.sh` — updated three `check_caller` invocations to new workflow names (`mistake`, `report-issue`, `sync`) + paths.
- `tests/integration/write-proposal.sh` — `/wheel-run` → `/wheel:run` in a comment.
- `tests/integration/hallucinated-current.sh`, `tests/integration/out-of-scope.sh`, `tests/unit/test-write-proposal-dispatch.sh` — output path strings updated from `shelf-full-sync-summary.md` to `sync-summary.md` to match the plugin-shelf rename.
- `plugin-shelf/scripts/derive-proposal-slug.sh` — comment mentioning `report-mistake-and-sync` → `kiln:mistake`.
- Top-level `workflows/` duplicates renamed in lockstep with plugin-shelf + plugin-kiln:
  - `shelf-full-sync.json` → `sync.json` (plus `"name"` field + internal output-path references)
  - `shelf-create.json` → `create.json`
  - `shelf-repair.json` → `repair.json` (plus `"name"` + three output-path references)
  - `report-issue-and-sync.json` → `report-issue.json` (plus `"name"` + nested `workflow: shelf:shelf-full-sync` → `shelf:sync`)
  - `workflows/tests/shelf-full-sync.json` → `workflows/tests/sync.json` (plus `"name"` + output path)

### False positives caught by the gate
The gate's `wheel-run` token matches both the renamed `wheel:wheel-run` skill AND the agent-type name `wheel-runner` (which is NOT a renamed skill — agents are a separate namespace). One line in `tests/test-team-wait-agent-capture.sh:64` and the frontmatter in `.claude/agents/wheel-runner.md:2` both hit this. Neither is a rename target. If the gate is re-run by anyone, they must exclude `wheel-runner` explicitly.

### Explicit out-of-scope hits still present
Per spec line 165 (Out of Scope) and Phase S tasks' explicit exclusions, these remain and are correct:

- `plugin-shelf/docs/PRD.md` — historical PRD of the shelf plugin itself. Spec line 171: "Fixing the `docs/PRD.md` placeholder" is Out of Scope.
- `plugin-shelf/scripts/*.sh` comments referencing `specs/shelf-sync-efficiency/contracts/interfaces.md` — historical spec paths; out of scope (spec line 151).
- `plugin-shelf/scripts/read-sync-manifest.sh` + `update-sync-manifest.sh` — references to `.shelf-sync.json` as a **data file** at repo root, not a skill/workflow name. The regex `shelf-sync\b` catches these incidentally.
- `plugin-shelf/skills/sync/SKILL.md:174` — historical feature slug `shelf-sync-v2` in an example string (`docs/features/2026-04-03-shelf-sync-v2/PRD.md`). Historical artifact, not a skill rename target.
- `.shelf-sync.json` — runtime data file; slugs inside are GitHub issue/doc slugs, not skill names.
- `.claude/settings.local.json` — gitignored local permissions file with version-pinned plugin cache paths from an old install. Will age out as the local cache refreshes.

## Rename tables in `contracts/interfaces.md`

The rename tables were largely complete — Phase K/C/S/TW implementers followed them cleanly and each recorded friction notes about minor gaps (e.g. shelf `plugin.json` having no `workflows` array, trim `plugin.json` same). The tables did NOT capture the top-level `workflows/` duplicates explicitly enough — implementers treated these as auditor-owned (Phase X3), which was correct per the partitioning but made the grep gate's first run noisy.

One gap worth noting for future pipelines: the rename tables call out `CLAUDE.md` as an auditor responsibility but don't break it down by line; the auditor had to re-read to find each reference. The spec did enumerate specific line numbers (lines 34–44 of spec.md) which helped.

## Smoke test (SC-002, SC-003, SC-005)

**File-presence smoke: PASS**
- All renamed skill dirs exist with correct frontmatter `name:` fields (verified: `shelf:sync`, `shelf:create`, `clay:new-product`, `trim:pull`, `wheel:run`).
- All old skill dirs are gone (`plugin-shelf/skills/shelf-*`, `plugin-clay/skills/create-prd`, `plugin-clay/skills/clay-list`, `plugin-kiln/skills/create-repo`, `plugin-kiln/skills/debug-diagnose`, `plugin-kiln/skills/debug-fix`, `plugin-trim/skills/trim-*`, `plugin-wheel/skills/wheel-*`).
- All renamed workflows exist: `plugin-shelf/workflows/sync.json`, `plugin-kiln/workflows/report-issue.json`, `plugin-kiln/workflows/mistake.json`, etc.
- All old workflow filenames are gone.

**End-to-end smoke (SC-003):** Not executed in this audit — requires a running wheel environment. The PR description flags this as manual verification post-merge.

## Blockers reconciliation

No `blockers.md` was created by any implementer — all four phases completed without blockers (verified from agent-notes files). No reconciliation needed.

## Recommendations for the retrospective
- The grep gate regex in SC-001 is usefully strict but catches the `wheel-runner` agent name as a false positive. Future renames that touch skill names should use more anchored regexes (e.g. `/wheel-run\b` to avoid `wheel-runner`).
- Partitioning by plugin worked well — four parallel implementers with disjoint file sets, no merge conflicts.
- The top-level `workflows/` duplicates are a latent hazard: identical content in two locations that drift independently. Consider a follow-up issue to either symlink them or delete the duplicates entirely.
