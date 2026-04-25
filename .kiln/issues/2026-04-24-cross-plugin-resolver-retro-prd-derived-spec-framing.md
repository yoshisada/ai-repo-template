---
status: open
source: retrospective
prd: cross-plugin-resolver-and-preflight-registry
priority: low
suggested_command: /kiln:kiln-fix
tags: [retro, prompt, /specify, build-prd, prd-derived]
---

# `/specify` framing assumes vague-description input; build-prd should detect "PRD-thorough" mode and short-circuit the interactive framing

**Date**: 2026-04-24
**Source**: cross-plugin-resolver retrospective; specifier friction note §"PRD vs spec scope overlap"

## Description

The PRD for this feature contained a complete Solution Architecture, full FR text, full NFR text, full test surface, and an ASCII runtime diagram. The /specify skill is framed as "create user stories from a vague description" — for this PRD, the specifier's actual job was a thin transformation: re-shape PRD content into spec-section conventions (G/W/T acceptance, success criteria) and resolve OQ-F-1 in research.md. The interactive "user stories first" framing didn't fit the input shape.

The specifier worked around this by interpreting the team-lead's chaining mandate as "produce the artifacts, by any means necessary" and saving cycles by writing artifacts directly. That worked, but the build-prd skill doesn't currently distinguish "PRD-thorough" inputs from "vague-description" inputs.

## Proposed prompt rewrite

**File**: `plugin-kiln/skills/kiln-build-prd/SKILL.md` (specifier-step prompt construction)

**Current**: Specifier prompt is identical regardless of PRD shape.

**Proposed**: Add a heuristic to build-prd that detects "PRD-thorough" inputs and adjusts the specifier prompt accordingly:

```markdown
> **PRD-thoroughness detection**: before spawning the specifier, scan the
> PRD for these markers:
>   - explicit "Solution Architecture" section ≥ 200 words, OR
>   - ≥ 5 numbered FRs with prose ≥ 50 words each, OR
>   - explicit "Test Surface" section listing fixture names.
>
> If ≥ 2 markers fire, prepend the specifier prompt with:
>
>     > **PRD-thorough mode**: this PRD already specifies architecture,
>     > FRs, NFRs, and test surface. Your job is the THIN transformation:
>     > (a) decompose FRs into G/W/T-shaped acceptance criteria, (b)
>     > resolve any BLOCKING open questions in research.md, (c) record
>     > exact bash-level interface signatures in contracts/interfaces.md.
>     > Do NOT re-invent scope. Do NOT add user stories the PRD didn't
>     > imply. The user-story / acceptance-scenario format is a PRESENTATION
>     > of the PRD's intent, not an opportunity to expand it.
>
> Otherwise, use the standard "vague description → user stories" framing.
```

**Why**: Without the heuristic, every PRD-thorough run depends on the specifier independently noticing the input shape and adapting. The specifier here did so successfully but flagged the friction explicitly. Codifying the detection pre-empts the next specifier's discovery cycle.

## Forwarding action

- Implement the heuristic in `plugin-kiln/skills/kiln-build-prd/SKILL.md`.
- Optional: extend the PRD template to declare `prd_thoroughness: thorough | sketch` in frontmatter, removing the heuristic in favor of an explicit author signal.
