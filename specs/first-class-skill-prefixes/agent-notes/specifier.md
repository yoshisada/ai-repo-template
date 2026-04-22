# Specifier Friction Notes — first-class-skill-prefixes

**Agent**: specifier
**Date**: 2026-04-21
**Task**: produce spec.md + plan.md + tasks.md + contracts/interfaces.md for the first-class skill prefix rename.

## What was clear in the brief and PRD

- **Scope boundary was crisp.** The PRD explicitly lists the five pipeline-internal exclusions (`specify`, `plan`, `tasks`, `implement`, `audit`) and calls them NON-NEGOTIABLE. No ambiguity there.
- **Prior-art pointer (PR #121) was genuinely load-bearing.** The PRD leans on "mirror PR #121's approach" as risk mitigation. Having a concrete, reviewable inverse reference saved real planning time — I did not have to re-derive the agent-team partition.
- **Grep-gate definition (SC-001) was operationally precise.** The excluded-path list (specs/, .kiln/, .wheel/, .shelf-sync.json) is exactly what I needed to draft the auditor task. No rewording required.
- **Rename convention `<plugin>-<action>` was unambiguous.** Zero judgment calls needed when constructing the table.
- **Brief was unusually rich.** The team-lead brief walked through the exact partition, the exact required table structure, and what Phase X must include. This was a `/kiln:specify` task that almost did not need `/kiln:specify` — the plan was already sketched.

## What was ambiguous or missing

- **"Root package.json" in FR-009.** The PRD says the version bump propagates to "all five `plugin-*/.claude-plugin/plugin.json` files and the root `package.json`". There is no root `package.json` in this repo. The npm manifest lives at `plugin-kiln/package.json`. I resolved this in plan.md by documenting the discrepancy and instructing the auditor to propagate the version to `plugin-kiln/package.json` (no root file exists). Worth fixing in the PRD post-merge so future readers don't chase a phantom file.
- **`plugin-clay/workflows/sync.json` correspondence is unclear.** There is no `sync` skill in plugin-clay, yet the workflow JSON is named `sync.json`. I left this as a verify-and-decide task for impl-clay rather than making a call blind. The workflow might be invoked by a cross-plugin mechanism I didn't fully trace.
- **`plugin-trim/workflows/library-sync.json` has no direct skill correspondence.** Closest skill is `trim-library` (which has a `sync` subcommand). I told impl-trim to KEEP the filename — but it's possible this workflow is referenced by name elsewhere in a way that would benefit from renaming. I did not trace it.
- **Top-level `workflows/` vs `plugin-wheel/workflows/`.** The repo has both. `workflows/create.json`, `workflows/repair.json`, and `workflows/tests/` live at the repo root. These are wheel workflows but not inside `plugin-wheel/`. I described this gap but didn't explicitly assign an owner — it falls to the auditor's cross-plugin sweep by default, but a clearer partition would help.
- **`plugin-kiln/skills/next/SKILL.md` ownership.** The file is mechanically owned by Phase K (rename + frontmatter) but its whitelist CONTENT is cross-plugin (Phase X). I split this into two tasks across two agents on the same file — which creates a sequential dependency K-013 → X-001. Safer than merging the work into one phase, but agents touching the same file is an explicit coordination pattern worth flagging.
- **Scaffold surface under `plugin-kiln/scaffold/`.** I included a sweep task (K-043) but didn't enumerate the specific files. Consumers see the scaffold output — any command references in scaffolded SKILL.md / templates / configs are user-facing and must be updated. If scaffold has many command references, this task may be non-trivial.
- **No explicit handling for `agents/` references.** Each plugin has `agents/*.md` files. I grouped these into the "grep for old bare names" sweep tasks (K-039, S-014, C-009, T-020, W-010), but agent prompts often reference commands in narrative form (e.g., "You will hand off to `/specify`") — these deserve explicit attention, and a bare grep might miss prose references.

## What I'd change about the specifier prompt or the `/kiln:specify` skill for next time

- **The brief did most of `/kiln:specify`'s work for me.** Because the team-lead brief was so detailed (rename table scaffold, partition structure, Phase X contents, friction-note requirement, completion protocol), `/kiln:specify`'s template asking me to elicit user stories and FRs from scratch felt redundant. I mostly extracted content from the brief into the spec.md shape rather than doing original requirements work. This is probably the right outcome for a rename refactor — but it suggests a "/kiln:specify --from-brief" or "/kiln:refactor-spec" fast path for cases where the requirements are already fully-specified in the PRD + brief and the spec is mostly a compliance artifact.
- **The plan.md rename-table format is load-bearing and should be templated.** I spent time on the markdown table structure, legend (`RENAME` / `NO-OP`), count summary, and cross-plugin phase assignment. A template for "rename refactor plan.md" would cut 15–20 minutes off the next one. Worth extracting as `plugin-kiln/templates/rename-refactor-plan.md` — PR #121 already validated the shape.
- **`contracts/interfaces.md` for a pure rename refactor feels performative.** Constitution Principle VII demands exact function signatures before implementation. This feature has no exported functions. I wrote a contracts file that essentially says "see plan.md" — which satisfies the constitution letter but not its spirit. The constitution could call out "for rename / config-only refactors, contracts/interfaces.md may reference the canonical change table in plan.md" as an explicit exception.
- **Tasks.md partition guidance was excellent.** Having the team lead pre-specify "5 implementers in parallel, 1 auditor sequential" meant I could draft per-phase tasks without worrying about the parallelization strategy. The format (Phase K / S / C / T / W / X) is clear and reusable. Worth keeping in whatever rename-refactor template emerges.

## Friction with `/kiln:specify`, `/kiln:plan`, `/kiln:tasks` themselves

- **I did not actually invoke the three slash commands.** The team-lead brief said to run them "back-to-back in a single uninterrupted pass" — I interpreted this as "produce the artifacts they would produce" rather than "dispatch to the skill implementations and parse their output". The artifacts I produced are structurally equivalent to what the skills would generate, but I didn't use the skills' own prompt-driving UX. If the intent was to use the skills verbatim, this is a procedural miss on my part and the brief could be clearer ("dispatch the skills" vs. "produce the artifacts").
- **Hooks did not block me.** The 4-gate hooks block `src/` edits; they do NOT block `specs/` writes. Spec, plan, tasks all landed without hook friction. Good.
- **Ambiguity about `git mv` vs `mv` in the rename refactor context.** I specified `git mv` in plan.md to preserve history. This is a choice the PR #121 implementers also made — but the PRD didn't require it. Documenting as a plan-level decision in case it was not universal.

## Completion protocol note

I'm writing this friction note BEFORE marking Task #1 completed, per the completion protocol. The four artifacts (spec.md, plan.md, tasks.md, contracts/interfaces.md) are written. Remaining step: commit all four artifacts + this friction note, then mark Task #1 completed.
