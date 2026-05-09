// FR-5 — Workflow diff module.
//
// Pure-functional, deterministic, synchronous. No I/O. Step alignment uses `id`
// as the join key (FR-5.3). Steps without an `id` index-pair only when both
// sides have an unidentified step at the same index; otherwise they show as
// added or removed.
//
// Field-level diff descends into nested objects via dot-path; arrays are
// compared element-wise after JSON-stringify (sufficient for v1 per plan D-3).
// Primitives, null, and arrays at any depth are leaf comparisons.

import type { Step, Workflow } from './types'

export interface FieldDiff {
  /** Dot-path within the step, e.g. `agent.model` or `if_zero`. */
  path: string
  left: unknown
  right: unknown
}

export interface ModifiedStep {
  /** Shared step id (the join key). */
  id: string
  leftStep: Step
  rightStep: Step
  /** Sorted ascending by `path`. */
  fieldDiff: FieldDiff[]
}

export interface WorkflowDiff {
  /** Steps in `right` but not `left`, by id. Order preserves right.steps order. */
  added: Step[]
  /** Steps in `left` but not `right`, by id. Order preserves left.steps order. */
  removed: Step[]
  /** Steps with the same id on both sides whose JSON content differs. */
  modified: ModifiedStep[]
  /** Steps that are deep-equal on both sides. Order preserves left.steps order. */
  unchanged: Step[]
}

// FR-5.3 — internal: stable JSON for deep-equality short-circuit. Sort keys so
// `{ a:1, b:2 }` and `{ b:2, a:1 }` compare equal.
function stableStringify(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value)
  if (Array.isArray(value)) return '[' + value.map(stableStringify).join(',') + ']'
  const obj = value as Record<string, unknown>
  const keys = Object.keys(obj).sort()
  return '{' + keys.map(k => JSON.stringify(k) + ':' + stableStringify(obj[k])).join(',') + '}'
}

function deepEqual(a: unknown, b: unknown): boolean {
  return stableStringify(a) === stableStringify(b)
}

/**
 * FR-5 — Walk two values and emit a FieldDiff at every leaf where they differ.
 * Descends into plain objects via dot-path. Arrays and primitives are leaves.
 *
 * If a key exists on one side but not the other, it's emitted with the
 * missing side as `undefined`.
 */
function fieldDiffEntries(
  left: unknown,
  right: unknown,
  prefix: string,
  out: FieldDiff[],
): void {
  // If both sides are plain objects, descend.
  const isPlainObj = (v: unknown): v is Record<string, unknown> =>
    v !== null && typeof v === 'object' && !Array.isArray(v)

  if (isPlainObj(left) && isPlainObj(right)) {
    const keys = new Set<string>([...Object.keys(left), ...Object.keys(right)])
    for (const key of keys) {
      const childPrefix = prefix === '' ? key : prefix + '.' + key
      fieldDiffEntries(left[key], right[key], childPrefix, out)
    }
    return
  }

  // Leaf comparison (or one-side-missing): emit if not deep-equal.
  if (!deepEqual(left, right)) {
    out.push({ path: prefix, left, right })
  }
}

function fieldDiffStep(left: Step, right: Step): FieldDiff[] {
  const out: FieldDiff[] = []
  fieldDiffEntries(left as unknown, right as unknown, '', out)
  out.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0))
  return out
}

/**
 * FR-5.3 — Compute a workflow diff.
 *
 * Step alignment:
 *   1. Steps with an `id` are paired across sides by id.
 *   2. Steps without an `id` are paired by index ONLY when both sides also
 *      lack an id at that index.
 *   3. Anything else falls through to added (only in right) or removed (only in left).
 *
 * @param left  Baseline workflow.
 * @param right Comparison workflow.
 * @returns     Categorized diff with field-level changes for modified pairs.
 */
export function diffWorkflows(left: Workflow, right: Workflow): WorkflowDiff {
  const leftSteps: Step[] = left.steps ?? []
  const rightSteps: Step[] = right.steps ?? []

  // Track which right steps have been claimed by an id-pair so we don't
  // double-count them in the index-pair pass below.
  const rightById = new Map<string, { idx: number; step: Step }>()
  rightSteps.forEach((s, idx) => {
    if (typeof s.id === 'string' && s.id.length > 0 && !rightById.has(s.id)) {
      rightById.set(s.id, { idx, step: s })
    }
  })
  const claimedRightIdx = new Set<number>()

  const added: Step[] = []
  const removed: Step[] = []
  const modified: ModifiedStep[] = []
  const unchanged: Step[] = []

  // Pass 1: walk left.steps. id-pair when possible; else queue for pass-2 index pairing.
  const leftUnidentified: Array<{ idx: number; step: Step }> = []
  for (let i = 0; i < leftSteps.length; i++) {
    const ls = leftSteps[i]
    const lid = typeof ls.id === 'string' ? ls.id : ''
    if (lid !== '' && rightById.has(lid)) {
      const { idx: rIdx, step: rs } = rightById.get(lid)!
      claimedRightIdx.add(rIdx)
      if (deepEqual(ls, rs)) {
        unchanged.push(ls)
      } else {
        modified.push({
          id: lid,
          leftStep: ls,
          rightStep: rs,
          fieldDiff: fieldDiffStep(ls, rs),
        })
      }
    } else if (lid !== '') {
      // id-having step in left with no match in right → removed
      removed.push(ls)
    } else {
      // unidentified — try index-pair in pass 2
      leftUnidentified.push({ idx: i, step: ls })
    }
  }

  // Pass 2: index-pair unidentified steps only when right's step at the same
  // index ALSO lacks an id and hasn't been claimed by an id-pair.
  for (const { idx, step: ls } of leftUnidentified) {
    const rs = rightSteps[idx]
    const rsHasId = rs && typeof rs.id === 'string' && rs.id.length > 0
    if (rs && !rsHasId && !claimedRightIdx.has(idx)) {
      claimedRightIdx.add(idx)
      if (deepEqual(ls, rs)) {
        unchanged.push(ls)
      } else {
        modified.push({
          id: '', // unidentified pair surfaces with empty id
          leftStep: ls,
          rightStep: rs,
          fieldDiff: fieldDiffStep(ls, rs),
        })
      }
    } else {
      // Unidentified left with no valid index-pair → removed
      removed.push(ls)
    }
  }

  // Pass 3: any right step not yet claimed → added (preserves right.steps order).
  rightSteps.forEach((rs, idx) => {
    if (!claimedRightIdx.has(idx)) added.push(rs)
  })

  return { added, removed, modified, unchanged }
}
