# Tests

## Layout

- `tests/unit/` — bash-level unit tests for individual scripts.
- `tests/integration/` — end-to-end shell scripts that exercise workflows.

## Running unit tests

Unit tests for `manifest-improvement-subroutine` are plain bash scripts (prefixed
`test-`). Run them directly:

```bash
bash tests/unit/test-derive-proposal-slug.sh
bash tests/unit/test-validate-reflect-output.sh
bash tests/unit/test-check-manifest-target-exists.sh
bash tests/unit/test-write-proposal-dispatch.sh
```

Each file is self-contained, prints `PASS`/`FAIL` lines per case, and exits
non-zero if any case fails.

### Optional — bats-core

Some contributors prefer `bats-core`. If you want to port these tests to bats:

```bash
brew install bats-core
```

Then the equivalent bats files would live alongside the shell scripts. The
shell-based tests are the authoritative source.

## Running integration tests

```bash
bash tests/integration/silent-skip.sh
bash tests/integration/write-proposal.sh
bash tests/integration/out-of-scope.sh
bash tests/integration/hallucinated-current.sh
bash tests/integration/ungrounded-why.sh
bash tests/integration/caller-wiring.sh
bash tests/integration/portability.sh
bash tests/integration/mcp-unavailable.sh
```
