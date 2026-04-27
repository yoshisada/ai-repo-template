# Specifier friction note — merge-pr-and-sc-grep-guidance

**Agent**: specifier (kiln-merge-pr-and-sc-grep team)
**Date**: 2026-04-27

## What worked well in the prompt

- The PRD-naming-authority directive listing the five canonical paths verbatim removed all ambiguity about file naming. I copied each path literally into spec.md/plan.md/tasks.md without interpretation.
- The file-ownership split (impl-roadmap-and-merge vs impl-docs) was given explicitly with full path lists per implementer. tasks.md inherited the split structurally — Section [A] and Section [B] are physically separated and the "DO NOT TOUCH" lists are explicit at the top of each section.
- The threshold-reconciliation carve-out ("PRD has NO quantitative perf thresholds") was given upfront. I noted it in the spec's Assumptions and avoided fabricating perf NFRs.
- The CHAINING REQUIREMENT was unambiguous — no skill-completion-suggestion ambiguity.
- The retro #187 PI-1 reference (stage by exact path, never `git add -A`) was cited inline; I propagated it into NFR-005 and into every commit task in tasks.md.

## Ambiguities I had to interpret

1. **plugin.json registration for `kiln-merge-pr`**: the PRD lists `plugin-kiln/.claude-plugin/plugin.json` in `impl-roadmap-and-merge`'s file ownership list, but inspecting the existing `plugin.json` shows skills are auto-discovered (no entry per existing skill). I documented this as Phase A4 / T037 in tasks.md with "default assumption: skills auto-discover; entry added only if explicit registration is required at edit-time inspection." Implementer makes the call; I did not assume an unnecessary edit.

2. **How the new skill captures "which files were flipped" for FR-006 staging precision**: the PRD says "stage by EXACT PATH" but doesn't specify the mechanism the skill uses to learn the flipped paths from the helper. Two equally valid approaches:
   - Re-walk the PRD's `derived_from:` list + filter by `git diff --name-only`.
   - Helper emits `flipped-path:` lines on stderr, captured by the skill.
   I documented both in contracts §B.3 and let the implementer choose. Approach 1 is preferred because it preserves the helper's NFR-002 zero-behavior-change invariant.

3. **Test-fixture extract pattern for the existing `build-prd-auto-flip-on-merge` test**: the existing escalation-audit fixture under `plugin-kiln/tests/build-prd-auto-flip-on-merge/run.sh` was built to source the inline Bash block out of `kiln-build-prd/SKILL.md`. After FR-009's refactor removes that inline block, the existing fixture's extract pattern may break. I added T023 calling out the risk and noting the implementer must either update the fixture's extract pattern or document the substitution in friction notes. I didn't decide this for them — depends on the existing fixture's exact extraction approach which I didn't read end-to-end.

4. **Where to insert the wheel README "Writing agent instructions" section**: the PRD says "in the README's table of contents or top-level headings." The existing README has no explicit TOC; sections progress as `## Install`, `## Workflow Format`, etc. I anchored the new section after `## Workflow Format` in contracts §F.1 / tasks T096, but kept the placement-relative-to-other-sections deliberately loose since I didn't enumerate every later heading.

5. **OQ-2 (tripwire error-text length)**: the PRD asks "worth checking that no existing log-parsing consumer truncates long tripwire errors. If yes, condense to one-line." I documented BOTH forms (longer and condensed) in contracts §E.3 with the literal `documentary` sentinel surviving both. Implementer makes the call at edit time. Not a decision specifier could make without inspecting consumers.

## Threshold reconciliation

Per the team-lead directive: this PRD has NO quantitative perf thresholds. NFRs are byte-identity (NFR-002) / structural (NFR-005) / boolean idempotency (NFR-001) / boolean confirm-never-silent (NFR-004). The baseline-checkpoint procedure does NOT apply. Documented in spec.md Assumptions block.

## Mid-spec interpretations not explicitly covered by the PRD

- **NFR-001 + FR-002a interaction**: the PRD's FR-002 says "Refuse to merge when state is not OPEN ... Surface the reason and exit non-zero." The PRD's NFR-001 says re-invocation on already-merged PR MUST detect merged state and still run auto-flip. These are in tension — strict FR-002 would refuse a `state=MERGED` PR. I resolved this by introducing FR-002a (idempotent skip path: `state=MERGED` proceeds to auto-flip stage; mergeStateStatus check is bypassed). This matches the PRD's NFR-001 text. Implementer should treat FR-002 + FR-002a as one composite gate.

- **`gh pr list --state merged --search "head:<feature-branch>"` ambiguity in FR-011**: the PRD says "If zero or multiple PRs match, surface the ambiguity to the user and skip that item; do not guess." I clarified in spec/contracts that "skip" means skip THAT item only — the rest of the drift list still processes. Without the clarification, "skip" could be read as "abort the whole `--fix` run."

- **Step 4b.5 surrounding markdown preservation**: FR-009 says "pure extraction — no behavior change." The 80-line Bash block is replaced; but the `### Step 4b.5: ...` heading + Purpose/When-this-runs/Inputs prose + Diagnostic-line literal/Verification-regex code-fences + invariants list have authoring value beyond the helper. I made it explicit in contracts §A.3 + tasks T020 that ONLY the bash code-fence body is replaced; the surrounding markdown stays verbatim.

## Things that surprised me

- The PRD's Acceptance Test (live-fire — closes the loop) is structurally the SC-001 + SC-007 closure. I treated it as a deferred test that the audit-pr stage executes after merge, not as a pre-merge testable assertion. Documented in plan.md "Phase 3 — Audit & PR".
- The existing Step 4b.5 block already has its own contracts file at `specs/escalation-audit/contracts/interfaces.md §A.2`. I cited that as the authoritative pre-extraction reference rather than re-deriving the diagnostic-line shape. Saves drift between the two contracts files.

## What I'd want clarified for next time

- A worked example of "exact-path staging when the file list is dynamically discovered post-helper" would be useful — there's a class of skill where the file list isn't statically known until the helper runs, and the staging-precision rule needs a canonical pattern. I picked one (re-walk + git-diff filter) but the substrate could ship a one-liner helper.
- Whether `kiln-test` harness auto-discovers `plugin-kiln/tests/<name>/` directories or requires explicit registration is something I assumed (auto-discovery, matches the existing convention). If wrong, the regression fixture won't run in CI and SC-002 won't actually gate.

## Mid-pass corrections from team-lead (applied 2026-04-27)

The team-lead sent two corrections AFTER the initial spec/plan/tasks commit (`38f7abdb`); applied as a follow-on commit in this same `/specify+/plan+/tasks` pass:

1. **`plugin.json` registration is NOT required**. Kiln plugin uses filesystem auto-discovery from `skills/`. The manifest at `plugin-kiln/.claude-plugin/plugin.json` has only `workflows` + `agent_bindings` arrays — no `skills` array. Creating `plugin-kiln/skills/kiln-merge-pr/SKILL.md` is sufficient registration. Removed the manifest from impl-roadmap-and-merge's file ownership list (spec.md NFR-005, plan.md, tasks.md owner header + T037 + T041 + DO-NOT-TOUCH list of impl-docs section).

2. **SC-002 fixture date-stability**: the helper inherits Step 4b.5's `TODAY="$(date -u +%Y-%m-%d)"` line. Freezing it would violate NFR-002 (zero behavior change). Strategy: golden post-snapshots embed a literal `<TODAY>` placeholder in the `shipped_date:` field; the fixture's `run.sh` materializes the comparison snapshot by `sed`-substituting the placeholder with `date -u +%Y-%m-%d` before the byte-for-byte diff. Updated SC-002 acceptance scenario, added T013a, expanded T014's contract, and updated contracts §G.1 + §G.2 to reflect the substitution step.

Both corrections are mid-pass — the implementers had already started Phase 1 setup when the corrections arrived. The follow-on commit ensures their first edit reads the corrected spec.

## Staging-collision lesson (commit `81eca4c3`) — for retrospective

When I ran `git add <exact-spec-paths>` to stage the corrections, the git index already held pre-staged changes from parallel work. The commit therefore included MORE than the 5 spec files I named:

- **Hook-bumped collateral (DESIRED pattern per retro #187 PI-2)**: `VERSION`, `plugin-{clay,kiln,shelf,trim,wheel}/.claude-plugin/plugin.json`, `plugin-{clay,kiln,shelf,trim,wheel}/package.json` — 11 files. The version-increment hook auto-stages these on Edit/Write tool use; sweeping them into the next commit is the intended behavior. No corrective action.
- **NOTEWORTHY collision**: `plugin-kiln/templates/spec-template.md` — impl-docs's completed Theme B work (FR-012/FR-013 authoring note + recipe). They had run `git add plugin-kiln/templates/spec-template.md` before I ran my own `git add` for the corrections. My commit therefore ran with their work pre-staged in the index. The diff content matches contracts §D.2 verbatim — semantically correct — but it shipped under MY commit message ("specify+plan+tasks: corrections...") instead of theirs ("docs(spec-template): SC-grep date-bound authoring note + recipe (FR-012, FR-013)"). The labeling error is now a permanent part of git history.

### Why this happened

`git add <path>` adds the named path to the index. It does NOT clear OR reject other already-staged paths. When two parallel agents both work toward `git add` + `git commit` cycles, whoever calls `git commit` first sweeps everything currently in the index — including the other agent's pre-staged-but-not-yet-committed work — into their commit. This is git's documented behavior, but it surprised me because I conflated "stage by exact path" with "commit by exact path." Those are distinct guarantees: you control what enters the index, not what's already there.

### What would have prevented it

A `git status --porcelain` check immediately before `git commit` (after the targeted `git add`) would have shown impl-docs's spec-template.md sitting in the index alongside my 5 spec files. I'd have spotted the collision and either:

1. Unstaged the collision (`git restore --staged plugin-kiln/templates/spec-template.md`) so impl-docs's commit could land cleanly under their own message, OR
2. Coordinated with team-lead to allow the absorption (which is what team-lead actually approved retroactively).

The fix is procedural, not technical: in concurrent-implementer pipelines, treat `git status --porcelain` BEFORE `git commit` as mandatory, even when you've staged by exact path. Especially when other agents are actively working on disjoint files — their staged but uncommitted index entries are invisible from your `git add` perspective but very visible to your `git commit`.

### Recommended PI for next-iteration build-prd skill

Add a pre-commit teammate-coordination check: when an agent is about to `git commit`, if `git diff --cached --name-only` includes ANY path NOT in the agent's declared file-ownership list (per spec NFR-005), the agent MUST either (a) message team-lead before proceeding, or (b) `git restore --staged` the foreign paths first. Both options preserve the labeling integrity of every commit. The cost is one extra `git diff --cached` call per commit; the benefit is no more commit-message-vs-content drift in concurrent runs.

The hook-bumped collateral (VERSION/manifests) is exempted because retro #187 PI-2 explicitly endorses that sweep pattern.

## Confidence

High on Theme A's helper extraction + skill body (mechanical, well-pinned by escalation-audit's contracts).
Medium on `--check --fix` (depends on how confirm-never-silent prompts render in skill bodies; a similar pattern exists elsewhere in plugin-kiln but I didn't read each one to confirm).
High on Themes B + C (pure documentation edits with grep-able sentinels).
