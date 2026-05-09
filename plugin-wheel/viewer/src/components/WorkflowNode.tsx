'use client'

import { memo } from 'react'
import { Handle, Position } from '@xyflow/react'
import type { Step } from '@/lib/types'

interface WorkflowNodeData {
  step: Step
  type: string
}

const TYPE_ICONS: Record<string, string> = {
  command: '⌨',
  agent: '◈',
  workflow: '⟳',
  branch: '⤿',
}

function WorkflowNodeComponent({ data }: { data: WorkflowNodeData }) {
  const { step, type } = data
  const typeClass = type || 'command'

  return (
    <div className={`workflow-node ${typeClass}`}>
      <Handle type="target" position={Position.Top} />

      <div className="node-header">
        <div className={`node-type-icon ${typeClass}`}>
          {TYPE_ICONS[type] || '○'}
        </div>
        <span className="node-id">{step.id || 'unknown'}</span>
      </div>

      <div className="node-body">
        {step.description && (
          <div className="node-description">{step.description}</div>
        )}
        {type === 'command' && step.command && (
          <div className="node-description" style={{ fontSize: 10, color: 'var(--accent-green)', opacity: 0.7 }}>
            {step.command.slice(0, 50)}{step.command.length > 50 ? '...' : ''}
          </div>
        )}
        {type === 'agent' && step.prompt && (
          <div className="node-description" style={{ fontSize: 10, color: 'var(--accent-purple)', opacity: 0.7 }}>
            {String(step.prompt).slice(0, 50)}{String(step.prompt).length > 50 ? '...' : ''}
          </div>
        )}

        <div className="node-tags">
          <span className={`node-tag ${typeClass}`}>{type}</span>
          {step.skip && <span className="node-tag skip">skip: {step.skip}</span>}
          {step.if_zero && <span className="node-tag if-zero">if_zero → {step.if_zero}</span>}
          {step.if_nonzero && <span className="node-tag if-nonzero">if_nonzero → {step.if_nonzero}</span>}
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