# Agent Friction Notes: prd-auditor

**Feature**: structured-roadmap
**Date**: 2026-04-24

## What Was Confusing

- **Spec FR naming with sub-IDs**: FR-014a, FR-014b, FR-018a, FR-018b, FR-018c don't get a clean count in "43 FRs". The audit prompt says to check every FR but doesn't address sub-IDs. I counted them as separate requirements (correct) but had to decide that myself.

- **`blockers.md` format**: The prompt template uses markdown headers, but it was unclear whether blockers.md should be a YAML document or a markdown file. I chose markdown to match the spec artifact style. Would help to have a template in `specs/structured-roadmap/` or `plugin-kiln/templates/`.

- **Smoke test definition**: The prompt says "invoke the new `/kiln:kiln-roadmap` skill end-to-end in a temp directory fixture" but this is a markdown skill system that runs inside a Claude process — it's not a CLI binary I can shell out to. Actual smoke testing requires `/kiln:kiln-test plugin-kiln` with the real Claude CLI. I had to resolve this ambiguity by doing structural verification (test fixture files exist, test.yaml well-formed, assertions.sh exit codes correct) and documenting that live execution requires the harness.

- **`kiln-specify` naming vs `specify`**: The skill lives at `plugin-kiln/skills/specify/SKILL.md` not `kiln-specify`. The plan.md calls it `kiln-specify` and the team prompt uses both names. The SKILL.md grep had to fall back to the `specify/` path. Would be cleaner if the directory name matched the skill's invocation name.

## Where I Got Stuck

- **Waiting for tasks #2 and #3**: Both impl-roadmap and impl-integration were not completed when I spawned. I sent the blocking message immediately and waited. This is correct pipeline behavior but added ~30 minutes of wall-clock time. The wait was unproductive — I could have been reading the PRD and pre-loading context (which I did) but couldn't start the actual audit.

- **Finding kiln-specify**: `ls plugin-kiln/skills/ | grep -i spec` returned nothing because the skill is at `plugin-kiln/skills/specify/SKILL.md`. I tried `kiln-specify/` first. This wasted two tool calls.

- **FR-013 gap discovery**: The gap (missing explicit context-read step before classification) wasn't obvious until I carefully traced the SKILL.md execution flow step-by-step. The SKILL.md does read phases in Step 5 (for phase assignment) but NOT before Step 2 (classification). The fix I added (Step 1b) is correct but I wish the spec had a clearer note about where in the flow the context read must happen.

## What Could Be Improved

- **`/audit` skill should auto-create blockers.md template**: If `specs/<feature>/blockers.md` doesn't exist, the skill should scaffold it from a template (like `plan.md` and `spec.md` get templates). I had to hand-write the structure.

- **PRD auditor prompt should say "markdown skills are AI instructions, not shell scripts"**: The smoke-test section says "invoke the skill end-to-end" which implies shelling out. For markdown skills, that means running `/kiln:kiln-test` which requires the Claude CLI environment. The prompt should say: "for markdown skills, smoke test = structural verification of test fixtures + notation that live execution requires `/kiln:kiln-test plugin-kiln`."

- **Blocker reconciliation protocol is clear but verbose**: "For each: check git log + current file state. If resolved, update status." This is good. I found the blocker was RESOLVED by checking the issue file status (prd-created) and the fix commit in git log. The commit message even said "write-issue-note reads .shelf-config" which was the exact blocker description. Worked well.

- **`contracts/interfaces.md` should include key-order determinism from the start**: impl-roadmap documented FR-037 key order in SKILL.md Rules but not in contracts. The contract document is the single source of truth — if it's not there, implementers may not find it. This gap was easy to fix (I added §1.3a) but it would have been better if specifier had included it.

- **Test coverage gate for Bash is genuinely hard**: bashcov/kcov are not standard install on CI/macOS. The implementation team noted this and I agree it should either be a setup pre-req documented in `CLAUDE.md` or the gate should specify an alternative measurement approach. Consider adding `gem install bashcov` to a `Makefile` or `package.json` devDependency, or switching to a coverage-friendly approach like wrapping helpers in test harnesses that count line execution.

## What Worked Well

- **FR-comment discipline**: Both implementers put `# FR-NNN / PRD FR-NNN` comments at the top of every Bash helper and in every SKILL.md section. This made the Spec→Code check mechanical — grep for the FR ID, confirm it's present. Zero hunting required.

- **contracts/interfaces.md**: Extremely detailed. Every helper signature, every JSON output shape, every heuristic table. This was the most useful artifact for the audit. It gave me a ground truth to check the implementation against rather than just reading the spec prose.

- **Test fixture structure**: All 17 test directories have `test.yaml`, `assertions.sh`, and relevant `inputs/` + `fixtures/`. Assertions are real (grep on file contents, grep on frontmatter keys, side-effect checks). No stubs. The cross-surface routing test using "issue file appeared as side effect" is an elegant proxy for testing Skill-tool invocation from a bash script.

- **Blocker (FR-004) already resolved**: The shelf-config blocker was the load-bearing dependency for this feature. It was fixed in PR #146 before this pipeline ran, so roadmap sync can ship without a downstream wait. The issue file even had the exact right status (`prd-created`) to signal it was handled.
