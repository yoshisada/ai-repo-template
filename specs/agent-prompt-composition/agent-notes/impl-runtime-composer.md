# impl-runtime-composer friction note (FR-009)

## Substrate citations (per §Implementer Prompt rule, tier-2 — direct `bash` invocation)

All five Theme A fixtures pass end-to-end via `bash plugin-{wheel,kiln}/tests/<name>/run.sh`:

| Fixture | SC | Exit | Last line |
|---|---|---|---|
| `plugin-wheel/tests/compose-context-shape/run.sh` | SC-3, NFR-6 | 0 | `PASS: compose-context-shape — JSON shape, sorting, determinism, exit codes 2/3/6 all OK` |
| `plugin-wheel/tests/validate-bindings-unknown-verb/run.sh` | SC-4 | 0 | `PASS: validate-bindings-unknown-verb — exit 4 on bad verb, 0 on valid/empty, 1 on malformed/missing` |
| `plugin-wheel/tests/compose-context-unknown-override/run.sh` | SC-5 | 0 | `PASS: compose-context-unknown-override — exit 5 on unknown-agent, exit 4 on unknown-verb, override+merge semantics correct` |
| `plugin-kiln/tests/research-first-agents-structural/run.sh` | SC-6 | 0 | `PASS: research-first-agents-structural — all 3 agents conform to FR-A-10/FR-A-11` |
| `plugin-kiln/tests/claude-md-architectural-rules/run.sh` | SC-8 | 0 | `PASS: claude-md-architectural-rules — all 12 canonical phrases present in CLAUDE.md` |

The kiln-test substrate (B-1 substrate gap noted in spec.md "Constraints") was not used for these fixtures because they're shell-only with no skill-execution path. Direct `bash` invocation matched the dominant wheel-test/kiln-test convention.

## T-A-09 audit divergence note

The pre-existing `plugin-kiln/agents/research-runner.md` carried (a) a verb-bindings table inside the body, (b) explicit tool references like ``scoped to `Read, Bash, SendMessage, TaskUpdate, TaskList` only``, (c) a numbered step-by-step task protocol (steps 1–6), and (d) a "Hard constraints" section enumerating what tools the agent must NOT use by name. All four are FR-A-11 violations. The body was rewritten in-place to be pure role identity: who the role is, what it reads off the runtime-injected context, what it produces, and the read-only/no-retry boundaries — but the prose now describes the role abstractly rather than enumerating verbs/tools/steps. The frontmatter (`name`, `description`, `tools` allowlist matching the spec, no `model`) was already conformant and was preserved.

## Friction observations — unified-PRD framing (Theme A + Theme B in one PRD)

**Where the unified framing helped**:

- **Single contracts file (`contracts/interfaces.md`)** with seven sections covering both themes meant I didn't have to chase a sibling PRD for the directive grammar. When my SC-3 fixture references the coordination-protocol stanza, I read §1 (Theme B directive grammar) and §5 (Theme A per-shape stanza format) side-by-side to confirm the two contracts compose cleanly.
- **Shared CLAUDE.md updates** under one Theme A owner (CLAUDE.md is in Theme A's column per spec.md "Theme Partition") prevented the merge-conflict trap of two parallel implementers both editing the same file. I authored the FR-A-12 rules + FR-B-8 directive aside + composer integration recipe in one coherent section. Theme B doesn't need to touch CLAUDE.md at all.
- **Spec.md "Theme Partition" table as a pre-resolved file-conflict contract** meant zero coordination time during work. The cross-track dep — Theme A's composer reads Theme B's `_shared/coordination-protocol.md` — is handled in fixtures by a self-stub that activates ONLY when Theme B hasn't shipped the file yet, and cleans up after itself. No write conflict.

**Where the unified framing hurt** (or required deliberate working-around):

- **Theme A's scope is meaningfully larger than Theme B's.** Theme A owns: composer (~200 lines after debugging two jq scoping bugs), validator, 8 task-shape stanzas, 3 agent.md files (1 audit + 2 new), plugin manifest extension, 5 test fixtures, and the CLAUDE.md Architectural Rules section. Theme B owns: resolver (~80 lines), 1 shared module, build script, CI gate, 3 agent refactors, 2 test fixtures. Roughly a 60/40 split. Under a separate-PRD framing, Theme A would have arrived as its own 2-week-long item; bundling it with Theme B compressed both into one pipeline with one auditor, but the auditor's work scales with the larger theme, not the smaller. **If we re-run the experiment, sizing the bundled PRDs by total surface (not by "they compose") is the right discipline** — the composition story would survive even if Theme B shipped first as its own PRD and Theme A followed referencing it as a dep.
- **Cross-track stub for `_shared/coordination-protocol.md` was friction.** My fixtures need that file at a hardcoded path (composer reads it). Theme B owns authorship per NFR-8 disjoint partition. To avoid blocking on Theme B's commit cadence I built a self-stub-and-cleanup into both compose-context fixtures (compose-context-shape and compose-context-unknown-override). This is robust but adds ~10 lines per fixture. Under a sequenced Theme-B-first framing the stub wouldn't be needed; under a parameterized-composer (`--coord-proto-path`) framing it also wouldn't be needed but the composer's API surface would grow. I chose the stub because the parameterization is YAGNI-violating (per NFR-3 backward compat the composer is opt-in already; consumers don't choose alternate paths).

**jq scoping bug worth a follow-on**: `$allowed | index(.key)` and `$allowed | index(.)` both silently misbehave when `.` is a string from a prior `keys[]` because `index()` re-binds input to its argument's left-hand side, not the outer `.`. The fix is to bind to a named variable with `keys[] as $v`. Two of my filters had this bug; I caught both via the manifest validation smoke test before fixtures were written. Filing this as a friction observation because a second implementer hitting the same trap would lose time — the jq error message ("Cannot index array with string 'key'") is unhelpful unless you know the scoping rule.

## What I'd change for the next pipeline of this shape

1. Pre-build a `plugin-wheel/tests/_shared/stub-coord-proto.sh` helper that any cross-track fixture can `source` — DRY across the two fixtures that needed it.
2. Add the jq scoping rule to `plan.md` Phase 0 as a cited gotcha so future implementers don't re-hit it.
3. Either bundle PRDs by total surface OR ship a "Theme Partition" sizing column showing rough LOC/file-count split so the orchestrator can call out asymmetry early.
