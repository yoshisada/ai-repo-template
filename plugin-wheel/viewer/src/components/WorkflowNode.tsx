'use client'

// WorkflowNode — per-step rendering inside the React Flow graph.
//
// FR-2.1 — handles all 11 step types in the extended StepType union.
// FR-2.2 — adds icons + colors for the four team primitives, picking from
//          the existing palette so the visual language stays coherent.
// FR-2.3 — body renders type-specific fields (team_name on team-create,
//          team ref on team-wait, etc.).

import { memo } from 'react'
import { Handle, Position } from '@xyflow/react'
import type { Step } from '@/lib/types'

interface WorkflowNodeData {
  step: Step
  type: string
}

// FR-2.2 — icon vocabulary. The four team types share a coherent visual
// family — circles / squares / overlays — distinct from agent (◈) and
// command (⌨) glyphs.
const TYPE_ICONS: Record<string, string> = {
  command: '⌨',
  agent: '◈',
  workflow: '⟳',
  branch: '⤿',
  loop: '↻',
  parallel: '⇉',
  approval: '✓',
  // FR-2.2 — team primitives.
  'team-create': '⊕',
  'team-wait': '⊞',
  'team-delete': '⊖',
  teammate: '◐',
}

// FR-2.3 — render the body fields per step type. Pure presentational.
function renderTypeBody(type: string, step: Step) {
  switch (type) {
    case 'command':
      return step.command ? (
        <div
          className="node-description"
          style={{ fontSize: 10, color: 'var(--accent-green)', opacity: 0.7 }}
        >
          {step.command.slice(0, 50)}
          {step.command.length > 50 ? '...' : ''}
        </div>
      ) : null
    case 'agent':
      return step.prompt ? (
        <div
          className="node-description"
          style={{ fontSize: 10, color: 'var(--accent-purple)', opacity: 0.7 }}
        >
          {String(step.prompt).slice(0, 50)}
          {String(step.prompt).length > 50 ? '...' : ''}
        </div>
      ) : null
    case 'team-create':
      // FR-2.3 — team-create body shows the declared team_name.
      return step.team_name ? (
        <div className="node-team-field">
          <span className="node-team-label">team:</span>
          <span className="node-team-value">{step.team_name}</span>
        </div>
      ) : null
    case 'team-wait':
      // FR-2.3 — team-wait body shows the awaited team ref + optional capture path.
      return (
        <>
          {step.team && (
            <div className="node-team-field">
              <span className="node-team-label">team:</span>
              <span className="node-team-value">{step.team}</span>
            </div>
          )}
          {step.output && (
            <div className="node-team-field">
              <span className="node-team-label">output:</span>
              <span
                className="node-team-value"
                style={{ fontSize: 9, opacity: 0.7 }}
                title={step.output}
              >
                {step.output.slice(0, 28)}
                {step.output.length > 28 ? '...' : ''}
              </span>
            </div>
          )}
        </>
      )
    case 'team-delete':
      // FR-2.3 — team-delete body shows team ref + terminal badge if present.
      return (
        <>
          {step.team && (
            <div className="node-team-field">
              <span className="node-team-label">team:</span>
              <span className="node-team-value">{step.team}</span>
            </div>
          )}
          {step.terminal && <span className="node-tag terminal">terminal</span>}
        </>
      )
    case 'teammate':
      // FR-2.3 — teammate body: team ref, sub-workflow path, optional model,
      // and a one-line summary of the assign payload.
      return (
        <>
          {step.team && (
            <div className="node-team-field">
              <span className="node-team-label">team:</span>
              <span className="node-team-value">{step.team}</span>
            </div>
          )}
          {step.workflow && (
            <div className="node-team-field">
              <span className="node-team-label">workflow:</span>
              <span
                className="node-team-value"
                style={{ fontSize: 9, opacity: 0.85 }}
                title={step.workflow}
              >
                {step.workflow.length > 28 ? `…${step.workflow.slice(-26)}` : step.workflow}
              </span>
            </div>
          )}
          {step.model && (
            <div className="node-team-field">
              <span className="node-team-label">model:</span>
              <span className="node-team-value">{step.model}</span>
            </div>
          )}
          {step.assign && Object.keys(step.assign).length > 0 && (
            <div
              className="node-description"
              style={{ fontSize: 9, opacity: 0.6, marginTop: 4 }}
              title={JSON.stringify(step.assign, null, 2)}
            >
              assign: {Object.keys(step.assign).slice(0, 3).join(', ')}
              {Object.keys(step.assign).length > 3 ? `, +${Object.keys(step.assign).length - 3}` : ''}
            </div>
          )}
        </>
      )
    default:
      return null
  }
}

function WorkflowNodeComponent({ data }: { data: WorkflowNodeData }) {
  const { step, type } = data
  const typeClass = type || 'command'

  return (
    <div className={`workflow-node ${typeClass}`}>
      <Handle type="target" position={Position.Top} />

      <div className="node-header">
        <div className={`node-type-icon ${typeClass}`}>{TYPE_ICONS[type] || '○'}</div>
        <span className="node-id">{step.id || 'unknown'}</span>
      </div>

      <div className="node-body">
        {step.description && <div className="node-description">{step.description}</div>}
        {renderTypeBody(type, step)}

        <div className="node-tags">
          <span className={`node-tag ${typeClass}`}>{type}</span>
          {step.skip && <span className="node-tag skip">skip: {step.skip}</span>}
          {step.if_zero && <span className="node-tag if-zero">if_zero → {step.if_zero}</span>}
          {step.if_nonzero && (
            <span className="node-tag if-nonzero">if_nonzero → {step.if_nonzero}</span>
          )}
        </div>
      </div>

      <Handle type="source" position={Position.Bottom} />
    </div>
  )
}

export default memo(WorkflowNodeComponent)

export const nodeTypes = {
  workflowNode: WorkflowNodeComponent,
}
