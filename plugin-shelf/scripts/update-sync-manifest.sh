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

  {
    version: ($current_manifest.version // "1.0"),
    last_synced: $now,
    issues: ($updated_issues | to_entries | map(.value)),
    docs: ($updated_docs | to_entries | map(.value))
  }
  ' \
  --argjson current_manifest "$current_manifest" \
  --argjson work_list "$work_list")

# Atomic write: write to temp, then mv
echo "$updated_manifest" | jq . > "${MANIFEST}.tmp"
mv "${MANIFEST}.tmp" "$MANIFEST"

# Count changes for summary
added=$(echo "$work_list" | jq '[(.issues[]?, .docs[]?) | select(.action == "create")] | length')
updated_count=$(echo "$work_list" | jq '[(.issues[]?, .docs[]?) | select(.action == "update")] | length')
removed=$(echo "$work_list" | jq '[(.issues[]?) | select(.action == "close")] | length')
skipped=$(echo "$work_list" | jq '[(.issues[]?, .docs[]?) | select(.action == "skip")] | length')
errors=$(echo "$results" | jq '[.errors[]?] | length')

cat > "$OUT" <<EOF
Sync manifest updated: $now_iso
  Added:     $added
  Updated:   $updated_count
  Removed:   $removed
  Unchanged: $skipped
  Errors:    $errors (items left unchanged for retry)
EOF

cat "$OUT"
