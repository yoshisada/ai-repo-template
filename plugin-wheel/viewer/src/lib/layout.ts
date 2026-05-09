// Pure-functional layered DAG layout for workflow visualization.
//
// Implements FR-1.1 through FR-1.8 of wheel-viewer-definition-quality:
//   FR-1.1: Identify the workflow's logical DAG by following next-step (default),
//           if_zero / if_nonzero (branch), skip (jump), and substep (loop body).
//   FR-1.2: Compute node positions via a layered topological-rank algorithm
//           (longest-path layering — hand-rolled, NO dagre dep per plan D-1).
//   FR-1.3: Branch targets that join back render at the rejoin point (longest-path
//           ranking naturally produces this).
//   FR-1.4: Loop substeps render as a nested node anchored to the loop step
//           with a labeled back-edge.
//   FR-1.5: Parallel children render as siblings at the same rank.
//   FR-1.6: Expanded sub-workflows render below their parent as a self-contained
//           sub-DAG with its own layered layout (isSubDAGChild = true).
//   FR-1.7: Team-step fan-out / fan-in — team-create → all teammates,
//           teammates → team-wait via 'team-fan-in' edges.
//   FR-1.8: No two nodes overlap (sibling spread + rank stacking ensure this).
//
// Pure: identical input → byte-identical (nodes, edges). No I/O, no Date.now,
// no Math.random. See plan.md D-1 + contracts/interfaces.md for the algorithm
// sketch and exported signatures.

import type { Step, Workflow } from './types'

// FR-1.2 — Layout grid constants. Exposed for FlowDiagram fitView and tests.
export const LAYOUT_RANK_HEIGHT = 160
export const LAYOUT_NODE_SPACING_X = 240
export const LAYOUT_SUB_DAG_OFFSET_Y = 200

// FR-1.2 — A positioned graph node. Shape matches contracts/interfaces.md
// (React-Flow native: position.x/y + data payload).
export interface GraphNode {
  id: string
  position: { x: number; y: number }
  data: {
    step: Step
    rank: number
    isExpanded?: boolean
    isSubDAGChild?: boolean
  }
  type?: string
}

// FR-1.1 — A typed edge. The renderer chooses visual treatment by `data.kind`.
export interface GraphEdge {
  id: string
  source: string
  target: string
  data?: {
    kind:
      | 'next'
      | 'branch-zero'
      | 'branch-nonzero'
      | 'skip'
      | 'loop-back'
      | 'expanded'
      | 'team-fan-in'
    label?: string
  }
  type?: string
  className?: string
  animated?: boolean
}

export interface LayoutResult {
  nodes: GraphNode[]
  edges: GraphEdge[]
}

// --- Internal helpers ---------------------------------------------------

function stepIdOf(s: Step, i: number): string {
  return s.id ?? `step-${i}`
}

// FR-1.7 — Map team-create step IDs to teammate step IDs that reference them.
function buildTeamIndex(steps: Step[]): Map<string, string[]> {
  const idx = new Map<string, string[]>()
  steps.forEach((s, i) => {
    if (s.type === 'teammate' && typeof s.team === 'string') {
      const id = stepIdOf(s, i)
      const list = idx.get(s.team) ?? []
      list.push(id)
      idx.set(s.team, list)
    }
  })
  return idx
}

// FR-1.1 — Build the full edge set in a stable order so the layout is
// deterministic. Returned edges include 'next' (default forward), branch
// targets, skip jumps, and team fan-in. Substep + loop-back + expanded
// edges are added later by the substep / sub-DAG routines.
function buildEdges(steps: Step[]): GraphEdge[] {
  const edges: GraphEdge[] = []
  const ids = steps.map(stepIdOf)
  const idSet = new Set(ids)
  const teammatesByTeam = buildTeamIndex(steps)

  // FR-1.3 — A step that is the target of a branch (if_zero / if_nonzero)
  // is reached ONLY via the branch routing. Its predecessor's default
  // forward fall-through is suppressed so the two legs sit in parallel
  // at the same rank rather than chained sequentially.
  const branchTargets = new Set<string>()
  steps.forEach((s) => {
    if (typeof s.if_zero === 'string') branchTargets.add(s.if_zero)
    if (typeof s.if_nonzero === 'string') branchTargets.add(s.if_nonzero)
  })

  steps.forEach((s, i) => {
    const id = ids[i]
    const next = steps[i + 1]
    const nextId = next ? ids[i + 1] : null

    // FR-1.7: Teammate steps are reached via team-create's fan-out, not via
    // sequential next chaining — skip the default forward edge entirely.
    if (s.type === 'teammate') {
      return
    }

    // FR-1.7: team-create fans out to every teammate referencing it.
    if (s.type === 'team-create') {
      const teammates = teammatesByTeam.get(id) ?? []
      teammates.forEach((tid) => {
        edges.push({
          id: `e-${id}-${tid}`,
          source: id,
          target: tid,
          data: { kind: 'next' },
        })
      })
      // Default chain to next step ONLY if it isn't a teammate of this team
      // and isn't a branch target (FR-1.3).
      if (
        next &&
        !(next.type === 'teammate' && next.team === id) &&
        !branchTargets.has(nextId as string)
      ) {
        edges.push({
          id: `e-${id}-${nextId}`,
          source: id,
          target: nextId as string,
          data: { kind: 'next' },
        })
      }
      return
    }

    // FR-1.7: team-wait fan-in — one edge per teammate of the same team.
    // This is in addition to (not in place of) the team-wait's own forward
    // chain to its next step, which falls through below.
    if (s.type === 'team-wait' && typeof s.team === 'string') {
      const teammates = teammatesByTeam.get(s.team) ?? []
      teammates.forEach((tid) => {
        edges.push({
          id: `e-${tid}-${id}-fanin`,
          source: tid,
          target: id,
          data: { kind: 'team-fan-in' },
        })
      })
    }

    // FR-1.1: Default forward edge i → i+1 unless terminal, only-skip, or
    // FR-1.3: the next step is a branch-target (reached only via branch routing).
    if (!s.terminal && !s.skip && next && !branchTargets.has(nextId as string)) {
      edges.push({
        id: `e-${id}-${nextId}`,
        source: id,
        target: nextId as string,
        data: { kind: 'next' },
      })
    }

    // FR-1.3: Branch edges. Targets must resolve to a sibling step id; orphan
    // refs are silently dropped here (lint surfaces them via L-003).
    if (s.if_zero && idSet.has(s.if_zero)) {
      edges.push({
        id: `e-${id}-${s.if_zero}-zero`,
        source: id,
        target: s.if_zero,
        data: { kind: 'branch-zero', label: 'if_zero' },
      })
    }
    if (s.if_nonzero && idSet.has(s.if_nonzero)) {
      edges.push({
        id: `e-${id}-${s.if_nonzero}-nonzero`,
        source: id,
        target: s.if_nonzero,
        data: { kind: 'branch-nonzero', label: 'if_nonzero' },
      })
    }
    // FR-1.1: Skip jumps (lint catches unresolved targets via L-004).
    if (s.skip && idSet.has(s.skip)) {
      edges.push({
        id: `e-${id}-${s.skip}-skip`,
        source: id,
        target: s.skip,
        data: { kind: 'skip', label: 'skip' },
      })
    }
  })

  return edges
}

// FR-1.2 / FR-1.3 — Longest-path rank assignment. Iterative relaxation
// works for any DAG; loop-back edges are excluded so cycles introduced by
// FR-1.4 don't drive ranks to infinity. Capped at nodeCount + 1 iterations.
function computeRanks(nodeIds: string[], edges: GraphEdge[]): Map<string, number> {
  const rank = new Map<string, number>()
  nodeIds.forEach((id) => rank.set(id, 0))

  for (let iter = 0; iter <= nodeIds.length; iter++) {
    let changed = false
    for (const e of edges) {
      if (e.data?.kind === 'loop-back') continue
      const ru = rank.get(e.source) ?? 0
      const rv = rank.get(e.target) ?? 0
      if (rv < ru + 1) {
        rank.set(e.target, ru + 1)
        changed = true
      }
    }
    if (!changed) break
  }
  return rank
}

// FR-1.4 — Loop substep cluster + labeled back-edge.
// Mutates `nodes`, `edges`, `rank` in place (so the caller can re-run rank
// pass with the substep included). Substep node id format: `<parent>-substep`.
function injectLoopSubsteps(
  steps: Step[],
  nodes: GraphNode[],
  edges: GraphEdge[],
  rank: Map<string, number>,
): void {
  steps.forEach((s, i) => {
    if (s.type !== 'loop' || !s.substep) return
    const parentId = stepIdOf(s, i)
    const substepId = `${parentId}-substep`
    const substep = s.substep
    nodes.push({
      id: substepId,
      position: { x: 0, y: 0 },
      data: {
        step: substep,
        rank: 0, // assigned below
      },
      type: 'workflowNode',
    })
    const parentRank = rank.get(parentId) ?? 0
    rank.set(substepId, parentRank + 1)
    // Forward edge into substep (same kind as a normal next-step).
    edges.push({
      id: `e-${parentId}-${substepId}-substep`,
      source: parentId,
      target: substepId,
      data: { kind: 'next', label: 'iterate' },
    })
    // FR-1.4: visual back-edge (loop-back) from substep to its parent.
    edges.push({
      id: `e-${substepId}-${parentId}-loop`,
      source: substepId,
      target: parentId,
      data: { kind: 'loop-back', label: '↺' },
      animated: true,
    })
  })
}

// FR-1.2 / FR-1.5 / FR-1.8 — Position each node by its rank (y) and by its
// horizontal index among siblings (x). Sibling order preserves the order
// in which nodes were added so the layout is deterministic.
function positionByRank(nodes: GraphNode[], rank: Map<string, number>): void {
  const byRank = new Map<number, GraphNode[]>()
  nodes.forEach((n) => {
    const r = rank.get(n.id) ?? 0
    n.data.rank = r
    const list = byRank.get(r) ?? []
    list.push(n)
    byRank.set(r, list)
  })
  byRank.forEach((siblings, r) => {
    const total = siblings.length
    const startX = -((total - 1) * LAYOUT_NODE_SPACING_X) / 2
    siblings.forEach((n, i) => {
      n.position = { x: startX + i * LAYOUT_NODE_SPACING_X, y: r * LAYOUT_RANK_HEIGHT }
    })
  })
}

// FR-1.6 — Append expanded sub-workflows below the parent flow as their own
// layered sub-DAG. Each sub-node carries `isSubDAGChild: true` so the
// renderer can apply cluster styling.
function appendExpandedSubWorkflows(
  parentNodes: GraphNode[],
  parentEdges: GraphEdge[],
  expanded: Map<string, Workflow>,
): void {
  if (expanded.size === 0) return

  const parentMaxY = parentNodes.reduce((m, n) => Math.max(m, n.position.y), 0)
  let baseY = parentMaxY + LAYOUT_SUB_DAG_OFFSET_Y

  for (const [parentId, subWf] of expanded) {
    const parent = parentNodes.find((n) => n.id === parentId)
    if (!parent) continue
    parent.data.isExpanded = true

    // Recurse — sub-workflows can themselves contain branches / loops / teams.
    const sub = buildLayout(subWf)
    if (sub.nodes.length === 0) continue

    // Translate sub-coordinates so the sub-DAG is centered under the parent
    // and below `baseY`. We compute the sub's bounding box from the recurse
    // output and pick the dx/dy that places its top centered under parent.x.
    const subXs = sub.nodes.map((n) => n.position.x)
    const subYs = sub.nodes.map((n) => n.position.y)
    const subMinX = Math.min(...subXs)
    const subMaxX = Math.max(...subXs)
    const subCenter = (subMinX + subMaxX) / 2
    const subMinY = Math.min(...subYs)
    const subMaxY = Math.max(...subYs)
    const dx = parent.position.x - subCenter
    const dy = baseY - subMinY

    const idMap = new Map<string, string>()
    sub.nodes.forEach((n) => {
      const newId = `expanded-${parentId}-${n.id}`
      idMap.set(n.id, newId)
      parentNodes.push({
        id: newId,
        position: { x: n.position.x + dx, y: n.position.y + dy },
        data: {
          step: n.data.step,
          rank: n.data.rank,
          isSubDAGChild: true,
        },
        type: n.type,
      })
    })
    sub.edges.forEach((e) => {
      parentEdges.push({
        id: `expanded-${parentId}-${e.id}`,
        source: idMap.get(e.source) ?? e.source,
        target: idMap.get(e.target) ?? e.target,
        data: e.data ? { ...e.data } : undefined,
        type: e.type,
        className: e.className,
        animated: e.animated,
      })
    })

    // FR-1.6: dashed-cyan-style edge from parent → each sub-DAG entry node.
    const targetIds = new Set(sub.edges.map((e) => e.target))
    const entries = sub.nodes.filter((n) => !targetIds.has(n.id))
    entries.forEach((n) => {
      parentEdges.push({
        id: `e-${parentId}-${idMap.get(n.id)}`,
        source: parentId,
        target: idMap.get(n.id) as string,
        data: { kind: 'expanded' },
        animated: true,
      })
    })

    baseY += subMaxY - subMinY + LAYOUT_SUB_DAG_OFFSET_Y
  }
}

// --- Public API ---------------------------------------------------------

// FR-1.1..FR-1.8 — pure function. Identical inputs produce byte-identical
// outputs (sort orders fixed, no Date.now / Math.random in any path).
export function buildLayout(
  workflow: Workflow,
  expandedWorkflows?: Map<string, Workflow>,
): LayoutResult {
  const steps = workflow.steps ?? []

  // FR-1.1: nodes for every step.
  const nodes: GraphNode[] = steps.map((s, i) => ({
    id: stepIdOf(s, i),
    position: { x: 0, y: 0 },
    data: { step: s, rank: 0 },
    type: 'workflowNode',
  }))

  // FR-1.1: build the edge set (next / branch / skip / team fan-in).
  const edges: GraphEdge[] = buildEdges(steps)

  // FR-1.2 / FR-1.3: first rank pass — over the main DAG.
  const rank = computeRanks(
    nodes.map((n) => n.id),
    edges,
  )

  // FR-1.4: inject loop substeps (adds nodes + edges, sets initial rank).
  injectLoopSubsteps(steps, nodes, edges, rank)

  // Re-rank including substeps so any predecessor relationships introduced
  // by substep edges propagate. Loop-back edges are skipped by computeRanks.
  const allIds = nodes.map((n) => n.id)
  const rerank = computeRanks(allIds, edges)
  // Preserve the substep-rank floor (parent + 1) in case rerank doesn't
  // promote it past the parent.
  steps.forEach((s, i) => {
    if (s.type !== 'loop' || !s.substep) return
    const parentId = stepIdOf(s, i)
    const substepId = `${parentId}-substep`
    const parentRank = rerank.get(parentId) ?? 0
    const subRank = rerank.get(substepId) ?? 0
    if (subRank <= parentRank) rerank.set(substepId, parentRank + 1)
  })

  // FR-1.5 / FR-1.8: position by rank.
  positionByRank(nodes, rerank)

  // FR-1.6: append expanded sub-workflows below.
  if (expandedWorkflows && expandedWorkflows.size > 0) {
    appendExpandedSubWorkflows(nodes, edges, expandedWorkflows)
  }

  return { nodes, edges }
}
