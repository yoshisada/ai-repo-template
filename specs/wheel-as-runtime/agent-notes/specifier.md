# Specifier friction note — wheel-as-runtime

**Date**: 2026-04-24
**Agent**: specifier
**Task**: #1 — Specify + plan + tasks for wheel-as-runtime

## What was confusing / where I got stuck

- **Spec directory naming collision with `/specify` default behavior.** The orchestrator explicitly mandated `specs/wheel-as-runtime/` (no numeric prefix, no date prefix, matches the branch slug), but `.specify/scripts/bash/create-new-feature.sh` defaults to a numbered/timestamped prefix AND creates a new branch. I had to bypass the script entirely — create the directory manually, skip the `/specify` script path, and write `spec.md` directly. The `/specify` skill template isn't designed to land in a pre-named, pre-branched directory. The same was true for `/plan` (`setup-plan.sh`) and `/tasks` (`check-prerequisites.sh`) — all three skill scripts assume they own feature-directory creation. **Friction**: the pipeline contract's "branch is already set, spec dir is pre-named" intent collides with the shipped kiln skill scripts. A `--prefab-dir <path>` flag on `/specify` (and a no-op equivalent in `/plan` / `/tasks`) would remove this collision.

- **PRD FR numbering vs spec theme tagging.** The PRD numbers FRs flat (FR-001..FR-020 across all five themes), but the themes are independent implementer tracks. I retagged FRs per-theme (FR-A1..A5, FR-B1..B3, FR-C1..C4, FR-D1..D4, FR-E1..E4) in the spec and referenced that mapping in checklists/requirements.md. **Friction**: either the PRD template or `/specify` should recommend theme-prefixed FR IDs when the feature bundles multiple themes — makes downstream partition trivial.

- **Interface contracts for shell + JSON + hook + env-export.** Constitution Article VII says "every exported function" — but half this PRD is shell scripts with stdin/stdout JSON contracts, half is workflow-JSON schema extensions, and one piece is an env-export invariant. The `contracts/interfaces.md` template implicitly assumes typed-language signatures (name/params/return/sync-vs-async). I expanded the shape to handle six heterogeneous contract types (script stdin/stdout, JSON schema addition, hook input contract, env-export invariant, batched wrapper shape). **Friction**: the template/guidance doesn't cover shell-heavy or infra-contract features — a shell-contract section in the interfaces template would help.

- **Agent-resolver "unknown passthrough" is a back-compat requirement but reads as a bug.** FR-A3 says the resolver accepts an unknown name and "passes through as-is" — I had to read this twice to realize it's the back-compat contract for current `subagent_type: general-purpose` spawns. In the resolver JSON output I made this explicit with `"source": "unknown"` so the dispatcher can branch on it (invariant I-A3). **Friction**: "unknown passthrough" in the PRD would benefit from an example.

## What could be improved

1. **Pipeline-aware mode for kiln skills.** `/specify`, `/plan`, `/tasks` should detect "I'm running inside a pipeline with a pre-named spec dir and pre-created branch" and skip their own branch-creation + directory-numbering scripts. Today I'm bypassing the skills entirely (writing files with Write) which means I don't benefit from the template's validation loops.

2. **Theme-prefixed FR IDs in PRD template.** When a PRD explicitly says "5 themes, 1 feature," the FR IDs should already be theme-tagged so the partition is visible at PRD-read time, not after /specify.

3. **Interface contract template extension.** Add a "shell / infra / schema-addition" section alongside the function-signature section. My `contracts/interfaces.md` had to freestyle it.

4. **Friction note path formalization.** The orchestrator said `specs/wheel-as-runtime/agent-notes/specifier.md` — that's fine, but the pipeline contract should list this as a documented sub-directory in the spec template itself so every agent knows where to write.

## Time split (rough)

- Reading PRD + constitution + spec template: ~5 min
- Drafting spec.md (5 user stories, 24 FRs retagged, 9 success criteria, edge cases): ~15 min
- Drafting plan.md (technical context, partition rationale, project structure): ~8 min
- Drafting contracts/interfaces.md (six contracts with invariants + tests): ~15 min
- Supporting artifacts (research, data-model, quickstart): ~8 min
- Drafting tasks.md (30+ tasks partitioned by track, cross-track deps flagged): ~12 min

Total: ~60-70 min. Most of it is write-out, not deliberation — the PRD was dense and well-specified, which made spec.md mostly a translation pass.
