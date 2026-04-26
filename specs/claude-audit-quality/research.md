# Research — claude-audit-quality

## Baseline

Captured by `researcher-baseline` on 2026-04-25 against `build/claude-audit-quality-20260425` (current branch; identical to `main` for CLAUDE.md, the rubric, the best-practices cache, and `plugin-kiln/scripts/context/` — no claude-audit changes have landed on this branch yet, so this measurement reflects pre-PR state).

### What "duration" we measured

`/kiln:kiln-claude-audit` is a Claude Code Skill, not a shell command — the model executes it inside its tool harness and we cannot wrap the full Skill invocation in `time` from a sub-agent shell. Per the team-lead's instruction (and per the SKILL.md note that "editorial LLM calls have no latency target for this skill"), we measured the **shell-side portion** the Skill performs:

- `plugin-kiln/scripts/context/read-project-context.sh` invocation (project-context snapshot)
- Rubric file load + `### <rule_id>` enumeration (`plugin-kiln/rubrics/claude-md-usefulness.md`)
- Best-practices cache header read (`plugin-kiln/rubrics/claude-md-best-practices.md` — `fetched:` + `cache_ttl_days:` parse, no WebFetch)
- All cheap rubric rules against the audited file set:
  - `load-bearing-section` citation grep across `plugin-kiln/{skills,agents,hooks,templates}` (the dominant cost)
  - `stale-migration-notice` blockquote grep
  - `recent-changes-overflow` bullet count
  - `active-technologies-overflow` bullet count
  - `hook-claim-mismatch` cheap claim extraction
- Plugin enumeration (project + user `enabledPlugins` union via `jq`) + per-plugin guidance-file resolution
- Vision.md region detection (line count + sync-marker grep)

This is everything the Skill does in shell **before** it issues editorial LLM calls. It does **not** include:

- Editorial LLM calls for `duplicated-in-prd`, `duplicated-in-constitution`, `stale-section`, `enumeration-bloat` (the LLM framing call — the cheap pass IS counted), `benefit-missing`, `loop-incomplete`, `product-slot-missing`, the FR-001 section-classification call, or external-best-practices delta evaluation.
- The output-file write (cheap; rounding noise).

NFR-001 says "audit duration MUST NOT increase by more than 30% relative to the pre-PR baseline." Reading the auditor's perspective: NFR-001 is enforceable on the shell-portion measurement (deterministic, reproducible across machines) and is **not** enforceable on the editorial portion (model-time, dependent on which model variant the harness routes to that day). The auditor for task #5 should re-run `/tmp/audit-bench.sh` post-PR and check the median against the +30% gate documented below.

### Audit duration — 5 sequential runs (warm cache after run 1)

| Run | Duration (s) |
|---|---|
| 1 (cold) | 0.851 |
| 2 (warm) | 0.647 |
| 3 (warm) | 0.660 |
| 4 (warm) | 0.786 |
| 5 (warm) | 0.790 |

- **Median**: **0.786 s**
- Mean: 0.747 s
- Min: 0.647 s
- Max: 0.851 s

**NFR-001 +30% gate (against median)**: post-PR median MUST be `≤ 1.022 s` (0.786 × 1.30) measured by the same script on this same repo state.

### Test command (re-runnable for SC verification)

```bash
# From the repo root, on a branch whose CLAUDE.md / rubric / best-practices cache /
# plugin-kiln/scripts/context/ tree match this baseline:
for i in 1 2 3 4 5; do echo "run $i: $(bash /tmp/audit-bench.sh)"; done
```

The benchmark script lives at `/tmp/audit-bench.sh` for this run; its source is reproduced verbatim below so the auditor can rebuild it on a fresh checkout (the `/tmp` location is intentionally ephemeral — it does NOT belong in the repo, since timing the cheap portion of an audit is not a regression-test we want CI to enforce):

```bash
#!/usr/bin/env bash
set -e
START=$(/usr/bin/python3 -c 'import time; print(time.time())')

# 1. Project-context reader
bash plugin-kiln/scripts/context/read-project-context.sh > /tmp/audit-bench-ctx.json 2>/dev/null || true

# 2. Rubric load
RUBRIC=plugin-kiln/rubrics/claude-md-usefulness.md
wc -l "$RUBRIC" >/dev/null
grep -c '^### ' "$RUBRIC" >/dev/null

# 3. Best-practices cache load
BP=plugin-kiln/rubrics/claude-md-best-practices.md
awk '/^fetched:/ { print $2; exit }' "$BP" >/dev/null
awk '/^cache_ttl_days:/ { print $2; exit }' "$BP" >/dev/null
wc -l "$BP" >/dev/null

# 4. Cheap rules against both audited files
for F in CLAUDE.md plugin-kiln/scaffold/CLAUDE.md; do
  [ -f "$F" ] || continue
  grep -c '^## ' "$F" >/dev/null
  grep -c -E 'Migration Notice|renamed from' "$F" >/dev/null || true
  awk '/^## Recent Changes/,/^## [^R]/' "$F" | grep -c '^- ' >/dev/null || true
  awk '/^## Active Technologies/,/^## [^A]/' "$F" | grep -c '^- ' >/dev/null || true
  grep -c -i -E 'hook|\.sh' "$F" >/dev/null || true
  for SEC in $(grep '^## ' "$F" | sed 's/^## //'); do
    grep -r -l --include='*.md' "$SEC" plugin-kiln/skills plugin-kiln/agents plugin-kiln/hooks plugin-kiln/templates >/dev/null 2>&1 || true
  done
done

# 5. Plugin enumeration + guidance-file resolution
PROJECT_ENABLED=$(jq -r '.enabledPlugins // [] | .[]' .claude/settings.json 2>/dev/null || true)
USER_ENABLED=$(jq -r '.enabledPlugins // [] | .[]' ~/.claude/settings.json 2>/dev/null || true)
ENABLED_PLUGINS=$( { printf '%s\n' "$PROJECT_ENABLED"; printf '%s\n' "$USER_ENABLED"; } | grep -v '^$' | sort -u )
for P in $ENABLED_PLUGINS; do
  test -f "plugin-${P}/.claude-plugin/claude-guidance.md" && wc -l "plugin-${P}/.claude-plugin/claude-guidance.md" >/dev/null || true
done

# 6. Vision.md region detection
VISION=.kiln/vision.md
if [ -f "$VISION" ]; then
  wc -l "$VISION" >/dev/null
  grep -c 'claude-md-sync:start' "$VISION" >/dev/null || true
fi

END=$(/usr/bin/python3 -c 'import time; print(time.time())')
/usr/bin/python3 -c "print(f'{${END} - ${START}:.3f}')"
```

### Audited files

The kiln source repo audits two files in one invocation (per SKILL.md Step 1b — "Source repo: both the real CLAUDE.md and the scaffold get audited"):

| Path | Size | Lines | Purpose |
|---|---|---|---|
| `CLAUDE.md` | 37 912 bytes | 305 | The real plugin-source-repo CLAUDE.md (this is the one humans + Claude Code consume in this repo) |
| `plugin-kiln/scaffold/CLAUDE.md` | 2 510 bytes | 47 | Scaffolded into consumer projects by `plugin-kiln/bin/init.mjs` |

Consumer-mode invocations only audit a single CLAUDE.md at the repo root.

### Latest audit log — signals breakdown

Source: `.kiln/logs/claude-md-audit-2026-04-25-202320.md` (most recent log; flagged in its own preamble as **smoke-test scope** — editorial passes for `benefit-missing` and `product-slot-missing` were deferred and surface as `inconclusive` rows, not as content findings).

**Total signals fired**: 6 rows in the Signal Summary table.

| signal_type | count | rules contributing |
|---|---|---|
| substance | 0 | — |
| freshness | 1 | `product-section-stale` (vision.md overlong-unmarked sub-signal) |
| bloat | 3 | `enumeration-bloat` × 2 (`## Active Technologies`, `## Available Commands`); `recent-changes-overflow` × 1 (`## Recent Changes`, count 6 > 5 threshold) |
| coverage | 2 | `benefit-missing` (inconclusive — deferred); `product-slot-missing` (inconclusive — deferred) |
| external | 0 (rendered as separate `## External best-practices deltas` table, not as Signal Summary rows; that table held 2 deltas + 1 "no deltas found" row this run) |

### Notes section length

| Metric | Value | Source |
|---|---|---|
| `## Notes` section bytes | 2 260 | `awk '/^## Notes/,/^## Smoke-test/' .kiln/logs/claude-md-audit-2026-04-25-202320.md` |
| `## Notes` section line count | 12 | (same) |

(The latest log has an extra `## Smoke-test verification` section because it was written explicitly as a smoke-test invocation. A normal-scope audit terminates at `## Notes`; auditor for task #5 should treat the Smoke-test trailer as out-of-band.)

### NFR-003 reference byte counts (idempotence anchor)

NFR-003 says `## Signal Summary` and `## Proposed Diff` MUST be byte-identical pre-vs-post on the same input. These are the reference byte counts the auditor should compare against. If the implementation changes either section's bytes on unchanged input, NFR-003 is broken.

| Section | Bytes | Lines |
|---|---|---|
| `## Signal Summary` | **843** | 11 (excluding the trailing `## Proposed Diff` boundary line) |
| `## Proposed Diff` | **2 281** | 46 |

Reproduce:

```bash
/usr/bin/python3 <<'PY'
import re
p = ".kiln/logs/claude-md-audit-2026-04-25-202320.md"
text = open(p).read()
def section(start, end):
    m = re.search(rf'^{re.escape(start)}.*?(?=^{re.escape(end)})', text, re.M | re.S)
    return m.group(0) if m else ""
ss = section("## Signal Summary", "## Proposed Diff")
pd = section("## Proposed Diff", "## Plugins Sync")
print(f"signal_summary_bytes={len(ss)}")
print(f"proposed_diff_bytes={len(pd)}")
PY
```

**Caveat for the auditor**: the latest log is a smoke-test-scope run. If the implementation produces a *full* (non-smoke) audit on the same inputs, the byte counts will differ — that's expected behavior, not an NFR-003 violation. NFR-003 is a "two runs of the same scope on unchanged inputs are byte-identical" gate, not "smoke and full match." The cleanest way to test NFR-003 post-implementation is: run the new audit twice in a row with stable inputs, diff the two output files, ignore only the timestamp header line, expect 0 diff in `## Signal Summary` + `## Proposed Diff`.

### Environment / repro context

- Branch: `build/claude-audit-quality-20260425`
- Repo: `/Users/ryansuematsu/Documents/github/personal/ai-repo-template`
- Date: 2026-04-25
- macOS (BSD coreutils); `python3` resolved to system `/usr/bin/python3` for portable wall-clock; `jq` 1.7.1-apple
- The project-context reader exits non-zero on this branch (the same control-character / jq-1.7.1-apple bug noted in the latest audit log's `## Notes`); the benchmark script tolerates that with `|| true` and falls through. If the reader is fixed before the auditor re-runs the gate, the median may *drop* slightly — that's a free win, not a regression.
