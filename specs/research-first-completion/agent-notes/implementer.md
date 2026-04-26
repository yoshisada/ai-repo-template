# Implementer Notes — research-first-completion

**Branch**: `build/research-first-completion-20260425`
**Date**: 2026-04-25
**Implementer**: pipeline implementer (single-implementer per Decision 1)

## Phases executed

A → B → C → D → E sequentially. No file conflicts encountered (single-
implementer pattern is the right call for this PR — confirmed empirically).

## Friction encountered

### F-1 — `parse-item-frontmatter.sh` cannot parse nested-flow YAML

The existing item-frontmatter parser (`plugin-kiln/scripts/roadmap/
parse-item-frontmatter.sh`) is a line-oriented awk parser that:

1. Treats `true`/`false` literals as the strings `"true"`/`"false"`
   (not booleans).
2. Splits flow-style lists (`[a, b, c]`) on commas — fine for scalar lists
   but breaks for nested object lists like `[{metric: tokens, direction:
   lower}]` (it splits the inner `metric: tokens` from `direction: lower`
   as separate string elements).

**Resolution**: rather than rewrite parse-item-frontmatter.sh (touched by
many committed test fixtures, high regression risk), I added a sibling
extractor at `plugin-kiln/scripts/research/parse-research-block.sh` that
uses the same python3 regex approach as `parse-prd-frontmatter.sh`. It
extracts ONLY research-block fields and emits a research-block-shaped JSON
projection. The validators (item / issue+feedback wrapper / PRD wrapper)
all call this extractor + the shared helper, sidestepping the awk parser's
limitation entirely.

**Cost**: small extra file; clean separation of concerns; zero regression
risk on parse-item-frontmatter.sh's hot path.

**If the awk parser's behavior is ever fixed**, the extractor remains
useful for issues + feedback (which have no other parser).

### F-2 — `false // null` semantics in jq

While writing `validate-research-block.sh` I tripped over this jq quirk:

```jq
($fm.needs_research // null) == false
```

When `$fm.needs_research == false`, the alternative-operator `//` returns
`null` (because false is "falsy" in jq). This breaks the rule-9 warning
`needs_research:false is the default — omit the key`. Fix: use
`($fm | has("needs_research")) and ($fm.needs_research == false)` instead.

**Friction**: spent ~10 minutes debugging the warning being silently
swallowed. The fix went into the helper directly; sanity tests caught it
quickly.

### F-3 — jq `index(.)` rebinds `.` inside parens

Tripped on this writing the unknown-research-block-key heuristic:

```jq
(known_research_keys | index(.))
```

Inside the parenthesized expression, `.` is rebound to the array (the
left-hand side of the pipe), not the original `.`. The fix is `as`-bind the
outer `.` first:

```jq
. as $k | (known_research_keys | index($k))
```

**Friction**: identical "silently zero matches" failure shape as F-2;
~5 minutes to root-cause.

### F-4 — Cold-start lockfile gotcha (PI-2 from issue #183)

I checked `.kiln/implementing.lock` at session start and found it already
present from a prior run. So Gate 4 of `require-spec.sh` was already
satisfied before I started — the gotcha didn't bite this run. If it had
been absent, I would have hand-created it (per the PI-2 workaround in
PR #182's friction note) before the first src/ edit in Phase A.

**Recommendation**: the team-lead's launch directive flagged this gotcha
preemptively; that's the right pattern. The implementer briefing was
thorough enough to keep this from being a blocker.

## Test substrate decisions

**All 11 fixtures use tier-2 substrate** (run.sh-only, direct bash
invocation). Rationale:

- The `/kiln:kiln-test plugin-kiln <fixture>` harness substrate is gap-
  documented in PR #166 + #168 (B-1 in those PRs). When the spec said
  "invoke /kiln:kiln-test plugin-kiln <fixture>", I treated it as
  "invoke OR direct bash-run with PASS-cite — substrate-appropriate" per
  the team-lead's launch directive.
- The fixtures mock LLM-spawning steps per CLAUDE.md Rule 5 — newly-
  shipped agents are not live-spawnable in the same session.
- Per-fixture stdout shows `pass  <assertion>` lines + `PASS: N/N
  assertions` summary on the last line.

T017 (`research-first-e2e`) is the load-bearing fixture for SC-005 +
phase-complete declaration. It exercises both happy and regression sub-
paths with a temp-dir reset between them, and emits PASS only when both
sub-paths pass. The gate evaluation is a deterministic shell-level mock
of the per-fixture token-count delta — orchestrator-side determinism is
what's tested, not LLM behavior.

## Decisions deviated from plan.md

None substantive. Two surface-level deviations worth noting:

1. **Decision 6 outcome**: chose option (b) — added thin wrapper
   `validate-prd-frontmatter.sh`. Plan.md left this open; the wrapper is
   ~40 LoC and matches the same shape as the issue/feedback wrapper, so
   the symmetry argument was the deciding factor.

2. **Decision 3 outcome**: chose option (b) — created
   `plugin-kiln/scripts/issues-feedback/validate-frontmatter.sh` as a new
   wrapper. Discovery confirmed no pre-existing issue/feedback validators
   (search via `find plugin-kiln/scripts -name "*validate*"` yielded only
   the item validator). Skill-level write-time wiring is documented as
   deferred in `blockers.md` B-001 — the ergonomics layer ships in this
   PR via the FR-015 question stanza in T011/T012 SKILL.md edits;
   automatic post-write validation is a follow-on.

## Gaps documented in blockers.md

- **B-001**: skill-level write-time validator wiring for kiln-report-
  issue and kiln-feedback (deferred).
- **B-002**: live LLM spawn for the research-first variant pipeline
  untested in this PR per CLAUDE.md Rule 5 (by design — first-real-use
  is the live integration path).

## Handoff notes for the auditor

1. **Schema validators**:
   - shared helper at `plugin-kiln/scripts/research/validate-research-
     block.sh` — single source of truth, byte-stable JSON output via
     `jq -c -S`.
   - sibling parser at `plugin-kiln/scripts/research/parse-research-
     block.sh` — necessary because parse-item-frontmatter.sh can't
     handle nested-flow YAML.
   - issue/feedback wrapper at `plugin-kiln/scripts/issues-feedback/
     validate-frontmatter.sh`.
   - PRD wrapper at `plugin-kiln/scripts/research/validate-prd-
     frontmatter.sh`.
   - item validator extended additively at `plugin-kiln/scripts/roadmap/
     validate-item-frontmatter.sh` — calls the shared helper after the
     existing item-schema validation; warnings emit to stderr (NFR-001
     backward compat preserved).

2. **Distill propagation** in `kiln-distill/SKILL.md` Step 3.5 (between
   Select Scope and Generate PRD). Conflict detection via the §5 jq
   expression; FR-006 prompt shape per §6; canonical merge jq expression
   from contracts §5; byte-identity skip path when no source declares
   `needs_research:true`.

3. **Build-prd routing** in `kiln-build-prd/SKILL.md` Step 2.5 (between
   Step 2 and Step 3). Skip-path is structural no-op (no stdout per
   Decision 7 / NFR-002). Variant path orchestrates establish-baseline →
   implement-in-worktree → measure-candidate → gate inline. Loud-fail
   (NFR-007) on `git worktree add` failure; no silent fallback to `cp -R`.

4. **Classifier extension** in `classify-description.sh` adds an OPTIONAL
   `research_inference` key when comparative-improvement signal words
   match. Structural absence when no signal matches (NFR-006 sibling
   pattern). FR-016 verbatim warning carried through verbatim for
   output_quality axes.

5. **FR-015 question stanzas** in three capture skills (`kiln-roadmap`
   §6.8, `kiln-report-issue` Step 1.5, `kiln-feedback` Step 4c). All
   conditional on `research_inference != null` from classifier output;
   silently skipped when absent.

6. **11 test fixtures** under `plugin-kiln/tests/<fixture>/`. All pass
   directly via `bash <fixture>/run.sh`. Total assertions: 96/96 PASS.

7. **Foundation invariants preserved (NFR-009)**: no edits to research-
   runner.sh, evaluate-direction.sh, evaluate-output-quality.sh,
   research-rigor.json, pricing.json, fixture-synthesizer.md, or output-
   quality-judge.md. The one shared file extended is `parse-prd-
   frontmatter.sh` — additive only (4 new field projections; existing
   3 projections + exit codes unchanged).

8. **PI-2 from issue #181 (smoke-pass before completion)**: T025 captured
   E2E fixture stdout to `agent-notes/e2e-smoke-output.txt` showing both
   happy and regression sub-paths PASS.

## Anything for the retrospective

- **The single-implementer pattern was the right call.** Four themes share
  multiple SKILL.md files (kiln-distill, kiln-build-prd, kiln-roadmap,
  kiln-report-issue, kiln-feedback) and the shared validation helper. A
  two-implementer split would have produced merge conflicts. Sequential
  per-phase commits kept the history clean.

- **Sibling extractor pattern (F-1) is reusable** for any future spec that
  needs research-block fields from non-PRD frontmatter surfaces. The PRD
  parser handles its own flow-style; everything else (item/issue/feedback)
  uses parse-research-block.sh. Worth surfacing in CLAUDE.md or a /plan
  hint that "if you need research-block fields from non-PRD surfaces, use
  the sibling parser, not parse-item-frontmatter.sh."

- **jq quirks cost ~15 minutes total**. Both F-2 and F-3 produced silently-
  empty results — they're easy to write and hard to debug. If we end up
  writing more research-block validators in jq, a small "jq footgun" guide
  in `plugin-kiln/lib/` would pay for itself in 1-2 future PRs.

- **Tier-2 substrate is clearly the right substrate** for this PR. The
  /kiln:kiln-test harness has a known gap (B-1 in PRs #166 + #168); direct
  bash-run is the canonical evidence path per the substrate-hierarchy rule.
  When the harness fix lands, every fixture should also pass via
  /kiln:kiln-test plugin-kiln <fixture>.
