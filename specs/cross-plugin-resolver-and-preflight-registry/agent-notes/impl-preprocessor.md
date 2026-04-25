# impl-preprocessor — friction notes (FR-009)

Track friction encountered while implementing Theme F2 (schema) + F4 (preprocessor + tripwire).
Filled in incrementally during work; finalized before marking task #3 completed.

## Phase 2.B — preprocessor pure logic + bats coverage

- **awk → sentinel-byte python3 pivot.** Plan §3 nominated `awk` for the
  escape pre-scan. In practice the escape-grammar contract (research §2.B
  / I-P-3) requires *positional* skip-tracking: the literal `$${...}`
  sequence must be invisible to the substitution stage and then decoded
  back. BSD awk's `gsub()` doesn't have negative lookbehind; the cleanest
  awk implementation is a manual char-by-char tokenizer, which is more
  fragile (and platform-divergent: macOS BSD awk vs Linux gawk) than a
  20-line `python3` pass that already-permitted-as-fallback per plan §3.
  Pivoted to a sentinel-byte placeholder pattern (`\x01ESC_DOLLAR_BRACE\x01`)
  inside python3. The sentinel is invisible to the FR-F4-5 narrowed
  tripwire grep, so escapes survive without false positives. Net: less
  code, more portable, behaviour matches the contract verbatim. Worth
  surfacing in retro: the plan's "awk preferred" guidance traded a small
  dependency win for a meaningful complexity hit.

- **Tripwire-before-decode ordering.** Initial draft decoded the sentinel
  inside the python3 stage, then ran the bash-side tripwire grep. That
  caught literal `${WHEEL_PLUGIN_shelf}` from user docstrings as a
  residual and false-positived. Fixed by leaving the sentinel in place
  through the tripwire scan and decoding in bash AFTER the scan returns
  zero. Cheap fix, but a non-obvious ordering — worth a comment in the
  source (added).

- **Bats was not preinstalled.** `brew install bats-core` worked locally;
  CI configs (e.g. `.github/workflows/wheel-tests.yml`) currently have
  no bats step. Phase 4 Wire-up should ensure CI installs bats before
  running the new `.bats` files. Flagging for impl-migration-perf and
  the auditor.

## Phase 4 — engine wiring + workflow_load schema + context.sh refactor

(filled in when impl-registry-resolver signals T031 is in place)

