# Research: Shelf Skills Polish

## Decision 1: Workflow step design for shelf-create

**Decision**: Use 8 steps — 4 command steps for data gathering, then 3 agent steps for MCP operations, plus 1 final command step for `.shelf-config` output. The `resolve-vault-path` and `check-duplicate` steps are agent steps because they require MCP calls.

**Rationale**: Follows the established command-first/agent-second pattern from `shelf-full-sync`. Command steps are deterministic and cheap. Agent steps handle the MCP judgment calls. The `write-shelf-config` step is a command because it writes to the local filesystem (not Obsidian).

**Alternatives considered**:
- Fewer agent steps by combining resolve + check + create into one: rejected because it would lose the observability benefit of separate outputs per step.
- All agent steps: rejected because data gathering doesn't need MCP and would waste tokens.

## Decision 2: shelf-repair diff/preview approach

**Decision**: The `generate-diff-report` agent step reads the current dashboard and the template, identifies structural differences (missing sections, non-canonical status, format drift), and writes a change report to `.wheel/outputs/shelf-repair-diff.md`. The subsequent `apply-repairs` step reads this report and applies changes.

**Rationale**: Separating preview from application gives users an audit trail of what changed. The diff report persists in `.wheel/outputs/` for review.

**Alternatives considered**:
- Single step that diffs and applies in one pass: rejected because no audit trail before changes.
- Interactive confirmation step: rejected because wheel workflows don't support interactive prompts mid-flow.

## Decision 3: Status label file format

**Decision**: Use a Markdown file (`status-labels.md`) with a simple table defining each status, its description, and mapping from common non-canonical equivalents.

**Rationale**: Markdown is readable by both humans and AI agents. A table format makes it easy for skills to reference. The mapping table handles normalization (e.g., "in-progress" -> "active").

**Alternatives considered**:
- JSON/YAML config: rejected because it's harder for skill authors to read inline.
- Embedding in each skill: rejected because it violates single-source-of-truth.

## Decision 4: shelf-full-sync summary implementation

**Decision**: Add a `command` type step (not agent) that uses `bash` + `grep`/`sed` to extract counts from the prior step output files and format them into a Markdown summary.

**Rationale**: The summary is deterministic text extraction — no judgment or MCP calls needed. A command step is cheaper and faster than spawning an agent.

**Alternatives considered**:
- Agent step: rejected because it would waste tokens on a task that's pure text parsing.
- Modifying the terminal step to also produce a summary: rejected because the terminal step (`push-progress-update`) already has a different responsibility.

## Decision 5: Vault root navigation approach

**Decision**: The `resolve-vault-path` agent step calls `mcp__obsidian-projects__list_files({ directory: "/" })` to get the vault root contents, then navigates to the configured `base_path`. If the path doesn't exist, it creates directories via `mcp__obsidian-projects__create_file` with placeholder files.

**Rationale**: Starting from vault root eliminates path guessing. The MCP `list_files` at "/" is the only reliable way to verify vault structure.

**Alternatives considered**:
- Direct `create_file` at the target path without verification: rejected because it wouldn't detect if the base_path structure already exists.
- `search_files` to find the base_path: rejected because search is slower and less precise than directory listing.
