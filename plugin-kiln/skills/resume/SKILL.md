---
name: "resume"
description: "Deprecated — use /next instead. Runs /next with a deprecation notice."
---

# Resume (Deprecated)

<!-- FR-010: /resume continues to function as deprecated alias that invokes /next -->

**This skill has been replaced by `/next`.** It is kept as a deprecated alias for backward compatibility.

```text
$ARGUMENTS
```

## Deprecation Notice

Print this notice before proceeding:

```
Note: `/resume` has been replaced by `/next`. Please use `/next` going forward.
`/resume` will continue to work but may be removed in a future version.
```

## Execute /next

After printing the deprecation notice, execute the full `/next` workflow with no additional flags.

Specifically, perform all of the following steps from `/next`:

1. **Read project context** — VERSION, branch, constitution
2. **Gather state from all local sources** — tasks, blockers, retrospectives, QA reports, backlog issues, unimplemented FRs
3. **Gather state from GitHub sources** — issues and PR comments (skip gracefully if `gh` unavailable)
4. **Classify and prioritize** — blocker/incomplete/qa-audit/backlog/improvement with critical/high/medium/low priorities
5. **Map to kiln commands** — every recommendation gets a concrete command
6. **Output terminal summary** — max 15 items grouped by priority
7. **Save persistent report** — to `.kiln/logs/next-<timestamp>.md`
8. **Create backlog issues** — for untracked gaps in `.kiln/issues/`

The output is identical to `/next` — the only difference is the deprecation notice at the top.
