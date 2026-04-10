#!/usr/bin/env bash
# obsidian-snapshot-capture.sh
# Contract: specs/shelf-sync-efficiency/contracts/interfaces.md §8.1
#
# Walks the Obsidian vault subtree for a project and emits a deterministic
# JSON snapshot (sorted by path) of every markdown file: frontmatter with
# sorted keys (last_synced/last_updated normalized) + sha256 of the body
# with trailing whitespace trimmed from every line.
#
# Usage: obsidian-snapshot-capture.sh <base_path> <slug> <output_json>
#
# Vault location: $OBSIDIAN_VAULT_ROOT (required). The script scans
# "${OBSIDIAN_VAULT_ROOT}/${base_path}/${slug}/".
#
# Dependencies: bash 5.x, jq, shasum (or sha256sum), find, awk.

set -euo pipefail

if [ $# -ne 3 ]; then
  echo "Usage: $0 <base_path> <slug> <output_json>" >&2
  exit 2
fi

base_path=$1
slug=$2
output_json=$3

vault_root=${OBSIDIAN_VAULT_ROOT:-}
if [ -z "$vault_root" ]; then
  echo "OBSIDIAN_VAULT_ROOT not set — cannot locate vault on disk" >&2
  exit 2
fi

project_root="${vault_root%/}/${base_path}/${slug}"
if [ ! -d "$project_root" ]; then
  echo "Project directory not found: $project_root" >&2
  printf '[]\n' > "$output_json"
  exit 0
fi

if command -v sha256sum >/dev/null 2>&1; then
  sha_cmd=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  sha_cmd=(shasum -a 256)
else
  echo "Neither sha256sum nor shasum available" >&2
  exit 2
fi

hash_body() {
  awk '{ sub(/[[:space:]]+$/, ""); print }' "$1" | "${sha_cmd[@]}" | awk '{print $1}'
}

split_frontmatter() {
  local file=$1 tmp_fm=$2 tmp_body=$3
  awk -v fm="$tmp_fm" -v body="$tmp_body" '
    BEGIN { state = 0 }
    NR == 1 && /^---[[:space:]]*$/ { state = 1; next }
    state == 1 && /^---[[:space:]]*$/ { state = 2; next }
    state == 1 { print > fm; next }
    { print > body }
  ' "$file"
  [ -f "$tmp_fm" ] || : > "$tmp_fm"
  [ -f "$tmp_body" ] || : > "$tmp_body"
}

frontmatter_to_json() {
  local fm_file=$1
  python3 - "$fm_file" <<'PY'
import json, re, sys
path = sys.argv[1]
try:
    with open(path) as f:
        raw = f.read()
except FileNotFoundError:
    print("{}")
    sys.exit(0)

result = {}
current_key = None
current_list = None
for line in raw.splitlines():
    if not line.strip():
        continue
    if current_list is not None:
        m = re.match(r"\s+-\s+(.*)", line)
        if m:
            val = m.group(1).strip().strip('"').strip("'")
            current_list.append(val)
            continue
        else:
            result[current_key] = current_list
            current_list = None
            current_key = None
    m = re.match(r"^([A-Za-z0-9_\-]+):\s*(.*)$", line)
    if not m:
        continue
    key, val = m.group(1), m.group(2).strip()
    if val == "":
        current_key = key
        current_list = []
        continue
    if val.startswith('"') and val.endswith('"'):
        val = val[1:-1]
    elif val.startswith("'") and val.endswith("'"):
        val = val[1:-1]
    if key in ("last_synced", "last_updated"):
        val = "<timestamp>"
    result[key] = val
if current_list is not None and current_key is not None:
    result[current_key] = current_list

print(json.dumps(result, sort_keys=True))
PY
}

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

entries_file="$tmp_dir/entries.jsonl"
: > "$entries_file"

while IFS= read -r -d '' file; do
  rel_path=${file#"${vault_root%/}/"}
  fm_tmp="$tmp_dir/fm"
  body_tmp="$tmp_dir/body"
  : > "$fm_tmp"; : > "$body_tmp"
  split_frontmatter "$file" "$fm_tmp" "$body_tmp"
  fm_json=$(frontmatter_to_json "$fm_tmp")
  body_hash=$(hash_body "$body_tmp")
  jq -cn \
    --arg path "$rel_path" \
    --argjson frontmatter "$fm_json" \
    --arg body_sha256 "$body_hash" \
    '{path: $path, frontmatter: $frontmatter, body_sha256: $body_sha256}' \
    >> "$entries_file"
done < <(find "$project_root" -type f -name '*.md' -print0 | LC_ALL=C sort -z)

jq -s 'sort_by(.path)' "$entries_file" > "$output_json"
