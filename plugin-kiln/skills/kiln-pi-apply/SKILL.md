---
name: kiln-pi-apply
description: Read open GitHub retrospective issues, extract File/Current/Proposed/Why PI blocks, and emit a propose-don't-apply diff report at .kiln/logs/pi-apply-<timestamp>.md. Never writes to skill/agent files — same discipline as /kiln:kiln-claude-audit and /kiln:kiln-hygiene. Use this to close the retro → source feedback loop when unresolved PIs accumulate.
---

# Kiln PI-Apply — Propose Prompt-Improvement Diffs

Consolidates unresolved Prompt Improvement (PI) proposals from open GitHub retrospective issues into a single reviewable diff report. The report is written to `.kiln/logs/pi-apply-<timestamp>.md`. **This skill never applies edits** — the maintainer reviews the report and chooses which proposals to accept.

Contracts:
- Script signatures + exit codes — `specs/workflow-governance/contracts/interfaces.md` Module 3.
- Report schema + section order — Module 3 §emit-report.sh.
- `pi-hash` algorithm — spec.md Clarification 7.
- Stale-anchor policy — spec.md Clarification 6.

## User Input

```text
$ARGUMENTS
```

V1 accepts no arguments. A `--since <date>` filter is tracked as a follow-on (PRD R-3).

## Step 0 — Flag parse + script path resolution

```bash
# FR-009: V1 takes no arguments. Reject unexpected flags to fail fast.
if [[ -n "${1:-}" ]]; then
  echo "kiln-pi-apply: no arguments accepted in V1 (received: $*)" >&2
  exit 2
fi

# Resolve the pi-apply script base. Prefer source-repo layout; fall back to
# $CLAUDE_PLUGIN_ROOT (consumer install or harness test scratch dir).
SCRIPT_BASE="plugin-kiln/scripts/pi-apply"
if [[ ! -d "$SCRIPT_BASE" ]]; then
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -d "${CLAUDE_PLUGIN_ROOT}/scripts/pi-apply" ]]; then
    SCRIPT_BASE="${CLAUDE_PLUGIN_ROOT}/scripts/pi-apply"
  else
    # Last-ditch: search the user's plugin cache (consumer install via `claude plugins`).
    CACHE_HIT=$(find "${HOME}/.claude/plugins/cache" -type d -name pi-apply 2>/dev/null | head -1 || true)
    if [[ -n "$CACHE_HIT" ]]; then
      SCRIPT_BASE="$CACHE_HIT"
    else
      echo "kiln-pi-apply: cannot locate pi-apply script dir; checked plugin-kiln/scripts/pi-apply, \$CLAUDE_PLUGIN_ROOT/scripts/pi-apply, and ~/.claude/plugins/cache" >&2
      exit 1
    fi
  fi
fi
```

## Step 1 — Fetch retro issues

<!-- FR-009: gh-backed fetch with fixture stub. NFR-002: must complete within 60s for ≤20 issues. -->

```bash
FETCH="$SCRIPT_BASE/fetch-retro-issues.sh"
if [[ ! -f "$FETCH" ]]; then
  echo "kiln-pi-apply: fetch helper missing at $FETCH" >&2
  exit 1
fi

# PI_APPLY_FETCH_STUB is the test hook — fixtures drop a canned JSON array and
# point at it via the env var. Live usage sets nothing and the script calls gh.
ISSUES_JSON=$(bash "$FETCH") || {
  echo "kiln-pi-apply: retro issue fetch failed (see stderr above)" >&2
  exit 3
}

ISSUE_COUNT=$(printf '%s' "$ISSUES_JSON" | jq 'length')
```

When `$ISSUE_COUNT == 0`, Step 2 is a no-op (the `seq` loop below has zero iterations), Step 3/4 also iterate over an empty stream, and Step 5's `emit-report.sh` handles the empty-stream path by writing the schema-stable "No open retro issues found" report. No early return needed — the downstream stages already degrade correctly.

## Step 2 — Parse PI blocks per issue

<!-- FR-009: extract File / Current / Proposed / Why blocks from each issue body. -->

```bash
PARSE="$SCRIPT_BASE/parse-pi-blocks.sh"

# Accumulate parsed blocks as NDJSON with issue_url joined in.
BLOCKS_NDJSON=""
# When ISSUE_COUNT is 0, the loop body never runs — `seq 0 -1` emits nothing.
if [[ "$ISSUE_COUNT" -gt 0 ]]; then
 for i in $(seq 0 $((ISSUE_COUNT - 1))); do
  NUMBER=$(printf '%s' "$ISSUES_JSON" | jq -r ".[$i].number")
  URL=$(printf '%s' "$ISSUES_JSON" | jq -r ".[$i].url")
  BODY=$(printf '%s' "$ISSUES_JSON" | jq -r ".[$i].body")

  # parse-pi-blocks emits one JSON record per block (plus parse_error records);
  # we enrich each with the issue_url so downstream scripts don't need to re-join.
  PARSED=$(printf '%s' "$BODY" | bash "$PARSE" "$NUMBER" || true)
  if [[ -z "$PARSED" ]]; then continue; fi
  ENRICHED=$(printf '%s\n' "$PARSED" | jq -c --arg url "$URL" '. + {issue_url: $url}')
  BLOCKS_NDJSON+="$ENRICHED"$'\n'
 done
fi
# Trim trailing newline for clean NDJSON.
BLOCKS_NDJSON="${BLOCKS_NDJSON%$'\n'}"
```

## Step 3 — Classify status per block

<!-- FR-012: classify each block as actionable / already-applied / stale. -->

```bash
CLASSIFY="$SCRIPT_BASE/classify-pi-status.sh"

CLASSIFIED_NDJSON=""
if [[ -n "$BLOCKS_NDJSON" ]]; then
  while IFS= read -r rec; do
    [[ -z "$rec" ]] && continue

    # parse_error records pass through untouched — they go straight to the emit stream.
    IS_ERR=$(printf '%s' "$rec" | jq -r 'has("parse_error")')
    if [[ "$IS_ERR" == "true" ]]; then
      CLASSIFIED_NDJSON+="$rec"$'\n'
      continue
    fi

    FILE=$(printf '%s' "$rec" | jq -r '.file')
    ANCHOR=$(printf '%s' "$rec" | jq -r '.anchor')
    PROPOSED=$(printf '%s' "$rec" | jq -r '.proposed')

    STATUS=$(bash "$CLASSIFY" \
      --target-file "$FILE" \
      --target-anchor "$ANCHOR" \
      --proposed "$PROPOSED")

    CLASSIFIED=$(printf '%s' "$rec" | jq -c --arg s "$STATUS" '. + {status: $s}')
    CLASSIFIED_NDJSON+="$CLASSIFIED"$'\n'
  done <<<"$BLOCKS_NDJSON"
  CLASSIFIED_NDJSON="${CLASSIFIED_NDJSON%$'\n'}"
fi
```

## Step 4 — Render diffs + compute pi-hashes

<!-- FR-010 / FR-011: render unified-diff only for actionable; compute pi-hash for all non-error records. -->

```bash
RENDER="$SCRIPT_BASE/render-pi-diff.sh"
HASH="$SCRIPT_BASE/compute-pi-hash.sh"

FINAL_NDJSON=""
if [[ -n "$CLASSIFIED_NDJSON" ]]; then
  while IFS= read -r rec; do
    [[ -z "$rec" ]] && continue

    IS_ERR=$(printf '%s' "$rec" | jq -r 'has("parse_error")')
    if [[ "$IS_ERR" == "true" ]]; then
      FINAL_NDJSON+="$rec"$'\n'
      continue
    fi

    ISSUE=$(printf '%s' "$rec" | jq -r '.issue_number')
    FILE=$(printf '%s' "$rec" | jq -r '.file')
    ANCHOR=$(printf '%s' "$rec" | jq -r '.anchor')
    CURRENT=$(printf '%s' "$rec" | jq -r '.current')
    PROPOSED=$(printf '%s' "$rec" | jq -r '.proposed')
    STATUS=$(printf '%s' "$rec" | jq -r '.status')

    DIFF=""
    if [[ "$STATUS" == "actionable" ]]; then
      DIFF=$(bash "$RENDER" \
        --target-file "$FILE" \
        --target-anchor "$ANCHOR" \
        --current "$CURRENT" \
        --proposed "$PROPOSED") || DIFF=""
    fi

    # FR-011: pi-hash covers (issue, file, anchor, proposed) per Clarification 7.
    # For actionable records we pass the rendered DIFF; for non-actionable we pass
    # the proposed text itself so hashes stay stable across runs for the same PI.
    HASH_INPUT="$DIFF"
    [[ "$STATUS" != "actionable" ]] && HASH_INPUT="$PROPOSED"
    PI_HASH=$(bash "$HASH" \
      --issue-number "$ISSUE" \
      --target-file "$FILE" \
      --target-anchor "$ANCHOR" \
      --proposed-diff "$HASH_INPUT")

    if [[ -n "$DIFF" ]]; then
      ENRICHED=$(printf '%s' "$rec" | jq -c --arg d "$DIFF" --arg h "$PI_HASH" '. + {diff: $d, pi_hash: $h}')
    else
      ENRICHED=$(printf '%s' "$rec" | jq -c --arg h "$PI_HASH" '. + {pi_hash: $h}')
    fi
    FINAL_NDJSON+="$ENRICHED"$'\n'
  done <<<"$CLASSIFIED_NDJSON"
  FINAL_NDJSON="${FINAL_NDJSON%$'\n'}"
fi
```

## Step 5 — Emit the report

<!-- FR-010: report goes to .kiln/logs/pi-apply-<timestamp>.md; never writes to skill/agent files. -->

```bash
EMIT="$SCRIPT_BASE/emit-report.sh"
REPORT_PATH=$(printf '%s' "$FINAL_NDJSON" | bash "$EMIT") || {
  echo "kiln-pi-apply: emit-report failed" >&2
  exit 1
}
```

## Step 6 — User-visible summary

Print a single line for the user summarising the result and the report path:

```bash
N_ACT=$(printf '%s' "$FINAL_NDJSON" | jq -c 'select(.status == "actionable")'       | grep -c . || true)
N_APP=$(printf '%s' "$FINAL_NDJSON" | jq -c 'select(.status == "already-applied")' | grep -c . || true)
N_STA=$(printf '%s' "$FINAL_NDJSON" | jq -c 'select(.status == "stale")'           | grep -c . || true)
N_ERR=$(printf '%s' "$FINAL_NDJSON" | jq -c 'select(has("parse_error"))'           | grep -c . || true)

printf 'pi-apply: %s actionable, %s already-applied, %s stale, %s parse errors → %s\n' \
  "${N_ACT:-0}" "${N_APP:-0}" "${N_STA:-0}" "${N_ERR:-0}" "$REPORT_PATH"
```

Exit 0 on success regardless of classification counts.

## Rules

<!-- FR-010: propose-don't-apply discipline. Same as /kiln:kiln-claude-audit and /kiln:kiln-hygiene. -->

- The skill ONLY writes to `.kiln/logs/pi-apply-<timestamp>.md` (and creates `.kiln/logs/` if absent). It MUST NOT call `Edit`, `Write`, `sed -i`, `perl -i`, or `git apply` against any file under `plugin-kiln/skills/` or `plugin-kiln/agents/`. The maintainer applies changes manually after reviewing the preview.
- **FR-010 discipline**: the report is the ONLY side-effect. A post-run audit asserting `git diff --stat plugin-kiln/skills plugin-kiln/agents` is empty must pass (that is the fixture at `plugin-kiln/tests/pi-apply-propose-only/` — T026).
- **FR-011 `pi-hash` stability**: same inputs → same hash. A second run within the same minute on the same backlog MUST emit byte-identical report bodies (everything after the `# PI-Apply Report — <timestamp>` header line). Tested by `plugin-kiln/tests/pi-apply-dedup-determinism/` — T025.
- **FR-012 status classification**: diff is rendered ONLY for records with `status: actionable`. Records with `status: already-applied` or `status: stale` appear in the report for audit but carry no diff body.
- **NFR-002 performance**: the pipeline must complete within 60 seconds for ≤ 20 open retro issues. The `gh` call is a single list query (no N+1), and every helper is a thin shell step.
- **NFR-005 back-compat**: pre-existing distilled PRDs with raw-issue `derived_from:` entries are NOT touched by this skill. The skill only reads GitHub retro issues and writes `.kiln/logs/`.
- **Edge case — empty retro backlog**: when `gh` returns zero open retro issues (or the stub's JSON is `[]`), the report still emits with schema-stable empty sections ("(none)" under each heading) and a "No open retro issues found." body.
- **Edge case — malformed PI block**: a block missing File / Current / Proposed / Why surfaces as a `parse_error` record in the "Parse Errors" section with the line range and issue URL. Other blocks in the same issue continue to parse — no all-or-nothing failure.
- **Edge case — `gh` failure**: fetch exits 3 with the underlying gh error on stderr. The skill aborts without writing a report. This is correct — a silently empty report would hide a connectivity regression.
