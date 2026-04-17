# Research: Manifest Improvement Subroutine

**Phase**: 0 (Plan) | **Date**: 2026-04-16

## R-001 — How does a "command" step invoke an MCP write?

**Decision**: It does not. The `write-proposal` step is a micro-sequence of two steps inside the workflow: (a) a bash `command` step that enforces the deterministic gate (validate reflect output, derive slug, verify `current` matches target file) and emits a dispatch envelope to `.wheel/outputs/propose-manifest-improvement-dispatch.json`; (b) an `agent` step that reads the dispatch envelope and, only on `action: "write"`, calls `mcp__claude_ai_obsidian-manifest__create_file` exactly once.

**Rationale**: Bash cannot call MCP tools. The project's existing shelf workflows follow the same pattern (`compute-work-list` command + `obsidian-apply` agent in `shelf-full-sync`). Keeping the gate enforcement in bash preserves determinism and testability while satisfying the "only MCP writes to the vault" constraint.

**Alternatives considered**:
- *Single agent step with no bash gate*: Rejected — FR-5/FR-6 require verifiable enforcement, not agent judgment.
- *Bash that shells out to a helper that calls MCP*: Rejected — no such helper exists; would be novel infrastructure.

## R-002 — How is `current` text matched?

**Decision**: `grep -F -q -- "$current" -- "$target_path"` (fixed-string, literal, quiet). Exit code 0 means match. No whitespace normalization, no regex, no trimming. This is verbatim per FR-5.

**Rationale**: FR-5 says "the `current` text exists verbatim in the target file". Verbatim means byte-for-byte. `grep -F` is POSIX, has no regex surprises, and is the simplest correct implementation. Multi-line `current` strings are handled because grep's input can be passed via process substitution / heredoc and matched line-by-line against the target; for truly multi-line blocks, we normalize to a single-line representation by reading `current` raw (including newlines) and using `grep -F --` which handles newlines in the needle via stdin.

**Alternatives considered**:
- *`diff` against a synthesized file*: Rejected — overkill for a substring check.
- *Python/awk regex*: Rejected — unnecessary complexity; verbatim match is the contract.
- *Fuzzy match*: Rejected — explicitly forbidden by FR-5.

**Edge case**: If `current` contains a newline, some bash patterns break. Implementation note: read `current` from the reflect JSON via `jq -r`, write to a temp file, then `grep -F -f <tmpfile> -- "$target"`. This handles any content.

## R-003 — Slug derivation algorithm

**Decision**: Deterministic pure-bash pipeline applied to the `why` sentence:

1. Lowercase.
2. Remove common English stop-words: `the a an is was were are of in on at to for and or but that this these those it its`.
3. Replace any non-alphanumeric run with a single `-`.
4. Collapse multiple consecutive `-` to one.
5. Trim leading/trailing `-`.
6. Truncate to ≤50 characters at a `-` boundary (never mid-word).

**Rationale**: Mirrors the proven slug algorithm used in `report-mistake-and-sync` (Step 7 of its agent instruction). Deterministic — same `why` sentence always produces the same slug. FR-10 requires these properties.

**Alternatives considered**:
- *Hash-based slug*: Rejected — not human-readable; FR-10 says kebab-case from the sentence.
- *Language-aware NLP slug*: Rejected — requires dependencies; not justified for ~1 call/day volume.

## R-004 — Where does the `reflect` step read its run context?

**Decision**: It reads files under `.wheel/outputs/` from the current run. Wheel's workflow runtime automatically surfaces prior-step outputs via `context_from`. The `reflect` step declares `context_from` pointing at the caller's relevant artifacts (for the three initial callers: the mistake/issue create result, the sync summary, etc.). The agent in the `reflect` step reads these and also has access to the repo filesystem (to inspect `@manifest/types/*.md` and `@manifest/templates/*.md` directly when verifying a candidate proposal).

**Rationale**: No new plumbing. This matches how `obsidian-apply` in `shelf-full-sync` reads its prior-step outputs.

**Alternatives considered**:
- *Pass a curated context blob to `reflect`*: Rejected — creates an extra command step with no value added; the agent can read what it needs.

## R-005 — How is silent-on-skip enforced byte-exactly?

**Decision**:
- The bash command sub-step (`write-proposal-dispatch.sh`) redirects ALL diagnostic output to `.wheel/outputs/propose-manifest-improvement-dispatch.json` only (the dispatch envelope). On skip, it writes `{"action":"skip"}` to the envelope and emits nothing to stdout/stderr. On any internal error (malformed reflect output, unreadable target file, etc.), it treats as skip per FR-18 — no user-visible output.
- The MCP agent sub-step reads the dispatch envelope first. On `action: "skip"`, it exits immediately without calling any MCP tool and without emitting any observable output. No stdout, no log line, no file created.
- The dispatch envelope itself is an internal artifact under `.wheel/outputs/` and is not surfaced to the user (consistent with FR-20 about the reflect output).

**Rationale**: "Silent" in the PRD means the user sees no output. Bash can redirect/suppress easily. Agent steps naturally produce no output unless they write a summary; we instruct the agent explicitly to produce no summary on skip.

**Alternatives considered**:
- *Suppress via `> /dev/null 2>&1` wrapper*: Rejected — loses the dispatch envelope, which the MCP agent step needs to read.

## R-006 — Graceful degradation when Obsidian MCP is unavailable (FR-15)

**Decision**: The MCP agent sub-step catches tool-unavailable errors, writes exactly one line to stderr (`warn: obsidian MCP unavailable; manifest improvement proposal not persisted`), exits 0, and does not retry. Wheel treats exit 0 as step success — the caller workflow continues past this step unaffected.

**Rationale**: FR-15 is explicit: warn once, exit 0, do not block caller. Single-line warning is the minimum observable signal to a human that a proposal was lost; any less is undetectable. The caller workflow's terminal step continues normally.

**Note**: This is the ONE place the sub-workflow may emit user-visible output. It is NOT a violation of silent-on-skip because skip (FR-7) is a different scenario — skip means "nothing to propose". MCP-unavailable means "had something, couldn't write it". Users deserve to know they lost a proposal.

**Alternatives considered**:
- *Retry with exponential backoff*: Rejected — blocks the caller, violates FR-15's "MUST NOT block".
- *Persist proposal to a local queue for later replay*: Rejected — adds state machinery, not in scope for v1.

## R-007 — Caller wiring precedence (FR-014)

**Decision**: For the two kiln callers (`report-issue-and-sync`, `report-mistake-and-sync`), insert the new sub-workflow step immediately before the existing terminal `shelf:shelf-full-sync` step — so any proposal written IS picked up by the same sync pass.

For `shelf-full-sync` itself, insert the new sub-workflow step between `generate-sync-summary` and the terminal `self-improve` step. This means a proposal written by THIS invocation of `shelf-full-sync` is NOT synced by THIS invocation (obsidian-apply already ran) — it is synced by the NEXT invocation. This is an intentional asymmetry: `shelf-full-sync` cannot call itself, and adding a second `obsidian-apply` after `propose-manifest-improvement` would double-sync and is complexity this PRD explicitly avoids (FR-16 assumption: one sub-workflow step, no custom glue).

**Rationale**: FR-14 says "pre-terminal so a proposal is picked up by the same sync pass". For the two kiln callers whose terminal is `shelf:shelf-full-sync`, this is literally satisfied. For `shelf-full-sync` itself, the most coherent reading is "pre-terminal step" — and accepting a one-run delay for proposals that originate DURING a full-sync run. The human triage path is unchanged either way; proposals show up in Obsidian after at most one additional sync cycle (which happens regularly).

**Documented consequence**: A maintainer reading `@inbox/open/` may see manifest-improvement proposals with a dashboard-last-synced timestamp one sync-cycle later than the run that generated them. This is acceptable.

**Alternatives considered**:
- *Run `obsidian-apply` twice in `shelf-full-sync`*: Rejected — doubles MCP call count, complicates error handling, violates "one sub-workflow step, no custom glue".
- *Have `propose-manifest-improvement` write directly via MCP and skip the next sync*: Rejected — the write already goes via MCP, but the manifest-sync state (`.shelf/sync-manifest.json`) is owned by `shelf-full-sync`'s command steps; updating it from inside a sub-workflow would entangle state ownership.

## R-008 — `${WORKFLOW_PLUGIN_DIR}` reliability

**Decision**: Every command step uses `bash "${WORKFLOW_PLUGIN_DIR}/scripts/<script>.sh"`. Zero command steps use repo-relative `plugin-shelf/scripts/...` paths. This matches the pattern `shelf-full-sync` already uses for `read-sync-manifest.sh`, `compute-work-list.sh`, `update-sync-manifest.sh`, `generate-sync-summary.sh`.

**Rationale**: `${WORKFLOW_PLUGIN_DIR}` is validated end-to-end in wheel v1143 per PRD assumption. No fallback is warranted — if the variable is unset, the script fails loudly (bash would print `No such file or directory` and exit nonzero), which surfaces the wheel bug instead of masking it.

**Verification task**: A pre-implementation sanity check runs `jq -r '.steps[] | select(.type=="command") | .command' plugin-shelf/workflows/propose-manifest-improvement.json` and greps for any `plugin-shelf/scripts/` substring. None permitted.

## R-009 — Proposal filename collision handling (FR-19)

**Decision**: Before calling `mcp__claude_ai_obsidian-manifest__create_file`, the MCP agent sub-step attempts the create. If it fails with "file already exists", the agent appends `-2`, `-3`, ... to the slug (before `.md`) and retries, up to a max of 9 attempts. After 9, it treats as MCP-unavailable and applies the FR-15 graceful-degradation path.

**Rationale**: Same-day collisions are rare (one proposal per run, few runs per day). The suffix approach matches what `report-mistake-and-sync` does for mistake-file collisions (Step 8 of its agent instruction). 9 attempts is plenty of headroom; beyond that, something is wrong.

## R-010 — Standalone invocation surface (FR-17)

**Decision**: Ship a companion skill `shelf:propose-manifest-improvement` (Markdown skill that runs `/wheel-run shelf:propose-manifest-improvement`). Contributors can invoke it directly via `/shelf:propose-manifest-improvement` for testing and manual use. Same workflow, same guarantees — no divergence.

**Rationale**: FR-17 requires standalone invocation. The wheel plugin's `/wheel-run` already provides this; the skill is a thin ergonomic wrapper so contributors don't have to remember the `/wheel-run` form.

**Alternatives considered**:
- *No skill, require `/wheel-run`*: Rejected — breaks the pattern where every sub-workflow has a skill wrapper, hurts discoverability.
