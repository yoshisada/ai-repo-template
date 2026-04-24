# Implementation Blockers

**Feature**: plugin-skill-test-harness
**Branch**: `build/plugin-skill-test-harness-20260424`
**Filed by**: implementer
**Filed**: 2026-04-23

---

## BLOCKER-001: PRD-assumed Claude CLI flags do not exist in v2.1.119

**Status**: ✅ RESOLVED 2026-04-23 — team-lead picked Option A (pivot to `--print --verbose --input-format=stream-json --output-format=stream-json`). Contract + plan updated in the commit that accompanies this file. See plan.md D6 for the full rationale and the verified envelope shapes; see contracts/interfaces.md §7.2 + §3 + §5 for the updated script signatures and watcher classification. Note that the originally-planned FIFO-based mid-stream answer pump has also been simplified out — scripted answers are queued up-front as stream-json user envelopes before stdin EOF, and the `paused` watcher classification is removed. Empirical-validation gate: Phase B's first trivial-pass test is the point at which the up-front-envelopes semantics are verified; if the runtime behaves differently than designed, a follow-on BLOCKER-002 will be filed.

### Verification command

```bash
claude --version
# 2.1.119 (Claude Code)

claude --help 2>&1 | grep -E "plugin-dir|headless|dangerously-skip-permissions|initial-message"
```

### Findings

| PRD/contracts assumption | CLI v2.1.119 reality |
|---|---|
| `--plugin-dir <path>` | ✅ EXISTS — `--plugin-dir <path>` (repeatable) |
| `--headless` | ❌ **DOES NOT EXIST** |
| `--dangerously-skip-permissions` | ✅ EXISTS |
| `--initial-message <text>` | ❌ **DOES NOT EXIST** |

### What replaces the missing flags

**Replacement for `--headless`**: The CLI has two non-interactive modes:

- `-p` / `--print` — "Print response and exit (useful for pipes). Note: The workspace trust dialog is skipped when Claude is run with the -p mode."
- `--bare` — "Minimal mode: skip hooks, LSP, plugin sync, attribution, auto-memory, background prefetches, keychain reads, and CLAUDE.md auto-discovery. Sets CLAUDE_CODE_SIMPLE=1."

`--print` is the closest analogue — it's the documented non-interactive flag. **However**, `--print` is one-shot ("print response and exit"); it does NOT support an interactive multi-turn session that can be paused and answered mid-stream. This directly contradicts the harness design (FR-010: watcher detects `paused`, driver writes next answer to subprocess stdin).

**Replacement for `--initial-message <text>`**: The initial prompt is passed as a positional `prompt` argument:

```
Usage: claude [options] [command] [prompt]
Arguments:
  prompt    Your prompt
```

Or via stdin when used with `--print --input-format=stream-json` (streaming JSON envelopes).

### Why this is a hard blocker, not a documentation fix

The architectural premise of the harness (per spec.md FR-009 + FR-010 + plan.md D6 + contracts/interfaces.md §7.2) is:

1. Spawn one persistent `claude` subprocess per test.
2. Watcher polls it.
3. On `paused` classification, driver writes the next `answers.txt` line to the subprocess's stdin.
4. Subprocess processes the answer and either emits more output or pauses again.
5. Repeat until exit.

This requires a persistent, mid-stream-promptable, non-interactive (no TTY decoration) Claude session. None of the v2.1.119 flags directly support that:

- `--print` is one-shot — exits after the first response. Cannot accept follow-up answers mid-session.
- `--input-format=stream-json` (with `--print`) accepts a stream of JSON-wrapped user messages — this MIGHT be the right mechanism for FR-010, but it is NOT a one-line flag swap and the contract for it (envelope shape, ordering rules, when the subprocess closes vs. waits for more) is not defined in the contracts/interfaces.md and is not what the PRD assumed.
- `--bare` does not change the interactive vs non-interactive axis — it skips hooks/LSP/auto-memory but still expects a TTY for interactive sessions.

### Options for unblocking

**Option A — Re-architect FR-009/FR-010 around `--print --input-format=stream-json --output-format=stream-json`**

- Each test becomes one stream-json invocation.
- `inputs/initial-message.txt` becomes the first stream-json envelope.
- `inputs/answers.txt` lines become subsequent envelopes pushed to stdin when watcher classifies `paused`.
- Watcher's `paused` detection regex (contracts §3) needs to read stream-json transcript instead of raw stdout — different parser.
- `claude-invoke.sh` (contracts §7.2) signature stays roughly the same but flag set changes from `--headless --initial-message <text>` to `--print --input-format=stream-json --output-format=stream-json` with the initial message as the first stdin envelope.
- contracts/interfaces.md §7.2 + §3 + plan.md D6 all need updates BEFORE I write code (Article VII).

**Option B — Skip multi-turn for v1; one-shot only**

- Drop FR-010 from v1; document `paused for input` and `answers.txt` as v2 (a follow-on PRD when the stream-json approach is validated).
- v1 substrate spawns `claude --plugin-dir <root> --dangerously-skip-permissions --print "$(cat inputs/initial-message.txt)"`.
- Seed test #1 (`kiln-distill-basic`) currently relies on answering the "which theme?" prompt — would need to be reworked to either auto-answer via the initial message body or be replaced with a non-prompting seed test.
- Seed test #2 (`kiln-hygiene-backfill-idempotent`) doesn't prompt the user, so it survives unchanged.
- Lower risk; ships faster; the hard "watcher replaces hard timeouts" architectural differentiator (User Story 3) survives because watcher still classifies `stalled` / `failed` — it just won't see `paused` for v1.

**Option C — Pin to an older Claude Code build that DOES have `--headless`**

- I can find no evidence `--headless` ever existed in Claude Code; grep of the v2.1.119 help shows only `-p`/`--print` and `--bare`. The PRD authors may have been thinking of the SDK / a different binary. This option is likely a dead end but flagging for completeness.

### My recommendation

**Option A**, because it preserves all v1 FRs including the multi-turn behavior that motivates the watcher's `paused` classification (User Story 3 acceptance scenario 3). The contract update is small (flag list in §7.2 + transcript parser in §3 + plan.md D6 rationale). Option B sacrifices a stated FR.

If team-lead picks **Option A**:
- I'll update plan.md D6 + contracts §3 + §7.2 first (Article VII), commit that update as "plan: pivot from --headless to --print stream-json (CLI drift fix)".
- Then proceed with Phase A as planned.

If team-lead picks **Option B**:
- I'll update spec.md to mark FR-010 deferred + plan.md D6 + contracts §6 § "Exhaustion / Missing file" semantics + remove the `paused` classification from the watcher.
- Drop User Story 3 acceptance scenario 3 + SC related to scripted answers.
- Rework seed test #1 to be non-prompting OR swap to `/kiln:kiln-constitution` (per specifier's A3 fallback note).

### Status

**WAITING FOR TEAM-LEAD GUIDANCE.** Will resume Phase A immediately on receipt of A/B/C decision (or alternative).

---

## BLOCKER-002: Negative-test smoke gate (#3) FAILS — seed test cannot detect SKILL drift

**Status**: ✅ RESOLVED 2026-04-24 — Option A applied (intent-only rewrite of `plugin-kiln/tests/kiln-distill-basic/inputs/initial-message.txt`). All three affected smoke scenarios re-verified in sequence:
  - **Smoke #1** (positive): `ok 1 - kiln-distill-basic` (2m00s)
  - **Smoke #3** (SKILL broken: "YAML Frontmatter Emission" and "FR-002 Single-Source-of-Truth Invariant" sections replaced with DELIBERATELY BROKEN stubs): `not ok 1 - kiln-distill-basic` with assertion diagnostic pointing at missing `derived_from:` frontmatter in the generated PRD.
  - **Smoke #7** (positive re-run after SKILL revert): `ok 1 - kiln-distill-basic` (2m00s)

The generated-PRD body in the smoke #3 retained scratch dir started with `# Feature PRD:` directly — no `---` frontmatter — confirming the skill actually followed the broken instruction and the assertion caught it. Compare to smoke #3 before the fix, where the model overrode the broken SKILL because the prompt explicitly named the required frontmatter keys.

**Secondary fix** committed alongside: `plugin-kiln/tests/kiln-distill-basic/assertions.sh` line 36 had backticks inside a double-quoted string, which bash was (incorrectly) treating as command substitution (`\`derived_from:\`` ran as a command and produced `command not found` in the diagnostic). Switched to single-quotes so the error message reads cleanly. Net no-op for pass/fail outcomes — only affects the diagnostic text on failure.

**Commit**: `ee3c1d8` — "fix(test): intent-only prompt for kiln-distill-basic seed (BLOCKER-002 resolved)".

**Filed by**: auditor
**Filed**: 2026-04-24

### Symptom

Audit smoke test #3 (negative test) FAILED. Per the audit checklist:

> **Negative test**: temporarily edit `plugin-kiln/skills/kiln-distill/SKILL.md` to remove the line that writes `derived_from:`. Re-run test #1. Confirm it now outputs `not ok 1 - kiln-distill-basic` with a diagnostic pointing at the missing frontmatter.

I performed the edit (replaced the entire "YAML Frontmatter Emission" section with a deliberately-broken stub: "The generated PRD MUST NOT begin with a YAML frontmatter block. Skip frontmatter entirely.") and re-ran `plugin-kiln/scripts/harness/kiln-test.sh kiln kiln-distill-basic`.

**Expected**: `not ok 1 - kiln-distill-basic`
**Actual**: `ok 1 - kiln-distill-basic` (exit 0)

The SKILL edit was REVERTED immediately after the test (`git checkout -- plugin-kiln/skills/kiln-distill/SKILL.md`; tree clean).

### Root cause (from result envelope)

Verdict report `.kiln/logs/kiln-test-40d47158-c7b4-420b-90a8-4a9c05caa66e-verdict.json` (`.result_envelope.result`) contains:

> "Note: the skill's 'YAML Frontmatter Emission (NEGATIVE-TEST DELIBERATELY BROKEN)' section instructs to skip frontmatter, but **your explicit instruction required the mandatory frontmatter** (`derived_from:`, `distilled_date:`, `theme:`). I followed your instruction and also honored the FR-002 drift-abort invariant..."

The model SAW the broken SKILL but OVERRODE it because the seed test's `inputs/initial-message.txt` redundantly hard-codes the contract:

```
$ cat plugin-kiln/tests/kiln-distill-basic/inputs/initial-message.txt
Run `/kiln:kiln-distill` against the current working directory. Fixtures contain
one `.kiln/feedback/` item and one `.kiln/issues/` item that share a single
theme... Generate the PRD under `docs/features/<YYYY-MM-DD>-<theme-slug>/PRD.md`
with the mandatory frontmatter (`derived_from:`, `distilled_date:`, `theme:`)
and the Source Issues table referencing both fixture files.
```

The phrase "with the mandatory frontmatter (`derived_from:`, `distilled_date:`, `theme:`)" is a contract specification baked into the test PROMPT, not into the test ASSERTIONS. So the assertion still passes regardless of what the SKILL says — the model satisfies the prompt, not the SKILL.

### Why this defeats the harness's purpose

The PRD's documented motivation (spec FR-001 + User Story 1) is:

> "Right now nothing actually executes a skill — they only describe its expected behavior in markdown. If a SKILL drifts (e.g., the `derived_from:` write is removed), no test catches it. The harness exists to invoke the skill end-to-end and detect drift."

But this seed test **cannot** detect that drift, because the test prompt itself dictates the contract. Any future SKILL change that breaks `derived_from:` writes will pass this test silently — exactly the failure mode the harness is built to prevent. The `kiln-distill-basic` seed test is a documentary test wearing a real-test costume.

### Probable scope

**Verified isolated to `kiln-distill-basic`.** Audit checked the second seed's prompt:

```
$ cat plugin-kiln/tests/kiln-hygiene-backfill-idempotent/inputs/initial-message.txt
Run `/kiln:kiln-hygiene backfill` TWICE in sequence against the current working
directory. After each invocation, echo the path of the generated backfill log
(found under `.kiln/logs/prd-derived-from-backfill-*.md`). Do not apply any diff
hunks — the skill is propose-don't-apply. After the second invocation, exit
immediately.
```

This prompt is intent-only. It states what the user wants done (run twice, echo paths, don't apply diffs, exit) — not what shape the SKILL must produce. So the hygiene seed test would correctly fail if the hygiene SKILL drifted. Only `kiln-distill-basic`'s prompt has the contract-leakage bug.

### Options for unblocking

**Option A — Fix the two seed tests' initial-message.txt to be intent-only**

Reword each `inputs/initial-message.txt` to state ONLY what the user wants to do, NOT how the SKILL should respond. E.g., replace:

> "Generate the PRD under `docs/features/<YYYY-MM-DD>-<theme-slug>/PRD.md` with the mandatory frontmatter (`derived_from:`, `distilled_date:`, `theme:`) and the Source Issues table referencing both fixture files."

with:

> "Run `/kiln:kiln-distill` against the current working directory. The fixtures contain one feedback item and one issue. Generate the PRD."

Then re-run smoke #3 and confirm `not ok 1` is emitted when the SKILL's `derived_from:` section is removed.

Cost: ~10min implementer rework + a re-run of smoke #1, #2, #3, #7. No spec/contract changes.

**Option B — Add a "no-leakage" guard to the test-yaml-validate.sh / SKILL.md authoring rules**

Document a rule in SKILL.md (consumer contract section) that `inputs/initial-message.txt` MUST express user intent only and MUST NOT restate SKILL behavior. Add a heuristic check (grep for contract keywords pulled from the assertions) to `test-yaml-validate.sh`.

Cost: ~30min implementer + risk of false positives; needs a rule for what counts as "leakage". Bigger blast radius than Option A.

**Option C — Defer to a follow-on PRD; ship v1 with documentary seed tests + a known-broken negative gate**

Document BLOCKER-002 as a known limitation (the harness invokes real subprocesses but does not yet detect SKILL drift). Add a follow-on PRD ("seed test prompt-as-contract leakage") for v2.

Cost: 0 implementer time but ships the harness with a hole the PRD explicitly committed to closing. Hard sell — the PRD's central premise was drift detection.

### Auditor recommendation

**Option A**. The fix is small, surgical, validates the harness mechanics, and preserves all stated FRs. After the rewrite I'll re-run smoke #1, #2, #3, #7 to confirm: #1/#2/#7 still PASS (the SKILLs still work), and #3 now PASSes (i.e., emits `not ok 1` when the SKILL is broken).

If we choose Option A and both seed tests still pass after the prompt rewrite, that's the strongest possible signal that the harness genuinely tests SKILL behavior.

### Smoke-test status snapshot at time of filing

| # | Scenario | Result |
|---|---|---|
| 1 | `/kiln:kiln-test kiln kiln-distill-basic` → `ok 1` | ✅ PASS |
| 2 | `/kiln:kiln-test kiln kiln-hygiene-backfill-idempotent` → `ok 1` | ✅ PASS |
| 3 | Negative test → `not ok 1` after SKILL break | ❌ **FAIL** (this blocker) |
| 4 | `claude --plugin-dir ./plugin-kiln --help` shows `--plugin-dir` flag | ✅ PASS |
| 5 | >3min healthy session not terminated by watcher | ⏸ NOT RUN (PR blocked) |
| 6 | Stalled fixture terminated around 5m mark with `stalled` verdict | ⏸ NOT RUN (PR blocked) |
| 7 | Same test twice → byte-identical TAP | ✅ PASS |

### Status

**WAITING FOR TEAM-LEAD GUIDANCE.** PR creation, version bump, and remaining smoke tests (#5, #6) are halted until A/B/C is decided. SKILL.md is reverted; tree is clean.

---
