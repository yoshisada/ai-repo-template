---
id: 2026-04-25-fr-a1-wheel-agent-centralization-shipped-2026-04-24
title: "Reverse FR-A1 wheel-agent-centralization — wheel is dispatch infra; agents belong to their consumer plugins"
type: feedback
date: 2026-04-25
status: open
severity: high
area: architecture
repo: https://github.com/yoshisada/ai-repo-template
files:
  - plugin-wheel/scripts/agents/registry.json
  - plugin-wheel/scripts/agents/resolve.sh
  - plugin-wheel/tests/agent-reference-walker/run.sh
  - plugin-wheel/tests/agent-resolver/run.sh
  - specs/wheel-as-runtime/spec.md
  - docs/features/2026-04-24-wheel-as-runtime/PRD.md
  - .kiln/feedback/2026-04-23-all-agents-should-live-in.md
---

FR-A1 (wheel agent centralization, shipped 2026-04-24 in build/wheel-as-runtime-20260424) is architecturally wrong-headed and should be reversed. Wheel is dispatch infrastructure (hooks, state machines, agent-resolver primitive, per-step model selection, workflow JSON validation) — it should own NO agent definitions. Agent definitions are role/domain content that belongs to the plugin whose workflows consume them.

Empirical evidence collected during a 2026-04-24 session:

- All 10 centralized agents (continuance, debugger, prd-auditor, qa-engineer, qa-reporter, smoke-tester, spec-enforcer, test-runner, test-watcher, ux-evaluator) live at plugin-wheel/agents/<name>.md with symlinks at plugin-kiln/agents/<name>.md
- ZERO wheel workflows consume any of them. The only plugin-wheel/ references are: plugin-wheel/scripts/agents/registry.json (the resolver metadata) and 2 wheel-internal resolver tests. These are infrastructure backing the centralization itself, not actual consumers.
- All 10 are kiln-consumed: 6 kiln skills (kiln-build-prd, kiln-fix, kiln-next, kiln-qa-pass, kiln-qa-pipeline, kiln-ux-evaluate) reference these agents in skill prose.
- The four "generic role archetypes" the original 2026-04-23 feedback (.kiln/feedback/2026-04-23-all-agents-should-live-in.md) wanted to host alongside (reconciler, writer, researcher, auditor) — the agents that would actually have justified centralization with real cross-plugin sharing — were never authored. So the centralization moved files but never delivered the cross-plugin-shared layer that was supposed to be the payoff.

Architectural principle going forward:

- Wheel owns the *how-to-find-an-agent* logic (resolver primitive, registry format spec, namespace resolution)
- Each plugin owns its own agent definitions in plugin-<name>/agents/<role>.md
- "Cross-plugin shared archetypes" should NOT be pre-built in wheel. If genuine sharing emerges, file a separate plugin (e.g., plugin-roles) — but don't speculatively house archetypes in wheel.
- Same plugin can author multiple specialized agents that share a conceptual role (e.g. kiln:research-runner + kiln:fixture-synthesizer + kiln:output-quality-judge for the research-first phase). Conceptual sharing across plugins (kiln:reconciler vs shelf:reconciler) should be DIFFERENT files specialized per plugin's domain — not a single shared file.

Migration path (high-level — full plan to be specified in a follow-up PRD):

1. Move all 10 agents from plugin-wheel/agents/ back to plugin-kiln/agents/ (the actual consumer)
2. Delete plugin-kiln/agents/<name>.md symlinks (they were redirects from the centralization; no longer needed)
3. Delete plugin-wheel/agents/ directory (no agents = no directory)
4. Update plugin-wheel/scripts/agents/registry.json to reference new paths, OR delete it if the resolver can scan plugin-<name>/agents/ dynamically
5. Update plugin-wheel/scripts/agents/resolve.sh — drop the legacy plugin-kiln/agents/ comment, support plugin-<name>/agents/ as the canonical pattern across all plugins
6. Update wheel-internal resolver tests (plugin-wheel/tests/agent-reference-walker/, plugin-wheel/tests/agent-resolver/) to use new paths
7. Update CLAUDE.md "Recent Changes" entry for build/wheel-as-runtime-20260424 to note Theme A was reversed; FR-A1..A5 narrative in specs/wheel-as-runtime/spec.md should reflect that the centralization was reverted while the resolver primitive (FR-A3, FR-A4, FR-A5) is preserved.
8. Authoring future agents follows the new principle: plugin-<name>/agents/<role>.md, registers as <plugin>:<role>, no symlinks.

Notable: the resolver primitive (FR-A3..A5) is still valuable — it works whether agents live in wheel or in their owning plugins. Only FR-A1 (canonical-path-in-wheel) and FR-A2 (atomic migration TO wheel) are wrong-headed and should be reversed. The rest of build/wheel-as-runtime-20260424 (Themes B, C, D, E) is unaffected.

This is a strategic-direction concern, not a tactical bug. Filed via /kiln:kiln-feedback so it can be picked up by /kiln:kiln-distill into a properly-scoped reversal PRD when the queue allows.
