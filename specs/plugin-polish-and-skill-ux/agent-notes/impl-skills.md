# Agent Friction Notes: impl-skills

## What was confusing or unclear

- T013 called for updating a scaffold copy of the issue template, but no scaffold copy exists at `plugin-kiln/scaffold/`. The task should have been marked N/A in the task breakdown or the existence of the scaffold copy verified during planning.
- The task list assigned T015/T016 (Phase 9 cross-cutting) without specifying which agent owns them. They were completed by impl-packaging, but ownership should have been explicit.

## Where I got stuck

- No blockers encountered. All file paths in the plan matched actual files. The contracts were clear enough to implement directly.

## What could be improved

- The classify-files step uses a shell script for file classification. A more robust approach would use `jq` with a JSON intermediate format, but the shell approach is simpler and matches existing trim workflow patterns.
- The plan should verify file existence for scaffold/template copies before creating tasks that reference them (T013 was a no-op).
- Task ownership for shared phases (Phase 9) should be assigned upfront in the task breakdown.
