#!/usr/bin/env bash
# Test: roadmap-promote-byte-preserve
#
# Validates: NFR-003 — promote-source.sh MUST preserve the source file's
# body (everything after the closing `---` of the frontmatter) byte-for-
# byte. Uses a body deliberately full of whitespace, Unicode, and trailing
# newlines to catch any reflow / normalization bug.
set -euo pipefail
LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PROMOTE="$REPO_ROOT/plugin-kiln/scripts/roadmap/promote-source.sh"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT; cd "$TMP"
mkdir -p .kiln/feedback

# Intentionally tricky body: tabs, leading/trailing whitespace, Unicode,
# blank lines, and a trailing newline.
cat > .kiln/feedback/2026-04-24-tricky-body.md <<'EOF'
---
id: 2026-04-24-tricky-body
title: "Tricky body"
status: open
---

# Feedback — edge cases ☁️

Line with trailing spaces:
Line with	embedded	tabs.

	Four-space-indented code-ish line.

---

Embedded horizontal rule above. Should NOT be treated as a second
frontmatter closer (awk scan stops at fm==2).

Final paragraph ending with no trailing newline after the period.
EOF

extract_body() {
  awk '/^---[[:space:]]*$/ { fm++; if (fm==2) { inbody=1; next } } inbody==1 { print }' "$1"
}

BEFORE=$(extract_body .kiln/feedback/2026-04-24-tricky-body.md | shasum -a 256 | awk '{print $1}')
BEFORE_BYTE_LEN=$(extract_body .kiln/feedback/2026-04-24-tricky-body.md | wc -c | tr -d ' ')

bash "$PROMOTE" \
  --source .kiln/feedback/2026-04-24-tricky-body.md \
  --kind feature \
  --blast-radius feature \
  --review-cost moderate \
  --context-cost "low" \
  --phase workflow-governance \
  --slug tricky-body >/dev/null

AFTER=$(extract_body .kiln/feedback/2026-04-24-tricky-body.md | shasum -a 256 | awk '{print $1}')
AFTER_BYTE_LEN=$(extract_body .kiln/feedback/2026-04-24-tricky-body.md | wc -c | tr -d ' ')

if [[ "$BEFORE" != "$AFTER" ]]; then
  echo "FAIL: body sha256 drifted — NFR-003 violated" >&2
  echo "  before: $BEFORE ($BEFORE_BYTE_LEN bytes)" >&2
  echo "  after:  $AFTER ($AFTER_BYTE_LEN bytes)" >&2
  exit 1
fi

echo "PASS: roadmap-promote-byte-preserve — body sha256 identical ($BEFORE, $BEFORE_BYTE_LEN bytes)"
