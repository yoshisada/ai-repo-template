---
agent: impl-governance
date: 2026-04-24
scope: FR-001..FR-008 (hook fixture, /kiln:kiln-roadmap --promote, distill gate, grandfathering)
---

# Friction note — impl-governance

## What went smoothly

- **Clean separation of phases.** Phases 1 (hook fixture), 2 (roadmap `--promote`), 3 (distill gate) were genuinely independent at the file-system level. No cross-phase merge surgery — commit-per-phase worked.
- **Pre-existing helpers did most of the heavy lifting.** `plugin-kiln/scripts/roadmap/validate-item-frontmatter.sh` caught schema drift on the first run of `promote-source.sh`; I didn't need to hand-roll a validator. Same for the `parse-item-frontmatter.sh` awk grammar.
- **Fixtures-as-contracts.** Writing each fixture before the implementation made signature drift impossible — the contract lived in the test assertions, which meant I couldn't ship a partial contract.

## Where I got stuck (and escaped)

1. **`harness-type: static` isn't wired in `dispatch-substrate.sh` v1.** The `/kiln:kiln-test` harness only knows about `plugin-skill`. I wanted to run my fixtures through the real harness (per T005 / T012 / T022) but the dispatcher would reject `static`. I landed on direct `bash <fixture>/run.sh` invocation and added a `test.yaml` with `harness-type: static` so the fixtures are discoverable once the `static` substrate lands. **Suggested follow-on**: add a thin `substrate-static.sh` to `plugin-kiln/scripts/harness/` that just execs `run.sh` and exits with its code — half a screen of bash, unblocks every static fixture (there are several already, per `grep -l 'harness-type: static' plugin-kiln/tests/*/test.yaml`).

2. **Contract §2's sizing enums contradicted the structured-roadmap schema.** The specifier drafted `--blast-radius <low|medium|high>` / `--review-cost <low|medium|high>` / `--context-cost <low|medium|high>`. That doesn't match `validate-item-frontmatter.sh` which enforces `isolated|feature|cross-cutting|infra` for blast, `trivial|moderate|careful|expert` for review, and free-text for context. I updated the contract first (per Article VII change-control), documented the change inline, and notified both specifier and impl-pi-apply. **Suggested follow-on**: add a cross-contract consistency linter that checks `plugin-kiln/scripts/roadmap/validate-item-frontmatter.sh` against any new contract's sizing flags — this is the second time this has bitten (see `.kiln/mistakes/2026-04-24-specifier-picked-wrong-blast-radius-enum.md` if one gets filed from this session).

3. **Validate-before-move trapped by `.tmp` basenames.** My first pass of `promote-source.sh` ran the validator against the `*.XXXXXX.tmp` temp file, which trips the "id must equal basename sans .md" rule. Had to move first, then validate, then roll back on failure. Fine resolution, but it cost a test cycle. **Suggested follow-on**: `validate-item-frontmatter.sh` could grow a `--target-basename <name>` flag that overrides the computed basename for pre-mv validation. Cheap fix.

4. **Contract §1 `invoke-promote-handoff.sh` was spec'd as a decision sink.** The original contract had the bash script prompt the user and emit accept/skip envelopes. But confirm-never-silent requires the Skill tool, which a bash script can't reach. I reshaped the script to pure enumeration (emit `{path,title,prompt}` per input, order-preserving) and moved the decision loop into `kiln-distill/SKILL.md` §0.5.3. Updated the contract to match. **Suggested follow-on**: when drafting plans that involve shell scripts AND user confirmations, spec the UX layer up-front — bash can't host Skill-tool dispatch.

## What could be improved in `/specify` / `/plan` / `/tasks`

- **`/plan` should cross-check contract §N flags against existing validators.** Both failure modes above (sizing enum mismatch; basename validation timing) would have been caught by a plan-time sweep of referenced scripts. Today the plan writes signatures against what *sounds right*, not what the real validators enforce. Concrete follow-on: `/plan` could grow a step that, for every flag value of the form `<a|b|c>` in contracts/interfaces.md, greps `plugin-kiln/scripts/**/validate-*.sh` for the matching key and flags literal mismatches. Complementary to specifier's own rule ("grep validators before drafting enum literals") — same signal, different checkpoint.
- **`/tasks` should distinguish "write script" from "author fixture-first".** My Phase 2 / Phase 3 tasks blurred the two. The structured-roadmap tasks template has T006–T009 as "create fixture" and T010–T012 as "implement + make pass" — that's the right shape; workflow-governance inherited it cleanly. Keep that template.
- **`/specify` clarifications were load-bearing — keep them structured.** The 8 clarifications in `spec.md` (esp. #2 grandfathering cutoff, #3 byte preservation, #4 per-entry UX, #5 coached pre-fill threshold, #7 pi-hash algorithm) were the backbone of every implementation decision I made. Including them in the spec (rather than burying them in the PRD) was the right call.

## Coordination notes

- Sent courtesy messages to specifier + impl-pi-apply on 2026-04-24 when I edited `contracts/interfaces.md` §1 and §2. Neither module has consumers outside this feature, so both edits were local.
- Phase 5 `CLAUDE.md` updates include a Recent Changes entry covering all three sub-initiatives. The `/kiln:kiln-pi-apply` entry in the "Available Commands" list and the T042 `/kiln:kiln-next` FR-013 smoke test are impl-pi-apply's to add — they own FR-009..FR-013 and will finalize those touches when Phase 4 lands.

## Status at task completion

- **Phases 1, 2, 3, 5 (my slice)**: all tasks marked `[X]`, four commits on the branch:
  - `62188dc` — Phase 1 fixture (FR-003)
  - `00609b6` — Phase 2 `--promote` path (FR-006)
  - `e8f86c9` — Phase 3 distill gate (FR-004/005/007/008)
  - Phase 5 commit pending (CLAUDE.md + agent-notes).
- All 9 new fixtures pass under `bash <fixture>/run.sh`.
- Coverage: every new script has at least one fixture asserting its contract. `promote-source.sh` has four (basic, byte-preserve, idempotency, missing-source); `detect-un-promoted.sh` has three (refuses, accepts-promoted, grandfathered); `invoke-promote-handoff.sh` has one (refuses). Estimated behavior coverage ≥80% for new code per constitution Article II.
- No new runtime dependencies. No hook edits. No `--no-verify` commits.
