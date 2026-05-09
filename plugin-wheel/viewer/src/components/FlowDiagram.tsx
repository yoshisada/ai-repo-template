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
import { buildLayout, type GraphEdge } from '@/lib/layout'
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
  const { nodes: rfNodes, edges: rfEdges } = useMemo(() => {
    const layout = buildLayout(workflow, expandedWorkflows)
    const nodes = layout.nodes.map((n) => ({
      id: n.id,
      type: n.type ?? 'workflowNode',
      position: n.position,
      data: { step: n.data.step, type: n.data.step.type ?? 'command' },
    }))
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
        nodeTypes={{ workflowNode: WorkflowNode as never }}
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
