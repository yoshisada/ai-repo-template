// Layout-engine unit tests (FR-1.1 through FR-1.8).
//
// Written FIRST per /implement TDD discipline — these tests will FAIL until
// `lib/layout.ts` lands. They MUST pass after T012 with no modifications here.
//
// Coverage scope (Constitution Article II, ≥80% on lib/layout.ts):
//   FR-1.1: edge-set construction from next/branch/skip/substep
//   FR-1.2: layered rank assignment (longest-path)
//   FR-1.3: branch rejoin (both legs converge cleanly at downstream node)
//   FR-1.4: loop substep cluster + back-edge
//   FR-1.5: parallel siblings at same rank
//   FR-1.6: expanded sub-workflow renders as sub-DAG below parent
//   FR-1.7: team-step fan-in (team-wait has N incoming edges)
//   FR-1.8: NO overlapping nodes — parameterized over every fixture under
//           workflows/tests/*.json AND plugin-wheel/tests/*/test.yaml fixtures

import { describe, it, expect } from 'vitest'
import * as fs from 'node:fs'
import * as path from 'node:path'
import {
  buildLayout,
  LAYOUT_RANK_HEIGHT,
  LAYOUT_NODE_SPACING_X,
  LAYOUT_SUB_DAG_OFFSET_Y,
  type GraphNode,
} from './layout'
import type { Step, Workflow } from './types'

// Helpers ------------------------------------------------------------------

function wf(name: string, steps: Step[]): Workflow {
  return {
    name,
    path: `/tmp/${name}.json`,
    source: 'local',
    stepCount: steps.length,
    steps,
    localOverride: false,
  }
}

// FR-1.8 — Two nodes overlap if their bounding boxes intersect. We model
// each node as occupying LAYOUT_NODE_SPACING_X × LAYOUT_RANK_HEIGHT centred
// at its position; with sibling spacing equal to width, distinct positions
// don't overlap.
function nodesOverlap(a: GraphNode, b: GraphNode): boolean {
  if (a.id === b.id) return false
  const ax = a.position.x
  const ay = a.position.y
  const bx = b.position.x
  const by = b.position.y
  // Two nodes overlap iff they share the exact same (x, y).
  return ax === bx && ay === by
}

function assertNoOverlap(nodes: GraphNode[], context: string) {
  for (let i = 0; i < nodes.length; i++) {
    for (let j = i + 1; j < nodes.length; j++) {
      if (nodesOverlap(nodes[i], nodes[j])) {
        throw new Error(
          `${context}: nodes ${nodes[i].id} and ${nodes[j].id} overlap at (${nodes[i].position.x}, ${nodes[i].position.y})`,
        )
      }
    }
  }
}

// Constants --------------------------------------------------------------

describe('layout constants', () => {
  it('exports the three layout constants per contracts/interfaces.md', () => {
    expect(LAYOUT_RANK_HEIGHT).toBe(160)
    expect(LAYOUT_NODE_SPACING_X).toBe(240)
    expect(LAYOUT_SUB_DAG_OFFSET_Y).toBe(200)
  })
})

// FR-1.1 / FR-1.2: linear chain ------------------------------------------

describe('buildLayout — linear chain (FR-1.1, FR-1.2)', () => {
  it('lays a 3-step linear chain as a vertical stack with monotonically increasing ranks', () => {
    const w = wf('linear', [
      { id: 'a', type: 'command', command: 'echo a' },
      { id: 'b', type: 'command', command: 'echo b' },
      { id: 'c', type: 'command', command: 'echo c', terminal: true },
    ])
    const { nodes, edges } = buildLayout(w)
    expect(nodes).toHaveLength(3)
    const ranks = nodes.map((n) => n.data.rank)
    expect(ranks).toEqual([0, 1, 2])
    // Linear chain: y is strictly increasing.
    expect(nodes[0].position.y).toBeLessThan(nodes[1].position.y)
    expect(nodes[1].position.y).toBeLessThan(nodes[2].position.y)
    // Two forward `next` edges only.
    const forward = edges.filter((e) => e.data?.kind === 'next')
    expect(forward.map((e) => `${e.source}->${e.target}`)).toEqual(['a->b', 'b->c'])
    assertNoOverlap(nodes, 'linear')
  })
})

// FR-1.3: branch with rejoin ---------------------------------------------

describe('buildLayout — branch with rejoin (FR-1.3)', () => {
  it('forks at branch step and rejoins downstream — rejoin node sits at one rank below max(branch leg)', () => {
    // root → branch → (zero|nonzero) → rejoin (terminal)
    const w = wf('branch-rejoin', [
      { id: 'root', type: 'command' },
      { id: 'branch', type: 'branch', condition: 'foo', if_zero: 'left', if_nonzero: 'right' },
      { id: 'left', type: 'command' },
      { id: 'right', type: 'command' },
      { id: 'rejoin', type: 'command', terminal: true },
    ])
    const { nodes, edges } = buildLayout(w)
    const rankOf = (id: string) => nodes.find((n) => n.id === id)?.data.rank
    expect(rankOf('root')).toBe(0)
    expect(rankOf('branch')).toBe(1)
    // Both legs at the same rank — they're siblings.
    expect(rankOf('left')).toBe(rankOf('right'))
    // Rejoin sits one rank below the legs (FR-1.3).
    const legRank = rankOf('left') as number
    expect(rankOf('rejoin')).toBe(legRank + 1)
    // Branch edges present (FR-1.3).
    expect(edges.some((e) => e.data?.kind === 'branch-zero' && e.target === 'left')).toBe(true)
    expect(edges.some((e) => e.data?.kind === 'branch-nonzero' && e.target === 'right')).toBe(true)
    assertNoOverlap(nodes, 'branch-rejoin')
  })
})

// FR-1.4: loop substep cluster -------------------------------------------

describe('buildLayout — loop substep (FR-1.4)', () => {
  it('renders the substep one rank below the loop step with a back-edge', () => {
    const w = wf('loop', [
      { id: 'init', type: 'command' },
      {
        id: 'loop1',
        type: 'loop',
        max_iterations: 5,
        substep: { type: 'command', command: 'echo iter' },
      },
      { id: 'after', type: 'command', terminal: true },
    ])
    const { nodes, edges } = buildLayout(w)
    // Substep node materializes as `loop1-substep`.
    const substep = nodes.find((n) => n.id === 'loop1-substep')
    expect(substep).toBeDefined()
    const loop = nodes.find((n) => n.id === 'loop1')!
    expect(substep!.data.rank).toBeGreaterThan(loop.data.rank)
    // FR-1.4: a back-edge (kind: 'loop-back') links substep → loop step.
    expect(
      edges.some(
        (e) => e.data?.kind === 'loop-back' && e.source === 'loop1-substep' && e.target === 'loop1',
      ),
    ).toBe(true)
    assertNoOverlap(nodes, 'loop')
  })
})

// FR-1.5: parallel siblings ----------------------------------------------

describe('buildLayout — parallel siblings at same rank (FR-1.5)', () => {
  it('places three teammates spawned by the same team-create at the same rank', () => {
    const w = wf('parallel-team', [
      { id: 'create', type: 'team-create', team_name: 'workers' },
      { id: 'w1', type: 'teammate', team: 'create', workflow: 'tests/team-sub-worker' },
      { id: 'w2', type: 'teammate', team: 'create', workflow: 'tests/team-sub-worker' },
      { id: 'w3', type: 'teammate', team: 'create', workflow: 'tests/team-sub-worker' },
      { id: 'wait', type: 'team-wait', team: 'create' },
    ])
    const { nodes } = buildLayout(w)
    const rankOf = (id: string) => nodes.find((n) => n.id === id)?.data.rank
    expect(rankOf('create')).toBe(0)
    // FR-1.5 + FR-1.7: all three teammates share one rank.
    expect(rankOf('w1')).toBe(rankOf('w2'))
    expect(rankOf('w2')).toBe(rankOf('w3'))
    // Their X coordinates are spread (no two share x).
    const xs = ['w1', 'w2', 'w3'].map((id) => nodes.find((n) => n.id === id)!.position.x)
    expect(new Set(xs).size).toBe(3)
    assertNoOverlap(nodes, 'parallel-team')
  })
})

// FR-1.7: team-step fan-in ------------------------------------------------

describe('buildLayout — team-wait fan-in (FR-1.7)', () => {
  it('team-wait receives one incoming edge per teammate referencing the same team-create id', () => {
    const w = wf('team-fan-in', [
      { id: 'create', type: 'team-create', team_name: 'fan' },
      { id: 'w1', type: 'teammate', team: 'create', workflow: 'sub' },
      { id: 'w2', type: 'teammate', team: 'create', workflow: 'sub' },
      { id: 'w3', type: 'teammate', team: 'create', workflow: 'sub' },
      { id: 'wait', type: 'team-wait', team: 'create' },
      { id: 'cleanup', type: 'team-delete', team: 'create', terminal: true },
    ])
    const { edges, nodes } = buildLayout(w)
    const fanIns = edges.filter(
      (e) => e.data?.kind === 'team-fan-in' && e.target === 'wait',
    )
    expect(fanIns).toHaveLength(3)
    expect(fanIns.map((e) => e.source).sort()).toEqual(['w1', 'w2', 'w3'])
    // The team-wait sits one rank below the teammates.
    const rankOf = (id: string) => nodes.find((n) => n.id === id)?.data.rank!
    expect(rankOf('wait')).toBe(rankOf('w1') + 1)
    assertNoOverlap(nodes, 'team-fan-in')
  })
})

// FR-1.6: expanded sub-workflow ------------------------------------------

describe('buildLayout — expanded sub-workflow (FR-1.6)', () => {
  it('renders the sub-DAG below the parent step with isSubDAGChild flagged', () => {
    const parent = wf('parent', [
      { id: 'a', type: 'command' },
      { id: 'sub-step', type: 'teammate', team: 'create', workflow: 'tests/sub' },
      { id: 'b', type: 'command', terminal: true },
    ])
    const sub = wf('tests/sub', [
      { id: 's1', type: 'command' },
      { id: 's2', type: 'command', terminal: true },
    ])
    const expanded = new Map<string, Workflow>([['sub-step', sub]])
    const { nodes, edges } = buildLayout(parent, expanded)

    // Parent nodes still present.
    expect(nodes.find((n) => n.id === 'a')).toBeDefined()
    expect(nodes.find((n) => n.id === 'sub-step')).toBeDefined()
    expect(nodes.find((n) => n.id === 'b')).toBeDefined()

    // Sub-DAG nodes namespaced and flagged.
    const subNodes = nodes.filter((n) => n.data.isSubDAGChild === true)
    expect(subNodes.length).toBeGreaterThanOrEqual(2)
    // Sub-DAG nodes appear at a y BELOW the parent step they expand.
    const parentNode = nodes.find((n) => n.id === 'sub-step')!
    subNodes.forEach((sn) => {
      expect(sn.position.y).toBeGreaterThan(parentNode.position.y)
    })

    // FR-1.6: an `expanded` edge connects the parent step to the sub-DAG entry.
    expect(edges.some((e) => e.data?.kind === 'expanded' && e.source === 'sub-step')).toBe(true)
    assertNoOverlap(nodes, 'expanded-sub-workflow')
  })
})

// FR-1.8: no-overlap invariant on every committed fixture ----------------

describe('buildLayout — FR-1.8 no-overlap invariant on every fixture', () => {
  // Collect every workflow JSON under workflows/tests/*.json relative to repo root.
  // __dirname = plugin-wheel/viewer/src/lib → 4 levels up = repo root.
  const repoRoot = path.resolve(__dirname, '../../../..')
  const fixtureDir = path.join(repoRoot, 'workflows', 'tests')
  const fixtures = fs.existsSync(fixtureDir)
    ? fs.readdirSync(fixtureDir).filter((f) => f.endsWith('.json'))
    : []

  if (fixtures.length === 0) {
    it.skip('no fixtures discovered — skipping (workflows/tests/ not found)', () => {})
  } else {
    fixtures.forEach((f) => {
      it(`no node overlap: ${f}`, () => {
        const raw = fs.readFileSync(path.join(fixtureDir, f), 'utf8')
        const json = JSON.parse(raw)
        const w: Workflow = {
          name: json.name ?? f,
          path: path.join(fixtureDir, f),
          source: 'local',
          stepCount: Array.isArray(json.steps) ? json.steps.length : 0,
          steps: Array.isArray(json.steps) ? json.steps : [],
          localOverride: false,
        }
        const { nodes } = buildLayout(w)
        assertNoOverlap(nodes, f)
      })
    })
  }
})

// FR-1.1: skip jump ------------------------------------------------------

describe('buildLayout — skip jump (FR-1.1)', () => {
  it('emits a skip-kind edge to the resolved target and suppresses default fall-through', () => {
    const w = wf('skip-jump', [
      { id: 'a', type: 'command' },
      { id: 'b', type: 'command', skip: 'd' }, // skip default forward, jump to 'd'
      { id: 'c', type: 'command' }, // never connected from 'b'
      { id: 'd', type: 'command', terminal: true },
    ])
    const { edges } = buildLayout(w)
    const skipEdge = edges.find((e) => e.data?.kind === 'skip')
    expect(skipEdge).toBeDefined()
    expect(skipEdge!.source).toBe('b')
    expect(skipEdge!.target).toBe('d')
    // No default forward from b → c.
    expect(edges.some((e) => e.source === 'b' && e.target === 'c' && e.data?.kind === 'next')).toBe(
      false,
    )
  })

  it('drops the skip edge when the target id does not resolve (lint catches via L-004)', () => {
    const w = wf('skip-orphan', [
      { id: 'a', type: 'command', skip: 'nonexistent' },
      { id: 'b', type: 'command', terminal: true },
    ])
    const { edges } = buildLayout(w)
    expect(edges.some((e) => e.data?.kind === 'skip')).toBe(false)
  })
})

// FR-1.3: branch-target orphan handling ---------------------------------

describe('buildLayout — branch with unresolved target (FR-1.3)', () => {
  it('drops the if_zero edge when the target does not resolve to a sibling step', () => {
    const w = wf('branch-orphan', [
      { id: 'root', type: 'command' },
      { id: 'br', type: 'branch', if_zero: 'nope', if_nonzero: 'nope2' },
      { id: 'after', type: 'command', terminal: true },
    ])
    const { edges } = buildLayout(w)
    expect(edges.some((e) => e.data?.kind === 'branch-zero')).toBe(false)
    expect(edges.some((e) => e.data?.kind === 'branch-nonzero')).toBe(false)
  })
})

// FR-1.7: team-create with a non-teammate next step ---------------------

describe('buildLayout — team-create with non-teammate next (FR-1.7)', () => {
  it('emits the default forward to a non-teammate next step', () => {
    const w = wf('lone-team-create', [
      { id: 'create', type: 'team-create', team_name: 'solo' },
      { id: 'after', type: 'command', terminal: true }, // not a teammate, not a branch target
    ])
    const { edges } = buildLayout(w)
    expect(
      edges.some((e) => e.source === 'create' && e.target === 'after' && e.data?.kind === 'next'),
    ).toBe(true)
  })

  it('suppresses the default forward when the next step is a branch target', () => {
    const w = wf('team-create-then-branch-target', [
      { id: 'create', type: 'team-create', team_name: 'solo' },
      { id: 'leg', type: 'command' }, // branch target
      { id: 'br', type: 'branch', if_zero: 'leg', if_nonzero: 'leg2' },
      { id: 'leg2', type: 'command', terminal: true },
    ])
    const { edges } = buildLayout(w)
    // FR-1.3: 'leg' is a branch target → no default chain create → leg.
    expect(
      edges.some((e) => e.source === 'create' && e.target === 'leg' && e.data?.kind === 'next'),
    ).toBe(false)
  })
})

// FR-1.4: loop substep coverage edge cases ------------------------------

describe('buildLayout — loop without substep (FR-1.4)', () => {
  it('does not inject a substep node when the loop step has no substep', () => {
    const w = wf('bare-loop', [
      { id: 'init', type: 'command' },
      { id: 'l', type: 'loop', max_iterations: 3 },
      { id: 'after', type: 'command', terminal: true },
    ])
    const { nodes } = buildLayout(w)
    expect(nodes.find((n) => n.id === 'l-substep')).toBeUndefined()
  })
})

// FR-1.6: expanded sub-workflow with empty steps ------------------------

describe('buildLayout — expanded sub-workflow edge cases (FR-1.6)', () => {
  it('skips a sub-workflow with no steps', () => {
    const parent = wf('parent', [
      { id: 'a', type: 'command' },
      { id: 'sub-step', type: 'teammate', team: 'create' },
      { id: 'b', type: 'command', terminal: true },
    ])
    const empty: Workflow = wf('empty-sub', [])
    const expanded = new Map<string, Workflow>([['sub-step', empty]])
    const { nodes } = buildLayout(parent, expanded)
    // Only the 3 parent nodes — no sub-DAG children injected.
    expect(nodes.filter((n) => n.data.isSubDAGChild).length).toBe(0)
  })

  it('skips when the parentId does not match any node', () => {
    const parent = wf('parent', [{ id: 'a', type: 'command', terminal: true }])
    const sub = wf('sub', [{ id: 's1', type: 'command' }])
    const expanded = new Map<string, Workflow>([['no-such-id', sub]])
    const { nodes } = buildLayout(parent, expanded)
    expect(nodes.filter((n) => n.data.isSubDAGChild).length).toBe(0)
  })
})

// FR-1.7: team-wait with no matching teammates --------------------------

describe('buildLayout — team-wait with empty teammate set (FR-1.7)', () => {
  it('does not emit fan-in edges when no teammates reference the team', () => {
    const w = wf('lonely-wait', [
      { id: 'create', type: 'team-create', team_name: 'lonely' },
      { id: 'wait', type: 'team-wait', team: 'create', terminal: true },
    ])
    const { edges } = buildLayout(w)
    expect(edges.some((e) => e.data?.kind === 'team-fan-in')).toBe(false)
  })
})

// Workflow with empty steps (defensive) ---------------------------------

describe('buildLayout — empty workflow', () => {
  it('returns an empty layout for a workflow with no steps', () => {
    const w: Workflow = wf('empty', [])
    const { nodes, edges } = buildLayout(w)
    expect(nodes).toHaveLength(0)
    expect(edges).toHaveLength(0)
  })
})

// Determinism (per contract: byte-identical output for byte-identical input)

describe('buildLayout — determinism', () => {
  it('produces byte-identical output across two calls with the same input', () => {
    const w = wf('det', [
      { id: 'a', type: 'command' },
      { id: 'b', type: 'command' },
      { id: 'c', type: 'command', terminal: true },
    ])
    const a = buildLayout(w)
    const b = buildLayout(w)
    expect(JSON.stringify(a)).toBe(JSON.stringify(b))
  })
})
