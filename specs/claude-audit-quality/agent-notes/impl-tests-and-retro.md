# Friction Note — impl-tests-and-retro

**Branch**: `build/claude-audit-quality-20260425`
**Owner scope**: Theme F (FR-024 + FR-025 — retro insight-score + retro-quality.md rubric) + the five claude-audit fixtures (FR-002, FR-005, FR-011, FR-014, FR-019).
**Tasks completed**: T060, T061, T062, T063, T064, T070, T071, T072, T073, T074.

## What worked well

- **Spec / contracts / tasks were copy-paste implementable.** §7 + §8 of `contracts/interfaces.md` gave me the YAML key shape, the threshold value (3), the warning line verbatim, and the rubric file shape verbatim. I lifted §8's contract directly into `plugin-kiln/rubrics/retro-quality.md` with zero paraphrase — that's the right discipline for a self-rating prompt that has to cite the rubric verbatim.
- **The `run.sh` tripwire pattern from `distill-multi-theme-basic`** was the right substrate for v1. Each fixture is ~80 lines of pure shell asserting structural invariants in `plugin-kiln/skills/kiln-claude-audit/SKILL.md` + `plugin-kiln/rubrics/claude-md-usefulness.md`; every fixture passes locally and the assertions are precise enough to catch a regression that removed the contract anchors.
- **Theme F is genuinely independent of Themes A-E.** I shipped Phase 2B at the same time impl-claude-audit was working on Theme A; zero file overlap. The orthogonality survived the implementation, not just the spec.
- **NFR-002 self-containment**: every fixture ships its own `fixtures/` directory with the example CLAUDE.md (and where applicable, the reference docs `.specify/memory/constitution.md` / `.kiln/vision.md`). Even though the v1 `run.sh` tripwire doesn't yet consume the fixture data, it's documented and ready for the substrate upgrade.

## What didn't work well

### F-1 — The retrospective agent has no separate file (T061 surprise)

**What I expected**: tasks.md and the team-lead prompt both said "likely `plugin-kiln/agents/_src/retrospective.md` or `plugin-kiln/agents/retrospective.md`". I went hunting for a file.

**What I found**: there is no separate file — the retrospective agent prompt is rendered INLINE in `plugin-kiln/skills/kiln-build-prd/SKILL.md` Step 5 (lines 1019-1085). The team-lead spawns the retrospective with the inline body as the `prompt:` argument to `Agent`.

**Why this matters**: my T062 + T063 edits both landed in `plugin-kiln/skills/kiln-build-prd/SKILL.md` rather than a dedicated agent file. The hybrid compile-and-commit convention (`<!-- @include _shared/<name>.md -->`) is therefore not relevant to Theme F — `grep '@include'` returned zero matches in the modified files (T064 verified).

**Proposal**:

### PI-1 — Update tasks.md path conventions section to reflect inline-vs-file ambiguity

**File**: `plugin-kiln/skills/kiln-build-prd/SKILL.md`

**Current**: "Retrospective agent prompt: `plugin-kiln/agents/_src/retrospective.md` (compiled to `plugin-kiln/agents/retrospective.md`) — implementer confirms exact file at start of T040" (in tasks.md path conventions section)

**Proposed**: "Retrospective agent prompt: rendered INLINE in `plugin-kiln/skills/kiln-build-prd/SKILL.md` Step 5 (the team-lead spawns the retrospective with the inline body as the `prompt:` argument to `Agent`). There is no separate `plugin-kiln/agents/retrospective.md` or `_src/retrospective.md`. Edits to the retrospective agent prompt land in Step 5 of `kiln-build-prd/SKILL.md`."

**Why**: T061 spent agent-time hunting for a file that doesn't exist. The path-conventions section in future spec/tasks.md drafts should pre-document this so the implementer doesn't re-discover it.

### F-2 — Concurrent staging on the same branch swept impl-claude-audit's Theme A into my Theme F commit

**What happened**: When I ran `git add plugin-kiln/rubrics/retro-quality.md plugin-kiln/skills/kiln-build-prd/SKILL.md specs/claude-audit-quality/tasks.md`, my `git status` showed several `M ` (already-staged) entries from version-increment hooks AND from `plugin-kiln/rubrics/claude-md-usefulness.md` + `plugin-kiln/skills/kiln-claude-audit/SKILL.md`. I assumed those were impl-claude-audit's UNstaged work and that mine wouldn't sweep them. I was wrong about which were staged. My commit 936659f swept impl-claude-audit's Theme A staged changes into my "Theme F" diff.

**Symptom**: the impl-claude-audit DM confirmed this hazard ("your Theme F commit (936659f) accidentally swept my Theme A staged changes into its diff"). Same hazard documented in their friction note.

**Why this matters**: with two impl agents working in parallel on the same branch, `git status`'s staged-vs-unstaged distinction is the only signal — and version-increment hooks running on either agent's edits muddy the signal. The "every Edit triggers a stage of VERSION + plugin.json bumps" pattern means that any agent's `git add <my-files>` quietly inherits whatever was staged before, including the other agent's WIP.

**Proposal**:

### PI-2 — Document the concurrent-staging hazard in `kiln-build-prd/SKILL.md` Step 3 (parallel impl assignment)

**File**: `plugin-kiln/skills/kiln-build-prd/SKILL.md`

**Current**: (no guidance about concurrent-staging on a shared branch — agents are told to "commit per phase" but not warned about the staged-area pollution from a sibling agent's hooks)

**Proposed**: append to the Step 3 parallel-impl assignment block:

> **Concurrent-staging hazard** (from claude-audit-quality retro): when two impl agents work on the same branch in parallel, the version-increment hook (which auto-stages VERSION + every `plugin-*/package.json` + `plugin-*/.claude-plugin/plugin.json` on every Edit/Write) means each agent's staging area accumulates the OTHER agent's bumps. Compounding the hazard: an agent that writes a file mid-edit by a sibling agent will see that file as `M ` (staged) in its `git status` AND `git add <my-files>` will sweep it into the next commit. Mitigation: before `git commit`, EVERY impl agent runs `git diff --cached --name-only` and confirms the diff scope matches THEIR owner-files list from tasks.md. If an unexpected file appears in the staged set, run `git restore --staged <file>` to unstage it (the file remains in the working tree for the sibling agent to commit themselves). DO NOT use `git reset` — that affects HEAD.

**Why**: this hazard hit BOTH impl agents in this build (mine + theirs); it cost a manual recovery cycle. A one-paragraph warning in the parallel-impl assignment block prevents the same recovery cycle on the next pipeline.

### F-3 — Substrate gap B-1 (kiln-test harness can't run live audit fixtures) is now load-bearing for 5 fixtures

**What's in scope for this PR**: the five fixtures use the `run.sh` pure-shell tripwire pattern. They assert structural invariants in the rubric/SKILL.md that GUARANTEE the FR's behavior. They do NOT actually invoke `claude --print --plugin-dir <path>` against a fixture mktemp dir.

**Why this is acceptable for v1**: the kiln-test harness's plugin-skill substrate (per `plugin-kiln/skills/kiln-test/SKILL.md` and PRD `kiln-test`) already invokes real `claude --print` subprocesses against `/tmp/kiln-test-<uuid>/` — but it does so for tests with `test.yaml` + `assertions.sh` that the harness DISCOVERS by walking `plugin-kiln/tests/`. Tests with only `run.sh` are not discovered by the harness today. My five fixtures are `run.sh`-only because the team-lead instructions said so (substrate gap B-1).

**What's a follow-on**: when substrate gap B-1 closes, my five fixtures will need a parallel `test.yaml` + `assertions.sh` that drives the actual audit invocation and parses output. The fixture data (`fixtures/CLAUDE.md`, `fixtures/.kiln/vision.md`, etc.) is ready for that upgrade. The structural-invariant tripwire run.sh stays as a cheap regression guard alongside.

**Proposal**:

### PI-3 — File a follow-on to migrate run.sh-only fixtures to test.yaml+assertions.sh once kiln-test discovers run.sh

**File**: `plugin-kiln/skills/kiln-test/SKILL.md`

**Current**: discovery walk uses `find plugin-*/tests -name test.yaml` (or equivalent — confirmed by inspection of existing tests).

**Proposed**: extend kiln-test discovery to ALSO recognize `run.sh`-only fixture directories (no `test.yaml`); harness invokes `bash run.sh` and parses the trailing `PASS:` / `FAIL:` line as the verdict. Documented as a stable contract in kiln-test SKILL.md so future fixtures can pick the right substrate (test.yaml for "drive the live skill"; run.sh for "structural-invariant tripwire").

**Why**: substrate gap B-1 forced me to author 5 fixtures in the run.sh pattern that the harness can't discover. A consumer running `/kiln:kiln-test plugin-kiln` won't see those 5 fixtures' verdicts in the harness report. Closing the gap means future structural-invariant fixtures (a perfectly legitimate pattern for skill-shape regression checks) get harness coverage by default.

## What I'd change about the spec / contracts

### F-4 — Contracts §7 fenced-block-as-frontmatter convention is non-obvious

**What §7 says**: `insight_score:` + `insight_score_justification:` go in "the issue body's YAML frontmatter". GitHub issues don't have first-class YAML frontmatter — what §7 actually means is "the leading ` ```yaml ` fenced code block at the top of the body is the convention `/kiln:kiln-pi-apply` parses".

**What I had to discover**: this convention is implicit. I documented it in the agent prompt edit (T062) so the retro agent doesn't put the keys in arbitrary places.

**Proposal**: future contracts should explicitly say "GitHub issues don't have first-class frontmatter; the convention `<consumer skill>` parses is `<exact mechanism>`". One sentence prevents a 5-minute discovery cycle.

(Not filing as a separate PI block — it's an editorial improvement to the specifier's process, not a code change.)

## Verified locally — fixture verdicts (substrate-appropriate citation)

The kiln-test harness can't yet discover `run.sh`-only fixtures (substrate gap B-1). I cite each fixture's verdict via direct invocation:

```
$ bash plugin-kiln/tests/claude-audit-no-comment-only-hunks/run.sh
PASS: claude-audit-no-comment-only-hunks — Step 3.5 invariant present; comment-only hunks forbidden in skill body; rubric 3-trigger taxonomy in place

$ bash plugin-kiln/tests/claude-audit-editorial-pass-required/run.sh
PASS: claude-audit-editorial-pass-required — duplicated-in-constitution rule wired with action: duplication-flag; FR-003 'no sub-LLM call' contract present; FR-004 3-trigger taxonomy plus 'editorial work feels expensive' prohibition present; Step 3.5 forbids cost-language inconclusive punts

$ bash plugin-kiln/tests/claude-audit-substance/run.sh
PASS: claude-audit-substance — missing-thesis rule registered with substance/editorial/expand-candidate/[vision.body]; pre-filter (R-1) documented; Step 2 substance pass executes before cheap rubric pass; substance rank=0 sort key present

$ bash plugin-kiln/tests/claude-audit-grounded-finding-required/run.sh
PASS: claude-audit-grounded-finding-required — FR-012 rationale-line key 'remove-this-citation-and-verdict-changes-because:' is contracted; decorative-correlation prohibition present; FR-013 project-context-driven row guarantee placeholder + zero-fired condition wired; ≥4 substance rules with non-empty ctx_json_paths registered; Notes substance-first ordering declared

$ bash plugin-kiln/tests/claude-audit-recent-changes-anti-pattern/run.sh
PASS: claude-audit-recent-changes-anti-pattern — rule registered with substance/cheap/removal-candidate/'## Recent Changes' match; standardized pointer block (git log + roadmap phases + ls docs/features + /kiln:kiln-next) present; generic <active-phase> placeholder preserves byte-identity (OQ-4); FR-017 reconciliation handlers in both kiln-claude-audit and kiln-doctor SKILL.md
```

5 of 5 fixtures PASS. SC-001 through SC-005 are anchored.

## Handoff

- All Phase 2B (Theme F) and Phase 2C (5 fixtures) tasks marked `[X]` in `specs/claude-audit-quality/tasks.md`.
- Theme F committed in 936659f. Phase 2C will be committed before this note lands.
- DM to `auditor` with subject "tests and retro ready" pending after final commit.
