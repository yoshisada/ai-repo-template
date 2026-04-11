#!/usr/bin/env bash
# compute-work-list.sh
# Contract: specs/shelf-sync-efficiency/contracts/interfaces.md §5
#
# Pure deterministic diff: joins repo state with the Obsidian index
# emitted by obsidian-discover and produces a work list JSON consumed by
# obsidian-apply. No MCP, no LLM, no agent.
#
# Inputs (paths fixed by the wheel workflow):
#   .wheel/outputs/read-shelf-config.txt
#   .wheel/outputs/fetch-github-issues.txt
#   .wheel/outputs/read-backlog-issues.txt
#   .wheel/outputs/read-feature-prds.txt
#   .wheel/outputs/detect-tech-stack.txt
#   .wheel/outputs/gather-repo-state.txt
#   .wheel/outputs/obsidian-index.json
#
# Output:
#   .wheel/outputs/compute-work-list.json

set -euo pipefail

OUT=".wheel/outputs/compute-work-list.json"
mkdir -p .wheel/outputs

# ---------- shelf config ----------
cfg=".wheel/outputs/read-shelf-config.txt"
base_path=$(grep -E '^base_path[[:space:]]*=' "$cfg" 2>/dev/null | head -1 | sed -E 's/^base_path[[:space:]]*=[[:space:]]*//' | tr -d '"' | sed -E 's/[[:space:]]+$//' || true)
slug=$(grep -E '^slug[[:space:]]*=' "$cfg" 2>/dev/null | head -1 | sed -E 's/^slug[[:space:]]*=[[:space:]]*//' | tr -d '"' | sed -E 's/[[:space:]]+$//' || true)
base_path=${base_path:-projects}
slug=${slug:-unknown}

now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
today=$(date -u +"%Y-%m-%d")
yyyymm=$(date -u +"%Y-%m")

# ---------- obsidian index ----------
idx=".wheel/outputs/obsidian-index.json"
if [ ! -f "$idx" ]; then
  echo '{"project_exists": false, "issues": [], "docs": [], "dashboard": null}' > "$idx"
fi

project_exists=$(jq -r '.project_exists // false' "$idx")

if [ "$project_exists" != "true" ]; then
  jq -n \
    --arg base_path "$base_path" \
    --arg slug "$slug" \
    '{
      base_path: $base_path,
      slug: $slug,
      project_exists: false,
      issues: [], docs: [],
      dashboard: {needs_update: false},
      progress: {needs_update: false},
      counts: {
        issues: {create: 0, update: 0, close: 0, skip: 0},
        docs:   {create: 0, update: 0, skip: 0}
      }
    }' > "$OUT"
  exit 0
fi

# ---------- GitHub issues ----------
gh_file=".wheel/outputs/fetch-github-issues.txt"
if [ -f "$gh_file" ] && jq -e 'type == "array"' "$gh_file" >/dev/null 2>&1; then
  gh_issues=$(cat "$gh_file")
else
  gh_issues="[]"
fi

# ---------- tech stack detection ----------
tech_file=".wheel/outputs/detect-tech-stack.txt"
tech_raw=""
[ -f "$tech_file" ] && tech_raw=$(cat "$tech_file")

detect_tags() {
  local content=$1
  local tags=()
  if grep -q 'tsconfig.json' <<< "$content"; then
    tags+=("language/typescript")
  elif grep -q 'package.json' <<< "$content"; then
    tags+=("language/javascript")
  fi
  grep -q 'Cargo.toml' <<< "$content" && tags+=("language/rust")
  grep -q -E 'pyproject.toml|requirements.txt' <<< "$content" && tags+=("language/python")
  grep -q 'go.mod' <<< "$content" && tags+=("language/go")
  grep -q 'Gemfile' <<< "$content" && tags+=("language/ruby")
  grep -q -E 'Dockerfile|docker-compose|compose.yml|compose.yaml' <<< "$content" && tags+=("infra/docker")
  grep -q 'infra/github-actions' <<< "$content" && tags+=("infra/github-actions")
  # framework detection from package.json deps listing
  grep -qw 'react' <<< "$content" && tags+=("framework/react")
  grep -qw 'next' <<< "$content" && tags+=("framework/next")
  grep -qw 'vue' <<< "$content" && tags+=("framework/vue")
  grep -qw 'express' <<< "$content" && tags+=("framework/express")
  grep -qw 'fastify' <<< "$content" && tags+=("framework/fastify")
  # emit sorted unique JSON array
  printf '%s\n' "${tags[@]}" | awk 'NF' | sort -u | jq -R . | jq -s .
}
detected_tags=$(detect_tags "$tech_raw")
[ -z "$detected_tags" ] && detected_tags="[]"

# ---------- current dashboard tags ----------
current_tags=$(jq '.dashboard.frontmatter.tags // []' "$idx")

# tag delta
tag_delta=$(jq -n \
  --argjson current "$current_tags" \
  --argjson detected "$detected_tags" \
  '{
    add:    ($detected - $current),
    remove: ($current - $detected),
    final:  $detected
  }')

# ---------- progress entry from gather-repo-state ----------
grs_file=".wheel/outputs/gather-repo-state.txt"
branch=""
recent_commits="[]"
if [ -f "$grs_file" ]; then
  branch=$(grep '^Branch:' "$grs_file" | head -1 | sed 's/^Branch:[[:space:]]*//')
  # Commits are listed under "Last 5 commits:" until "---"
  commit_block=$(awk '/^Last 5 commits:/{flag=1;next}/^---$/{flag=0}flag' "$grs_file" | head -5)
  recent_commits=$(echo "$commit_block" | jq -R . | jq -s 'map(select(length > 0))')
fi

task_progress_block=$(awk '/^Task progress:/{flag=1;next}/^VERSION:/{flag=0}flag' "$grs_file" 2>/dev/null || true)

progress_summary="Automated sync on $today from branch ${branch:-unknown}"
progress_outcomes=$(jq -n \
  --argjson commits "$recent_commits" \
  --arg tasks "$task_progress_block" \
  '
    ($commits | map("commit: " + .)) +
    (if ($tasks // "") != "" then [($tasks | split("\n") | map(select(length > 0)) | join(" | "))] else [] end)
  ')
progress_links=$(echo "$recent_commits" | jq '[.[] | capture("^(?<sha>[a-f0-9]+)") | "commit:" + .sha]' 2>/dev/null || echo '[]')

# ---------- compute issue work list ----------
# Index existing issue notes by filename_slug for quick lookup
existing_issues=$(jq '.issues // []' "$idx")

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//' | cut -c1-60
}

# Build issues actions using jq for deterministic rendering
issues_actions=$(jq -cn --argjson gh "$gh_issues" --argjson existing "$existing_issues" \
  --arg base_path "$base_path" --arg slug "$slug" --arg now "$now_iso" '
  def slugify:
    ascii_downcase
    | gsub("[^a-z0-9]"; "-")
    | gsub("-{2,}"; "-")
    | sub("^-"; "") | sub("-$"; "")
    | .[0:60];
  ($existing | map({key: .filename_slug, value: .}) | from_entries) as $by_slug |
  [
    $gh[] |
    (.title | slugify) as $fs |
    ("\($base_path)/\($slug)/issues/\($fs).md") as $path |
    ($by_slug[$fs] // null) as $prev |
    (
      if $prev == null then "create"
      elif ((.updatedAt // "1970-01-01T00:00:00Z") > ($prev.last_synced // "1970-01-01T00:00:00Z")) then "update"
      elif (.state == "closed" and ($prev.status // "open") != "closed") then "close"
      else "skip" end
    ) as $action |
    {
      action: $action,
      path: $path,
      filename_slug: $fs,
      frontmatter: (
        {
          type: "issue",
          status: (.state // "open"),
          severity: "medium",
          source: ("GitHub #" + (.number|tostring)),
          github_number: .number,
          project: ("[[" + $slug + "]]"),
          tags: [
            "source/github",
            "severity/medium",
            "type/improvement"
          ],
          last_synced: $now
        }
      ),
      title: (.title // ""),
      body: ("Synced from GitHub issue #" + (.number|tostring) + ".")
    } |
    if .action == "skip" or .action == "close" then del(.body) else . end
  ]
')

# ---------- compute doc work list ----------
prd_file=".wheel/outputs/read-feature-prds.txt"
existing_docs=$(jq '.docs // []' "$idx")

# parse "SLUG=... TITLE=... FRs=N NFRs=N STATUS=... PATH=..." lines
prd_json="[]"
if [ -f "$prd_file" ] && ! grep -q '(no PRDs)' "$prd_file"; then
  prd_json=$(awk '
    /^SLUG=/ {
      slug=""; title=""; frs=0; nfrs=0; status=""; path=""
      n=split($0, parts, " ")
      for (i=1;i<=n;i++) {
        if (parts[i] ~ /^SLUG=/) slug=substr(parts[i],6)
        else if (parts[i] ~ /^TITLE=/) { title=substr(parts[i],7); j=i+1; while (j<=n && parts[j] !~ /^(FRs|NFRs|STATUS|PATH)=/) { title=title" "parts[j]; j++ } }
        else if (parts[i] ~ /^FRs=/) frs=substr(parts[i],5)+0
        else if (parts[i] ~ /^NFRs=/) nfrs=substr(parts[i],6)+0
        else if (parts[i] ~ /^STATUS=/) status=substr(parts[i],8)
        else if (parts[i] ~ /^PATH=/) path=substr(parts[i],6)
      }
      gsub(/"/, "\\\"", title)
      printf "{\"slug\":\"%s\",\"title\":\"%s\",\"frs\":%d,\"nfrs\":%d,\"status\":\"%s\",\"path\":\"%s\"}\n", slug, title, frs, nfrs, status, path
    }
  ' "$prd_file" | jq -s .)
fi

docs_actions=$(jq -cn --argjson prds "$prd_json" --argjson existing "$existing_docs" \
  --arg base_path "$base_path" --arg slug "$slug" --arg now "$now_iso" '
  ($existing | map({key: .filename_slug, value: .}) | from_entries) as $by_slug |
  [
    $prds[] |
    .slug as $fs |
    ("\($base_path)/\($slug)/docs/\($fs).md") as $path |
    ($by_slug[$fs] // null) as $prev |
    (if $prev == null then "create" else "update" end) as $action |
    {
      action: $action,
      path: $path,
      filename_slug: $fs,
      frontmatter: {
        type: "doc",
        title: .title,
        summary: .title,
        fr_count: .frs,
        nfr_count: .nfrs,
        status: (.status // "Draft"),
        project: ("[[" + $slug + "]]"),
        tags: ["doc/prd"],
        prd_path: .path,
        last_synced: $now
      },
      title: .title,
      body: ("## Requirements\n- Functional: " + (.frs|tostring) + " FRs\n- Non-functional: " + (.nfrs|tostring) + " NFRs\n\n## Source\n[View PRD](" + .path + ")")
    }
  ]
')

# ---------- counts ----------
issue_counts=$(echo "$issues_actions" | jq '{
  create: [.[] | select(.action=="create")] | length,
  update: [.[] | select(.action=="update")] | length,
  close:  [.[] | select(.action=="close")]  | length,
  skip:   [.[] | select(.action=="skip")]   | length
}')
doc_counts=$(echo "$docs_actions" | jq '{
  create: [.[] | select(.action=="create")] | length,
  update: [.[] | select(.action=="update")] | length,
  skip:   [.[] | select(.action=="skip")]   | length
}')

# ---------- dashboard needs_update ----------
tags_changed=$(echo "$tag_delta" | jq '(.add | length) > 0 or (.remove | length) > 0')

dashboard_block=$(jq -n \
  --arg path "$base_path/$slug/$slug.md" \
  --argjson tags_changed "$tags_changed" \
  --argjson final_tags "$(echo "$tag_delta" | jq .final)" \
  --arg today "$today" \
  --arg branch "$branch" \
  '{
    needs_update: true,
    path: $path,
    frontmatter_patch: {
      tags: $final_tags,
      status: "in-progress",
      next_step: ("Continue work on " + (if $branch == "" then "main" else $branch end)),
      last_updated: $today
    },
    preserve_sections: ["About", "Human Needed", "Feedback", "Feedback Log"]
  }')

# ---------- progress block ----------
progress_block=$(jq -n \
  --arg path "$base_path/$slug/progress/$yyyymm.md" \
  --arg date "$today" \
  --arg summary "$progress_summary" \
  --argjson outcomes "$progress_outcomes" \
  --argjson links "$progress_links" \
  '{
    needs_update: true,
    path: $path,
    create_if_missing: true,
    append_entry: {
      date: $date,
      summary: $summary,
      outcomes: $outcomes,
      links: $links
    }
  }')

# ---------- assemble ----------
jq -n \
  --arg base_path "$base_path" \
  --arg slug "$slug" \
  --argjson issues "$issues_actions" \
  --argjson docs "$docs_actions" \
  --argjson dashboard "$dashboard_block" \
  --argjson progress "$progress_block" \
  --argjson issue_counts "$issue_counts" \
  --argjson doc_counts "$doc_counts" \
  '{
    base_path: $base_path,
    slug: $slug,
    project_exists: true,
    issues: $issues,
    docs: $docs,
    dashboard: $dashboard,
    progress: $progress,
    counts: {issues: $issue_counts, docs: $doc_counts}
  }' > "$OUT"

echo "compute-work-list.json written: $(jq -c '.counts' "$OUT")"
