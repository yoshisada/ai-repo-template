# Implementation Plan: Wheel Test Runner Extraction

**Branch**: `build/wheel-test-runner-extraction-20260425`
**Spec**: `specs/wheel-test-runner-extraction/spec.md`
**Approach**: Pure relocation (`git mv` semantics) of 12 bash scripts + one-line edit to one SKILL.md + one new fixture. Bash 5.x + `jq` + POSIX utilities. No new runtime dependencies.

## Summary

Three changes shipped atomically in one squash-merge PR:

1. **Relocate** 12 bash scripts from `plugin-kiln/scripts/harness/` → `plugin-wheel/scripts/harness/`. Rename top-level entrypoint `kiln-test.sh` → `wheel-test-runner.sh`. All other filenames preserved (sibling internal helpers — no consumer references their filenames externally).
2. **Update** the single live `bash <path>` line in `plugin-kiln/skills/kiln-test/SKILL.md` to point at `${WORKFLOW_PLUGIN_DIR}/../plugin-wheel/scripts/harness/wheel-test-runner.sh`. Update the preamble's "non-negotiable" sentence to reference the new path.
3. **Add** one new fixture `plugin-wheel/tests/wheel-test-runner-direct/` (run.sh-only pattern) that invokes `wheel-test-runner.sh` directly. Author one snapshot-diff helper at `plugin-wheel/scripts/harness/snapshot-diff.sh` per `contracts/interfaces.md §3`.

## Phases

### Phase 1 — Preflight: grep audit + baseline preparation

Verifies R-R-1 mitigation (hidden coupling) before any move happens. Surfaces any `plugin-kiln/` literal that would break the runner's self-containment.

**Files audited (no edits)**:

- `plugin-kiln/scripts/harness/kiln-test.sh`
- `plugin-kiln/scripts/harness/watcher-runner.sh`
- `plugin-kiln/scripts/harness/dispatch-substrate.sh`
- `plugin-kiln/scripts/harness/substrate-plugin-skill.sh`
- `plugin-kiln/scripts/harness/tap-emit.sh`
- `plugin-kiln/scripts/harness/test-yaml-validate.sh`
- `plugin-kiln/scripts/harness/scratch-create.sh`
- `plugin-kiln/scripts/harness/scratch-snapshot.sh`
- `plugin-kiln/scripts/harness/fixture-seeder.sh`
- `plugin-kiln/scripts/harness/claude-invoke.sh`
- `plugin-kiln/scripts/harness/config-load.sh`
- `plugin-kiln/scripts/harness/watcher-poll.sh`

**Audit script**:

```bash
# Run from repo root. Each line must be either empty or a documented exception.
git grep -nF 'plugin-kiln/' plugin-kiln/scripts/harness/ \
  | grep -vE '(SUBJECT_TO_REWRITE_EXCEPTIONS_BELOW)'
```

Expected exceptions (kiln-specific path literals that will need migration):
- Any `plugin-kiln/tests` references that should become `plugin-<name>/tests` via the existing `<name>` placeholder substitution in `config-load.sh`.

If any other `plugin-kiln/` literal surfaces in the audit, the implementer MUST migrate it to either (a) wheel-relative via `${BASH_SOURCE[0]}`, (b) caller-passed argument, or (c) plugin-name parameterized substitution. None expected per spec assumptions; this audit is the tripwire.

### Phase 2 — Move runner core (FR-R1)

Atomic relocation. Use `git mv` to preserve history. Rename `kiln-test.sh` to `wheel-test-runner.sh` during the move per FR-R1-1.

**Operations** (all in one commit, executed in this order):

```bash
mkdir -p plugin-wheel/scripts/harness
git mv plugin-kiln/scripts/harness/kiln-test.sh plugin-wheel/scripts/harness/wheel-test-runner.sh
git mv plugin-kiln/scripts/harness/watcher-runner.sh plugin-wheel/scripts/harness/
git mv plugin-kiln/scripts/harness/dispatch-substrate.sh plugin-wheel/scripts/harness/
git mv plugin-kiln/scripts/harness/substrate-plugin-skill.sh plugin-wheel/scripts/harness/
git mv plugin-kiln/scripts/harness/tap-emit.sh plugin-wheel/scripts/harness/
git mv plugin-kiln/scripts/harness/test-yaml-validate.sh plugin-wheel/scripts/harness/
git mv plugin-kiln/scripts/harness/scratch-create.sh plugin-wheel/scripts/harness/
git mv plugin-kiln/scripts/harness/scratch-snapshot.sh plugin-wheel/scripts/harness/
git mv plugin-kiln/scripts/harness/fixture-seeder.sh plugin-wheel/scripts/harness/
git mv plugin-kiln/scripts/harness/claude-invoke.sh plugin-wheel/scripts/harness/
git mv plugin-kiln/scripts/harness/config-load.sh plugin-wheel/scripts/harness/
git mv plugin-kiln/scripts/harness/watcher-poll.sh plugin-wheel/scripts/harness/
# Verify nothing else remains under the old harness dir:
test -z "$(ls plugin-kiln/scripts/harness/ 2>/dev/null)"
rmdir plugin-kiln/scripts/harness/ 2>/dev/null || true
```

**Files touched**:
- `plugin-wheel/scripts/harness/wheel-test-runner.sh` — renamed from `kiln-test.sh`. Internal `${BASH_SOURCE[0]}` resolution requires no edits (the harness_dir derivation at line 30 of the original file is portable and works post-move).
- `plugin-wheel/scripts/harness/<11 other helpers>` — moved verbatim.

**Internal cross-reference verification**: After the `git mv`, run a smoke check by invoking `bash plugin-wheel/scripts/harness/wheel-test-runner.sh plugin-kiln kiln-distill-basic` (any small fixture). If sibling-helper resolution via `harness_dir` fails, fix the broken reference (none expected — `${BASH_SOURCE[0]}` is portable to bash 3.2+).

### Phase 3 — Façade update (FR-R2)

One-line edit + one preamble-sentence edit to `plugin-kiln/skills/kiln-test/SKILL.md`. Skill prose unchanged otherwise.

**Files touched**:

- `plugin-kiln/skills/kiln-test/SKILL.md`:
  - Line 31 (current): `bash "${WORKFLOW_PLUGIN_DIR}/scripts/harness/kiln-test.sh" $ARGUMENTS`
  - Line 31 (after): `bash "${WORKFLOW_PLUGIN_DIR}/../plugin-wheel/scripts/harness/wheel-test-runner.sh" $ARGUMENTS`
  - Line 10 (current): `**Non-negotiable**: this skill MUST delegate to ${WORKFLOW_PLUGIN_DIR}/scripts/harness/kiln-test.sh ...`
  - Line 10 (after): `**Non-negotiable**: this skill MUST delegate to ${WORKFLOW_PLUGIN_DIR}/../plugin-wheel/scripts/harness/wheel-test-runner.sh ...`

**No other prose edits.** Test fixture conventions, test.yaml schema, env vars, `.kiln/test.config` overrides, exit-code documentation, and the "Writing a new test" section all stay verbatim.

### Phase 4 — Cross-repo grep gate + collateral updates (FR-R2-3)

Catch any other live reference to the old path. Update each.

**Audit script**:

```bash
git grep -nF 'plugin-kiln/scripts/harness/kiln-test' \
  ':(exclude).wheel/history/**' \
  ':(exclude)specs/**/blockers.md' \
  ':(exclude)specs/**/retro.md' \
  ':(exclude)docs/features/**/PRD.md' \
  ':(exclude)CLAUDE.md'
```

Each remaining match MUST be updated to `plugin-wheel/scripts/harness/wheel-test-runner.sh` (or the resolution-disciplined variant if inside a SKILL.md / hook / workflow).

Known/expected matches at PRD time (pre-edit; auditor verifies all are gone post-edit):
- `plugin-kiln/skills/kiln-test/SKILL.md` (handled in Phase 3)
- Any other kiln SKILL.md / agent / hook / workflow that mentions the old path (TBD by audit; likely zero-or-few).

### Phase 5 — Non-kiln consumability fixture (FR-R3)

Author the wheel-side fixture proving the runner works without `plugin-kiln/` in the call chain.

**Files touched**:

- `plugin-wheel/tests/wheel-test-runner-direct/run.sh` — NEW. Tier-2 fixture (run.sh-only pattern). Invokes `wheel-test-runner.sh` directly with a minimal synthetic fixture; asserts on exit code, verdict-report path, and TAP stdout shape. MUST NOT reference `plugin-kiln/` anywhere (FR-R3-2 / SC-R-3 grep gate).
- `plugin-wheel/tests/wheel-test-runner-direct/fixture/` — synthetic minimal scratch fixture used by run.sh. May be a tiny bats-style or a noop assertions.sh that asserts a known invariant (e.g., scratch dir exists, stdin is processed). Authored to validate runner argument-parsing + plugin-resolution + scratch-dir creation + exit-code aggregation paths WITHOUT requiring an LLM call. (Per Phase 4 carve-out, the runner's substrate-dispatch path may be exercised via a no-LLM shortcut — implementer judgment.)

If a no-LLM synthetic fixture is impractical, fallback acceptable: invoke the runner against an existing tiny fixture (e.g., a deterministic plugin-skill fixture) and assert on the verdict-report shape only.

### Phase 6 — Snapshot-diff comparator (NFR-R-8)

Author one comparator helper that the auditor uses to verify NFR-R-3 byte-identity.

**Files touched**:

- `plugin-wheel/scripts/harness/snapshot-diff.sh` — NEW. Implements the per-fixture exclusion contract per `contracts/interfaces.md §3`. Three modes: `bats` (preprocess-substitution.bats), `verdict-report` (kiln-distill-basic — section-level body exclusion for `## Last 50 transcript envelopes`), and `verdict-report-deterministic` (fast plugin-skill fixture — modulo timestamps/UUIDs/abs paths only).

### Phase 7 — Test fixtures + tripwires (the discipline gate per NFR-R-2)

Beyond Phase 5's `wheel-test-runner-direct/` fixture, this PRD also requires SC-R-1 snapshot-diff verification on three named fixtures.

**Verification fixtures** (no new dirs — these exercise existing fixtures via the snapshot-diff comparator):

- The auditor (or implementer pre-audit) runs each of the three named fixtures pre and post (post = on this branch), captures the verdict reports, and runs `plugin-wheel/scripts/harness/snapshot-diff.sh` per the appropriate mode. Pre-PRD baselines are at `specs/wheel-test-runner-extraction/research/baseline-snapshot/`.

**Mutation tripwires** (NFR-R-2 — every silent-failure mode has at least one):

- `plugin-wheel/tests/wheel-test-runner-direct/` includes a mutation-tripwire variant: implementer authors `run.sh` such that a deliberate edit to `wheel-test-runner.sh` (e.g., adding a stray space character to the TAP header) makes the snapshot-diff fail. Documented in the fixture's run.sh comments.

### Phase 8 — Live-smoke gate (NFR-R-5, SC-R-2)

Per the §Auditor Prompt — Live-Substrate-First Rule, the auditor (or implementer pre-audit) runs the canonical live-smoke substrate.

**Invocation**:

```bash
bash plugin-kiln/tests/perf-kiln-report-issue/run.sh
# Captures /tmp/perf-results.tsv and /tmp/perf-medians.json
```

**Acceptance**: post-PRD `after_arm_medians` within tolerance bands per spec.md §Success Criteria SC-R-2:

- `wall_clock_sec`: ±20% vs baseline 7.751s (range 6.20s–9.30s)
- `duration_api_ms`: ±20% vs baseline 4364ms (range 3491ms–5237ms)
- `num_turns`: exactly 2
- `output_tokens`: ±10% vs baseline 180 (range 162–198) — advisory

Implementer cites `/tmp/perf-medians.json` path + the post-run TSV path in `agent-notes/implementer.md` AND in the PR description verification checklist.

### Phase 9 — Documentation (in same PR per NFR-R-4)

- `plugin-wheel/README.md` — add a "Test Runner" section (or a top-level link to the new doc) showing how a non-kiln plugin invokes the runner.
- `plugin-wheel/docs/test-runner.md` — NEW. Worked example: invoking `wheel-test-runner.sh` from a hypothetical `plugin-foo` consumer, with sample test.yaml + assertions.sh + verdict-report excerpt. Per SC-R-6.
- `CLAUDE.md` "Recent Changes" block — updated by `/kiln:kiln-build-prd` retrospective phase (NOT implementer-authored).

## Test Strategy

Per NFR-R-1: the wheel-side fixture proves consumability via direct `bash run.sh` invocation. Per NFR-R-2: every documented failure mode has a mutation tripwire. Per NFR-R-5: live-smoke gate cited in PR description.

**Coverage matrix (FR / NFR → fixture / verification)**:

| FR / NFR | Verification |
|---|---|
| FR-R1-1, FR-R1-2 (move) | `git log --diff-filter=R` shows the renames; `ls plugin-wheel/scripts/harness/` shows all 12 files |
| FR-R1-3 (CLI args + exit codes) | `wheel-test-runner-direct/run.sh` invokes all three forms (auto-detect, `<plugin>`, `<plugin> <test>`) |
| FR-R1-4 (verdict-report path) | snapshot-diff against `kiln-distill-basic-pre-prd.md` shows path prefix preserved |
| FR-R1-5 (TAP v14) | snapshot-diff against `preprocess-substitution.bats-pre-prd.md` shows byte-identity |
| FR-R1-6 (`KILN_TEST_REPO_ROOT`) | `wheel-test-runner-direct/run.sh` exports the env var and asserts plugin-discovery honors it |
| FR-R2-1, FR-R2-2 (façade) | `git diff plugin-kiln/skills/kiln-test/SKILL.md` shows ≤2 line edits + only the bash-invocation + preamble lines change |
| FR-R2-3 (grep gate) | SC-R-3 grep run by auditor — empty result |
| FR-R3-1, FR-R3-2 (non-kiln) | `wheel-test-runner-direct/` fixture passes; `git grep plugin-kiln/ plugin-wheel/tests/wheel-test-runner-direct/` is empty |
| FR-R4-1 (byte-identity 3 fixtures) | snapshot-diff pre/post via `snapshot-diff.sh` for each of the 3 named fixtures |
| FR-R4-2 (TAP byte-identity) | covered by snapshot-diff bats mode on `preprocess-substitution.bats` |
| FR-R4-3 (exit codes) | spot-check on at least one passing + one failing fixture pre/post |
| FR-R4-4 (all fixtures pass) | run a representative sweep — at minimum the 3 named fixtures + `wheel-test-runner-direct/` |
| NFR-R-1 (substrate-hierarchy citation) | implementer cites `wheel-test-runner-direct/run.sh` exit code + PASS summary in friction note |
| NFR-R-2 (silent-failure tripwires) | mutation case in `wheel-test-runner-direct/` |
| NFR-R-3 (strict back-compat) | SC-R-1 satisfied via snapshot-diff |
| NFR-R-4 (atomic shipment) | git log shows Phase 2 + Phase 3 in same squash-merge commit |
| NFR-R-5 (live-smoke) | SC-R-2 satisfied via `perf-kiln-report-issue/run.sh` invocation |
| NFR-R-6 (perf budget ≤50ms) | `time` measurement on a fast-deterministic fixture pre vs post |
| NFR-R-7 (no rename in user-facing paths) | grep `KILN_TEST_REPO_ROOT` / `.kiln/logs/kiln-test-` / `/tmp/kiln-test-` / `/kiln:kiln-test` — all preserved |
| NFR-R-8 (snapshot-diff comparator pinned) | `plugin-wheel/scripts/harness/snapshot-diff.sh` exists per `contracts/interfaces.md §3` |

## Risks & Mitigations

- **R-R-1 (hidden coupling)** — mitigated by Phase 1 audit before any `git mv`.
- **R-R-2 (skill resolution)** — RESOLVED in spec phase via OQ-R-1 → option (a). Validated by `workflow-plugin-dir-bg` smoke pattern.
- **R-R-3 (snapshot-diff false positives)** — mitigated by `contracts/interfaces.md §3` per-fixture exclusion contract + Phase 6 comparator helper.
- **R-R-4 (substrate-gap recurrence)** — out of scope. This PRD ships on its own; data feeds back into items #2-#4.
- **R-NEW-1 (consumer-install layout for sibling plugins not validated for this specific path)** — mitigation: spot-check post-PR by running `/kiln:kiln-test plugin-kiln <fixture>` against a consumer-install layout (e.g., a `mktemp -d` repo with `npm install @yoshisada/kiln`). If layout drift breaks resolution, fall back to OQ-R-1 option (b) — wheel-side resolver helper. Documented in `blockers.md` if it surfaces.

## Rollback

Pure relocation. Rollback is `git revert <commit-sha>` of the squash-merge PR. No state-file fields, no schema migrations, no consumer-side migration required (they auto-track the SKILL.md update via plugin install).

## Atomic shipment checklist (NFR-R-4)

The single squash-merge PR MUST include:

- [ ] All 12 `git mv` operations + filename rename for entrypoint
- [ ] `plugin-kiln/skills/kiln-test/SKILL.md` two-line edit
- [ ] All FR-R2-3 grep-gate cleanup edits (any other live references discovered)
- [ ] `plugin-wheel/tests/wheel-test-runner-direct/run.sh` + fixture dir
- [ ] `plugin-wheel/scripts/harness/snapshot-diff.sh`
- [ ] `plugin-wheel/docs/test-runner.md` + `plugin-wheel/README.md` link
- [ ] `agent-notes/implementer.md` friction note with cited verdict-report paths + live-smoke medians-JSON path

If ANY item is missing, the PR is a half-state and the auditor blocks merge per NFR-R-4.
