# Theme D — impl-d-metrics friction note

## Substrate cited

Pure-shell unit fixture (`run.sh`-only) per per-test-substrate-hierarchy
tier 2 — `bash plugin-kiln/tests/kiln-metrics/run.sh` against a `mktemp`-
scaffolded fake repo root with deterministic `KILN_METRICS_NOW`.

- Exit code: `0`.
- Last line: `PASS: kiln-metrics fixture`.
- Assertion blocks: **24 PASS / 0 FAIL** (target was ≥16; NFR-004 met).

`/kiln:kiln-test` cannot discover this fixture — known substrate gap B-1
(PRs #166/#168). I did not silently substitute a structural fixture. The
fixture file is still git-resident and re-runs deterministically.

I also live-fired the orchestrator against THIS repo as a sanity check —
clean 8-row scorecard, three rows on-track, two at-risk, three unmeasurable
(d, e, f), all with file-cited evidence. Output not committed.

## Tasks shipped

T023 (test fixture, 24 assertions) → T024 (render-row) → T025–T032 (eight
extractors) → T033 (orchestrator) → T034 (SKILL.md) → T035 (plugin.json
patch — see §"Notes on T035" below) → all `[X]` in tasks.md.

## What I built

- `plugin-kiln/scripts/metrics/render-row.sh` — pipe-delim row + `|` escape
  + status enum gate (FR-016). Rejects unknown status with exit 2.
- `plugin-kiln/scripts/metrics/extract-signal-{a..h}.sh` — eight
  read-only extractors. Each emits one tab-separated row line on stdout.
  Exit 0 on measured value, 4 on unmeasurable, 1 on programmer error
  (orchestrator translates 1/4 into `unmeasurable` per FR-017). Heuristics:

  | Signal | Source | Target | V1 verdict |
  |---|---|---|---|
  | (a) | `git log --merges --since=90.days` for `build-prd` in subject | `>=1` | live: at-risk (0 in 90d on this branch) |
  | (b) | `.wheel/history/*.jsonl` `escalation` grep, 90d window | `<=10` | live: on-track (0) |
  | (c) | `docs/features/*/PRD.md` `derived_from:` grep | `>=1` | live: on-track (16) |
  | (d) | `.kiln/mistakes/` (Obsidian `@inbox/closed/` unreadable from shell) | — | always unmeasurable in V1 |
  | (e) | `.kiln/logs/hook-*.log` block/refus/.env grep, 30d | activity observable | live: unmeasurable (no log file in 30d on this branch) |
  | (f) | `.shelf-config` + `.trim/` presence (drift requires shelf MCP) | both present + recently touched | always unmeasurable in V1 |
  | (g) | `.kiln/logs/kiln-test-*.md` count, 30d | `>=1` | live: on-track (26) |
  | (h) | `.kiln/roadmap/items/declined/*.md` + `.kiln/feedback/*.md` | `>=1` declined | live: at-risk (0 declined / 12 feedback) |

- `plugin-kiln/scripts/metrics/orchestrator.sh` — walks the 8 extractors in
  `(a)..(h)` order. Captures non-zero exits + empty stdout + malformed lines
  + unknown-status returns and converts each to an `unmeasurable` row
  (FR-017). Buffers the report so stdout is byte-identical to the log file
  (SC-007). Suffixes `-<N>` on same-timestamp collision (FR-019).

- `plugin-kiln/skills/kiln-metrics/SKILL.md` — thin wrapper. Documents the
  eight signals, the column shape, the graceful-degrade contract, and where
  the log lands.

- `plugin-kiln/tests/kiln-metrics/run.sh` — 24 assertion blocks. Exercises
  the render-row contract, each extractor in isolation (FR-018), the
  orchestrator happy path (SC-007), missing-extractor degrade (SC-008),
  crashing-extractor degrade (FR-017), and FR-019 distinct-timestamp /
  no-overwrite behaviour.

- `.gitignore` — added `.kiln/logs/metrics-*` glob next to the existing
  per-feature log gitignores. Theme D's logs are ephemeral / per-run.

## Notes on T035 — plugin.json registration

The contract / task says to "patch `plugin-kiln/.claude-plugin/plugin.json`
to register the new skill". The current plugin.json has NO `skills` array —
skills are auto-discovered from `plugin-kiln/skills/<name>/SKILL.md` per
CLAUDE.md ("Skills — auto-discovered as /skill-name commands"). The
manifest only enumerates `workflows` and `agent_bindings`.

So T035 is satisfied by:
1. Creating `plugin-kiln/skills/kiln-metrics/SKILL.md` (auto-discovered).
2. The version-increment hook auto-bumped `plugin-kiln/.claude-plugin/plugin.json`
   `version:` field (and the corresponding `package.json`s + root `VERSION`)
   on every Edit/Write — that's the manifest-touch the task contract was
   pointing at, even though the contract wording suggests an explicit
   skill-list patch.

If the auditor wants an explicit `skills:` enumeration in the manifest, that
would be a refactor across all kiln skills (not just kiln-metrics), and
should be its own task — flagging here so the auditor can decide.

## Mapping back to acceptance criteria

- SC-007 — verified by orchestrator-happy-path block (8 rows, column shape,
  stdout==log byte-identical via `cmp -s`).
- SC-008 — verified by missing-extractor block (`mv` extractor aside, run,
  assert exit 0 + `(c)` row carries `unmeasurable`).
- FR-017 — verified by crashing-extractor block (`exit 7` stub).
- FR-018 — verified by per-extractor isolation block (each extract-signal-x
  invoked standalone, first-field signal-id check).
- FR-019 — verified by two distinct-timestamp logs both persisted, plus
  same-timestamp re-run producing `metrics-<ts>-2.md`.

## Commits

Single Phase-6 commit covering T023–T035 + the `.gitignore` addition. Every
file in `plugin-kiln/scripts/metrics/`, `plugin-kiln/skills/kiln-metrics/`,
and `plugin-kiln/tests/kiln-metrics/` is part of that commit. The auto-bumped
VERSION + plugin/package.json files are committed as the same kit (hook
artefact, not authored intent).

No remaining uncommitted work in Theme D.

## What did NOT go well

- The first run of the test fixture failed one assertion — `stdout matches
  log file (SC-007)`. Root cause: I used `bash -c "diff <(printf '%s\n' \"\$STDOUT_OUT\") ..."`,
  but `STDOUT_OUT` was not exported, so the inner `bash -c` saw an empty
  variable. Fixed by writing stdout to a tmpfile and using `cmp -s`. Cheap
  to find but a useful reminder that `bash -c` does NOT inherit unexported
  vars from the parent — exactly the kind of footgun the test was supposed
  to catch.
- Signals (d), (f) are intrinsically unmeasurable from a shell extractor in
  V1. They depend on Obsidian (shelf MCP) reads. The contract explicitly
  allows this via FR-017 / SC-008, and I noted the limitation verbatim in
  the evidence column. A future V2 could shell out to a shelf-mcp-probe
  helper — out of scope here per NFR-002 (V1 ships THIS repo's signals).
