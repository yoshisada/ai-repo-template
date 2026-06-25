---
name: kiln-pi-apply
description: Redirect to kiln-self-improve workflow. Collects unclassified improvement proposals from the ledger and latest retro, auto-applies low-risk config patches (L1), and surfaces high-risk skill/hook/workflow proposals as text for human review (L2). Renamed to kiln-improve — this skill stays as a redirect alias.
---

# Kiln PI-Apply — Redirect to Self-Improve Workflow

> **Renamed.** This skill is now a redirect alias. The new preferred name is `/kiln:kiln-improve`.
> Both names run the same `kiln:kiln-self-improve` wheel workflow.

The self-improve workflow replaces the old manual "propose-only" approach:
- **L1 (auto-apply):** Low-risk proposals targeting `.kiln/config.json`, `.kiln/standards.md`, or `.kiln/test-strategy.json` are applied and committed automatically.
- **L2 (surface for review):** High-risk proposals (hooks, skills, agents, workflows) and any low-risk proposals targeting skill/agent files are printed as text for human review.

```text
$ARGUMENTS
```

## Delegate to Wheel

```
/wheel:wheel-run kiln:kiln-self-improve
```
