---
id: 2026-04-23-all-agents-should-live-in
title: Centralize agent definitions with dynamic path-based resolution (not locked to wheel workflows)
type: feedback
date: 2026-04-23
status: prd-created
severity: high
area: architecture
repo: https://github.com/yoshisada/ai-repo-template
prd: docs/features/2026-04-24-wheel-as-runtime/PRD.md
---

all agents should live in plugin-wheel, not scattered across kiln/shelf/trim/etc. kiln (and other plugins) will always depend on wheel since wheel is the dispatch engine — so centralizing agent definitions in wheel gives a single portable contract. Generic role archetypes (reconciler, writer, researcher, auditor) as well as domain-specific ones (qa-engineer, debugger, smoke-tester, prd-auditor) all belong in wheel. Also: workflow agent-step spawns currently hardcode subagent_type=general-purpose, which loads the full generic system prompt + tool set for every step — a waste of context/latency when a specialized agent would fit.

## Clarification (2026-04-24) — resolution must be dynamic, not locked to wheel-workflow declarations

Agents should be **first-class, path-addressable resources**, not a registry that only wheel workflows can read from. Any caller — a wheel step, a kiln skill spawning via the Agent tool, a shelf workflow, an ad-hoc `/kiln:kiln-fix` debug loop — should be able to pass a full path (or a resolvable identifier) to the agent definition and get the correct `subagent_type` + system prompt wired in.

Concretely:

- **Path-addressable definitions**: every agent lives at a canonical path (e.g. `plugin-wheel/agents/reconciler.md`, `plugin-wheel/agents/qa-engineer.md`). Callers pass that path and get a resolved spawn.
- **No wheel-workflow monopoly on lookup**: the resolution logic — "given path-or-name, return the agent spec to attach to the Agent tool call" — must NOT live only inside the wheel workflow dispatcher. It should be a shared primitive that any plugin or skill can call.
- **Name aliases are a convenience layer on top of paths**: short names like `reconciler`, `qa-engineer` can resolve via a registry lookup, but the underlying mechanism is still path resolution. Unknown names fall through to "pass the string through as-is" so non-registered custom agents still work.
- **Agent definitions stay composable and discoverable**: consumer projects can ship their own agents (e.g. `my-project/.claude/agents/my-custom-agent.md`) and reference them by path from wheel workflows OR kiln skills, without the wheel workflow JSON being the only place that knows about them.
- **Backward compat**: existing `subagent_type: general-purpose` spawns continue to work during migration. The new path-based form is additive.

Why this matters: locking agent resolution to wheel workflow JSON means every caller that isn't a wheel workflow has to duplicate the spawn plumbing (as kiln skills currently do). A path-addressable shared primitive lets wheel, kiln, shelf, and future plugins all share the same spawn contract without being coupled to wheel's workflow engine.
