#!/usr/bin/env bash
# lock.sh — Filesystem-based atomic locking for parallel fan-in
# FR-010: mkdir-based atomic locking

# FR-010: Attempt to acquire a lock (mkdir-based)
# Params: $1 = lock directory base path (.wheel/.locks), $2 = lock name (e.g., "step-3-fanin")
# Output: none
# Exit: 0 if lock acquired (we are the winner), 1 if lock already held (someone else won)
lock_acquire() {
  local lock_base="$1"
  local lock_name="$2"
  local lock_dir="${lock_base}/${lock_name}"
  mkdir -p "$lock_base" 2>/dev/null
  # mkdir is atomic — only one process can create the directory
  if mkdir "$lock_dir" 2>/dev/null; then
    return 0
  else
    return 1
  fi
}

# FR-010: Release a lock (rmdir)
# Params: $1 = lock directory base path, $2 = lock name
# Output: none
# Exit: 0 on success, 1 if lock didn't exist
lock_release() {
  local lock_base="$1"
  local lock_name="$2"
  local lock_dir="${lock_base}/${lock_name}"
  if [[ -d "$lock_dir" ]]; then
    rmdir "$lock_dir" 2>/dev/null
    return $?
  else
    return 1
  fi
}

# FR-010: Clean all locks (used on workflow start/reset)
# Params: $1 = lock directory base path
# Output: none
# Exit: 0
lock_clean_all() {
  local lock_base="$1"
  if [[ -d "$lock_base" ]]; then
    rm -rf "$lock_base"
  fi
  mkdir -p "$lock_base"
  return 0
}
