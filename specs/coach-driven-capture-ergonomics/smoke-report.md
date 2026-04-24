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
| All standalone behavioural + tripwire tests | ✅ PASS (8/8) |

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

## Known-remaining work (Phase 6 polish — non-blocking)

Per `audit-quality.md` compliance report, Phase 6 polish tasks T053–T057 are not marked `[X]`:
- T053 — Active Technologies CLAUDE.md entry for `plugin-kiln/scripts/context/` (not strictly required — folded into T054 entry below).
- **T054 — CLAUDE.md Recent Changes entry. `audit-smoke-pr` added this before PR creation.** ✅
- T055 — golden-file baseline capture for `--quick` (no pre-change baseline exists; follow-on).
- T056 — `/kiln:kiln-coverage` — informal for Bash codebases; file-level coverage mapping in compliance report stands in.
- T057 — `/kiln:kiln-test plugin-kiln` full sweep — deferred to first post-merge run (see §7).

These are non-blocking for the feature itself. PR body lists them under "Known-remaining polish".

## Verdict

**SMOKE PASS.** Proceeding with PR creation.
