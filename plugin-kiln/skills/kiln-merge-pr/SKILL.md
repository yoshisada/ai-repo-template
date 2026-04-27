---
name: kiln-merge-pr
description: Merge a PR and atomically flip its derived_from roadmap items in one operation. Wraps `gh pr merge` with a mergeability gate, post-merge state confirmation, PRD location, and an invocation of the shared `auto-flip-on-merge.sh` helper. Closes the async-merge auto-flip gap that PR #186 / PR #189 hit. Flags — `--squash` (default) | `--merge` | `--rebase` for merge method; `--no-flip` to skip the auto-flip stage. Use as `/kiln:kiln-merge-pr <pr-number>`.
---

# Kiln Merge PR — Atomic Merge + Auto-Flip

The maintainer-facing surface for merging a PR that `kiln-build-prd` shipped. Replaces the previous workflow of `gh pr merge <pr>` followed by manually re-running Step 4b.5 to flip the roadmap items — those steps now happen in one indivisible operation triggered by the maintainer's natural action (the merge itself).

Spec: `specs/merge-pr-and-sc-grep-guidance/spec.md` (FR-001..FR-007, NFR-001, NFR-005). Contract: `specs/merge-pr-and-sc-grep-guidance/contracts/interfaces.md` §B. PRD: `docs/features/2026-04-27-merge-pr-and-sc-grep-guidance/PRD.md`.

## User Input

```text
$ARGUMENTS
```

Arguments:

- `<pr-number>` — required, bare numeric (leading `#` tolerated and stripped).
- `--squash` (default) | `--merge` | `--rebase` — mutually exclusive merge method, propagated to `gh pr merge`.
- `--no-flip` — escape hatch; the merge proceeds, the auto-flip stage is skipped entirely (FR-007).

## Constants

```bash
HELPER="plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh"
COMMIT_MSG_TEMPLATE="chore(roadmap): auto-flip on merge of PR #%s"
```

## Stage 1 — Working-tree preflight (NFR-005, FR-006)

`git status --porcelain` MUST be empty before any merge or flip happens. If the working tree is dirty, refuse and surface the dirty paths. NEVER `git stash` automatically (PRD R-3 — V1 deferral).

```bash
DIRTY_FILES="$(git status --porcelain)"
if [ -n "$DIRTY_FILES" ]; then
  echo "kiln-merge-pr: pr=${PR_NUMBER} stage=preflight working-tree=dirty exit=2"
  echo "Refusing to merge with uncommitted changes. Files:"
  echo "$DIRTY_FILES"
  echo "Commit, stash, or discard these changes manually, then re-run."
  exit 2
fi
```

**Why this matters**: a dirty tree at flip time would leak unrelated edits into the auto-flip commit (retro #187 PI-1 — the all-stage hazard, where staging the entire working tree pulls in unrelated files). The skill's commit step stages by exact path, so a dirty tree wouldn't actually leak files in practice, but the maintainer is more confused by mixed state than by an early refusal. Clean tree → clean commit.

## Stage 2 — Mergeability gate (FR-002, FR-002a)

```bash
PR_INFO_JSON="$(gh pr view "$PR_NUMBER" --json state,mergeable,mergeStateStatus 2>/dev/null || echo '{}')"
PR_STATE="$(echo "$PR_INFO_JSON" | jq -r '.state // "unknown"')"
PR_MERGEABLE="$(echo "$PR_INFO_JSON" | jq -r '.mergeable // "UNKNOWN"')"
PR_MERGE_STATE_STATUS="$(echo "$PR_INFO_JSON" | jq -r '.mergeStateStatus // "UNKNOWN"')"

ACTION="refuse"
case "$PR_STATE" in
  OPEN)
    case "$PR_MERGE_STATE_STATUS" in
      CLEAN|UNSTABLE|HAS_HOOKS) ACTION="accept" ;;
      *) ACTION="refuse" ;;
    esac
    ;;
  MERGED)
    # FR-002a / NFR-001 — idempotent re-invocation: skip Stage 3, proceed to Stage 4.
    ACTION="skip-merge-already-merged"
    ;;
  *) ACTION="refuse" ;;
esac

echo "kiln-merge-pr: pr=${PR_NUMBER} stage=gate state=${PR_STATE} mergeStateStatus=${PR_MERGE_STATE_STATUS} action=${ACTION}"

if [ "$ACTION" = "refuse" ]; then
  echo "Refusing to merge. PR state=${PR_STATE}, mergeStateStatus=${PR_MERGE_STATE_STATUS}."
  echo "Resolve the merge gate (rebase, fix conflicts, or address review) and re-run."
  exit 1
fi
```

**Idempotency path (NFR-001)**: when the gate detects `state=MERGED`, the skill skips Stage 3 entirely and proceeds to Stage 4. Re-invocation on a merged PR is supported and produces `step4b-auto-flip: ... items=N patched=0 already_shipped=N` from the helper.

## Stage 3 — Merge (FR-003)

```bash
if [ "$ACTION" = "accept" ]; then
  # Default method is --squash (FR-001). Method is set above based on the flag passed.
  METHOD="${MERGE_METHOD:-squash}"
  echo "kiln-merge-pr: pr=${PR_NUMBER} stage=merge method=${METHOD} result=in-progress"
  if ! gh pr merge "$PR_NUMBER" "--${METHOD}" --delete-branch; then
    echo "kiln-merge-pr: pr=${PR_NUMBER} stage=merge method=${METHOD} result=failed"
    exit 1
  fi

  # FR-003 — wait for `gh pr view --json state` to return MERGED before proceeding.
  for _attempt in 1 2 3 4 5 6 7 8 9 10; do
    POST_STATE="$(gh pr view "$PR_NUMBER" --json state 2>/dev/null | jq -r '.state // "unknown"')"
    [ "$POST_STATE" = "MERGED" ] && break
    sleep 1
  done
  if [ "$POST_STATE" != "MERGED" ]; then
    echo "kiln-merge-pr: pr=${PR_NUMBER} stage=merge method=${METHOD} result=failed"
    echo "gh pr merge returned 0 but state is ${POST_STATE} after 10s. Investigate manually."
    exit 1
  fi
  echo "kiln-merge-pr: pr=${PR_NUMBER} stage=merge method=${METHOD} result=merged"
fi
# When ACTION=skip-merge-already-merged, Stage 3 is a no-op (FR-002a).
```

## Stage 4 — PRD location (FR-004)

```bash
PR_FILES_JSON="$(gh pr view "$PR_NUMBER" --json files 2>/dev/null || echo '{}')"
# Lex-sort the files list and take the FIRST docs/features/*/PRD.md entry.
PRD_PATH="$(echo "$PR_FILES_JSON" \
  | jq -r '.files[]? | .path' \
  | grep -E '^docs/features/[^/]+/PRD\.md$' \
  | sort \
  | head -n 1)"

if [ -z "$PRD_PATH" ]; then
  echo "kiln-merge-pr: pr=${PR_NUMBER} stage=locate-prd prd=none"
  echo "kiln-merge-pr: pr=${PR_NUMBER} auto-flip=skipped reason=no-prd-in-changeset"
  exit 0
fi
echo "kiln-merge-pr: pr=${PR_NUMBER} stage=locate-prd prd=${PRD_PATH}"
```

**Multi-PRD-in-changeset rule**: a PR that ships multiple PRDs is rare; per FR-004 / spec edge-case, the skill picks the lex-first match and proceeds. Multi-PRD PRs are out of scope for V1; if observed, file a follow-on roadmap item.

## Stage 5 — Auto-flip (FR-005, FR-007)

```bash
if [ "$NO_FLIP" = "true" ]; then
  echo "kiln-merge-pr: pr=${PR_NUMBER} auto-flip=skipped reason=--no-flip"
else
  # Snapshot the .kiln/roadmap/items/ directory's git state BEFORE the helper runs,
  # so Stage 6 can stage by exact mutated path (FR-006, NFR-005). Approach 1 from
  # contract §B.3 — re-walk derived_from + git diff filter.
  bash "$HELPER" "$PR_NUMBER" "$PRD_PATH"
fi
```

**Helper's diagnostic line** (byte-identical to Step 4b.5's pre-extraction emission per NFR-002):

```text
step4b-auto-flip: pr-state=<MERGED|OPEN|CLOSED|unknown> auto-flip=<success|skipped> items=<N> patched=<K> already_shipped=<S> reason=<|no-derived-from|pr-not-merged|gh-unavailable>
```

The skill does NOT re-format or re-emit this line — the helper owns it. Existing log-parsing consumers see the identical format whether the flip happened via Step 4b.5 (in-pipeline), `/kiln:kiln-merge-pr` (this skill), or `/kiln:kiln-roadmap --check --fix` (drift fixer).

## Stage 6 — Commit + push (FR-006, NFR-005)

Stage by **exact path** — never use the all-stage form (retro #187 PI-1, NFR-005). Use `git diff --name-only` to discover which `.kiln/roadmap/items/*.md` files the helper actually mutated, then `git add` each one explicitly.

```bash
if [ "$NO_FLIP" = "true" ]; then
  echo "kiln-merge-pr: pr=${PR_NUMBER} stage=commit-and-push files=0 result=skipped-no-flip"
else
  # Approach 1 (contract §B.3) — derive flipped paths from git diff.
  FLIPPED_PATHS="$(git diff --name-only -- '.kiln/roadmap/items/*.md')"
  if [ -z "$FLIPPED_PATHS" ]; then
    echo "kiln-merge-pr: pr=${PR_NUMBER} stage=commit-and-push files=0 result=skipped-no-changes"
  else
    FILE_COUNT=0
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      git add "$path"          # Exact path; NFR-005.
      FILE_COUNT=$((FILE_COUNT + 1))
    done <<< "$FLIPPED_PATHS"

    COMMIT_MSG="$(printf "$COMMIT_MSG_TEMPLATE" "$PR_NUMBER")"
    git commit -m "$COMMIT_MSG"
    git push
    echo "kiln-merge-pr: pr=${PR_NUMBER} stage=commit-and-push files=${FILE_COUNT} result=pushed"
  fi
fi
```

## Idempotency contract (NFR-001, FR-002a)

A second invocation of `/kiln:kiln-merge-pr <same-pr>` MUST succeed end-to-end:

1. Stage 1 passes (clean tree).
2. Stage 2 detects `state=MERGED` → ACTION=skip-merge-already-merged.
3. Stage 3 is skipped.
4. Stage 4 locates the PRD again (idempotent — `gh pr view --json files` is read-only).
5. Stage 5 invokes the helper; helper short-circuits each item via the `pr: <N>` idempotency guard → `items=N patched=0 already_shipped=N`.
6. Stage 6 sees zero git diff entries → `result=skipped-no-changes`. No commit, no push.

Net effect: zero file mutations, zero commits — the canonical diagnostic line still emits, log-parsing consumers see identical output whether the auto-flip ran on first or second invocation.

## Working-tree-dirty rule (NFR-005, FR-006)

If Stage 1 detects an unrelated dirty tree, the skill exits non-zero BEFORE Stage 2 runs. The maintainer is told exactly which files are dirty and instructed to clean them. The skill does NOT offer `--stash-and-restore` for V1 (PRD R-3 deferral). Rationale: stashing introduces failure modes (stash conflicts on restore, partial stash, hidden state) that hurt more than the manual `git status` step costs.

## Related skills

- `/kiln:kiln-build-prd` — runs the full pipeline; Step 4b.5 of that skill calls the SAME `auto-flip-on-merge.sh` helper this skill calls (FR-009 — extracted shared helper).
- `/kiln:kiln-roadmap --check --fix` — catches drift for items merged via the GitHub web UI or `gh pr merge` directly (i.e. NOT through this skill); also calls the same helper (FR-010).
