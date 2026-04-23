# fixture-gh-unavailable

Exercises SC-003: gh-unavailable graceful degradation (FR-006).

## Shape

Reuses the same item set as `fixture-all-rules-fire/` but is invoked
with `gh` stripped from PATH (or with `GH_TOKEN` unset on a non-authed
host).

## Invocation

```bash
# Approach A: strip gh from PATH
PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "$(dirname $(command -v gh))" | paste -sd: -) \
  /kiln:kiln-hygiene

# Approach B: fake an unauthed host
GH_TOKEN= gh auth logout 2>/dev/null; /kiln:kiln-hygiene
```

## Assertions on the preview

```bash
# Header reports gh as unavailable
grep -c '^\*\*gh availability\*\*: unavailable$' preview.md
# → 1

# Every merged-prd-not-archived row is action=inconclusive
grep -c '^| merged-prd-not-archived |' preview.md
# → N (one per .kiln/issues/*.md in prd-created state)
! grep -qE '^\| merged-prd-not-archived \|.+\| (archive-candidate|needs-review) \|' preview.md
# → exit 0 (no non-inconclusive rows for this rule)

# Notes section contains the exact string from contract §9
grep -Fc 'merged-prd-not-archived: gh unavailable — marked inconclusive' preview.md
# → 1

# No bundled archive section rendered (zero archive-candidate rows)
! grep -q '^## Bundled: merged-prd-not-archived' preview.md
# → exit 0

# Skill exit code
echo $?
# → 0
```
