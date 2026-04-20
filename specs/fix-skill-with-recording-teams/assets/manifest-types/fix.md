---
type: manifest-type
name: fix
last_updated: 2026-04-20
---

# `@manifest/types/fix.md`

A **fix note** is the durable record of one `/kiln:fix` invocation — the write produced by the `fix-record` team after the debug loop terminates (either with a successful commit or after 9-attempt escalation). Fix notes live at `@projects/<project>/fixes/<YYYY-MM-DD>-<slug>.md` and are the canonical surface future AI agents read when deciding whether a given bug has been seen before, what the cause was, and what worked (or what was tried and failed).

Fix notes are schema-conformant to this file. The `fix-record` team brief references the rules below verbatim.

Modeled on `@manifest/types/mistake.md` — same frontmatter-then-sections shape, same three-axis tag discipline, same "the slug names the trap future agents should watch for" principle.

## Required frontmatter

Every fix note MUST carry these frontmatter fields, in this order, no others above them:

- `type: fix` — literal value; identifies the note's shape for tooling and graph views. (FR-005, FR-006)
- `date: <YYYY-MM-DD>` — the date the fix landed (or escalated), in UTC. Matches the filename prefix.
- `status: <fixed|escalated>` — enum. `fixed` means the debug loop produced a passing commit. `escalated` means the 9-attempt loop exhausted without a passing fix.
- `commit: <hash-or-null>` — the commit hash of the landed fix, as plain text. `null` when `status: escalated`.
- `resolves_issue: <ref-or-null>` — a GitHub issue number (as a string, e.g. `"42"`), a URL, or `null`. When non-null, the body SHOULD link to it (see "Body sections" below).
- `files_changed: [<path>, ...]` — list of repo-relative paths. For `status: fixed`, the files that were modified. For `status: escalated`, files that were inspected (not modified). MAY be empty for escalated notes; MUST be present either way.
- `tags: [<fix-axis>, <topic-axis>, <stack-axis>]` — tag vocabulary; see "Tag axes" below.

A field not listed MUST NOT appear. If a future revision adds a field, bump `last_updated` at the top of this file and update the `fix-record` brief in the same change.

## Body sections

Exactly five H2 sections, in this order, always present (even if a section's content is `_none_`):

1. `## Issue` — the bug, stated as one or two sentences. Derived from the free-text argument to `/kiln:fix` (or the GitHub issue title). First-person is fine; past tense is fine. Plain description — no speculation.
2. `## Root cause` — one sentence describing the underlying defect. For escalated notes, state the leading hypothesis explicitly as such ("Leading hypothesis: ..."). Do NOT write "unknown" — the debug loop always has a leading hypothesis by construction.
3. `## Fix` — for `status: fixed`: one to three sentences describing what was changed and why. For `status: escalated`: a plain enumeration of techniques attempted ("Tried: X (failed because Y), tried Z (failed because W)"). Do not hedge; honesty principle applies the same way it does in `@manifest/types/mistake.md`.
4. `## Files changed` — a bulleted list of the `files_changed` frontmatter entries. Write `_none_` when the list is empty (escalated fixes may leave this empty). Each bullet is a repo-relative path, no decoration.
5. `## Escalation notes` — `_none_` when `status: fixed`. For `status: escalated`, a populated multi-line section with (a) the techniques tried with the `why it failed` per technique, (b) any diagnostic artifact paths the debugger produced, (c) the recommendation to the human ("suggest manual inspection of `<path>`", "suggest raising a new spec for this behavior", etc.).

## Body cross-references (FR-007)

Inside `## Issue` or just after it, the note SHOULD include:

- `Resolves [[#<issue-ref>]]` or `Resolves <URL>` — when `resolves_issue` is non-null. Use a wikilink form if the issue lives in an Obsidian-tracked system; otherwise a plain URL.
- `Related spec: [[<feature_spec_path>]]` — when `feature_spec_path` is non-null.
- `Commit: <hash>` — when `commit` is non-null. Plain text, not a wikilink (commits live outside the vault).

When any of these values is null, simply omit the line. Do not write a placeholder.

## Tag axes (FR-006)

Every fix note carries **exactly three tag-axis categories**, in the order below. Under-tagged or over-tagged notes are a defect — an under-tagged note is invisible to the queries future agents run, and an over-tagged note is noise.

### Axis 1 — `fix/*` (exactly one)

The class of failure that was fixed. Pick the single best match:

- `fix/runtime-error` — uncaught exception, crash, null-deref, or similar runtime failure in a deployed path.
- `fix/regression` — a previously-working behavior broke due to a recent change.
- `fix/test-failure` — a test was failing and now passes; the product path may or may not have changed.
- `fix/build-failure` — the build, typecheck, lint, or bundle step was failing.
- `fix/ui` — layout, styling, interaction, visual regression, or anything Playwright-observable in a browser.
- `fix/performance` — latency, memory, or throughput regression.
- `fix/documentation` — docs-only fix (typo in a README, wrong example, outdated config).

If no `fix/*` tag fits (rare), propose a new value via the manifest-improvement channel — do not invent one inline.

### Axis 2 — `topic/*` (at least one)

Free-form topic axis, inherited convention from other manifest types. Examples: `topic/auth`, `topic/routing`, `topic/data-migration`, `topic/oauth`, `topic/caching`. Use whatever topic tag(s) already exist in the vault for this area; add a new one only if there is no reasonable match.

### Axis 3 — stack axis (exactly one)

One of: `language/*`, `framework/*`, `lib/*`, `infra/*`, `testing/*`. Derive it from the `files_changed` list and/or the repo conventions:

- `language/typescript`, `language/python`, `language/rust`, `language/bash`, ...
- `framework/react`, `framework/next`, `framework/svelte`, ...
- `lib/playwright`, `lib/vitest`, ...
- `infra/ci`, `infra/docker`, ...
- `testing/e2e`, `testing/unit`, ...

A fix touching multiple stack layers (say, a TypeScript component AND a Playwright test) picks the stack layer where the root cause lived — the layer the debug loop actually patched.

## Example note

```markdown
---
type: fix
date: 2026-04-20
status: fixed
commit: a1b2c3d4e5f6
resolves_issue: "42"
files_changed:
  - src/auth/login.ts
  - src/auth/__tests__/login.spec.ts
tags:
  - fix/regression
  - topic/auth
  - language/typescript
---

## Issue
Login redirect after successful auth sent users to `/home` even when they arrived via a deep link, dropping their intended destination.

Resolves [[#42]].
Related spec: [[specs/auth/spec.md]].
Commit: a1b2c3d4e5f6

## Root cause
The redirect target was hardcoded to `/home` in `finalizeLogin` instead of reading the `returnTo` query param.

## Fix
Made the redirect target read from `returnTo` when present, falling back to `/home` otherwise. Added a regression test covering the deep-link path.

## Files changed
- src/auth/login.ts
- src/auth/__tests__/login.spec.ts

## Escalation notes
_none_
```

## Example escalated note

```markdown
---
type: fix
date: 2026-04-20
status: escalated
commit: null
resolves_issue: null
files_changed:
  - src/jobs/queue.ts
  - src/jobs/__tests__/queue.spec.ts
tags:
  - fix/test-failure
  - topic/jobs
  - testing/unit
---

## Issue
The `queue` unit test fails intermittently in CI (roughly 1-in-20 runs) with "expected 3 items, got 2".

## Root cause
Leading hypothesis: the test races against an async flush in `Queue.drain`. The `expect` runs before the final `await` in the implementation settles.

## Fix
Tried: awaiting `queue.drain()` explicitly in the test (failed — drain already awaited). Tried: seeding a deterministic clock (failed — flakes still reproduced). Tried: serializing queue operations with a mutex (failed — deadlocked on the second test case). Did not land a passing fix within 9 attempts.

## Files changed
- src/jobs/queue.ts
- src/jobs/__tests__/queue.spec.ts

## Escalation notes
Techniques tried:
- Explicit await of `queue.drain()` — the test still raced; `drain` appears to await an empty promise chain.
- Deterministic clock via `vi.useFakeTimers()` — flakes still reproduced, suggesting the race is not timer-bound.
- Serialization mutex around queue ops — deadlocked the second test case; added complexity without fixing the race.

Diagnostics:
- `.kiln/qa/latest/queue-race.log` — stack traces from five flake reproductions.

Recommendation to human:
- Suggest manual inspection of `Queue.drain` — the promise chain may not be what it appears, or the test may be racing against microtask scheduling not captured by `await drain()`.
- Consider raising a new spec for "queue must be deterministically drainable in tests" if the current contract is ambiguous.
```
