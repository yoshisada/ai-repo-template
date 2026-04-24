# Interface Contracts: Pipeline Input Completeness

These contracts are the **single source of truth** for the implementation. The implementer MUST match these literal strings, function signatures, and bash blocks verbatim. Any divergence is a contract bug — file an issue, do not silently rewrite.

## §1 — Step 4b bash pseudocode (replaces lines 590–631 of `plugin-kiln/skills/kiln-build-prd/SKILL.md`)

The Step 4b heading and surrounding prose stay; only the numbered bash blocks change. The replacement body:

```markdown
## Step 4b: Issue Lifecycle Completion (FR-007, FR-008)

After the audit-pr agent creates the PR, and before spawning the retrospective, the team lead completes the issue lifecycle for this build. Step 4b runs inline in the team lead's main-chat context (NOT a dedicated agent).

1. **Identify the PRD path and PR number** (set during pipeline orchestration):
   ```bash
   PRD_PATH="<the PRD path used for this build, e.g. docs/features/2026-04-23-pipeline-input-completeness/PRD.md>"
   PR_NUMBER="<the PR number from audit-pr, e.g. 145>"
   TODAY="$(date -u +%Y-%m-%d)"
   LOG_FILE=".kiln/logs/build-prd-step4b-${TODAY}.md"
   mkdir -p .kiln/logs
   ```

2. **Path normalization helper** (defined inline):
   ```bash
   # normalize_path <raw>: strip leading ./, trailing /, and surrounding whitespace.
   # Echoes empty string if the path is absolute (starts with /) or empty after stripping.
   normalize_path() {
     local raw="$1"
     # strip surrounding whitespace incl. CR
     raw="$(printf '%s' "$raw" | tr -d '\r' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
     # reject absolute
     case "$raw" in
       /*) printf '' ; return 0 ;;
     esac
     # strip leading ./
     raw="${raw#./}"
     # strip trailing /
     raw="${raw%/}"
     printf '%s' "$raw"
   }

   PRD_PATH_NORM="$(normalize_path "$PRD_PATH")"
   ```

3. **Scan for matching items across BOTH `.kiln/issues/` AND `.kiln/feedback/`**:
   ```bash
   SCANNED_ISSUES=0
   SCANNED_FEEDBACK=0
   MATCHED=0
   ARCHIVED=0
   SKIPPED=0
   MATCH_LIST=()  # absolute or repo-relative paths to archive

   for f in .kiln/issues/*.md .kiln/feedback/*.md; do
     [ -f "$f" ] || continue
     case "$f" in
       .kiln/issues/*)   SCANNED_ISSUES=$((SCANNED_ISSUES + 1)) ;;
       .kiln/feedback/*) SCANNED_FEEDBACK=$((SCANNED_FEEDBACK + 1)) ;;
     esac

     # Read raw status & prd lines (first occurrence each)
     status_raw="$(grep -m1 '^status:' "$f" | sed -E 's/^status:[[:space:]]*//' | tr -d '\r' | sed -E 's/[[:space:]]+$//')"
     prd_raw="$(grep -m1 '^prd:'    "$f" | sed -E 's/^prd:[[:space:]]*//'    | tr -d '\r' | sed -E 's/[[:space:]]+$//')"

     # Status must normalize to literal "prd-created"
     [ "$status_raw" = "prd-created" ] || continue

     # Normalize prd field; reject empty, absolute, or non-existent
     prd_norm="$(normalize_path "$prd_raw")"
     if [ -z "$prd_norm" ] || [ ! -f "$prd_norm" ]; then
       SKIPPED=$((SKIPPED + 1))
       continue
     fi

     if [ "$prd_norm" = "$PRD_PATH_NORM" ]; then
       MATCH_LIST+=("$f")
       MATCHED=$((MATCHED + 1))
     fi
   done
   ```

4. **Update + archive matched files** (preserves originating directory):
   ```bash
   for f in "${MATCH_LIST[@]}"; do
     orig_dir="$(dirname "$f")"          # .kiln/issues  or  .kiln/feedback
     base="$(basename "$f")"
     dest_dir="${orig_dir}/completed"
     mkdir -p "$dest_dir"

     # Rewrite frontmatter: replace status:, insert completed_date + pr after it.
     # Use a tempfile + mv for atomicity. Insert lines just below the status line.
     tmp="$(mktemp "${f}.XXXXXX")"
     awk -v today="$TODAY" -v pr="$PR_NUMBER" '
       BEGIN { inserted = 0 }
       /^status:[[:space:]]/ && !inserted {
         print "status: completed"
         print "completed_date: " today
         print "pr: #" pr
         inserted = 1
         next
       }
       { print }
     ' "$f" > "$tmp" && mv "$tmp" "$f"

     if mv "$f" "${dest_dir}/${base}"; then
       ARCHIVED=$((ARCHIVED + 1))
     else
       echo "WARN: failed to archive $f → ${dest_dir}/${base}" >&2
       SKIPPED=$((SKIPPED + 1))
     fi
   done
   ```

5. **Emit the diagnostic line (FR-003) — exactly once per run, exact format**:
   ```bash
   DIAG_LINE="step4b: scanned_issues=${SCANNED_ISSUES} scanned_feedback=${SCANNED_FEEDBACK} matched=${MATCHED} archived=${ARCHIVED} skipped=${SKIPPED} prd_path=${PRD_PATH_NORM}"
   echo "$DIAG_LINE"
   printf '%s\n' "$DIAG_LINE" >> "$LOG_FILE"
   ```

6. **Commit (FR-005)** — always commits the log; commits archived files iff any matched:
   ```bash
   git add "$LOG_FILE"
   if [ "$ARCHIVED" -gt 0 ]; then
     git add .kiln/issues/ .kiln/feedback/
     git commit -m "chore: step4b lifecycle — archived ${ARCHIVED} item(s) for ${PRD_PATH_NORM}"
   else
     git commit -m "chore: step4b lifecycle noop — ${PRD_PATH_NORM}"
   fi
   ```

If `git commit` reports "nothing to commit" (e.g., the log file was empty before this run and wrote a duplicate diagnostic), continue without erroring.
```

### §1 invariants

- The diagnostic line literal format MUST match the template exactly. No reordering of fields, no additional fields, no missing fields. The grep regex used to verify is in spec.md SC-002.
- The `mv` for archival MUST happen AFTER the in-place frontmatter rewrite, so the moved file already has the updated `status`/`completed_date`/`pr` lines.
- The `MATCH_LIST` accumulator pattern decouples the scan loop from the archive loop. Do NOT collapse them — this preserves the `scanned_*` totals from being affected by mid-loop `mv`.
- The `tr -d '\r'` is non-optional. Some `.shelf-config` and frontmatter files originate from CRLF environments.

## §2 — Diagnostic line literal template

```
step4b: scanned_issues=<N> scanned_feedback=<M> matched=<K> archived=<A> skipped=<S> prd_path=<PRD_PATH>
```

- `<N>`, `<M>`, `<K>`, `<A>`, `<S>` are non-negative decimal integers (use `0` when empty).
- `<PRD_PATH>` is the value of `$PRD_PATH_NORM` after normalization (relative path, no leading `./`, no trailing `/`).
- The line begins with the literal prefix `step4b: ` (six chars + colon + space). No leading whitespace.
- The line MUST be one line. No embedded newlines.

Verification regex (used in SC-002):
```
^step4b: scanned_issues=[0-9]+ scanned_feedback=[0-9]+ matched=[0-9]+ archived=[0-9]+ skipped=[0-9]+ prd_path=[^[:space:]]+$
```

## §3 — `.shelf-config` defensive parse routine

The `read-shelf-config` step in `plugin-shelf/workflows/shelf-write-issue-note.json` is replaced with a command that emits a structured, parser-friendly block. The parser mirrors `plugin-shelf/scripts/shelf-counter.sh`'s `_read_key()` pattern (see §3 of `specs/report-issue-speedup/contracts/interfaces.md`).

### Parser semantics

For each key `K` in `{slug, base_path, dashboard_path}`:

```bash
read_shelf_key() {
  local key="$1"
  [ -f .shelf-config ] || { printf ''; return 0; }
  grep -E "^${key}[[:space:]]*=" .shelf-config 2>/dev/null \
    | tail -1 \
    | sed -E "s/^${key}[[:space:]]*=[[:space:]]*//" \
    | sed -E 's/^"(.*)"$/\1/' \
    | sed -E "s/^'(.*)'\$/\\1/" \
    | tr -d ' \t\r'
}
```

- `tail -1` — last occurrence wins (matches `_read_key()`).
- The two `sed` quote-strip passes handle `key = "value"` and `key = 'value'`.
- The `tr -d ' \t\r'` strips trailing whitespace and CRLF. (Vault paths and slugs do not contain literal spaces — values that would are out of contract.)

### Step output format (what `read-shelf-config` writes to `.wheel/outputs/read-shelf-config.txt`)

```
## SHELF_CONFIG_PARSED
slug = <parsed slug or empty>
base_path = <parsed base_path or empty>
dashboard_path = <parsed dashboard_path or empty>
shelf_config_present = <true|false>
## END_SHELF_CONFIG_PARSED
```

If `.shelf-config` does not exist, all four lines are emitted with empty values (and `shelf_config_present = false`). The downstream `obsidian-write` agent reads this fixed-shape block; no ad-hoc parsing.

### Replacement command for the workflow JSON

```bash
bash -c '
read_shelf_key() {
  local key="$1"
  [ -f .shelf-config ] || { printf ""; return 0; }
  grep -E "^${key}[[:space:]]*=" .shelf-config 2>/dev/null \
    | tail -1 \
    | sed -E "s/^${key}[[:space:]]*=[[:space:]]*//" \
    | sed -E "s/^\\\"(.*)\\\"\$/\\1/" \
    | sed -E "s/^'\\''(.*)'\\''\$/\\1/" \
    | tr -d " \t\r"
}
present="false"; [ -f .shelf-config ] && present="true"
echo "## SHELF_CONFIG_PARSED"
echo "slug = $(read_shelf_key slug)"
echo "base_path = $(read_shelf_key base_path)"
echo "dashboard_path = $(read_shelf_key dashboard_path)"
echo "shelf_config_present = ${present}"
echo "## END_SHELF_CONFIG_PARSED"
'
```

The implementer MAY (and is encouraged to) move this into a small reusable script `${WORKFLOW_PLUGIN_DIR}/scripts/parse-shelf-config.sh` to keep the JSON readable. If extracted, the workflow command MUST use `bash "${WORKFLOW_PLUGIN_DIR}/scripts/parse-shelf-config.sh"` (per CLAUDE.md plugin-portability invariant — never `plugin-shelf/scripts/...`).

## §4 — `shelf-write-issue-note-result.json` schema (extended with `path_source`)

### Success result

```json
{
  "issue_file": "<the .kiln/issues path from context>",
  "obsidian_path": "<target path written>",
  "action": "created",
  "path_source": ".shelf-config (base_path + slug)",
  "errors": []
}
```

`action` ∈ `{"created", "patched"}`.
`path_source` ∈ `{".shelf-config (base_path + slug)", "discovery (shelf-config incomplete)"}` — these two literal strings ONLY. No variations, no embellishments.

### Error result (parse failure / all MCP calls fail)

```json
{
  "issue_file": "<path or empty>",
  "obsidian_path": "<target or empty>",
  "action": "failed",
  "path_source": "unknown",
  "errors": ["<short diagnostic>"]
}
```

### `finalize-result` fallback (extended)

When the agent's output JSON is missing or invalid, `finalize-result` writes:

```json
{
  "issue_file": "",
  "obsidian_path": "",
  "action": "failed",
  "path_source": "unknown",
  "errors": ["obsidian-write agent produced empty or invalid result JSON"]
}
```

### Decision rule for `path_source`

In the `obsidian-write` agent:

```
IF shelf_config_present == "true" AND slug != "" AND base_path != "":
  path_source = ".shelf-config (base_path + slug)"
  target_path = "${base_path}/${slug}/issues/${basename}"
ELSE:
  path_source = "discovery (shelf-config incomplete)"
  slug      = $(basename of git remote, .git stripped) ; fallback to "$(basename $(pwd))"
  base_path = "projects"
  target_path = "${base_path}/${slug}/issues/${basename}"
```

The `discovery` branch MUST NOT call `mcp__claude_ai_obsidian-projects__list_files`. Discovery here means "fall back to derived defaults" — NOT vault listing. (The agent's existing `MUST NOT call list_files` rule stays.)

## §5 — Fixture shapes (for SMOKE.md)

### §5.1 — Step 4b two-source fixture (SC-001)

```bash
# Setup
mkdir -p .kiln/issues .kiln/feedback docs/features/2026-04-23-fixture/
cat > docs/features/2026-04-23-fixture/PRD.md <<'PRDEOF'
# Fixture PRD
PRDEOF

cat > .kiln/issues/2026-04-23-fixture-issue.md <<'EOF'
---
status: prd-created
prd: docs/features/2026-04-23-fixture/PRD.md
---
fixture issue body
EOF

cat > .kiln/feedback/2026-04-23-fixture-feedback.md <<'EOF'
---
status: prd-created
prd: docs/features/2026-04-23-fixture/PRD.md
---
fixture feedback body
EOF

# Invocation (manual; in-pipeline this is automatic)
PRD_PATH="docs/features/2026-04-23-fixture/PRD.md"
PR_NUMBER="999"
# (paste Step 4b body from contracts/interfaces.md §1, steps 1–6)

# Assertion
test -f .kiln/issues/completed/2026-04-23-fixture-issue.md && \
test -f .kiln/feedback/completed/2026-04-23-fixture-feedback.md && \
grep -q '^status: completed' .kiln/issues/completed/2026-04-23-fixture-issue.md && \
grep -q '^status: completed' .kiln/feedback/completed/2026-04-23-fixture-feedback.md && \
echo OK || echo FAIL
```

### §5.2 — Step 4b path-normalization fixture (SC-003)

```bash
# Setup (extends §5.1 with leading ./ and trailing / on prd:)
cat > .kiln/issues/2026-04-23-fixture-leading-dot.md <<'EOF'
---
status: prd-created
prd: ./docs/features/2026-04-23-fixture/PRD.md
---
EOF

cat > .kiln/feedback/2026-04-23-fixture-trailing-slash.md <<'EOF'
---
status: prd-created
prd: docs/features/2026-04-23-fixture/PRD.md/
---
EOF

# Invocation: same Step 4b body, $PRD_PATH=docs/features/2026-04-23-fixture/PRD.md
# Assertion
test -f .kiln/issues/completed/2026-04-23-fixture-leading-dot.md && \
test -f .kiln/feedback/completed/2026-04-23-fixture-trailing-slash.md && \
echo OK || echo FAIL
```

### §5.3 — Step 4b zero-match diagnostic (SC-002)

```bash
# Setup: ensure .kiln/issues and .kiln/feedback exist but contain no matching items
mkdir -p .kiln/issues .kiln/feedback
PRD_PATH="docs/features/2026-04-23-NONEXISTENT/PRD.md"
PR_NUMBER="999"
# (paste Step 4b body)

# Assertion: diagnostic line appears in stdout AND in today's log file
TODAY="$(date -u +%Y-%m-%d)"
grep -E '^step4b: scanned_issues=[0-9]+ scanned_feedback=[0-9]+ matched=0 archived=0 skipped=[0-9]+ prd_path=' \
  ".kiln/logs/build-prd-step4b-${TODAY}.md" \
  && echo OK || echo FAIL
```

### §5.4 — `shelf-write-issue-note` shelf-config-present fixture (SC-004)

```bash
# Pre-condition: .shelf-config exists with non-empty base_path + slug (this repo's default state)
test -f .shelf-config || { echo "FAIL: prerequisite .shelf-config missing"; exit 1; }

# Create a synthetic backlog issue
mkdir -p .kiln/issues
cat > .kiln/issues/2026-04-23-smoke-write-issue-note.md <<'EOF'
---
title: smoke fixture for write-issue-note
type: improvement
severity: low
category: workflow
source: manual
status: open
date: 2026-04-23
---
## Description
fixture body
EOF

# Manually invoke the wheel sub-workflow (or run /kiln:kiln-report-issue if available)
# For automation: simulate via the existing kiln-report-issue path — the smoke tester
# will spawn it as a sub-agent.

# Assertion: result JSON records the .shelf-config path source AND zero list_files calls
RESULT=".wheel/outputs/shelf-write-issue-note-result.json"
test -s "$RESULT" || { echo "FAIL: missing $RESULT"; exit 1; }
SOURCE="$(jq -r '.path_source' "$RESULT")"
test "$SOURCE" = ".shelf-config (base_path + slug)" \
  && jq -e '.errors == []' "$RESULT" >/dev/null \
  && echo OK || echo FAIL
```

### §5.5 — `shelf-write-issue-note` discovery-fallback fixture (SC-005)

```bash
# Setup: temporarily hide .shelf-config
test -f .shelf-config && mv .shelf-config .shelf-config.bak
trap 'test -f .shelf-config.bak && mv .shelf-config.bak .shelf-config' EXIT

# Invoke the workflow (same as §5.4)
# ...

# Assertion: result records discovery + still succeeds
RESULT=".wheel/outputs/shelf-write-issue-note-result.json"
SOURCE="$(jq -r '.path_source' "$RESULT")"
test "$SOURCE" = "discovery (shelf-config incomplete)" \
  && jq -e '.errors == []' "$RESULT" >/dev/null \
  && echo OK || echo FAIL

# Cleanup happens via trap
```

### §5.6 — Idempotence check (SC-006)

```bash
# Run §5.1 setup + Step 4b body once. Then run Step 4b again with the same $PRD_PATH.
# Second run's diagnostic line should report matched=0 archived=0 (the items already moved).
TODAY="$(date -u +%Y-%m-%d)"
LOG=".kiln/logs/build-prd-step4b-${TODAY}.md"
LAST_LINE="$(tail -1 "$LOG")"
echo "$LAST_LINE" | grep -qE 'matched=0 archived=0' && echo OK || echo FAIL
```

## §6 — Cross-references

| Contract section | Spec FR | Success Criterion | Phase |
|---|---|---|---|
| §1 step 3 (scan loop) | FR-001 | SC-001 | A |
| §1 step 4 (archive logic) | FR-002 | SC-001 | A |
| §1 step 2 + step 3 normalize | FR-004 | SC-003 | B |
| §2 diagnostic literal | FR-003 | SC-002 | B |
| §1 step 5–6 + log append | FR-005 | SC-002, SC-006 | B |
| §3 parse routine | FR-006/FR-007 inputs | SC-004, SC-005 | C |
| §4 result JSON | FR-006, FR-007 | SC-004, SC-005 | C |
| §5 fixtures | (all) | SC-008 | E |
| (verification log) | NFR-002, NFR-004 | SC-005, SC-006, SC-007 | F |
