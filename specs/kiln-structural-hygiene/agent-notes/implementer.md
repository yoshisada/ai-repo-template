# Implementer notes — kiln-structural-hygiene

Single implementer. All 5 phases A–E, ~17 tasks, per-phase commits.

## What went smoothly

- **Contracts-first discipline paid off.** `contracts/interfaces.md` §5–§9 locked the predicate shapes and the grep-anchored error strings to the token; the skill body was essentially transcription work once the rubric landed.
- **Mirror precedent.** `/kiln:kiln-claude-audit` (PR #141) provided a 1:1 template for Step 1 path resolution, Step 2 override parsing, and the propose-don't-apply discipline. Fewer novel design decisions, faster ship.
- **Phased commits matched the scope.** Each phase (A–E) was ~80–150 lines of diff, easy to reason about individually. Constitution VIII incremental completion worked as intended.

## Friction / where the spec could have been tighter

1. **`find -printf` is GNU-only.** Both `contracts/interfaces.md` §6 and my initial SKILL.md + doctor-3h used `find ... -printf '%f\n'` to enumerate top-level dir basenames. This broke silently on macOS (BSD find) — the `find` errored out, the `while` loop read zero entries, and the predicate returned "no drift" on a repo that would otherwise have drift. Caught by the SC-004 harness when I saw `drift=0` on a repo where I expected possible signals. Fixed by switching to `find ... | sed 's:^\./::'` everywhere (SKILL.md, doctor 3h, SMOKE.md). Flagging as a spec-contract drift: contract §6 still references `-printf '%f\n'` — the auditor should decide whether to update the contract or leave it as an editorial note.

2. **Frontmatter parsing with `awk -F:`.** The `prd:` field in many `.kiln/issues/*.md` files has leading whitespace and colons embedded in paths. My Step 5c uses `awk -F: '/^prd:/ {print $2; exit}' | tr -d ' '` which grabs just the second field — meaning a `prd:` value containing a colon (e.g. some future `prd: https://…`) would truncate. Good enough for the current file shapes, but a `yq`-based parser would be more robust. Out of scope for v1.

3. **Fixtures are documentary, not executable.** The plugin has no existing test-harness convention (the `plugin-kiln/skills/kiln-claude-audit/tests/` directory doesn't exist either). I wrote fixtures as README.md + sample frontmatter files with shell-runnable assertion snippets rather than a harness.sh that drives everything end-to-end. The skill is invoked via `/kiln:kiln-hygiene` in the Claude Code runtime, not a standalone shell script, so a pure-bash harness would have been a poor fit. The auditor may want to flag this as a v2 gap.

4. **SC-005 self-grep.** My first pass at the SKILL.md "Rules" section literally listed the forbidden patterns (`sed -i`, `mv .kiln/issues/`, etc.) as the prohibited set — which made the SC-005 grep match its own prohibition sentence. Rephrased to describe the patterns without writing them literally; SC-005 now passes clean. Worth a note for anyone writing a similar skill in future.

5. **Phase overlap temptation.** I nearly wrote Step 5c + the bundled preview in the Phase B commit because the full implementation was fresh in mind. Backed out and re-added in Phase D to honor the per-phase-commit discipline. The payoff was a cleaner commit history — the Phase C (doctor 3h) commit touches only doctor, the Phase D commit is purely hygiene-skill work.

6. **Backwards-compat assertion is hard to run without a baseline on `main`.** SC-007 / fixture-no-drift requires capturing stdout of `/kiln:kiln-cleanup --dry-run` etc. on `main` BEFORE the merge, diffing against the same on this branch AFTER the merge (minus the 3h row). The implementer pass cannot run this by itself — documented as a deferred auditor check in SMOKE.md.

## SC-004 real-repo measurement

Recorded 2026-04-23 against this branch HEAD (`build/kiln-structural-hygiene-20260423`) on macOS:

```
$ /usr/bin/time -p bash /tmp/3h_harness.sh
drift=0
real 0.38
user 0.19
sys 0.18

$ /usr/bin/time -p bash /tmp/3h_harness.sh   # cache-warm
drift=0
real 0.31
user 0.18
sys 0.15
```

Budget: <2.00s. Margin: ~5.3x under budget. Pass.

Notable: no cheap signals fired on this branch because (a) the repo has zero top-level orphaned folders and (b) `.kiln/logs/` + `.kiln/qa/*` have been kept trimmed by the existing retention rules + the pre-PR housekeeping sweep in 574f220.

## SC assessment summary

| SC | Status | Notes |
|---|---|---|
| SC-001 | ✅ pass | Rubric exists at `plugin-kiln/rubrics/structural-hygiene.md`, 3 rules, referenced ≥1x outside rubric+skill (28 hits counted). |
| SC-002 | ⚠ deferred | Fixture + assertions written in `fixture-all-rules-fire/README.md`. Live run requires gh auth against real merged PRs; auditor should execute. |
| SC-003 | ⚠ deferred | Bash recipe + assertions in `fixture-gh-unavailable/README.md`. Auditor should execute. |
| SC-004 | ✅ pass | 0.31s real on this branch — 5.3x under the 2s budget. Raw `time -p` output above. |
| SC-005 | ✅ pass | `grep -nE 'sed -i\|mv \.kiln/(issues\|feedback)/\|git mv \.kiln/(issues\|feedback)/' plugin-kiln/skills/kiln-hygiene/SKILL.md` → 0 matches. |
| SC-006 | ⚠ deferred | Idempotence recipe in `fixture-no-drift/README.md`. Requires a live `/kiln:kiln-hygiene` invocation, which the implementer cannot execute mid-run (the skill doesn't exist yet as a user-invokable command until this PR merges into a consumer's install). Auditor should execute. |
| SC-007 | ⚠ deferred | Requires capturing pre-PR baseline on `main` + post-PR output, diffing. Auditor-owned. |
| SC-008 | ⚠ deferred | `git worktree add 574f220^` + `/kiln:kiln-hygiene` + grep for 18 filenames. SMOKE.md §SC-008 has the full recipe. Auditor-owned. |

## Files touched

New:
- `plugin-kiln/rubrics/structural-hygiene.md` (rubric)
- `plugin-kiln/skills/kiln-hygiene/SKILL.md` (audit skill)
- `plugin-kiln/skills/kiln-hygiene/tests/fixtures/fixture-*/README.md` + sample items
- `specs/kiln-structural-hygiene/SMOKE.md`
- `specs/kiln-structural-hygiene/agent-notes/implementer.md` (this file)

Modified:
- `plugin-kiln/skills/kiln-doctor/SKILL.md` (+3h subcheck between 3g and 3f, +3 rows in Step 3e example)
- `CLAUDE.md` (+1 line under Available Commands naming `/kiln:kiln-hygiene` + rubric path)

Unchanged (verified diff):
- `plugin-kiln/skills/kiln-cleanup/SKILL.md` (NFR-003 backwards compat)
- All `plugin-kiln/skills/kiln-doctor/SKILL.md` pre-existing subchecks 3a–3g, 3f, 3e (ordering preserved)
- `specs/kiln-structural-hygiene/{spec.md,plan.md,contracts/interfaces.md}` (specifier-owned)

Auto-bumped by hooks on every Phase commit:
- `VERSION`
- `plugin-{clay,kiln,shelf,trim,wheel}/{.claude-plugin/plugin.json,package.json}` (4th-segment increment — this is the hooked "edit" counter, not a feature/release bump)

## Open questions for auditor

1. Is the `find -printf` GNU-ism in contracts §6 worth updating in-place, or leaving as an editorial note? I opted to fix it in the skill body (portable form) but leave the contract alone since the contract is specifier-owned.
2. Should `fixture-all-rules-fire/` sample items include a fake PRD directory structure under `docs/features/`? I opted to document it in the fixture README (bootstrap steps) rather than commit empty PRD stubs; the auditor may prefer the opposite.
3. Is the documentary (README-style) fixture shape acceptable for v1, or should we add an executable harness.sh that exercises the predicate in isolation? The precedent (claude-audit) has no harness either; I erred on the side of consistency with precedent.
