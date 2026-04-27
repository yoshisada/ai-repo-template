# impl-theme-c friction notes

**Owner**: `impl-theme-c` (Theme C — escalation-audit skill + kiln-doctor subcheck)
**Phases owned**: 2 (setup), 6 (US4 escalation-audit skill), 7 (US5 doctor subcheck), 8 (T071 polish)
**Branch**: `build/escalation-audit-20260426`
**Date**: 2026-04-26

## What landed

| Phase | Files touched | Tests |
|-------|---------------|-------|
| 6 (US4) | `plugin-kiln/skills/kiln-escalation-audit/SKILL.md` (new) | `plugin-kiln/tests/escalation-audit-inventory-shape/run.sh` (new, 5/5 PASS) |
| 7 (US5) | `plugin-kiln/skills/kiln-doctor/SKILL.md` (insert §4 after §3h, append two rows in §3e) | inline smoke per SC-007 below |

No other paths were touched (concurrent-staging hazard discipline). impl-themes-ab's `update-item-state.sh` + `kiln-build-prd/SKILL.md` were left untouched in the worktree throughout.

## SC-007 inline smoke — verified

The doctor §4 subcheck is structural-grep-tested by impl-theme-c via scratch-dir runs. The bash block was extracted from `kiln-doctor/SKILL.md` (the `# FR-016 — escalation-frequency tripwire` fence) and run against three corpora:

| Corpus | Expected | Observed |
|--------|----------|----------|
| 25 `awaiting_user_input:true` JSONs in `.wheel/history/` (mtime within 7d) | `WARN — 25 awaiting_user_input events in last 7 days` + `consider running /kiln:kiln-escalation-audit` | matches |
| 5 events under threshold | `OK — 5 awaiting_user_input events in last 7 days` (no suggestion) | matches |
| `.wheel/history/` missing entirely | `OK — 0 awaiting_user_input events in last 7 days` | matches |

This satisfies SC-007 inline. No standing doctor-subcheck fixture exists in `plugin-kiln/tests/` to extend; spinning up a brand-new doctor-subcheck fixture is out of scope for this PRD per task T064's substrate carve-out (no false-positive: not substrate-blocked, just no existing fixture to attach to).

## Friction notes (FR-009 of build-prd)

### F-1 — Contract D.4 said "awk-extract pattern", precedent was "structural-invariant tripwire"

Contracts/interfaces.md §D.4 prescribed `Invokes the skill (via the awk-extract pattern, sourcing the SKILL.md run block)`. Most existing kiln tests use a different pattern: structural-invariant grep against SKILL.md without execution (e.g. `tests/distill-multi-theme-basic/`, `tests/claude-audit-grounded-finding-required/`, `tests/distill-research-block-propagation/`). I went with the contract's prescription — extract every ```bash``` fence into one concatenated script via `awk '/^```bash$/{flag=1;next} /^```$/{flag=0} flag'`, then `bash` it inside scaffolded `$TMP` dirs. This works AND is more behaviorally meaningful, but it ties the test's PASS/FAIL to the fence layout in SKILL.md (e.g. accidentally renaming a fenced block to ```bash-pseudocode``` would silently break it).

Mitigation already in run.sh: a `extract: SKILL.md bash fences contain all ingestors + report assembly` sanity assertion checks for the literal `WHEEL_TSV` / `GIT_TSV` / `HOOK_TSV` / `REPORT_PATH` / `Verdict-tagging deferred` strings. If a future SKILL.md edit drops one of those anchors, the fixture fails loudly.

**Recommendation for future PRDs**: standardize on either (a) extract-and-run (executable bash + structural anchors), or (b) tripwire-only (structural assertions). Mixing them in one PRD's fixtures forces every implementer to re-derive which substrate the contract author meant.

### F-2 — Concurrent-staging hazard handled by exact-path staging

Per team-lead's brief and retro #187 PI-1, I never ran `git add -A` / `git add .`. Phase 6's commit was staged with explicit paths:
```
git add plugin-kiln/skills/kiln-escalation-audit/SKILL.md \
        plugin-kiln/tests/escalation-audit-inventory-shape/run.sh \
        specs/escalation-audit/tasks.md
```
The version-increment hook had pre-staged `VERSION` + each `plugin-*/.claude-plugin/plugin.json` + each `plugin-*/package.json`. These represent cumulative version-counter bumps from BOTH implementers' edits. I tried `git reset HEAD <those-files>` to leave them for impl-themes-ab's commit, but they re-staged before my `git commit` ran (likely the version-increment hook firing on subsequent edits during the commit pre-flight). They ended up in my Phase 6 commit. This isn't a correctness issue — the version counter is bookkeeping — but it's a small hazard the directive doesn't fully prevent.

**Recommendation**: future concurrent-staging guidance should explicitly note that hook-emitted bookkeeping (VERSION, plugin manifests) will be picked up by whichever implementer commits first, regardless of who triggered the original edit.

### F-3 — kiln-doctor section ordering quirk

`kiln-doctor/SKILL.md` has sections in the order 3a → 3b → 3c → 3d → 3g → 3h → 3f → 3e (i.e., 3e is the terminal report section, 3f is the second-to-last, and 3g/3h were inserted into the middle out of alphabetic order). Task T060 said "AFTER existing `### 3h: Structural hygiene drift` section" — that placement puts the new `### 4` BETWEEN `3h` and `3f`, which works but reads oddly because `3f` follows `4`. I followed the task verbatim. If a follow-on PR cleans up doctor's section ordering, `4` should land AFTER `3f`/`3e`.

### F-4 — Idempotence is real but H1 timestamp + Notes diagnostics are explicitly exempt

NFR-003 says "byte-identical Events section". The skill writes a fresh report file per invocation (filename includes `<timestamp>`), so two runs produce two files. The fixture's idempotence assertion compares the `## Events` block (between `## Events` and `## Notes` markers) byte-identically; H1 + Notes ingestion-error rows are exempt. This matches the spec but is worth flagging because the natural reading of "idempotent skill" is "same file, same bytes."

## Open items / handoff

- T071 (Polish): I need to re-run `/kiln:kiln-test plugin-kiln` to confirm the new fixture lands in the consolidated test report. Doing this immediately after this commit.
- No blockers for impl-themes-ab. Theme C did not touch any file impl-themes-ab edits.
- The skill, the test fixture, and the doctor subcheck are independently shippable. If Theme A or B blocks audit, Theme C can ship alone.
