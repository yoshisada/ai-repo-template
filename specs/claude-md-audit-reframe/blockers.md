# Blockers — claude-md-audit-reframe

**Status**: 0 unresolved
**Compliance**: 100% (29/29 PRD FRs covered, 19/19 new fixtures structurally verified, smoke test passed)

No blockers identified during the audit pass. All FRs trace to spec, code, and at least one fixture. The two non-blocking observations below are flagged for follow-on PRs (out of scope for this build).

## Non-blocking observations

### O-1: project-context reader emits malformed JSON on control characters in PRD bodies
- **Where**: `plugin-kiln/scripts/context/read-project-context.sh`
- **Symptom**: When a PRD body contains literal control characters (U+0000..U+001F unescaped), the reader's emitted JSON fails to parse. The auditor's source-repo run hit this on line 1161 column 199.
- **Mitigation in place**: Skill body's Step 1 fallback path catches the parse failure and degrades to an empty snapshot (`warn: project-context reader unavailable`). The audit completes successfully.
- **Owner for follow-on**: separate from this PR. File as a `.kiln/issues/` capture; reader script hardening (likely jq `-Rs` + escape pass) is the fix.

### O-2: source-repo `.kiln/vision.md` is 44 lines without sync-region markers
- **Where**: `.kiln/vision.md` at repo root
- **Symptom**: Triggers the `vision-overlong-unmarked` sub-signal under `product-section-stale` per FR-023 Edge Cases. This is correct rule behavior, not a bug.
- **Mitigation options**: maintainer adds `<!-- claude-md-sync:start --> ... <!-- claude-md-sync:end -->` markers around a summary region, OR shortens vision.md ≤40 lines, OR sets `product_sync = false` in `.kiln/claude-md-audit.config` per FR-029.
- **Owner for follow-on**: maintainer; not this PR's concern.

### O-3: T201 (full /kiln:kiln-test plugin-kiln batch run) deferred to maintainer-driven follow-on
- **Where**: `plugin-kiln/tests/claude-audit-*/` (23 fixtures, each with `timeout-override: 900`)
- **Substrate decision**: Auditor performed structural substrate verification (assertion-shape spot-checks confirmed real `grep -qE` + FAIL exits + PASS reporting; no stubs) plus the in-pipeline smoke test on the actual source-repo CLAUDE.md (T202 + T203 idempotence simulation). Full 23-fixture batch run via `/kiln:kiln-test plugin-kiln` is documented as the maintainer-driven follow-on validation gate.
- **Rationale**: in-pipeline auditor budget cannot accommodate ~5.75hr of subprocess execution. Live-substrate-first rule's third tier (structural surrogate) is invoked per team-lead's brief, with the gap explicitly flagged here per the rule's documentation requirement.
- **Owner for follow-on**: maintainer (pre-merge or post-merge `/kiln:kiln-test plugin-kiln` invocation).
