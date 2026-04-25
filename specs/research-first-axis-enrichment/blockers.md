# Blockers: research-first-axis-enrichment

**Status**: 0 blockers — pipeline is shippable.

---

## Reconciliation Summary (2026-04-25, audit-pr)

Both audits returned clean verdicts:

- **audit-compliance** (task #4): 100% PRD coverage (15/15 FRs, 5/5 NFRs, 7/7 SCs), 100% FR compliance (16/16 spec FRs implemented + tested), 14/14 test fixtures green, 0 blockers.
- **audit-smoke** (task #5): SC-001..SC-007 all PASS via 9 pure-shell unit fixtures (69 total assertions, $0 API cost). Foundation backward-compat (NFR-AE-003) confirmed: 5 foundation fixtures re-run green post-extension.

No SC failed. No fix-up commit was required. This branch is green for PR.

---

## Documented Follow-Ons (Not Blockers)

The audit-compliance report flagged one spec-internal-consistency improvement that the implementation already handles correctly. Documenting here so it surfaces on the next pipeline run rather than being lost:

### Spec text inconsistency: FR-AE-005 `equal_or_better` axis-aware polarity

The literal formula in `spec.md` FR-AE-005 reads `regression iff (b - c) / max(b, 1) > t/100`. That formula is correct for `accuracy` (higher-is-better) but wrong for `tokens / time / cost` (lower-is-better). With `tokens, tol=0, b=100, c=101` the literal formula yields `-0.01 > 0` → no regression, which contradicts SC-AE-003 (which requires +1 token at infra zero-tolerance to FAIL).

**Implementation is correct**: `evaluate-direction.sh` applies axis-aware polarity (lower-is-better for tokens/time/cost; higher-is-better for accuracy) and SC-AE-003's test fixture passes.

**Recommended follow-on**: Update `spec.md` FR-AE-005 and `contracts/interfaces.md §4` to make axis-aware `equal_or_better` polarity explicit. Capture as a `.kiln/issues/` entry on the next pipeline run; not a ship-blocker.

### Discoverability nit: `audit-pricing-staleness.sh`

`FR-AE-013` (pricing-table-stale tripwire, ≥180d) currently lives only in the SC-AE-007 fixture's inline mtime probe logic. A standalone `audit-pricing-staleness.sh` helper would be more discoverable for future auditors. Not a blocker — the tripwire is verified to fire, and the auditor's responsibility is documented in spec.

### Structural fixture for SC-AE-008 atomic pairing

SC-AE-008 (atomic pairing of `pricing.json` + `research-rigor.json` + `research-runner.sh`) is currently verified by the auditor running `git diff main...HEAD --name-only`. A dedicated `run.sh` fixture wired into `/kiln:kiln-test` would make this reproducible at CI time. Not a blocker — the structural check passed and is documented.

---

## Conclusion

Ship-ready. Three follow-on improvements documented above for the next pipeline run.
