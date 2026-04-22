# Retrospective friction notes

**Agent**: retrospective (Task #8)
**Date**: 2026-04-21
**Output**: GitHub issue #128 — https://github.com/yoshisada/ai-repo-template/issues/128

## What was clear in the brief

- **Inputs were fully enumerated.** Seven friction-note files under `agent-notes/` + PR #127 body. No ambiguity about what to read or whether to poll live teammates ("Do NOT poll live teammates" was explicit).
- **Pre-identified signals accelerated synthesis.** The brief listed specific cross-cutting themes already known from in-flight messages (BSD `sed`/`\b`, filesystem-path-shape refs, frontmatter `description:` self-references, cross-plugin rewrite ownership ambiguity, pre-existing dangling refs, grep false positives, VERSION hook noise, Mermaid edge labels). This is effectively a pre-outlined "what was painful" section — most of my job was confirming and expanding from the notes.
- **Output structure was tightly specified.** Title, labels, required body sections, and the completion protocol (friction note → issue filed → mark completed) were all concrete. Zero judgment needed on issue scaffolding.
- **Optional-vs-required split was explicit.** The SKILL.md edit was marked optional with a clear default ("leave untouched and let the GitHub issue drive the change via normal /kiln:fix or /kiln:build-prd cycles"). This made it easy to defer rather than feeling pressured to make a change.

## What was ambiguous

- **"Small prompt improvement to build-prd/SKILL.md"** — I read kiln-build-prd/SKILL.md and found it's a general-purpose pipeline orchestrator without rename-refactor-specific guidance. Injecting a "filesystem-path sweep" bullet there would either be (a) too generic to be useful (applies to any refactor, not just renames) or (b) too specific and would bloat the general skill. I opted to skip the optional edit and let the retrospective's actionable improvement #6 ("extract `templates/rename-refactor-plan.md`") carry the fix — that's the natural home for rename-refactor-specific rubric items. The brief anticipated this outcome with its "otherwise leave the skill untouched" guidance.
- **Labels.** `retrospective` is not in the repo's standard label set — `gh issue create --label retrospective,build-prd` worked, which suggests gh auto-created it or it pre-existed. No error, but worth flagging that retrospective-as-label convention isn't documented in the kiln skill docs.

## What I'd change about my own brief

- **Explicit guidance on what NOT to belong in build-prd/SKILL.md would help.** The optional edit felt tempting ("something concrete to ship") but injecting rename-specific content into a general-purpose skill is the wrong shape. A sentence in the brief like "if the improvement is rename-specific, it probably belongs in a template/future skill, not build-prd/SKILL.md" would have resolved this faster.
- **No task to auto-extract the template.** Retrospectives like this produce a concrete backlog item ("extract rename-refactor-plan.md template") but there's no built-in step to file it as a `/kiln:report-issue` or backlog entry separate from the retrospective issue itself. The retrospective issue will get read once; the template extraction will get forgotten. Consider: retrospective brief should include "for each actionable improvement, file a tracked backlog item" as a final step.
- **No friction signal on token budget.** I read 7 friction notes + PR body in parallel (one tool call) which was efficient, but the retrospective synthesis itself (the issue body) is long. If the brief had a target length ("keep sections to 3-6 bullets"), I'd have trimmed earlier. It's already within the 3-6 bullet rubric, but a few sections drifted longer.

## Completion protocol note

Writing this note BEFORE marking Task #8 completed, per the protocol. Issue #128 is filed. No code / SKILL.md edits made — intentional per the "otherwise leave the skill untouched" option.
