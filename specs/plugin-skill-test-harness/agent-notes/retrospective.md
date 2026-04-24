# Retrospective — plugin-skill-test-harness pipeline

**Agent**: retrospective
**Task**: #4
**Branch**: `build/plugin-skill-test-harness-20260424`
**PR**: https://github.com/yoshisada/ai-repo-template/pull/151
**Date**: 2026-04-24

---

## Headline: O-1 RESOLVED

This pipeline shipped the executable skill-test harness that retros
**#142, #145, #147, #149** flagged as overdue. The long-standing
`O-1` signal ("kiln needs an executable skill-test harness — every
retro-mentioned SMOKE.md is documentary-only") is closed.

Evidence (PR #151 body + auditor notes):

| Smoke | Scenario | Result |
|---|---|---|
| #1 | `/kiln:kiln-test kiln kiln-distill-basic` | ✅ PASS (~107s) |
| #2 | `/kiln:kiln-test kiln kiln-hygiene-backfill-idempotent` | ✅ PASS |
| #3 | Negative test — broken SKILL → `not ok 1` | ✅ PASS (after BLOCKER-002 fix `b6f063c`) |
| #4 | `claude --plugin-dir ./plugin-kiln --help` flag set present | ✅ PASS (v2.1.119) |
| #5 | Long-running healthy session not terminated | ✅ PASS (parameterized) |
| #6 | Stalled fixture terminated via classifier-driven SIGTERM | ✅ PASS (parameterized) |
| #7 | TAP determinism across two runs | ✅ PASS (byte-identical) |

The harness is real: it spawns actual `claude --print --verbose
--input-format=stream-json --output-format=stream-json --plugin-dir
<root>` subprocesses, isolates them in `/tmp/kiln-test-<uuid>/`, and
detects SKILL drift (smoke #3 is the proof-of-work). Documentary SMOKE
blocks are no longer the state of the art.

**The mechanism that produced this resolution matters as much as the
outcome.** The signal pattern was: 4 consecutive retros flagged the gap
→ retro #149 (`prd-derived-from-frontmatter`) escalated it to
`.kiln/feedback/2026-04-24-kiln-needs-an-executable-skill-test-harness.md`
→ `/kiln:kiln-distill` picked it up → `/kiln:kiln-build-prd` executed
it → merge-ready PR. **This is the first end-to-end demonstration that
retrospective signals can escalate to shipped features via the normal
pipeline, without a special intervention.** Codify:
`4-consecutive-flags → auto-escalate to feedback file` should become a
formal retro discipline.

---

## Signal counters (running totals)

| Signal | Prior count | This run | New total | Action |
|---|---|---|---|---|
| **O-1** documentary-only SMOKE | 4 (retros #142/#145/#147/#149) | shipped | **RESOLVED** | Close the signal. Track whether future retros stop flagging it (expected: yes). |
| **R-1** strict-behavioral-superset bless-inline | 3 (CRLF hoist, D-1 POSIX awk, pure-bash watcher v1 — actually already 4 by retro #149's count) | +1 (BLOCKER-001 stream-json pivot, blessed inline via contract update commit `284edb2`) | **5+** | **EXECUTE PI-1 prompt rewrite.** The auditor brief must now enumerate R-1 as a permitted class with two named precedents: (a) POSIX-portability tightening, (b) contract-revision-under-technical-blocker. |
| **FR-005 terminology collision** | 1 (retro #149) | 0 | 1 (unchanged) | Did not recur. Keep tracking passively. |
| **BLOCKER-filed-and-resolved mid-pipeline** | implicit | **2** (BLOCKER-001 CLI drift, BLOCKER-002 prompt leakage) | first explicit count | Codify as a success pattern — see below. |

---

## What worked — quote-level evidence

### The brief's "file a blocker, don't silently substitute" instruction was load-bearing

BLOCKER-001 (the PRD assumed `--headless` and `--initial-message` flags
that do not exist in Claude Code v2.1.119) is exactly the failure mode
PRD Risk 4 warned about. The implementer could have silently
substituted `--print`, wired up a brittle one-shot call, and shipped a
harness that never actually worked end-to-end. Instead, they stopped,
filed BLOCKER-001 with three enumerated options (A/B/C) and a
recommendation, and waited. The team-lead picked Option A; the
contract was updated in commit `284edb2`; implementation resumed from
Phase A with a clean contract.

From implementer.md line 21:

> **Resolution**: BLOCKER-001 filed → team-lead picked Option A → plan.md
> D6 + contracts/interfaces.md §7.2 + §3 + §5 updated → blocker closed.

The load-bearing phrase from the team-lead brief — "file a blocker
rather than silently substituting" — is what made this go right.
**Keep it in every implementer brief going forward, verbatim.**

### Mandatory negative smoke caught the harness's most dangerous self-deception

BLOCKER-002 is uncomfortable to read: the very anti-pattern the
harness is built to detect (prompt-as-contract leakage) was present
in the harness's own first seed test. The implementer's Phase F
"happy path passed, I declared done" moment was exactly the
documentary-test failure mode. The audit's smoke #3 (break the SKILL,
expect `not ok`) is the ONLY gate that distinguished a real test from
a documentary test wearing a costume.

From implementer.md line 75:

> The audit's smoke #3 step (break the SKILL, expect `not ok 1`) is the
> ONLY check that distinguishes a real test from a documentary-test-in-
> costume. [...] Lesson carried forward: every future seed test MUST
> include a negative-drift run during implementation, not only at audit
> time.

Without the mandatory negative-smoke item in the auditor's checklist,
we would have shipped a harness that silently passes every test. **The
mandatory-smoke list is what makes the harness real.** This is the
retro's strongest case for treating audit checklists as NON-NEGOTIABLE.

### Mid-pipeline scope-pivot worked cleanly

BLOCKER-001 forced an Article VII contract update mid-pipeline. The
implementer handled it in a single clean commit (`284edb2 spec(contract):
pivot to stream-json for multi-turn skill invocation (resolves CLI
blocker)`) before resuming Phase A. Specifier's A1/A2 decisions (the
substrate abstraction shape) survived the pivot because the abstraction
was scoped to substrate-dispatch, not CLI-flag-set. **Codify as a
success pattern**: when a blocker forces a contract change, update the
contract FIRST (Article VII), commit it as a dedicated spec commit,
THEN resume implementation. Do not mix spec and code changes in the
same commit.

---

## What was uncomfortable but was caught in time

### Prompt-contract leakage in the harness's own seed test (BLOCKER-002)

The `kiln-distill-basic` seed test's `inputs/initial-message.txt`
originally read:

> "Generate the PRD under `docs/features/<YYYY-MM-DD>-<theme-slug>/PRD.md`
> with the mandatory frontmatter (`derived_from:`, `distilled_date:`,
> `theme:`) and the Source Issues table referencing both fixture files."

The model satisfied the prompt regardless of SKILL content, because
the prompt named every contract key. Negative-drift test passed when
it should have failed. Fix (commit `b6f063c`) rewrote the prompt to
intent-only:

> "Run `/kiln:kiln-distill` against the fixtures in the current working
> directory. There is one open feedback item and one open issue. When
> and if the skill prompts for theme selection, answer using the queued
> answer lines. The goal is to bundle the open items into a feature PRD."

**Codify for all future seed-test authors:** `inputs/initial-message.txt`
MUST be intent-only. The SKILL's contract lives in `assertions.sh`, not
in the prompt. Test for leakage by reading the prompt aloud: if it
sounds like a spec ("output must contain X with Y keys"), it's leaking;
if it sounds like a goal ("bundle the open items into a PRD"), it's
clean. The auditor codified this in `kiln-test/SKILL.md` and
`plugin-kiln/tests/README.md` (see auditor.md "Codified best practice"
section).

### Negative-test discipline: remove ALL contract evidence

A subtler auditor self-correction from smoke #3 iteration (auditor.md
line 153, implementer.md line 79):

The auditor's first negative-test edit only removed the prose
description of frontmatter emission, leaving the literal YAML template
block and the FR-002 single-source-of-truth invariant intact. The
model read the surviving examples in-context and faithfully reproduced
them → false `ok 1`. Only after collapsing ALL THREE (prose + literal
template + invariant section) did `not ok 1` reproduce. **Codify:**
negative-drift SKILL breaks must `grep -n` for every occurrence of the
contract key across the SKILL and neutralize all of them, not just
the top-of-section header. Surviving examples ARE documentation in
disguise.

### The pipe-vs-redirect stdin invariant (implementer Watchout #4)

`claude --print --input-format=stream-json < file.json` silently emits
ZERO envelopes on macOS. The same stream piped via `cat file.json |
claude ...` works. If a future maintainer "cleans up" the cat-pipe to
a `<` redirect, every test will silently pass with empty transcripts.
Commit `f957ddd` refined the Watchout to emphasize this. Auditor
suggested a tripwire (refuse to run if transcript < 100 bytes after
subprocess exit). **Recommend this be filed as a follow-on issue via
`/kiln:kiln-report-issue` so it doesn't get lost.**

---

## Pipeline-mechanics findings (not code findings)

### Task #2 re-open pattern is undocumented but correct

Task #2 ("Implement plugin-skill-test-harness") was marked completed
after Phase H, then re-opened when BLOCKER-002 required implementer
rework. This is the right move — the downstream audit check found a
real problem, and the task was not actually done — but it is not
currently documented in `plugin-kiln/skills/kiln-build-prd/SKILL.md`.
The build-prd brief today implicitly assumes tasks are a DAG and
downstream work starts only after upstream tasks are done.

**Prompt rewrite proposal**: update build-prd SKILL.md to document the
"downstream-found-issue re-open" pattern explicitly. Something like:

> If an auditor (or any downstream agent) finds an issue that requires
> upstream rework, the upstream task SHOULD be re-opened via TaskUpdate
> (status: in_progress) rather than creating a new task. The re-opened
> task's audit trail (pre-complete → in_progress → complete) is the
> record that the rework happened.

### Version bump: `feature` vs `pr` segment

The auditor bumped `VERSION` to `000.001.009.000` — incrementing the
**feature** segment rather than the **pr** segment that build-prd
SKILL.md instructs ("Bump VERSION pr segment"). The feature-level
bump is almost certainly correct for a substantive new skill
(`/kiln:kiln-test`) + new agent (`test-watcher`) + 13 new harness
scripts; calling it a "pr-level edit" understates the change class.
**Prompt rewrite proposal**: update build-prd SKILL.md to instruct a
heuristic, not a rule:

> Bump VERSION: **feature** segment for PRDs that add a new skill or
> agent or substantial new subsystem; **pr** segment for
> fixes/refactors/polish PRDs. If in doubt, bump feature.

### Parallel audit ↔ implementer co-tenancy hazard

During BLOCKER-002 resolution, the auditor's smokes #5 and #6 ran in
parallel with the implementer's negative-verify run. The `rm -rf
/tmp/kiln-test-*` cleanup pattern in `SMOKE.md` Block A is wildcard-
based and clobbered the sibling process's scratch. No correctness
impact (each run's verdict JSON is emitted before cleanup), but
flagged as a follow-on. **Action**: file this via
`/kiln:kiln-report-issue` if not already. Scope cleanup to the run's
own UUID, or document a "no concurrent harness runs in the same repo"
constraint in SKILL.md. Auditor suggestions at auditor.md
"Suggestions for follow-on PRDs" #6.

### User-via-teammate-relay (tmux edge case)

The user was stuck in the auditor teammate's tmux pane during the
BLOCKER-002 decision, and their "I go with A" response came through
the auditor channel rather than team-lead. Not a pipeline problem per
se — the message was understood and acted on. But if this recurs, it
is worth documenting in build-prd SKILL.md that
tmux-relay-via-teammate is an acceptable fallback when the primary
team-lead channel is broken.

---

## Prompt-rewrite actions (prioritized)

1. **[HIGH] Execute PI-1 auditor brief rewrite.** R-1 is at 5+ stable
   occurrences across 4 pipelines. Rewrite
   `plugin-kiln/skills/kiln-build-prd/SKILL.md` auditor section to
   enumerate R-1 as a permitted class of deviation with two named
   precedents (POSIX-portability tightening; contract-revision-under-
   technical-blocker). Unblocks auditors from relying on memory of
   prior precedents.

2. **[HIGH] Keep "file a blocker, don't silently substitute"
   verbatim** in every implementer brief. This instruction was
   load-bearing for BLOCKER-001 and should not be paraphrased.

3. **[MED] Document Task re-open pattern** in build-prd SKILL.md. When
   downstream work finds an issue requiring upstream rework, re-open
   the upstream task rather than creating a new one.

4. **[MED] Fix version-bump instruction** in build-prd SKILL.md.
   Change from "bump pr segment" to the class-of-change heuristic
   above.

5. **[MED] Codify seed-test prompt convention** in `kiln-test/SKILL.md`
   (consumer contract section) and `plugin-kiln/tests/README.md`. The
   auditor's write-up at auditor.md "Codified best practice" is
   ready-to-paste.

6. **[LOW] Add "4-consecutive-flags → escalate to feedback file"
   discipline** to the retrospective skill itself (or to
   `kiln-build-prd` retrospective brief). O-1's resolution is the
   first proof-of-concept that this path works end-to-end; make it a
   named discipline.

---

## Follow-on issues to file via `/kiln:kiln-report-issue`

(Retrospective does not file these directly — they belong to the
team-lead or a subsequent session. Listed here so nothing gets lost.)

- **Parallel-run co-tenancy hazard** (auditor.md follow-on #6): scope
  scratch-cleanup to the run's own UUID.
- **Pipe-vs-redirect tripwire** in `claude-invoke.sh`: refuse to run
  if transcript < 100 bytes post-subprocess-exit (implementer Watchout
  #4 + auditor's suggestion).
- **Scratch-escape isolation test** (auditor.md follow-on #3): add
  `plugin-kiln/tests/scratch-isolation/` fixture.
- **Watcher Task-tool invocation** (auditor.md follow-on #4): swap
  pure-bash `watcher-runner.sh` for a Task-tool spawn of
  `test-watcher.md` agent — contract-compatible per implementer's
  design.
- **TAP artifact retention policy** (auditor.md follow-on #5):
  `kiln-test --keep=last-N` to manage `.kiln/logs/` growth.
- **Prompt-leakage heuristic detector** (BLOCKER-002 Option B): grep
  `inputs/initial-message.txt` for tokens from `assertions.sh` at
  validate time; warn on overlap.

---

## Meta-lesson

This pipeline is the first end-to-end success of the retro →
feedback-file → distill → build-prd escalation path. It took **4
retrospectives** of flagging, **1 feedback file** (escalated by retro
#149), **1 distill run**, **1 build-prd run**, **2 mid-pipeline
blockers**, and **1 downstream-found-issue task re-open** to ship.
The number to remember is **4 retros**: by the fourth flagging,
escalate.

The harness catches itself: BLOCKER-002 proves that the anti-pattern
the harness exists to detect can lurk INSIDE the harness's own
fixtures. The discipline of mandatory negative-smoke is what keeps
this kind of self-deception from shipping. Treat audit checklists as
non-negotiable — they are the mirror the pipeline holds up to itself.
