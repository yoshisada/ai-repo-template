# fixture-no-drift

Exercises:
- SC-006 (idempotence) — two runs back-to-back on unchanged state produce byte-identical preview bodies excluding the header timestamp line.
- SC-007 (backwards compat) — existing `/kiln:kiln-cleanup` and `/kiln:kiln-doctor` modes produce identical stdout + exit codes compared to pre-PR baseline.

## Shape

An empty `.kiln/issues/` (or one containing only `status: completed`
items already in `.kiln/issues/completed/`) plus zero orphaned
top-level folders and zero stale artifacts older than
`unreferenced-kiln-artifact.min_age_days`.

## Assertions — SC-006

```bash
/kiln:kiln-hygiene
sleep 1  # force a distinct timestamp
/kiln:kiln-hygiene
cd .kiln/logs
PREV1=$(ls -1t structural-hygiene-*.md | sed -n '2p')
PREV2=$(ls -1t structural-hygiene-*.md | sed -n '1p')
diff <(tail -n +2 "$PREV1") <(tail -n +2 "$PREV2")
# → empty (byte-identical bodies)
```

The header line (`# Structural Hygiene Audit — <timestamp>`) is the
only permitted diff per NFR-002.

## Assertions — SC-007

```bash
# Capture baseline on main (pre-PR merge)
git stash
git checkout main
/kiln:kiln-cleanup --dry-run > baseline-cleanup-dryrun.txt
/kiln:kiln-cleanup          > baseline-cleanup.txt
/kiln:kiln-doctor --fix --dry-run 2>&1 | grep -v 'Structural hygiene drift' > baseline-doctor-fix-dryrun.txt
/kiln:kiln-doctor --cleanup        2>&1 | grep -v 'Structural hygiene drift' > baseline-doctor-cleanup.txt
git checkout -
git stash pop

# Current branch
/kiln:kiln-cleanup --dry-run > current-cleanup-dryrun.txt
/kiln:kiln-cleanup          > current-cleanup.txt
/kiln:kiln-doctor --fix --dry-run 2>&1 | grep -v 'Structural hygiene drift' > current-doctor-fix-dryrun.txt
/kiln:kiln-doctor --cleanup        2>&1 | grep -v 'Structural hygiene drift' > current-doctor-cleanup.txt

diff baseline-cleanup-dryrun.txt current-cleanup-dryrun.txt        # → empty
diff baseline-cleanup.txt current-cleanup.txt                      # → empty
diff baseline-doctor-fix-dryrun.txt current-doctor-fix-dryrun.txt  # → empty (after excluding 3h row)
diff baseline-doctor-cleanup.txt current-doctor-cleanup.txt        # → empty (after excluding 3h row)
```

The `grep -v 'Structural hygiene drift'` masks the new 3h row that is
permitted to exist per NFR-003; all OTHER output must be unchanged.

## No bodies

Empty state. No sample issue or feedback files ship with this fixture
— the point is that the audit produces no signals.
