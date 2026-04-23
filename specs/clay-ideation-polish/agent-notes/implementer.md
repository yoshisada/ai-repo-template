# Implementer Notes — Clay Ideation Polish

**Date**: 2026-04-22
**Model**: Opus 4.7 (team implementer agent)
**Branch**: `build/clay-ideation-polish-20260422`

## What worked well

- **Contracts/interfaces.md was load-bearing in the best way.** The four helper idioms (`is_parent_product`, `list_sub_ideas`, `read_frontmatter_field`, `--parent=` parser) are small enough to inline everywhere they're needed, and having them pinned in one file meant I could copy-paste the exact bash into each skill without drift between copies. Specifier did great work there.
- **Decision 1 (filesystem-only parent detection)** is easy to implement and easy to reason about. Zero schema changes for existing `about.md` files.
- **Decision 2 (missing intent → marketable)** is the right default. Every downstream skill just runs the standard code path when the frontmatter is absent; no new "legacy product" branch needed.
- **Phase-per-commit cadence** plus phase-level checkboxes made it easy to stay oriented. The 17 sub-tasks broke down cleanly.

## Where the PRD / plan underspecified and I had to interpret

### 1. Parent row status in `/clay:clay-list`

The plan says sub-rows use the same status-derivation logic as flat products, but doesn't say what to show in the parent row's Status / Artifacts columns. I rendered parent rows with `—` for both (the parent has no PRD files of its own; its "status" is derived from its children). This is called out in the updated example table. An auditor may want to confirm this matches intended UX.

### 2. Parent row repo-URL display when shared-repo exists

Similar gap: once a shared repo exists for a parent, the parent row in `/clay:clay-list` could show either the shared repo URL or `—`. I opted for "show the shared URL on the parent row; show `(shared: <parent>)` on each sub-row" because it avoids repeating the URL three times and makes the sharing relationship legible. Again, open to UX tweak.

### 3. Intent prompt text

PRD says "prompt for intent" but doesn't pin the exact wording. I wrote a 3-bullet user-facing prompt with the same label convention used elsewhere in clay. If the project has a house style, this may need polish.

### 4. `$SLUG` threading through `clay-idea`

Step 2.8 re-points `SLUG="$PARENT_SLUG/$SUB_SLUG"` so downstream routing targets the nested path. This works for the bash `mkdir -p products/$SLUG` and `$IDEA_FILE` semantics, but I didn't trace every code path below Step 4 to make sure no downstream step assumes `$SLUG` is flat. Leaving as an auditor check.

### 5. Where did the "sibling parent" option send the user?

Step 2.7 offers "sibling parent (different top-level slug)" as one of three collision-resolution options. My implementation re-prompts for a top-level slug and treats the idea as a brand-new flat product. But the spec only says "Create a different top-level slug" — did it mean "start over entirely with a new name" (my interpretation) or "create another parent next to the existing one" (a separate interpretation)? I went with the simpler reading.

## Where plan.md's decisions were tight but I'd flag for an auditor

### Decision 1 false-positive risk

The plan calls the false-positive risk "extremely narrow" and that's true for this plugin repo today, but at scale a flat product with one `about.md` plus a stray sub-folder that happens to contain an `idea.md` (e.g., someone put a design sketch there) WILL trigger the predicate. If that user then runs `/clay:clay-idea` and hits the collision prompt, the "sibling parent" and "abort" options are available — so the worst case is UX confusion, not data loss. Still, noting it.

### Decision 3 and the `intent:` on parents

Decision 3 says `parent:` is forbidden on parent products and flat top-level products. Good. But it doesn't say whether a parent's `about.md` should carry an `intent:` field. My read: no, because the parent itself isn't a product you build — each sub-idea has its own intent. Specifier-level decision; calling out in case an auditor disagrees.

## Cross-skill coupling that was harder than expected

### Phase D (clay-create-repo) was the biggest mental-load phase

Team lead's warning was right — D1/D2/D3 all touch the same file and overlap conceptually. I did them in one continuous edit pass: Step 1a (detect sub-idea), Step 1b (shared-repo prompt), Step 1c (URL resolution), plus the Step 3 / Step 5 / Step 7.5 / Step 8 branches that diverge on `SHARED_REPO_CHOSEN`. The result is a skill body with four distinct "sub-idea + shared repo" branches living alongside the original flat-product paths. It works, but the skill is now noticeably denser. A follow-on PRD could factor some of this into a preamble helper.

### `clay-idea` has two parallel classification steps now

Step 2.5 (intent) and Step 2.7 (parent collision) are independent — a user answering `internal` intent can still be asked about a parent collision on the next step. That's correct, but it's worth noting that a sub-idea under a parent is not automatically internal; we prompt for intent fresh per sub-idea per Decision 3. This is what Decision 3 specifies, but it does mean two round-trips happen before the user sees the overlap analysis result. If user feedback complains, the mitigation is to reorder: prompt for intent AFTER the sub-idea selection, not before.

## Auditor handoff

All 17 tasks in `tasks.md` are `[X]`. Each phase has its own commit:

- Phase A: `0885aac`
- Phase B: `5b80c84`
- Phase C: `25f0724`
- Phase D: `ce49447`
- Phase E: (this commit)

No `src/` edits occurred (skill-body only), so no hook gates were exercised beyond the VERSION auto-increment which is working as intended.

Smoke results are in `smoke-results.md` (static code-path walkthrough per fixture). Live slash-command runs are the user's pre-merge check, captured in `SMOKE.md`.

## One flag I want to surface

I did NOT introduce a `--intent=` CLI flag anywhere, and I pushed back on any temptation to do so. Per the team-lead brief this would be an FR-001 violation. `/clay:clay-idea` always prompts for intent — no bypass.
