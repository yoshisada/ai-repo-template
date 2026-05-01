'use client'

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
import type { Workflow } from '@/lib/types'

interface FlowDiagramProps {
  workflow: Workflow
  selectedStepId: string | null
  onSelectStep: (stepId: string) => void
  expandedWorkflows?: Map<string, Workflow>
}

function getStepType(step: { type?: string; if_zero?: string | null; if_nonzero?: string | null }): string {
  if (step.if_zero || step.if_nonzero) return 'branch'
  return step.type || 'command'
}

function getNodeColor(type: string): string {
  if (type === 'command') return '#3fb950'
  if (type === 'agent') return '#a78bfa'
  if (type === 'workflow') return '#38bdf8'
  return '#5c6b7d'
}

interface GraphNode {
  id: string
  type: string
  step: unknown
  x: number
  y: number
}

function buildGraphLayout(workflow: Workflow): GraphNode[] {
  const nodes: GraphNode[] = []

  // Simple vertical layout with no horizontal offset
  // Branches will be shown with dashed edges, not displaced columns
  workflow.steps.forEach((step: unknown, i: number) => {
    const s = step as { id?: string; type?: string; description?: string; command?: string; prompt?: string; instruction?: string; skip?: string; if_zero?: string | null; if_nonzero?: string | null }
    const stepId = s.id || `step-${i}`
    const type = getStepType(s)
    const x = 0
    const y = i * 160
    nodes.push({ id: stepId, type, step: s, x, y })
  })

  return nodes
}

function buildNodesAndEdges(workflow: Workflow, expandedWorkflows?: Map<string, Workflow>) {
  const graphNodes = buildGraphLayout(workflow)

  const nodes = graphNodes.map(gn => ({
    id: gn.id,
    type: 'workflowNode',
    position: { x: gn.x, y: gn.y },
    data: { step: gn.step, type: gn.type },
  }))

  const edges: Array<{
    id: string; source: string; target: string; type?: string; label?: string;
    animated?: boolean; style?: React.CSSProperties; labelStyle?: React.CSSProperties;
    labelBgStyle?: React.CSSProperties; markerEnd?: { type: MarkerType; color: string }
  }> = []

  workflow.steps.forEach((step: unknown, i: number) => {
    const s = step as { id?: string; if_zero?: string | null; if_nonzero?: string | null; skip?: string }
    const stepId = s.id || `step-${i}`

    const nextStep = workflow.steps[i + 1] as { id?: string } | undefined
    if (nextStep && !s.skip) {
      const nextId = nextStep.id || `step-${i + 1}`
      edges.push({
        id: `e-${stepId}-${nextId}`,
        source: stepId,
        target: nextId,
        type: 'smoothstep',
        style: { stroke: '#2a3544', strokeWidth: 2 },
        markerEnd: { type: MarkerType.ArrowClosed, color: '#2a3544' },
      })
    }

    if (s.if_zero) {
      edges.push({
        id: `e-${stepId}-${s.if_zero}-zero`,
        source: stepId,
        target: s.if_zero,
        type: 'smoothstep',
        label: 'if zero',
        animated: true,
        style: { stroke: '#f59e0b', strokeWidth: 2, strokeDasharray: '5 3' },
        labelStyle: { fill: '#f59e0b', fontSize: 9 },
        labelBgStyle: { fill: '#111820', padding: 4 },
        markerEnd: { type: MarkerType.ArrowClosed, color: '#f59e0b' },
      })
    }

    if (s.if_nonzero) {
      edges.push({
        id: `e-${stepId}-${s.if_nonzero}-nonzero`,
        source: stepId,
        target: s.if_nonzero,
        type: 'smoothstep',
        label: 'if nonzero',
        animated: true,
        style: { stroke: '#f59e0b', strokeWidth: 2 },
        labelStyle: { fill: '#f59e0b', fontSize: 9 },
        labelBgStyle: { fill: '#111820', padding: 4 },
        markerEnd: { type: MarkerType.ArrowClosed, color: '#f59e0b' },
      })
    }

    if (s.skip) {
      edges.push({
        id: `e-${stepId}-${s.skip}-skip`,
        source: stepId,
        target: s.skip,
        type: 'smoothstep',
        style: { stroke: '#475569', strokeWidth: 1.5, strokeDasharray: '3 3' },
        markerEnd: { type: MarkerType.ArrowClosed, color: '#475569' },
      })
    }
  })

  // Add expanded workflow nodes below the parent step
  if (expandedWorkflows && expandedWorkflows.size > 0) {
    let baseY = graphNodes.length * 160 + 80

    for (const [stepId, subWf] of expandedWorkflows) {
      const parentNode = nodes.find(n => n.id === stepId)
      if (!parentNode) continue

      const expandedLabelId = `expanded-${stepId}`

      // Add edge from parent to expanded label (animated dashed cyan line)
      edges.push({
        id: `e-${stepId}-${expandedLabelId}`,
        source: stepId,
        target: expandedLabelId,
        type: 'smoothstep',
        animated: true,
        style: { stroke: '#38bdf8', strokeWidth: 2, strokeDasharray: '8 4' },
        markerEnd: { type: MarkerType.ArrowClosed, color: '#38bdf8' },
      })

      // Add sub-workflow label node
      nodes.push({
        id: expandedLabelId,
        type: 'workflowNode',
        position: { x: parentNode.position.x, y: baseY },
        data: {
          step: { id: expandedLabelId, type: 'workflow', description: `▼ ${subWf.name}` },
          type: 'workflow',
        },
      })

      // Find the step AFTER the current workflow step in the main flow
      const workflowStepIndex = workflow.steps.findIndex((s: unknown, idx: number) => {
        const sid = (s as { id?: string }).id || `step-${idx}`
        return sid === stepId
      })
      const nextMainStep = workflow.steps[workflowStepIndex + 1] as { id?: string } | undefined
      const nextMainStepId = nextMainStep ? (nextMainStep.id || `step-${workflowStepIndex + 1}`) : null

      // Add sub-workflow steps - layout horizontally
      const subStepCount = subWf.steps.length
      const totalSubWidth = Math.max(0, (subStepCount - 1)) * 200
      const startX = parentNode.position.x - totalSubWidth / 2
      let prevSubId = expandedLabelId
      let lastSubStepId = expandedLabelId

      subWf.steps.forEach((subStep: unknown, i: number) => {
        const s = subStep as { id?: string; type?: string; description?: string }
        const subStepId = `expanded-${stepId}-${s.id || i}`
        nodes.push({
          id: subStepId,
          type: 'workflowNode',
          position: { x: startX + i * 200, y: baseY },
          data: { step: s, type: s.type || 'command' },
        })

        edges.push({
          id: `e-${prevSubId}-${subStepId}`,
          source: prevSubId,
          target: subStepId,
          type: 'smoothstep',
          style: { stroke: '#38bdf8', strokeWidth: 1, opacity: 0.6 },
          markerEnd: { type: MarkerType.ArrowClosed, color: '#38bdf8' },
        })
        prevSubId = subStepId
        lastSubStepId = subStepId
      })

      // Connect back to the main flow from the last sub-step
      if (nextMainStepId) {
        edges.push({
          id: `e-${lastSubStepId}-${nextMainStepId}-return`,
          source: lastSubStepId,
          target: nextMainStepId,
          type: 'smoothstep',
          animated: true,
          label: '→ return',
          style: { stroke: '#38bdf8', strokeWidth: 1.5, strokeDasharray: '4 2' },
          labelStyle: { fill: '#38bdf8', fontSize: 10 },
          labelBgStyle: { fill: '#111820', padding: 3 },
          markerEnd: { type: MarkerType.ArrowClosed, color: '#38bdf8' },
        })
      }

      baseY += 250
    }
  }

  return { nodes, edges }
}

export default function FlowDiagram({ workflow, selectedStepId, onSelectStep, expandedWorkflows }: FlowDiagramProps) {
  const { nodes: initNodes, edges: initEdges } = useMemo(
    () => buildNodesAndEdges(workflow, expandedWorkflows),
    [workflow, expandedWorkflows],
  )

  const [nodes, setNodes, onNodesChange] = useNodesState(initNodes)
  const [edges, setEdges, onEdgesChange] = useEdgesState(initEdges)
  const prevWorkflowRef = useRef<string>('')
  const prevExpandedSizeRef = useRef<number>(0)
  const { fitView } = useReactFlow()

  useEffect(() => {
    if (prevWorkflowRef.current !== workflow.name) {
      prevWorkflowRef.current = workflow.name
      setNodes(initNodes)
      setEdges(initEdges)
    } else {
      const expandedSize = expandedWorkflows?.size || 0
      if (expandedSize !== prevExpandedSizeRef.current) {
        prevExpandedSizeRef.current = expandedSize
        setNodes(initNodes)
        setEdges(initEdges)
        // Re-layout after expansion changes
        setTimeout(() => fitView({ padding: 0.3, duration: 300 }), 50)
      }
    }
  }, [workflow, initNodes, initEdges, setNodes, setEdges, expandedWorkflows, fitView])

  const highlightedNodes = useMemo(() => {
    if (!selectedStepId) return new Set<string>()
    const deps = new Set<string>()
    deps.add(selectedStepId)
    const stepIdx = workflow.steps.findIndex((s: unknown) => (s as { id?: string }).id === selectedStepId)
    if (stepIdx >= 0) {
      const step = workflow.steps[stepIdx] as { context_from?: string[]; id?: string }
      if (step.context_from) {
        step.context_from.forEach(c => deps.add(c))
      }
      if (stepIdx > 0) {
        const prev = workflow.steps[stepIdx - 1] as { id?: string }
        deps.add(prev.id || `step-${stepIdx - 1}`)
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

  const onNodeDoubleClick = useCallback(
    (_: React.MouseEvent, node: { id: string }) => {
      // Double-click on a workflow node that has a sub-workflow triggers expand
      // The parent component handles this via onSelectStep auto-expand logic
      onSelectStep(node.id)
    },
    [onSelectStep],
  )

  return (
    <div className="flow-container">
      <ReactFlow
        nodes={nodes.map(n => ({
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
          nodeColor={node => getNodeColor((node.data as { type?: string })?.type || 'command')}
          maskColor="rgba(10, 14, 20, 0.8)"
        />
      </ReactFlow>
    </div>
  )
}