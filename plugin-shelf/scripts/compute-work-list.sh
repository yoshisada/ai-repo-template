#!/usr/bin/env bash
# compute-work-list.sh
# Contract: specs/shelf-sync-efficiency/contracts/interfaces.md §5
#
# Pure deterministic diff: joins repo state with the sync manifest
# and computes which notes need to be created, updated, or skipped.
# Also computes the dashboard tag delta and the progress entry.
# No MCP, no LLM, no agent.
#
# Inputs (paths fixed by the wheel workflow):
#   .wheel/outputs/read-shelf-config.txt
#   .wheel/outputs/fetch-github-issues.txt
#   .wheel/outputs/read-backlog-issues.txt
#   .wheel/outputs/read-feature-prds.txt
#   .wheel/outputs/detect-tech-stack.txt
#   .wheel/outputs/gather-repo-state.txt
#   .wheel/outputs/sync-manifest.json
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

# ---------- sync manifest ----------
manifest_file=".wheel/outputs/sync-manifest.json"
if [ ! -f "$manifest_file" ]; then
  echo '{"version":"1.0","last_synced":null,"issues":[],"docs":[]}' > "$manifest_file"
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
  grep -qw 'react' <<< "$content" && tags+=("framework/react")
  grep -qw 'next' <<< "$content" && tags+=("framework/next")
  grep -qw 'vue' <<< "$content" && tags+=("framework/vue")
  grep -qw 'express' <<< "$content" && tags+=("framework/express")
  grep -qw 'fastify' <<< "$content" && tags+=("framework/fastify")
  printf '%s\n' "${tags[@]}" | awk 'NF' | sort -u | jq -R . | jq -s .
}
detected_tags=$(detect_tags "$tech_raw")
[ -z "$detected_tags" ] && detected_tags="[]"

# ---------- progress entry from gather-repo-state ----------
grs_file=".wheel/outputs/gather-repo-state.txt"
branch=""
recent_commits="[]"
if [ -f "$grs_file" ]; then
  branch=$(grep '^Branch:' "$grs_file" | head -1 | sed 's/^Branch:[[:space:]]*//')
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

# ---------- compute issue work list with hash-based diff ----------
# Read manifest issues indexed by github_number
manifest_json=$(cat "$manifest_file")

issues_actions=$(jq -cn \
  --argjson gh "$gh_issues" \
  --argjson manifest "$manifest_json" \
  --arg base_path "$base_path" \
  --arg slug "$slug" \
  --arg now "$now_iso" \
  '
  def slugify:
    ascii_downcase
    | gsub("[^a-z0-9]"; "-")
    | gsub("-{2,}"; "-")
    | sub("^-"; "") | sub("-$"; "")
    | .[0:60];

  # Index manifest issues by github_number
  ($manifest.issues // [] | map({key: (.github_number | tostring), value: .}) | from_entries) as $manifest_by_num |

  # Track which manifest issues are seen (for close detection)
  ($manifest.issues // [] | map(.github_number)) as $manifest_nums |
  ($gh | map(.number)) as $gh_nums |

  # Process GitHub issues
  [
    $gh[] |
    (.title | slugify) as $fs |
    ("\($base_path)/\($slug)/issues/\($fs).md") as $path |
    (.number | tostring) as $num_str |

    # Compute source_hash: sha256 of {"number": N, "updatedAt": "..."}
    ({"number": .number, "updatedAt": (.updatedAt // "1970-01-01T00:00:00Z")} | tojson) as $hash_input |
    ("sha256:" + ($hash_input | @base64)) as $source_hash |

    ($manifest_by_num[$num_str] // null) as $prev |

    (
      if $prev == null then "create"
      elif $source_hash != ($prev.source_hash // "") then "update"
      else "skip" end
    ) as $action |

    {
      action: $action,
      path: $path,
      filename_slug: $fs,
      github_number: .number,
      source_hash: $source_hash,
      source_data: {
        title: (.title // ""),
        body: (.body // ""),
        state: (.state // "open"),
        labels: ([.labels[]? | .name] // []),
        created_at: (.createdAt // ""),
        updated_at: (.updatedAt // "")
      }
    }
  ] +
  # Detect closed: manifest issues not in current GitHub list
  [
    $manifest_nums[] |
    tostring as $num_str |
    select([$gh_nums[] | tostring] | index($num_str) | not) |
    $manifest_by_num[$num_str] |
    {
      action: "close",
      path: .path,
      filename_slug: .filename_slug,
      github_number: .github_number,
      source_hash: (.source_hash // ""),
      source_data: {}
    }
  ]
')

# ---------- compute doc work list with hash-based diff ----------
prd_file=".wheel/outputs/read-feature-prds.txt"

# Build PRD entries with file content for hashing
prd_json="[]"
if [ -f "$prd_file" ] && ! grep -q '(no PRDs)' "$prd_file"; then
  # Parse PRD listing lines into JSON with content
  prd_entries=""
  while IFS= read -r line; do
    [[ "$line" =~ ^SLUG= ]] || continue
    prd_slug=$(echo "$line" | sed -E 's/.*SLUG=([^ ]+).*/\1/')
    prd_title=$(echo "$line" | sed -E 's/.*TITLE=([^ ]+( [^[:upper:]][^ ]*)*).*/\1/' | head -c 200)
    prd_path=$(echo "$line" | sed -E 's/.*PATH=([^ ]+).*/\1/')
    prd_status=$(echo "$line" | sed -E 's/.*STATUS=([^ ]*).*/\1/')
    prd_frs=$(echo "$line" | sed -E 's/.*FRs=([0-9]+).*/\1/')
    prd_nfrs=$(echo "$line" | sed -E 's/.*NFRs=([0-9]+).*/\1/')

    # Read PRD file content for hash computation
    prd_content=""
    if [ -f "$prd_path" ]; then
      prd_content=$(cat "$prd_path")
    fi
    # Compute source_hash as sha256 of file content
    source_hash="sha256:$(echo -n "$prd_content" | shasum -a 256 | cut -d' ' -f1)"

    prd_entries="${prd_entries}$(jq -n \
      --arg slug "$prd_slug" \
      --arg title "$prd_title" \
      --arg path "$prd_path" \
      --arg status "$prd_status" \
      --arg frs "$prd_frs" \
      --arg nfrs "$prd_nfrs" \
      --arg source_hash "$source_hash" \
      --arg prd_content "$prd_content" \
      '{
        slug: $slug,
        title: $title,
        path: $path,
        status: $status,
        frs: ($frs | tonumber),
        nfrs: ($nfrs | tonumber),
        source_hash: $source_hash,
        prd_content: $prd_content
      }'
    )"$'\n'
  done < "$prd_file"

  if [ -n "$prd_entries" ]; then
    prd_json=$(echo "$prd_entries" | jq -s 'map(select(. != null))')
  fi
fi

docs_actions=$(jq -cn \
  --argjson prds "$prd_json" \
  --argjson manifest "$manifest_json" \
  --arg base_path "$base_path" \
  --arg slug "$slug" \
  --arg now "$now_iso" \
  '
  # Index manifest docs by slug
  ($manifest.docs // [] | map({key: .slug, value: .}) | from_entries) as $manifest_by_slug |

  [
    $prds[] |
    .slug as $fs |
    ("\($base_path)/\($slug)/docs/\($fs).md") as $path |
    ($manifest_by_slug[$fs] // null) as $prev |

    (
      if $prev == null then "create"
      elif .source_hash != ($prev.source_hash // "") then "update"
      else "skip" end
    ) as $action |

    {
      action: $action,
      path: $path,
      filename_slug: $fs,
      slug: $fs,
      source_hash: .source_hash,
      prd_path: .path,
      source_data: {
        prd_content: .prd_content
      }
    }
  ]
')

# ---------- compute mistake work list with hash-based diff ----------
# Contract: specs/mistake-capture/contracts/interfaces.md §4
# Discovers .kiln/mistakes/*.md, computes content hash per file, joins against
# the sync-manifest `mistakes[]` array (keyed by path), and emits per-entry
# action ∈ {create, update, skip}. A prior entry with proposal_state="filed"
# always produces skip regardless of hash change (FR-014).

mistakes_entries=""
if [ -d .kiln/mistakes ]; then
  shopt -s nullglob
  for mf in .kiln/mistakes/*.md; do
    [ -f "$mf" ] || continue
    m_basename=$(basename "$mf" .md)
    # Expect YYYY-MM-DD-<slug>. Extract date + slug defensively.
    m_date=""
    m_slug="$m_basename"
    if [[ "$m_basename" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})-(.+)$ ]]; then
      m_date="${BASH_REMATCH[1]}"
      m_slug="${BASH_REMATCH[2]}"
    fi

    m_content=$(cat "$mf")
    m_source_hash="sha256:$(echo -n "$m_content" | shasum -a 256 | cut -d' ' -f1)"

    # Parse frontmatter fields we need for source_data. Use awk to extract
    # between the two --- delimiters, then sed to pull individual keys.
    m_fm=$(awk '/^---$/{n++; next} n==1' "$mf" 2>/dev/null || true)
    m_body=$(awk '/^---$/{n++; next} n>=2' "$mf" 2>/dev/null || true)

    extract_fm() {
      local key=$1
      echo "$m_fm" | grep -E "^${key}:" | head -1 | sed -E "s/^${key}:[[:space:]]*//" | sed -E 's/^"(.*)"$/\1/'
    }

    m_title=$(echo "$m_body" | grep -E '^# ' | head -1 | sed -E 's/^#[[:space:]]*//')
    m_assumption=$(extract_fm assumption)
    m_correction=$(extract_fm correction)
    m_severity=$(extract_fm severity)
    m_status=$(extract_fm status)
    m_made_by=$(extract_fm made_by)
    m_fm_date=$(extract_fm date)
    [ -z "$m_date" ] && m_date="$m_fm_date"

    # tags may be inline list or YAML block list. Best-effort capture: take
    # everything under "tags:" until next top-level key. Then split on commas
    # or newlines + leading `-`.
    m_tags_raw=$(echo "$m_fm" | awk '
      /^tags:/ {flag=1; sub(/^tags:[[:space:]]*/, ""); if(length($0)>0) print; next}
      flag && /^[A-Za-z_][A-Za-z0-9_]*:/ {flag=0}
      flag {print}
    ')
    m_tags_json=$(echo "$m_tags_raw" | tr ',' '\n' | sed -E 's/^[[:space:]]*-?[[:space:]]*//; s/^\[//; s/\]$//; s/^"//; s/"$//' | awk 'NF' | jq -R . | jq -s .)
    [ -z "$m_tags_json" ] && m_tags_json="[]"

    m_proposal_path="@inbox/open/${m_date}-mistake-${m_slug}.md"

    # Look up manifest entry by path
    m_prev=$(jq -c --arg p "$mf" '(.mistakes // []) | map(select(.path == $p)) | .[0] // null' "$manifest_file")
    m_prev_state=$(echo "$m_prev" | jq -r '.proposal_state // empty')
    m_prev_hash=$(echo "$m_prev" | jq -r '.source_hash // empty')

    if [ "$m_prev_state" = "filed" ]; then
      m_action="skip"
    elif [ -z "$m_prev_hash" ]; then
      m_action="create"
    elif [ "$m_source_hash" != "$m_prev_hash" ]; then
      m_action="update"
    else
      m_action="skip"
    fi

    entry=$(jq -n \
      --arg action "$m_action" \
      --arg path "$mf" \
      --arg filename_slug "$m_slug" \
      --arg date "$m_date" \
      --arg source_hash "$m_source_hash" \
      --arg title "$m_title" \
      --arg assumption "$m_assumption" \
      --arg correction "$m_correction" \
      --arg severity "$m_severity" \
      --arg status "$m_status" \
      --argjson tags "$m_tags_json" \
      --arg made_by "$m_made_by" \
      --arg body "$m_body" \
      --arg proposal_path "$m_proposal_path" \
      '{
        action: $action,
        path: $path,
        filename_slug: $filename_slug,
        date: $date,
        source_hash: $source_hash,
        source_data: {
          title: $title,
          assumption: $assumption,
          correction: $correction,
          severity: $severity,
          status: $status,
          tags: $tags,
          made_by: $made_by,
          date: $date,
          body: $body
        },
        proposal_path: $proposal_path
      }')
    mistakes_entries="${mistakes_entries}${entry}"$'\n'
  done
fi

if [ -n "$mistakes_entries" ]; then
  mistakes_actions=$(echo "$mistakes_entries" | jq -s '.')
else
  mistakes_actions='[]'
fi

# Build mistakes_prior_state (proposal_state == "open" entries), for the
# obsidian-apply reconciliation (§5.3).
mistakes_prior_state=$(jq -c '[(.mistakes // [])[] | select(.proposal_state == "open") | {path, proposal_path, proposal_state}]' "$manifest_file")
[ -z "$mistakes_prior_state" ] && mistakes_prior_state='[]'

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
mistake_counts=$(echo "$mistakes_actions" | jq '{
  create: [.[] | select(.action=="create")] | length,
  update: [.[] | select(.action=="update")] | length,
  skip:   [.[] | select(.action=="skip")]   | length
}')

# ---------- dashboard ----------
# No vault reads needed — compute tag delta from detected vs config
tag_delta=$(jq -n \
  --argjson detected "$detected_tags" \
  '{
    add:    $detected,
    remove: [],
    final:  $detected
  }')

dashboard_block=$(jq -n \
  --arg path "$base_path/$slug/$slug.md" \
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

# ---------- progress ----------
progress_path="$base_path/$slug/progress/$yyyymm.md"
# Determine if progress file is new (not yet recorded in sync manifest)
known_progress_paths=$(jq -r '.progress_paths // [] | .[]' "$manifest_file" 2>/dev/null || true)
is_new_progress_file=true
while IFS= read -r known_path; do
  if [ "$known_path" = "$progress_path" ]; then
    is_new_progress_file=false
    break
  fi
done <<< "$known_progress_paths"

progress_block=$(jq -n \
  --arg path "$progress_path" \
  --arg date "$today" \
  --arg yyyymm "$yyyymm" \
  --arg slug "$slug" \
  --arg summary "$progress_summary" \
  --argjson outcomes "$progress_outcomes" \
  --argjson links "$progress_links" \
  --argjson is_new "$is_new_progress_file" \
  '{
    needs_update: true,
    path: $path,
    is_new_file: $is_new,
    yyyymm: $yyyymm,
    slug: $slug,
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
  --argjson mistakes "$mistakes_actions" \
  --argjson mistakes_prior_state "$mistakes_prior_state" \
  --argjson dashboard "$dashboard_block" \
  --argjson progress "$progress_block" \
  --argjson issue_counts "$issue_counts" \
  --argjson doc_counts "$doc_counts" \
  --argjson mistake_counts "$mistake_counts" \
  '{
    base_path: $base_path,
    slug: $slug,
    issues: $issues,
    docs: $docs,
    mistakes: $mistakes,
    mistakes_prior_state: $mistakes_prior_state,
    dashboard: $dashboard,
    progress: $progress,
    counts: {issues: $issue_counts, docs: $doc_counts, mistakes: $mistake_counts}
  }' > "$OUT"

echo "compute-work-list.json written: $(jq -c '.counts' "$OUT")"
