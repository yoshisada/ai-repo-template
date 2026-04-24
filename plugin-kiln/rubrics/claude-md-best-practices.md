---
source_url: https://code.claude.com/docs/en/best-practices#write-an-effective-claude-md
fetched: 2026-04-24
cache_ttl_days: 30
---

# Write an effective CLAUDE.md — cached Anthropic guidance

Cached copy of the "Write an effective CLAUDE.md" section from Anthropic's Claude Code
best-practices documentation. Consumed by `/kiln:kiln-claude-audit` (FR-014). The audit
attempts a fresh `WebFetch` on each run; on success it may update this file. On failure
(network unreachable, 404, parse error), the audit uses this cached copy and logs
`cache used, network unreachable` (FR-015). If `fetched:` above is older than
`cache_ttl_days` (30), the audit flags cache staleness in the preview (FR-015 +
Clarification #3).

## Verbatim excerpt

CLAUDE.md is a special file that Claude reads at the start of every conversation.
Include Bash commands, code style, and workflow rules. This gives Claude persistent
context it can't infer from code alone.

The `/init` command analyzes your codebase to detect build systems, test frameworks,
and code patterns, giving you a solid foundation to refine.

There's no required format for CLAUDE.md files, but keep it short and human-readable.
For example:

```markdown
# Code style
- Use ES modules (import/export) syntax, not CommonJS (require)
- Destructure imports when possible (eg. import { foo } from 'bar')

# Workflow
- Be sure to typecheck when you're done making a series of code changes
- Prefer running single tests, and not the whole test suite, for performance
```

CLAUDE.md is loaded every session, so only include things that apply broadly. For
domain knowledge or workflows that are only relevant sometimes, use skills instead.
Claude loads them on demand without bloating every conversation.

**Keep it concise.** For each line, ask: *"Would removing this cause Claude to make
mistakes?"* If not, cut it. Bloated CLAUDE.md files cause Claude to ignore your actual
instructions.

### Include vs. exclude

| ✅ Include | ❌ Exclude |
|---|---|
| Bash commands Claude can't guess | Anything Claude can figure out by reading code |
| Code style rules that differ from defaults | Standard language conventions Claude already knows |
| Testing instructions and preferred test runners | Detailed API documentation (link to docs instead) |
| Repository etiquette (branch naming, PR conventions) | Information that changes frequently |
| Architectural decisions specific to your project | Long explanations or tutorials |
| Developer environment quirks (required env vars) | File-by-file descriptions of the codebase |
| Common gotchas or non-obvious behaviors | Self-evident practices like "write clean code" |

### Behavioral tuning

If Claude keeps doing something you don't want despite having a rule against it, the
file is probably too long and the rule is getting lost. If Claude asks questions that
are answered in CLAUDE.md, the phrasing might be ambiguous. Treat CLAUDE.md like code:
review it when things go wrong, prune it regularly, and test changes by observing
whether Claude's behavior actually shifts.

You can tune instructions by adding emphasis (e.g., "IMPORTANT" or "YOU MUST") to
improve adherence. Check CLAUDE.md into git so your team can contribute. The file
compounds in value over time.

### Imports

CLAUDE.md files can import additional files using `@path/to/import` syntax:

```markdown
See @README.md for project overview and @package.json for available npm commands.

# Additional Instructions
- Git workflow: @docs/git-instructions.md
- Personal overrides: @~/.claude/my-project-instructions.md
```

### File locations

CLAUDE.md can live in several locations:

- **Home folder (`~/.claude/CLAUDE.md`)** — applies to all Claude sessions
- **Project root (`./CLAUDE.md`)** — check into git to share with your team
- **Project root (`./CLAUDE.local.md`)** — personal project-specific notes; add to
  `.gitignore` so it isn't shared
- **Parent directories** — useful for monorepos; both `root/CLAUDE.md` and
  `root/foo/CLAUDE.md` are pulled in automatically
- **Child directories** — Claude pulls child `CLAUDE.md` files on demand when working
  with files in those directories

---

## Derived audit checks (FR-014 preview-log deltas)

The `/kiln:kiln-claude-audit` "External best-practices deltas" subsection MUST evaluate
the audited CLAUDE.md against at least these rubric points and emit at least one
finding per run (or an explicit "no deltas found" note when fully compliant):

1. **Length / density** — if the file exceeds ~200 lines OR contains sections the
   guidance explicitly calls out as excludable (file-by-file descriptions, long
   tutorials, self-evident practices), propose trimming with a concrete section
   citation.
2. **Excluded-category drift** — grep for patterns matching the "❌ Exclude" column
   (e.g., API-documentation dumps, frequently-changing info like version numbers,
   file-by-file narration). Flag each as a removal candidate with evidence from the
   audited file.
3. **Included-category gaps** — if the file is missing one of the ✅ Include
   categories that the project demonstrably uses (e.g., repo has a test runner but
   CLAUDE.md has no "Testing" block), propose an addition grounded in the project
   context snapshot (FR-013 currently-installed commands / active phase).
4. **Emphasis hygiene** — flag clusters of `IMPORTANT` / `YOU MUST` bolding that
   exceed five instances per 100 lines (emphasis overuse degrades adherence per the
   guidance).
5. **Import usage** — if the audited CLAUDE.md repeats content that already lives
   in a referenced file (`@README.md`, `@docs/...`), propose replacing the inline
   copy with an `@`-import.

Each finding MUST cite the specific line-range or section of the audited file that
triggered the delta. "No deltas found" is only acceptable when all five checks above
return clean.

---

## Cache refresh protocol (FR-014 / FR-015)

On every `/kiln:kiln-claude-audit` run:

1. Attempt `WebFetch(https://code.claude.com/docs/en/best-practices#write-an-effective-claude-md)`.
2. On success — rewrite this file's body with the freshly-fetched verbatim excerpt
   and bump `fetched:` to today's ISO date.
3. On failure — keep the existing file and log
   `cache used, network unreachable` in the preview log.
4. If `fetched:` is older than `cache_ttl_days` — flag cache staleness in the
   preview even when WebFetch was not attempted.

The audit NEVER edits `CLAUDE.md` itself (FR-016) — only this rubric file and the
`.kiln/logs/claude-md-audit-<ts>.md` preview.
