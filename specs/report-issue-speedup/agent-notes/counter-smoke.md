# Phase A-4 — Counter smoke transcript

## Setup

Fresh tempdir, seeded `.shelf-config`:

```
# Test config
slug = test
shelf_full_sync_threshold = 3
```

(No `shelf_full_sync_counter` line — `ensure-defaults` should append it on first call.)

## Environment

- macOS 24.5.0, zsh. **`command -v flock` → not found.** Script took the unlocked fallback path per FR-006 (±1 drift accepted).
- `flock` is absent in the default macOS toolchain; the fallback is exercised on every dev box unless the user installs `util-linux` via brew. This is now confirmed behavior, not a bug.

## Results

```
=== read ===
{"counter":0,"threshold":3}

=== 10 increment-and-decide cycles (threshold=3) ===
iter=01  out={"before":0,"after":1,"threshold":3,"action":"increment"}  config_counter_now=1
iter=02  out={"before":1,"after":2,"threshold":3,"action":"increment"}  config_counter_now=2
iter=03  out={"before":2,"after":0,"threshold":3,"action":"full-sync"}  config_counter_now=0
iter=04  out={"before":0,"after":1,"threshold":3,"action":"increment"}  config_counter_now=1
iter=05  out={"before":1,"after":2,"threshold":3,"action":"increment"}  config_counter_now=2
iter=06  out={"before":2,"after":0,"threshold":3,"action":"full-sync"}  config_counter_now=0
iter=07  out={"before":0,"after":1,"threshold":3,"action":"increment"}  config_counter_now=1
iter=08  out={"before":1,"after":2,"threshold":3,"action":"increment"}  config_counter_now=2
iter=09  out={"before":2,"after":0,"threshold":3,"action":"full-sync"}  config_counter_now=0
iter=10  out={"before":0,"after":1,"threshold":3,"action":"increment"}  config_counter_now=1
```

Cadence: `0→1→2→reset(0)→1→2→reset(0)→1→2→reset(0)→1` — exactly the pattern the contract requires.

## Observations

1. **`ensure-defaults` idempotency**: the missing counter key was auto-appended on the first call; subsequent calls did not re-append.
2. **Comment / key-order preservation**: the initial `# Test config` comment and the `slug = test` line stayed byte-identical across 10 rewrites.
3. **Atomic tempfile+mv**: no transient truncation observed; intermediate reads inside the run always saw a complete file.
4. **Lock-file state**: in the fallback path no `.shelf-config.lock` sibling is ever created (the flock-guarded `9>` redirect only runs when flock is present). No cleanup required.
