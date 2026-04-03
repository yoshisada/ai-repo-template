---
title: "Hook gate enforcement is broken in 3 ways — scoping, chicken-and-egg, allowlist"
type: bug
severity: critical
category: hooks
source: analyze-issues
github_issue: "#26, #9, #15"
status: prd-created
date: 2026-04-01
---

## Description

The PreToolUse hook gates have three distinct failures:

### 1. Gates match wrong spec (CRITICAL)
Gates use `specs/*/spec.md` glob — any prior feature's spec satisfies the gate, not just the current feature's. In #26, specs from the previous feature (`headless-settings-page`) satisfied the gate, allowing implementers to commit code before the current feature's spec was even finalized. The entire hook-based enforcement of specify-before-implement was silently bypassed.

### 2. Gate 4 chicken-and-egg
Gate 4 blocks all writes until tasks.md has at least one `[X]` mark. But agents can't mark a task `[X]` without first writing the files that complete it. Workarounds: agents pre-mark tasks `[X]` before writing files, or use `Bash cat >` to bypass the Write tool hook entirely. Both are hacks that undermine the gate.

### 3. Allowlist doesn't match documented intent
The hook documentation says it blocks `src/` edits, but the actual implementation blocks everything not in a hardcoded allowlist (docs/, specs/, scripts/, .claude/, tests/). This blocks `cli/`, `templates/`, and `modules/` — none of which are `src/`. The allowlist doesn't match the documented behavior.

## Impact

Critical — the spec-first workflow enforcement, which is the core value proposition of kiln's hooks, can be silently bypassed. Multiple agents in multiple runs resorted to workarounds.

## Suggested Fix

1. **Scope gates to current feature**: Check `specs/<current-feature>/spec.md` where `<current-feature>` is derived from the branch name or a `.kiln/current-feature` file
2. **Fix Gate 4**: Allow writes when running inside `/implement` without requiring a pre-marked `[X]`. Options: add an `implementing.lock` file, or trust the implement skill context
3. **Fix allowlist**: Only block `src/` as documented, not everything-except-allowlist. Or expand the allowlist to include `cli/`, `templates/`, `modules/`, and other common non-src directories
4. **Enforce contracts**: Add a gate check that verifies `contracts/interfaces.md` exists (#15)

## Source Retrospectives

- #26: CRITICAL — hook gate matched prior feature's spec
- #9: Gate 4 chicken-and-egg reported by 2 agents; allowlist too narrow reported by 2 agents
- #15: contracts/interfaces.md not enforced in gates

prd: docs/features/2026-04-01-pipeline-reliability/PRD.md
