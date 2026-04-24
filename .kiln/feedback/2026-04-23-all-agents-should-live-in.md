---
id: 2026-04-23-all-agents-should-live-in
title: Centralize all agent definitions in plugin-wheel; workflows declare roles, wheel resolves
type: feedback
date: 2026-04-23
status: open
severity: high
area: architecture
repo: https://github.com/yoshisada/ai-repo-template
---

all agents should live in plugin-wheel, not scattered across kiln/shelf/trim/etc. kiln (and other plugins) will always depend on wheel since wheel is the dispatch engine — so centralizing agent definitions in wheel gives a single portable contract. Workflow steps declare a role/agent name; wheel resolves it; consumers don't have to ship per-plugin agent files. Generic role archetypes (reconciler, writer, researcher, auditor) as well as domain-specific ones (qa-engineer, debugger, smoke-tester, prd-auditor) all belong in wheel. Also: workflow agent-step spawns currently hardcode subagent_type=general-purpose, which loads the full generic system prompt + tool set for every step — a waste of context/latency when a specialized agent would fit.
