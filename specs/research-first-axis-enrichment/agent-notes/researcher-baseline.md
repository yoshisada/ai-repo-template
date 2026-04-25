# Researcher-baseline — friction notes

**Branch**: `build/research-first-axis-enrichment-20260425`
**Task**: 2 — capture pricing + time-noise baselines
**Captured**: 2026-04-25

## What worked

- `WebFetch` on `docs.anthropic.com/en/docs/about-claude/pricing` resolved cleanly (after one redirect to `platform.claude.com`). The "Model pricing" table is structured Markdown — easy to extract per-row numerics. **Documenting the canonical pricing source URL** in a comment in `plugin-kiln/lib/pricing.json` is a cheap stale-detection signal beyond the 180-day mtime heuristic.
- `python3 -c 'import time; print(time.monotonic())'` is a great monotonic source. It removed the entire macOS / coreutils ambiguity in one line. Strongly recommend the implementer use it as primary in the runner startup ladder (FR-009).

## What didn't

- **`https://www.anthropic.com/pricing` is a wrong source.** It redirects to `claude.com/pricing` which is plan-level (Free / Pro / Max), not per-MTok. The team-lead's task brief listed it as Step-1 of the source-resolution ladder. Recommendation for the next pipeline run: **swap step-1 to `https://docs.anthropic.com/en/docs/about-claude/pricing`** — that's the canonical per-MTok source and resolves on first try.
- **The PRD's example pricing in FR-010 is 2-of-3 wrong.** `claude-opus-4-7` example values track Opus 4 / 4.1 legacy ($15 / $75 / $1.50), and `claude-haiku-4-5-20251001` example values track Haiku 3.5 ($0.80 / $4 / $0.08). Only `claude-sonnet-4-6` matches. The PRD acknowledged "values MUST be confirmed during implementation" — this baseline confirms they need replacement, not just confirmation. SC-004 is undefined-behavior-for-tests if the implementer ships the PRD-example values verbatim. **Suggested PI for retro**: when a PRD includes example data tagged "confirm during implementation", the specifier should mark that data as `unverified:` in the PRD frontmatter so the implementer can search for un-cleared markers before merging.

## Surprises

- **macOS BSD `date +%N` worked** on this researcher's host (`/bin/date +%N` → `127871000`). Apple's BSD date evidently picked up GNU-style `%N` at some point — but this is NOT documented in the man page and is not safe to assume on older macOS. Sticking with `python3 time.monotonic()` as primary sidesteps the question entirely.
- **No fixture in `plugin-kiln/tests/` ships a `run.sh`** — they're test-yaml fixtures invoked via `/kiln:kiln-test` harness, not direct-bash runnable. Used `plugin-wheel/tests/agent-resolver/run.sh` instead (180 ms Bash fixture; representative of harness floor, NOT representative of real kiln-test → claude-print research-run wall-clock). The team-lead's brief listed both tree-roots as candidates — for future baselining, `plugin-wheel/tests/` is the right tree to sample.

## Time budget

Total wall clock ≈8 minutes (within the ≤15 minute budget). The two WebFetch redirects accounted for ~30 % of the elapsed time; resolving the canonical URL upfront would have saved a hop.
