# Friction Note — audit-pr

**Track**: audit-pr (TaskList #6)
**Branch**: `build/wheel-step-input-output-schema-20260425`
**PR**: #166 (https://github.com/yoshisada/ai-repo-template/pull/166)
**Author**: audit-pr

## Summary — Complete

PR #166 created with `build-prd` label. All three steps in my prompt executed:

1. **Smoke test** — completed via the structural fixture `kiln-report-issue-inputs-resolved` (21/21 PASS). Direct live `/kiln:kiln-report-issue` end-to-end run was not driveable from sub-agent context per B-3 in `blockers.md` (wheel hooks bind to the user's primary session); same wall audit-compliance hit. The team-lead's prompt allows "run an inline smoke yourself" and I judged the structural fixture + audit-compliance's perf substrate (N=5 alternating before/after `claude --print` subprocesses) jointly satisfy what the smoke is meant to assert. Documented this honestly in the PR body's headline-metric section as a final user-driven smoke that remains as an unchecked box on the test plan checklist.
2. **Step 4b lifecycle archival** — both PRD `derived_from:` entries processed. Diagnostic line appended to `.kiln/logs/build-prd-step4b-2026-04-25.md` (the file pre-existed from an earlier build-prd run for a different PRD; appended a new line rather than overwriting).
3. **PR creation** — `gh pr create --label build-prd` succeeded with the headline-metric block populated from `audit-perf-results.tsv` (post-PRD medians from audit-compliance) and the SC-G-1(b) anchor from `kiln-report-issue-inputs-resolved` case 14.

## Friction observed

### F-1 — `pr: #<NUMBER>` ordering chicken-and-egg in Step 4b
**Surface**: team-lead's prompt Step 2 says "rewrite frontmatter (..., `pr: #<PR_NUMBER>`)" but Step 3 is "Create the PR." The PR number isn't known until Step 3 runs, but the natural reading of the prompt is "do Step 2 before Step 3 so the lifecycle archival is part of the PR." I resolved this by reordering: Step 3 first (push branch, create PR, get number), then Step 2 (archival with the number), then a follow-up commit. Recommend the team-lead prompt explicitly call out the ordering: either "do Step 2 before Step 3 with `pr: #<TBD>` and amend later" or "do Step 3 first to get the PR number, then Step 2 as a follow-up commit on the same branch."

### F-2 — `.kiln/mistakes/` has no archival convention; team-lead prompt acknowledges but reader has to handle
**Surface**: team-lead's prompt: "`.kiln/mistakes/` doesn't have a standard archival convention — handle it by writing the same status update in-place (no `mv`)". This is correctly defensive, but it's the second prompt I've seen that calls out this asymmetry — symptom that `.kiln/mistakes/` either should grow a `completed/` convention OR `derived_from:` consumers should branch on source-directory. Filed earlier mistake (`2026-04-25-assumed-component-fixtures-equal-end-to-end-coverage.md`) was promoted to a roadmap item per audit-compliance's blockers.md; not re-filing.

### F-3 — `status: completed` overwrites `status: verified` / `status: fixed` semantics
**Surface**: the issue I archived had `status: verified` (a smoke-test-result; it's saying "the cross-plugin-resolver fix is empirically verified live"). The mistake had `status: fixed` (saying "the wrong assumption has been corrected"). Step 4b says to set `status: completed` for both — but `completed` doesn't preserve the kind-specific verb. A consumer reading the issue/mistake-note schema later might not know which "completed" means. Recommend Step 4b either preserve the prior status as `prior_status:` or use a kind-specific enum (`archived: true` is more neutral). Not blocking — just a schema-cleanliness observation.

### F-4 — uncommitted side-effects from audit-compliance's stalled run remained on the working tree
**Surface**: when I started, `git status` showed:
- modified: `.kiln/roadmap/phases/90-queued.md`
- deleted: `.wheel/outputs/create-issue-result.md`
- untracked: 2 roadmap items (`2026-04-25-wheel-spawn-topology-linter.md`, `2026-04-25-wheel-verify-tool.md`), 1 stopped state file from the B-3 stalled `/kiln:kiln-report-issue` attempt

These are audit-compliance's side-effects (the stalled run + the follow-on roadmap items they filed). They're orthogonal to PR #166's scope. I left them alone (didn't stage, didn't revert) because (a) the roadmap items are tracked work that should land separately and (b) reverting/cleaning would be presumptuous. **`gh pr create` warned "5 uncommitted changes"** — that warning was correctly ignored, but it would be cleaner if the prior teammate cleaned up their working tree before signaling completion. Recommendation for team-lead: add "leave the working tree clean before marking your task done" to the audit-compliance prompt.

### F-5 — B-3 (live-smoke not driveable from sub-agent context) is a load-bearing limitation
**Surface**: B-3 in `blockers.md`. This affects every teammate after impl-* in the build-prd pipeline that needs to drive a real wheel workflow end-to-end. audit-compliance hit it; I hit it. Both of us worked around it via the structural fixture + perf substrate — but neither of us can produce the canonical `dispatch-background-sync.command_log == 0` evidence that the auditor's recommendation in their handoff message specifies. The unchecked box at the bottom of the PR's test plan is the visible artifact of this gap. **Recommendation** (already filed in B-3): make wheel hooks sub-agent-driveable for testing, OR document this in the audit-compliance + audit-pr teammate prompts so future runs don't re-discover it. A structural fixture + perf substrate IS sound evidence for the gate — but the prompt language "run the migrated `/kiln:kiln-report-issue` end-to-end" should be revised to acknowledge the substrate substitution as canonical.

## Suggestions for the retrospective (TaskList #7)

- (F-1) Step 4b ordering should be explicit in the team-lead prompt template.
- (F-3) `status: completed` schema convention deserves a roadmap item (preserve prior status, or rename to `archived: true`).
- (F-4) Add a "leave working tree clean" closing rule to all teammate prompts.
- (F-5) B-3 (sub-agent live-smoke wall) is a structural pipeline limitation that surfaced twice in one run; either fix wheel or codify the workaround in teammate prompts.

## Cited artifacts

- PR: https://github.com/yoshisada/ai-repo-template/pull/166
- Step 4b diagnostic: `.kiln/logs/build-prd-step4b-2026-04-25.md` (line 2)
- Smoke fixture verdict: `.kiln/logs/kiln-test-kiln-report-issue-inputs-resolved-2026-04-25T07-56-56Z.log`
- Live perf data: `specs/wheel-step-input-output-schema/audit-perf-results.tsv` + `audit-perf-driver.out`
