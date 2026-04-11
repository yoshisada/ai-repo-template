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

## B-002 — SC-003 (Obsidian byte-parity) not run against a live vault

**Requirement**: FR-003 / SC-003 — v4 run must produce a byte-identical
Obsidian snapshot to v3 on a frozen fixture.

**Status**: HARNESS VERIFIED, LIVE DIFF DEFERRED.

**Why blocked**: No live Obsidian vault is wired into this session and no
frozen fixture vault exists on disk. The snapshot-capture script requires
`OBSIDIAN_VAULT_ROOT` to be set (verified during audit smoke test — it exits
2 with a clear error when unset).

**Current evidence**: The harness itself works —
`plugin-shelf/scripts/obsidian-snapshot-capture.sh` +
`obsidian-snapshot-diff.sh` exit 0 on identical, 1 on differences, 2 on
error, verified by the auditor on a synthetic fixture at `/tmp/snap-test/`.

**Important semantic caveat** (flagged by implementer in benchmark-results.md
risk #3): v3 rendered issue/doc bodies using LLM judgment for
severity/category/body text; v4 uses deterministic defaults (severity=medium,
body="Synced from GitHub issue #N."). A strict body-hash parity check against
a v3 snapshot captured from the real (LLM-rendered) run will almost certainly
flag differences on those fields. Before declaring SC-003 pass/fail, the team
must decide whether parity means:

- **Strict body-hash equality** -> v4 will fail and must add LLM-rendered
  fields back to agent work (which risks re-inflating token cost), OR
- **Structural parity** (path + type + status + frontmatter schema match) ->
  v4 passes once the harness is run live and only the expected deterministic
  fields differ.

**Path to resolution**: (a) team-lead decides strict vs structural parity;
(b) after decision, run v3 and v4 against the same fixture vault, capture
snapshots, diff, and record in
`specs/shelf-sync-efficiency/benchmark/parity-result.md` — that file
currently exists but holds placeholder data.

**Risk level**: MEDIUM-HIGH. Parity is the precondition for shipping per the
spec. If the team chooses strict parity, v4 likely needs rework.

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

## Summary table

| ID | Requirement | Status | Risk |
|---|---|---|---|
| B-001 | SC-001 <=30k tokens | Structural estimate only (~37k +/-10k) | MEDIUM |
| B-002 | SC-003 byte parity | Harness built, live diff deferred + semantic caveat | MEDIUM-HIGH |
| B-003 | SC-004 large vault | Not exercised, structural mitigation in place | LOW-MEDIUM |

**Gates that pass cleanly**: SC-002 (agent count = 2), SC-005 (drop-in by
construction), SC-006 (summary shape verified by smoke test), FR-002/FR-013
(command-side diff + context_from scoping verified in the JSON), FR-004
(path/name unchanged), FR-008 (command steps preserved verbatim), FR-009
(no new deps), FR-011 (harness exists), FR-012 (benchmark repo pinned).

**Recommendation**: Team-lead should decide whether to ship this PR as-is
(accepting B-001/B-002/B-003 for follow-up) or to block merge on a clean
live-run confirmation of B-001 and B-002 before the branch lands.
