# Specifier Notes: v5 Manifest-Based Architecture

**Date**: 2026-04-16
**Agent**: specifier

## Design decisions

1. **`status` field is dual-classified**: For issues, `status` is programmatic (reflects GitHub open/closed, updated on every sync). For docs, `status` is inferred (reflects LLM reading of PRD, set on create only). This is the most nuanced part of the field classification and must be called out explicitly in the agent instructions.

2. **`source_data` included in work list for CREATE and UPDATE**: Even though UPDATE doesn't use `source_data` for inferred fields, it's included in the work list for UPDATE entries too. This is because issue UPDATE still needs `source_data.state` to update the programmatic `status` field. For docs UPDATE, `source_data` could technically be omitted, but keeping it uniform simplifies the compute-work-list script and the agent can simply ignore it for doc updates.

3. **No `project_exists` check in v5**: v4 had `obsidian-discover` check if the project dashboard exists and emit `project_exists: false` to short-circuit. v5 doesn't read the vault for diffing, so this check moves to the apply agent. If the agent tries to write and the project doesn't exist, it will create files (which is the correct behavior for cold start). The dashboard `needs_update` flag handles whether to attempt dashboard operations.

4. **Manifest doesn't track dashboard or progress**: The manifest only tracks issues and docs. Dashboard and progress updates are always computed fresh from repo state and always applied. This keeps the manifest simple and avoids staleness issues with dashboard state.

## Gaps / things to watch

- **Cold start on existing v3/v4 vaults**: The first v5 run will treat everything as CREATE since there's no manifest. This means it will try to `create_file` for items that already exist in the vault. The agent instructions should handle this gracefully — either by catching the "file exists" error and falling back to an UPDATE-style patch, or by having compute-work-list check for file existence. This needs to be resolved during implementation (T031).

- **Parity testing**: v5 redefines parity. v4 aimed for byte-identical snapshots vs v3. v5 can't achieve that because CREATE generates new inferred fields via LLM (non-deterministic) and UPDATE preserves existing ones. The parity test should verify: (a) UPDATE doesn't modify inferred fields, (b) CREATE generates reasonable inferred fields, (c) programmatic fields are correct. SC-003 language should be interpreted as "no regression" rather than "byte-identical."

- **`append_file` MCP tool**: The instructions mention this is coming soon. Progress handling in obsidian-apply is designed as an isolated block so upgrading to append_file is a one-line change. Worth a follow-up task when the tool ships.
