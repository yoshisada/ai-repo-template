# Blockers — research-first-completion

## B-001 — issue/feedback skill write-time validator wiring (T003 follow-up)

**Status**: deferred to follow-on PR.

**Context**: T003 / Decision 3 outcome (b) ships the shared validation helper
+ `plugin-kiln/scripts/issues-feedback/validate-frontmatter.sh` wrapper. Both
are exercised via direct script invocation (substrate-tier-2 fixtures).

**Gap**: The `/kiln:kiln-report-issue` and `/kiln:kiln-feedback` skills are
SKILL.md prose-driven (not pipelined through a write helper script). Adding
a write-time validation hook to those flows requires either:

(i) prepending a Bash step to the SKILL.md prose that invokes the wrapper
    against the freshly-written file before considering the capture
    "complete", surfacing any `ok:false` errors back to the user; OR
(ii) refactoring the file-write inside each skill to call a shared helper
    that always validates after writing.

**Why deferred**: the schema-validator infrastructure is the load-bearing
deliverable of T003; integrating the wrapper into interactive capture flows
is a follow-on ergonomics concern. False-positive recovery (NFR-006) does
not depend on write-time validation — a maintainer who bypasses the
classifier-proposed research-block can still hand-edit the file and validate
via direct CLI invocation. The Phase C SKILL.md edits (T010..T012) add the
classifier-proposal accept/tweak/reject question, which is the primary user-
facing surface this PR ships for these skills.

**Reopen criterion**: file a follow-on roadmap item once the v1 captures
demonstrate research-block frontmatter being introduced into issue/feedback
files in real flows. No reopen needed if real-use shows research-block
authoring lives only on roadmap items + PRDs.

## B-002 — research-first build-prd variant: live LLM spawn untested in this PR

**Status**: by design (CLAUDE.md Rule 5).

**Context**: T007 ships the Phase 2.5 stanza in `/kiln:kiln-build-prd`. The
variant pipeline orchestrates `establish-baseline → implement-in-worktree →
measure-candidate → gate → audit → PR`. CLAUDE.md Rule 5 forbids live agent
spawn for newly-shipped agents in the session that ships them. The E2E
fixture (T017) mocks every LLM-spawning step.

**Gap**: First-real-use (next pipeline run on a `needs_research: true` PRD)
is the primary live verification path. If the live integration surfaces
unexpected behavior (e.g., worktree cleanup leakage on interruption), file
a follow-on issue.

**Reopen criterion**: live-spawn validation is queued for the next session
per CLAUDE.md Rule 5.
