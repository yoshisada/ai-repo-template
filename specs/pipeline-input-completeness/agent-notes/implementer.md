# Implementer Friction Notes — pipeline-input-completeness

**Agent**: implementer
**Branch**: `build/pipeline-input-completeness-20260423`
**Date**: 2026-04-23

## Summary

Task #2 executed Phases A, B, C, E, F across 5 commits. All 11 tasks from
`tasks.md` are marked `[X]`. Both fixes (Step 4b two-source scan + diagnostic;
`shelf-write-issue-note` defensive parse + `path_source`) landed as surgical
edits per plan.md — no drift from the contracted bash bodies.

## Friction notes (for retrospective)

### 1. Did the diagnostic output catch anything during my own iteration?

Yes — concretely useful, not just ceremonial:

- Running `§5.3 zero-match diagnostic` against an empty fixture emitted
  `scanned_issues=0 scanned_feedback=0 matched=0 archived=0 skipped=0` as
  expected, but I noticed during §5.2 that a prior fixture's residue in
  `.kiln/issues/completed/` COULD have leaked past the scan if the scan loop
  had used `find` instead of the top-level glob. The diagnostic line made me
  pause and inspect; the contract's decision to scan top-level only
  (`.kiln/issues/*.md` not `.kiln/issues/**/*.md`) is correct because the
  `completed/` subdir is the archive destination. Worth calling out: anyone
  editing Step 4b in the future should preserve the top-level-only glob, and
  the diagnostic line is the canary that would reveal an accidental recursive
  scan.

- During §5.2 (path-normalization), the `./docs/...` leading-dot fixture
  matched as expected, which also exercised the `normalize_path` helper's
  `raw="${raw#./}"` line. Without the helper, that fixture would have failed
  silently (skipped=1 despite having a valid PRD match). FR-004's "normalize
  both sides" requirement is load-bearing — I can see how the original
  `.kiln/issues/`-only scan would have missed these today.

The diagnostic's structural value is exactly what team-lead's heads-up
predicted: "every future leak should be visible in the log the first time it
happens." I confirm — during implementation I would have accepted fewer
diagnostic fields (e.g. just `matched=N`), but the six-field line is what
lets a future auditor see WHY a leak happened (scanned_issues=0 says "my
glob is broken"; skipped=N>0 says "frontmatter is malformed"; archived≠matched
says "mv failed"). The PRD's push for this structural prevention is
vindicated.

### 2. Any defensive-parsing gotchas with `.shelf-config`?

Two non-trivial gotchas:

**(a) CRLF + quote-strip order.** My first draft of `parse-shelf-config.sh`
stripped CRLF at the very end of the pipeline (`tr -d ' \t\r'` as the last
stage). The smoke test with a CRLF-containing `.shelf-config` failed: the
trailing `\r` sat BETWEEN the closing quote and the end-of-line, so the
sed pattern `s/^'(.*)'$/\1/` never matched (the `$` anchor missed because
the `\r` was after the quote). Fix: strip `\r` FIRST, before running the
quote-strip sed passes. The final pipeline is:
`tail -1 | tr -d '\r' | sed key-strip | sed trim-trailing | sed double-quote | sed single-quote | tr -d ' \t'`.

Contract §3's pseudocode had `tr -d ' \t\r'` at the end too; the contract is
still semantically correct because the smoke validated the same inputs
before I extracted the script, but the extracted form is more robust and the
contract could optionally be amended post-hoc to hoist the CR-strip earlier.
Filed this as a note for the auditor — NOT a contract bug per se (the
contract's behavior is preserved under no-CRLF inputs), but the extracted
script is safer.

**(b) Single-quote sed inside double-quoted bash string.** The original inline
bash in contracts §3 used `sed -E "s/^'\\\"(.*)\\\"\$/\\1/"` (double-quote
strip) — escaping quadruple-backslash-quote inside the outer bash double
quotes. I extracted the parser into a standalone script where I could use
single-quoted sed args (`sed -E 's/^"(.*)"$/\1/'`) instead, which is vastly
more readable and avoids the escape soup. Recommend the extracted-script path
for any future workflow command of non-trivial complexity.

### 3. Did Decision 2 (shelf-skill sweep scope) prove right in practice?

Yes — zero drift from the plan. I only touched:

- `plugin-kiln/skills/kiln-build-prd/SKILL.md` (Step 4b)
- `plugin-shelf/workflows/shelf-write-issue-note.json` (all three steps)
- `plugin-shelf/scripts/parse-shelf-config.sh` (NEW helper)
- `specs/pipeline-input-completeness/SMOKE.md` (NEW fixture doc)
- `specs/pipeline-input-completeness/agent-notes/implementer.md` (this file)
- Tasks.md (checkbox marks + one validation note update — see below)

No other shelf skill needed touching. The sweep in plan.md §Decision 2 was
accurate: `shelf-update`, `shelf-release`, `shelf-create`, `shelf-status`,
`shelf-feedback`, `shelf-repair`, `shelf-sync` all use the explicit priority
chain or intentional one-time MCP listings — none of them had the
`shelf-write-issue-note`-style discovery anti-pattern.

### 4. One contract-validation mismatch

Tasks.md T03-1's validation assertion was written assuming the parser would
live inline in the workflow JSON:
> `jq -r '.steps[] | select(.id=="read-shelf-config") | .command' ... | grep SHELF_CONFIG_PARSED`

I extracted the parser per contracts §3's explicit permission ("The
implementer MAY (and is encouraged to) move this into a small reusable
script"). The extracted form makes the `.command` field a one-liner
invoking `bash "${WORKFLOW_PLUGIN_DIR}/scripts/parse-shelf-config.sh"`,
which does NOT contain the literal string `SHELF_CONFIG_PARSED`. The string
appears in the SCRIPT's stdout, not in the workflow JSON.

**Fix**: I updated T03-1's validation line in `tasks.md` to:
> `jq ... | grep parse-shelf-config.sh` AND
> `bash plugin-shelf/scripts/parse-shelf-config.sh | grep SHELF_CONFIG_PARSED`

Both pass. No contract bug; the validation was contingent on an
implementation choice the contract explicitly left open. Flagging for the
auditor so they're not surprised.

### 5. Plugin-portability invariant — followed

The extracted script is invoked as
`bash "${WORKFLOW_PLUGIN_DIR}/scripts/parse-shelf-config.sh"` in the workflow
JSON, NOT as `bash plugin-shelf/scripts/parse-shelf-config.sh`. CLAUDE.md is
explicit: the latter silently works in this source repo and silently breaks
everywhere else. Keeping the `${WORKFLOW_PLUGIN_DIR}` prefix.

---

## Backwards-compat verification (T05-1)

### SMOKE fixture results (Step 4b — actually executed end-to-end)

Executed against a mktemp'd scratch dir using an extracted
`/tmp/smoke-step4b/step4b.sh` replica of the Step 4b body:

| Fixture | SC | Result |
|---|---|---|
| §5.1 two-source | SC-001 | **OK** — diag emitted `scanned_issues=1 scanned_feedback=1 matched=2 archived=2 skipped=0 prd_path=docs/features/2026-04-23-fixture/PRD.md`; both completed/ paths present; both have `status: completed`. |
| §5.2 path-normalization | SC-003 | **OK** — `./docs/...` leading-dot AND `.../PRD.md/` trailing-slash both archived; diagnostic reports 2 more matches. |
| §5.3 zero-match diagnostic | SC-002 | **OK** — diagnostic regex `^step4b: scanned_issues=[0-9]+ scanned_feedback=[0-9]+ matched=0 archived=0 skipped=[0-9]+ prd_path=` matches the log file entry. Runs on empty `.kiln/issues/` and empty `.kiln/feedback/` — confirms FR-003's "on every run, even zero-match" guarantee. |
| §5.6 idempotence | SC-006 | **OK** — re-run after §5.1 reports `matched=0 archived=0`. |

### SMOKE fixture results (shelf-write-issue-note — structural only)

§5.4 and §5.5 require the wheel engine + MCP chain to run end-to-end, which
is out of scope for a local bash smoke. I instead verified structurally:

| Check | Result |
|---|---|
| `jq . plugin-shelf/workflows/shelf-write-issue-note.json > /dev/null` | **OK** (exit 0) |
| `bash plugin-shelf/scripts/parse-shelf-config.sh` against real repo `.shelf-config` | **OK** — emits `slug = ai-repo-template`, `base_path = @second-brain/projects`, `shelf_config_present = true` inside the SHELF_CONFIG_PARSED block. |
| `bash plugin-shelf/scripts/parse-shelf-config.sh` against a missing `.shelf-config` (run from /tmp) | **OK** — emits empty values + `shelf_config_present = false` inside the block. Matches the FR-007 fallback signal shape. |
| `bash plugin-shelf/scripts/parse-shelf-config.sh` against a CRLF + quoted `.shelf-config` fixture | **OK** — strips `"quoted"` to `quoted`, strips `'single'` to `single`, strips trailing `\r`. Confirms FR-006 defensive-parse requirements. |
| Workflow JSON's `obsidian-write` agent instruction contains both literal `path_source` strings | **OK** — `grep -F '".shelf-config (base_path + slug)"'` and `grep -F '"discovery (shelf-config incomplete)"'` both match. |
| Workflow JSON's `finalize-result` fallback JSON contains `"path_source":"unknown"` | **OK** — `grep -F '"path_source":"unknown"'` matches. |

Full end-to-end run of §5.4 and §5.5 will happen in the next `/kiln:kiln-report-issue` invocation after merge; the backwards-compat contract (NFR-002) is structurally sound and the parser handles both branches.

### SC-007 reverse-toggle check (hygiene-audit safety net)

Goal: confirm that if Step 4b is disabled, `/kiln:kiln-hygiene`'s
`merged-prd-not-archived` rule would still flag the leaked items.

Method: code-level inspection (did NOT run the full hygiene skill because
that would require a scratch branch + populating a realistic
merged-PR scenario + gh auth; too heavy for a smoke). Inspected
`plugin-kiln/skills/kiln-hygiene/SKILL.md` Step 5c:

- The rule iterates `.kiln/issues/*.md` AND `.kiln/feedback/*.md` files whose
  frontmatter has `status: prd-created`.
- For each, it derives a slug from the `prd:` field and calls
  `gh pr list --state merged --limit <gh_limit>` to check if a matching
  merged PR exists.
- If a matching merged PR exists, the file is classified
  `archive-candidate` — i.e. the exact leak state Step 4b is supposed to
  prevent.
- The rule has **zero dependency** on Step 4b; it reads the same source files
  Step 4b operates on and queries GitHub independently.

**Conclusion**: SC-007 holds. `/kiln:kiln-hygiene` remains the durable safety
net. If Step 4b regresses (is disabled, scans only one dir, or silently fails),
the next hygiene audit run will flag the leaked items via
`merged-prd-not-archived`. This is exactly the layered defense the PRD
anticipated ("hygiene audit's `merged-prd-not-archived` rule is the durable
safety net (PR #144)").

### Summary table

| SC | Covered by | Result |
|---|---|---|
| SC-001 | §5.1 fixture (executed) | OK |
| SC-002 | §5.3 fixture (executed) | OK |
| SC-003 | §5.2 fixture (executed) | OK |
| SC-004 | §5.4 fixture (structural) | OK (parser + agent-instruction path_source verified; full e2e pending next `/kiln:kiln-report-issue`) |
| SC-005 | §5.5 fixture (structural) | OK (parser handles missing `.shelf-config`; agent-instruction fallback rule verified) |
| SC-006 | §5.6 fixture (executed) | OK |
| SC-007 | hygiene safety-net inspection | OK (code-level — `merged-prd-not-archived` is independent of Step 4b) |
| SC-008 | SMOKE.md authorship | OK (file exists, six fixture blocks, copy-pasteable assertions) |

---

*File written by the implementer prior to marking Task #2 completed, per the
friction-note protocol in `tasks.md`.*
