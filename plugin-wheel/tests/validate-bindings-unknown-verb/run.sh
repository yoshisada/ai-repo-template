#!/usr/bin/env bash
# SC-4 fixture — validate-bindings.sh exits 4 on a manifest with an unknown verb.
# Substrate tier-2: invoke directly, assert exit code.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VALIDATOR="${REPO_ROOT}/plugin-wheel/scripts/agents/validate-bindings.sh"
[[ ! -x "$VALIDATOR" ]] && { echo "FAIL: validator not executable" >&2; exit 1; }

TMPDIR="$(mktemp -d -t validate-bindings.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

# Case A — manifest with unknown verb → exit 4 with diagnostic.
cat > "$TMPDIR/bad-manifest.json" <<'EOF'
{
  "name": "test-plugin",
  "agent_bindings": {
    "research-runner": {
      "verbs": {
        "verify_quality": "ok",
        "make_coffee": "should be rejected — not in closed namespace"
      }
    }
  }
}
EOF

set +e
"$VALIDATOR" "$TMPDIR/bad-manifest.json" >"$TMPDIR/stdout" 2>"$TMPDIR/stderr"
rc=$?
set -e

[[ $rc -eq 4 ]] || { echo "FAIL: bad manifest exit = $rc (want 4)" >&2; cat "$TMPDIR/stderr" >&2; exit 1; }
grep -qF "make_coffee" "$TMPDIR/stderr" || { echo "FAIL: stderr missing 'make_coffee' diagnostic" >&2; cat "$TMPDIR/stderr" >&2; exit 1; }
grep -qF "research-runner" "$TMPDIR/stderr" || { echo "FAIL: stderr missing agent name in diagnostic" >&2; exit 1; }
grep -qF "closed namespace" "$TMPDIR/stderr" || { echo "FAIL: stderr missing 'closed namespace' marker" >&2; exit 1; }

# Case B — manifest with all valid verbs → exit 0.
cat > "$TMPDIR/ok-manifest.json" <<'EOF'
{
  "name": "test-plugin",
  "agent_bindings": {
    "research-runner": {
      "verbs": {
        "verify_quality": "ok",
        "measure": "ok"
      }
    }
  }
}
EOF
"$VALIDATOR" "$TMPDIR/ok-manifest.json" || { echo "FAIL: valid manifest rejected" >&2; exit 1; }

# Case C — manifest without agent_bindings → exit 0 (no-op).
cat > "$TMPDIR/no-bindings.json" <<'EOF'
{ "name": "test-plugin" }
EOF
"$VALIDATOR" "$TMPDIR/no-bindings.json" || { echo "FAIL: manifest without agent_bindings rejected" >&2; exit 1; }

# Case D — malformed JSON → exit 1.
echo '{ this is not json' > "$TMPDIR/bad-json.json"
set +e
"$VALIDATOR" "$TMPDIR/bad-json.json" >/dev/null 2>"$TMPDIR/stderr"
rc=$?
set -e
[[ $rc -eq 1 ]] || { echo "FAIL: malformed JSON exit = $rc (want 1)" >&2; exit 1; }

# Case E — missing file → exit 1.
set +e
"$VALIDATOR" "$TMPDIR/does-not-exist.json" >/dev/null 2>"$TMPDIR/stderr"
rc=$?
set -e
[[ $rc -eq 1 ]] || { echo "FAIL: missing file exit = $rc (want 1)" >&2; exit 1; }

echo "PASS: validate-bindings-unknown-verb — exit 4 on bad verb, 0 on valid/empty, 1 on malformed/missing"
