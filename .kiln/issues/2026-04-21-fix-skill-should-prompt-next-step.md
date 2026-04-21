---
type: issue
date: 2026-04-21
status: open
priority: medium
repo: https://github.com/yoshisada/ai-repo-template
tags: [skill-ux, kiln-fix]
---

# `/kiln:fix` should prompt "what's next" after completion

## Description

The last step of `/kiln:fix` currently ends with a report (Step 5 for success, Step 6 for escalation, Step 7 for recording). After the report, control returns to the user with no suggested next action.

For parity with `/kiln:next` (which always ends with a "Suggested next" line) and for smoother session flow, `/kiln:fix` should close with a prompt that suggests what to do next — e.g., run the relevant smoke test, trigger `/kiln:next` for the full backlog view, open the PR, or explicitly say "nothing urgent — you're done."

## Why this matters

After a fix lands, the user is often at a natural decision point (ship? test more? move to next task?). Without a nudge, they either forget to verify or lose context while hunting for what to do. A one-line prompt at the bottom of the fix report closes that gap — same pattern `/kiln:next` uses.

## Suggested implementation

At the end of `plugin-kiln/skills/fix/SKILL.md` — after the Step 7 "Record the Fix" report — add a Step 8 or append to Step 7.10:

```
> **What's next?** Options:
> - `/kiln:next` — see prioritized backlog
> - `/qa-final` — run E2E gate (if UI was touched)
> - Review the diff and ship the PR
> - `/kiln:report-issue <description>` — log follow-up friction
```

Or dynamically: if the fix was a UI fix, suggest `/qa-final`; if other fixes remain in the backlog, suggest `/kiln:next`; if escalated, suggest `/kiln:report-issue` or spec update.

## Source

User observation during `/kiln:build-prd plugin-naming-consistency` session, 2026-04-21, after prior `/kiln:fix` runs (T015 vault write + fix-skill record cycle).
