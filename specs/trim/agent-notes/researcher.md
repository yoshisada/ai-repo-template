# Researcher Friction Notes — Trim

**Date**: 2026-04-09

## Findings

1. **Official Penpot MCP tool surface is deceptively small**: Only 5 tools, with `execute_code` doing all the heavy lifting. Documentation doesn't enumerate Plugin API methods well — had to piece together capabilities from multiple sources (DeepWiki, community forums, Smashing Magazine article). The actual type definitions are at `doc.plugins.penpot.app` but the site doesn't render well for scraping.

2. **Two fundamentally different MCP architectures**: The official MCP (plugin-based, `execute_code`) vs community servers (direct API, discrete tools) have completely different interaction patterns. Trim workflows need to be designed MCP-agnostic via agent steps, which adds complexity but is the right call.

3. **No modification timestamps in MCP**: Neither server exposes per-component modification timestamps. This affects FR-017 (last-modified-wins sync). The PRD's "Penpot modification timestamp" assumption doesn't hold — trim will need snapshot-based comparison instead.

4. **The zcube/penpot-mcp-server has the richest tool set (76+ tools)** but is third-party. The official MCP is sparser but more stable. Recommend documenting both as supported options.

## Time Spent

Research took most of the effort on web fetching and cross-referencing multiple sources to build a complete picture. The official docs are spread across help.penpot.app, deepwiki, GitHub READMEs, and community forums.
