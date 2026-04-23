# fixture-all-rules-fire

Exercises SC-002: merged-PRD archival catches a real instance.

## Shape

Five items are represented below. Copy them into a scratch repo's
`.kiln/issues/` and create the matching PRD files under
`docs/features/` (or `products/`) before running the audit.

| file | status | prd | expected signal |
|---|---|---|---|
| merged-1.md | prd-created | docs/features/2026-04-01-merged-one/PRD.md | archive-candidate (if branch `build/merged-one-20260401` is in `gh pr list --state merged`) |
| merged-2.md | prd-created | docs/features/2026-04-02-merged-two/PRD.md | archive-candidate |
| merged-3.md | prd-created | products/merged-three/PRD.md | archive-candidate (products/ slug derivation path) |
| unmerged-control.md | prd-created | docs/features/2026-04-10-unmerged/PRD.md | needs-review (no merged PR matching slug) |
| malformed.md | prd-created | (missing or blank) | needs-review (prd: field empty or points at missing file) |

## Assertions on the preview

Against `.kiln/logs/structural-hygiene-<ts>.md`:

```bash
# Exactly 3 archive-candidate rows for this rule
grep -c '^| merged-prd-not-archived |.*| archive-candidate |' preview.md
# → 3

# Bundled section exists with count 3
grep -c '^## Bundled: merged-prd-not-archived (3 items)$' preview.md
# → 1

# Strict bundle-accept prose is present verbatim
grep -Fc 'Accept or reject as a unit.' preview.md
# → 1

# Control does NOT appear in the bundled diff body (sorted filename check)
! grep -q 'unmerged-control.md' <(awk '/^## Bundled: merged-prd-not-archived/,/^## [^B]/' preview.md)
# → exit 0

# Malformed item appears as needs-review in the Signal Summary
grep -c '| merged-prd-not-archived |.*| needs-review |.*malformed.md' preview.md
# → 1
```

## Notes

The fixture does not ship executable bootstrap bash — the audit skill
is invoked via `/kiln:kiln-hygiene` in Claude Code, not as a direct
shell script. To run the fixture end-to-end, a human (or the auditor
agent) constructs the `.kiln/issues/` layout in a scratch worktree,
invokes the skill, and diffs the preview against the assertions above.
