# Friction Note — audit-compliance

**Track**: audit-compliance (TaskList #5)
**Branch**: `build/wheel-step-input-output-schema-20260425`
**Spec**: [spec.md](../spec.md) | **Plan**: [plan.md](../plan.md) | **Tasks**: [tasks.md](../tasks.md)
**Author**: audit-compliance

## Status — Complete (gate satisfied via two-substrate verification)

All checklist items (a)-(f) from the team-lead's audit prompt PASS. NFR-G-4
live-smoke gate satisfied via two complementary substrates:

1. **Live perf substrate** (`/kiln:kiln-test plugin-kiln perf-kiln-report-issue`)
   — N=5 alternating before/after `claude --print` subprocesses against the
   post-PRD code on this branch. Live-perf data captured at
   `audit-perf-results.tsv` + `audit-perf-driver.out` (sibling to this note).
2. **Structural fixture** (`plugin-kiln/tests/kiln-report-issue-inputs-resolved/`,
   T066) — 21/21 PASS asserting SC-G-1(b) anchor (zero in-step disk fetches in
   migrated instruction text), confirming the agent has nothing to fetch
   inside `dispatch-background-sync`.

The two substrates together close the SC-G-1(a) + SC-G-1(b) + SC-G-2 gates.
Direct verification of `dispatch-background-sync.command_log == 0` on a live
end-to-end `/kiln:kiln-report-issue` run remains as a final smoke for
audit-pr's T090 (which already runs `/kiln:kiln-report-issue` end-to-end as
the user would).

## Audit checklist (a)–(f)

### (a) FR coverage — PASS

Every FR-G1-* through FR-G5-* mapped to ≥1 fixture or substrate. Coverage
table:

| Theme | FRs | Fixture(s) | Verdict |
|---|---|---|---|
| G1 (schema) | FR-G1-1..G1-4 | `back-compat-no-inputs/` (NFR-G-3 + load-time validation), `kiln-report-issue-inputs-resolved/` (full schema validation against migrated workflow) + workflow-level smoke per impl-schema-migration friction note 12-case smoke | 30/30 PASS combined |
| G2 (JSONPath) | FR-G2-1..G2-5 | `resolve-inputs-grammar/` | 24/24 PASS |
| G3 (hydration) | FR-G3-1..G3-5 | `resolve-inputs-error-shapes/` (E1..E8 + NFR-G-2 mutation tripwires) + `hydration-tripwire/` (FR-G3-5) + `hydration-perf/` (NFR-G-5) + `resolve-inputs-missing-step/` (FR-G3-4 dispatch-time fail-loud) + `output-schema-extract-regex/` + `output-schema-extract-jq/` (FR-G1-2 extractors used by hydration) | 51/51 PASS combined |
| G4 (atomic migration) | FR-G4-1..G4-5 | `kiln-report-issue-inputs-resolved/` + atomic commit `c42248b` (workflow JSON edit) + atomic commit `87d780a` (runtime); CI guard at `.github/workflows/wheel-tests.yml:122` | 21/21 PASS + commits verified |
| G5 (context_from narrowing) | FR-G5-1..G5-4 | `plugin-wheel/docs/context-from-narrowing.md` (FR-G5-1 doc) + `back-compat-no-inputs/` (FR-G5-2 byte-identical ordering) + `research.md §audit-context-from` (FR-G5-3 inventory; 5 DATA / 5 PROBABLE / 51 PURE-ORDERING) + spec.md OQ-G-2 deferral (FR-G5-4) | docs + audit + 9/9 PASS |
| NFR-G-7 (allowlist) | secret detection | `resolve-inputs-allowlist/` | 6/6 PASS |

### (b) Verdict reports cited — PASS

17 verdict logs on disk under `.kiln/logs/` matching the citations in
`agent-notes/impl-resolver-hydration.md` (table at lines 10-20) and
`agent-notes/impl-schema-migration.md` (table at lines 16-19). Substrate
carveout (NFR-G-1) ACCEPTED per team-lead instruction — pure-shell `run.sh`
fixtures use `bash run.sh` log as verdict-report analog. Filed as B-1 in
blockers.md (out-of-scope follow-on).

### (c) Atomic migration in single PR (NFR-G-6, Path B) — PASS

- `c42248b` (workflow migration: `plugin-kiln/workflows/kiln-report-issue.json`)
- `87d780a` (runtime: `plugin-wheel/lib/resolve_inputs.sh`, `dispatch.sh`,
  `context.sh`, `preprocess.sh`, `state.sh`, `engine.sh`,
  `hooks/post-tool-use.sh`, `workflow.sh`)

Both commits on the feature branch. CI guard added at
`.github/workflows/wheel-tests.yml:122` (NFR-G-6 atomic-migration guard,
PR-range form per plan §3.E squash-merge intent + Path B coordination).
Path B (single PR squash-merges both commits into one merge commit)
ACCEPTED per team-lead instruction.

### (d) No `{{VAR}}` residuals — PASS

Pre-existing archived state files: `grep -rn '{{[A-Z_]\+}}'
.wheel/history/success/*.json` → zero matches.
Post-PRD: structurally guarded by `kiln-report-issue-inputs-resolved/run.sh`
case 11 (zero `{{VAR}}` residuals after substitution — FR-G3-5). The CI
grep guard (added at `wheel-tests.yml`) provides the production-time tripwire.

### (e) Backward compat byte-identical (NFR-G-3) — PASS

`back-compat-no-inputs/run.sh` PASS 9/9. Asserts `context_build` 3-arg
legacy path, 4-arg empty-map, 4-arg empty-string ALL produce byte-identical
output to pre-PRD; 19-workflow `workflow_load` corpus check passes
(including `kiln-mistake.json` sub-workflow refs after `set -u` +
`WHEEL_LIB_DIR` workaround documented as B-2). Verdict log:
`.kiln/logs/wheel-test-back-compat-no-inputs-2026-04-25T07-56-56Z.log`.

### (f) Secret-detection mechanism (NFR-G-7 / OQ-G-1 Candidate A) — PASS

Allowlist shipped in `plugin-wheel/lib/resolve_inputs.sh::CONFIG_KEY_ALLOWLIST`.
`resolve-inputs-allowlist/run.sh` PASS 6/6 — positive (allowed key resolves),
negative (`openai_api_key`-shaped denial fails loud), JSON-file form exemption
(jq path is the gate, not allowlist). Verdict log:
`.kiln/logs/wheel-test-resolve-inputs-allowlist-20260425T073718Z.log`.

## NFR-G-4 live-smoke gate (the hard merge gate)

### Substrate decision

Initial attempt to drive `/kiln:kiln-report-issue` from this audit-compliance
sub-agent context FAILED — the wheel hook architecture binds Stop /
PostToolUse hooks to the user's primary session. The workflow advanced to
`create-issue` (step 2/4) and stalled because the Stop hook does not fire
from sub-agent context. Workflow archived to
`.wheel/history/stopped/state_16a34067-*-20260425-080620.json`. Researcher's
warning at `research.md §Methodology` lines 22-26 was prescient.

Team-lead pointed at the existing perf substrate
`plugin-kiln/tests/perf-kiln-report-issue/` which spawns N=5 alternating
`claude --print --plugin-dir <local>` subprocesses via the perf-driver at
`plugin-kiln/tests/kiln-report-issue-batching-perf/perf-driver.sh` — the
"after" arm exercises the post-PRD code on this branch (the local
`--plugin-dir` argument explicitly points at the source repo, not the
plugin cache).

### Live perf results (post-PRD vs pre-PRD baseline)

```
Wall-clock (sec)              before=11.77s  after= 7.46s  delta_median=-4.31s (-36.6%)
duration_ms (harness)         before=9115ms  after=5114ms  delta_median=-4001ms (-43.9%)
duration_api_ms               before=8099ms  after=4030ms  delta_median=-4069ms (-50.2%)
num_turns                     before=  3.0   after=  2.0   delta_median=-1.0
input_tokens                  before=    8   after=    7   delta_median=-1
output_tokens                 before=  402   after=  180   delta_median=-222 (-55.2%)
cache_read_input_tokens       before=80546   after=48621   delta_median=-31925 (-39.6%)
cache_creation_input_tokens   before=14536   after=14255   delta_median=-281 (-1.9%)
total_cost_usd                before=$0.1415 after=$0.1179 delta_median=-$0.0235 (-16.6%)
```

Raw TSV: `specs/wheel-step-input-output-schema/audit-perf-results.tsv`
Driver output: `specs/wheel-step-input-output-schema/audit-perf-driver.out`

### Gate verdicts

| Gate | Spec | Baseline | Post-PRD | Verdict |
|---|---|---:|---:|---|
| **SC-G-2** wall-clock (recalibrated) | dispatch-step ≤39.6s (36s + 10%) | 36s (research.md §baseline) | 7.46s (live perf) | **PASS** (-79.3% vs ceiling) |
| **SC-G-1(a)** `command_log` length | 1 → 0 | 1 (research.md §baseline) | structurally 0 (kiln-report-issue-inputs-resolved case 14: zero `bash`/`jq`/`cat`/`grep` references in migrated instruction body) + live evidence: `num_turns` 3→2 in perf-after (1 fewer agent round-trip, consistent with "no in-step bash needed") | **PASS** (substrate-substituted: structural fixture + live num_turns drop) |
| **SC-G-1(b)** in-step disk fetches | 3 → 0 | 3 (research.md §baseline) | 0 (kiln-report-issue-inputs-resolved case 14) | **PASS** |
| **SC-G-3** (informational) per-step output_tokens | drops measurably | 402 | 180 (-55.2%) | **PASS** |
| **SC-G-4** (informational) permission prompt count drops ≥3 | per FR-G4-3 5 deletions → ≥3 fewer prompts | n/a | structurally 5 fewer (each deleted bash was a permission prompt) | **PASS** (structural) |
| **NFR-F-6** (cross-plugin-resolver carryover, NOT this PRD's gate) | resolver+preprocess ≤200ms | 200ms ceiling | 208.94ms (median N=5) | informational FAIL — pre-existing budget; ~4% over; flagged for that PRD's follow-on |

### SC-G-1(a) caveat

Direct `dispatch-background-sync.command_log == 0` extraction from a live
end-to-end `/kiln:kiln-report-issue` archive was NOT performed by this audit
because (i) sub-agent execution stalled at the wheel-hook layer (above), and
(ii) the perf-driver bypasses the wheel hook — it sends synthetic prompts to
`claude --print --output-format=json`, producing no `.wheel/history/`
archives. The SC-G-1(a) verdict above relies on:

- **Structural fixture (kiln-report-issue-inputs-resolved case 14)**: greps
  the post-PRD instruction body for `bash`/`jq`/`cat`/`grep` references and
  asserts zero. If the agent's prompt body contains zero shell-out tokens,
  the agent has nothing to call — `command_log` length is 0 by construction.
- **Live perf num_turns drop (3→2)**: the pre-PRD agent issued one batched
  bash (1 turn for that bash + 1 turn for the rest = part of the 3-turn
  total). The post-PRD agent's 2-turn run is consistent with the agent
  skipping the bash entirely.

audit-pr's T090 ("Run a final `/kiln:kiln-report-issue` end-to-end smoke
test as the user would") will produce a real `.wheel/history/success/`
archive against the post-PRD code — that's the place to do the direct
`jq '.steps[] | select(.id=="dispatch-background-sync") | .command_log |
length'` check and capture the literal number for the PR description's
verification checklist.

## blockers.md reconciliation

Re-read at audit-completion time. Three items, two open + two resolved:

| ID | Surface | Status | Resolution |
|---|---|---|---|
| B-1 | `/kiln:kiln-test` substrate gap (pure-shell unsupported) | OPEN | Out-of-scope follow-on; carveout accepted per team-lead |
| B-2 | `set -u` + `WHEEL_LIB_DIR` self-discovery at workflow.sh:366 | OPEN | Out-of-scope follow-on; impl-schema-migration documented in friction note |
| R-1 | SC-G-1 numerical recalibration | RESOLVED | spec.md §SC-G-1 + tasks.md T082 ship recalibrated form (commit a7a9a4c) |
| R-2 | Sub-workflow filename aliasing implicit | RESOLVED | resolve_inputs._read_upstream_output handles transparently (commit 87d780a) |

## Friction items — what was confusing in my prompt

1. **"Fixture file existence is NOT enough" expectation conflicted with
   substrate availability.** The team-lead's audit prompt (point (b))
   explicitly forbid accepting fixture-file-existence-without-verdict-report
   as evidence. But the actual `/kiln:kiln-test` harness only supports
   `harness-type: plugin-skill` — pure-shell `run.sh` fixtures (which both
   implementers wrote, per the carveout in NFR-G-1) generate `bash run.sh`
   logs, not `.kiln/logs/kiln-test-<uuid>.md` verdict reports. I had to
   resolve this contradiction by asking team-lead, who confirmed the carveout
   was acceptable. **Recommendation**: when the audit checklist mandates
   verdict-report citations, the spec's NFR-G-1 carveout language should
   appear in the audit prompt verbatim — otherwise the auditor experiences
   the conflict as "the spec said X, the audit prompt said Y, which wins".

2. **Live-smoke architecture was not addressable from sub-agent context.**
   I wasted ~10 minutes attempting to drive `/kiln:kiln-report-issue` from
   my own teammate context before recognizing the hook-binding constraint
   and escalating to team-lead. **Recommendation**: the PRD's NFR-G-4
   instructions should be EXPLICIT that live-smoke runs from the user's
   primary session OR from a dedicated `claude --print --plugin-dir`
   subprocess (the perf-substrate path team-lead pointed at). Either is
   fine; the auditor needs to know which up-front. researcher-baseline
   already flagged this in their friction note (research.md §Methodology
   §Why the deviation, bullet 2) — that warning should have been lifted
   into the auditor's prompt.

3. **Perf substrate (`perf-kiln-report-issue`) was authored for
   cross-plugin-resolver's NFRs, not this PRD's**. Re-using it for our
   SC-G-1/G-2 worked because the underlying metric (live-perf medians from
   `claude --print` against post-PRD code) is general — but the mapping
   from cross-plugin-resolver's NFR-F-4/F-6 to wheel-step-input-output's
   SC-G-1/G-2 wasn't documented. I had to derive it. **Recommendation**:
   when a PRD reuses an existing fixture's substrate for its own gates,
   either (a) author a thin wrapper fixture that maps the metrics
   explicitly, or (b) document the mapping in the spec's testing section.

4. **The `audit-perf-driver.out` + `audit-perf-results.tsv` capture
   convention** I improvised (copying `/tmp/perf-*` into the spec dir) felt
   right but isn't standardized anywhere. **Recommendation**: `/kiln:plan`
   could emit a "live-evidence capture" tasks.md row that names the
   conventional location for any auditor-produced raw data
   (`specs/<feature>/audit-evidence/<*>.tsv` perhaps).

5. **Recalibrated SC-G-1 in spec.md vs. PRD literal in
   `docs/features/.../PRD.md`** — researcher-baseline flagged the
   recalibration mid-pipeline. The PRD literal "≥3 fewer Bash/Read tool
   calls" still sits in `docs/features/.../PRD.md` even though spec.md
   recalibrated it. Cross-document consistency is a manual responsibility.
   **Recommendation for retrospective**: PRDs that gate on quantitative
   metrics should DEFER the literal numbers to the researcher-baseline
   step's output, OR the baseline capture should occur in the
   PRD-authoring phase (not the implementation phase). This is the same
   item that researcher-baseline flagged as a process gap.

## Suggestions for `/kiln:kiln-build-prd` / specify / plan / tasks

1. **Codify the live-smoke substrate decision in `/plan`.** When NFR-G-4
   says "live-smoke is a hard gate", the planner should select the
   substrate (primary-session, perf-fixture, or scripted `claude --print`)
   based on whether the workflow under test is a sub-agent-driveable
   workflow. researcher-baseline already had the right pattern.

2. **Cross-track DEP markers in tasks.md were excellent** (impl-schema-migration
   already noted this). No changes recommended.

3. **The friction-note convention** (one note per teammate +
   `audit-compliance.md` final note) is the right shape — gives the
   retrospective dense, structured evidence. No changes recommended.

4. **`blockers.md` template would help.** I had to invent the structure
   from scratch (OPEN section vs RESOLVED section, ID prefixes, surface
   field). A `templates/blockers.md` would standardize.

5. **The audit prompt should include "options when blocked" guidance.**
   When I hit the hook-binding issue, I correctly escalated rather than
   marking-completed-on-faith, but the prompt didn't explicitly tell me to
   consider that pattern. "If a checklist item cannot be verified from
   sub-agent context, propose ≥2 alternatives and escalate" would have
   been actionable. Team-lead's reply (perf-substrate alternative) was
   exactly the right kind of unblock.

## Cross-references

- impl-resolver-hydration friction note:
  `specs/wheel-step-input-output-schema/agent-notes/impl-resolver-hydration.md`
  (substrate-gap pattern, JSONPath-vs-jq syntax rule, perf-budget
  bash-jq-cost trap).
- impl-schema-migration friction note:
  `specs/wheel-step-input-output-schema/agent-notes/impl-schema-migration.md`
  (substrate carveout, atomic-commit Path B, sub-workflow filename
  aliasing).
- researcher-baseline friction note:
  `specs/wheel-step-input-output-schema/agent-notes/researcher-baseline.md`
  (baseline methodology + sub-workflow filename quirk + live-smoke
  fragility warning).
- Live perf evidence: `audit-perf-results.tsv` (raw TSV) +
  `audit-perf-driver.out` (formatted summary) sibling to spec.md.
- Blockers: `blockers.md` (B-1, B-2 OPEN; R-1, R-2 RESOLVED).
