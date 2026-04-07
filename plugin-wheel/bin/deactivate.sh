#!/usr/bin/env bash
# deactivate.sh — No-op deactivation script for wheel workflows
# This script intentionally does nothing. Its execution is intercepted by
# the PostToolUse hook (post-tool-use.sh), which uses the hook input's
# session_id and agent_id to archive only the caller's own state file.
#
# Usage: deactivate.sh              — stop caller's own workflow
#        deactivate.sh --all        — stop all workflows
#        deactivate.sh <target>     — stop workflows matching target
#
# Called by /wheel-stop. The PostToolUse hook extracts the argument from
# tool_input.command to determine which state files to archive.
exit 0
