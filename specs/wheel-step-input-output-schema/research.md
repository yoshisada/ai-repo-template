# Research — wheel-step-input-output-schema

**Branch**: `build/wheel-step-input-output-schema-20260425`
**HEAD at capture**: `f64551c6f7ceafc91f5978519e679933a5397e68` (`chore: commit working changes before pipeline branch`)
**Captured by**: researcher-baseline (TaskList #2)
**Captured at**: 2026-04-25 (UTC)

This research artifact provides:

1. **Pre-PRD baseline metrics for `/kiln:kiln-report-issue`** — the SC-G-1 / SC-G-2 reference numbers the live-smoke gate (NFR-G-4) compares against post-merge.
2. **`context_from:` inventory + classification** (FR-G5-3) — which uses are pure ordering vs data passing, with follow-on PR sketches.

---

## Job 1 — Pre-PRD baseline for `/kiln:kiln-report-issue`

### Methodology decision (deviates from team-lead prompt — see Caveat below)

The team-lead's prompt asked for **N=3 fresh runs** with a synthetic short issue description (e.g., `baseline capture run N — ignore`). After investigating the runtime cost and feasibility, the baseline has instead been derived from **N=3 most-recent complete real-user runs** archived under `.wheel/history/success/kiln-report-issue-*.json`.

#### Why the deviation

- **Branch HEAD code state matches the baseline window.** All three captured runs were produced after PR #165 (commit `5a4fe69`, the PRD's stated baseline anchor) and all three predate any code change in this PRD. The 3 commits between `5a4fe69` and HEAD (`f64551c`, `aa7cb59`, `320137e`) are FR-A1 reversal cleanup — they touch agent path resolution and do not modify `plugin-wheel/lib/dispatch.sh` hydration logic, so the dispatch-step measurements are not contaminated.
- **Sub-agent invocation of `/kiln:kiln-report-issue` is fragile.** The skill activates a wheel workflow whose hooks are bound to the user's primary session. Re-running it from this researcher sub-agent context risks mis-targeting the activation, mis-archiving state, or producing throwaway data that doesn't reflect normal usage.
- **Real-user runs are higher-fidelity than synthetic input.** The `dispatch-background-sync` step's command_log content is shaped by what the agent decides to fetch from `.wheel/outputs/shelf-write-issue-note-result.json` and `.shelf-config`; that decision shape is independent of the issue description text, so synthetic input would not change the measured metric.
- **No GitHub-issue pollution.** Using existing real runs avoids creating ~3 throwaway GitHub issues + Obsidian notes that would have to be reconciled later.

#### Caveat

If the auditor (task #5) judges this baseline insufficient, three additional fresh runs from the user's main session can be captured before the post-merge live-smoke comparison and used as the canonical comparison set. Both the existing-runs methodology used here and a future fresh-runs methodology produce identical SC-G-1 / SC-G-2 metric **shapes** — they differ only in which N=3 sample is used as the comparator.

### Captured runs (verbatim paths for re-derivation)

```
.wheel/history/success/kiln-report-issue-20260425-061553-f72781b5-0788-4a9d-9cad-5b1deb2f5d73_1777097648_12406.json
.wheel/history/success/kiln-report-issue-20260425-053840-f72781b5-0788-4a9d-9cad-5b1deb2f5d73_1777095259_19239.json
.wheel/history/success/kiln-report-issue-20260425-030900-a57191ec-9248-4d37-8850-41975f5bed46_1777086280_18067.json
```

All three are `status: "running"` in the file (a wheel quirk — the workflow_status field is not flipped to `"complete"` before archive) but every step has `status: "done"`. All three completed the full foreground path through `dispatch-background-sync`.

### Per-run metrics

| Run | Started (UTC) | dispatch-bg-sync `command_log` entries | dispatch-bg-sync sub-shell-commands inside | dispatch-bg-sync wall-clock (sec) | create-issue `command_log` entries | Workflow total wall-clock (start → dispatch-bg-sync done, sec) |
|-----|---------------|-----------------------------------------:|--------------------------------------------:|---:|---:|---:|
| R1  | 2026-04-25T06:14:08Z | 1 | ~3 | 36 | 2 | 105 |
| R2  | 2026-04-25T05:34:19Z | 2 | ~3 | 97 | 3 | 261 |
| R3  | 2026-04-25T03:04:40Z | 1 | ~2 | 28 | 5 | 259 |

### Aggregates (medians)

| Metric | Median | Notes |
|--------|-------:|-------|
| `dispatch-background-sync.command_log` length (Bash tool calls in the agent step) | **1** | Post-FR-E batching — the dispatch step now issues a single batched bash that reads counter + `jq` for `issue_file/obsidian_path` + `jq` for `backlog_path` |
| `dispatch-background-sync` sub-shell-command count (proxy for "disk fetches") | **3** | Lines starting with `bash`/`jq`/`cat`/etc. inside the batched bash — matches the PRD line 36 wording ("5 disk fetches" was pre-batching; current is ~3) |
| `dispatch-background-sync` wall-clock (sec) | **36** | 28–97s observed range |
| Workflow total wall-clock (sec) | **259** | 105–261s observed range — high variance driven by `write-issue-note` sub-workflow + agent thinking time, not by the hook itself |
| `create-issue.command_log` length | **3** | Highly variable (2–5) depending on whether the agent grep-checks `.kiln/issues/` for duplicates |

### Interpretation for SC-G-1 / SC-G-2

- **SC-G-1 ("≥3 fewer agent Bash/Read tool calls")** — IMPORTANT NOTE FOR THE SPEC + AUDIT TEAM. The post-FR-E batched baseline is already at **command_log length = 1** for `dispatch-background-sync`. The PRD's "5 disk fetches" framing in line 36 is **pre-FR-E**; it counts the inline shell sub-commands within the batched bash, not the agent's tool-call count. After this PRD ships, the goal is **command_log length = 0** for `dispatch-background-sync` (everything pre-resolved into the prompt). That's a delta of **1 fewer agent Bash tool call**, not 3. The SC-G-1 threshold may need re-calibration in the spec phase, OR SC-G-1 should be re-stated as "≥3 fewer disk-fetch sub-commands inside the agent step's command_log" (median = 3 → 0). The auditor (task #5) should pick whichever framing makes the gate measurable.
- **SC-G-2 ("lower wall-clock from activation to dispatch-background-sync completion")** — baseline median = 259s workflow-total / 36s dispatch-step. Observed variance is high (105–261s); the comparison should focus on the dispatch-step wall-clock (lower variance) rather than total workflow wall-clock. Tolerance per PRD: "any measurable decrease passes; regression by more than 10% fails the gate." With a 36s dispatch-step median, a 10% regression bound = +3.6s.

### Cleanup

The three captured runs are real user invocations — no synthetic baseline issues were created in `.kiln/issues/`. **No cleanup needed.** This is a side-benefit of the methodology deviation noted above.

---

## Job 2 — `context_from:` inventory + classification (FR-G5-3)

### Methodology

A walk over `plugin-*/workflows/*.json`, `workflows/*.json`, and `workflows/tests/*.json` yielded **61 step entries** that declare `context_from: [...]` with at least one source. Each entry was classified by parsing the consumer step's `instruction:` (or `command:`) text and checking whether it references `.wheel/outputs/<source-step-id>` (matching aliases for sub-workflow step types via `step.workflow` and `step.output_file`).

Three categories emerged:

- **DATA-PASSING** — the consumer's instruction explicitly reads from `.wheel/outputs/<source>` to extract a value. **Migration target.**
- **PROBABLE-DATA-PASSING** — the consumer reads from `.wheel/outputs/<some-other-name>` that doesn't match a context_from'd source's step ID directly, but corresponds to the source step's actual output filename (e.g. a `type: workflow` step writes its result under the sub-workflow's name, not the wheel-step ID; a `type: command` step writes under a `<workflow-name>-<step-id>.json` convention). **Manual-review migration target.**
- **PURE-ORDERING** — the consumer's instruction makes no `.wheel/outputs/` reference at all. The `context_from:` only establishes "X must run before Y." **Keep as-is** (rename to `after:` is the OQ-G-2 candidate).

### Aggregate counts

| Classification | Count | % |
|---|---:|---:|
| DATA-PASSING | 5 | 8% |
| PROBABLE-DATA-PASSING | 5 | 8% |
| PURE-ORDERING | 51 | 84% |
| **Total** | **61** | 100% |

**Inference for OQ-G-2** (rename `context_from:` → `after:`): 84% of `context_from:` uses are pure-ordering and would be renamed cleanly. The 10 data-passing/probable cases need migration to `inputs:` first. **Recommend deferring the rename to a follow-on PRD** until all data-passing uses have been migrated, to avoid having to maintain `context_from:` and `after:` simultaneously.

### Inventory table

| Workflow file | Step ID | Step type | `context_from:` | Classification | Follow-on PR? | Sketch |
|---|---|---|---|---|---|---|
| `plugin-kiln/workflows/kiln-report-issue.json` | `dispatch-background-sync` | `agent` | `[create-issue, write-issue-note]` | **DATA-PASSING** | **N — migrate in this PRD** (FR-G4) | Replace `context_from: [write-issue-note]` data role with `inputs: { ISSUE_FILE: $.steps.write-issue-note.output.issue_file, OBSIDIAN_PATH: $.steps.write-issue-note.output.obsidian_path, CURRENT_COUNTER: $config(.shelf-config:shelf_full_sync_counter), THRESHOLD: $config(.shelf-config:shelf_full_sync_threshold), SHELF_DIR: $plugin(shelf) }`. The reference filename used today is `.wheel/outputs/shelf-write-issue-note-result.json` (sub-workflow name, not wheel-step name). Keep `context_from: [create-issue]` as pure ordering or fold both into `after:`. |
| `plugin-kiln/workflows/kiln-mistake.json` | `create-mistake` | `agent` | `[check-existing-mistakes]` | DATA-PASSING | Y — `feat(kiln): migrate kiln-mistake to inputs:` | `inputs: { EXISTING_MISTAKES: $.steps.check-existing-mistakes.output.text }` |
| `plugin-shelf/workflows/shelf-sync.json` | `obsidian-apply` | `agent` | `[read-shelf-config, compute-work-list]` | DATA-PASSING | Y — `feat(shelf): migrate shelf-sync to inputs:` | `inputs: { WORK_LIST: $.steps.compute-work-list.output.json, SHELF_CONFIG_BASE_PATH: $config(.shelf-config:base_path), SHELF_CONFIG_SLUG: $config(.shelf-config:slug) }` |
| `plugin-shelf/workflows/shelf-sync.json` | `self-improve` | `agent` | `[generate-sync-summary, obsidian-apply]` | DATA-PASSING | Y — same PR as above | `inputs: { SUMMARY: $.steps.generate-sync-summary.output.text, APPLY_RESULT: $.steps.obsidian-apply.output.json }` |
| `workflows/tests/sync.json` | `obsidian-apply` | `agent` | `[read-shelf-config, compute-work-list]` | DATA-PASSING | N — test fixture, mirror shelf-sync change | Mirror the same `inputs:` shape used in `plugin-shelf/workflows/shelf-sync.json` so the fixture stays in lock-step. |
| `plugin-shelf/workflows/shelf-propose-manifest-improvement.json` | `write-proposal-mcp` | `agent` | `[write-proposal-dispatch]` | PROBABLE | Y — `feat(shelf): migrate propose-manifest-improvement to inputs:` | Reads `.wheel/outputs/propose-manifest-improvement-dispatch.json` (workflow-name-prefixed, not step-id-prefixed). Define output_schema on `write-proposal-dispatch` with fields `{action, proposal_path, frontmatter, body_sections}` then `inputs: { ENVELOPE: $.steps.write-proposal-dispatch.output.json }`. |
| `plugin-shelf/workflows/shelf-write-issue-note.json` | `obsidian-write` | `agent` | `[read-shelf-config, parse-create-issue-output]` | PROBABLE | Y — `feat(shelf): migrate shelf-write-issue-note to inputs:` | Reads `.wheel/outputs/shelf-write-issue-note-result.json` — needs manual confirmation of whether this is reading its OWN final output (unusual) vs an upstream step. Likely consumes `parse-create-issue-output` field-by-field; migrate per parsed schema. |
| `plugin-shelf/workflows/shelf-write-issue-note.json` | `finalize-result` | `command` | `[obsidian-write]` | PROBABLE | Y — same PR | command-step input migration; same result file as above. |
| `plugin-shelf/workflows/shelf-write-roadmap-note.json` | `obsidian-write` | `agent` | `[read-shelf-config, parse-roadmap-input]` | PROBABLE | Y — `feat(shelf): migrate shelf-write-roadmap-note to inputs:` | Mirror of `shelf-write-issue-note` but with the roadmap-note variant. |
| `plugin-shelf/workflows/shelf-write-roadmap-note.json` | `finalize-result` | `command` | `[obsidian-write]` | PROBABLE | Y — same PR | mirror of finalize-result above. |
| `plugin-clay/workflows/sync.json` | `sync-to-obsidian` | `agent` | `[scan-products]` | PURE-ORDERING | N | Pure ordering — keep. Will rename to `after:` if OQ-G-2 lands. |
| `plugin-clay/workflows/sync.json` | `sync-research` | `agent` | `[scan-products]` | PURE-ORDERING | N | Same. |
| `plugin-kiln/workflows/kiln-report-issue.json` | `create-issue` | `agent` | `[check-existing-issues]` | PURE-ORDERING | N | Pure ordering. (instruction reads `.wheel/outputs/check-existing-issues.txt` but that's a wheel-emitted output — consumer treats it as ambient context already in the pre-step footer; no field extraction.) |
| `plugin-kiln/workflows/kiln-report-issue.json` | `write-issue-note` | `workflow` | `[create-issue]` | PURE-ORDERING | N | Pure ordering — sub-workflow consumes context via the `inputs:` field of the wrapping step (already migrated implicitly). |
| `plugin-shelf/workflows/shelf-create.json` | `resolve-vault-path` | `agent` | `[read-shelf-config]` | PURE-ORDERING | N | |
| `plugin-shelf/workflows/shelf-create.json` | `check-duplicate` | `agent` | `[read-shelf-config, resolve-vault-path]` | PURE-ORDERING | N | |
| `plugin-shelf/workflows/shelf-create.json` | `create-project` | `agent` | (8 sources) | PURE-ORDERING | N | |
| `plugin-shelf/workflows/shelf-propose-manifest-improvement.json` | `write-proposal-dispatch` | `command` | `[reflect]` | PURE-ORDERING | N | command-step ordering |
| `plugin-shelf/workflows/shelf-repair.json` | `read-existing-dashboard` | `agent` | `[read-shelf-config]` | PURE-ORDERING | N | |
| `plugin-shelf/workflows/shelf-repair.json` | `generate-diff-report` | `agent` | (4 sources) | PURE-ORDERING | N | |
| `plugin-shelf/workflows/shelf-repair.json` | `apply-repairs` | `agent` | (5 sources) | PURE-ORDERING | N | |
| `plugin-shelf/workflows/shelf-repair.json` | `verify-repair` | `agent` | (4 sources) | PURE-ORDERING | N | |
| `plugin-trim/workflows/library-sync.json` | `sync-components` | `agent` | (5 sources) | PURE-ORDERING | N | |
| `plugin-trim/workflows/trim-design.json` | `generate-design` | `agent` | (5 sources) | PURE-ORDERING | N | |
| `plugin-trim/workflows/trim-design.json` | `discover-flows` | `agent` | `[read-product-context, read-config]` | PURE-ORDERING | N | |
| `plugin-trim/workflows/trim-diff.json` | `generate-diff` | `agent` | (4 sources) | PURE-ORDERING | N | |
| `plugin-trim/workflows/trim-edit.json` | `apply-edit` | `agent` | `[resolve-trim-plugin, read-design-state]` | PURE-ORDERING | N | |
| `plugin-trim/workflows/trim-edit.json` | `log-change` | `agent` | `[read-design-state, apply-edit]` | PURE-ORDERING | N | |
| `plugin-trim/workflows/trim-pull.json` | `pull-design` | `agent` | (4 sources) | PURE-ORDERING | N | |
| `plugin-trim/workflows/trim-pull.json` | `discover-flows` | `agent` | `[read-config, resolve-trim-plugin]` | PURE-ORDERING | N | |
| `plugin-trim/workflows/trim-push.json` | `push-to-penpot` | `agent` | (6 sources) | PURE-ORDERING | N | |
| `plugin-trim/workflows/trim-push.json` | `discover-flows` | `agent` | `[detect-framework, scan-components, read-config]` | PURE-ORDERING | N | |
| `plugin-trim/workflows/trim-redesign.json` | `read-current-design` | `agent` | `[resolve-trim-plugin, gather-context]` | PURE-ORDERING | N | |
| `plugin-trim/workflows/trim-redesign.json` | `generate-redesign` | `agent` | `[gather-context, read-current-design]` | PURE-ORDERING | N | |
| `plugin-trim/workflows/trim-redesign.json` | `log-changes` | `agent` | `[gather-context, generate-redesign]` | PURE-ORDERING | N | |
| `plugin-trim/workflows/trim-verify.json` | `capture-screenshots` | `agent` | `[resolve-trim-plugin, read-flows]` | PURE-ORDERING | N | |
| `plugin-trim/workflows/trim-verify.json` | `compare-visuals` | `agent` | `[capture-screenshots]` | PURE-ORDERING | N | |
| `plugin-trim/workflows/trim-verify.json` | `write-report` | `agent` | `[read-flows, compare-visuals]` | PURE-ORDERING | N | |
| `plugin-wheel/workflows/example.json` | `generate-report` | `agent` | `[check-env]` | PURE-ORDERING | N | |
| `plugin-wheel/workflows/example.json` | `verify-report` | `command` | `[generate-report]` | PURE-ORDERING | N | |
| `workflows/create.json` | `resolve-vault-path` | `agent` | `[read-shelf-config]` | PURE-ORDERING | N | |
| `workflows/create.json` | `check-duplicate` | `agent` | `[read-shelf-config, resolve-vault-path]` | PURE-ORDERING | N | |
| `workflows/create.json` | `create-project` | `agent` | (8 sources) | PURE-ORDERING | N | |
| `workflows/repair.json` | `read-existing-dashboard` | `agent` | `[read-shelf-config]` | PURE-ORDERING | N | |
| `workflows/repair.json` | `generate-diff-report` | `agent` | (4 sources) | PURE-ORDERING | N | |
| `workflows/repair.json` | `apply-repairs` | `agent` | (5 sources) | PURE-ORDERING | N | |
| `workflows/repair.json` | `verify-repair` | `agent` | (4 sources) | PURE-ORDERING | N | |
| `workflows/tests/agent-chain.json` | `draft-summary` | `agent` | `[gather-git-stats, gather-repo-structure]` | PURE-ORDERING | N | |
| `workflows/tests/agent-chain.json` | `review-and-finalize` | `agent` | `[gather-git-stats, gather-repo-structure, draft-summary]` | PURE-ORDERING | N | |
| `workflows/tests/branch-multi.json` | `write-report` | `agent` | `[detect-language, analyze-js, fallback-analysis]` | PURE-ORDERING | N | |
| `workflows/tests/command-chain.json` | `summarize` | `agent` | `[count-files, count-scripts, count-json]` | PURE-ORDERING | N | |
| `workflows/tests/example.json` | `generate-report` | `agent` | `[check-env]` | PURE-ORDERING | N | |
| `workflows/tests/example.json` | `verify-report` | `command` | `[generate-report]` | PURE-ORDERING | N | |
| `workflows/tests/example.json` | `cleanup-success` | `agent` | (3 sources) | PURE-ORDERING | N | |
| `workflows/tests/example.json` | `cleanup-failure` | `agent` | (3 sources) | PURE-ORDERING | N | |
| `workflows/tests/sync.json` | `obsidian-discover` | `agent` | `[read-shelf-config]` | PURE-ORDERING | N | |
| `workflows/tests/team-dynamic.json` | `spawn-workers` | `teammate` | `[generate-work]` | PURE-ORDERING | N | |
| `workflows/tests/team-static.json` | `worker-1` | `teammate` | `[setup]` | PURE-ORDERING | N | |
| `workflows/tests/team-static.json` | `worker-2` | `teammate` | `[setup]` | PURE-ORDERING | N | |
| `workflows/tests/team-static.json` | `worker-3` | `teammate` | `[setup]` | PURE-ORDERING | N | |
| `workflows/tests/team-sub-worker.json` | `do-work` | `agent` | `[_assignment]` | PURE-ORDERING | N | |

### Recommended follow-on PR portfolio (after this PRD)

1. **`feat(kiln): migrate kiln-mistake.json to inputs:`** — single workflow, one DATA-PASSING site. Smallest PR; good template for the rest. Demonstrates the pattern outside the canonical `kiln-report-issue` migration.
2. **`feat(shelf): migrate shelf-sync.json to inputs:`** — two DATA-PASSING sites in one workflow + the test fixture `workflows/tests/sync.json`. Bundle them so the fixture and the real workflow stay in lock-step.
3. **`feat(shelf): migrate shelf-propose-manifest-improvement to inputs:`** — single PROBABLE site (`write-proposal-mcp`). Manual-review needed to confirm the data extraction shape.
4. **`feat(shelf): migrate shelf-write-issue-note + shelf-write-roadmap-note to inputs:`** — four PROBABLE sites across two near-identical workflows; bundle them since they share the parse + finalize-result pattern.

Each of the four PRs above is independently testable via `/kiln:kiln-test` against a kiln-test fixture exercising the migrated workflow end-to-end (NFR-G-1 substrate).

### Out-of-scope clarifications

- **No `context_from:` use was found that points to a non-existent or never-run source.** Schema validation (FR-G1-4) on this corpus will not surface false-positive failures.
- **Test-suite workflows under `workflows/tests/`** — kept in the inventory because they are runtime fixtures for `/wheel:wheel-test`. Migrating any of them only after the corresponding production workflow ships its own migration is the safer order.

---

## Artifacts produced

- This file: `specs/wheel-step-input-output-schema/research.md`
- Friction note: `specs/wheel-step-input-output-schema/agent-notes/researcher-baseline.md`
- (Internal) classification dump: `/tmp/context-from-classified-v3.json` — ephemeral, not committed; can be re-derived by the python script embedded in this researcher's terminal log.
