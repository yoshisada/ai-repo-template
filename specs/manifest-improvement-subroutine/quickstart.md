# Quickstart: Manifest Improvement Subroutine

**Phase**: 1 (Plan) | **Date**: 2026-04-16

A short recipe for a contributor to exercise the sub-workflow locally.

## Prereqs

- wheel plugin installed (`/wheel-init` run once per repo).
- shelf plugin installed.
- Obsidian MCP connected to a vault containing `@manifest/types/` and `@inbox/open/` (optional — test the silent-skip and MCP-unavailable paths without it).

## 1. Standalone skip run

Simulate a run where nothing should be proposed.

```bash
# Seed the reflect output as skip.
mkdir -p .wheel/outputs
echo '{"skip": true}' > .wheel/outputs/propose-manifest-improvement.json

# Run the sub-workflow via the skill wrapper.
# (In Claude Code: type /shelf:propose-manifest-improvement)
# Equivalent CLI:
/wheel-run shelf:propose-manifest-improvement

# Expected:
# - Exit status 0.
# - No file created in @inbox/open/.
# - .wheel/outputs/propose-manifest-improvement-dispatch.json == {"action":"skip"}
# - .wheel/outputs/propose-manifest-improvement-mcp.txt empty.
```

## 2. Standalone propose run (happy path)

Seed a reflect output that matches a real manifest file.

```bash
# Pick a manifest file and a line currently in it.
TARGET="@manifest/types/mistake.md"
CURRENT=$(sed -n '1p' "$VAULT_ROOT/manifest/types/mistake.md")   # first line

cat > .wheel/outputs/propose-manifest-improvement.json <<EOF
{
  "skip": false,
  "target": "$TARGET",
  "section": "top of file",
  "current": "$CURRENT",
  "proposed": "$CURRENT (with a trailing note)",
  "why": "Demo run produced .wheel/outputs/demo-evidence.txt showing the need for a trailing note."
}
EOF
touch .wheel/outputs/demo-evidence.txt

/wheel-run shelf:propose-manifest-improvement

# Expected:
# - A single new file in @inbox/open/ named 2026-04-16-manifest-improvement-<slug>.md
#   where <slug> derives from the `why` sentence.
# - Frontmatter: type: proposal, target: <TARGET>, date: 2026-04-16
# - Body: four H2 sections in order — ## Target, ## Current, ## Proposed, ## Why.
```

## 3. Standalone out-of-scope run (force-skip)

Target a path that is NOT under `@manifest/types/` or `@manifest/templates/`.

```bash
cat > .wheel/outputs/propose-manifest-improvement.json <<'EOF'
{
  "skip": false,
  "target": "plugin-shelf/skills/shelf-update/SKILL.md",
  "section": "## Purpose",
  "current": "some text",
  "proposed": "some better text",
  "why": "Demo evidence in .wheel/outputs/demo.txt."
}
EOF

/wheel-run shelf:propose-manifest-improvement

# Expected:
# - Exit status 0.
# - No file created in @inbox/open/ (target is out of scope per FR-4).
# - Dispatch envelope shows {"action":"skip"}.
```

## 4. Standalone hallucinated-current run (force-skip)

```bash
cat > .wheel/outputs/propose-manifest-improvement.json <<'EOF'
{
  "skip": false,
  "target": "@manifest/types/mistake.md",
  "section": "## Required frontmatter",
  "current": "text that definitely does not appear in the file",
  "proposed": "replacement",
  "why": "Seen in .wheel/outputs/demo.txt."
}
EOF

/wheel-run shelf:propose-manifest-improvement

# Expected:
# - Exit status 0.
# - No file created in @inbox/open/.
# - Dispatch envelope shows {"action":"skip"} because check-manifest-target-exists.sh
#   returned non-zero.
```

## 5. Caller-wired end-to-end — report-mistake-and-sync

```bash
# Trigger a mistake capture.
/kiln:mistake "Assumed the reflect output format was permissive; turns out FR-5 enforces verbatim match."

# The report-mistake-and-sync workflow runs:
#   check-existing-mistakes → create-mistake → propose-manifest-improvement → full-sync
#
# On a clean repo with a well-modeled manifest, propose-manifest-improvement will
# silently skip and the user sees normal mistake-capture output.
#
# If the AI agent in the reflect step notices a real manifest gap, a proposal
# file lands in @inbox/open/ during the final shelf-full-sync pass.
```

## 6. Caller-wired end-to-end — report-issue-and-sync

```bash
/kiln:report-issue "QA smoke tests take 3x longer on ARM runners than x86."

# Same pattern: check-existing-issues → create-issue → propose-manifest-improvement → full-sync.
# Typically silent-skip (the manifest doesn't track runner architecture, so no improvement target).
```

## 7. Caller-wired end-to-end — shelf-full-sync

```bash
/shelf:shelf-full-sync

# Pattern: ... → generate-sync-summary → propose-manifest-improvement → self-improve
# Note: per research.md R-007, a proposal written here is NOT synced by THIS run
# (obsidian-apply already ran earlier in the workflow). It will be synced by the
# NEXT full-sync call. This is intentional — one proposal per run, no extra sync.
```

## 8. Testing the MCP-unavailable graceful-degradation

```bash
# Disconnect Obsidian MCP (close Obsidian, or disable the MCP server).
# Seed a propose reflect output from step 2.
/wheel-run shelf:propose-manifest-improvement

# Expected:
# - Exit status 0.
# - .wheel/outputs/propose-manifest-improvement-mcp.txt contains exactly:
#     warn: obsidian MCP unavailable; manifest improvement proposal not persisted
# - No file in @inbox/open/.
# - Caller workflows (if you were in one) continue past this step normally.
```

## 9. Verifying portability

In a consumer repo that has the shelf plugin installed via cache (no `plugin-shelf/` directory in the repo):

```bash
# Confirm ${WORKFLOW_PLUGIN_DIR} resolves correctly.
# The workflow JSON must reference only ${WORKFLOW_PLUGIN_DIR}/scripts/... — never plugin-shelf/scripts/...
grep -E 'plugin-shelf/scripts/' "$(find ~/.claude/plugins/cache -name propose-manifest-improvement.json | head -1)" || echo "OK — portable"

# Then run:
/wheel-run shelf:propose-manifest-improvement

# Expected: no "No such file or directory" errors on command steps.
```

## 10. Unit-test locally

```bash
# From repo root:
bats tests/unit/derive-proposal-slug.bats
bats tests/unit/validate-reflect-output.bats
bats tests/unit/check-manifest-target-exists.bats

# Or integration:
bash tests/integration/silent-skip.sh
bash tests/integration/write-proposal.sh
bash tests/integration/caller-wiring.sh
```

## Troubleshooting

- **Proposal not written after a seemingly valid reflect output**: Check `.wheel/outputs/propose-manifest-improvement-dispatch.json`. If it is `{"action":"skip"}`, look at `validate-reflect-output.sh` exit conditions (missing field, out-of-scope target, `current` not verbatim, `why` not grounded).
- **`${WORKFLOW_PLUGIN_DIR}: unbound variable`**: Wheel is too old. Needs v1143+.
- **File written but not picked up by shelf-full-sync in same run**: Expected for runs of `shelf-full-sync` itself (see R-007). Two kiln callers DO pick it up same-run.
