## Issue Created

**File**: `.kiln/issues/2026-04-25-cross-plugin-resolver-substitution-verified-live.md`
**Title**: Cross-plugin-resolver substitution verified live (PR #165)
**Date**: 2026-04-25
**Status**: verified
**Kind**: smoke-test-result
**Priority**: low
**Repo**: https://github.com/yoshisada/ai-repo-template
**Tags**: smoke-test, cross-plugin-resolver, verified, wheel, state-persistence
**Source**: kiln-report-issue (meta — workflow under test is also the verification vehicle)

## Duplicate check

Scanned `.kiln/issues/*.md` — no near-duplicate matches for "smoke", "substitut", "cross-plugin". Filed new.

## Smoke test verdict

✅ PR #165 fix verified live. State file embeds `workflow_definition`; `engine_init` prefers it; agent prompt receives literal absolute path; no `${WHEEL_PLUGIN_shelf}` leaks to the dispatched instruction.
