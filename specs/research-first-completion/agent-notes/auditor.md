# Auditor friction notes — research-first-completion

**Auditor**: auditor (build/research-first-completion-20260425)
**Date**: 2026-04-25

## Audit findings

Verdict **PASS**. PRD compliance is 20/20 FRs, 6/6 NFRs, 11/11 SC fixtures
(spec lists 7 SC names but ships 11 anchored fixtures — every FR-anchored
SC has its own run.sh). Both load-bearing invariants verified directly:

- **NFR-009 foundation invariants UNTOUCHED** — `git diff main..HEAD` on
  every listed untouchable returns 0 lines. The single shared file
  extended (`parse-prd-frontmatter.sh`) is additive only — existing
  projections + exit codes preserved.
- **NFR-002 / NFR-005 byte-identity** — manual parse of
  `2026-04-25-research-first-foundation/PRD.md` produces the existing
  3-key projection unchanged plus 4 nulls for the new fields. Skip-path
  probe falls through with NO stdout.

The implementer's Phase D test scaffolding is thorough — every signal
word mapping in the FR-014 table has a fixture row; the conflict prompt
shape is asserted character-for-character against NFR-004's verbatim
contract; the byte-identity skip path is a single jq lookup with a hard
"NEVER emit stdout" comment in SKILL.md.

## Substrate decisions

**Live workflow substrate** was NOT used for `research-first-e2e/`. The
`/kiln:kiln-test` harness exists but was not exercised through it for
this PR — the fixture's `run.sh` is self-contained per NFR-008 and the
PRD's FR-019 explicitly carves out a PASS-cite fallback ("if the harness
can't run the fixture in-substrate, `bash plugin-kiln/tests/research-
first-e2e/run.sh` is the canonical evidence path"). Direct-invocation
substrate (tier-2) is the canonical evidence per spec.

For schema validators + classifier + distill propagation + build-prd
routing dry-run — direct script invocation IS the live substrate; there
is no harness layer above these. Tier-1 (live substrate) is direct
script invocation for these surfaces.

For the distill propagation conflict prompt + build-prd routing branch
— the fixtures exercise the contracts (jq expressions + Phase 2.5
probe) directly rather than through a fully-spawned `/kiln:kiln-distill`
or `/kiln:kiln-build-prd` skill invocation. This is the right level
because:

- Skill-level invocation requires live LLM spawn (CLAUDE.md Rule 5
  forbids this for newly-shipped agents in the same session — applies
  to the build-prd variant which routes to live agents).
- The contract under test is the jq expression / shell branch logic,
  not the LLM execution.
- B-002 explicitly documents that first-real-use is the live integration
  path.

This is NOT a substrate downgrade — it's the highest-meaningful tier
given the LLM-spawn carve-out. The structural fallback (tier-3) was NOT
used for any FR/NFR/SC; every requirement has live-script or live-jq
evidence.

## Friction encountered

- **None substantive.** The implementer's friction notes (F-1..F-4 in
  `agent-notes/implementer.md`) describe the parser limitations they
  worked around; none of those workarounds caused audit-time confusion.
- The schema validator's "needs_research:true without fixture_corpus"
  warning fires on the valid-block test case in §4.1 of my manual
  rejects sweep — this is correct behavior (rule 10 of contracts §2);
  not a bug.
- Test count mapping: `back-compat-no-requires/` is in
  `specs/research-first-foundation/` test inventory, not
  `research-first-completion/`. I cite it in the audit as evidence for
  NFR-001 because it's the canonical no-frontmatter back-compat fixture
  in the repo. Implementer's notes also surface it.

## Anything for the retrospective

- The 5-phase commit cadence (A: schema → B: distill+build-prd → C:
  classifier+capture → D: 11 fixtures → E: notes+smoke) made the audit
  walkthrough straightforward. Each phase's commit message cited task
  IDs (PI-1 from issue #181), and the running fixture list maps
  one-to-one with FRs. The audit-report's compliance table was
  essentially a transcription job, not detective work.
- The `research-first-e2e/` fixture is a model for "load-bearing E2E
  with mocked LLM spawn" — under 250 LoC, two scenarios in one run.sh,
  no external network, runs in <2 seconds. Worth pointing to from the
  CLAUDE.md "Test substrate hierarchy" doc as a tier-2 reference.
- B-001 (skill-level write-time validator wiring) is small enough to
  ship as a tactical follow-up; the wrapper script + helper are already
  there. Worth a roadmap item to keep visible.
- The `/kiln:kiln-test` harness wiring for shell-only fixtures (issue
  #181 PI-2) remains unsolved infrastructure — multiple PRs in this
  phase have hit it. Worth re-prioritizing if the next PRD also relies
  on shell-only fixtures.
