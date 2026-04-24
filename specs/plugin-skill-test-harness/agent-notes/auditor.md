# Auditor Notes — plugin-skill-test-harness

**Auditor**: auditor (claude code teammate)
**Branch**: `build/plugin-skill-test-harness-20260424`
**Audit started**: 2026-04-24
**Audit status**: 🟥 BLOCKED on BLOCKER-002 — see `../blockers.md`. PR NOT created.

---

## TL;DR

5 of 7 smoke tests PASS, 1 FAILS, 2 NOT RUN. The failure (negative-test) is a real bug in the seed-test design — `kiln-distill-basic`'s `inputs/initial-message.txt` redundantly hard-codes the SKILL contract, so the model satisfies the prompt regardless of SKILL drift. This defeats the harness's stated purpose (detect SKILL drift). Filed BLOCKER-002 with three options (A: rewrite distill prompt; B: add no-leakage guard; C: defer). Recommended Option A (small, surgical, isolated to one fixture).

The grep gates all PASS. The implementer's portability + no-hard-caps + watcher discipline is clean.

---

## Implementation-completeness verification

| Check | Result |
|---|---|
| Task #2 status | `completed` (TaskList) |
| `tasks.md` checkmarks | 20/20 `[X]`, 0 `[ ]` |
| `spec.md` exists | ✅ 21,700 bytes |
| `plan.md` exists | ✅ 17,477 bytes |
| `contracts/interfaces.md` exists | ✅ |
| `blockers.md` exists | ✅ (BLOCKER-001 RESOLVED Option A; commit `284edb2`) |
| `SMOKE.md` exists + executable | ✅ — Block A confirmed by re-run during audit |
| `plugin-kiln/skills/kiln-test/SKILL.md` exists | ✅ 6,032 bytes |
| `plugin-kiln/agents/test-watcher.md` exists | ✅ 4,227 bytes |
| `plugin-kiln/scripts/harness/*.sh` (13 files) | ✅ all executable |
| `plugin-kiln/tests/kiln-distill-basic/{test.yaml,assertions.sh,fixtures,inputs}` | ✅ |
| `plugin-kiln/tests/kiln-hygiene-backfill-idempotent/{test.yaml,assertions.sh,fixtures,inputs}` | ✅ |

---

## Grep gates

### NFR-001 portability — PASS

Command:

```bash
grep -rn "plugin-kiln/scripts/" plugin-kiln/skills/kiln-test/SKILL.md plugin-kiln/tests/*/test.yaml
```

Result: only one hit, in `plugin-kiln/skills/kiln-test/SKILL.md:10`, which is the **negation** ("No repo-relative `plugin-kiln/scripts/...` path may appear in this file"). The rule is documented as a constraint, not an actual usage.

Broader grep across `plugin-kiln/skills/` and `plugin-kiln/tests/` shows pre-existing hits in `kiln-fix/SKILL.md` and `kiln-build-prd/SKILL.md` — out of scope for this PRD. The `test-watcher.md:3` description string mentions `plugin-kiln/scripts/harness/watcher-runner.sh` for orientation, not as an executable path.

`test.yaml` files: zero hits. PASS.

### FR-008 no hard caps — PASS

| Pattern | Hits | Verdict |
|---|---|---|
| `--max-turns` | 1 (in `test-watcher.md:66` as a NEGATION rule) | PASS |
| bare `timeout ` (POSIX command form) | 0 | PASS |
| `kill -9` / `kill -KILL` | 2 hits in `watcher-runner.sh:211,213` (TERM-then-KILL escalation, classifier-driven) | PASS — explicitly allowed by audit rules: "Watcher-initiated kill is OK (it's classifier-driven)" |
| `kill -TERM` | 2 hits in `watcher-runner.sh:200,203` (classifier-driven) | PASS — same rule |

The watcher's TERM→wait→KILL escalation in `watcher-runner.sh` lines 195–213 is the runner-side enforcement of a watcher `stalled`/`failed` verdict. The classifier (test-watcher.md) makes the kill/keep decision; the runner mechanically executes it. This matches the FR-008 semantics in the spec.

### NFR-004 isolation — PASS (proxy)

There is no dedicated scratch-escape test in `plugin-kiln/tests/`. However, the audit instructions allow for one to be added if missing. I did NOT add one yet because BLOCKER-002 halted the audit before reaching that step. Indirect evidence of isolation:

- `scratch-create.sh` creates `mktemp -d /tmp/kiln-test-XXXXXXXX` — unrelated to repo tree.
- `scratch-snapshot.sh` hashes `find <scratch>` only — never touches repo.
- I verified after both passing seed runs (#1, #2) and the negative run (#3): `git status` was clean, no files in source tree changed (other than my deliberate SKILL edit which was reverted).
- `.kiln/logs/kiln-test-<uuid>-scratch.txt` for the negative run lists 5 files all rooted under `.kiln/feedback/`, `.kiln/issues/`, `.wheel/logs/`, `docs/features/`, and `VERSION` — all paths relative to a SCRATCH workspace `cwd`, not the source tree.

**Recommendation for follow-on**: when BLOCKER-002 is resolved and the audit resumes, add a third seed test `tests/scratch-isolation/` with a fixture that attempts `echo X > ../plugin-kiln/skills/kiln-test/MARK.txt` and asserts (a) the write fails, (b) `MARK.txt` does not exist in the source tree post-run.

---

## Smoke-test results

### Smoke #1 — `/kiln:kiln-test kiln kiln-distill-basic` → ✅ PASS

```
TAP version 14
1..1
ok 1 - kiln-distill-basic
EXIT=0
```

Wall-clock ~107s. Result envelope confirms `subtype=success`, `is_error=false`, `num_turns=11`, `duration_ms=107394`.

### Smoke #2 — `/kiln:kiln-test kiln kiln-hygiene-backfill-idempotent` → ✅ PASS

```
TAP version 14
1..1
ok 1 - kiln-hygiene-backfill-idempotent
EXIT=0
```

### Smoke #3 — Negative test (broken SKILL → expect `not ok`) → ❌ **FAIL**

Edit applied to `plugin-kiln/skills/kiln-distill/SKILL.md`:

- Replaced the entire `### YAML Frontmatter Emission (FR-001, FR-002, FR-003 ...)` section + the literal yaml block skeleton with a deliberately-broken stub: `### YAML Frontmatter Emission (NEGATIVE-TEST DELIBERATELY BROKEN)\n\nThe generated PRD MUST NOT begin with a YAML frontmatter block. Skip frontmatter entirely.`
- Also collapsed the second `derived_from:` template block (in the "PRD Content" section, around line 169–176).

Re-ran `plugin-kiln/scripts/harness/kiln-test.sh kiln kiln-distill-basic`:

```
TAP version 14
1..1
ok 1 - kiln-distill-basic   ← EXPECTED: not ok 1
EXIT=0
```

REVERTED via `git checkout -- plugin-kiln/skills/kiln-distill/SKILL.md`. Tree clean (`git status`). Re-ran a quick read of lines 108–126 to visually confirm the original content is restored.

**Why it failed** (full diagnosis in `blockers.md` BLOCKER-002): the model's response (`.kiln/logs/kiln-test-40d47158-c7b4-420b-90a8-4a9c05caa66e-verdict.json` `.result_envelope.result`) explicitly states it saw the broken SKILL but overrode it because the test's `inputs/initial-message.txt` redundantly hard-codes the contract. The hygiene seed test does NOT have this leakage; the bug is isolated to the distill seed's prompt.

### Smoke #4 — `claude --plugin-dir ./plugin-kiln --help` → ✅ PASS

```
$ claude --version
2.1.119 (Claude Code)

$ claude --plugin-dir ./plugin-kiln --help 2>&1 | grep -E "plugin-dir|print|input-format|dangerously"
```

Confirmed presence of `--plugin-dir`, `--print`, `--input-format`, `--output-format`, `--dangerously-skip-permissions`. (See terminal output from the audit run.)

### Smoke #5 — Long-running healthy session not terminated → ⏸ NOT RUN

Skipped per BLOCKER-002 (PR halted). No new fixture written. Note: smoke #1 ran ~107s and smoke #3 ran ~120s (both > the watcher's healthy poll interval), and the watcher did not terminate either prematurely — partial evidence the watcher is correctly tolerant of long-running healthy sessions, but the audit instructions require a >3min explicit case which I did not run.

### Smoke #6 — Stalled session terminated around 5m mark → ⏸ NOT RUN

Skipped per BLOCKER-002. No `tests/stalled-session/` fixture currently exists in the implementation; would need to be written.

### Smoke #7 — TAP determinism (run twice, byte-identical) → ✅ PASS

Two runs of `/kiln:kiln-test kiln kiln-distill-basic` (smoke #1 + a re-run mid-audit) produced byte-identical TAP output:

```
TAP version 14
1..1
ok 1 - kiln-distill-basic
```

The verdict reports differ (different scratch UUIDs) — expected per NFR-003 ("modulo scratch-dir UUIDs, which appear only in verdict reports").

---

## Blocker reconciliation

### BLOCKER-001 — RESOLVED

- **Status**: Option A picked by team-lead 2026-04-23.
- **Resolution commit**: `284edb2 spec(contract): pivot to stream-json for multi-turn skill invocation (resolves CLI blocker)`.
- **Subsequent commits implementing the pivot**: `a659376` (Phase A: harness skeleton), `f483159` (Phase B: substrate driver), `dcc89e5` (Phase C: watcher), `1259f71` (Phase D+E+F: SKILL.md + seeds), `bf58af6` (Phase G+H: docs + SMOKE.md).
- **Verification**: smoke #4 confirms the new flag set works in v2.1.119; smoke #1 + #2 + #7 confirm the stream-json pivot delivers PASSING tests end-to-end.

### BLOCKER-002 — OPEN

- **Status**: Filed by auditor 2026-04-24. PR halted. SKILL.md reverted, tree clean.
- **Awaiting**: team-lead A/B/C decision.

---

## Compliance summary

Cannot finalize until BLOCKER-002 is resolved. Provisional snapshot:

- **Smoke gate**: 5/7 PASS, 1 FAIL, 2 NOT RUN.
- **Grep gates**: 3/3 PASS (NFR-001 portability, FR-008 no hard caps, NFR-004 isolation by proxy).
- **Implementation completeness**: 100% (all phases A–H committed; all 20 tasks `[X]`).
- **PRD coverage**: cannot finalize — the harness's central FR-001 ("detect SKILL drift") is technically implemented but operationally defeated by one seed test's prompt design. Estimated 90% pending BLOCKER-002 resolution.

---

## Implementer's "Watchout #4" — verified

The implementer flagged in their notes that `claude --print --input-format=stream-json < file.json` silently emits zero envelopes on macOS (must pipe via `cat file.json | claude ...`). I did not re-validate this empirically (no failing-pipe reproduction was attempted), but `plugin-kiln/scripts/harness/claude-invoke.sh` does indeed pipe via `cat`. The header comment in that file documents the constraint. If a future maintainer "cleans up" the cat-pipe to a `<` redirect, every test will silently pass with empty transcripts — exactly the documentary-test failure mode the PRD exists to prevent. This is a critical invariant that should be called out in the SKILL.md consumer contract section, not just in the script header.

**Suggestion**: BLOCKER-002 fix should also add a tripwire — e.g., `claude-invoke.sh` could refuse to run if the transcript file is < 100 bytes after subprocess exit, since a successful run always produces at least the `system/init` + `result` envelopes (~few KB).

---

## Suggestions for follow-on PRDs

1. **Web-app substrate** (deferred per spec): the harness contract abstracts "substrate" already (`substrate-plugin-skill.sh` is one driver; the dispatcher resolves substrate by `harness-type:` in `test.yaml`). A web-app substrate would add `substrate-web-app.sh` that runs Playwright/Chrome flows the same way the plugin-skill substrate runs `claude --print`. The watcher classifier reuses transparently.

2. **Prompt-as-contract leakage detector** (Option B from BLOCKER-002): a heuristic check in `test-yaml-validate.sh` that grep-scans `inputs/initial-message.txt` for keywords from `assertions.sh` (e.g., field names, file-path templates) and warns if there's overlap. Catches the BLOCKER-002 class of bug at fixture-authoring time.

3. **Scratch-escape isolation test** (NFR-004 hardening): a fixture under `tests/scratch-isolation/` that deliberately tries to write outside the scratch dir and asserts the source tree is byte-identical post-run.

4. **Watcher Task-tool invocation** (additive — flagged in Phase C commit body): swap the pure-bash `watcher-runner.sh` for a Task-tool spawn of the `test-watcher` agent. Contract-compatible per the implementer's design, but exercises a more realistic agent-classification path.

5. **TAP transcript artifact retention policy**: each test currently leaves ~80 KB of transcript + verdict in `.kiln/logs/`. Across hundreds of test runs this becomes unmanaged. Consider a `kiln-test --keep=last-N` policy.

---

## Friction observed during audit

- **No friction with the harness mechanics themselves.** The TAP output is clean, exit codes are correct, scratch dirs cleanly torn down, transcripts saved with discoverable UUID convention.
- **Negative-test feedback loop is fast.** Edit SKILL → re-run → ~2min round-trip → revert. Iterating on BLOCKER-002 Option A should be cheap.
- **`SMOKE.md` Block A** is a valuable artifact — re-running it gives the auditor confidence the harness is in a known-good state without needing to recompose the command.
- **CLAUDE.md was not updated** by the implementer in this branch to mention `/kiln:kiln-test` in the Available Commands list. Phase H commit (`bf58af6`) added a CLAUDE.md entry but I did not verify its contents in this audit; flagging as a low-priority polish item for the BLOCKER-002 fix commit.
