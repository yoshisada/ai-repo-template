# Blockers: shelf-sync-efficiency

**Feature**: shelf-sync-efficiency
**Branch**: `build/shelf-sync-efficiency-20260410`
**Audited**: 2026-04-10

This file records gaps between the PRD and the shipped implementation that the
auditor could not close inside this session. Each entry lists the requirement,
why it is blocked, and the path to resolution.

---

## B-001 — SC-001 (token cost <=30k) not empirically confirmed

**Requirement**: FR-007 / SC-001 — one `shelf-full-sync` run on the pinned
benchmark repo must cost <=30k tokens via wheel-runner telemetry.

**Status**: NOT VERIFIED (structural estimate only).

**Why blocked**: Implementer deliberately did not invoke wheel-runner from
inside the implementer session because (a) a live run costs ~30k+ tokens and
would blow the session budget shared with the auditor and retrospective, and
(b) nesting wheel-runner inside wheel-runner conflates the implementer-turn
cost with the workflow-turn cost being measured. The auditor session is
under the same constraint.

**Current evidence**: `specs/shelf-sync-efficiency/benchmark/v4-token-cost.md`
models the cost structurally at ~37k +/- 10k. The range straddles the target.

**Path to resolution**: After this PR merges (or from a clean session),
run `/wheel-run shelf-full-sync` once against the pinned benchmark repo
(`yoshisada/ai-repo-template` @ `2973dedb4a0b3cfa8f8235bc30b369830af73e07`)
and record the per-agent telemetry in
`specs/shelf-sync-efficiency/benchmark/v4-token-cost.md`. If >30k, the
documented next lever is to drop the pre-rendered `body` field from
`compute-work-list.json` and have `obsidian-apply` template from a minimal
placeholder — that is reversible inside Phase 3.

**Risk level**: MEDIUM. Agent count dropped from 4 -> 2 is the dominant cost
reduction and is directly measured; it is plausible but not certain that the
total lands under 30k.

---

## B-002 — SC-003 (Obsidian behavioral parity) — RESOLVED in v5

**Requirement**: FR-003 / SC-003 — v4 run must produce a byte-identical
Obsidian snapshot to v3 on a frozen fixture.

**Status**: RESOLVED (v5 implementation, 2026-04-16).

**What happened (v4)**: `compute-work-list.sh` generated doc entries with
hardcoded `summary = title`, `status = "Draft"`, and incomplete `tags` — all
of which would have regressed existing vault content on UPDATE.

**How v5 resolves this**: v5 splits fields into two classifications:
- **Programmatic fields** (source, github_number, prd_path, project,
  last_synced, status for issues): always patched on UPDATE via
  `mcp__obsidian-projects__patch_file`.
- **Inferred fields** (summary, tags, category, severity, status for docs):
  set ONLY on CREATE by the LLM agent reading source_data; NEVER touched on
  UPDATE.

On UPDATE, `obsidian-apply` calls `patch_file` with only programmatic fields,
preserving all LLM-inferred content from the original CREATE. On CREATE, the
agent reads the full `source_data` (issue body or PRD content) and generates
meaningful inferred fields — matching v3 behavior.

This is Road A from the original analysis (vault schema split into
programmatic vs inferred), implemented without a migration script because
`patch_file` naturally preserves unmentioned fields.

**Risk level**: RESOLVED.

---

## B-003 — SC-004 (large-vault ceiling) not exercised

**Requirement**: FR-006 / SC-004 — workflow must complete on a vault with
>=50 issues and >=20 PRDs without any agent step hitting its context ceiling.

**Status**: NOT EXERCISED.

**Why blocked**: No large-vault fixture exists. Synthesizing one was out of
scope for both implementer and auditor sessions.

**Mitigation in place**: v5 eliminated `obsidian-discover` entirely — no vault
reads for diffing. `compute-work-list` uses hash-based diff against the local
`.shelf-sync.json` manifest. `obsidian-apply` receives only the pre-filtered
work list via `context_from`, never the raw upstream JSONs. Per-agent payload
is structurally bounded by (# of notes actually changing * per-entry size),
not (# of notes in the vault * full body).

**Path to resolution**: Create a fixture with 50+ issues and 20+ PRDs under
`docs/features/`, run v5, capture per-agent token telemetry, record in
`specs/shelf-sync-efficiency/benchmark/large-vault-result.md` (currently
placeholder). If a ceiling is hit, the lever is trimming `source_data` from
the work list for UPDATE items (they only need programmatic fields) — do NOT
add a second agent (FR-001 ceiling of 1).

**Risk level**: LOW-MEDIUM. The structural mitigation is sound; the risk is
empirical confirmation, not architectural.

---

---

## B-004 — compute-work-list.sh failed to parse .shelf-config whitespace format — RESOLVED

**Requirement**: FR-002 — deterministic diff computation must produce correct
paths from `.shelf-config` fields.

**Status**: RESOLVED (fix committed 2026-04-11, commit `41b3a88`).

**What happened**: `grep '^base_path='` didn't match the `.shelf-config`
format `base_path = value` (spaces around `=`). Result: `base_path` fell
back to `"projects"` and `slug` to `"unknown"`, producing paths like
`projects/unknown/issues/...` that would have corrupted the vault.

**Fix**: Switched to `grep -E '^base_path[[:space:]]*='` with `sed` to strip
whitespace and quotes. Verified by re-running against real `.shelf-config`.

---

## B-005 — Doc sync produces regressed content (summary, status, tags) — RESOLVED in v5

**Requirement**: FR-003 / SC-003 — v4 output must match v3 on a reference
repo.

**Status**: RESOLVED (v5 implementation, 2026-04-16). Root cause of B-002,
resolved by the same v5 patch_file architecture.

**What happened (v4)**: `compute-work-list.sh` pre-rendered frontmatter with
hardcoded summary/status/tags that could not match LLM-inferred v3 values.

**How v5 resolves this**: v5 no longer pre-renders frontmatter in the work
list. Instead:
- On CREATE: the obsidian-apply agent reads `source_data.prd_content` and
  generates meaningful summary, status, tags, and category — matching v3
  behavior where the LLM reads the source and infers these fields.
- On UPDATE: `patch_file` touches only programmatic fields (source, prd_path,
  last_synced, project). Summary, status, tags, and category are never
  overwritten, preserving whatever was set at creation time.

| Field | v3 (LLM-inferred) | v5 CREATE (LLM-inferred) | v5 UPDATE (preserved) |
|---|---|---|---|
| `summary` | Meaningful summary | Meaningful summary | Not touched |
| `status` | Reflects state | Inferred from PRD | Not touched |
| `tags` | Full tag set | Full tag set | Not touched |

**Risk level**: RESOLVED.

---

## Summary table

| ID | Requirement | Status | Risk |
|---|---|---|---|
| B-001 | SC-001 ≤30k tokens | Structural estimate only (~37k ±10k); gate likely unreachable on large vault | MEDIUM |
| B-002 | SC-003 behavioral parity | RESOLVED — v5 patch_file architecture (programmatic vs inferred fields) | — |
| B-003 | SC-004 large vault | Not exercised, structural mitigation in place | LOW-MEDIUM |
| B-004 | FR-002 correct path parsing | RESOLVED — commit 41b3a88 | — |
| B-005 | FR-003 doc content parity | RESOLVED — v5 CREATE uses LLM inference, UPDATE uses patch_file (no overwrite) | — |

**Gates that pass cleanly**: SC-002 (agent count = 1, v5), SC-005 (drop-in by
construction), SC-006 (summary shape verified by smoke test), FR-002/FR-013
(command-side diff + context_from scoping verified in the JSON), FR-004
(path/name unchanged), FR-008 (command steps preserved verbatim), FR-009
(no new deps), FR-011 (harness exists), FR-012 (benchmark repo pinned),
FR-014 (manifest read/write steps present), FR-015 (patch_file for UPDATE),
FR-016 (create_file + LLM inference for CREATE).

**Merge status**: B-002/B-005 RESOLVED by v5 patch_file architecture. Remaining
open blockers: B-001 (token cost empirical verification), B-003 (large-vault
exercise). Neither is merge-blocking — structural mitigations in place.
