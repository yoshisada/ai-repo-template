# Smoke Tests: Pipeline Input Completeness

**Spec**: [spec.md](./spec.md)
**Contracts**: [contracts/interfaces.md](./contracts/interfaces.md)
**Branch**: `build/pipeline-input-completeness-20260423`

## About

Documentary smoke fixtures for the two fixes in this PRD. Pattern matches
`kiln-claude-audit`, `kiln-hygiene`, and `kiln-structural-hygiene`: README +
sample files + shell-runnable assertions. **No executable harness** — each
fixture is a copy-pasteable bash block that ends with
`echo OK || echo FAIL`.

All fixtures assume CWD = repository root.

## How to run

1. Pick a fixture section below (Step 4b or shelf-write-issue-note).
2. Read its **Setup** block and paste into a shell.
3. Paste its **Invocation** block (Step 4b: the bash body from
   [contracts/interfaces.md §1 steps 1–6](./contracts/interfaces.md#1--step-4b-bash-pseudocode-replaces-lines-590631-of-plugin-kilnskillskiln-build-prdskillmd); shelf-write-issue-note: invoke
   via `/kiln:kiln-report-issue` or by running the workflow directly).
4. Paste the **Assertion** block. It should print `OK`.
5. Run the **Cleanup** block (where present) so the next fixture starts fresh.

SC mapping per block:

| Block | SC covered |
|---|---|
| §5.1 Step 4b two-source | SC-001 |
| §5.2 Step 4b path-normalization | SC-003 |
| §5.3 Step 4b zero-match diagnostic | SC-002 |
| §5.4 shelf-write-issue-note shelf-config-present | SC-004 |
| §5.5 shelf-write-issue-note discovery fallback | SC-005 |
| §5.6 Step 4b idempotence | SC-006 |
| (Phase F verification log) | SC-007 |

---

## Step 4b fixtures

### §5.1 — Two-source fixture (SC-001)

Validates FR-001 (both `.kiln/issues/` and `.kiln/feedback/` are scanned) and
FR-002 (archive preserves originating directory).

#### Setup

```bash
# Setup
mkdir -p .kiln/issues .kiln/feedback docs/features/2026-04-23-fixture/
cat > docs/features/2026-04-23-fixture/PRD.md <<'PRDEOF'
# Fixture PRD
PRDEOF

cat > .kiln/issues/2026-04-23-fixture-issue.md <<'EOF'
---
status: prd-created
prd: docs/features/2026-04-23-fixture/PRD.md
---
fixture issue body
EOF

cat > .kiln/feedback/2026-04-23-fixture-feedback.md <<'EOF'
---
status: prd-created
prd: docs/features/2026-04-23-fixture/PRD.md
---
fixture feedback body
EOF
```

#### Invocation

```bash
# Manual run; in-pipeline this happens automatically inside Step 4b.
PRD_PATH="docs/features/2026-04-23-fixture/PRD.md"
PR_NUMBER="999"
# (paste Step 4b body from contracts/interfaces.md §1, steps 1–6)
```

#### Expected output

```
step4b: scanned_issues=1 scanned_feedback=1 matched=2 archived=2 skipped=0 prd_path=docs/features/2026-04-23-fixture/PRD.md
```

#### Assertion

```bash
test -f .kiln/issues/completed/2026-04-23-fixture-issue.md && \
test -f .kiln/feedback/completed/2026-04-23-fixture-feedback.md && \
grep -q '^status: completed' .kiln/issues/completed/2026-04-23-fixture-issue.md && \
grep -q '^status: completed' .kiln/feedback/completed/2026-04-23-fixture-feedback.md && \
echo OK || echo FAIL
```

#### Cleanup

```bash
rm -rf .kiln/issues/completed/2026-04-23-fixture-issue.md \
       .kiln/feedback/completed/2026-04-23-fixture-feedback.md \
       docs/features/2026-04-23-fixture/
```

---

### §5.2 — Path-normalization fixture (SC-003)

Validates FR-004 (normalize both sides: leading `./` and trailing `/` stripped
before comparison; absolute paths rejected).

#### Setup

```bash
mkdir -p .kiln/issues .kiln/feedback docs/features/2026-04-23-fixture/
cat > docs/features/2026-04-23-fixture/PRD.md <<'PRDEOF'
# Fixture PRD
PRDEOF

cat > .kiln/issues/2026-04-23-fixture-leading-dot.md <<'EOF'
---
status: prd-created
prd: ./docs/features/2026-04-23-fixture/PRD.md
---
EOF

cat > .kiln/feedback/2026-04-23-fixture-trailing-slash.md <<'EOF'
---
status: prd-created
prd: docs/features/2026-04-23-fixture/PRD.md/
---
EOF
```

#### Invocation

```bash
PRD_PATH="docs/features/2026-04-23-fixture/PRD.md"
PR_NUMBER="999"
# (paste Step 4b body)
```

#### Assertion

```bash
test -f .kiln/issues/completed/2026-04-23-fixture-leading-dot.md && \
test -f .kiln/feedback/completed/2026-04-23-fixture-trailing-slash.md && \
echo OK || echo FAIL
```

#### Cleanup

```bash
rm -rf .kiln/issues/completed/2026-04-23-fixture-leading-dot.md \
       .kiln/feedback/completed/2026-04-23-fixture-trailing-slash.md \
       docs/features/2026-04-23-fixture/
```

---

### §5.3 — Zero-match diagnostic fixture (SC-002)

Validates FR-003 (diagnostic line emits on every run, even zero-match) and
FR-005 (log-file append happens on every run).

#### Setup

```bash
mkdir -p .kiln/issues .kiln/feedback
```

#### Invocation

```bash
PRD_PATH="docs/features/2026-04-23-NONEXISTENT/PRD.md"
PR_NUMBER="999"
# (paste Step 4b body)
```

#### Expected output (diagnostic format)

Exactly one line on stdout and appended to
`.kiln/logs/build-prd-step4b-<YYYY-MM-DD>.md`:

```
step4b: scanned_issues=<N> scanned_feedback=<M> matched=0 archived=0 skipped=<S> prd_path=docs/features/2026-04-23-NONEXISTENT/PRD.md
```

#### Assertion

```bash
TODAY="$(date -u +%Y-%m-%d)"
grep -E '^step4b: scanned_issues=[0-9]+ scanned_feedback=[0-9]+ matched=0 archived=0 skipped=[0-9]+ prd_path=' \
  ".kiln/logs/build-prd-step4b-${TODAY}.md" \
  && echo OK || echo FAIL
```

---

### §5.6 — Idempotence fixture (SC-006)

Validates that re-running Step 4b against the same PRD after the first archive
is a no-op and records the no-op explicitly.

#### Setup

Run §5.1 Setup + Invocation + Assertion first, leaving the completed/ files in
place. Then re-run the Step 4b body with the same `$PRD_PATH`.

#### Assertion

```bash
TODAY="$(date -u +%Y-%m-%d)"
LOG=".kiln/logs/build-prd-step4b-${TODAY}.md"
LAST_LINE="$(tail -1 "$LOG")"
echo "$LAST_LINE" | grep -qE 'matched=0 archived=0' && echo OK || echo FAIL
```

---

## `shelf-write-issue-note` fixtures

Both fixtures invoke the workflow via its standard entrypoint
(`/kiln:kiln-report-issue` — the background sub-agent path — or direct wheel
run). They inspect
`.wheel/outputs/shelf-write-issue-note-result.json` after completion.

The two fixtures follow the **`mv .shelf-config .shelf-config.bak` save-and-restore pattern** — this is documented because the vault parser depends on
`.shelf-config` and restoring it is mandatory for downstream workflow runs.

### §5.4 — `.shelf-config` present (SC-004)

Validates FR-006 (defensive parse produces the `.shelf-config (base_path + slug)`
`path_source` when the config is present and complete).

#### Preconditions

- `.shelf-config` exists at repo root with non-empty `slug` and `base_path`.
  This is the default state for an initialized kiln repo.

```bash
test -f .shelf-config || { echo "FAIL: prerequisite .shelf-config missing"; exit 1; }
```

#### Setup

```bash
mkdir -p .kiln/issues
cat > .kiln/issues/2026-04-23-smoke-write-issue-note.md <<'EOF'
---
title: smoke fixture for write-issue-note
type: improvement
severity: low
category: workflow
source: manual
status: open
date: 2026-04-23
---
## Description
fixture body
EOF
```

#### Invocation

```bash
# Easiest: invoke via the workflow entrypoint the kiln-report-issue bg agent uses.
# The simplest way to drive it in a smoke is:
#   /kiln:kiln-report-issue <short description pointing at the fixture file>
#
# For a pure-bash smoke (no slash command), run the workflow directly via the
# wheel entrypoint — the sub-workflow reads from context so an end-to-end
# invocation requires a driving agent. For smoke purposes we accept the slash
# command invocation.
```

#### Assertion

```bash
RESULT=".wheel/outputs/shelf-write-issue-note-result.json"
test -s "$RESULT" || { echo "FAIL: missing $RESULT"; exit 1; }
SOURCE="$(jq -r '.path_source' "$RESULT")"
test "$SOURCE" = ".shelf-config (base_path + slug)" \
  && jq -e '.errors == []' "$RESULT" >/dev/null \
  && echo OK || echo FAIL
```

#### Cleanup

```bash
rm -f .kiln/issues/2026-04-23-smoke-write-issue-note.md
```

---

### §5.5 — Discovery fallback (SC-005)

Validates FR-007 (when `.shelf-config` is absent, the workflow records
`path_source: "discovery (shelf-config incomplete)"` and still succeeds — i.e.
backwards-compat per NFR-002 is honored for repos without `.shelf-config`).

#### Setup — hide `.shelf-config`

```bash
test -f .shelf-config && mv .shelf-config .shelf-config.bak
trap 'test -f .shelf-config.bak && mv .shelf-config.bak .shelf-config' EXIT
```

> **Save-and-restore contract**: the `trap` on `EXIT` restores `.shelf-config`
> even if the fixture body errors out. This is non-negotiable — downstream
> workflow runs depend on `.shelf-config` being present.

#### Invocation

Same as §5.4 — invoke via `/kiln:kiln-report-issue` or the direct workflow
entrypoint against the same synthetic issue file.

#### Assertion

```bash
RESULT=".wheel/outputs/shelf-write-issue-note-result.json"
SOURCE="$(jq -r '.path_source' "$RESULT")"
test "$SOURCE" = "discovery (shelf-config incomplete)" \
  && jq -e '.errors == []' "$RESULT" >/dev/null \
  && echo OK || echo FAIL
```

#### Cleanup

The `trap 'mv .shelf-config.bak .shelf-config' EXIT` on the Setup block
restores `.shelf-config` automatically. After running assertions:

```bash
# Belt-and-braces restore if the shell that ran the trap exited already:
test -f .shelf-config.bak && mv .shelf-config.bak .shelf-config
test -f .shelf-config || echo "FAIL: .shelf-config not restored"
```

---

## Parser unit smoke (bonus)

Not tied to a specific SC but useful for quick confidence in
`plugin-shelf/scripts/parse-shelf-config.sh`:

```bash
TMPDIR=$(mktemp -d); cd "$TMPDIR"
printf '# comment\n\nslug = "quoted-slug"\nbase_path='\''single'\''\r\ndashboard_path=  spaced-value  \r\n' > .shelf-config
bash /PATH/TO/ai-repo-template/plugin-shelf/scripts/parse-shelf-config.sh
cd - && rm -rf "$TMPDIR"
```

Expected:
```
## SHELF_CONFIG_PARSED
slug = quoted-slug
base_path = single
dashboard_path = spaced-value
shelf_config_present = true
## END_SHELF_CONFIG_PARSED
```

Covers: quoted values (double + single), CRLF line endings, surrounding
whitespace, comment/blank-line skipping.
