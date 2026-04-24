#!/usr/bin/env bash
# Roadmap backfill generator — executable methodology per BACKFILL-METHODOLOGY.md.
# Idempotent. Re-running overwrites generated item/phase files with the same content.
# See BACKFILL-METHODOLOGY.md for rationale and future-skill extraction notes.

set -euo pipefail

BACKFILL_DATE="2026-04-24"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

ITEMS_DIR=".kiln/roadmap/items"
PHASES_DIR=".kiln/roadmap/phases"
mkdir -p "$ITEMS_DIR" "$PHASES_DIR"

# Phase order (stable) + membership.
# Format: phase_slug|phase_title|status|item_id,item_id,...
PHASES=(
  "01-foundations|Foundations — kiln core|complete|2026-03-31-continuance-agent,2026-03-31-kiln-rebrand-and-qa,2026-04-01-analyze-issues,2026-04-01-kiln-polish,2026-04-01-pipeline-reliability,2026-04-01-pipeline-workflow-polish,2026-04-01-qa-tooling-templates"
  "02-wheel-engine|Wheel workflow engine|complete|2026-04-03-wheel,2026-04-04-kiln-wheel-polish,2026-04-04-wheel-skill-activation,2026-04-05-wheel-session-guard,2026-04-06-wheel-create-workflow,2026-04-06-wheel-per-agent-state,2026-04-07-wheel-workflow-composition,2026-04-09-wheel-team-primitives,2026-04-10-wheel-test-skill"
  "03-shelf-obsidian|Shelf / Obsidian integration|complete|2026-04-03-shelf,2026-04-03-shelf-config-artifact,2026-04-03-shelf-sync-v2,2026-04-08-shelf-skills-polish,2026-04-10-shelf-sync-efficiency"
  "04-plugin-clay|Clay / ideation plugin|complete|2026-04-07-clay-idea-entrypoint,2026-04-07-plugin-clay"
  "05-plugin-trim|Trim / design plugin|complete|2026-04-09-trim,2026-04-09-trim-design-lifecycle,2026-04-09-trim-penpot-layout,2026-04-09-trim-push-v2"
  "06-developer-ergonomics|Developer ergonomics + cross-plugin polish|complete|2026-04-07-developer-tooling-polish,2026-04-09-plugin-polish-and-skill-ux,2026-04-16-manifest-improvement-subroutine,2026-04-16-mistake-capture,2026-04-20-fix-skill-with-recording-teams,2026-04-21-first-class-skill-prefixes,2026-04-21-plugin-naming-consistency"
  "07-feedback-loop|Feedback-loop observability + self-maintenance|complete|2026-04-22-kiln-capture-fix-polish,2026-04-22-report-issue-speedup,2026-04-23-kiln-self-maintenance,2026-04-23-kiln-structural-hygiene,2026-04-23-pipeline-input-completeness,2026-04-23-structured-roadmap,2026-04-24-plugin-skill-test-harness,2026-04-24-prd-derived-from-frontmatter"
  "08-in-flight|Current frontier — PRDs in progress|in-progress|2026-04-23-wheel-user-input,2026-04-24-claude-md-audit-reframe"
)

# Items whose state is NOT `shipped` (because they're in-progress — PRD only).
IN_PROGRESS_ITEMS="2026-04-23-wheel-user-input 2026-04-24-claude-md-audit-reframe"
is_in_progress() {
  local id="$1"
  for ip in $IN_PROGRESS_ITEMS; do
    [[ "$id" == "$ip" ]] && return 0
  done
  return 1
}

# Infer blast_radius from slug keywords — coarse, override by hand after.
infer_blast_radius() {
  local slug="$1"
  case "$slug" in
    *wheel*|*pipeline*|*hook*|*infra*|*plugin-polish*|*naming-consistency*|*skill-prefixes*)
      echo "cross-cutting" ;;
    *reliability*|*session-guard*|*team-primitives*)
      echo "infra" ;;
    *)
      echo "feature" ;;
  esac
}

# Humanize slug → title.
humanize_slug() {
  local slug="$1"
  # Strip date prefix, replace hyphens with spaces, capitalize first letter.
  local core
  core=$(echo "$slug" | sed 's/^[0-9-]*//' | tr '-' ' ')
  echo "$(tr '[:lower:]' '[:upper:]' <<< "${core:0:1}")${core:1}"
}

# Generate one item file.
write_item() {
  local id="$1" phase="$2"
  local date="${id%%-[a-z]*}"          # everything up to first letter-after-digits
  date="${id:0:10}"                    # simpler: first 10 chars YYYY-MM-DD
  local slug="${id:11}"
  local title
  title=$(humanize_slug "$id")
  local status state br
  if is_in_progress "$id"; then
    status="in-progress"
    state="distilled"
  else
    status="shipped"
    state="shipped"
  fi
  br=$(infer_blast_radius "$slug")

  local out="$ITEMS_DIR/$id.md"
  cat > "$out" <<EOF
---
id: $id
title: $title
kind: feature
date: $date
status: $status
state: $state
phase: $phase
blast_radius: $br
review_cost: moderate
context_cost: "1-3 sessions"
source: backfill
prd: docs/features/$id/PRD.md
---

Backfilled from \`docs/features/$id/\` on $BACKFILL_DATE.
EOF
}

# Generate phase files + item files.
order=0
for entry in "${PHASES[@]}"; do
  IFS='|' read -r phase_slug phase_title phase_status item_csv <<< "$entry"
  order=$((order + 1))

  # Compute earliest/latest dates from item IDs in this phase.
  IFS=',' read -r -a items <<< "$item_csv"
  earliest="${items[0]:0:10}"
  latest="${items[-1]:0:10}"

  # Write phase file.
  phase_file="$PHASES_DIR/$phase_slug.md"
  {
    echo "---"
    echo "name: $phase_slug"
    echo "title: $phase_title"
    echo "status: $phase_status"
    echo "order: $order"
    echo "started: $earliest"
    if [[ "$phase_status" == "complete" ]]; then
      echo "completed: $latest"
    fi
    echo "source: backfill"
    echo "---"
    echo ""
    echo "$phase_title"
    echo ""
    echo "Items:"
    for id in "${items[@]}"; do
      echo "- $id"
    done
  } > "$phase_file"

  # Write item files in this phase.
  for id in "${items[@]}"; do
    write_item "$id" "$phase_slug"
  done
done

echo "Generated $(ls "$PHASES_DIR" | wc -l | tr -d ' ') phase files."
echo "Generated $(ls "$ITEMS_DIR" | wc -l | tr -d ' ') item files."
