# Interface Contracts: Research-First Completion

**Feature**: research-first-completion
**Plan**: [../plan.md](../plan.md)
**Spec**: [../spec.md](../spec.md)
**Foundation contracts**: [`../../research-first-foundation/contracts/interfaces.md`](../../research-first-foundation/contracts/interfaces.md) (referenced as "foundation §N").
**Axis-enrichment contracts**: [`../../research-first-axis-enrichment/contracts/interfaces.md`](../../research-first-axis-enrichment/contracts/interfaces.md) (referenced as "axis-enrichment §N").
**Plan-time-agents contracts**: [`../../research-first-plan-time-agents/contracts/interfaces.md`](../../research-first-plan-time-agents/contracts/interfaces.md) (referenced as "plan-time-agents §N").
**Constitution Article**: VII (Interface Contracts Before Implementation — NON-NEGOTIABLE).

This document is the SINGLE SOURCE OF TRUTH for every signature in the net-new code paths AND every additive extension to existing scripts. Implementation MUST match these signatures exactly. If a signature needs to change, update this contract FIRST and re-run constitution check.

Foundation contracts (foundation §1..§11), axis-enrichment contracts (axis-enrichment §1..§9), and plan-time-agents contracts (plan-time-agents §1..§9) are unchanged where not extended below.

---

## §1 — Research-block frontmatter schema (canonical, all four surfaces)

**Anchors**: FR-001, FR-002, FR-003, FR-004, NFR-001, NFR-007.

The six research-block fields appear in YAML frontmatter on items, issues, feedback, and PRD frontmatter. All optional. All default-off (absence preserves pre-PR behavior).

**Canonical key shape** (YAML):

```yaml
needs_research: true | false                    # bool, optional
empirical_quality:                               # list, optional
  - metric: accuracy | tokens | time | cost | output_quality
    direction: lower | higher | equal_or_better
    priority: primary | secondary               # default: secondary
    rubric: <string>                            # required when metric: output_quality
fixture_corpus: synthesized | declared | promoted   # enum, optional
fixture_corpus_path: <repo-relative-path>            # required when fixture_corpus: declared|promoted
promote_synthesized: true | false                # bool, optional, default: false
excluded_fixtures:                               # list, optional
  - path: <repo-relative-path>
    reason: <string>
```

**Field contracts**:
- `needs_research` — bool. `true` enables research-first routing (FR-009). `false` is permitted but discouraged (validator emits `Warning: needs_research:false is the default — omit the key`). Absent → default false (no routing).
- `empirical_quality[]` — list. Per-entry: `metric ∈ ALLOWED_METRIC`, `direction ∈ ALLOWED_DIR`, `priority` defaults to `secondary` if omitted. `rubric: <non-empty-string>` is REQUIRED when `metric: output_quality` (per plan-time-agents FR-010). Duplicate metrics within a single source's `empirical_quality[]` fail validation.
- `fixture_corpus` — enum. `synthesized` triggers the synthesizer agent (per plan-time-agents). `declared` requires `fixture_corpus_path:`. `promoted` requires `fixture_corpus_path:` AND that the path points at an existing committed corpus.
- `fixture_corpus_path` — string. MUST be repo-relative; absolute paths fail with `Bail out! fixture-corpus-path-must-be-relative: <path>` (FR-003 / OQ-4).
- `promote_synthesized` — bool. Default `false`. Only meaningful when `fixture_corpus: synthesized`.
- `excluded_fixtures[]` — list. Per-entry: `path: <non-empty-string>`, `reason: <non-empty-string>`. Both required.

**Allowed enums**:
```
ALLOWED_METRIC = {accuracy, tokens, time, cost, output_quality}
ALLOWED_DIR    = {lower, higher, equal_or_better}
ALLOWED_PRI    = {primary, secondary}
ALLOWED_FIXTURE_CORPUS = {synthesized, declared, promoted}
```

**PRD frontmatter key order** (FR-004 — authoritative):
```
derived_from
distilled_date
theme
needs_research
empirical_quality
fixture_corpus
fixture_corpus_path
promote_synthesized
excluded_fixtures
```

**Backward compatibility invariant** (NFR-001): every existing artifact without research-block fields validates cleanly. Validators are additive.

---

## §2 — Shared validation helper signature

**Anchors**: FR-001, FR-002, FR-003, FR-004, Decision 3.

**Path**: `plugin-kiln/scripts/research/validate-research-block.sh`

**CLI**:
```
validate-research-block.sh <frontmatter-json>
```

**Input**: `<frontmatter-json>` is a JSON string (NOT a file path) — the projected frontmatter object emitted by the appropriate parser (`parse-item-frontmatter.sh` for items; `parse-prd-frontmatter.sh` for PRDs; new sibling parser for issues + feedback).

**Stdout**: one JSON object on a single line, jq -c -S byte-stable:
```json
{"ok": true, "errors": [], "warnings": ["..."]}
```
or
```json
{"ok": false, "errors": ["..."], "warnings": []}
```

**Field contracts**:
- `ok` — bool. `true` iff every error check passes; `false` if any error.
- `errors[]` — list of strings. Each string is a human-readable error message naming the violating field.
- `warnings[]` — list of strings. Used for warn-but-pass cases (unknown research-block keys, `needs_research: false` discouraged, `needs_research: true` without `fixture_corpus:`).

**Exit code**: 0 always (validation result is in JSON, not exit code — matches `validate-item-frontmatter.sh` precedent).

**Validation rules** (canonical — implements FR-001/FR-002/FR-003):
1. If `needs_research` present → must be `true | false`.
2. If `empirical_quality[]` present:
   - Each entry has `metric ∈ ALLOWED_METRIC`. Else error `unknown metric: <value>`.
   - Each entry has `direction ∈ ALLOWED_DIR`. Else error `unknown direction: <value>`.
   - Each entry's `priority` defaults to `secondary` if omitted; if present must be `∈ ALLOWED_PRI`.
   - If `metric: output_quality` → `rubric: <non-empty-string>` REQUIRED. Else error `output_quality-axis-missing-rubric`.
   - Duplicate `metric` within the array → error `duplicate metric: <value>`.
3. If `fixture_corpus` present → must be `∈ ALLOWED_FIXTURE_CORPUS`.
4. If `fixture_corpus ∈ {declared, promoted}` → `fixture_corpus_path:` REQUIRED. Else error `fixture-corpus-path-required-when-declared-or-promoted`.
5. If `fixture_corpus_path` present → MUST be repo-relative (no leading `/`). Else error `fixture-corpus-path-must-be-relative: <path>`.
6. If `fixture_corpus: synthesized` AND `fixture_corpus_path:` present → warning `fixture-corpus-path-ignored-with-synthesized: <path>`.
7. If `excluded_fixtures[]` present → each entry has non-empty `path:` AND non-empty `reason:`. Else error.
8. Unknown research-block-shaped keys → warning `unknown research-block field: <key>` (warn-but-pass per OQ resolution).
9. `needs_research: false` → warning `needs_research:false is the default — omit the key`.
10. `needs_research: true` AND `fixture_corpus:` absent → warning `needs_research:true without fixture_corpus — variant pipeline will bail at corpus-load`.

**Reentrant**: same input → byte-identical output (NFR-001 sibling).

---

## §3 — `parse-prd-frontmatter.sh` additive projections

**Anchors**: FR-004, FR-009, NFR-009 (preserves axis-enrichment §3 contract).

**Existing contract (axis-enrichment §3)**: emits `{"blast_radius": ..., "empirical_quality": [...], "excluded_fixtures": [...]}` JSON projection. This contract is UNCHANGED for those three fields.

**Additive extension** (this PR): three more field projections appended to the projection object. New canonical projection:
```json
{
  "blast_radius": "isolated" | "feature" | "cross-cutting" | "infra" | null,
  "empirical_quality": [...] | null,
  "excluded_fixtures": [...] | null,
  "fixture_corpus": "synthesized" | "declared" | "promoted" | null,
  "fixture_corpus_path": "<repo-relative-path>" | null,
  "needs_research": true | false | null,
  "promote_synthesized": true | false | null
}
```

**Sort invariant**: keys are sorted ASC alphabetically (`json.dumps(..., sort_keys=True)`). This re-sorts the existing three keys; the alphabetical sort is byte-stable and deterministic.

**Exit-code invariant** (NFR-009): the existing exit codes (0 success, 2 malformed) are preserved. The new fields are projected as `null` when absent (matches existing pattern). Malformed values fail loudly per NFR-007:
- `fixture_corpus` ∉ ALLOWED_FIXTURE_CORPUS → exit 2 with `Bail out! parse error: unknown fixture_corpus: <value>`.
- `fixture_corpus_path` is absolute → exit 2 with `Bail out! parse error: fixture-corpus-path-must-be-relative: <path>`.
- `needs_research` not bool-shaped → exit 2 with `Bail out! parse error: needs_research must be true|false`.
- `promote_synthesized` not bool-shaped → exit 2 with `Bail out! parse error: promote_synthesized must be true|false`.

**Backward compatibility** (NFR-009 + NFR-001): a PRD without any research-block fields produces the same JSON projection as pre-PR (with `needs_research: null`, `fixture_corpus: null`, `fixture_corpus_path: null`, `promote_synthesized: null` ADDED to the existing three null-able fields). Callers that read only the existing three fields continue to work unchanged.

**Reentrant**: same input → byte-identical output (NFR-AE-002 sibling carried forward).

---

## §4 — `classify-description.sh` extension (research_inference)

**Anchors**: FR-013, FR-014, FR-016.

**Existing contract**: emits `{"surface": ..., "kind": ..., "confidence": ..., "alternatives": [...]}` JSON. UNCHANGED.

**Additive extension**: when comparative-improvement signal words match, the output JSON gains an OPTIONAL `research_inference` key. When NO signal matches, the key is OMITTED entirely (NOT `null`, NOT empty object — false-negative recovery is structural).

**`research_inference` shape** (when present):
```json
{
  "needs_research": true,
  "matched_signals": ["<signal-word>", ...],
  "proposed_axes": [
    {"metric": "...", "direction": "...", "priority": "..."},
    ...
  ],
  "rationale": "matched signal word: <word>"
}
```

For axes including `metric: output_quality`, the rationale ALSO includes the verbatim FR-016 warning string on a separate line:
```
matched signal word: clearer
(`output_quality` enables the judge-agent — see `2026-04-24-research-first-output-quality-judge.md` for drift-risk caveats)
```

**Signal word list (FR-013)** — case-insensitive whole-word match:
```
faster | slower | cheaper | "more expensive" | reduce | increase
optimize | efficient | "compare to" | versus | "vs " | "better than"
regression | improve | degradation
```
Plus the axis-inference-only signals (not in PRD list but referenced by FR-014 axis table):
```
latency | tokens | cost | expensive | smaller | concise | verbose
accurate | wrong | clearer | "better-structured" | "more actionable"
```

**Axis-inference table (FR-014)**:

| Signal(s)                                                     | Inferred axes                                                                |
|---------------------------------------------------------------|------------------------------------------------------------------------------|
| `faster | slower | latency`                                   | `[{metric: time, direction: lower}]`                                         |
| `cheaper | tokens | cost | "more expensive" | expensive`      | `[{metric: cost, direction: lower}, {metric: tokens, direction: lower}]`     |
| `smaller | concise | verbose`                                 | `[{metric: tokens, direction: lower}]`                                       |
| `accurate | wrong | regression`                               | `[{metric: accuracy, direction: equal_or_better}]`                           |
| `clearer | "better-structured" | "more actionable"`           | `[{metric: output_quality, direction: equal_or_better}]` + FR-016 warning   |
| `compare to | versus | "vs " | "better than" | improve | optimize | efficient | degradation | reduce | increase` | `[]` (no axis-inference; emit `needs_research: true` only with rationale)    |

**Priority assignment**: every inferred axis gets `priority: primary` by default. Maintainer can `tweak` to change.

**Multi-signal handling**: if a description matches multiple signals (e.g., "make it faster AND cheaper"), the `matched_signals` array contains all matches AND the `proposed_axes` array is the SET-UNION of all inferred axes (deduplicated by `metric`). Same union-merge semantics as FR-005 distill propagation.

**CLI surface** (existing UNCHANGED):
```
classify-description.sh <description>
```

The `research_inference` key is appended to the existing JSON output; no new CLI flag is needed (the behavior is "always run inference; emit only when matches").

**Exit code**: 0 always (matches existing contract).

---

## §5 — `kiln-distill` SKILL.md propagation step (canonical jq expression)

**Anchors**: FR-005, FR-006, FR-007, FR-008, NFR-003, NFR-005, Decision 5.

The propagation step in `/kiln:kiln-distill` SKILL.md MUST use the following jq expression to compute the union-merged `empirical_quality[]` axes from N source frontmatter JSON projections. The expression is the single source of truth for axis ordering (NFR-003 determinism hook).

**Inputs**: an array of source-frontmatter JSON projections (each is the output of the appropriate parser per artifact type), e.g.:
```json
[
  {"empirical_quality": [{"metric": "tokens", "direction": "lower", "priority": "primary"}], ...},
  {"empirical_quality": [{"metric": "time", "direction": "lower", "priority": "secondary"}], ...},
  {"empirical_quality": null, ...}
]
```

**Canonical jq expression** (axis-merge with priority promotion):
```
[.[] | (.empirical_quality // []) | .[]]
| group_by(.metric + ":" + .direction)
| map({
    metric: .[0].metric,
    direction: .[0].direction,
    priority: (
      if any(.priority == "primary") then "primary" else "secondary" end
    )
  } + (
    if .[0].metric == "output_quality" then {rubric: .[0].rubric} else {} end
  ))
| sort_by(.metric, .direction)
```

**Conflict detection (FR-006)**: BEFORE the union-merge, distill MUST detect conflicting `direction` values for the same `metric`. The detection jq expression:
```
[.[] | (.empirical_quality // []) | .[]]
| group_by(.metric)
| map(select((map(.direction) | unique | length) > 1))
```
A non-empty result indicates conflicts; distill MUST surface the FR-006 conflict prompt (per §6 below) before proceeding to the union-merge above.

**Scalar-key propagation (FR-007)**: `fixture_corpus`, `fixture_corpus_path`, `promote_synthesized` propagate VERBATIM from sources. When two sources declare different values, distill MUST surface a confirm-never-silent prompt of the same shape as FR-006 (per §6 below). When only one source declares, that source's value propagates unchanged.

**`excluded_fixtures[]` propagation (FR-007)**: list-keyed values are union-merged on `path`. Duplicate `path` with different `reason` triggers the §6 conflict prompt.

**`needs_research` propagation (FR-005)**: `true` iff ANY selected source declares `needs_research: true`. Otherwise OMITTED from the generated PRD frontmatter (NOT `false` — false-default is structural absence per NFR-005 byte-identity).

**Byte-identity fallback (FR-008, NFR-005)**: when `needs_research` is OMITTED (no source declares true), distill emits PRD frontmatter with the existing three keys ONLY (`derived_from`, `distilled_date`, `theme`). NO research-block keys appear. This is the byte-identity reference path.

**Determinism (NFR-003)**: re-running the propagation on unchanged inputs produces byte-identical PRD frontmatter. Verified by `plugin-kiln/tests/distill-research-block-determinism/`.

---

## §6 — FR-006 conflict prompt shape (distill ambiguity resolution)

**Anchors**: FR-006, FR-007, NFR-004.

When distill detects a conflict (per §5 conflict detection), it surfaces this prompt to stdout (NOT stderr — the prompt expects user input on stdin):

**Canonical prompt shape**:
```
Conflict on <key>: <metric-or-scalar-key>
  <source-path-A> declares <key>: <value-A>
  <source-path-B> declares <key>: <value-B>
  [<source-path-C> declares <key>: <value-C>]
  ...
Pick one <key> or specify a third.
> _
```

**Field contracts**:
- `<key>` — either `direction` (for `empirical_quality[]` direction conflicts) OR a scalar-key name (`fixture_corpus`, `promote_synthesized`, etc.).
- `<metric-or-scalar-key>` — for axis conflicts, the conflicting `metric` (e.g., `tokens`); for scalar conflicts, the scalar key name (e.g., `fixture_corpus`).
- `<source-path-X>` — relative path to the source artifact, exactly as it appears in `derived_from:` (e.g., `.kiln/feedback/2026-04-15-foo.md`).
- `<value-X>` — the conflicting value verbatim from the source frontmatter.

**Multi-conflict handling**: when multiple metrics conflict (e.g., `tokens` AND `time` both have direction conflicts), distill emits ONE block per metric, separated by blank lines. NO cap on N (OQ-1 resolution). User responds to each block sequentially.

**User input**:
- Typing one of the listed `<value-X>` values → resolves with that value.
- Typing a fresh value → validated against the relevant ALLOWED enum; on success resolves with the fresh value; on failure re-prompts.
- Typing `abandon` (or sending EOF) → distill exits 2 without writing the PRD.
- Empty input → re-prompts.

**Verbatim contract (NFR-004)**: the prompt MUST contain both source paths AND both value pairs. Bad shape: "axes conflict, please resolve." Good shape: see template above.

**Test fixture**: `plugin-kiln/tests/distill-axis-conflict-prompt/` asserts the exact prompt shape against a fixture backlog with two items declaring `metric: tokens` with different directions.

---

## §7 — `kiln-build-prd` SKILL.md Phase 2.5 stanza signature

**Anchors**: FR-009, FR-010, FR-011, FR-012, NFR-002, Decision 2, Decision 7.

**Insertion point**: between the existing `/tasks` step and the existing `/implement` step in `plugin-kiln/skills/kiln-build-prd/SKILL.md`. New step is named "Phase 2.5: research-first variant".

**Skip-path probe** (NFR-002 byte-identity):
```bash
# Single jq lookup on already-parsed frontmatter JSON
NEEDS_RESEARCH=$(jq -r '.needs_research // false' <<<"$PRD_FRONTMATTER_JSON")
if [ "$NEEDS_RESEARCH" != "true" ]; then
  # Skip path — structural no-op, NO stdout, NO log line
  return 0
fi
```

**Variant pipeline (FR-010)** — runs only when `NEEDS_RESEARCH == "true"`:
1. **establish-baseline** — invoke `plugin-wheel/scripts/harness/research-runner.sh` with the baseline plugin-dir against the declared corpus. Capture metrics to `.kiln/research/<prd-slug>/baseline-metrics.json`.
2. **implement-in-worktree** — `git worktree add <tempdir> <branch>` (per Decision 4); run `/implement` in the worktree; record the worktree path for cleanup.
3. **measure-candidate** — invoke `research-runner.sh` with the candidate plugin-dir (from the worktree) against the SAME corpus. Capture metrics to `.kiln/research/<prd-slug>/candidate-metrics.json`.
4. **gate** — invoke `evaluate-direction.sh` for mechanical axes (per axis-enrichment §4); invoke `evaluate-output-quality.sh` for the `output_quality` axis (per plan-time-agents §4). Capture per-axis verdicts to `.kiln/research/<prd-slug>/per-axis-verdicts.json` (foundation precedent — this PR does NOT modify its shape).
5. **gate-pass branch** — if every axis returns `pass`, continue to the existing `/audit` + PR-creation steps. The auditor MUST inject the FR-012 `## Research Results` section into the PR body.
6. **gate-fail branch** — if ANY axis returns `regression`, HALT BEFORE invoking `/audit` or PR-creation. Surface the verbatim per-axis report (read from `per-axis-verdicts.json`); emit `Bail out! research-first-gate-failed: <prd-slug>` to stderr; exit 2.

**Worktree cleanup**: regardless of branch, the SKILL.md MUST run `git worktree remove --force <tempdir>` after the gate completes (success OR fail). Cleanup is in a `trap` block to survive interruptions.

**Gate-fail invariant (FR-011)**: the auditor agent + PR-creation agent are NEVER spawned on the gate-fail path. The SKILL.md prose MUST explicitly forbid spawning them; reviewer-visible invariant.

**Gate-pass auditor input (FR-012)**: the auditor receives an additional input: the path to `.kiln/research/<prd-slug>/per-axis-verdicts.json` AND the path to the research report at `.kiln/logs/research-<uuid>.md`. The auditor's PR body composition MUST insert a `## Research Results` heading with the per-axis pass-status table (shape per spec FR-012).

**Skip-path observability (Decision 7, OQ-6)**: NO stdout on skip path. NO log line. True byte-identity per NFR-002. If a follow-on PR needs skip-path observability, that's OQ-6 work.

---

## §8 — Coached-capture interview integration (FR-015 single-question stanza)

**Anchors**: FR-015, FR-016, NFR-006, Decision 9.

**Insertion point**: each capture-skill SKILL.md (`/kiln:kiln-roadmap`, `/kiln:kiln-report-issue`, `/kiln:kiln-feedback`) gains ONE new question stanza in the coached-capture interview. The stanza is conditional on `research_inference != null` in the classifier output JSON; absent → silently skipped.

**Question stanza shape** (per `coach-driven-capture-ergonomics` FR-004 §5.0):
```
Q: Does this need research?
   Proposed: needs_research: true
             empirical_quality:
               - metric: tokens
                 direction: lower
                 priority: primary
   Why: matched signal word: cheaper
   [accept / tweak <value> / reject / skip / accept-all]
   > _
```

**For axes including `output_quality` (FR-016)**: the `Why:` line gains a second line — the verbatim warning:
```
   Why: matched signal word: clearer
        (`output_quality` enables the judge-agent — see `2026-04-24-research-first-output-quality-judge.md` for drift-risk caveats)
```

**Response handling** (per §5.0a response parser):
- `accept` → write the proposed research-block keys verbatim into the artifact frontmatter.
- `tweak <value>` → re-render the question with the maintainer's edited proposal; loop until accept/reject/skip.
- `reject` → write NO research-block keys (NFR-006 structural absence).
- `skip` → equivalent to `reject` for this question (no research-block keys written).
- `accept-all` → accept this proposal AND auto-accept all subsequent questions in the interview.

**False-negative recovery**: when `research_inference` is absent from the classifier output, the question is NEVER rendered. The maintainer can hand-add research-block frontmatter to the captured artifact later.

**Test fixtures**:
- `plugin-kiln/tests/classifier-research-inference/` exercises the question rendering with positive matches.
- `plugin-kiln/tests/classifier-research-rejection-recovery/` exercises the structural-absence on reject.
- `plugin-kiln/tests/classifier-output-quality-warning/` exercises the FR-016 verbatim warning.
- `plugin-kiln/scripts/research/lint-classifier-output-quality-warning.sh` asserts the literal warning string in classifier output JSON.

---

## §9 — E2E fixture CLI surface

**Anchors**: FR-017, FR-018, FR-019, NFR-008, SC-005, Decision 10.

**Path**: `plugin-kiln/tests/research-first-e2e/run.sh`

**CLI**:
```
run.sh                          # default: run BOTH happy and regression sub-paths
run.sh --scenario=happy         # run only happy sub-path
run.sh --scenario=regression    # run only regression sub-path
```

**Default invocation behavior**: runs `--scenario=happy` first, then `--scenario=regression`, with a temp-dir reset between them. The fixture's last-line `PASS` is emitted ONLY if BOTH sub-paths pass. Exit 0 on success.

**Per-sub-path stdout invariant**:
- Happy sub-path: stdout contains the literal token `research-first variant invoked`, contains `gate pass`, does NOT contain `gate fail`. Final assertion: `PR created (mocked)` literal token.
- Regression sub-path: stdout contains the literal token `research-first variant invoked`, contains `gate fail`, does NOT contain `PR created`. Final assertion: pipeline halted before PR creation.

**Fixture scaffolding (NFR-008)**:
- `mktemp -d` creates an isolated temp dir.
- A minimal `kiln-init` mock copies `.kiln/`, `plugin-kiln/scripts/`, `plugin-wheel/scripts/` subset into the temp dir.
- A roadmap item is written declaring `needs_research: true` + `empirical_quality: [{metric: tokens, direction: lower}]` + `fixture_corpus: declared` + `fixture_corpus_path: fixtures/corpus/`.
- Two fixture files in `fixtures/corpus/` provide the corpus.
- `/kiln:kiln-distill` is invoked via direct script invocation OR mocked SKILL.md execution; PRD is written; assertion fires that the PRD frontmatter inherits the research block.
- `/kiln:kiln-build-prd` is invoked similarly; the variant pipeline runs against mocked baseline + candidate outputs.
- For happy: candidate outputs match baseline byte-for-byte (or improve); gate returns pass.
- For regression: candidate outputs are deliberately worse on `metric: tokens` (e.g., 10x larger); gate returns regression on that axis.

**Mocking strategy** (Decision 10):
- LLM-spawning steps are mocked via shell scripts that write predetermined output.
- `git worktree add` is mocked or replaced with `cp -R` for the test (the variant pipeline's worktree mechanism is NOT under test here; the gate's behavior is).
- GitHub API calls are mocked (no real PR is created; the mock writes to a known stdout token).

**Live `claude` CLI invocation forbidden** (NFR-008 + CLAUDE.md Rule 5).

**Runtime budget** (NFR-008 informational): ≤ 30s on developer macOS.

**`/kiln:kiln-test` harness wiring (FR-019)**: the fixture is registered as a test under `plugin-kiln/tests/research-first-e2e/` matching the existing harness convention. Direct invocation `bash plugin-kiln/tests/research-first-e2e/run.sh` is the canonical evidence path (PASS-cite fallback per issue #181 PI-2).

---

## §10 — `lint-classifier-output-quality-warning.sh` (FR-016 / SC-011)

**Anchors**: FR-016, SC-011.

**Path**: `plugin-kiln/scripts/research/lint-classifier-output-quality-warning.sh`

**CLI**:
```
lint-classifier-output-quality-warning.sh <classifier-output-json>
```

**Input**: a JSON string (the output of `classify-description.sh`).

**Behavior**:
1. Parse the JSON via `jq`.
2. If `research_inference` is absent → exit 0 (nothing to lint).
3. If `research_inference.proposed_axes[]` does NOT contain `metric: output_quality` → exit 0.
4. If `research_inference.rationale` does NOT contain the verbatim FR-016 warning string → exit 2 with `Bail out! lint-classifier-output-quality-warning: missing verbatim warning`.
5. If contains the verbatim warning → exit 0.

**Verbatim warning string** (single literal — copy character-for-character):
```
(`output_quality` enables the judge-agent — see `2026-04-24-research-first-output-quality-judge.md` for drift-risk caveats)
```

**Exit codes**: 0 PASS, 2 FAIL.

---

## §11 — Test fixture matrix (anchored to Success Criteria)

| SC    | Fixture path                                                   | What it asserts                                                              |
|-------|----------------------------------------------------------------|------------------------------------------------------------------------------|
| SC-001 | `plugin-kiln/tests/classifier-research-inference/`            | "cheaper" / "faster" descriptions produce research-block proposals.          |
| SC-002 | `plugin-kiln/tests/distill-research-block-propagation/`       | Distill propagates research block from source into PRD frontmatter.          |
| SC-003 | `plugin-kiln/tests/build-prd-research-routing/`               | `needs_research: true` PRD invokes the variant pipeline.                     |
| SC-004 | `plugin-kiln/tests/build-prd-standard-routing-bytecompat/`    | No-research-block PRD routes byte-identically to pre-PR.                     |
| SC-005 | `plugin-kiln/tests/research-first-e2e/`                       | E2E fixture happy + regression both pass; PASS on last line.                 |
| SC-006 | `plugin-kiln/tests/distill-axis-conflict-prompt/`             | Distill conflict prompt fires with both source paths + both directions.     |
| SC-007 | `plugin-kiln/tests/distill-research-block-determinism/`       | Re-distill produces byte-identical PRD frontmatter.                          |
| SC-008 | `plugin-kiln/tests/classifier-research-rejection-recovery/`   | Reject → no research-block frontmatter (structural absence).                 |
| SC-009 | `plugin-kiln/tests/research-block-schema-validation/`         | Validator catches malformed values; warns on unknown keys.                   |
| SC-010 | `plugin-kiln/tests/classifier-axis-inference-mapping/`        | Each FR-014 signal-word → axes mapping is correct.                           |
| SC-011 | `plugin-kiln/tests/classifier-output-quality-warning/`        | output_quality proposals include the verbatim FR-016 warning.                |
| SC-011 | `plugin-kiln/scripts/research/lint-classifier-output-quality-warning.sh` | CI lint script asserts FR-016 warning verbatim.                            |

Each fixture has its own `run.sh` matching the existing kiln test convention. Last line includes `PASS` on success; non-zero exit on failure.
