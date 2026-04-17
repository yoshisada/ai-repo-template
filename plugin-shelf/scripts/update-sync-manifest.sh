#!/usr/bin/env bash
# update-sync-manifest.sh
# Contract: specs/shelf-sync-efficiency/contracts/interfaces.md §7
#
# After obsidian-apply completes, updates .shelf-sync.json with new source
# hashes for all items that were created or updated. Ensures the next run
# can detect what has changed.
#
# Inputs:
#   .wheel/outputs/compute-work-list.json  — items + source_hash values
#   .wheel/outputs/obsidian-apply-results.json — success/failure status
#   .shelf-sync.json (or empty manifest on cold start)
#
# Output: .wheel/outputs/update-sync-manifest.txt (human-readable summary)

set -euo pipefail

OUT=".wheel/outputs/update-sync-manifest.txt"
MANIFEST=".shelf-sync.json"
WORK_LIST=".wheel/outputs/compute-work-list.json"
RESULTS=".wheel/outputs/obsidian-apply-results.json"
mkdir -p .wheel/outputs

now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Read existing manifest or start fresh
if [ -f "$MANIFEST" ] && jq . "$MANIFEST" > /dev/null 2>&1; then
  current_manifest=$(cat "$MANIFEST")
else
  current_manifest='{"version":"1.0","last_synced":null,"issues":[],"docs":[]}'
fi

# Read work list and results
work_list=$(cat "$WORK_LIST")
results=$(cat "$RESULTS")

# Collect error paths from results for skip-on-failure logic
error_paths=$(echo "$results" | jq -r '[.errors[]? | .path] | unique | .[]' 2>/dev/null || echo "")

# Build updated manifest using jq
updated_manifest=$(jq -n \
  --argjson current "$current_manifest" \
  --argjson work_list "$work_list" \
  --arg error_paths "$error_paths" \
  --arg now "$now_iso" \
  '
  # Parse error paths into an array for lookup
  ($error_paths | split("\n") | map(select(length > 0))) as $err_paths |

  # Process issues: merge work list results into current manifest
  ($current_manifest.issues // []) as $cur_issues |
  ($work_list.issues // []) as $wl_issues |

  # Index current issues by github_number
  ($cur_issues | map({key: (.github_number | tostring), value: .}) | from_entries) as $cur_by_num |

  # Apply work list changes
  (
    reduce ($wl_issues[] | select(.action != "skip")) as $item ($cur_by_num;
      if ($err_paths | index($item.path)) then .  # skip failed items
      elif $item.action == "create" then
        . + {($item.github_number | tostring): {
          github_number: $item.github_number,
          filename_slug: $item.filename_slug,
          path: $item.path,
          source_hash: $item.source_hash,
          last_synced: $now
        }}
      elif $item.action == "update" then
        . + {($item.github_number | tostring): (
          .[$item.github_number | tostring] // {} |
          . + {
            source_hash: $item.source_hash,
            last_synced: $now
          }
        )}
      elif $item.action == "close" then
        del(.[$item.github_number | tostring])
      else . end
    )
  ) as $updated_issues |

  # Process docs: merge work list results into current manifest
  ($current_manifest.docs // []) as $cur_docs |
  ($work_list.docs // []) as $wl_docs |

  # Index current docs by slug
  ($cur_docs | map({key: .slug, value: .}) | from_entries) as $cur_by_slug |

  # Apply work list changes
  (
    reduce ($wl_docs[] | select(.action != "skip")) as $item ($cur_by_slug;
      if ($err_paths | index($item.path)) then .  # skip failed items
      elif $item.action == "create" then
        . + {($item.slug): {
          slug: $item.slug,
          path: $item.path,
          source_hash: $item.source_hash,
          prd_path: $item.prd_path,
          last_synced: $now
        }}
      elif $item.action == "update" then
        . + {($item.slug): (
          .[$item.slug] // {} |
          . + {
            source_hash: $item.source_hash,
            last_synced: $now
          }
        )}
      else . end
    )
  ) as $updated_docs |

  # Update progress_paths: add the progress file path if newly created
  ($work_list.progress.path // null) as $prog_path |
  ($current_manifest.progress_paths // []) as $cur_prog_paths |
  (if $prog_path != null and ($cur_prog_paths | index($prog_path) == null)
   then $cur_prog_paths + [$prog_path]
   else $cur_prog_paths
   end) as $updated_prog_paths |

  # Process mistakes (Contract: specs/mistake-capture/contracts/interfaces.md §6):
  #   - upsert create/update rows with proposal_state: "open"
  #   - apply reconciliation (open → filed) from results.mistakes.reconciliation
  #   - skip items whose path is in errors
  ($current_manifest.mistakes // []) as $cur_mistakes |
  ($work_list.mistakes // []) as $wl_mistakes |
  ($results.mistakes.reconciliation // []) as $recon |

  # Index current mistakes by path
  ($cur_mistakes | map({key: .path, value: .}) | from_entries) as $cur_by_path |

  # Apply work list create/update
  (
    reduce ($wl_mistakes[] | select(.action != "skip")) as $item ($cur_by_path;
      if ($err_paths | index($item.path)) then .  # skip failed items
      elif $item.action == "create" then
        . + {($item.path): {
          path: $item.path,
          filename_slug: $item.filename_slug,
          date: $item.date,
          source_hash: $item.source_hash,
          proposal_path: $item.proposal_path,
          proposal_state: "open",
          last_synced: $now
        }}
      elif $item.action == "update" then
        . + {($item.path): (
          .[$item.path] // {
            path: $item.path,
            filename_slug: $item.filename_slug,
            date: $item.date,
            proposal_path: $item.proposal_path,
            proposal_state: "open"
          } |
          . + {
            source_hash: $item.source_hash,
            last_synced: $now
          }
        )}
      else . end
    )
  ) as $post_wl_mistakes |

  # Apply reconciliation: open → filed for paths the agent confirmed left @inbox/open/
  (
    reduce $recon[] as $r ($post_wl_mistakes;
      if .[$r.path] and $r.new_state == "filed" then
        . + {($r.path): (.[$r.path] | . + {proposal_state: "filed", last_synced: $now})}
      else . end
    )
  ) as $updated_mistakes |

  {
    version: ($current_manifest.version // "1.0"),
    last_synced: $now,
    issues: ($updated_issues | to_entries | map(.value)),
    docs: ($updated_docs | to_entries | map(.value)),
    mistakes: ($updated_mistakes | to_entries | map(.value)),
    progress_paths: $updated_prog_paths
  }
  ' \
  --argjson current_manifest "$current_manifest" \
  --argjson work_list "$work_list" \
  --argjson results "$results")

# Atomic write: write to temp, then mv
echo "$updated_manifest" | jq . > "${MANIFEST}.tmp"
mv "${MANIFEST}.tmp" "$MANIFEST"

# Count changes for summary
added=$(echo "$work_list" | jq '[(.issues[]?, .docs[]?, .mistakes[]?) | select(.action == "create")] | length')
updated_count=$(echo "$work_list" | jq '[(.issues[]?, .docs[]?, .mistakes[]?) | select(.action == "update")] | length')
removed=$(echo "$work_list" | jq '[(.issues[]?) | select(.action == "close")] | length')
skipped=$(echo "$work_list" | jq '[(.issues[]?, .docs[]?, .mistakes[]?) | select(.action == "skip")] | length')
errors=$(echo "$results" | jq '[.errors[]?] | length')
filed=$(echo "$results" | jq '[.mistakes.reconciliation[]? | select(.new_state == "filed")] | length')

cat > "$OUT" <<EOF
Sync manifest updated: $now_iso
  Added:     $added
  Updated:   $updated_count
  Removed:   $removed
  Unchanged: $skipped
  Filed:     $filed (mistake proposals moved out of @inbox/open/)
  Errors:    $errors (items left unchanged for retry)
EOF

cat "$OUT"
