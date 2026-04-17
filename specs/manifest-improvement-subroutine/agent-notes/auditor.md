# Auditor Notes — manifest-improvement-subroutine

**Audit date**: 2026-04-16
**Outcome**: PASS. PR created with `build-prd` label.

## What went smoothly

- Blockers.md was already in a clean state from the implementer — no unresolved gaps, clear FR→script→test traceability table. Reconciliation was minimal.
- Unit and integration tests are pure bash. Running the full suite end-to-end was ~2 seconds total. No flakes, no environment coupling.
- `caller-wiring.sh` bakes in the "propose@N-2, terminal@N-1" positional assertion — made FR-14 trivial to re-verify.
- The `${WORKFLOW_PLUGIN_DIR}` convention is cleanly applied across every modified workflow JSON. FR-16 check is a single grep.

## Friction encountered

1. **Repo has two workflow trees**: `plugin-*/workflows/*.json` (the authoritative plugin source) AND `workflows/*.json` at repo root (older/scaffold copies). An initial broad grep `**/workflows/*.json` hit the scaffold copies and surfaced bare `plugin-shelf/scripts/…` paths — a false positive for the FR-16 check. Scoping grep to `plugin-shelf/workflows/` and `plugin-kiln/workflows/` cleared it. Risk: a future auditor running the blanket grep from the team-lead instructions will hit the same scaffold copies and may believe FR-16 is violated. Worth an issue to either delete the root-level `workflows/` copies or move them under `workflows/tests/` where they belong.

2. **FR-2 vs implementation step count**: spec says "exactly two steps: reflect + write-proposal" (FR-002), but the workflow JSON has three steps (reflect, write-proposal-dispatch, write-proposal-mcp). This is intentional per R-001 in research.md — the "write-proposal stage" is split into a pure-bash dispatch command (deterministic gate) and an MCP agent (the actual vault write). The blockers.md note makes this explicit and treats the two implementation steps as a logical single "write-proposal" stage. A future auditor reading FR-002 literally without reading R-001 or blockers.md might flag this as a divergence. Consider tightening FR-002 language in the spec to "a reflect step followed by a write-proposal stage (one or more steps implementing exact-patch gate + MCP write)."

3. **bats vs pure-bash tests**: tasks.md and the original plan assumed `bats` availability; environment has none. Implementer rewrote tests as pure bash with equivalent assertion semantics. The blockers.md tooling note is correct but this is the second feature this quarter where `bats` was assumed and not present — either commit to `bats` as a dev dependency in `plugin-kiln/package.json` or stop writing plans that assume it.

4. **`validate-non-compiled.sh` false positives on `plugin-shelf/scripts/…`**: the repo-level validator's regex pre-dates the `plugin-shelf/` directory and doesn't know about it. Reports 7 "file reference not found" errors that are all correct file references. Documented as a tooling note, but this noise degrades the audit signal — anyone running validators pre-PR sees 7 red flags that are all false. Worth a backlog issue via `/kiln:report-issue`.

5. **Contracts folder non-obvious from task wording**: the team-lead task #3 instructions mention `specs/manifest-improvement-subroutine/contracts/interfaces.md` but that path wasn't explicitly cited for cross-referencing during FR trace. I trusted the blockers.md table instead. If contracts had diverged from implementation, I would have missed it. Suggestion: add "re-read contracts/interfaces.md and spot-check against one script signature" to the audit checklist.

## Gaps in tracing that required extra work

- None. The blockers.md traceability table gave script-level paths per FR. The only thing I had to do manually was open each cited script and verify the cited behavior actually holds at the line level — which is the correct audit work, not a gap.

## Recommendations for future audit tasks

- Have `/kiln:audit` (or the team-lead script for the auditor role) output a scoped grep set like `plugin-*/workflows/*.json` by default instead of `**/workflows/*.json`, to pre-empt the scaffold-copy false positive.
- Add a "spec vs implementation step-count sanity check" to the audit: if FR-N says "exactly K steps" and the JSON has K' ≠ K steps, require a blockers.md entry explaining why.
- Keep the positional caller-wiring assertion pattern — cheap, fast, catches regressions in one line of test code per caller.
