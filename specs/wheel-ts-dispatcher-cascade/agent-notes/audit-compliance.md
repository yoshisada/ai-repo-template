# Agent Friction Notes: audit-compliance

**Feature**: wheel-ts-dispatcher-cascade
**Date**: 2026-05-01

## What Was Confusing

- **"blocked on #2" coordination**: The prompt said to wait for `impl-wheel` to message done OR TaskList to show #2 completed. Both are fine as signals, but in practice the message arrived first with richer context (exact commit hashes, deferred tasks). TaskList alone would have been sufficient but the message made the impl-side decisions legible without re-reading 9 commit diffs.

- **Coverage gate instructions**: The spec acceptance gate (§8) says "80% coverage gate on changed lines per Constitution Article II," but the tooling version mismatch (`@vitest/coverage-v8@4.1.5` vs `vitest@1.6.1`) makes this unrunnable. The gap between "pass this gate" and "the tooling to run this gate is broken" was friction — I had to document a pre-existing infrastructure issue as a non-blocker rather than simply running the check. The spec should note when the coverage flag is known-broken.

- **cascadeNext cursor-advance ordering in engineHandleHook**: The engine's post-dispatch cursor-advance block (engine.ts:138–145) is still present and runs after every cascade-emitting dispatch. Verifying this wasn't a double-advance required mentally tracing through several scenarios (end-of-workflow, blocking-step halt, depth-cap). The correct answer is "not a double advance" but this wasn't documented anywhere. A brief comment in engineHandleHook explaining why its cursor-advance is safe when the cascade has already advanced would help future readers.

## Where I Got Stuck

- **dispatchStep depth parameter in engineHandleHook**: The engine calls `dispatchStep(step, ..., cursor)` without a `depth` argument. Per contract §3, this is backwards-compatible (defaults to 0). But I had to re-read the contract, the engine code, and the dispatchStep signature to confirm it was intentional. A `// depth defaults to 0 — each engineHandleHook call starts a fresh cascade chain` comment at the call site would eliminate this verification step.

- **FR-010 test 2 scope reduction**: The spec fixture #2 says "test writes the agent's output file, fires post_tool_use, and verifies the trailing command cascade-runs." The actual test only validates the first half (cascade stops at agent; trailing command is pending). The second half (post-agent resume) is deferred to `/wheel:wheel-test` E2E. This deviation from the spec is documented in tasks.md T-072 but not in the spec itself. I had to cross-reference to understand it wasn't a gap — the spec FR-010 fixture description should be updated to reflect the actual test scope or note the deferral explicitly.

## What Could Be Improved

1. **Spec FR-010 should reflect actual test scope for fixture #2**: The wording "test then writes the agent's output file, fires post_tool_use, and verifies the trailing command cascade-runs" sets an expectation that the test doesn't meet. Update the spec or add a `(Note: post-agent resume is E2E only; vitest fixture covers halt-only assertion)` annotation.

2. **coverage tooling version should be pinned in package.json**: `@vitest/coverage-v8` should be `"^1.6.1"` or set via a `peerDependencies` + `overrides` pattern to stay in sync with vitest. This failure mode (coverage silently broken by semver-incompatible dep) is a recurring footgun.

3. **engineHandleHook: add a comment on why double-advance is safe**: Future auditors of the cascade will hit the same question I did. The comment saves 5 minutes of re-verification per audit pass.

4. **Pre-wait idle time**: I spent ~2 minutes reading the PRD and checking an empty spec directory while task #1 was still in progress. There's no way to parallelize this; it's just idle time. No action required — documenting for latency awareness.

## What Worked Well

- The FR numbering is consistent across PRD / spec / code comments / tests. FR-001 through FR-010 are all co-located and easy to cross-reference.
- `git log --oneline` + commit message convention made the 5-commit history immediately auditable.
- `cascadeNext` is a single function that encodes all 6 contract behaviors from interfaces.md §4. Auditing the cascade logic meant reading one function, not 3-4 per-dispatcher clones.
- The skipped-step walk-past in `cascadeNext` (not in the contract) is clearly documented in both the comment and the impl-wheel friction note. The deviation is explicit, not hidden.
