# Auditor (Phase X) friction notes

## What worked

- Implementers reached near-completeness within their plugin scopes. Of the roughly 60 renames across five plugins, the Phase X cross-plugin sweep surfaced only ~30 dangling command references outside plugin scopes. Most of them were concentrated in exactly three classes of file: (1) other plugins' SKILL.md invoking `/wheel:run`, (2) `CLAUDE.md`'s Available Commands table, (3) `docs/architecture.md`'s Mermaid diagram labels.
- impl-shelf's cross-plugin callout listing surviving `shelf:` hits in plugin-kiln as a safety net was extremely valuable, even though impl-kiln had already caught them. That message-as-belt-and-suspenders pattern saved a full extra grep cycle.
- impl-wheel's heads-up about filesystem-path-shape refs (`...plugin-wheel/skills/<old>/lib/...`) not being caught by command-shape regexes led me to widen the sweep to `.sh` and bare-word patterns.
- The split between command-form grep (`/plugin:name`) and bare-form grep (`/name`) was essential — a regex that matched both at once produced too many false positives from path fragments (`/next` in `framework/next` tag, `/init` in `init.mjs`).

## What was hard or surprising

- **BSD grep has no lookahead**, so multi-pass exclusion of already-renamed forms required scripting `for pattern in ...; do grep -F ...; done` with literal-string matching. On Linux `grep -P` would have been one-shot. Worth flagging: the grep gate shell snippet in the PRD should specify `grep -F` (fixed string) over `grep -rnE` when the goal is exact substring match.
- **Auto-incrementing VERSION hook fires on every edit.** During the sweep I made ~30 edits, each bumping the edit segment by 1 (VERSION went 257→260 before I consciously ran `version-bump.sh pr`). I eventually committed the hook-driven bumps as part of the sweep commit, then did the explicit FR-009 pr bump on top. This is fine but confusing — the PR ends up with two version-adjacent commits. A future improvement: gate the edit-hook's VERSION increment behind a "build session" marker so it doesn't noise the diff when the feature itself will re-bump the `pr` segment anyway.
- **docs/architecture.md Mermaid labels** have two syntactic forms: node declarations (`id["/cmd"]`) and edge labels (`-->|"/cmd"| target`). My first sed pass missed the edge-label form. Having a pure-AST Mermaid rewriter would be safer than regex.
- **Historical feature PRDs** (under `docs/features/2026-03-*` and prior `2026-04-*`) refer to commands that no longer exist. Per PRD FR-003 non-goal they stay unchanged, but they will appear as false positives in any future automated grep gate. If future features want a cleaner gate, the excluded-paths list needs to grow each time, or the gate should require command forms to appear in a changed file (not any file) to count.
- **SC-001 grep gate pattern collision**. Words that are also old skill names — `create`, `init`, `list`, `update`, `sync`, `status`, `stop`, `run`, `test`, `next` — show up everywhere for unrelated reasons (tag names, config key names, file paths, CLI sub-commands). The gate absolutely needs command-shape (`/plugin:name` or `/name<space>`) anchoring; a bare-word `grep -w create` is unusable.

## For the retrospective

- Future rename-refactors at this scale should formalize the PRD's "Excluded paths" list into a `scripts/grep-gate.sh` that takes the rename table as input and emits a single PASS/FAIL with the offending-path list. The spec author wrote the pattern inline in SC-001; codifying it as a script would make the gate repeatable and objective.
- Five parallel implementers is the right parallelism for this partition; their commits came in with zero conflicts against each other because each owned exactly one `plugin-<p>/` subtree.
- Phase X took roughly as long as any individual implementer phase despite being "just sweep and commit" — the cross-plugin sweep is NOT a light phase and should be scoped accordingly in future builds. The auditor role is a real implementer plus a PR-writing step plus a formal compliance gate.
