# Auditor friction notes — research-first-plan-time-agents

**Author**: auditor (kiln-research-first-plan-time-agents pipeline)
**Date**: 2026-04-25
**Branch**: `build/research-first-plan-time-agents-20260425`
**Tasks executed**: T#3 (audit + smoke + PR).

## Friction encountered

1. **Team-lead's audit checklist mismatched the spec's reconciled allowlist** — the team-lead's prompt asserted `fixture-synthesizer` should have `Read+Write+Bash`, but spec.md FR-001 (and the lint script + structural test) lock `Read, Write, SendMessage, TaskUpdate`. The PRD's FR-001 used the R+W+B wording, but the spec explicitly reconciled it with "Bash is **not** added (the synthesizer writes files directly; jq derivations happen in the calling skill, not in the agent)". Treated spec as authoritative per the kiln workflow contract (PRD → spec resolves ambiguities). **Recommendation**: when team-lead audit checklists are derived from the PRD body, the build-prd orchestrator should regenerate them after the specifier reconciles open items, OR the auditor should default to the spec when they diverge. Documented in audit-report.md "Allowlists" section so future readers see the divergence.

2. **No live workflow substrate for `/plan`-time agent spawn** — `kiln-test` cannot drive an interactive `/plan` session that spawns a sub-agent and validates relay envelope shape. The structural-surrogate fallback (mock-injection + tier-3 prose checks) is the documented best-available evidence per the live-substrate-first rule's tier 3. **Flagged in audit-report.md** as a non-discipline gap; live-spawn validation queues to the first-real-use synthesized-corpus PRD (SC-001) and first-real-use `output_quality`-axis PRD (SC-002). This is a session-bound limitation of CLAUDE.md Rule 5 (new agent.md not spawnable in shipping session), not a missing test.

3. **Audit-report path-shape verification for FR-007 (promote-vs-one-off)** — the SKILL.md prose mandates the path divergence (`plugin-<skill-plugin>/fixtures/<skill>/corpus/` vs `.kiln/research/<prd-slug>/corpus/`), but no fixture asserts the actual file move. This is unavoidable without live-spawn substrate (the move only happens after a real human accept-all). Documented as path-shape-only verification in the traceability table; live-emission queued for SC-001 PRD.

4. **NFR-009 (regen budget visibility) is a structural assertion only** — SKILL.md L201 mandates the `Regeneration budget used: <N>/<corpus_size × max_regenerations>` header, but no fixture writes a real synthesis-report.md. This is correct: the synthesis-report.md is emitted only after human-review ends, which is non-mockable in a structural fixture. Live emission queues to SC-001.

5. **Skip-path measurement is dominated by `/usr/bin/time` granularity** — the probe runs in well under 10 ms on macOS, and `/usr/bin/time -p` reports in 0.01-second resolution, so the measurements show 0.00s / 0.01s noise. Adequate to demonstrate "≤ baseline + 50 ms" but not precise. This is consistent with research.md §baseline's accepted irreducible-floor framing. **Recommendation**: a future precision pass could use `gdate +%s%N` (GNU date) on a Linux CI runner to get sub-millisecond timing, but it would not change the verdict.

## What worked well

- **Implementer's friction notes were thorough.** All five items were verifiable against the code: the placeholder-swap fix in parse-prd-frontmatter.sh, the latent `set -e + grep | pipe` bug in lint-agent-allowlists.sh, the tier-3 substrate decisions for T016/T019, the probe-script extraction for T015. All matched what I observed in the source.

- **`research-first-agents-structural` (sibling test) gave free coverage** — it asserts `fixture-synthesizer.md` and `output-quality-judge.md` conform to FR-A-10/FR-A-11 (no model: in frontmatter; no verb tables; no enumerated tool refs; no step-by-step prose). This was a no-cost cross-check that the new agent prose follows the established research-first agent shape.

- **The lint trio is the right pattern.** `lint-judge-prompt.sh` + `lint-synthesizer-prompt.sh` + `lint-agent-allowlists.sh` together enforce the three load-bearing invariants (verbatim rubric token, diversity prompt verbatim, allowlist drift detection) in a way that's resilient to future agent.md edits. Future PRDs that touch these files will trigger lint failures before merge.

- **The PRD → spec reconciliation pattern (Directive 1, Directive 2 in spec.md)** is a useful audit affordance — the spec explicitly cites WHICH PRD threshold it reframed and WHY (with measurement evidence in research.md §baseline). This made FR/NFR coverage verification much faster than a pure forward pass would have.

## Anything for the retrospective

- **Build-prd team-lead prompt drift from spec** (item #1 above) — the orchestrator generated the auditor's prompt from the PRD body, before the specifier landed Directive 1 + Directive 2. This is a generic build-prd issue, not specific to this PRD. Worth filing as a `/kiln:kiln-feedback` item: "team-lead audit checklist should refresh after specifier reconciliation."

- **Test-fixture authoring-vs-execution discipline (PI-2)** held — implementer ran every fixture before marking the task `[X]`. Audit confirmed by re-running 11 fixtures end-to-end with all 54 assertions PASS.

- **Live-substrate-first rule** is correctly treated as a NON-NEGOTIABLE; structural-surrogate fallback is documented explicitly per the rule's tier-3 affordance. The session-bound CLAUDE.md Rule 5 limitation is a known constraint — the auditor should NOT silently downgrade, but FLAGGING and queuing to first-real-use is the right escape hatch for this class of gap.

- **23 tasks `[X]` and 5 `[X]`-tied commits** = healthy pace; no batch-flip-at-end anti-pattern. Phase commits each touch ~12-15 files due to version-bump hook churn; implementer's recommendation about per-PR vs per-edit version bumps is worth revisiting in a future retro.
