# Quickstart: Trim Plugin

## Prerequisites

1. Claude Code installed and running
2. Penpot MCP server installed and connected to Claude Code
3. A Penpot project with at least one file/page
4. The wheel engine plugin (`plugin-wheel/`) installed

## Setup

### 1. Install the plugin

```bash
# From npm (when published)
claude plugins install @yoshisada/trim

# Or for local development
# The plugin is at plugin-trim/ in the repo
```

### 2. Configure Penpot connection

```bash
/trim-config
```

This prompts for your Penpot project ID and file ID, then writes `.trim-config` to your repo root.

### 3. Start syncing

**Design-first** (have a Penpot design, want code):
```bash
/trim-pull
```

**Code-first** (have code, want Penpot components):
```bash
/trim-push
```

**Check for drift**:
```bash
/trim-diff
```

**Manage component library**:
```bash
/trim-library        # List all tracked components
/trim-library sync   # Auto-sync drifted components
```

**Generate a design from a PRD**:
```bash
/trim-design
```

## Typical Workflow

1. `/trim-config` — Connect to your Penpot project (once per project)
2. Design in Penpot or code first
3. `/trim-pull` or `/trim-push` — Sync between design and code
4. Edit in either tool
5. `/trim-diff` — Check what's changed
6. `/trim-pull` or `/trim-push` — Sync changes back
7. `/trim-library` — Review overall sync status
