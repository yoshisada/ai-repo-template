---
name: kiln-improve
description: Run the self-improvement loop. Collects unclassified improvement proposals from the ledger and latest retro, auto-applies low-risk config patches (L1 — .kiln/config.json, .kiln/standards.md, .kiln/test-strategy.json), and surfaces high-risk proposals (hooks, skills, agents, workflows) as text for human review (L2). Supersedes kiln-pi-apply (which now redirects here).
---

# Kiln Improve — Self-Improvement Loop

Closes the build-friction loop by:
- **Collecting** unclassified proposals from `.kiln/ledger/proposals/` and the latest retro
- **Classifying** each as LOW (config-only) or HIGH (hook/skill/agent/workflow) risk
- **Applying** LOW proposals targeting `.kiln/` config files automatically (L1 patch + commit)
- **Surfacing** HIGH proposals and LOW proposals targeting skill/agent files as text for your review (L2)
- **Syncing** ledger entries to Obsidian (best-effort)

```text
$ARGUMENTS
```

V1 accepts no arguments. A `--since <date>` filter and a `--dry-run` mode are planned follow-ons.

## Delegate to Wheel

```
/wheel:wheel-run kiln:kiln-self-improve
```
