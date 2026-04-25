# R-005 loophole: "negative result ok" implicitly permits "measure wrong layer + ship anyway"

**Date**: 2026-04-24
**Source**: wheel-as-runtime Theme E post-mortem
**Priority**: medium
**Suggested command**: `/kiln:kiln-fix`
**Tags**: [auto:continuance, wheel-as-runtime, PRD-template, risk-framing]

## Description

Risk R-005 in the wheel-as-runtime PRD reads: *"FR-018's step-batching prototype could discover that the round-trip latency claim is wrong (e.g. dominated by something else like cold-start), in which case the audit doc should still ship with the negative result documented and the FR scope re-narrows to that finding. Don't force a positive result."*

That framing is correct for honest negative-result reporting. But it doesn't cover the case that actually happened: *measurement was taken at a layer where the claim could not be observed, a negative result was returned at that layer, and the runtime switchover shipped anyway on the strength of "debuggability + portability + convention" rationale.*

In other words, R-005 makes "we measured and it's not faster, but we shipped the wrapper pattern" safe. It does not make "we didn't measure at the right layer, so we don't know, but we shipped the live switchover" safe. Those are different failure modes.

## What should happen

PRD-template risk-framing guidance (either in `/kiln:kiln-create-prd` or as a clarification inside the structured-roadmap / kiln-distill pipeline) should require risks of the "measurement-contingent ship" shape to include an explicit **measurement-layer specification**. Example:

```
R-005: If the measured perf delta (at the LLM-tool-call round-trip layer, NOT the
bash-orchestration layer — see NFR-X) is within noise or negative, the implementer
MUST revert any runtime switchover tied to the perf claim before marking the FR
complete. The wrapper, audit doc, and convention doc ship regardless.
```

The guidance should prevent the implicit "can't measure → ship anyway" path.

## Why this matters

R-005-shaped hedges appear in most engineering PRDs. A template-level fix here prevents the same gap from manifesting in future perf or optimization PRDs.
