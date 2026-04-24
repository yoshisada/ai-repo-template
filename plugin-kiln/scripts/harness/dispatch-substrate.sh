#!/usr/bin/env bash
# dispatch-substrate.sh — Single-case substrate dispatcher (v1: plugin-skill
#                        only). Extension point per plan.md "Substrate
#                        Abstraction" — to add a new substrate in a follow-on
#                        PRD, drop in a new substrate-<name>.sh script and
#                        add a case below.
#
# Satisfies: FR-002 (substrate tag) + plan.md substrate abstraction
# Contract:  contracts/interfaces.md §5
#
# Usage:
#   dispatch-substrate.sh <harness-type> <scratch-dir> <test-dir> <plugin-root>
#
# Drops the first arg (harness-type) and calls `substrate-<harness-type>.sh`
# with the remaining args (per the substrate-script calling convention).
set -euo pipefail

harness_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

if [[ $# -ne 4 ]]; then
  echo "dispatch-substrate.sh: expected 4 args (harness-type scratch-dir test-dir plugin-root), got $#" >&2
  exit 2
fi

harness_type=$1
scratch_dir=$2
test_dir=$3
plugin_root=$4

case $harness_type in
  plugin-skill)
    exec "$harness_dir/substrate-plugin-skill.sh" "$scratch_dir" "$test_dir" "$plugin_root"
    ;;
  *)
    echo "dispatch-substrate.sh: Substrate '$harness_type' not implemented in v1" >&2
    exit 2
    ;;
esac
