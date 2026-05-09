# impl-graph friction notes — wheel-viewer-definition-quality

## Decisions made

### Layout library: hand-rolled (NOT dagre)
Followed plan D-1 — hand-rolled topological-rank layered layout, ~280 LOC including
constants and FR-traced comments. No new npm dep. Coverage on `lib/layout.ts`:
**96.48% lines / 100% functions / 77.17% branches** with 24 passing tests.

The 250 KB dagre + lodash transitive cost was the deciding factor. The hand-rolled
algorithm gives us exact control over the team-step fan-in pattern (FR-1.7) and
the expanded sub-DAG offset (FR-1.6) — both are unusual enough that dagre would
have required custom node/edge labelers anyway.

### Branch-target suppression rule (FR-1.3)
Added a rule not explicitly called out in the algorithm sketch but required to
make FR-1.3 ("rejoin point, not orphan columns") actually work:

> A step that is the target of any `if_zero` / `if_nonzero` is reached ONLY via
> the branch routing. Its predecessor's default forward fall-through is
> suppressed.

Without this, sibling branch legs (e.g. `analyze-js` and `fallback-analysis` in
`branch-multi.json`) chain via the natural `i → i+1` default edge, cascading
their ranks. The suppression keeps both legs at the same rank under the branch
step. Documented inline in `lib/layout.ts` (search for `branchTargets`).

### Loop substep model (FR-1.4)
Substeps materialize as nodes with id `<parent>-substep`, ranked one below the
parent loop step. The back-edge (`kind: 'loop-back'`) is excluded from the rank
relaxation so cycles don't push ranks to infinity. The renderer animates this
edge in pink with a `↺` label so the iteration boundary is visually obvious.

### Team-step rendering (FR-2.2, FR-2.3)
Color family for the four team primitives:

| Type | Border / icon color | Rationale |
|---|---|---|
| `team-create` | `#0ea5e9` (sky-500) | Cyan family, slightly cooler than agent purple |
| `team-wait` | `#0ea5e9` (sky-500) | Same as team-create — they're the begin/end pair |
| `team-delete` | `#0369a1` (sky-700, dimmed) | Distinct darker cyan; opacity 0.95 to feel "spent" |
| `teammate` | `#22d3ee` (cyan-400) | Brighter than the team primitives — they're the workers |

Icons (`⊕ ⊞ ⊖ ◐`) come from the unicode geometric block — readable at the small
icon size (18×18) and visually evocative (plus = create, square = block / wait,
minus = delete, half-circle = unit-of-work).

Body fields rendered per type per FR-2.3:
- `team-create`: `team_name`
- `team-wait`: `team` ref + `output` capture path
- `team-delete`: `team` ref + `terminal: true` chip
- `teammate`: `team` + `workflow` + optional `model` + assign-key summary

### Edge kind vocabulary
Renderer chooses visual treatment by `edge.data.kind`:

| Kind | Visual | FR |
|---|---|---|
| `next` | Slate solid | FR-1.1 |
| `branch-zero` | Amber dashed, animated | FR-1.3 |
| `branch-nonzero` | Amber solid, animated | FR-1.3 |
| `skip` | Slate dotted, thin | FR-1.1 |
| `loop-back` | Pink dashed, animated, `↺` label | FR-1.4 |
| `expanded` | Cyan dashed, animated (preserves prior treatment) | FR-1.6 |
| `team-fan-in` | Cyan solid, slightly thicker | FR-1.7 |

## Friction points

### contracts/interfaces.md was the right size
The interface contract was concrete enough (function sigs, type shapes,
algorithm sketch in plan D-1) that I could write `layout.ts` end-to-end without
re-asking questions. The one place I had to make a judgment call —
branch-target suppression — fell out of the test fixture failing on the
"rejoin" case, which was a healthy way to find it.

### Spec-hook block during specifier-still-running window
require-spec.sh blocked all `src/**` writes for ~3 minutes while the specifier
was actively writing tasks.md. I committed the hygiene step (delete
viewer.html) first since it lives under `skills/` — outside the hook's
blocklist — and read contracts/interfaces.md as soon as it landed so the
algorithm design was ready to go when tasks.md unblocked the rest.

### CSS file co-ownership held without conflict
plan D-4 split `viewer.css` between impl-graph (node rules) and impl-shell
(shell rules). Both implementers appended to the bottom of the file — me at
~line 1175 (just above `/* Edge styles */`), impl-shell adding their FR-3 /
FR-5.1 sections at ~line 208. No git merge conflict, no stomping.

### Determinism verification
The "byte-identical output for byte-identical input" requirement (per
contracts/interfaces.md) is exercised by an explicit test (`describe('buildLayout — determinism')`).
No `Date.now` / `Math.random` / `Set` iteration leaks made it into the
algorithm; `Map` iteration follows insertion order which is deterministic in V8.

## What I'd flag for retrospective

- The branch-target suppression rule is non-obvious. It deserves a callout in
  the next PRD's plan if branches keep evolving (e.g. n-way branches, switch).
- Test fixture parameterization (every workflows/tests/*.json validated for
  no-overlap) is the most valuable single test in the suite — caught cases
  the hand-written examples didn't, and made the FR-1.8 invariant cheap to
  defend going forward. Worth replicating in other PR PRD test plans.
