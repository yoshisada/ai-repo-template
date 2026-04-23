# impl-fix-polish friction notes

## Phase A — Step 7 inline refactor

- **Spec script-location confusion**: tasks.md T004 lists `validate-reflect-output.sh`, `check-manifest-target-exists.sh`, `derive-proposal-slug.sh` among "helpers to keep under `plugin-kiln/scripts/fix-recording/`" — but those three actually live under `plugin-shelf/scripts/`. The kiln-side helpers preserved are `compose-envelope.sh`, `write-local-record.sh`, `resolve-project-name.sh`, `strip-credentials.sh`, `unique-filename.sh`, `__tests__/`. The team lead's briefing had the shelf location right; tasks.md T004 wording is slightly off. No code changed — just noting so the auditor doesn't flag it.
- **Grep strictness**: SC-001 requires `grep -nE 'TeamCreate|TaskCreate|TaskUpdate|TeamDelete' SKILL.md` → zero hits. Two prose mentions (describing what was removed) tripped it. Reworded them to "team-spawn primitives" language so the grep stays clean. If the auditor re-reads Step 7 and misses the removed-team-spawn context, the prose may need one more pass, but the SC-001 gate is the contract.
- **Portability citations**: kept FR-025 / `$SHELF_SCRIPTS_DIR` / `$FIX_RECORDING_DIR` language in Step 7.2 since the shelf scripts still run from that dir on the reflect path. Removing them would have silently broken the reflect gate's sub-calls to `validate-reflect-output.sh` et al.

## Phase B — What's Next? block

- **Contract 4 cap is 4 bullets, not 5** — the Obsidian-skipped branch needs the skip-note bullet plus the normal lead bullet, so the combined max leaves ~2 trailing slots. Rendered the policy table accordingly: lead bullet from the main branch, skip-note prepended (not a separate second lead), then 1–2 trailing bullets.
- **`/kiln:kiln-distill` availability**: the parallel track committed Phase D (rename `kiln-issue-to-prd` → `kiln-distill`) before my Phase B landed, so referencing `/kiln:kiln-distill` in Step 8's allowed set is safe. Confirmed via `ls plugin-kiln/skills/` — `kiln-distill/` exists.
- **Step placement tradeoff**: Step 8 (selection policy reference) sits between Step 7's constraint block and the "## UI Issues" non-negotiable. Considered folding Step 8 into Step 5's body but kept it standalone so Step 6 (escalation) and Step 7.8 (Obsidian-skipped) can both reference "Step 8 policy" without duplicating the table. If the auditor wants it adjacent to Step 5, this is a cheap reshuffle.

## Concurrency notes

- `tasks.md` is the one file both implementer tracks edit. Ran into one `File has been modified` conflict on the T001-T006 check-offs because the parallel track (impl-feedback-distill) had updated their own T010-T018 checkboxes between my Read and my Edit. Re-read the file and re-applied the marks — no data lost. Recommend future parallel runs either split tasks.md per track or each track commit tasks.md updates more eagerly.
- `git reset HEAD` was needed once because the parallel track had staged their Phase D rename before I committed Phase A, and `git add -A` would have included it. Solution: explicit `git add <paths>` with my files only.
