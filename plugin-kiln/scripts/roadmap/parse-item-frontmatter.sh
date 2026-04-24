#!/usr/bin/env bash
# parse-item-frontmatter.sh — parse a roadmap item file's YAML frontmatter to JSON
#
# FR-007 / PRD FR-007: Item frontmatter required keys
# Contract: specs/structured-roadmap/contracts/interfaces.md §2.1
#
# Usage:   parse-item-frontmatter.sh <path-to-item.md>
# Output:  stdout = single-line JSON object of frontmatter (all keys preserved verbatim)
# Exit:    0 on success; 2 if file missing; 3 if frontmatter malformed

set -u

ITEM_PATH="${1:-}"

if [ -z "$ITEM_PATH" ]; then
  echo "usage: parse-item-frontmatter.sh <path-to-item.md>" >&2
  exit 2
fi

if [ ! -f "$ITEM_PATH" ]; then
  echo "parse-item-frontmatter: file not found: $ITEM_PATH" >&2
  exit 2
fi

# Extract the YAML frontmatter block: lines between the first pair of `---`.
# Use awk to walk the file in a single pass without relying on gawk-only features.
# Emit a JSON object using jq as the final shaper so string escaping is correct.
#
# Frontmatter grammar we accept (keep it narrow to match the schema in §1.3):
#   key: scalar            → { "key": "scalar" }
#   key: [a, b, c]         → { "key": ["a","b","c"] }
#   key: |                 → { "key": "<multi-line string joined with \n>" }
#     line1
#     line2
#   key:                   → { "key": ["a","b"] }
#     - a
#     - b
#
# Numbers are kept as strings — the schema has no numeric fields other than
# `order` on phases; downstream validators re-check types.

awk '
  BEGIN {
    in_fm = 0
    saw_open = 0
    current_key = ""
    mode = "scalar"   # scalar | block | list
    block_buf = ""
  }
  /^---[[:space:]]*$/ {
    if (saw_open == 0) { saw_open = 1; in_fm = 1; next }
    else if (in_fm == 1) { in_fm = 0; done = 1; flush(); exit 0 }
  }
  in_fm == 1 {
    # Continuation of a block scalar (key: |)
    if (mode == "block") {
      if (match($0, /^[[:space:]]{2,}/)) {
        line = $0
        sub(/^[[:space:]]{2,}/, "", line)
        if (block_buf == "") block_buf = line
        else                 block_buf = block_buf "\n" line
        next
      } else {
        # block ended — flush it as a scalar pair
        emit_scalar(current_key, block_buf)
        mode = "scalar"
        block_buf = ""
      }
    }
    # List continuation: `  - value` lines
    if (mode == "list") {
      if (match($0, /^[[:space:]]+-[[:space:]]+/)) {
        item = $0
        sub(/^[[:space:]]+-[[:space:]]+/, "", item)
        gsub(/^"|"$/, "", item)
        list_items[list_n++] = item
        next
      } else {
        emit_list(current_key)
        mode = "scalar"
      }
    }
    # Blank line in scalar mode — skip
    if ($0 ~ /^[[:space:]]*$/) next
    # Key: value
    if (match($0, /^[A-Za-z_][A-Za-z0-9_]*:/)) {
      colon = index($0, ":")
      key = substr($0, 1, colon - 1)
      val = substr($0, colon + 1)
      sub(/^[[:space:]]+/, "", val)
      sub(/[[:space:]]+$/, "", val)
      if (val == "|") {
        current_key = key
        mode = "block"
        block_buf = ""
        next
      }
      if (val == "") {
        current_key = key
        mode = "list"
        list_n = 0
        delete list_items
        next
      }
      # Inline list [a, b, c]
      if (match(val, /^\[.*\]$/)) {
        inner = substr(val, 2, length(val) - 2)
        split_items(inner, key)
        next
      }
      # Scalar — strip surrounding quotes
      gsub(/^"|"$/, "", val)
      gsub(/^'"'"'|'"'"'$/, "", val)
      emit_scalar(key, val)
      next
    }
  }
  END {
    if (done == 1) exit 0
    if (mode == "block" && current_key != "") emit_scalar(current_key, block_buf)
    if (mode == "list"  && current_key != "") emit_list(current_key)
    flush()
  }
  function emit_scalar(k, v) {
    pairs[pair_n++] = json_string(k) ":" json_string(v)
  }
  function emit_list(k,   i, acc) {
    acc = ""
    for (i = 0; i < list_n; i++) {
      if (i > 0) acc = acc ","
      acc = acc json_string(list_items[i])
    }
    pairs[pair_n++] = json_string(k) ":[" acc "]"
  }
  function split_items(s, k,   n, a, i, item, acc) {
    n = split(s, a, ",")
    acc = ""
    for (i = 1; i <= n; i++) {
      item = a[i]
      sub(/^[[:space:]]+/, "", item)
      sub(/[[:space:]]+$/, "", item)
      gsub(/^"|"$/, "", item)
      if (i > 1) acc = acc ","
      acc = acc json_string(item)
    }
    pairs[pair_n++] = json_string(k) ":[" acc "]"
  }
  function json_string(s,   r) {
    gsub(/\\/, "\\\\", s)
    gsub(/"/,  "\\\"", s)
    gsub(/\n/, "\\n",  s)
    gsub(/\r/, "\\r",  s)
    gsub(/\t/, "\\t",  s)
    return "\"" s "\""
  }
  function flush(   i, acc) {
    acc = ""
    for (i = 0; i < pair_n; i++) {
      if (i > 0) acc = acc ","
      acc = acc pairs[i]
    }
    print "{" acc "}"
  }
' "$ITEM_PATH"
