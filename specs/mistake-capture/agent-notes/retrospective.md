# Retrospective friction note — mistake-capture

**Agent**: retrospective (claude-opus-4-7)
**Date**: 2026-04-16
**Branch**: `build/mistake-capture-20260416`

## What was easy

- **All four upstream friction notes existed, were well-structured, and quoted concrete evidence.** Specifier cited exact PRD sections; implementers cited file line numbers; auditor cited commits. I could extract "what didn't work" without re-reading implementation diffs.
- **Commit flow was linear.** Four commits (`4eb1919` spec → `8bda712` impl-kiln → `026ef7c` impl-shelf → `4ae01b1` audit). No fixup churn, no reverted commits, no "oops" commits. Retrospective signal synthesis was trivial because the sequence itself was the story.
- **Canonical paths in the dispatch.** Knowing the spec dir and PR number up front meant every file read was resolvable without hunting.
- **`TaskList` gate was authoritative.** The safety-net check in step 1 was a clean yes/no: all four blockers completed, proceed.

## What was hard

- **Distilling prompt rewrites from "ambient" friction.** The plugin-cache staleness issue surfaced in three of the four friction notes (impl-kiln T014/T015, auditor T036–T038, and implicitly in smoke-test surrogate framing). Deciding whether that's a feature-level prompt issue, a pipeline-level orchestration issue, or a systemic `kiln`/`wheel` bug took a second pass — none of the notes explicitly separated the three scopes.
- **Judging "worked well" vs "didn't work well" is fuzzy when everything succeeded on first iteration.** Both implementers and the auditor reported zero rework, zero blockers, zero contract drift post-edit. A retrospective is easier when there's pain to name. For successful runs the risk is the retro degrades to "team was great" — I tried to force concrete evidence for every bullet.
- **Contract-edit framing.** The three contract edits (documented in `contract-edits.md`) are the most interesting signal from this run — ambiguity caught by the implementer before implementation drift, fixed up front. But "contract edit" is both evidence of what went well (caught early) AND what could be better (specifier could have caught via `get_permissions` during `/plan`). I had to write both angles carefully to avoid contradicting myself.
- **No retrospective template.** I had to invent a structure. The team-lead prompt enumerates required sections (prompt clarity, missing instructions, handoff failures, wasted work, communication overhead, plus the "File/Current/Proposed/Why" rewrite format), but doesn't give a skeleton for the "what worked / didn't work" body. A template would speed future retros.

## What I nearly missed

- **The specifier's Observation #45** (`create-new-feature.sh` bypass) is a prompt-brittleness signal that only surfaces when the branch is pre-checked-out. Because the feature succeeded, this easily could have been filed under "no friction." But it's actually a prompt-design gap: `/kiln:specify` assumes a greenfield branch and silently clobbers state if one isn't. Flagged in the proposed changes.
- **impl-shelf's "MCP access matrix" recommendation** is a process improvement, not a feature critique. I almost put it in "what went well" (the ambiguity was caught!) until I re-read and realized the point is: the ambiguity shouldn't have needed catching. Moved to "prompt & communication improvements."

## Observations for future retrospectives

1. **The "friction note before marking complete" pattern is load-bearing.** Every friction note was written before task completion per the team-lead's dispatch instructions. This is why retrospective-level evidence existed to synthesize. Keep this.
2. **The `contract-edits.md` pattern is new and very high-signal.** When an implementer caught an ambiguity, they (a) updated contracts first, (b) documented rationale in a dedicated file, (c) noted it in their own friction note, and (d) the auditor cross-checked against the updated contract. This is a four-way triangulation that makes the retrospective's job trivial. Recommend codifying `contract-edits.md` as a standard artifact for `/build-prd` runs.
3. **Surrogate smoke tests need a standard name and home.** The auditor used "surrogate smoke" (shelf-side fixture instead of full wheel activation) because plugin-cache lag prevented end-to-end. This pattern will recur every time a new wheel workflow is added inside a plugin. Naming and locating these in a predictable place (e.g., under `.wheel/surrogate/` or noted in `blockers.md` as "surrogate smoke performed") would speed up audits.

## Total time spent

- Reading friction notes + commits + PR body + blockers: ~12 min.
- Synthesis: ~10 min.
- Issue body drafting: ~8 min.
- This file: ~6 min.
