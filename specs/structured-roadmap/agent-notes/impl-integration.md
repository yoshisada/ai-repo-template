# impl-integration friction note — structured-roadmap

## What was clear

- **Contracts were precise.** `contracts/interfaces.md` §3 (shelf workflow) and §7 (distill extension) defined exact JSON shapes, literal strings, and sort orders. The `path_source` literal-string invariant (one of EXACTLY two strings) in §3.2 was unambiguous enough to write assertion logic directly from the contract.
- **Phase split was clean.** "impl-roadmap owns kiln-roadmap + templates + migration; impl-integration owns distill + shelf helper + next/specify hooks" left no shared-file contention. In 17 tasks (T040–T056, T058, T060, T062) I never had to touch an impl-roadmap file.
- **The early-landing directive was load-bearing.** Specifier's instruction "land T040 + T041 EARLY (block on T040 only) so impl-roadmap's T020 end-to-end test can run" was the right sequencing — once the shelf helper + workflow JSON were on disk, impl-roadmap could write their Step 5 item-write logic against a real target instead of a sketched contract.

## What was unclear

- **"skill" vs "workflow" terminology in the briefing.** Team-lead's briefing said "plugin-shelf/skills/shelf-write-roadmap-note/SKILL.md — NEW skill following shelf-write-issue-note pattern". But `shelf-write-issue-note` is a **workflow JSON**, not a skill — there's no `plugin-shelf/skills/shelf-write-issue-note/` dir. tasks.md T041 said the right thing ("Author plugin-shelf/workflows/shelf-write-roadmap-note.json"). I followed tasks.md. This should be fixed in the briefing template — workflows and skills are distinct artifacts and calling them interchangeably cost me a ~3-minute detour to confirm which one was canonical.
- **plugin.json "skill descriptor" (T060).** tasks.md said "Update plugin-kiln/.claude-plugin/plugin.json skill descriptor for kiln-distill". But plugin.json only carries the plugin-level description — per-skill descriptors live in each `skills/<name>/SKILL.md` frontmatter `description:` field, which was already updated as part of T043. I documented this in the task itself with a NOTE. The canonical place to update a skill's public-facing blurb should be called out explicitly in tasks.md (either "update plugin.json" OR "update SKILL.md frontmatter" — they're not the same).
- **No explicit spec of what "backward compat" means for distill narrative.** I wrote a backward-compat note ("when no items exist, narrative reverts to the 2-section feedback→issue shape; `derived_from:` byte-identical to pre-structured-roadmap output") but had to infer this from NFR-003 + the general "don't break existing callers" principle. The spec should have had an explicit backward-compat clause.

## Handoff friction from specifier

- **Good**: The "spec artifacts ready" SendMessage was explicit about the phase I owned (Phase 3, T040–T056) and the key call-outs. It also flagged the T041 early-landing optimization, which I executed.
- **Minor**: The specifier mentioned I'd be "BLOCKED on impl-roadmap T007" — but in practice, nothing in distill / shelf / next / specify actually depends on the validator at write-time. The validator is a pre-write gate for the **capture** path (impl-roadmap's T020), not for the **consumption** path (my T043–T050). I waited ~0 extra time because impl-roadmap moved fast, but in theory I could have unblocked in parallel. Future briefings should distinguish "write-side validator dep" vs "read-side validator dep".

## Cross-plugin coupling pain (kiln ↔ shelf)

- **Surprisingly low.** The shelf side is purely mechanical: parse input → compute path → write via MCP → emit result JSON. The kiln side (distill step 5) just writes `.kiln/roadmap/items/<basename>.md` via `update-item-state.sh` and doesn't need to know the shelf exists. The only coupling point is the shelf workflow name (`shelf:shelf-write-roadmap-note`) being invoked somewhere — and that's impl-roadmap's concern (T020), not mine.
- **One coupling concern I chose to keep loose**: distill does NOT dispatch the shelf workflow on promotion. It only writes the state flip locally. If a user expects their Obsidian copy of the item to reflect `state: distilled`, they need to re-run `/kiln:kiln-roadmap` against the item or `/shelf:shelf-sync` picks it up on the next sync cycle. I think this is correct (keeps distill lean) but it should be called out in a user-facing doc.

## Wasted work

- **Near-zero.** I re-read `shelf-write-issue-note.json` line-by-line before writing `shelf-write-roadmap-note.json`, which was ~5 minutes, but the mirror-pattern payoff was huge (assertions.sh for T042 literally reuses `parse-shelf-config.sh` verbatim and applies the same decision rule in shell).
- The single awkward bit: `extract_body` in `parse-roadmap-input.sh` needed a branch to handle frontmatterless files (vision.md), which I verified with a quick `/tmp` smoke test. Small cost (~2 minutes); catching it pre-test avoided a harness failure on T042/T054 that would have blamed vision handling.

## What would have helped

1. **Unified artifact vocabulary in the briefing.** "Skill" vs "workflow" vs "agent" vs "helper script" are four different things with four different file patterns. The briefing should use the term that matches tasks.md exactly.
2. **Explicit "what NOT to touch" list.** Team-lead gave me "DO NOT edit the kiln-roadmap skill, roadmap templates, or migration scripts" which was perfect. Keep this style.
3. **Contract-first debugging.** When in doubt, `contracts/interfaces.md` was the ground truth. The contract's explicit "path_source MUST be present in every result JSON — one of EXACTLY three literal strings" was worth more than any prose explanation. More of this style of contract writing, please.

## Task completion summary

Phase 3 tasks owned: T040, T041, T042, T043, T044, T045, T046, T047, T048, T049, T050, T051, T052, T053, T054, T055, T056, T058, T060, T062 — all [X].

Commit range: e9cbe31 → HEAD.

Three commits:
1. `e9cbe31` — T040+T041 (shelf helper + workflow JSON, early land for impl-roadmap T020).
2. `52fe6ee` — T043-T050 (distill three-stream + kiln-next active-phase + specify state hook).
3. `b0342a2` — T042 + T051-T056 (7 test fixtures with assertions).

Polish (T058/T060/T062) landed alongside in small edits to CLAUDE.md and tasks.md.
