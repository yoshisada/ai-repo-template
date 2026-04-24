# audit-pr friction notes — wheel-user-input

**Agent:** audit-pr (Task #4)
**Branch:** build/wheel-user-input-20260424 → main
**PR:** https://github.com/yoshisada/ai-repo-template/pull/155

## What went well

- Clean hand-off from audit-compliance: the teammate message contained every stat the PR body asked for (PRD %, test coverage, blocker counts, smoke 6/6, invariant proof), so filling the template was mechanical — no chasing numbers across files.
- The task-blocking graph (my #4 blocked by #3) meant I correctly idled on ScheduleWakeup rather than polling, and woke up once audit-compliance actually messaged me.
- `git push -u origin …` + `gh pr create --label build-prd` worked first try; label was accepted without needing to be pre-created.

## Friction

1. **Staged-but-uncommitted VERSION bumps on entry.** When I started, `git status` showed staged modifications to `VERSION` and all five `plugin-*/package.json` / `plugin.json` files — artifacts of the version-increment hook firing during the implementer/auditor edit phases. The prior agents never committed them, so I had to decide on the fly whether to:
   - (a) commit them as part of this feature (chose this — they're semantically "edits from this feature's file writes")
   - (b) push without them (would leave an awkward dirty tree on the branch)
   - (c) reset them (would make the `VERSION` file drift from what the hook expects)

   **Recommendation:** either (i) have the version-increment hook auto-commit its bumps immediately (separate commit per edit feels noisy, but would guarantee a clean tree), or (ii) add an explicit step to the implementer agent's brief that says "commit any staged VERSION/package.json bumps before handing off." As-is, every audit-pr teammate has to solve this ambiguity from scratch.

2. **`Warning: 5 uncommitted changes` from `gh pr create`.** After my version-bump commit, there were still untracked files on the branch (`.kiln/roadmap/`, `.kiln/vision.md`, `plugin-shelf/bin/`, `specs/wheel-user-input/agent-notes/audit-compliance.md`, plus `.kiln/roadmap.md` modified). These came from earlier-in-pipeline work that isn't strictly part of this feature's scope. `gh pr create` warns but doesn't block, and the PR goes up from what's on `origin/<branch>` — so the warning is cosmetic. Still, it's a signal the pipeline is leaving scratch artifacts behind.

   **Recommendation:** either the pipeline's final step should sweep untracked files into a `chore:` commit (if they belong with the feature) or `.gitignore` them (if they don't). Having audit-pr silently stand over a dirty tree makes it hard to tell whether something was forgotten.

3. **Tool-search overhead on wake-up.** Every autonomous-loop wake-up re-delivered the deferred-tools reminder and re-triggered ToolSearch for `TaskList`/`TaskUpdate`/`SendMessage`. Not expensive, but it's noise that wouldn't exist if the ScheduleWakeup re-entry preserved which tool schemas were already loaded.

## Template feedback

The PR body template in my task brief was excellent — structured invariants section, explicit out-of-scope callouts, test plan checklist. The only thing I'd add is a "Commits" bullet under Summary so reviewers see the phase-by-phase progression (phase 0 contracts → phase 7 docs) without having to click through git history.

## Time on task

~2 wake-up cycles (ScheduleWakeup 1200s + 1800s) mostly idle, then ~3 minutes of real work once audit-compliance's message arrived: verify tasks → commit VERSION → push → create PR → this note.
