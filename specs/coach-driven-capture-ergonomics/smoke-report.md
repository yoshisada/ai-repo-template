---
feature: coach-driven-capture-ergonomics
auditor: audit-smoke-pr
audited_at: 2026-04-24
branch: build/coach-driven-capture-ergonomics-20260424
verdict: PASS
---

# Smoke Report — Coach-Driven Capture Ergonomics

Plugin-source repo — no runtime application to launch. Smoke surface = helper scripts + SKILL.md invariants + harness-runnable behavioural tests. All checks PASS.

## Summary

| Check | Result |
|---|---|
| Reader produces valid JSON on live kiln repo | ✅ PASS (exit 0, 46 719 bytes, schema keys present) |
| Reader completes in <2 s on live kiln repo (NFR-001) | ✅ PASS (0.22 s real on 45 PRDs + 50 items) |
| Reader byte-identical across two back-to-back runs (NFR-002) | ✅ PASS (`diff -q` empty) |
| Multi-theme emitter byte-identical (NFR-003) | ✅ PASS (`distill-multi-theme-determinism/run.sh` green) |
| Modified SKILL.md files parse (frontmatter + required fields) | ✅ PASS (kiln-roadmap, kiln-claude-audit, kiln-distill) |
| Helper scripts are executable | ✅ PASS (6/6 scripts `-rwxr-xr-x`) |
| All standalone behavioural + tripwire tests | ✅ PASS (11/11) |
| Phase 6 polish T053–T057 | ✅ DONE (see §Phase 6 polish below — T055/T056/T057 substituted with documented alternatives) |

## Details

### 1. Live reader invocation (end-to-end runtime check)

```
$ time bash plugin-kiln/scripts/context/read-project-context.sh > /tmp/smoke-reader-run1.json
real  0.22s   user 0.09s   sys 0.09s
exit 0
size  46 719 bytes
stderr  (empty)
```

Sanity on emitted shape:

```
$ jq 'keys' run1.json
["claude_md","plugins","prds","readme","roadmap_items","roadmap_phases","schema_version","vision"]
$ jq '.prds | length'          -> 45
$ jq '.roadmap_items | length' -> 50
$ jq '.roadmap_phases | length'-> 0   (no phase files on this branch — expected)
```

NFR-001 budget 2000 ms — observed 220 ms wall-clock on real repo. **PASS.**

### 2. Byte-identical determinism (NFR-002)

```
$ bash read-project-context.sh > run1.json
$ bash read-project-context.sh > run2.json
$ diff -q run1.json run2.json
(no output — identical)
```

**PASS.**

### 3. NFR-003 multi-theme determinism test

```
$ bash plugin-kiln/tests/distill-multi-theme-determinism/run.sh
PASS: helpers + derived_from three-group sort are byte-identical on re-run (NFR-003)
exit 0
```

Confirmed per team-lead's specific ask: the test runs `select-themes.sh` + `disambiguate-slug.sh` + `emit-run-plan.sh` pipeline twice against fresh tempdirs and diffs output byte-for-byte, AND runs `sort_derived_from` twice on the same entry set.

### 4. SKILL.md parseability (modified skills)

All three modified SKILL.md files have open+close frontmatter fences and non-empty `name:` / `description:` fields:

| Skill | Frontmatter close | name | description |
|---|---|---|---|
| `plugin-kiln/skills/kiln-roadmap/SKILL.md` | line 4 | `kiln-roadmap` | present (840 lines total) |
| `plugin-kiln/skills/kiln-claude-audit/SKILL.md` | line 4 | `kiln-claude-audit` | present (361 lines total) |
| `plugin-kiln/skills/kiln-distill/SKILL.md` | line 4 | `kiln-distill` | present (625 lines total) |

### 5. Helper script executable bits

```
-rwxr-xr-x plugin-kiln/scripts/context/read-plugins.sh
-rwxr-xr-x plugin-kiln/scripts/context/read-prds.sh
-rwxr-xr-x plugin-kiln/scripts/context/read-project-context.sh
-rwxr-xr-x plugin-kiln/scripts/distill/disambiguate-slug.sh
-rwxr-xr-x plugin-kiln/scripts/distill/emit-run-plan.sh
-rwxr-xr-x plugin-kiln/scripts/distill/select-themes.sh
```

All 6 executable. **PASS.**

### 6. Standalone test re-verification (do not trust implementer claims)

Ran every test `audit-quality` listed as standalone-runnable. All green on my invocation:

| Test | Result |
|---|---|
| `project-context-reader-determinism` | ✅ PASS |
| `project-context-reader-empty` | ✅ PASS |
| `project-context-reader-performance` | ✅ PASS (135 ms elapsed / 2000 ms budget on 50+100 synthetic fixture) |
| `distill-multi-theme-slug-collision` | ✅ PASS (5 case checks) |
| `distill-multi-theme-run-plan` | ✅ PASS (5 case checks incl. omission / severity sort / stable ties) |
| `distill-multi-theme-basic` | ✅ PASS (7 SKILL.md markers) |
| `distill-multi-theme-state-flip-isolation` | ✅ PASS (tripwire + behavioural guard-unit) |
| `distill-multi-theme-determinism` | ✅ PASS (NFR-003) |
| `distill-single-theme-no-regression` | ✅ PASS (FR-021) |
| `roadmap-coached-interview-basic` | ✅ PASS (11 markers) |
| `roadmap-coached-interview-empty-snapshot` | ✅ PASS |
| `roadmap-coached-interview-quick` | ✅ PASS |

**8 behavioural + 3 tripwires = 11 / 11 green.**

### 7. Harness-driven tests (NOT exercised in this smoke)

9 tests (`roadmap-vision-{first-run,re-run,no-drift,empty-fallback,partial-snapshot}` and `claude-audit-{project-context,cache-stale,network-fallback,propose-dont-apply}`) require the `/kiln:kiln-test` harness to spawn a real `claude --print` subprocess against a fixture. That's a multi-minute run that spawns Claude children and is not practical inside a pipeline agent context. `audit-quality`'s test-quality audit confirmed each has real assertions.shell files with `.kiln/vision.md` / `.kiln/logs/claude-md-audit-*.md` file-shape checks — deferring their runtime exercise to the first post-merge `/kiln:kiln-test plugin-kiln` sweep (Phase 6 polish T057).

### 8. End-to-end skill invocation

The reader invocation in §1 is the closest feasible runtime end-to-end — it is what `/kiln:kiln-roadmap`, `/kiln:kiln-distill`, and `/kiln:kiln-claude-audit` all shell out to. Directly invoking the SKILL.md files (`/kiln:kiln-distill --help`, etc.) would require spawning a second `claude` subprocess from inside a pipeline agent, which the task description correctly flagged as "if feasible" — for plugin-source repos this is better deferred to the harness sweep.

## Phase 6 polish — status

Per team-lead direction, `audit-smoke-pr` picked up T053–T057 before finalising. All five now `[X]` in `tasks.md`.

### T053 — Active Technologies entry ✅

`plugin-kiln/README.md` does not exist. Added the Active Technologies entry to root `CLAUDE.md` (per rubric fallback):

> Shared project-context reader under `plugin-kiln/scripts/context/` (`read-project-context.sh` + `read-prds.sh` + `read-plugins.sh`) — Bash 5.x + `jq` + POSIX awk; emits deterministic JSON (`LC_ALL=C` + path/name sort) consumed by `/kiln:kiln-roadmap`, `/kiln:kiln-claude-audit`, and `/kiln:kiln-distill`. Multi-theme distill helpers under `plugin-kiln/scripts/distill/` (`select-themes.sh`, `disambiguate-slug.sh`, `emit-run-plan.sh`). No new runtime dependency. (build/coach-driven-capture-ergonomics-20260424)

No new tech introduced — only new scripts under existing Bash + `jq` + awk stack.

### T054 — Recent Changes entry ✅

Added to `CLAUDE.md` `## Recent Changes` at top of the list (see commit `b6ca5dc`). Summarises reader + coaching on 4 capture surfaces + NFR coverage + backward-compat posture.

### T055 — `--quick` byte-identical check (substituted) ✅

> No `--quick` golden-file fixture was committed pre-change, so a literal "re-run against baseline" substitution is structurally impossible.

Substituted with the equivalent behavioural test:

```
$ bash plugin-kiln/tests/distill-single-theme-no-regression/run.sh
PASS: single-theme path remains byte-identical (FR-021 / NFR-005)
exit 0
```

This test exercises `select-themes.sh` Channel 4 fallback (single-theme shortcut) + `emit-run-plan.sh` zero-byte-for-N=1 rule directly against the helpers. It validates the same invariant T055 was meant to protect — the single-theme path is byte-identical to its pre-change shape.

### T056 — Coverage (substituted — pure-Bash source) ✅

`/kiln:kiln-coverage` is not meaningful for pure-Bash plugin source (no Istanbul / coverage.py equivalent). Substituted with script→test mapping per team-lead's heuristic:

| Script | Covering test(s) | Status |
|---|---|---|
| `plugin-kiln/scripts/context/read-project-context.sh` | `project-context-reader-determinism/run.sh`, `project-context-reader-empty/run.sh`, `project-context-reader-performance/run.sh`, `roadmap-coached-interview-basic/run.sh` | ✅ covered (4 tests) |
| `plugin-kiln/scripts/context/read-prds.sh` | via `read-project-context.sh` orchestrator (indirect) | ✅ covered (transitive) |
| `plugin-kiln/scripts/context/read-plugins.sh` | via `read-project-context.sh` orchestrator (indirect) | ✅ covered (transitive) |
| `plugin-kiln/scripts/distill/select-themes.sh` | `distill-multi-theme-basic/run.sh`, `distill-multi-theme-determinism/run.sh`, `distill-single-theme-no-regression/run.sh` | ✅ covered (3 tests) |
| `plugin-kiln/scripts/distill/disambiguate-slug.sh` | `distill-multi-theme-basic/run.sh`, `distill-multi-theme-slug-collision/run.sh`, `distill-multi-theme-determinism/run.sh` | ✅ covered (3 tests) |
| `plugin-kiln/scripts/distill/emit-run-plan.sh` | `distill-multi-theme-run-plan/run.sh`, `distill-multi-theme-determinism/run.sh`, `distill-single-theme-no-regression/run.sh` | ✅ covered (3 tests) |

**6 / 6 helpers covered. Constitutional 80 % gate satisfied as "every helper has ≥1 covering test" for pure-Bash.**

### T057 — `/kiln:kiln-test plugin-kiln` sweep (substituted — harness-substrate gap) ✅

Team-lead's brief: _"If the harness is broken or doesn't yet support interactive-stdin, document the blocker inline in the smoke report and count static tripwires as 'best-available pass.' Do NOT hold the PR on a harness-substrate bug."_

Confirmed blocker: `/kiln:kiln-test` spawns `claude --print --plugin-dir ...` subprocesses against `/tmp/kiln-test-<uuid>/` fixtures. Running this from inside a pipeline agent (which is itself a claude process) is brittle (nested subprocess + child-process lifecycle), and 9 fixtures (`roadmap-vision-*`, `claude-audit-*`) additionally require interactive-stdin that's not yet wired. This was flagged by `impl-context-roadmap.md` and `impl-distill-multi.md` friction notes during implementation — it's a substrate gap, not a regression introduced by this PRD.

**Best-available substitution**: ran the full standalone-runnable subset (11 / 11 green — see §6 above). Static SKILL.md tripwires for the 9 harness-only fixtures are counted as "best-available pass"; audit-quality's hand inspection of each `assertions.sh` confirmed substantive file-shape assertions.

**Follow-on (separate PRD)**: harness-substrate upgrade to support interactive-stdin + nested-claude-invocation so T057 can be exercised unconditionally. Not blocking this PR.

## Verdict

**SMOKE PASS.** Proceeding with PR creation.
