'use client'

// FlowDiagram — React Flow shell wrapping the pure-functional `buildLayout`.
//
// FR-1.1..1.8 — layout work lives in `lib/layout.ts`; this component is a
// thin renderer that translates LayoutResult → React Flow nodes/edges and
// wires interactivity (selection highlight, double-click expand,
// fit-to-view re-render on workflow / expansion change).

import { useCallback, useMemo, useEffect, useRef } from 'react'
import {
  ReactFlow,
  Background,
  Controls,
  MiniMap,
  useNodesState,
  useEdgesState,
  useReactFlow,
  MarkerType,
} from '@xyflow/react'
import '@xyflow/react/dist/style.css'
import WorkflowNode from './WorkflowNode'
import SubDAGGroupNode from './SubDAGGroupNode'
import { buildLayout, LAYOUT_GROUP_PAD, LAYOUT_GROUP_TITLE_H, type GraphEdge } from '@/lib/layout'
import type { Workflow } from '@/lib/types'

interface FlowDiagramProps {
  workflow: Workflow
  selectedStepId: string | null
  onSelectStep: (stepId: string) => void
  expandedWorkflows?: Map<string, Workflow>
}

// FR-1.1 — minimap node-color mapping. Mirrors WorkflowNode's color family.
function getNodeColor(type: string): string {
  if (type === 'command') return '#3fb950'
  if (type === 'agent') return '#a78bfa'
  if (type === 'workflow') return '#38bdf8'
  if (type === 'branch') return '#f59e0b'
  if (type === 'loop') return '#ec4899'
  if (type === 'parallel') return '#06b6d4'
  if (type === 'approval') return '#8b5cf6'
  // FR-2.2 — team-step color family (cyan/blue spectrum, distinct from agent purple).
  if (type === 'team-create' || type === 'team-wait' || type === 'team-delete') return '#0ea5e9'
  if (type === 'teammate') return '#22d3ee'
  return '#5c6b7d'
}

// FR-1.1 — edge styling per LayoutResult kind. Centralizes the visual
// vocabulary so the layout engine stays renderer-agnostic.
function styleForEdge(edge: GraphEdge) {
  const kind = edge.data?.kind ?? 'next'
  switch (kind) {
    case 'branch-zero':
      // FR-1.3 — branch zero: amber dashed.
      return {
        type: 'smoothstep',
        animated: true,
        label: edge.data?.label,
        style: { stroke: '#f59e0b', strokeWidth: 2, strokeDasharray: '5 3' },
        labelStyle: { fill: '#f59e0b', fontSize: 9 },
        labelBgStyle: { fill: '#111820', padding: 4 },
        markerEnd: { type: MarkerType.ArrowClosed, color: '#f59e0b' },
      }
    case 'branch-nonzero':
      // FR-1.3 — branch nonzero: amber solid.
      return {
        type: 'smoothstep',
        animated: true,
        label: edge.data?.label,
        style: { stroke: '#f59e0b', strokeWidth: 2 },
        labelStyle: { fill: '#f59e0b', fontSize: 9 },
        labelBgStyle: { fill: '#111820', padding: 4 },
        markerEnd: { type: MarkerType.ArrowClosed, color: '#f59e0b' },
      }
    case 'skip':
      return {
        type: 'smoothstep',
        style: { stroke: '#475569', strokeWidth: 1.5, strokeDasharray: '3 3' },
        markerEnd: { type: MarkerType.ArrowClosed, color: '#475569' },
      }
    case 'loop-back':
      // FR-1.4 — loop back-edge: pink dashed, animated.
      return {
        type: 'smoothstep',
        animated: true,
        label: edge.data?.label,
        style: { stroke: '#ec4899', strokeWidth: 1.5, strokeDasharray: '4 2' },
        labelStyle: { fill: '#ec4899', fontSize: 11 },
        labelBgStyle: { fill: '#111820', padding: 3 },
        markerEnd: { type: MarkerType.ArrowClosed, color: '#ec4899' },
      }
    case 'expanded':
      // FR-1.6 — expanded sub-DAG: dashed cyan (preserved visual treatment).
      return {
        type: 'smoothstep',
        animated: true,
        style: { stroke: '#38bdf8', strokeWidth: 2, strokeDasharray: '8 4' },
        markerEnd: { type: MarkerType.ArrowClosed, color: '#38bdf8' },
      }
    case 'team-fan-in':
      // FR-1.7 — team fan-in: cyan solid, slightly thicker so the
      // converging shape reads visually.
      return {
        type: 'smoothstep',
        style: { stroke: '#0ea5e9', strokeWidth: 2 },
        markerEnd: { type: MarkerType.ArrowClosed, color: '#0ea5e9' },
      }
    case 'next':
    default:
      return {
        type: 'smoothstep',
        style: { stroke: '#2a3544', strokeWidth: 2 },
        markerEnd: { type: MarkerType.ArrowClosed, color: '#2a3544' },
      }
  }
}

export default function FlowDiagram({
  workflow,
  selectedStepId,
  onSelectStep,
  expandedWorkflows,
}: FlowDiagramProps) {
  // FR-1.1..1.8 — delegate ALL positioning to the pure-functional layout
  // engine. This component just adapts the result for React Flow.
  // Sub-DAG group nodes carry width/height + parentId/extent → propagated
  // both at the top level AND inside `style` so React Flow v12 actually
  // renders the group at the declared size (style-side is what the DOM
  // measures; node-side feeds layout math).
  const { nodes: rfNodes, edges: rfEdges } = useMemo(() => {
    const layout = buildLayout(workflow, expandedWorkflows)
    const nodes = layout.nodes.map((n) => {
      const baseStyle: React.CSSProperties = {}
      if (n.width !== undefined) baseStyle.width = n.width
      if (n.height !== undefined) baseStyle.height = n.height
      return {
        id: n.id,
        type: n.type ?? 'workflowNode',
        position: n.position,
        data: {
          step: n.data.step,
          type: n.data.step?.type ?? 'command',
          subWorkflowName: n.data.subWorkflowName,
        },
        ...(n.parentId ? { parentId: n.parentId } : {}),
        ...(n.extent ? { extent: n.extent } : {}),
        ...(n.width !== undefined ? { width: n.width } : {}),
        ...(n.height !== undefined ? { height: n.height } : {}),
        ...(n.zIndex !== undefined ? { zIndex: n.zIndex } : {}),
        ...(Object.keys(baseStyle).length > 0 ? { style: baseStyle } : {}),
      }
    })
    const edges = layout.edges.map((e) => ({
      id: e.id,
      source: e.source,
      target: e.target,
      ...styleForEdge(e),
    }))
    return { nodes, edges }
  }, [workflow, expandedWorkflows])

  const [nodes, setNodes, onNodesChange] = useNodesState(rfNodes)
  const [edges, setEdges, onEdgesChange] = useEdgesState(rfEdges)
  const prevWorkflowRef = useRef<string>('')
  const prevExpandedSizeRef = useRef<number>(0)
  const { fitView } = useReactFlow()

  useEffect(() => {
    if (prevWorkflowRef.current !== workflow.name) {
      prevWorkflowRef.current = workflow.name
      setNodes(rfNodes)
      setEdges(rfEdges)
    } else {
      const expandedSize = expandedWorkflows?.size ?? 0
      if (expandedSize !== prevExpandedSizeRef.current) {
        prevExpandedSizeRef.current = expandedSize
        setNodes(rfNodes)
        setEdges(rfEdges)
        // FR-1.6 — re-fit-view after sub-DAG injection so the larger graph
        // is visible without manual zoom.
        setTimeout(() => fitView({ padding: 0.3, duration: 300 }), 50)
      }
    }
  }, [workflow, rfNodes, rfEdges, setNodes, setEdges, expandedWorkflows, fitView])

  // FR-1.1 — selection-context highlight: dim every node not (selectedStepId,
  // its declared context_from sources, or its sequential predecessor).
  const highlightedNodes = useMemo(() => {
    if (!selectedStepId) return new Set<string>()
    const deps = new Set<string>([selectedStepId])
    const stepIdx = workflow.steps.findIndex((s) => s.id === selectedStepId)
    if (stepIdx >= 0) {
      const step = workflow.steps[stepIdx]
      step.context_from?.forEach((c) => deps.add(c))
      if (stepIdx > 0) {
        const prev = workflow.steps[stepIdx - 1]
        deps.add(prev.id ?? `step-${stepIdx - 1}`)
      }
    }
    return deps
  }, [selectedStepId, workflow])

  const onNodeClick = useCallback(
    (_: React.MouseEvent, node: { id: string }) => {
      onSelectStep(node.id)
    },
    [onSelectStep],
  )

  // FR-1.6 — double-click on a step that has a sub-workflow triggers expansion.
  // The owning page resolves the sub-workflow and passes it through
  // `expandedWorkflows`; here we just propagate the click.
  const onNodeDoubleClick = useCallback(
    (_: React.MouseEvent, node: { id: string }) => {
      onSelectStep(node.id)
    },
    [onSelectStep],
  )

  // FR-1.6 visual-fidelity — recompute the group box ONLY on drag-stop.
  // Per-frame recompute (onNodeDrag) caused two visible bugs: (a) the box
  // jittered as it tracked each cursor frame, (b) the translate-children-
  // back logic shifted siblings out from under the cursor mid-drag.
  //
  // Drag-stop semantics:
  //   1. Take children's CURRENT positions (relative to group origin)
  //   2. Compute the snug bounding box that contains every child +
  //      padding + title-bar height
  //   3. If any child went LEFT or UP of the title-bar origin (impossible
  //      under extent:'parent' clipping, but defensive), shift the group's
  //      absolute position back by that delta AND shift children forward
  //      by the same delta so they look unmoved
  //   4. Apply new width/height to the group node
  //
  // The box NEVER shrinks below the original layout-computed size — it
  // only grows to encompass children that have wandered outward. Shrinking
  // would mean clipping children that aren't currently at the edge.
  // FR-1.6 visual-fidelity — recompute every group's bounding box on
  // drag-stop. Walking ALL groups (rather than only the one inferred
  // from draggedNode.parentId) is defensive against React Flow handler
  // signature variance and works for both child-drag (the typical case)
  // AND for group-drag (no-op since children are relative-positioned).
  const onNodeDragStop = useCallback(
    () => {
      setNodes((nds) => {
        const NODE_W = 240
        const NODE_H = 90
        // Collect every group node + its children.
        const groups = nds.filter((n) => n.type === 'subDAGGroup')
        if (groups.length === 0) return nds
        const childrenByGroup = new Map<string, typeof nds>()
        for (const n of nds) {
          if (n.parentId) {
            const list = childrenByGroup.get(n.parentId) ?? []
            list.push(n)
            childrenByGroup.set(n.parentId, list)
          }
        }

        // For each group: compute the bbox of its children + decide if
        // (a) the box needs to grow / shrink and (b) the box origin
        // needs to shift to keep children inside (PAD, PAD+TITLE_H+).
        const groupUpdates = new Map<
          string,
          { width: number; height: number; shiftX: number; shiftY: number }
        >()
        for (const g of groups) {
          const children = childrenByGroup.get(g.id) ?? []
          if (children.length === 0) continue
          let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
          for (const c of children) {
            minX = Math.min(minX, c.position.x)
            minY = Math.min(minY, c.position.y)
            maxX = Math.max(maxX, c.position.x + NODE_W)
            maxY = Math.max(maxY, c.position.y + NODE_H)
          }
          const shiftX = Math.max(0, LAYOUT_GROUP_PAD - minX)
          const shiftY = Math.max(0, (LAYOUT_GROUP_PAD + LAYOUT_GROUP_TITLE_H) - minY)
          const shiftedMaxX = maxX + shiftX
          const shiftedMaxY = maxY + shiftY
          const width = shiftedMaxX + LAYOUT_GROUP_PAD
          const height = shiftedMaxY + LAYOUT_GROUP_PAD
          groupUpdates.set(g.id, { width, height, shiftX, shiftY })
        }

        if (groupUpdates.size === 0) return nds

        return nds.map((n) => {
          const update = groupUpdates.get(n.id)
          if (update) {
            const baseStyle = (n.style ?? {}) as React.CSSProperties
            return {
              ...n,
              position: {
                x: n.position.x - update.shiftX,
                y: n.position.y - update.shiftY,
              },
              width: update.width,
              height: update.height,
              style: { ...baseStyle, width: update.width, height: update.height },
            }
          }
          if (n.parentId) {
            const parentUpdate = groupUpdates.get(n.parentId)
            if (parentUpdate && (parentUpdate.shiftX !== 0 || parentUpdate.shiftY !== 0)) {
              return {
                ...n,
                position: {
                  x: n.position.x + parentUpdate.shiftX,
                  y: n.position.y + parentUpdate.shiftY,
                },
              }
            }
          }
          return n
        })
      })
    },
    [setNodes],
  )

  return (
    <div className="flow-container">
      <ReactFlow
        nodes={nodes.map((n) => ({
          ...n,
          style: {
            opacity: selectedStepId && !highlightedNodes.has(n.id) ? 0.4 : 1,
          } as React.CSSProperties,
        }))}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onNodeClick={onNodeClick}
        onNodeDoubleClick={onNodeDoubleClick}
        onNodeDragStop={onNodeDragStop}
        nodeTypes={{
          workflowNode: WorkflowNode as never,
          subDAGGroup: SubDAGGroupNode as never,
        }}
        fitView
        fitViewOptions={{ padding: 0.3 }}
        minZoom={0.2}
        maxZoom={2}
        defaultEdgeOptions={{
          type: 'smoothstep',
          style: { stroke: '#2a3544', strokeWidth: 2 },
        }}
      >
        <Background color="#1e2732" gap={20} size={1} />
        <Controls />
        <MiniMap
          nodeColor={(node) => getNodeColor((node.data as { type?: string })?.type ?? 'command')}
          maskColor="rgba(10, 14, 20, 0.8)"
        />
      </ReactFlow>
    </div>
  )
}
