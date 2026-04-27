# Specifier friction notes — vision-tooling

Notes captured while running `/kiln:specify` → `/kiln:plan` → `/kiln:tasks` for the vision-tooling PRD on 2026-04-27.

## What was confusing or ambiguous

### 1. PRD FR-001 mixes append-bullet and append-paragraph semantics under the same flag-set

**PRD quote (FR-001)**: *"--add-constraint, --add-non-goal, --add-success-signal, --add-mission, --add-out-of-scope (atomic temp+mv append). Each appends a new bullet to the named section atomically (temp + mv)."*

**Friction**: PRD says "appends a new bullet" universally, but the target sections of `--add-mission` (`## What we are building`) and `--add-out-of-scope` (`## What it is not`) are PROSE in the current `.kiln/vision.md`, not bullet lists. Strictly applying "new bullet" to these sections would inject `- foo` into prose, producing structurally broken markdown.

**How resolved**: Plan §1.1 + spec FR-021 + Assumption-3 carve out per-flag operation semantics: `append-bullet` for the bullet sections, `append-paragraph` for the prose sections. PRD FR-001 isn't contradicted because it doesn't specify bullet-semantics-for-prose; it says "appends a new bullet to the named section" and the canonical interpretation in this V1 is that the flag appends a new entry under the named section in whichever shape the section uses. Plan documents this explicitly via the section-flag-mapping table (FR-021).

**PRD/skill suggestion**: Future PRDs that target sections with mixed shape (prose vs bullet vs replace) should call out per-section operation in a table at the FR level rather than the generic "appends a new bullet" prose. A small FR-text amendment like *"Each appends a new entry (bullet for bullet-shaped sections; paragraph for prose-shaped sections; see FR-021 mapping table)"* would have eliminated the friction.

### 2. PRD `--add-non-goal` vs `--add-out-of-scope` overlap

**PRD quote (FR-001)**: lists both `--add-non-goal` and `--add-out-of-scope`.

**Friction**: Both target the *What it is not* section. Without a disambiguator, an implementer would reasonably ask "are these synonyms? Should one error out?". The PRD doesn't say. The spec resolved it via the section-flag-mapping table (`--add-non-goal` = bullet form for terse capture; `--add-out-of-scope` = paragraph form), but this is a guess at maintainer intent.

**PRD/skill suggestion**: When a PRD lists multiple flags targeting the same section, include a one-line rationale per flag explaining when to use which. Or, alternatively, pick one and drop the other. The current 5-flag append set could plausibly be 4 flags (mission, constraint, non-goal-or-out-of-scope, success-signal) without losing capture power.

### 3. PRD `derived_from:` parsing brittleness in /specify hook

**Friction**: The roadmap-item state-flip hook in step 7a of the specify skill uses an awk script that, per the original spec text, has a stop-condition (`/^[^[:space:]-]/`) which incorrectly terminates the list when continuation lines begin with whitespace. On this PRD's frontmatter (4 derived_from items), the awk emitted only the first item. I had to write a corrected awk locally to extract all four items and run the state flip. The hook DID succeed — `update-item-state.sh` flipped all four items to `state: specced` — but only because I noticed the parse was incomplete and bypassed the embedded awk.

**PRD/skill suggestion**: The specify-skill awk in step 7a needs a fix:

```awk
# Current (buggy): stops on first non-space line OR list continuation
in_df && /^[^[:space:]-]/ { in_df = 0 }

# Replacement: stop only on a non-list-item (any line not starting with whitespace)
in_df {
  if (/^[[:space:]]+-[[:space:]]+\.kiln\/roadmap\/items\//) { sub(...); print; next }
  if ($0 !~ /^[[:space:]]/) { in_df = 0 }
}
```

File a `/kiln:kiln-mistake` against the specify skill hook script — this is exactly the kind of silent-pass-with-incomplete-output failure that the WORKFLOW_PLUGIN_DIR canary in CLAUDE.md guards against in other contexts.

### 4. Phase 1.5 "research-first plan-time agents" boilerplate when probe = skip

**Friction**: The plan-skill outline ships ~150 lines of Phase 1.5 instructions. For PRDs without `needs_research:` / `fixture_corpus:` / `empirical_quality:` frontmatter (like this one), the entire phase is a no-op, but the boilerplate is still rendered into context. The plan template doesn't have a Phase-1.5 placeholder, so the implementer has to remember to write a single-sentence "skipped" note rather than letting the skill emit nothing.

**PRD/skill suggestion**: The plan skill could emit a frontmatter probe earlier and only render the Phase-1.5 boilerplate when `ROUTE != skip`. This would shave context cost for the common case (most PRDs don't declare research-first frontmatter).

### 5. tasks-template.md has stale sample tasks

**Friction**: The `.specify/templates/tasks-template.md` file contains illustrative-only sample tasks ("Create User model", "Implement authentication middleware") with a comment saying "DO NOT keep these sample tasks." This works fine when the implementer reads the comment, but the format-validation rules later in the skill prompt include the sample tasks as "correct examples." A literal-minded LLM could keep "Create User model in src/models/user.py" in the final tasks.md.

**PRD/skill suggestion**: Replace the sample tasks in the template with `<!-- TASKS GO HERE -->` and put the format examples ONLY in the prompt instructions — not in the template file itself.

## What went smoothly

- PRD scope was crisp: 4 themes, 19 FRs, 5 NFRs, 10 SCs, 7 explicit Non-Goals — no ambiguity about what's in/out for V1.
- The contract surface (14 helpers + 2 skill orchestrators) decomposed cleanly along FR boundaries, so contracts/interfaces.md was straightforward to write.
- NFR-005 fixture-capture ordering (R-4 mitigation) was already called out in the PRD itself, which made T001 sequencing obvious.
- PRD's Non-Goals section is well-written: every "NOT X" was matched in the spec to either a deferred-V2 stub or an explicit constraint.
- The 4-gate hook, Constitution Articles I/II/VII/VIII, and CLAUDE.md Rules 1–6 are all consistent with the plan's helper-script + per-FR-test substrate — no friction at the architecture level.

## Net suggestions

1. **Specify-skill awk fix** (most impactful — silent data loss in the state-flip hook).
2. **PRD authoring guidance** for mixed-shape section targets (prose vs bullet) — add a section-shape table to the PRD template.
3. **Plan-skill Phase-1.5 conditional rendering** to reduce token cost for non-research-first PRDs.
4. **tasks-template.md sample-task removal** — replace with a placeholder marker.
5. **PRD authoring guidance** on overlap-free flag sets — when multiple flags target the same section, document the disambiguator inline.
