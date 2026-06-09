// Diff module — coverage for diffWorkflows() per FR-5.3.
//
// Step alignment uses `id` as the join key. Steps with no matching `id` on the
// other side fall through to added / removed. Steps without an `id` are
// index-paired only when both sides have an unidentified step at the same index.
// Otherwise they appear as added/removed.
//
// Output sort order:
//   - added: preserves order of right.steps (the steps appearing in right but absent in left)
//   - removed: preserves order of left.steps
//   - modified: preserves order of left.steps for paired ids
//   - unchanged: preserves order of left.steps

import { describe, it, expect } from 'vitest'
import { diffWorkflows } from './diff'
import type { Step, Workflow } from './types'

function makeWorkflow(name: string, steps: Step[]): Workflow {
  return {
    name,
    path: `/tmp/${name}.json`,
    source: 'local',
    stepCount: steps.length,
    steps,
    localOverride: false,
  }
}

describe('diffWorkflows — added / removed / unchanged / modified', () => {
  it('all-added: every step in right is new (left empty)', () => {
    // FR-5.3 — id-keyed alignment, all-new case
    const left = makeWorkflow('a', [])
    const right = makeWorkflow(
      'b',
      [
        { id: 'r1', type: 'command' },
        { id: 'r2', type: 'agent' },
      ],
    )
    const d = diffWorkflows(left, right)
    expect(d.added.map(s => s.id)).toEqual(['r1', 'r2'])
    expect(d.removed).toEqual([])
    expect(d.modified).toEqual([])
    expect(d.unchanged).toEqual([])
  })

  it('all-removed: every step in left is gone (right empty)', () => {
    const left = makeWorkflow(
      'a',
      [
        { id: 'l1', type: 'command' },
        { id: 'l2', type: 'agent' },
      ],
    )
    const right = makeWorkflow('b', [])
    const d = diffWorkflows(left, right)
    expect(d.removed.map(s => s.id)).toEqual(['l1', 'l2'])
    expect(d.added).toEqual([])
    expect(d.modified).toEqual([])
    expect(d.unchanged).toEqual([])
  })

  it('all-unchanged: identical step lists pair every id with deep-equal content', () => {
    const steps: Step[] = [
      { id: 's1', type: 'command', command: 'echo hi' },
      { id: 's2', type: 'agent', model: 'sonnet' },
    ]
    const d = diffWorkflows(makeWorkflow('a', steps), makeWorkflow('b', steps))
    expect(d.unchanged.map(s => s.id)).toEqual(['s1', 's2'])
    expect(d.added).toEqual([])
    expect(d.removed).toEqual([])
    expect(d.modified).toEqual([])
  })

  it('modified: same id, different content surfaces a fieldDiff sorted by path', () => {
    // FR-5.3 — paired by id; field diff records left + right values per path.
    const left = makeWorkflow('a', [
      { id: 's1', type: 'agent', model: 'haiku', prompt: 'old' },
    ])
    const right = makeWorkflow('b', [
      { id: 's1', type: 'agent', model: 'sonnet', prompt: 'old' },
    ])
    const d = diffWorkflows(left, right)
    expect(d.modified).toHaveLength(1)
    const m = d.modified[0]
    expect(m.id).toBe('s1')
    expect(m.fieldDiff.map(f => f.path)).toEqual(['model'])
    expect(m.fieldDiff[0].left).toBe('haiku')
    expect(m.fieldDiff[0].right).toBe('sonnet')
    expect(d.added).toEqual([])
    expect(d.removed).toEqual([])
    expect(d.unchanged).toEqual([])
  })

  it('mixed: added + removed + modified + unchanged in one pass', () => {
    const left = makeWorkflow('a', [
      { id: 'common', type: 'command', command: 'old-cmd' },
      { id: 'gone', type: 'agent', model: 'haiku' },
      { id: 'kept', type: 'workflow' },
    ])
    const right = makeWorkflow('b', [
      { id: 'common', type: 'command', command: 'new-cmd' }, // modified
      { id: 'kept', type: 'workflow' }, // unchanged
      { id: 'fresh', type: 'team-create', team_name: 'workers' }, // added
    ])
    const d = diffWorkflows(left, right)
    expect(d.modified.map(m => m.id)).toEqual(['common'])
    expect(d.removed.map(s => s.id)).toEqual(['gone'])
    expect(d.unchanged.map(s => s.id)).toEqual(['kept'])
    expect(d.added.map(s => s.id)).toEqual(['fresh'])
  })

  it('preserves left order for removed and right order for added', () => {
    // FR-5 spec — added uses right.steps order, removed uses left.steps order.
    const left = makeWorkflow('a', [
      { id: 'a1', type: 'command' },
      { id: 'a2', type: 'command' },
      { id: 'a3', type: 'command' },
    ])
    const right = makeWorkflow('b', [
      { id: 'b1', type: 'command' },
      { id: 'b2', type: 'command' },
      { id: 'b3', type: 'command' },
    ])
    const d = diffWorkflows(left, right)
    expect(d.removed.map(s => s.id)).toEqual(['a1', 'a2', 'a3'])
    expect(d.added.map(s => s.id)).toEqual(['b1', 'b2', 'b3'])
  })
})

describe('diffWorkflows — unidentified-step pairing (no id)', () => {
  it('pairs unidentified steps at the same index, both sides', () => {
    // Step alignment fallback: when both sides have a step with no id at index N,
    // they're paired (modified if content differs, unchanged if equal).
    const left = makeWorkflow('a', [{ type: 'command', command: 'first' }])
    const right = makeWorkflow('b', [{ type: 'command', command: 'second' }])
    const d = diffWorkflows(left, right)
    expect(d.modified).toHaveLength(1)
    expect(d.modified[0].fieldDiff.map(f => f.path)).toContain('command')
  })

  it('treats orphan unidentified step on one side as added/removed (not paired)', () => {
    // Left has an unidentified step at index 0, right has none — left's becomes removed.
    const left = makeWorkflow('a', [{ type: 'command' }])
    const right = makeWorkflow('b', [])
    const d = diffWorkflows(left, right)
    expect(d.removed).toHaveLength(1)
    expect(d.modified).toEqual([])
    expect(d.added).toEqual([])
  })

  it('does not cross-pair an unidentified step in left with an id-having step in right at same index', () => {
    // Index-pair only kicks in when BOTH sides at that index lack an id.
    const left = makeWorkflow('a', [{ type: 'command' }])
    const right = makeWorkflow('b', [{ id: 'rid', type: 'command' }])
    const d = diffWorkflows(left, right)
    expect(d.removed).toHaveLength(1) // left's no-id step
    expect(d.added.map(s => s.id)).toEqual(['rid']) // right's id-having step
    expect(d.modified).toEqual([])
  })
})

describe('diffWorkflows — fieldDiff ordering and depth', () => {
  it('sorts fieldDiff entries by path', () => {
    // FR-5 — sort fieldDiff by path so the diff renders deterministically.
    const left = makeWorkflow('a', [
      {
        id: 's1',
        type: 'agent',
        model: 'haiku',
        prompt: 'old',
        agent_type: 'general-purpose',
      },
    ])
    const right = makeWorkflow('b', [
      {
        id: 's1',
        type: 'agent',
        model: 'sonnet',
        prompt: 'new',
        agent_type: 'specialized',
      },
    ])
    const d = diffWorkflows(left, right)
    const paths = d.modified[0].fieldDiff.map(f => f.path)
    const sorted = [...paths].sort()
    expect(paths).toEqual(sorted)
  })

  it('records nested-object differences via dot-path', () => {
    // Field diff descends into nested objects — `agent.foo` vs `agent.foo`.
    const left = makeWorkflow('a', [
      {
        id: 's1',
        type: 'agent',
        agent: { model: 'haiku', region: 'us' } as Record<string, unknown>,
      },
    ])
    const right = makeWorkflow('b', [
      {
        id: 's1',
        type: 'agent',
        agent: { model: 'sonnet', region: 'us' } as Record<string, unknown>,
      },
    ])
    const d = diffWorkflows(left, right)
    expect(d.modified).toHaveLength(1)
    const paths = d.modified[0].fieldDiff.map(f => f.path)
    expect(paths).toContain('agent.model')
    expect(paths).not.toContain('agent.region')
  })
})

describe('diffWorkflows — same-id-different-content edge', () => {
  it('classifies same-id-deep-equal as unchanged, not modified', () => {
    const same: Step = { id: 's1', type: 'command', command: 'echo' }
    const d = diffWorkflows(makeWorkflow('a', [same]), makeWorkflow('b', [{ ...same }]))
    expect(d.unchanged.map(s => s.id)).toEqual(['s1'])
    expect(d.modified).toEqual([])
  })
})
