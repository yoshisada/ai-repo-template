# audit-tests friction note

## Surprises / Friction

### F1 — `/kiln:kiln-test` cannot discover the `auto-flip-on-merge-fixture`
Team-lead's directive said "Run `/kiln:kiln-test plugin-kiln auto-flip-on-merge-fixture`
yourself and verify the verdict report shows PASS." When I tried to invoke the harness
runner I confirmed what the implementer flagged in handoff: the live discovery loop in
`plugin-wheel/scripts/harness/wheel-test-runner.sh` (lines ~135-144) only enrolls a test
directory if it contains `test.yaml`. There is no `run.sh`-only fallback in the runner
even though `plugin-kiln/skills/kiln-test/SKILL.md` advertises one. So the canonical
verification path I was asked to walk does not exist in the substrate today.

I substituted the next-best-substrate per the cited hierarchy:
- **Substrate #2 — direct bash run.sh** of `plugin-kiln/tests/auto-flip-on-merge-fixture/run.sh`
  → printed `PASS` with exit 0; both first-run (items=3 patched=3 already_shipped=0) and
  idempotent re-run (items=3 patched=0 already_shipped=3) byte-diffs are clean.
- **Cross-substrate corroboration** — `plugin-kiln/tests/build-prd-auto-flip-on-merge/run.sh`
  → 27/27 PASS, confirming the FR-009 refactor of Step 4b.5 in
  `plugin-kiln/skills/kiln-build-prd/SKILL.md` is zero-behavior-change.

This substrate gap is itself a candidate for a follow-on PRD (kiln-test should grow a
`run.sh`-only branch, or the docs should retract that capability claim).

### F2 — T038 structural grep would fail by literal reading; semantic intent met
T038 specs `grep -c '^### Stage' plugin-kiln/skills/kiln-merge-pr/SKILL.md` ≥ 6. The
shipped skill uses `## Stage` (level-2 headings), so the literal grep returns 0. The
semantic intent — six staged sections, each with a diagnostic line — IS satisfied
(`grep -c '^## Stage'` returns 6). I treated this as a non-blocking deviation rather than
a test failure because:
- The test was an authoring sanity-grep, not a runtime gate.
- The 6 stages exist; their FR mappings, diagnostic literals, and idempotency notes are
  all present.
- No downstream consumer parses by `^### Stage`.

Worth noting in a retro PI: tasks should anchor on a heading shape that the contract
itself fixes (the contracts/interfaces.md §B.1 example uses `## Stage`), not a stricter
shape introduced only in tasks.md.

### F3 — Five tasks left unchecked despite work being done
T060, T061, T062 (impl-roadmap-and-merge friction-note + commit + handoff) and T070, T071
(impl-docs read-only orientation) are still `[ ]` in tasks.md. Verified the substantive
deliverables exist:
- `agent-notes/impl-roadmap-and-merge.md` on disk.
- Commit `3e679602` matches T061's prescribed message ("chore(specs): impl-roadmap-and-merge friction note + tasks.md [X] marks + T013a fixture conformance").
- The handoff message I'm responding to is literally T062.
- T070-T071 are read-only orientation; nothing on disk to inspect.

Procedural box-tick miss, not actual incomplete work — flagged to team-lead.

### F4 — SC-005 second-grep ugrep parsing collision
When I ran `grep -F "--since='YYYY-MM-DD'" ...` to verify SC-005's recipe substring,
the system's `ugrep`-aliased grep parsed `--since=...` as an option and errored. This
is an environment-specific tooling quirk, not a test or implementation defect. The
recipe text IS present (verified via `grep -F -- "--since='YYYY-MM-DD'"` and a manual
file inspection — the canonical recipe block is in `plugin-kiln/templates/spec-template.md`).

If SC-005 is wired into a CI sentinel as written, the `--` separator should be added
to the asserter to keep the SC stable across grep variants.

## Recommended PIs

- **PI-1** (priority high): kiln-test harness should grow a `run.sh`-only test
  fixture branch matching what `plugin-kiln/skills/kiln-test/SKILL.md` already
  documents. Either implement the branch or retract the documented capability.
- **PI-2** (priority med): tasks.md authoring rule — "structural greps in tests
  MUST anchor on the same heading shape the contracts/interfaces.md example
  uses; tasks MUST NOT introduce a stricter regex than the contract". Avoids
  repeating the T038 false-failure shape.
- **PI-3** (priority low): SC-grep recipes that contain `--<flag>=...` patterns
  should ship with `--` separators in their asserter examples to defend against
  grep variants that parse aggressively.
