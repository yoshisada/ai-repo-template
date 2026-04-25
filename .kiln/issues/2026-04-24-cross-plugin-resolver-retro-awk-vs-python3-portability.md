---
status: open
source: retrospective
prd: cross-plugin-resolver-and-preflight-registry
priority: low
suggested_command: /kiln:kiln-fix
tags: [retro, prompt-template, plan, portability, bsd-vs-gnu]
---

# Plan §"awk preferred" guidance traded a small dependency win for BSD-vs-GNU complexity; both implementers pivoted to python3

**Date**: 2026-04-24
**Source**: cross-plugin-resolver retrospective; impl-registry-resolver friction note §4 + impl-preprocessor friction note §"awk → sentinel-byte python3 pivot"

## Description

Plan §3 nominated `awk` for the escape pre-scan and the resolver token-discovery scan, with `python3` as a permitted fallback. In practice, both implementers hit BSD-vs-GNU portability divergence:

- **impl-registry-resolver**: `sed 's/\$\${[^}]*\}//g'` parsed differently on macOS BSD sed vs GNU sed (BSD raised "RE error: invalid repetition count(s)" on a regex GNU sed accepts). Pivoted to a portable awk hand-tokenizer.
- **impl-preprocessor**: BSD awk's `gsub()` lacks negative lookbehind; the cleanest awk implementation for positional escape-tracking became a manual char-by-char tokenizer (more fragile than the 20-line python3 sentinel-byte pass it was supposed to replace). Pivoted to python3.

Net: the plan's preference order (awk > python3) inverted in practice for any logic involving positional state-tracking. Worth codifying.

## Proposed prompt rewrite

**File**: `plugin-kiln/templates/plan-template.md` (Implementation language guidance) AND `.specify/memory/constitution.md` (if it lists tooling principles)

**Current** (plan-template, if present): No explicit BSD-vs-GNU guidance; authors default to "awk preferred for shell-flavor purity."

**Proposed**: Add a portability sub-rule:

```markdown
> **Portability rule — bash text processing**: when a transformation
> requires (a) positional state across characters, (b) multi-pass
> tokenization, (c) non-trivial regex with quantifiers, OR (d) escape-
> grammar handling, prefer `python3` over `awk`/`sed`. macOS ships BSD
> awk + BSD sed which diverge from GNU on quantifier syntax, lookbehind,
> and `gsub()` semantics. `python3` is on every Claude-Code-supported
> dev machine (it's a hard dep of the harness). Pure-shell-flavor purity
> is a value, but BSD/GNU portability is a HARDER value when the team
> supports both Linux CI and macOS dev.
```

**Why**: Both implementers independently rediscovered this and pivoted mid-implementation. The plan's "awk preferred" hint cost both of them ~20-30 min of false-start work before the pivot. A general portability rule pre-empts the next PRD's rediscovery.

## Forwarding action

- Patch `plugin-kiln/templates/plan-template.md` (or add an "Implementation Language Selection" sub-section if absent).
- Optional: add a `/plan` skill self-check that flags `awk`/`sed` in the plan body for any task whose description mentions "escape" / "positional" / "tokenize" and prompts the planner to confirm portability.
