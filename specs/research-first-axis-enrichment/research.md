# Research — research-first-axis-enrichment

## §baseline (current-main measurements, captured 2026-04-25)

### FR-010 pricing confirmation

Source: <https://platform.claude.com/docs/en/docs/about-claude/pricing> (resolved redirect from `https://docs.anthropic.com/en/docs/about-claude/pricing`). Page renders the canonical "Model pricing" table; consumer-facing `https://www.anthropic.com/pricing` redirects to `https://claude.com/pricing` and DOES NOT publish per-MTok rates (plan-level only).

Per-MTok rates as of 2026-04-25:

| model                       | input_per_mtok | output_per_mtok | cached_input_per_mtok | source |
|-----------------------------|----------------|------------------|------------------------|--------|
| claude-opus-4-7             | $5.00          | $25.00           | $0.50                  | platform.claude.com/docs (Model pricing → "Claude Opus 4.7" row, "Cache Hits & Refreshes" col) |
| claude-sonnet-4-6           | $3.00          | $15.00           | $0.30                  | platform.claude.com/docs (Model pricing → "Claude Sonnet 4.6" row) |
| claude-haiku-4-5-20251001   | $1.00          | $5.00            | $0.10                  | platform.claude.com/docs (Model pricing → "Claude Haiku 4.5" row) |

**PRD-vs-confirmed deltas — implementer MUST overwrite the PRD example values in `plugin-kiln/lib/pricing.json`:**

| model                       | PRD example (FR-010)               | Confirmed (2026-04-25)              | Delta |
|-----------------------------|-------------------------------------|--------------------------------------|-------|
| claude-opus-4-7             | $15 / $75 / $1.50                   | **$5 / $25 / $0.50**                 | PRD example tracks Opus 4 / 4.1 legacy pricing — Opus 4.5+ is 1/3 the rate. Implementer MUST replace. |
| claude-sonnet-4-6           | $3.00 / $15.00 / $0.30              | $3.00 / $15.00 / $0.30               | match — ship as-PRD'd. |
| claude-haiku-4-5-20251001   | $0.80 / $4.00 / $0.08               | **$1.00 / $5.00 / $0.10**            | PRD example tracks Haiku 3.5 — Haiku 4.5 is 25% more expensive. Implementer MUST replace. |

Two of three rows in the PRD example are wrong. SC-004 ("research run mixing fixtures from `claude-opus-4-7` and `claude-haiku-4-5-20251001` MUST produce per-fixture `cost_usd` matching hand-computed `(in × $/in + out × $/out) / 1_000_000` to within 4 decimal places") will fail unless the implementer ships the confirmed rates above. Hand-computed checks in tests must use confirmed numbers.

### FR-005 time-noise calibration

- **Fixture used**: `plugin-wheel/tests/agent-resolver/run.sh` (Bash-only resolver fixture; representative of the harness floor, NOT a kiln-test → `claude --print` subprocess workload — see caveat below).
- **Runs**: 5, consecutive, single shell, no parallelism.
- **Per-run wall clock (seconds, monotonic clock via `python3 -c 'import time; print(time.monotonic())'`)**: [0.1864, 0.1834, 0.1763, 0.1942, 0.1696]
- **min**: 0.1696s **max**: 0.1942s **median**: 0.1834s **range**: 0.0246s (**13.41 %** of median)

**Recommendation**: the existing PRD-table values are **NOT appropriate at the harness floor** — observed 13.41 % run-to-run wobble blows past `feature` (2 %), `cross-cutting` (1 %), and `infra` (0 %) tolerances on this short fixture. BUT — the harness floor is the wrong baseline:

- `agent-resolver` is a 180 ms Bash fixture. `tolerance_pct` is meant to be applied against full kiln-test research runs that wrap a `claude --print --plugin-dir` subprocess. Real research-run wall-clock is dominated by API latency (5–60 s per call), so the same ±25 ms harness jitter shrinks from 13 % to <0.5 % of total when the denominator is a real subprocess.
- For the time axis to be meaningful, **single-run measurement on a sub-second fixture is degenerate** regardless of `tolerance_pct`. The PRD's "Risks & Open Questions → Time-axis noise floor" already calls this out and defers multi-run averaging.

**Concrete recommendations for the implementer**:
1. **Keep the PRD-table tolerance_pct values as-is** (5 / 2 / 1 / 0). They're reasonable when applied against real kiln-test research-run durations.
2. **Document a fixture-duration floor** below which the time axis is silently un-enforced (suggest ≥1 s; the harness jitter exceeds 1 % of any candidate ≤2 s wall-clock). Either implement as a runner-side guard (warn + skip time-axis enforcement) or as a research-run-author rubric ("don't gate on time for sub-second fixtures").
3. **If a maintainer hits time-axis flakes on real fixtures**, the FIRST response per PRD risk note is multi-run averaging, not silent tolerance widening. Time-axis flakes on first real use should land in `specs/research-first-axis-enrichment/blockers.md` for follow-on PRD scoping (matches `2026-04-24-research-first-time-and-cost-axes` source-item hint).

Verdict: **PRD-table tolerance_pct is appropriate for real research-run workloads** — DO NOT widen it pre-emptively. Add a sub-second-fixture guard or document the floor.

### NFR-002 monotonic-clock availability

Probed on macOS Darwin (this researcher's host):

| candidate | available? | notes |
|-----------|------------|-------|
| `gdate +%s.%N` (coreutils on macOS) | **NOT INSTALLED** (`which gdate` → not found; `brew list coreutils` → no output). |
| `/bin/date +%s.%N` (BSD date) | **WORKS (surprising)** — emits `1777155056.129807000` with 9-digit nanoseconds. BSD date on this macOS build (Darwin) appears to support `%N`. Verified `/bin/date +%N` → `127871000`. Cannot confirm whether ALL macOS versions ship a `%N`-aware BSD date — older / clean installs likely do not. |
| `python3 -c 'import time; print(time.monotonic())'` | **WORKS** (used for the timing measurements above). Genuinely monotonic, not affected by NTP slew. Available everywhere `python3` is. |
| Linux `date +%s.%N` | assumed-available (not measured on this macOS host) — GNU date supports `%N` natively. |

**Recommendation for runner startup check** (FR-009 anchor):

1. **Prefer `python3 -c 'import time; print(time.monotonic())'`** as the cross-platform monotonic source. It's the only candidate that's both (a) genuinely monotonic (immune to NTP slew, mid-run clock changes) and (b) portable across Linux + macOS without coreutils. `python3` is already a documented kiln dependency (Active Technologies block in CLAUDE.md). Zero new dependencies.
2. **Fallback ladder** if `python3` is unavailable for some reason:
   - `gdate +%s.%N` (Linux GNU date OR macOS+coreutils)
   - `/bin/date +%s.%N` (works on this macOS, may not work on older macOS)
   - **Abort, do NOT fall back to integer-second `date +%s`** — second-resolution is too coarse to detect anything but multi-second regressions; a fixture going from 800 ms → 1.2 s would be reported as 1 s → 1 s and silently pass the gate.
3. **Do NOT require `brew install coreutils`** as a precondition — gating on coreutils breaks zero-config consumer installs. The python3-first ladder makes coreutils optional.

The runner startup check (FR-009 anchor) should resolve the first available option from the ladder above and abort with a loud error if none resolves with sub-second precision. This matches NFR-002 ("no new runtime dependency"): `python3` is already required, so the ladder adds nothing.
