#!/usr/bin/env bash
# activate.sh — No-op activation script for wheel workflows
# This script intentionally does nothing. Its execution is intercepted by
# the PostToolUse hook (post-tool-use.sh), which uses the hook input's
# session_id and agent_id to create a properly-owned state file.
#
# Usage: activate.sh <workflow-name>
# Called by /wheel:run after validation. The workflow name is passed as $1
# so the hook can extract it from tool_input.command.
exit 0
