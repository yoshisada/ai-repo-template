# Large-Vault Result — deferred

**Status**: deferred to auditor or a follow-up task

Per SC-004 the test needs ≥50 GitHub issues + ≥20 PRDs under
`docs/features/`. No such fixture was synthesized in this session because:

1. Synthesizing a 50+ issue GitHub fixture requires either a dedicated
   test repo (unavailable) or scripting `gh issue create` against a throwaway
   repo (out of session scope for a workflow refactor).
2. The structural risk this gate guards against is "obsidian-discover or
   obsidian-apply hits an agent context ceiling". The v4 design mitigates
   this by making obsidian-discover emit ONLY frontmatter-derived fields
   (no body) and obsidian-apply consume ONLY the pre-filtered work list
   (no raw upstreams). Both agents' payloads scale linearly with the
   number of issues/PRDs — at 50+20 items the discovery index is
   estimated at ~6k tokens and the work list at ~10k tokens, well under
   agent context limits.

## If SC-004 fails at runtime

Per plan.md: shrink the `obsidian-discover` index payload further (drop
fields beyond path+filename_slug+last_synced+status). DO NOT add a third
agent — that violates FR-001.
