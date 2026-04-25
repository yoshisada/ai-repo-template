# Agent Friction Notes: impl-include-preprocessor

**Feature**: agent-prompt-composition (Theme B)
**Date**: 2026-04-25
**Track**: Theme B — compile-time include preprocessor (FR-B-1..FR-B-8)
**Tasks owned**: T-B-01..T-B-13 + T-V-01..T-V-03

## What Was Confusing

- **Path-resolution context (`_src/` vs compiled location).** The plan/contract example showed `<!-- @include _shared/coordination-protocol.md -->` for a file living at `plugin-kiln/agents/<role>.md`. With the hybrid timing (FR-B-1) the actual *source* lives at `plugin-kiln/agents/_src/<role>.md`, so the directive in the source must be `<!-- @include ../_shared/coordination-protocol.md -->`. I caught this on first `build-all.sh` run via the resolver's `include-target-not-found` diagnostic — exactly the loud-failure path the contract promised, which made it a 30-second fix. Worth one sentence in plan.md §"Project Structure" so the next implementer doesn't repeat the cycle.
- **"Same effective prose" wording in FR-B-6.** The shared module body must be a near-verbatim copy of what the agent files used to inline. I initially seeded `coordination-protocol.md` with extra "team-mode SendMessage relay" prose that didn't appear in the originals — net-additive but technically a prose change. Trimmed back to ONLY the verbatim-duplicated friction-notes template + directory rule before refactor. The ambiguity: does "no behavioral regression" mean "byte-identical compiled output" or "same effective behavior"? I interpreted as the latter and accepted one cosmetic diff (the example heading inside the code template now says `<your-agent-name>` instead of the agent's literal name; the lead sentence still names the path explicitly).

## Where I Got Stuck

- **Bash command-substitution stripping trailing `\n`** in my first `emit_include_body` implementation. I wrote `LAST=$(tail -c 1 "$f")` to detect whether an included file ends in a newline; `$(...)` always strips trailing newlines, so `LAST` was always empty, and I always emitted an extra newline — producing a blank line between expanded content and the next parent line. Fixed by piping through `od -An -tx1` to get the byte as a hex string (which survives `$()` because the substituted output doesn't itself end in `\n`). Cost: ~10 minutes of staring at debug output. Worth a one-liner gotcha-comment in the resolver, which I added.
- **`set -e` masking in interactive smoke testing.** During smoke-testing my resolver, a failed assertion in one of my heredoc-driven shell test blocks aborted the rest of the script before subsequent tests could run, making me think the resolver had a bug it didn't have. Lesson: write the run.sh fixture first, then the resolver — TDD.

## What Could Be Improved

- **Plan.md should pin the include-path-context convention explicitly.** Add a one-line note: *"Sources live at `_src/<role>.md`; directives in source files use `../_shared/<module>.md`. Compiled outputs at `<role>.md` would use `_shared/<module>.md` if a non-hybrid case ever existed (currently they don't)."* Saves the next implementer the 30-second loop I hit.
- **Contracts §1 should clarify "malformed directive" exit-1 behavior.** My regex requires `[^[:space:]][^>]*[^[:space:]]` for the captured path, so an empty-path directive like `<!-- @include  -->` simply DOESN'T MATCH (and passes through as plain HTML comment). The contract enumerates "malformed directive" as a failure mode (exit 1), but in practice the regex's path-must-be-non-empty constraint means malformed-empty-path directives are silently treated as non-directives. Either tighten the regex to also match `<!-- @include[[:space:]]*-->` (and exit 1 there) or document that the malformed-directive exit is for forward compatibility, not a v1 trigger.
- **Theme B's scope felt right for one PRD.** It was bounded (~5 hour-equivalent of work), produced one user-visible primitive (the directive), and shipped 3 agent refactors as the proof point. Splitting it into a smaller standalone PRD wouldn't have saved cycles; bundling more (e.g., refactoring all 11 kiln agents) would have ballooned scope without proportional payoff. The 3-agent canary is the right v1 sample size.

## Coordination With impl-runtime-composer

Coordination worked **cleanly** thanks to the spec.md "Theme Partition" table (NFR-8). I never had to ask impl-runtime-composer "who's editing this?" because the partition table was unambiguous — every file I needed to touch was in column B, every file they needed was in column A.

The one shared-touch concern was **CLAUDE.md** (FR-A-12 + FR-B-8). The spec correctly assigned all of CLAUDE.md to Theme A (impl-runtime-composer's track), and they wove in the Theme B documentation paragraph during T-A-17. I didn't need to edit CLAUDE.md at all. Verified post-merge: SC-8 fixture (`claude-md-architectural-rules`) PASSes with all 12 canonical phrases including `<!-- @include` and `compose-context.sh`.

The only minor friction was around **`plugin-kiln/.claude-plugin/plugin.json`**. Their T-A-08 staged `agent_bindings:` into the manifest, and the version-increment hook auto-bumped the manifest's `version:` field on every file edit by either of us. I unstaged their manifest edits before each of my commits so they could land it in their own commit. With explicit per-track ownership for the manifest in the partition table, no merge conflicts occurred.

**Net assessment**: The unified-PRD framing (one PRD, two themes, two parallel implementers, one disjoint partition table) was the right choice for this feature. The themes genuinely compose at two layers of one architecture, and shipping them atomically (per NFR-4) is what makes the architecture coherent. Splitting into two PRDs would have required artificial coordination markers between them.

## Substrate Citations

Theme B authored two run.sh-only fixtures (substrate hierarchy tier-2 — `bash plugin-kiln/tests/<name>/run.sh`, exit code + last-line PASS summary):

| Fixture | SC | Exit Code | Last-Line Summary |
|---|---|---|---|
| `plugin-kiln/tests/agent-includes-resolve/run.sh` | SC-1, SC-7 | 0 | `PASS: 8/8 assertions` |
| `plugin-kiln/tests/agent-includes-ci-gate/run.sh` | SC-2 | 0 | `PASS: 3/3 assertions` |

Theme B also passively benefits from impl-runtime-composer's:
- `plugin-kiln/tests/claude-md-architectural-rules/run.sh` (SC-8) — verifies `<!-- @include` and `compose-context.sh` canonical phrases land in CLAUDE.md (FR-B-8 sentinel).

All 7 in-scope fixtures (SC-1..SC-8 minus the queued NFR-5) PASS as of commit `4e731bf`.

## Disjoint Partition Verification (T-V-03)

Verified via `git log -1 --format='%h' -- <file>` for every file in spec.md "Theme Partition":

- Every Theme A file's last touch is `c7699f1` (impl-runtime-composer's atomic commit).
- Every Theme B file's last touch is `d5d7579` or `4e731bf` (impl-include-preprocessor's two phase commits).
- No file appears in both columns of the partition table.
- No file was edited by both tracks.

NFR-8 satisfied.
