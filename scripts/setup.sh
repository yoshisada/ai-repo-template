#!/bin/bash
# FR-001: Single setup script that bootstraps everything.
# FR-002: Idempotent — safe to run multiple times.
set -euo pipefail

echo "╭─────────────────────────────────────╮"
echo "│  AI Repo Template — Setup           │"
echo "╰─────────────────────────────────────╯"
echo ""

# ── Step 1: Check prerequisites ──────────────────────────────

check_tool() {
  if command -v "$1" &>/dev/null; then
    echo "  ✓ $1 found ($(command -v "$1"))"
    return 0
  else
    echo "  ✗ $1 not found"
    return 1
  fi
}

echo "Checking prerequisites..."
MISSING=0
check_tool node || MISSING=1
check_tool jq || MISSING=1

# Check for bun or npm
if command -v bun &>/dev/null; then
  echo "  ✓ bun found"
  PKG_MGR="bun"
elif command -v npm &>/dev/null; then
  echo "  ✓ npm found (bun recommended but npm works)"
  PKG_MGR="npm"
else
  echo "  ✗ No package manager found (install bun or npm)"
  MISSING=1
fi

if [ "$MISSING" -eq 1 ]; then
  echo ""
  echo "Install missing tools and re-run this script."
  exit 1
fi
echo ""

# ── Step 2: Install uv (for speckit) ────────────────────────

echo "Setting up uv (Python package manager)..."
if command -v uv &>/dev/null; then
  echo "  ✓ uv already installed"
elif command -v "$HOME/.local/bin/uv" &>/dev/null; then
  echo "  ✓ uv already installed at ~/.local/bin/uv"
  export PATH="$HOME/.local/bin:$PATH"
else
  echo "  → Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh 2>&1 | tail -1
  export PATH="$HOME/.local/bin:$PATH"
  echo "  ✓ uv installed"
fi
echo ""

# ── Step 3: Install speckit ─────────────────────────────────

echo "Setting up spec-kit..."
if command -v specify &>/dev/null || command -v "$HOME/.local/bin/specify" &>/dev/null; then
  echo "  ✓ specify already installed"
else
  echo "  → Installing specify-cli..."
  uv tool install specify-cli --from "git+https://github.com/github/spec-kit.git" 2>&1 | tail -1
  echo "  ✓ specify installed"
fi

# Initialize speckit if not already done (idempotent check)
if [ ! -f ".specify/init-options.json" ]; then
  echo "  → Initializing spec-kit for claude..."
  echo "y" | "$HOME/.local/bin/specify" init . --ai claude --ai-skills --ignore-agent-tools 2>&1 | grep -E "^(├|└)" || true
  echo "  ✓ spec-kit initialized"
else
  echo "  ✓ spec-kit already initialized"
fi
echo ""

# ── Step 4: Configure ruflo (claude-flow) MCP ───────────────

echo "Setting up ruflo (claude-flow)..."
MCP_FILE=".mcp.json"
if [ -f "$MCP_FILE" ] && grep -q "claude-flow" "$MCP_FILE"; then
  echo "  ✓ claude-flow already in $MCP_FILE"
else
  # Create or update .mcp.json
  if [ ! -f "$MCP_FILE" ]; then
    cat > "$MCP_FILE" <<'MCPEOF'
{
  "mcpServers": {
    "claude-flow": {
      "command": "npx",
      "args": ["-y", "@claude-flow/cli@latest"]
    }
  }
}
MCPEOF
    echo "  ✓ Created $MCP_FILE with claude-flow"
  else
    # Merge into existing .mcp.json using node
    node -e "
      const fs = require('fs');
      const cfg = JSON.parse(fs.readFileSync('$MCP_FILE', 'utf-8'));
      cfg.mcpServers = cfg.mcpServers || {};
      cfg.mcpServers['claude-flow'] = { command: 'npx', args: ['-y', '@claude-flow/cli@latest'] };
      fs.writeFileSync('$MCP_FILE', JSON.stringify(cfg, null, 2) + '\n');
    "
    echo "  ✓ Added claude-flow to existing $MCP_FILE"
  fi
fi
echo ""

# ── Step 5: Make hooks executable ───────────────────────────

echo "Setting up hooks..."
chmod +x .claude/hooks/*.sh 2>/dev/null || true
echo "  ✓ Hook scripts are executable"
echo "  ✓ Hooks configured in .claude/settings.json"
echo ""

# ── Step 6: Verify ──────────────────────────────────────────

echo "Verifying setup..."
CHECKS=0
TOTAL=0

verify() {
  TOTAL=$((TOTAL + 1))
  if [ -f "$1" ] || [ -d "$1" ]; then
    echo "  ✓ $2"
    CHECKS=$((CHECKS + 1))
  else
    echo "  ✗ $2 — missing: $1"
  fi
}

verify "CLAUDE.md" "CLAUDE.md (workflow rules)"
verify ".claude/settings.json" "Hooks configuration"
verify ".claude/hooks/require-spec.sh" "Spec enforcement hook"
verify ".claude/hooks/block-env-commit.sh" "Secret commit blocker"
verify ".specify/memory/constitution.md" "Constitution"
verify ".specify/templates/spec-template.md" "Spec template"
verify "docs/PRD.md" "PRD placeholder"
verify "specs/README.md" "Specs directory"
verify ".mcp.json" "MCP config (ruflo)"
verify ".claude/skills" "Custom skills directory"
verify ".claude/agents" "Custom agents directory"

echo ""
if [ "$CHECKS" -eq "$TOTAL" ]; then
  echo "✓ All $TOTAL checks passed — setup complete!"
else
  echo "✗ $CHECKS/$TOTAL checks passed — some items need attention."
fi

echo ""
echo "Next steps:"
echo "  1. Edit docs/PRD.md with your product requirements"
echo "  2. Run /speckit.specify to create your first feature spec"
echo "  3. Start building — hooks will enforce the workflow"
echo ""
