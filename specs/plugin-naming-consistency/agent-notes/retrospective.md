# Retrospective — friction notes

## Prompt clarity
The team-lead brief was unusually well-scoped: explicit analysis lens, expected output format (File/Current/Proposed/Why), expected file count (3-6), and concrete target files (SKILL.md paths, agent defs, template files). No back-and-forth needed.

## What I had to infer
- The brief said "point to a line in an agent definition under `.claude/agents/`". That path only exists as a scaffolded location for consumer projects; agent defs for this plugin source repo live under `plugin-kiln/agents/`. I adapted by targeting `plugin-kiln/agents/*.md` paths where appropriate.
- The interfaces template under `plugin-kiln/templates/interfaces-template.md` is function-signature-oriented only; there's no precedent for rename-refactor contract tables. I noted this as its own finding (Finding 4) rather than treating it as a miss.

## What would help next time
- When a retro is for a non-typical build (rename refactor, migration, non-code change), the brief could link to one or two prior retros that handled similar cases. This retro targets template gaps because the feature fell outside the interface-contract-shaped assumption baked into `/plan` and `interfaces-template.md`.
- The agent-notes files are consistently strong input; this is the third pipeline where I'd say they carry the retro. Worth reinforcing the FR-009 requirement in build-prd's example-brief text, not just as a numbered FR.
