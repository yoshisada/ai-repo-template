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

## B-002 — SC-003 (Obsidian behavioral parity) — CONFIRMED REGRESSION on docs

**Requirement**: FR-003 / SC-003 — v4 run must produce a byte-identical
Obsidian snapshot to v3 on a frozen fixture.

**Status**: CONFIRMED REGRESSION (live run 2026-04-11). Workflow stopped
before obsidian-apply executed; vault was NOT written.

**What happened**: A post-pipeline live run on the real vault revealed that
`compute-work-list.sh` generates doc entries with:
- `summary = title` (copy of doc title, not a meaningful summary)
- `status = "Draft"` (hardcoded, ignores actual implementation state)
- `tags` missing `status/*` and `category/*` entries present in existing vault

All 24 doc update actions would have regressed existing vault content.

**Root cause**: bash cannot infer what v3 LLM agents derived from reading PRD
content. The v4 architecture works for issues (content comes from GitHub JSON
verbatim) but fails for docs (content requires reading and summarizing PRDs).

**Scope**: Issue sync is likely correct. Doc sync is the broken surface.

**Path to resolution**: Choose between:
- **Road A (vault schema split)**: Separate vault frontmatter into programmatic
  fields (synced deterministically) and inferred fields (set on create only,
  never overwritten on update). Requires vault migration script.
- **Road B (merge-aware apply)**: obsidian-apply reads existing note before
  writing, merging computed fields over preserved LLM-inferred fields. No vault
  migration needed; obsidian-apply makes more MCP read calls.

See backlog issue `2026-04-11-shelf-vault-programmatic-interactions.md` for
architectural detail. Both roads require spec update before code changes.

**Risk level**: CRITICAL. This is a correctness regression that blocks merge.

---

## B-003 — SC-004 (large-vault ceiling) not exercised

**Requirement**: FR-006 / SC-004 — workflow must complete on a vault with
>=50 issues and >=20 PRDs without any agent step hitting its context ceiling.

**Status**: NOT EXERCISED.

**Why blocked**: No large-vault fixture exists. Synthesizing one was out of
scope for both implementer and auditor sessions.

**Mitigation in place**: `obsidian-discover` emits only
`{path, last_synced, status, github_number, source}` per note (no body) per
contracts section 4.3. `obsidian-apply` receives only the pre-filtered work
list, never the raw index or raw upstream JSONs. Per-agent payload is
structurally bounded by (# of notes actually changing * per-entry size),
not (# of notes in the vault * full body).

**Path to resolution**: Create a fixture with 50+ issues and 20+ PRDs under
`docs/features/`, run v4, capture per-agent token telemetry, record in
`specs/shelf-sync-efficiency/benchmark/large-vault-result.md` (currently
placeholder). If a ceiling is hit, the documented lever is shrinking the
discovery index payload further — do NOT add a third agent (FR-001 ceiling).

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

## B-005 — Doc sync produces regressed content (summary, status, tags)

**Requirement**: FR-003 / SC-003 — v4 output must match v3 on a reference
repo.

**Status**: CONFIRMED REGRESSION (live run 2026-04-11). Root cause of B-002.
Vault not written — workflow stopped before obsidian-apply executed.

**What happened**: `compute-work-list.sh` cannot derive the LLM-inferred
fields that v3 agents computed by reading PRD files:

| Field | v3 (LLM-inferred) | v4 (deterministic) | Regresses? |
|---|---|---|---|
| `summary` | Meaningful summary from PRD | Copy of `title` | YES |
| `status` | Reflects implementation state | Hardcoded `"Draft"` | YES |
| `tags` | Includes `status/*`, `category/*` | Only `doc/prd` | YES |

**Scope**: Issue sync is unaffected (content from GitHub JSON verbatim).
Doc sync (24 updates on this vault) would regress all three fields.

**Path to resolution**: See backlog issue
`2026-04-11-shelf-vault-programmatic-interactions.md`. Road A or Road B
must be chosen and specced before this branch can merge.

**Risk level**: CRITICAL. Merge-blocking.

---

## Summary table

| ID | Requirement | Status | Risk |
|---|---|---|---|
| B-001 | SC-001 ≤30k tokens | Structural estimate only (~37k ±10k); gate likely unreachable on large vault | MEDIUM |
| B-002 | SC-003 behavioral parity | CONFIRMED REGRESSION (doc sync) — root cause is B-005 | CRITICAL |
| B-003 | SC-004 large vault | Not exercised, structural mitigation in place | LOW-MEDIUM |
| B-004 | FR-002 correct path parsing | RESOLVED — commit 41b3a88 | — |
| B-005 | FR-003 doc content parity | CONFIRMED REGRESSION — LLM-inferred fields cannot be reproduced in bash | CRITICAL |

**Gates that pass cleanly**: SC-002 (agent count = 2), SC-005 (drop-in by
construction), SC-006 (summary shape verified by smoke test), FR-002/FR-013
(command-side diff + context_from scoping verified in the JSON), FR-004
(path/name unchanged), FR-008 (command steps preserved verbatim), FR-009
(no new deps), FR-011 (harness exists), FR-012 (benchmark repo pinned).

**Merge status**: BLOCKED on B-002/B-005. Requires architectural decision
(Road A or Road B) and re-implementation before merge.
