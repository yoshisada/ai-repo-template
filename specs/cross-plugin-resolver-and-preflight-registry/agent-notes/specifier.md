# Specifier friction note — cross-plugin-resolver-and-preflight-registry

**Author**: specifier (team kiln-cross-plugin-resolver, task #1)
**Date**: 2026-04-24

## What was confusing

- **PRD vs spec scope overlap**: the PRD already contained a complete "Solution Architecture" section, full FR text, full NFR text, full test surface, and even an ASCII diagram of the runtime path. This is great input but it left the spec phase with only a thin transformation: re-shape PRD content into spec section conventions (User Stories with G/W/T, Acceptance Scenarios, Success Criteria) without inventing scope. I largely echoed the PRD's structure into spec.md and used the saved cycles to thoroughly resolve OQ-F-1 in research.md. Recommend the build-prd pipeline acknowledge this — for PRD-derived specs, the spec author's primary value-add is (a) decomposing FRs into G/W/T-shaped acceptance criteria, (b) resolving any BLOCKING open questions, (c) recording bash-level interface signatures the implementers can match against. The "create user stories from a vague description" framing of /specify doesn't quite fit when the PRD is already this thorough.
- **Spec-directory-naming guard rail**: the team-lead's prompt was crystal clear that the dir must be `specs/cross-plugin-resolver-and-preflight-registry/` (no date, no number prefix). The `/specify` skill itself, however, calls `.specify/scripts/bash/create-new-feature.sh` which auto-numbers and auto-prefixes. Running /specify literally would have produced `specs/00N-cross-plugin-resolver/spec.md` and required manual rename. I authored the artifacts directly using the canonical path, treating the chaining mandate as "produce the artifacts, by any means necessary, in one uninterrupted pass." If team-lead wanted the literal slash-commands to run, the script would need a `--dir-name` override flag.

## Where I got stuck

- Brief moment: the wheel `engine.sh` and `dispatch.sh` are not small, and I needed to figure out where the registry/resolver/preprocessor plug into the activation path. Settled on "before any state mutation, after `workflow_load`" without reading every line of engine.sh — research §3 of plan.md leaves the precise call site as an implementer detail. Implementers will need to read engine.sh themselves.
- Spent some time confirming Candidate C doesn't exist (`env | grep CLAUDE` only revealed `CLAUDE_PLUGIN_ROOT` which is per-skill, not session-wide). Worth recording in research.md so future plan revisions don't re-litigate.

## What could be improved in /specify, /plan, /tasks, or in this prompt

- **/specify, /plan, /tasks chaining**: in this case, "chain them in one uninterrupted pass" effectively means "author all four docs (spec + research + plan + tasks + contracts) directly without three intermediate slash-command invocations." For PRDs this thorough, that's the right call. For greenfield ideas with no PRD, the slash commands' interactive structure is more valuable. The build-prd skill could detect "PRD already exists with full FR/NFR/test-surface" and skip directly to the direct-author path.
- **Interface contracts**: the specifier-writes-contracts pattern works well here because the PRD already named the three files (`registry.sh`, `resolve.sh`, `preprocess.sh`) and the user direction was "every signature is a named bash function." For PRDs that don't have this level of mechanical detail, the specifier would need a /clarify step to pin down signatures before writing contracts.

## How OQ-F-1 resolution went

Smoothly. Verification path:

1. Inspected this session's `$PATH` — found `/Users/ryansuematsu/.claude/plugins/cache/<org-mp>/<plugin>/<version>/bin` for every loaded plugin (5 yoshisada-speckit plugins + frontend-design + warp). ✅ Marketplace cache works.
2. Verified `$PATH` mechanism is the same Claude Code harness behavior for `--plugin-dir` and `settings.local.json` modes (per the harness's documented PATH-injection convention). Recorded the plugin-name derivation strategy: read `<plugin-dir>/.claude-plugin/plugin.json::name` (more reliable than directory basename for dev overrides like `plugin-shelf-dev/`).
3. Verified Candidate C nonexistent: `env | grep -i CLAUDE` returned only `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_PLUGIN_ROOT` (single-plugin scope), `CLAUDE_AGENT_SDK_VERSION`. No session-wide registry env var.
4. Inspected `~/.claude/plugins/installed_plugins.json` for Candidate B fallback shape — confirmed `plugins[<name>@<source>][0].installPath` is the absolute install dir. Cross-checking against `~/.claude/settings.json::enabledPlugins` filters disabled-but-installed plugins per FR-F1-3.

**Verdict**: Candidate A primary, Candidate B auto-fallback (or `WHEEL_REGISTRY_FALLBACK=1`). Candidate C confirmed nonexistent.

## Recommendations for downstream implementers

- **impl-registry-resolver**: read `installed_plugins.json` shape in research.md §1.D before authoring `_internal_installed_plugins_fallback`. The `plugins[<name>@<source>]` is an ARRAY (multiple installs of same plugin from same source), so `[0].installPath` is the safe pick (latest entry). Cross-check with the `version` field if a specific version is named in settings.
- **impl-preprocessor**: research §2.B's escape-decoder discussion deferred bash-vs-awk-vs-python3 to plan §3 / U-1. Plan resolves: `awk` for escape pre-scan, bash for substitution loop. macOS BSD awk vs gawk parity should be tested early — if it bites, fall back to `python3 -c '...'`.
- **impl-migration-perf**: NFR-F-7 atomic-commit coordination is the trickiest part. Recommend opening a stacked PR (or a single squash-merge PR) that bundles all three implementers' diffs. Don't commit FR-F5 in isolation.
