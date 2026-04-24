#!/usr/bin/env bash
# fixture-seeder.sh — Recursively copy a test's fixtures/ dir into the scratch dir.
#
# Satisfies: FR-002 (fixture copy step)
# Contract:  contracts/interfaces.md §7.1
#
# Usage:
#   fixture-seeder.sh <test-dir> <scratch-dir>
#
# Args:
#   <test-dir>    absolute path to the test directory (contains fixtures/)
#   <scratch-dir> absolute path to an already-created empty scratch dir
#
# Stdout: nothing (silent on success)
# Stderr: diagnostics
# Exit:   0 on success (even if fixtures/ is absent — empty fixture is valid)
#         2 on copy error / missing scratch dir / bad args
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "fixture-seeder.sh: expected 2 args, got $# (usage: <test-dir> <scratch-dir>)" >&2
  exit 2
fi

test_dir=$1
scratch_dir=$2

if [[ ! -d $test_dir ]]; then
  echo "fixture-seeder.sh: test-dir does not exist: $test_dir" >&2
  exit 2
fi
if [[ ! -d $scratch_dir ]]; then
  echo "fixture-seeder.sh: scratch-dir does not exist: $scratch_dir" >&2
  exit 2
fi

fixtures="$test_dir/fixtures"

# contracts §7.1: "If `fixtures/` does not exist, exits 0 (empty fixture is valid)."
if [[ ! -d $fixtures ]]; then
  exit 0
fi

# Recursive copy preserving modes. `/.` + trailing slash on dest copies CONTENTS
# not the directory itself — what we want.
if ! cp -R "$fixtures"/. "$scratch_dir"/; then
  echo "fixture-seeder.sh: cp -R failed from $fixtures to $scratch_dir" >&2
  exit 2
fi

exit 0
