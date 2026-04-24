# audit-pr friction note — structured-roadmap pipeline

**Date**: 2026-04-24
**Agent**: audit-pr
**Task**: #5 — push branch + create PR with build-prd label

## What went smoothly
- `git push -u origin` worked first try; remote already existed and tracking was set cleanly.
- `gh pr create --label "build-prd"` accepted the label on first invocation — no label-missing error.
- audit-compliance's hand-off message was crisp and complete: it listed PRD coverage, FR compliance, schema invariants, test quality, smoke test result, blocker counts, and which gaps were fixed mid-audit. I had every number I needed to fill the PR template without re-reading the audit report end-to-end. I only needed to read `blockers.md` once to confirm the resolved/open split matched the summary.
- The PR template in my prompt was precise enough that body assembly was a single heredoc call; no back-and-forth.

## PR body assembly — notes for future audit-pr runs
- **Test coverage placeholder (`<Y>`)**: the template expects a single percentage. Reality was messier: FR-assertion coverage (95%) is measurable, but the constitutional bash line/branch coverage is **unmeasurable** because bashcov/kcov aren't installed (T063). I resolved this by filling the field with both: the measurable FR-assertion % + an explicit call-out that the bash metric is blocked. Future runs on Bash-heavy features should expect this same ambiguity and handle it the same way — do NOT paper over with a made-up number.
- **Dependency / Known blocker section**: the template assumed the `2026-04-23-write-issue-note-ignores-shelf-config` issue was still open and provided conditional language (`<If the blocker issue is still open>`). By the time I ran, audit-compliance had already confirmed it was RESOLVED via PR #146. I rewrote the section to lead with the resolution and call out the remaining T063 blocker as the only open item. The template's conditional hint was useful but the branching logic would be cleaner as explicit "if resolved / if still open" sub-templates rather than an inline placeholder.
- **Warning `1 uncommitted change`**: `gh pr create` flagged one uncommitted file. That file is `.claude/scheduled_tasks.lock`, which is a transient runtime artifact (comparable to `.version.lock`). It's not a PR-worthy change and was not introduced by this feature — it was already in the baseline `git status` snapshot when I started. Safe to ignore, but future audit-pr agents may want to confirm the uncommitted change is a known transient before proceeding.

## Missing info / friction from hand-off chain
- None blocking. audit-compliance's summary had every stat I needed. The only missing field was a single measured bash-coverage %, and that's a T063/tooling gap rather than a hand-off gap.
- Would have been mildly useful if audit-compliance had included the **PR labels** in their summary (e.g., "use `build-prd`") — I had it in my own prompt, but cross-checking against audit-compliance's recommendation would have been an extra signal. Minor.

## gh CLI friction
- None. `gh pr create --label "build-prd" --title ... --body "$(cat <<'PREOF' ... PREOF)"` worked on first try. Heredoc quoting with `PREOF` (vs `EOF`) was a good choice in the template — avoids collision with the `EOF` used inside the Test plan backticks.

## Suggestions for future audit-pr prompts
1. When the blocker-reconciliation changes the resolved/open split after the prompt is written, include explicit instruction: "If audit-compliance reports the shelf blocker as RESOLVED, lead the Dependency section with the resolution + PR #; otherwise use the conditional phrasing."
2. For Bash-heavy features, warn that `<Y>` test coverage may be unmeasurable and provide the fallback phrasing ("unmeasured — T063 blocker") rather than expecting a number.
3. Consider pre-staging the PR body as a file in `specs/<feature>/pr-body.md` so that copy-paste recovery is possible if `gh pr create` fails mid-invocation. Not needed this run (first-try success), but a cheap safety net for long bodies.

## Outcome
- Branch pushed: ✓
- PR created: https://github.com/yoshisada/ai-repo-template/pull/153 with `build-prd` label
- Friction note written: ✓ (this file)
- Task #5 marked completed: pending this write
- team-lead notified: pending this write
