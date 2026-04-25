---
id: 2026-04-23-wheel-as-plugin-agnostic-infra
title: "Move more plugins and kiln commands to wheel"
kind: goal
date: 2026-04-23
status: open
phase: 90-queued
state: planned
blast_radius: cross-cutting
review_cost: careful
context_cost: "multi-PRD initiative — 4 ordered children"
promoted_from: .kiln/feedback/2026-04-23-we-need-to-move-more-plugins.md
---

# Move more plugins and kiln commands to wheel

Promoted from [`.kiln/feedback/2026-04-23-we-need-to-move-more-plugins.md`](.kiln/feedback/2026-04-23-we-need-to-move-more-plugins.md) on 2026-04-23. Sharpened on 2026-04-25 with explicit destructuring + non-goals list.

## Principle

Wheel is plugin-agnostic infrastructure. Commands, mechanisms, and substrates that any plugin might want should live in wheel; surfaces that are tightly coupled to a specific plugin's domain stay in that plugin.

This is the sibling principle to the FR-A1 reversal (build/wheel-as-runtime-20260424, reversed in `320137e` + `aa7cb59`): same direction-of-travel ("wheel = infrastructure"), opposite mistake. FR-A1 moved plugin-specific content INTO wheel, which was wrong because it forced wheel to coordinate every plugin release. The right move is the opposite — extract genuine cross-cutting mechanisms OUT OF kiln so wheel becomes a thicker substrate that other plugins can build on without touching kiln.

## Destructured children (ordered by ascending blast radius)

Each child is its own roadmap item, depends on the listed predecessors, and addresses this parent. Build in order — the lower-blast extractions de-risk the higher-blast ones:

1. **`2026-04-25-wheel-test-runner-extraction`** (blast: isolated) — Move kiln-test runner core to wheel as façade pattern. Validates the "extract to wheel" pattern at minimum scope. No user-facing change.
2. **`2026-04-25-shell-test-substrate`** (blast: isolated) — Add `harness-type: shell-test` to the wheel-test-runner so `run.sh`-only fixtures become discoverable. Closes the recurring B-1 substrate gap from PRs #166 and #168 audits. Depends on #1.
3. **`2026-04-25-friction-note-primitive`** (blast: feature) — Extract FR-009 friction-note convention from `kiln-build-prd` SKILL.md prose into a wheel primitive any orchestrating skill can use. Independent of #1/#2.
4. **`2026-04-25-team-orchestration-primitive`** (blast: cross-cutting) — Extract `TaskCreate` + `addBlockedBy` + retrospective scaffolding from `kiln-build-prd` into a wheel teammate-orchestration primitive. Highest-blast, biggest payoff. Should ship LAST after #1-#3 prove the extraction pattern works. Depends on #1, #3.

## Non-goals (stays in kiln — DO NOT move speculatively)

These are kiln-specific surfaces tightly coupled to spec-first workflow / PRD lifecycle / `.kiln/` artifact ownership:

- `/specify`, `/plan`, `/tasks`, `/implement`, `/audit` — spec-first ceremony
- `/kiln:kiln-distill`, `/kiln:kiln-roadmap`, `/kiln:kiln-claude-audit`, `/kiln:kiln-feedback`, `/kiln:kiln-report-issue`, `/kiln:kiln-mistake` — kiln-specific surfaces (PRD lifecycle, retrospective bundling, `.kiln/` artifact ownership)
- `/kiln:kiln-fix` — already correctly inlined per FR-001/FR-005 (no team primitives, MCP-direct)
- `/kiln:kiln-doctor`, `/kiln:kiln-hygiene` — kiln-specific manifest schema + structural rubric

If genuine cross-plugin sharing emerges for any of these, file a separate plugin (e.g., `plugin-roles`) — but do NOT speculatively house them in wheel.

## Source

> we need to move more plugins to wheel. probably would be good to get more commands from kiln to wheel.

— `.kiln/feedback/2026-04-23-we-need-to-move-more-plugins.md`
