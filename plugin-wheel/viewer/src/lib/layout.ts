// Pure-functional layered DAG layout for workflow visualization.
//
// Implements FR-1.1 through FR-1.8 of wheel-viewer-definition-quality:
//   FR-1.1: Identify the workflow's logical DAG by following next-step (default),
//           if_zero / if_nonzero (branch), skip (jump), and substep (loop body).
//   FR-1.2: Compute node positions via dagre's Sugiyama layered layout
//           (revised from plan.md D-1's hand-rolled approach — see positionByRank
//           comment for the why). dagre handles crossing minimization + edge
//           routing through dummy nodes, which hand-rolling cannot guarantee.
//   FR-1.3: Branch targets that join back render at the rejoin point (dagre's
//           network-simplex ranker naturally produces this).
//   FR-1.4: Loop substeps render as a nested node anchored to the loop step
//           with a labeled back-edge.
//   FR-1.5: Parallel children render as siblings at the same rank.
//   FR-1.6: Expanded sub-workflows render INLINE below their parent (push down
//           subsequent main-DAG ranks; isSubDAGChild = true for cluster styling).
//   FR-1.7: Team-step fan-out / fan-in — team-create → all teammates,
//           teammates → team-wait via 'team-fan-in' edges.
//   FR-1.8: No two nodes overlap AND no edges cross node bodies (dagre's
//           coordinate assignment with edge-aware separation guarantees this).
//
// Pure: identical input → byte-identical (nodes, edges). No I/O, no Date.now,
// no Math.random. dagre's `layout(g)` is deterministic given identical input.

import type { Step, Workflow } from './types'
import * as dagreModule from '@dagrejs/dagre'

// FR-1.2 — Legacy rank-height constant. Retained for FlowDiagram fitView
// math + tests that assert relative y-spacing. dagre now drives actual
// positions, but downstream code still references LAYOUT_RANK_HEIGHT as a
// nominal rank step.
export const LAYOUT_RANK_HEIGHT = 160
export const LAYOUT_NODE_SPACING_X = 240
export const LAYOUT_SUB_DAG_OFFSET_Y = 200

// FR-1.2 — dagre tuning. Node box size is the canvas the React-Flow node
// occupies (must match WorkflowNode.tsx's intrinsic width × height so
// dagre's collision math reflects the actual rendered DOM).
const LAYOUT_NODE_WIDTH = 240
const LAYOUT_NODE_HEIGHT = 90
// Sep values control gutters between dagre-laid-out elements. Generous
// values reduce visual cramming + give edges more bend room.
const LAYOUT_NODE_SEP = 80   // horizontal gap between siblings at same rank
const LAYOUT_RANK_SEP = 110  // vertical gap between consecutive ranks
const LAYOUT_EDGE_SEP = 30   // gap between parallel edges in same channel

// Sub-DAG group container — bounding-box padding around children + title
// bar height. Both are referenced when sizing the group node AND when
// translating child coordinates to be relative to the group origin.
export const LAYOUT_GROUP_PAD = 24
export const LAYOUT_GROUP_TITLE_H = 32

// FR-1.2 — A positioned graph node. Shape matches contracts/interfaces.md
// (React-Flow native: position.x/y + data payload).
//
// Sub-DAG group nodes (`type: 'subDAGGroup'`) carry width/height directly
// so React Flow renders the bounding box at the correct size. Their
// `data.subWorkflowName` becomes the title rendered at the top of the box.
//
// Sub-DAG children carry `parentId` referencing their group node so React
// Flow's parent-child semantics (drag-as-one, extent-clip) apply. Their
// `position` is RELATIVE to the parent (group-origin coordinates).
export interface GraphNode {
  id: string
  position: { x: number; y: number }
  data: {
    step: Step
    rank: number
    isExpanded?: boolean
    isSubDAGChild?: boolean
    subWorkflowName?: string
    subDAGGroupId?: string
  }
  type?: string
  parentId?: string
  extent?: 'parent'
  width?: number
  height?: number
  zIndex?: number
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

// FR-1.2 / FR-1.5 / FR-1.8 — Delegate positioning to dagre's Sugiyama
// layered layout. Handles rank assignment, sibling ordering to minimize
// crossings, and edge routing — the three things the hand-rolled
// implementation could not do without obstacle avoidance.
//
// Why dagre over a richer hand-roll: layered DAGs without obstacle
// avoidance fundamentally cannot guarantee "no edges crossing nodes" in
// the presence of fan-in (team-wait), fan-out (team-create), branches,
// loops, and expanded sub-DAGs simultaneously. Dagre (1.4MB on disk,
// ~40KB minified+gzipped) implements the standard Sugiyama pipeline:
// rank assignment → crossing minimization → coordinate assignment with
// dummy-node-augmented edge routing.
//
// FR-1.4 loop-back edges are EXCLUDED from the dagre graph (dagre would
// rank-tangle them); they're rendered visually but don't influence layout.
function positionByRank(
  nodes: GraphNode[],
  edges: GraphEdge[],
  rank: Map<string, number>,
): void {
  // Record rank on each node for renderer hooks that key off it (e.g.
  // alternating-rank background bands). We compute the rank ourselves
  // so we don't depend on dagre's internal rank labels.
  nodes.forEach((n) => {
    n.data.rank = rank.get(n.id) ?? 0
  })

  const g = new dagreModule.graphlib.Graph()
  g.setGraph({
    rankdir: 'TB',           // top-to-bottom layered
    align: 'UL',             // upper-left alignment within rank
    nodesep: LAYOUT_NODE_SEP,
    ranksep: LAYOUT_RANK_SEP,
    edgesep: LAYOUT_EDGE_SEP,
    marginx: 20,
    marginy: 20,
    acyclicer: 'greedy',
    ranker: 'tight-tree',
  })
  g.setDefaultEdgeLabel(() => ({}))

  nodes.forEach((n) => {
    g.setNode(n.id, {
      width: LAYOUT_NODE_WIDTH,
      height: LAYOUT_NODE_HEIGHT,
    })
  })

  edges.forEach((e) => {
    // Skip loop-back so dagre doesn't try to flatten the cycle.
    if (e.data?.kind === 'loop-back') return
    g.setEdge(e.source, e.target)
  })

  dagreModule.layout(g)

  // Dagre reports centers; React Flow expects top-left of the node box.
  nodes.forEach((n) => {
    const dn = g.node(n.id)
    if (!dn) return
    n.position = {
      x: dn.x - LAYOUT_NODE_WIDTH / 2,
      y: dn.y - LAYOUT_NODE_HEIGHT / 2,
    }
  })
}

// FR-1.6 — Inline expanded sub-workflows directly under their parent step.
// Pushes down all main-DAG nodes whose y is below the parent so the
// sub-DAG renders IN-FLOW (between the parent and the next rank) rather
// than dangling below the entire main DAG. Each sub-node carries
// `isSubDAGChild: true` so the renderer can apply cluster styling.
function appendExpandedSubWorkflows(
  parentNodes: GraphNode[],
  parentEdges: GraphEdge[],
  expanded: Map<string, Workflow>,
): void {
  if (expanded.size === 0) return

  for (const [parentId, subWf] of expanded) {
    const parent = parentNodes.find((n) => n.id === parentId)
    if (!parent) continue
    parent.data.isExpanded = true

    // Recurse — sub-workflows can themselves contain branches / loops / teams.
    const sub = buildLayout(subWf)
    if (sub.nodes.length === 0) continue

    // Bounding box of the recursed sub-DAG.
    const subXs = sub.nodes.map((n) => n.position.x)
    const subYs = sub.nodes.map((n) => n.position.y)
    const subMinX = Math.min(...subXs)
    const subMaxX = Math.max(...subXs)
    const subCenter = (subMinX + subMaxX) / 2
    const subMinY = Math.min(...subYs)
    const subMaxY = Math.max(...subYs)
    const subHeight = subMaxY - subMinY + LAYOUT_RANK_HEIGHT

    // Insertion strategy: sub-DAG goes IMMEDIATELY BELOW the parent step
    // (parent.y + RANK_HEIGHT * 0.75 — slightly less than a full rank so
    // the visual nesting reads as "inside" rather than "next step").
    const subTopY = parent.position.y + LAYOUT_RANK_HEIGHT * 0.75
    const totalHeightConsumed = subHeight + LAYOUT_RANK_HEIGHT * 0.5

    // Push down every main-DAG node strictly below the parent so the
    // sub-DAG has its own y-space. Operate ONLY on non-sub-DAG nodes
    // (sub-DAG children added by earlier iterations stay in their slot).
    parentNodes.forEach((n) => {
      if (n.id === parentId) return
      if (n.data.isSubDAGChild) return
      if (n.position.y > parent.position.y) {
        n.position = { x: n.position.x, y: n.position.y + totalHeightConsumed }
      }
    })

    // Group bounding box — sub-DAG content + padding for the title bar +
    // breathing room. Group's top-left in absolute (canvas) coords.
    const subContentWidth = subMaxX - subMinX + LAYOUT_NODE_WIDTH
    const subContentHeight = subMaxY - subMinY + LAYOUT_NODE_HEIGHT
    const groupW = subContentWidth + LAYOUT_GROUP_PAD * 2
    const groupH = subContentHeight + LAYOUT_GROUP_PAD * 2 + LAYOUT_GROUP_TITLE_H
    // Center group horizontally under the parent step's x-center.
    const parentCenterX = parent.position.x + LAYOUT_NODE_WIDTH / 2
    const groupX = parentCenterX - groupW / 2
    const groupY = subTopY

    // Emit the group node. Renders as a bounding box with the sub-workflow
    // name at the top — see GroupNode.tsx for the visual treatment.
    const groupId = `expanded-group-${parentId}`
    parentNodes.push({
      id: groupId,
      position: { x: groupX, y: groupY },
      width: groupW,
      height: groupH,
      data: {
        step: parent.data.step,           // for type-color theming on the group
        rank: parent.data.rank + 0.5,
        subWorkflowName: subWf.name,
        isSubDAGChild: false,
      },
      type: 'subDAGGroup',
      zIndex: -1,                          // sit behind children
    })

    // Children's positions are RELATIVE to the group origin. Translate the
    // dagre-computed absolute coords into group-local coords by subtracting
    // (subMinX, subMinY) and adding the inner padding + title bar offset.
    const childDx = LAYOUT_GROUP_PAD - subMinX
    const childDy = LAYOUT_GROUP_PAD + LAYOUT_GROUP_TITLE_H - subMinY

    const idMap = new Map<string, string>()
    sub.nodes.forEach((n) => {
      const newId = `expanded-${parentId}-${n.id}`
      idMap.set(n.id, newId)
      parentNodes.push({
        id: newId,
        position: { x: n.position.x + childDx, y: n.position.y + childDy },
        data: {
          step: n.data.step,
          rank: n.data.rank,
          isSubDAGChild: true,
          subDAGGroupId: groupId,
        },
        type: n.type,
        parentId: groupId,
        extent: 'parent',
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

    // FR-1.6 + visual-fidelity fix — when a parent expands, its OUTGOING
    // main-DAG edges (next, team-fan-in, etc.) MUST originate from the
    // sub-DAG's EXIT nodes instead of from the parent, otherwise those
    // edges visually overlap the freshly-inserted sub-DAG box. The
    // semantic chain becomes:  parent → sub-DAG entry … sub-DAG exit →
    // next main step. Preserves the dashed-cyan parent→entry edge from
    // above as the "this opens here" affordance.
    //
    // Identify sub-DAG exits = nodes with no outgoing edges within the sub.
    const subSourceIds = new Set(sub.edges.map((e) => e.source))
    const exits = sub.nodes
      .filter((n) => !subSourceIds.has(n.id))
      .map((n) => idMap.get(n.id) as string)

    if (exits.length > 0) {
      // Find main-DAG edges that originated FROM the parent step and
      // that target nodes outside this sub-DAG. Reroute their source
      // to the sub-DAG's (single, or first) exit node.
      const exitId = exits[0]
      const newEdges: GraphEdge[] = []
      for (const e of parentEdges) {
        // Leave expansion-internal edges alone; only reroute main-DAG
        // edges whose source is the parent and whose target is NOT a
        // sub-DAG child we just added.
        const targetIsSubChild =
          e.target.startsWith(`expanded-${parentId}-`) ||
          e.id.startsWith(`expanded-${parentId}-`)
        const isExpandedKindFromParent =
          e.data?.kind === 'expanded' && e.source === parentId
        if (
          e.source === parentId &&
          !targetIsSubChild &&
          !isExpandedKindFromParent
        ) {
          newEdges.push({
            ...e,
            id: `${e.id}-rerouted-via-${exitId}`,
            source: exitId,
          })
        } else {
          newEdges.push(e)
        }
      }
      // Mutate in place — preserve identity of the array the caller passed in.
      parentEdges.length = 0
      parentEdges.push(...newEdges)
    }
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
  positionByRank(nodes, edges, rerank)

  // FR-1.6: append expanded sub-workflows below.
  if (expandedWorkflows && expandedWorkflows.size > 0) {
    appendExpandedSubWorkflows(nodes, edges, expandedWorkflows)
  }

  return { nodes, edges }
}
