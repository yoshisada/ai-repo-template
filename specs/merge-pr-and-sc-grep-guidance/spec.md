# Feature Specification: Merge-PR Skill + Spec-Template SC-Grep Guidance

**Feature Branch**: `build/merge-pr-and-sc-grep-guidance-20260427`
**Created**: 2026-04-27
**Status**: Draft
**Input**: PRD `docs/features/2026-04-27-merge-pr-and-sc-grep-guidance/PRD.md` (3 themes / 16 FRs / 5 NFRs / 7 SCs)

## User Scenarios & Testing *(mandatory)*

Three themes ship together because each removes one rediscovery cycle in the build-prd substrate. Theme A is concrete code (new skill + extracted helper + extended `--check`) and is the highest-leverage of the three. Themes B and C are documentation edits inside two authoring surfaces (kiln spec-template and wheel preprocess + README).

### User Story 1 — `/kiln:kiln-merge-pr <pr>` merges and auto-flips atomically (Priority: P1) 🎯 MVP

When the maintainer is ready to merge a PR that `kiln-build-prd` shipped, they invoke `/kiln:kiln-merge-pr 189` instead of `gh pr merge 189`. The skill gates on PR mergeability, runs `gh pr merge`, waits for the `MERGED` state, locates the PRD via `gh pr view <pr> --json files`, and invokes the shared `auto-flip-on-merge.sh` helper against the PRD's `derived_from:` list. Roadmap items flip in-place, get committed, and pushed — with zero manual intervention. The async-merge gap that PR #186 and PR #189 both hit is closed by construction.

**Why this priority**: This is the highest-leverage of the three themes. Step 4b.5 already exists and works inside an active pipeline; the gap is purely temporal — pipeline ships, team-lead shuts down, maintainer merges later, auto-flip never fires. `/kiln:kiln-merge-pr` makes "merge and flip" one indivisible operation triggered by the maintainer's natural action (the merge itself). MVP because the rest of the PRD's value depends on this skill existing.

**Independent Test**: Stub `gh pr view <pr> --json state,mergeable,mergeStateStatus` to return `{state: "OPEN", mergeable: "MERGEABLE", mergeStateStatus: "CLEAN"}`, stub `gh pr merge` to print success and stub the post-merge `gh pr view <pr> --json state` to return `{state: "MERGED"}`, stub `gh pr view <pr> --json files` to include a PRD path, scaffold a fixture PRD with three `derived_from:` items, run `/kiln:kiln-merge-pr <stub-pr>`, then assert: (a) all three items end at `state: shipped`/`status: shipped`/`pr: <stub>`/`shipped_date: <today>`, (b) the canonical diagnostic line `step4b-auto-flip: pr-state=MERGED auto-flip=success items=3 patched=3 already_shipped=0 reason=` is emitted byte-for-byte, (c) a roadmap-flip commit exists with the canonical message.

**Acceptance Scenarios**:

1. **Given** an open, mergeable PR `<N>` whose changeset includes one PRD with three `derived_from:` items, **When** the maintainer runs `/kiln:kiln-merge-pr <N>`, **Then** the merge completes via `gh pr merge <N> --squash --delete-branch`, the post-merge `gh pr view <N> --json state` returns `MERGED`, the helper flips all three items, and the diagnostic line `step4b-auto-flip: pr-state=MERGED auto-flip=success items=3 patched=3 already_shipped=0 reason=` is printed.
2. **Given** the same scenario with `--merge` instead of the default `--squash`, **When** the skill runs, **Then** `gh pr merge` is invoked with `--merge --delete-branch` (flag is propagated; default is `--squash`).
3. **Given** a PR whose `gh pr view` returns `state: CLOSED` (already closed without merge), **When** the skill runs, **Then** the mergeability gate refuses the merge, surfaces `state=CLOSED`, exits non-zero, and does NOT run the auto-flip stage.
4. **Given** an already-merged PR `<N>` (re-invocation), **When** the skill runs, **Then** the mergeability gate detects `state: MERGED`, skips the merge step, still runs the auto-flip stage, and emits `step4b-auto-flip: pr-state=MERGED auto-flip=success items=N patched=0 already_shipped=N reason=` (idempotent — NFR-001).
5. **Given** a merged PR whose changeset has zero `docs/features/*/PRD.md` files, **When** the skill runs, **Then** auto-flip is skipped and the diagnostic line `kiln-merge-pr: pr=<N> auto-flip=skipped reason=no-prd-in-changeset` is emitted (FR-004); exit code is 0 (the merge succeeded).
6. **Given** the maintainer passes `--no-flip`, **When** the skill runs, **Then** the merge runs but the auto-flip stage is skipped entirely; the diagnostic line is `kiln-merge-pr: pr=<N> auto-flip=skipped reason=--no-flip` (FR-007).
7. **Given** the working tree has unrelated uncommitted changes at invocation, **When** the skill reaches the post-flip commit step, **Then** it refuses to commit, surfaces the changes via `git status`, and exits non-zero — never running `git add -A` (FR-006, NFR-005).

---

### User Story 2 — Step 4b.5 inline block extracted to shared helper (Priority: P1)

The 80-line inline Bash block at Step 4b.5 in `plugin-kiln/skills/kiln-build-prd/SKILL.md` is extracted verbatim into `plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh`. Step 4b.5 becomes a single-line invocation of the helper. `/kiln:kiln-merge-pr` calls the same helper. `/kiln:kiln-roadmap --check --fix` calls the same helper. One implementation, three call sites.

**Why this priority**: Without the extraction, every call site (Step 4b.5, the new merge-pr skill, the new `--check --fix` mode) reimplements the same frontmatter-mutation logic — three drift surfaces that must stay byte-compatible forever. The extraction is the load-bearing prerequisite for User Story 1 and User Story 3 to share semantics. P1 because both downstream stories depend on the helper existing.

**Independent Test**: Run the regression fixture `plugin-kiln/tests/auto-flip-on-merge-fixture/run.sh` — scaffolds a snapshot of the pre-merge state of PR #189's three derived_from items + the PR #189 PRD, invokes `bash plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh 189 docs/features/2026-04-26-escalation-audit/PRD.md` against the snapshot, and asserts the post-flip files are byte-for-byte identical to the post-merge state observed in commit `22a91b10`. Re-run the helper; assert no further mutation (idempotency).

**Acceptance Scenarios**:

1. **Given** a fresh checkout, **When** `git diff plugin-kiln/skills/kiln-build-prd/SKILL.md` is inspected after the FR-009 refactor lands, **Then** the previous Step 4b.5 inline Bash block is removed and replaced by a single-line `bash plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh "$PR_NUMBER" "$PRD_PATH"` invocation; the file's `wc -l` strictly decreases.
2. **Given** the helper is invoked against a fixture matching pre-merge state of PR #189, **When** `bash plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh 189 <prd>` runs, **Then** each of the PR #189 derived_from items ends with the exact frontmatter observed in commit `22a91b10` (`pr: 189`, `shipped_date: 2026-04-26`, `state: shipped`, `status: shipped`) — verified by byte-for-byte `diff` against snapshot golden files (NFR-002).
3. **Given** the helper is invoked a second time against the post-flip state, **When** the helper runs, **Then** the diagnostic line emits `items=N patched=0 already_shipped=N` and zero file mutations occur (FR-008 idempotency, verified by `git diff` returning empty).
4. **Given** the helper is invoked against a PRD whose `derived_from:` references a path that does NOT exist on disk, **When** the helper runs, **Then** the missing entry is logged but the helper does NOT abort — matching Step 4b.5's existing `MISSING_ENTRIES` branch (zero-behavior-change extraction).
5. **Given** the helper's diagnostic line is captured, **When** compared to Step 4b.5's pre-extraction output for the same inputs, **Then** the lines are byte-for-byte identical (the verification regex `^step4b-auto-flip: pr-state=(MERGED|OPEN|CLOSED|unknown) auto-flip=(success|skipped) items=[0-9]+ patched=[0-9]+ already_shipped=[0-9]+ reason=[a-z-]*$` matches both forms).

---

### User Story 3 — `/kiln:kiln-roadmap --check --fix` confirm-never-silent drift fix (Priority: P2)

When the maintainer runs `/kiln:kiln-roadmap --check --fix`, drifted items detected by the existing `--check` (Check 5: merged-PR drift) are presented as a confirm-never-silent list with `[fix all / pick / skip]` options. On `fix all` or per-item accept, the shared `auto-flip-on-merge.sh` helper is invoked for each accepted entry. On `skip` or empty input, no writes happen.

**Why this priority**: User Story 1 catches NEW merges going through `/kiln:kiln-merge-pr`; User Story 3 catches OLD drift (items merged via the GitHub web UI before `/kiln:kiln-merge-pr` shipped, or items merged via `gh pr merge` directly without using the new skill). Without it, the cleanup-cost trap stays open for any merge that bypasses `/kiln:kiln-merge-pr`. P2 because manual `update-item-state.sh` invocations remain available.

**Independent Test**: Synthesize a drifted item by reverting a known-shipped item from `state: shipped` → `state: distilled` (and stripping `pr:` + `shipped_date:`); stub `gh pr list --state merged --search "head:<branch>"` to return one match; run `/kiln:kiln-roadmap --check --fix` with stubbed user input `accept`; assert the item flips back to `state: shipped` + `pr: <N>` + `shipped_date: <today>` and the report emits `fix=success items=1`. Repeat with stubbed input `skip`; assert `git diff` is empty.

**Acceptance Scenarios**:

1. **Given** the maintainer runs `/kiln:kiln-roadmap --check` (no `--fix`), **When** the skill executes, **Then** behavior is byte-identical to pre-FR-010 — drift is detected and reported, no prompts appear, no writes happen, exit semantics are unchanged (FR-010 backward-compat / NFR-005).
2. **Given** the maintainer runs `/kiln:kiln-roadmap --check --fix` and the report contains three drifted items, **When** the skill prompts `[fix all / pick / skip]`, **Then** the three items are listed with their `prd:`, resolved PR number, and current state.
3. **Given** the maintainer responds `fix all`, **When** the skill executes, **Then** `auto-flip-on-merge.sh <pr> <prd>` is invoked once per drifted item and the report emits `fix=success items=3 patched=3` (or `already_shipped=K` for any race-condition entries).
4. **Given** the maintainer responds `skip` or sends empty input, **When** the skill exits, **Then** zero file mutations occur (verified by `git diff` returning empty) — confirm-never-silent rule (NFR-004).
5. **Given** a drifted item whose `gh pr list --state merged --search "head:<feature-branch>"` returns zero PRs OR multiple PRs, **When** the skill processes the drift list, **Then** that single item is surfaced as ambiguous and skipped (the helper is NOT invoked) — implementer MUST NOT guess (FR-011).
6. **Given** the maintainer responds `pick`, **When** the skill iterates, **Then** the user is prompted per-item with `[accept / skip]`, and only accepted entries are flipped.

---

### User Story 4 — Spec-template SC-grep date-bound authoring note (Priority: P2)

`plugin-kiln/templates/spec-template.md`'s Success Criteria section gains an authoring note + recipe that advises future PRD authors to include a date or commit cutoff when writing grep-style success criteria against directories with historical state (`.wheel/history/`, `archive/`, `migrations/`). The note also recommends the substantive alternative: express the SC against a fresh artifact produced by a consumer-install simulation rather than against historical state.

**Why this priority**: Authoring guidance only — touches one template file. P2 because the cost is low and the rediscovery is recurring (cross-plugin-resolver hit it; future PRDs will hit it again). Higher than P3 because every distilled PRD reads this template.

**Independent Test**: `grep -F 'date-bound qualifier' plugin-kiln/templates/spec-template.md` returns ≥ 1 match AND a recipe code-fence in the template contains the literal string `--since='YYYY-MM-DD'`.

**Acceptance Scenarios**:

1. **Given** the spec-template is opened by a future PRD author, **When** they reach `## Success Criteria *(mandatory)*`, **Then** they see an authoring note labeled "Grep-style SCs against historical state" that explains the failure mode (pre-PRD historical noise auto-flags) and provides the canonical recipe.
2. **Given** the recipe block, **When** rendered, **Then** it contains a code-fence with at least one canonical form: `git log --name-only --pretty='' --since='YYYY-MM-DD' -- '<glob>' | sort -u | xargs -I{} git grep -lE '<pattern>' -- {}`.
3. **Given** the authoring note, **When** read end-to-end, **Then** it explicitly recommends the substantive alternative — express the SC against a fresh artifact produced by a consumer-install simulation rather than a directory-wide scan (FR-013).

---

### User Story 5 — Wheel preprocessor + README documentary-references rule (Priority: P2)

`plugin-wheel/lib/preprocess.sh` gains a module-level comment documenting the "documentary references trip the tripwire" gotcha; `plugin-wheel/README.md` gains a "Writing agent instructions" section with the same rule in author-facing language; the FR-F4-5 tripwire's error text is extended to point at the explanation directly. Future workflow authors see the rule on first violation rather than rediscovering it mid-migration.

**Why this priority**: Documentation only — three surfaces, all author-discoverable. P2 because the rediscovery cost is concrete (cross-plugin-resolver cycle) and the failure mode tripped the SC-F-6 archive grep too.

**Independent Test**: `grep -lF 'documentary' plugin-wheel/lib/preprocess.sh plugin-wheel/README.md` returns BOTH paths AND the FR-F4-5 tripwire path testing the rendered error contains the literal string `If you intended this as documentary text, rewrite as plain prose; the tripwire fires on the prefix pattern even with $$ escaping.`.

**Acceptance Scenarios**:

1. **Given** a future workflow author opens `plugin-wheel/lib/preprocess.sh`, **When** they read the module-level comment block, **Then** they see a section that names BOTH failure modes (FR-F4-5 prefix-pattern fires on grammar variants the substitution regex skips; `$$` escaping survives the tripwire but lands in archives where SC-F-6 grep trips it) and recommends plain-prose substitution that does NOT reproduce the token grammar (FR-014).
2. **Given** a future workflow author reads `plugin-wheel/README.md`, **When** they look at the table of contents (or top-level headings), **Then** they discover a "Writing agent instructions" section (or extension of the existing workflow-authoring section) that contains the same rule in author-facing language (FR-015).
3. **Given** an author trips the FR-F4-5 tripwire by accident, **When** the tripwire fires, **Then** the error text now contains the line `If you intended this as documentary text, rewrite as plain prose; the tripwire fires on the prefix pattern even with $$ escaping.` — directing the reader to the explanation on first violation (FR-016).

---

### Edge Cases

- **PR is unmergeable** (`mergeStateStatus: BEHIND` / `DIRTY` / `BLOCKED`): `/kiln:kiln-merge-pr` refuses, surfaces the reason, exits non-zero, does NOT attempt the merge.
- **`gh` CLI unavailable / not authenticated**: `/kiln:kiln-merge-pr`'s pre-flight gate (FR-002) fails fast with a diagnostic; auto-flip stage never runs. Mirrors Step 4b.5's `gh-unavailable` degraded branch.
- **PRD `derived_from:` is empty / missing**: helper emits `step4b-auto-flip: ... auto-flip=skipped ... reason=no-derived-from`; matches existing Step 4b.5 behavior byte-for-byte.
- **Helper invoked with `<pr-number>` that contains a leading `#`**: helper accepts both `#189` and `189` forms (matches Step 4b.5's `^pr:[[:space:]]*#?${PR_NUMBER}\b` idempotency check).
- **Multiple PRDs in one PR's changeset**: FR-004 specifies "first matching `docs/features/*/PRD.md`" — implementers MUST sort lexically and pick `[0]`. Multi-PRD PRs are out of scope for V1; a follow-on item can be queued if observed in the wild.
- **`/kiln:kiln-roadmap --check --fix` invoked with no drift detected**: skill prints "No drift detected" and exits 0 with no prompt.
- **Spec-template authoring note conflicts with existing structure**: the note is purely additive — appended to the existing `## Success Criteria *(mandatory)*` section. No restructuring.
- **Tripwire error-text length concern (OQ-2)**: the new error line is ~80 characters; if any log-parsing consumer truncates long tripwire errors, condense to a one-line `see plugin-wheel/README.md §Writing agent instructions` pointer. Verified by inspection during implementation.

## Requirements *(mandatory)*

### Functional Requirements

#### Theme A — `/kiln:kiln-merge-pr` skill + helper extraction + `--check --fix`

- **FR-001** (PRD FR-001): A new skill at `plugin-kiln/skills/kiln-merge-pr/SKILL.md` MUST accept a PR number as required positional argument and `--squash | --merge | --rebase` as optional flag (default `--squash`). MUST also accept `--no-flip` as an escape hatch (merge only, skip auto-flip stage).
- **FR-002** (PRD FR-002): `/kiln:kiln-merge-pr` MUST gate on PR mergeability via `gh pr view <pr> --json state,mergeable,mergeStateStatus` BEFORE attempting the merge. Refuse to merge when `state` is not `OPEN` (or `MERGED` per FR-002a/NFR-001 idempotency) or `mergeStateStatus` is not `CLEAN`/`MERGEABLE`. Surface the reason and exit non-zero.
- **FR-002a** (NFR-001 idempotency): When `state == MERGED`, the skill MUST skip the merge step (no-op `gh pr merge`) and proceed to the auto-flip stage. Re-invocation on a merged PR is supported.
- **FR-003** (PRD FR-003): `/kiln:kiln-merge-pr` MUST invoke `gh pr merge <pr> --<method> --delete-branch` and wait for merge confirmation via `gh pr view <pr> --json state` returning `MERGED` before proceeding to auto-flip.
- **FR-004** (PRD FR-004): `/kiln:kiln-merge-pr` MUST locate the PRD via `gh pr view <pr> --json files` → first file (lexical sort, `[0]`) matching `docs/features/*/PRD.md`. If zero matches, emit a diagnostic line `kiln-merge-pr: pr=<n> auto-flip=skipped reason=no-prd-in-changeset` and exit 0.
- **FR-005** (PRD FR-005): `/kiln:kiln-merge-pr` MUST invoke the shared helper `plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh <pr> <prd>` against the located PRD, and the canonical diagnostic line `step4b-auto-flip: pr-state=MERGED auto-flip=success items=N patched=N already_shipped=N reason=` MUST be emitted byte-for-byte by the helper (so existing consumers parse identically).
- **FR-006** (PRD FR-006): `/kiln:kiln-merge-pr` MUST commit the roadmap-item flips with message `chore(roadmap): auto-flip on merge of PR #<n>` and push to origin. If the working tree had unrelated uncommitted changes at invocation, the skill MUST refuse and surface them — never `git add -A` (NFR-005, retro #187 PI-1). Staging MUST be by exact path: `git add .kiln/roadmap/items/<each-flipped>.md`.
- **FR-007** (PRD FR-007): `--no-flip` MUST skip the auto-flip stage entirely (FR-004 through FR-006 do not run). The merge still runs; the diagnostic line is `kiln-merge-pr: pr=<n> auto-flip=skipped reason=--no-flip`.
- **FR-008** (PRD FR-008): `plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh` MUST be a verbatim extraction of the existing Step 4b.5 inline block in `plugin-kiln/skills/kiln-build-prd/SKILL.md`. The helper accepts `<pr-number> <prd-path>` as positional args, reads the PRD's `derived_from:` list, flips each item via `update-item-state.sh <path> shipped --status shipped`, then patches `pr: <n>` and `shipped_date: <YYYY-MM-DD>` at the END of the frontmatter (canonical bare-numeric placement). Helper MUST be idempotent: a second run reports `already_shipped=N patched=0` and zero file mutations.
- **FR-009** (PRD FR-009): Step 4b.5 in `plugin-kiln/skills/kiln-build-prd/SKILL.md` MUST be refactored to call the shared `auto-flip-on-merge.sh` helper instead of inlining the logic. This is a pure extraction — no behavior change. Diagnostic line output, exit codes, and frontmatter mutations MUST remain byte-for-byte identical to the pre-extraction inline block (NFR-002).
- **FR-010** (PRD FR-010): `/kiln:kiln-roadmap --check --fix` MUST extend the existing `--check` mode (Check 5: merged-PR drift, escalation-audit FR-005). When invoked WITHOUT `--fix`, behavior is unchanged. When invoked WITH `--fix`, the skill MUST present drifted items as a confirm-never-silent list with `[fix all / pick / skip]` options. On `fix all` or per-item accept, the skill MUST call `auto-flip-on-merge.sh <pr> <prd>` for each accepted entry. On `skip` or empty input, MUST exit 0 with no writes (NFR-004).
- **FR-011** (PRD FR-011): `/kiln:kiln-roadmap --check --fix` MUST resolve the PR number for each drifted item by reading the item's `prd:` field, then probing `gh pr list --state merged --search "head:<feature-branch>"` to find the merged PR that matches. If zero or multiple PRs match, MUST surface the ambiguity and skip that single item; MUST NOT guess heuristically.

#### Theme B — Spec-template SC-grep date-bound recipe

- **FR-012** (PRD FR-012): `plugin-kiln/templates/spec-template.md` MUST gain an authoring note + recipe inside the `## Success Criteria *(mandatory)*` section. The note MUST advise that grep-style SCs against directories with historical state (`.wheel/history/`, `archive/`, `migrations/`) include a date or commit cutoff, and provide the canonical recipe in a code-fence: `git log --name-only --pretty='' --since='YYYY-MM-DD' -- '<glob>' | sort -u | xargs -I{} git grep -lE '<pattern>' -- {}`. The literal string `date-bound qualifier` MUST appear in the note.
- **FR-013** (PRD FR-013): The same authoring note MUST also recommend the alternative — express the SC against a fresh artifact produced by a consumer-install simulation (the substantive assertion) rather than a directory-wide scan of historical state.

#### Theme C — Wheel preprocessor + README documentary-references rule

- **FR-014** (PRD FR-014): `plugin-wheel/lib/preprocess.sh` MUST gain a module-level comment block documenting the "documentary references trip the tripwire" gotcha. The comment MUST name BOTH failure modes (FR-F4-5 prefix-pattern fires on grammar variants the substitution regex skips; `$$` escaping survives the tripwire but lands in archives where SC-F-6 grep trips it), and recommend plain-prose substitution that does NOT reproduce the token grammar. The literal word `documentary` MUST appear in the comment.
- **FR-015** (PRD FR-015): `plugin-wheel/README.md` MUST gain a "Writing agent instructions" section (or a clearly named extension of the existing workflow-authoring section) with the same rule, in author-facing language. The section MUST be discoverable from a top-level heading. The literal word `documentary` MUST appear in the section.
- **FR-016** (PRD FR-016): The FR-F4-5 tripwire's error text in `plugin-wheel/lib/preprocess.sh` MUST be extended to include the line `If you intended this as documentary text, rewrite as plain prose; the tripwire fires on the prefix pattern even with $$ escaping.` — emitted as part of the rendered error so authors hit the explanation on first violation.

### Non-Functional Requirements

- **NFR-001** (idempotency): `/kiln:kiln-merge-pr <pr>` re-invoked on an already-merged PR MUST detect the merged state via FR-002a's gate, skip the merge, still run the auto-flip stage, and emit `step4b-auto-flip: pr-state=MERGED auto-flip=success items=N patched=0 already_shipped=N reason=`.
- **NFR-002** (zero-behavior-change extraction): the FR-009 extraction of Step 4b.5 → `auto-flip-on-merge.sh` MUST produce byte-for-byte identical mutations to a snapshot of pre-merge state of PR #189. A regression fixture under `plugin-kiln/tests/auto-flip-on-merge-fixture/` asserts that running the helper against the snapshot produces the post-merge state observed in commit `22a91b10`. Output diagnostic line MUST be byte-identical to Step 4b.5's pre-extraction emission.
- **NFR-003** (live-substrate-first auditing): per LIVE-SUBSTRATE-FIRST, the auditor for FR-005 (canonical diagnostic format) MUST verify the `step4b-auto-flip:` output against the live shipped helper, not against documented spec text. Same rule for FR-008's idempotency.
- **NFR-004** (confirm-never-silent): `/kiln:kiln-roadmap --check --fix` MUST never auto-fix without explicit user confirmation. Default behavior with no input is `skip`, not `fix all`.
- **NFR-005** (concurrent-staging hazard): per retro #187 PI-1, this PRD's implementation MUST stage by exact path, never `git add -A`. Implementers MUST split file ownership cleanly:
  - `impl-roadmap-and-merge` owns: `plugin-kiln/skills/kiln-merge-pr/SKILL.md` (NEW), `plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh` (NEW), `plugin-kiln/skills/kiln-build-prd/SKILL.md` (Step 4b.5 refactor), `plugin-kiln/skills/kiln-roadmap/SKILL.md` (`--check --fix` extension), `plugin-kiln/.claude-plugin/plugin.json` (skill registration), `plugin-kiln/tests/auto-flip-on-merge-fixture/` (NEW).
  - `impl-docs` owns: `plugin-kiln/templates/spec-template.md`, `plugin-wheel/lib/preprocess.sh`, `plugin-wheel/README.md`.
  - The two implementers MUST never touch the same file.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001** (from FR-001..FR-007, NFR-001): `/kiln:kiln-merge-pr <test-pr>` invoked end-to-end against a real PR (created and immediately merged via this skill in a fresh test branch) merges the PR, runs the auto-flip, commits the flips, and pushes — with zero manual intervention. Verified live against THIS PRD's PR after spec.md ships (Acceptance Test, PRD §"Acceptance Test — Live-Fire").
- **SC-002** (from FR-008, FR-009, NFR-002): the regression fixture `plugin-kiln/tests/auto-flip-on-merge-fixture/run.sh` runs `auto-flip-on-merge.sh` against a snapshot matching pre-merge state of PR #189 and asserts byte-for-byte equality with post-merge state from commit `22a91b10`. Test is wired into the `kiln-test` harness and runs in CI.
- **SC-003** (from FR-009): the inline Step 4b.5 Bash block in `plugin-kiln/skills/kiln-build-prd/SKILL.md` is removed and replaced with a single-line invocation of `auto-flip-on-merge.sh`. Verified by `git diff plugin-kiln/skills/kiln-build-prd/SKILL.md` showing the block deleted and the file's `wc -l` strictly decreasing.
- **SC-004** (from FR-010, FR-011, NFR-004): `/kiln:kiln-roadmap --check --fix` invoked against a repo with at least one synthesized drifted item (revert `state: shipped` → `state: distilled` on a test item) detects the drift, prompts for confirmation, applies the fix on `accept`, and reports `fix=success items=1`. On `skip`, no writes happen — verified by `git diff` being empty.
- **SC-005** (from FR-012, FR-013): `plugin-kiln/templates/spec-template.md` contains the literal authoring note + recipe block. Verified by `grep -F 'date-bound qualifier' plugin-kiln/templates/spec-template.md` returning ≥ 1 match AND the recipe code-fence containing the literal string `--since='YYYY-MM-DD'`.
- **SC-006** (from FR-014, FR-015, FR-016): `plugin-wheel/lib/preprocess.sh` module-level comment, `plugin-wheel/README.md` section, AND the FR-F4-5 tripwire error text all contain the documentary-references rule. Verified by `grep -lF 'documentary' plugin-wheel/lib/preprocess.sh plugin-wheel/README.md` returning BOTH files AND a tripwire-path test asserting the rendered error contains `If you intended this as documentary text, rewrite as plain prose; the tripwire fires on the prefix pattern even with $$ escaping.`.
- **SC-007** (cumulative — from NFR-002): re-running `/kiln:kiln-merge-pr` on the merged PR for THIS PRD produces the byte-identical `step4b-auto-flip:` diagnostic line and zero file changes (idempotency closing-loop validation). Captured as the closing live-fire validation of the pipeline (Acceptance Test).

## Assumptions

- The maintainer has `gh` CLI installed and authenticated. Skill is degraded-to-no-op if not, matching Step 4b.5's existing `gh-unavailable` branch.
- `kiln-build-prd`'s Step 4b.5 inline block at lines ~1019..1110 of `plugin-kiln/skills/kiln-build-prd/SKILL.md` is the canonical pre-extraction reference. The helper is a verbatim extraction modulo positional argument parsing (`$1=PR_NUMBER`, `$2=PRD_PATH`) instead of inheriting `$PR_NUMBER` / `$PRD_PATH` from the skill body's enclosing scope.
- PR #189 commit `22a91b10` is the canonical post-merge snapshot. Items in scope: the three derived_from items the auto-flip touched. Snapshot files are committed verbatim under `plugin-kiln/tests/auto-flip-on-merge-fixture/golden/`.
- The existing `update-item-state.sh --status` flag (escalation-audit FR-002) is preserved unchanged; the helper is its sole new caller for the bulk-flip path.
- `/kiln:kiln-roadmap --check`'s existing Check 5 output (escalation-audit FR-005) — `[drift] <item-id> ... pr=#<N>` — is the parse target for FR-010's drift-list iteration. Implementer parses by line, not by re-running the resolution logic.
- Mode flag mapping for `gh pr merge`: `--squash` → `--squash`, `--merge` → `--merge`, `--rebase` → `--rebase`. `--delete-branch` is always passed (matches build-prd's audit-pr convention).
- The PRD has NO quantitative perf thresholds (NFRs are byte-identity / structural), so the baseline-checkpoint procedure in `kiln-build-prd` does NOT apply for this run. Documented in `agent-notes/specifier.md`.
