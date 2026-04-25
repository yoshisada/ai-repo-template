---
title: Pipeline-bypass loophole — require-spec hook only gates src/ edits, plugin source repos go unguarded
date: 2026-04-25
status: open
kind: bug
priority: medium
repo: https://github.com/yoshisada/ai-repo-template
tags:
  - hooks
  - workflow
  - governance
  - kiln
  - constitution
source: kiln-report-issue
files:
  - plugin-kiln/hooks/require-spec.sh
  - .claude/settings.json
  - scripts/compile-agents.sh
---

# Pipeline-bypass loophole — require-spec hook only gates src/ edits, plugin source repos go unguarded

## Description

The `require-spec.sh` hook (Constitution Article IV) physically blocks
`src/` edits without a spec/plan/tasks/[X] gate. But this repo — the
plugin source repo for `@yoshisada/kiln` — has no `src/` directory.
All plugin code lives under `plugin-*/`. So when an assistant or
contributor edits `plugin-kiln/scripts/`, `plugin-wheel/lib/`, or
`.claude/settings.json` here, **no hook fires**. The 4-gate workflow
exists in spirit but is structurally bypassed.

## Concrete instance

In the 2026-04-25 conversation, the assistant:

1. Filed roadmap item `2026-04-25-agent-prompt-includes` via
   `/kiln:kiln-roadmap`.
2. In the same turn, wrote `scripts/compile-agents.sh` (~80 lines)
   and added a PostToolUse hook to `.claude/settings.json` — a
   substantive code change implementing v1 of the just-filed roadmap
   item.
3. No spec at `specs/agent-prompt-includes/`, no
   `contracts/interfaces.md`, no plan.md, no tasks.md, no
   implementation tasks marked `[X]`.
4. On branch `build/wheel-test-runner-extraction-20260425` — an
   unrelated feature branch.

Constitution Articles I (Spec-First, NON-NEGOTIABLE) and VII
(Interface Contracts, NON-NEGOTIABLE) were violated. No hook
intervened because the matcher path is `src/**` and this repo's
plugin code lives under `plugin-*/`.

## Why this matters

The plugin source repo is exactly where pipeline discipline should be
strictest — these scripts ship to consumers. A loophole that lets
any contributor (human or AI) bypass spec-first development on the
plugin itself defeats the whole point of the constitution.

## Proposed fixes

Either is sufficient; together they're belt + suspenders.

### Fix 1 — Extend `require-spec.sh` matcher for plugin source repos

When the working directory contains a `.claude-plugin/` directory at
the top level (i.e., this IS a plugin source repo), extend the
matcher to also gate:

- `plugin-*/scripts/**`
- `plugin-*/hooks/**`
- `plugin-*/bin/**`
- `plugin-*/lib/**`
- `.claude/settings.json` (and `.claude/hooks/**`)

Skip the gate for `plugin-*/agents/**`, `plugin-*/skills/**`,
`plugin-*/templates/**` since those are markdown/config-style edits
that often happen during /implement steps.

### Fix 2 — Instruction-time guardrail (assistant behavior)

After the assistant invokes `/kiln:kiln-roadmap` (filing or updating
a roadmap item), the next legal step in the same turn is one of:

- Another `/kiln:kiln-roadmap` invocation (filing more items)
- `/kiln:kiln-distill` (bundle into PRD)
- `/kiln:kiln-report-issue` / `/kiln:kiln-feedback` (capture only)
- Direct human input

The assistant SHOULD NOT implement code that satisfies the
just-filed roadmap item in the same turn. Could be enforced via a
CLAUDE.md rule + a soft Stop-hook reminder when both
`Skill(kiln:kiln-roadmap)` and `Edit/Write` of `plugin-*/scripts/**`
or `.claude/settings.json` happen in the same turn.

## Acceptance signal

Running this exact scenario after the fix:

1. Assistant calls `/kiln:kiln-roadmap` and files an item.
2. Assistant tries to `Edit` `scripts/foo.sh` to implement that item.
3. The hook (Fix 1) blocks the edit with a message naming the
   missing spec/plan/tasks artifacts AND/OR the assistant
   self-checks (Fix 2) and stops.

Today: edit succeeds silently. Desired: edit blocks with a clear
diagnostic.
