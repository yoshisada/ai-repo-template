---
name: "kiln-resume"
description: "Deprecated — use /kiln:kiln-next instead. Runs /kiln:kiln-next with a deprecation notice."
---

# Resume (Deprecated)

<!-- FR-010: /kiln:kiln-resume continues to function as deprecated alias that invokes /kiln:kiln-next -->

**This skill has been replaced by `/kiln:kiln-next`.** It is kept as a deprecated alias for backward compatibility.

```text
$ARGUMENTS
```

## Deprecation Notice

Print this notice before proceeding:

```
Note: `/kiln:kiln-resume` has been replaced by `/kiln:kiln-next`. Please use `/kiln:kiln-next` going forward.
`/kiln:kiln-resume` will continue to work but may be removed in a future version.
```

## Execute /kiln:kiln-next

After printing the deprecation notice, execute the full `/kiln:kiln-next` workflow with no additional flags.

Specifically, perform all of the following steps from `/kiln:kiln-next`:

1. **Read project context** — VERSION, branch, constitution
2. **Gather state from all local sources** — tasks, blockers, retrospectives, QA reports, backlog issues, unimplemented FRs
3. **Gather state from GitHub sources** — issues and PR comments (skip gracefully if `gh` unavailable)
4. **Classify and prioritize** — blocker/incomplete/qa-audit/backlog/improvement with critical/high/medium/low priorities
5. **Map to kiln commands** — every recommendation gets a concrete command
6. **Output terminal summary** — max 15 items grouped by priority
7. **Save persistent report** — to `.kiln/logs/next-<timestamp>.md`
8. **Create backlog issues** — for untracked gaps in `.kiln/issues/`

The output is identical to `/kiln:kiln-next` — the only difference is the deprecation notice at the top.
