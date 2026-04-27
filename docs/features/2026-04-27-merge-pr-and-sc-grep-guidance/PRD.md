---
derived_from:
  - .kiln/roadmap/items/2026-04-24-sc-grep-date-bound-qualifier.md
  - .kiln/roadmap/items/2026-04-24-sc-grep-doc-references-carve-out.md
  - .kiln/roadmap/items/2026-04-27-auto-flip-on-async-merge.md
distilled_date: 2026-04-27
theme: merge-pr-and-sc-grep-guidance
---
# Feature PRD: Merge-PR Skill + Spec-Template SC-Grep Guidance

**Date**: 2026-04-27
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md)

## Background

Three independent friction points surfaced across the last two pipelines (escalation-audit PR #189, cross-plugin-resolver) all share one root cause: the build-prd substrate has small but load-bearing gaps that force every author to re-discover the same workaround. This PRD bundles three tactical fixes that each remove one rediscovery cycle.

Recently the roadmap surfaced these items in the **10-self-optimization** + **90-queued** phases: `2026-04-27-auto-flip-on-async-merge` (feature), `2026-04-24-sc-grep-date-bound-qualifier` (feature), `2026-04-24-sc-grep-doc-references-carve-out` (feature).

The first item — auto-flip-on-async-merge — is the highest-leverage of the three. Theme A of escalation-audit (PR #189) shipped the Step 4b.5 inline auto-flip block in `kiln-build-prd/SKILL.md`. It works correctly when invoked, but only fires INSIDE an active build-prd pipeline run. The common case is: build-prd ships the PR, the team-lead shuts down, the maintainer merges asynchronously some time later. By then the team-lead context is gone and Step 4b.5 has nothing to execute it. Items stay at `state: distilled` until manually flipped — which is exactly the drift PR #186 captured (8 items needing manual flip), and ironically PR #189 itself hit the same gap (had to manually run the just-shipped Step 4b.5 logic to verify SC-006).

The other two items are spec-template authoring guidance: success criteria written as bare `git grep` against directories with historical state (`.wheel/history/`, `archive/`, `migrations/`) auto-flag pre-PRD matches every time, and documentary references to `${WHEEL_PLUGIN_<name>}` / `${WORKFLOW_PLUGIN_DIR}` inside agent `instruction` text trip the wheel preprocessor's tripwire even with `$$` escaping. Both came out of cross-plugin-resolver-and-preflight-registry's retrospective; both cost a fix-attempt cycle to rediscover.

### Source Issues

| # | Source Entry | Source | Type | GitHub Issue | Severity / Area |
|---|--------------|--------|------|--------------|------------------|
| 1 | [Spec-template grep-style success criteria need a date-bound qualifier](../../../.kiln/roadmap/items/2026-04-24-sc-grep-date-bound-qualifier.md) | .kiln/roadmap/items/ | item | — | feature / phase:10-self-optimization |
| 2 | [Documentary references to `${WHEEL_PLUGIN_<name>}` / `${WORKFLOW_PLUGIN_DIR}` trip both the runtime tripwire and the SC grep](../../../.kiln/roadmap/items/2026-04-24-sc-grep-doc-references-carve-out.md) | .kiln/roadmap/items/ | item | — | feature / phase:10-self-optimization |
| 3 | [Auto-flip on async merge — Step 4b.5 doesn't fire when user merges PR after team-lead shutdown](../../../.kiln/roadmap/items/2026-04-27-auto-flip-on-async-merge.md) | .kiln/roadmap/items/ | item | — | feature / phase:90-queued |

## Problem Statement

The build-prd substrate has three small gaps that each force authors to re-discover the same workaround on every encounter:

1. **Lifecycle gap (item 3)**: roadmap items captured by `/kiln:kiln-distill` are flipped from `state: in-phase` → `state: distilled` with `prd:` back-reference, but the next transition (`distilled` → `shipped` + `pr:` + `shipped_date:`) only fires when Step 4b.5 of `kiln-build-prd/SKILL.md` runs inside an active pipeline. The maintainer's natural workflow — let the pipeline ship the PR, review later, merge asynchronously — bypasses the auto-flip entirely. The consequence is silent drift: items stay `distilled` indefinitely, and the only catch-up mechanism today is `/kiln:kiln-roadmap --check` which detects but doesn't fix.

2. **SC-authoring gap (item 1)**: spec-template offers no guidance on grep-style success criteria. Authors write the simplest formulation (`git grep -E '<pattern>' .wheel/history/`) and every auditor that runs it verbatim has to spend time chasing why "the SC fails" before realizing it's pre-PRD historical noise (71 matches in cross-plugin-resolver's case). The substantive assertion (new artifacts produced post-PRD have zero matches) is correct but unauthored.

3. **Token-grammar gap (item 2)**: `plugin-wheel/lib/preprocess.sh` has a load-bearing tripwire (FR-F4-5) that fires on any post-substitution `${WHEEL_PLUGIN_…}` / `${WORKFLOW_PLUGIN_DIR}` match. Authors who include documentary references to these tokens inside agent `instruction:` text — even purely as prose describing legacy behavior — trip the tripwire on the next workflow run. `$$` escaping defers the trip but leaves the post-decode form in `.wheel/history/success/*.json` where it tripping a second tripwire (the SC-F-6 archive grep). The only durable form is plain prose that doesn't reproduce the token grammar.

## Goals

- **Eliminate the async-merge auto-flip gap by construction**: ship `/kiln:kiln-merge-pr <pr>` — a combined merge+flip skill that runs the merge AND the auto-flip atomically. The maintainer invokes it instead of `gh pr merge`; the moment the merge succeeds, the flip runs.
- **Catch historical and out-of-band drift**: extend `/kiln:kiln-roadmap --check` (FR-005 of escalation-audit) with a `--fix` flag that one-shot flips detected drift after per-entry user confirmation. Catches items that drifted before this PRD shipped, or PRs merged via the GitHub web UI / git CLI that bypassed `/kiln:kiln-merge-pr`.
- **Extract the auto-flip logic to a shared helper**: pull the verbatim Step 4b.5 inline block out of `kiln-build-prd/SKILL.md` into `plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh`. Step 4b.5 calls the helper; `/kiln:kiln-merge-pr` calls the helper; `/kiln:kiln-roadmap --check --fix` calls the helper. One implementation, three call sites.
- **Document the SC-grep date-bound recipe in `spec-template.md`**: add an authoring note + recipe so future PRDs adopt the date-bound formulation by default.
- **Document the token-grammar rule in `plugin-wheel/lib/preprocess.sh` + `plugin-wheel/README.md`**: make "documentary references trip the tripwire" discoverable BEFORE the next author rediscovers it mid-migration.

## Non-Goals

- **NOT building a merge-watcher git/gh hook** — option (a) of the auto-flip-on-async-merge item is rejected as too invasive (cross-cutting hook surface). `/kiln:kiln-merge-pr` + `--check --fix` cover the same ground with less infrastructure.
- **NOT changing the spec-template overall structure** — sc-grep guidance is a small additive note in the Success Criteria authoring section, not a rewrite.
- **NOT touching the wheel preprocessor's behavior** — the token-grammar fix is documentation-only. The tripwire stays as-is; the change is making the authoring rule discoverable.
- **NOT auto-applying `--fix` without confirmation** — `/kiln:kiln-roadmap --check --fix` is confirm-never-silent (lists drifted items, asks `[fix all / pick / skip]`, fires the helper for accepted entries only).
- **NOT changing `/kiln:kiln-roadmap --check`'s detection logic** — only the optional `--fix` mode is new.

## Requirements

### Functional Requirements

- **FR-001** (from: `2026-04-27-auto-flip-on-async-merge.md`): `/kiln:kiln-merge-pr <pr>` MUST accept a PR number as required positional argument and `--squash | --merge | --rebase` as optional flag (default `--squash`). MUST also accept `--no-flip` as an escape hatch (merge only, skip auto-flip).
- **FR-002** (from: `2026-04-27-auto-flip-on-async-merge.md`): `/kiln:kiln-merge-pr` MUST gate on PR mergeability via `gh pr view <pr> --json state,mergeable,mergeStateStatus` BEFORE attempting the merge. Refuse to merge when state is not `OPEN` or mergeStateStatus is not `CLEAN`/`MERGEABLE`. Surface the reason and exit non-zero.
- **FR-003** (from: `2026-04-27-auto-flip-on-async-merge.md`): `/kiln:kiln-merge-pr` MUST invoke `gh pr merge <pr> --<method> --delete-branch` and wait for merge confirmation via `gh pr view <pr> --json state` returning `MERGED` before proceeding to auto-flip.
- **FR-004** (from: `2026-04-27-auto-flip-on-async-merge.md`): `/kiln:kiln-merge-pr` MUST locate the PRD via `gh pr view <pr> --json files` → first file matching `docs/features/*/PRD.md`. If zero matches, emit a diagnostic line `kiln-merge-pr: pr=<n> auto-flip=skipped reason=no-prd-in-changeset` and exit 0 (the merge succeeded; auto-flip is appropriately skipped).
- **FR-005** (from: `2026-04-27-auto-flip-on-async-merge.md`): `/kiln:kiln-merge-pr` MUST invoke the shared helper `plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh` against the PRD's `derived_from:` list and emit the canonical diagnostic line `step4b-auto-flip: pr-state=MERGED auto-flip=success items=N patched=N already_shipped=N reason=` matching Step 4b.5's output format byte-for-byte (so existing consumers parse identically).
- **FR-006** (from: `2026-04-27-auto-flip-on-async-merge.md`): `/kiln:kiln-merge-pr` MUST commit the roadmap-item flips with message `chore(roadmap): auto-flip on merge of PR #<n>` and push to origin. If the working tree had unrelated uncommitted changes at invocation, refuse and surface them — do not stage with `git add -A`.
- **FR-007** (from: `2026-04-27-auto-flip-on-async-merge.md`): `--no-flip` MUST skip the auto-flip stage entirely (FR-004 through FR-006 do not run). The merge still runs; the diagnostic line is `kiln-merge-pr: pr=<n> auto-flip=skipped reason=--no-flip`.
- **FR-008** (from: `2026-04-27-auto-flip-on-async-merge.md`): `plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh` MUST be a verbatim extraction of the existing Step 4b.5 inline block in `plugin-kiln/skills/kiln-build-prd/SKILL.md`. The helper accepts `<pr-number> <prd-path>` as positional args, reads the PRD's `derived_from:` list, flips each item's `state` to `shipped` + `status` to `shipped`, inserts `pr: <n>` and `shipped_date: <YYYY-MM-DD>` at the END of the frontmatter (canonical bare-numeric placement), and is idempotent: a second run with `<pr> <prd>` reports `already_shipped=N patched=0` per FR-004 of escalation-audit.
- **FR-009** (from: `2026-04-27-auto-flip-on-async-merge.md`): Step 4b.5 in `plugin-kiln/skills/kiln-build-prd/SKILL.md` MUST be refactored to call the shared `auto-flip-on-merge.sh` helper instead of inlining the logic. This is a pure extraction — no behavior change. Diagnostic line output, exit codes, and frontmatter mutations MUST remain byte-for-byte identical to the pre-extraction inline block.
- **FR-010** (from: `2026-04-27-auto-flip-on-async-merge.md`): `/kiln:kiln-roadmap --check --fix` MUST extend the existing `--check` mode (FR-005 of escalation-audit). When invoked WITHOUT `--fix`, behavior is unchanged (detect and report drift, exit 0). When invoked WITH `--fix`, present the drifted items as a confirm-never-silent list with `[fix all / pick / skip]` options. On `fix all` or per-item accept, call `auto-flip-on-merge.sh <pr> <prd>` for each accepted entry. On `skip` or empty input, exit 0 with no writes.
- **FR-011** (from: `2026-04-27-auto-flip-on-async-merge.md`): `/kiln:kiln-roadmap --check --fix` MUST resolve the PR number for each drifted item by reading the item's `prd:` field, then probing `gh pr list --state merged --search "head:<feature-branch>"` to find the merged PR that matches. If zero or multiple PRs match, surface the ambiguity to the user and skip that item; do not guess.
- **FR-012** (from: `2026-04-24-sc-grep-date-bound-qualifier.md`): `plugin-kiln/templates/spec-template.md` MUST gain an authoring note + recipe in the Success Criteria section. The note MUST advise that grep-style SCs against directories with historical state (`.wheel/history/`, `archive/`, `migrations/`) include a date or commit cutoff, and provide the canonical recipe (`git log --name-only --pretty='' --since='YYYY-MM-DD' -- '<glob>' | sort -u | xargs -I{} git grep -lE '<pattern>' -- {}`).
- **FR-013** (from: `2026-04-24-sc-grep-date-bound-qualifier.md`): The authoring note MUST also recommend the alternative — express the SC against a fresh artifact produced by a consumer-install simulation (the substantive assertion) rather than a directory-wide scan of historical state.
- **FR-014** (from: `2026-04-24-sc-grep-doc-references-carve-out.md`): `plugin-wheel/lib/preprocess.sh` MUST gain a module-level comment documenting the "documentary references trip the tripwire" gotcha. The comment MUST name both failure modes (FR-F4-5 prefix-pattern fires on grammar variants the substitution regex skips; `$$` escaping survives the tripwire but lands in archives where SC-F-6 grep trips it), and recommend plain-prose substitution that does NOT reproduce the token grammar.
- **FR-015** (from: `2026-04-24-sc-grep-doc-references-carve-out.md`): `plugin-wheel/README.md` MUST gain a "Writing agent instructions" section (or extend the existing workflow-authoring section) with the same rule, in author-facing language. The section MUST be discoverable from the README's table of contents or top-level headings.
- **FR-016** (from: `2026-04-24-sc-grep-doc-references-carve-out.md`): The FR-F4-5 tripwire's error text in `plugin-wheel/lib/preprocess.sh` MUST be extended to include the line `If you intended this as documentary text, rewrite as plain prose; the tripwire fires on the prefix pattern even with $$ escaping.` so authors hit the explanation directly on first violation.

### Non-Functional Requirements

- **NFR-001** (idempotency): `/kiln:kiln-merge-pr <pr>` re-invoked on an already-merged PR MUST detect the merged state via FR-002's gate, skip the merge, and still run the auto-flip stage. The auto-flip stage's own idempotency (FR-008) means the second-run diagnostic line is `step4b-auto-flip: pr-state=MERGED auto-flip=success items=N patched=0 already_shipped=N reason=`.
- **NFR-002** (zero-behavior-change extraction): the FR-009 extraction of Step 4b.5 → `auto-flip-on-merge.sh` MUST produce byte-for-byte identical mutations to test fixtures from PR #189. A regression test asserts that running the helper against a snapshot of pre-merge state produces the post-merge state observed in commit `22a91b10`.
- **NFR-003** (live-substrate-first auditing): per the LIVE-SUBSTRATE-FIRST rule, the auditor for FR-005 (canonical diagnostic format) MUST verify the `step4b-auto-flip:` output against the live shipped helper, not against a documented spec text. Same rule for FR-008's idempotency.
- **NFR-004** (confirm-never-silent): `/kiln:kiln-roadmap --check --fix` MUST never auto-fix without explicit user confirmation. Default behavior with no input is `skip`, not `fix all`.
- **NFR-005** (concurrent-staging hazard): per retro #187 PI-1, this PRD's implementation MUST stage by exact path, never `git add -A`. Implementers touching the same file (likely `kiln-build-prd/SKILL.md` if both FR-009 and any other Step-4b.5 adjacent change land) MUST be bundled into one implementer or coordinated via task dependencies.

## User Stories

- **As the maintainer**, when I'm ready to merge a PR that build-prd shipped, I run `/kiln:kiln-merge-pr 189` instead of `gh pr merge 189` and the roadmap item flips happen automatically. I never run a manual auto-flip block again.
- **As the maintainer**, when I notice a few weeks later that some items drifted (because I merged via the GitHub web UI or before this skill shipped), I run `/kiln:kiln-roadmap --check --fix` and accept-all the listed drifted items in one step.
- **As a future PRD author**, when I write a `## Success Criteria` section with a grep assertion against `.wheel/history/`, the spec-template authoring note tells me to use the date-bound recipe BEFORE the next auditor wastes time chasing historical noise.
- **As a future workflow author**, when I'm writing an agent `instruction:` block and want to describe the wheel's plugin-relative substitution behavior, the wheel README's "Writing agent instructions" section warns me NOT to reproduce the `${WHEEL_PLUGIN_<name>}` / `${WORKFLOW_PLUGIN_DIR}` grammar verbatim — I write plain prose instead.

## Success Criteria

- **SC-001** (from: FR-001..FR-007): `/kiln:kiln-merge-pr <some-test-pr>` invoked end-to-end against a real PR (created and immediately merged via this skill in a fresh test branch) merges the PR, runs the auto-flip, commits the flips, and pushes — with zero manual intervention. Verified by running it against THIS PRD's PR after spec.md ships.
- **SC-002** (from: FR-008, FR-009): a regression test under `plugin-kiln/tests/` runs `auto-flip-on-merge.sh` against a fixture matching pre-merge state of PR #189 and asserts byte-for-byte equality with post-merge state from commit `22a91b10`. Test is added to `kiln-test` harness and runs in CI.
- **SC-003** (from: FR-009): the inline Step 4b.5 bash block in `plugin-kiln/skills/kiln-build-prd/SKILL.md` is removed and replaced with a single-line invocation of `auto-flip-on-merge.sh`. Verified by `git diff plugin-kiln/skills/kiln-build-prd/SKILL.md` showing the block deleted and `wc -l` decreasing.
- **SC-004** (from: FR-010, FR-011, NFR-004): `/kiln:kiln-roadmap --check --fix` invoked against a repo with at least one drifted item (synthesized by reverting `state: shipped` → `state: distilled` on a test item) detects the drift, prompts for confirmation, applies the fix on `accept`, and reports `fix=success items=1`. On `skip`, no writes happen — verified by `git diff` being empty.
- **SC-005** (from: FR-012, FR-013): `plugin-kiln/templates/spec-template.md` contains the literal authoring note + recipe block. Verified by `grep -F 'date-bound qualifier' plugin-kiln/templates/spec-template.md` returning at least one match AND the recipe code-fence containing `--since='YYYY-MM-DD'`.
- **SC-006** (from: FR-014, FR-015, FR-016): `plugin-wheel/lib/preprocess.sh` module-level comment, `plugin-wheel/README.md` workflow-authoring section, AND the FR-F4-5 tripwire error text all contain the documentary-references rule. Verified by `grep -lF 'documentary' plugin-wheel/lib/preprocess.sh plugin-wheel/README.md` returning both files AND the tripwire path testing the extended error string.
- **SC-007** (cumulative — from: NFR-002): re-running `/kiln:kiln-merge-pr` on the merged PR for THIS PRD produces the byte-identical diagnostic line and zero file changes (idempotency). Captured as the closing live-fire validation of the pipeline.

## Tech Stack

Inherited from parent PRD. No additions. Implementation is bash scripts + skill markdown + template/README markdown — same substrate as the rest of plugin-kiln + plugin-wheel.

## Risks & Open Questions

- **R-1** (FR-009 zero-behavior-change risk): extracting Step 4b.5 verbatim is straightforward, but the exact frontmatter-mutation awk block has subtle invariants (canonical bare-numeric `pr:` placement at END of frontmatter; idempotency check accepting both `pr: 189` and `pr: #189` for back-compat). Implementer MUST run the regression fixture (SC-002) BEFORE marking FR-009 complete; deviation triggers blockers.md.
- **R-2** (FR-011 PR resolution ambiguity): `gh pr list --search "head:<feature-branch>"` may return zero PRs (branch deleted) or multiple PRs (rebases / re-creates with same head name). Spec explicitly handles this by surfacing ambiguity and skipping; implementer MUST NOT add heuristic guessing.
- **R-3** (FR-006 git-state preflight): `/kiln:kiln-merge-pr` refuses to commit if the working tree has unrelated changes. This is the right safety bar but creates friction when the maintainer has WIP. Open question: does the skill offer `--stash-and-restore` as a follow-on? Decision: NO for V1 — surface the WIP, exit, let the user handle it. Re-evaluate after first month of use.
- **R-4** (FR-010 ordering vs --check): `/kiln:kiln-roadmap --check --fix` extends the existing `--check` skill. Implementer MUST verify that adding `--fix` doesn't change `--check` behavior when `--fix` is absent (NFR-005 byte-identical compat for the single-flag case).
- **OQ-1** (--fix one-shot UX): when 5+ items are drifted, is the prompt `[fix all / pick / skip]` enough, or do we need `[fix all / fix oldest N / pick / skip]` with a numeric escape? Suggest: ship the simple form; iterate based on first month's drift volume.
- **OQ-2** (FR-016 tripwire error-text length): the proposed error-text extension adds ~80 characters. Worth checking that no existing log-parsing consumer truncates long tripwire errors. If yes, condense to a one-line "see plugin-wheel/README.md §Writing agent instructions" pointer.

---

## Acceptance Test (Live-Fire — closes the loop)

The PRD that ships this code MUST be merged via `/kiln:kiln-merge-pr <its-own-pr>`. If the merge succeeds and the auto-flip emits `step4b-auto-flip: ... items=3 patched=3` against this PRD's three derived_from items, the feature has self-validated end-to-end. (This is the cleanest SC-001 verification possible — the skill closes its own loop on its own merge.)
