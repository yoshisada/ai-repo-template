'use client'

import type { Workflow } from '@/lib/types'
import StepRow from './StepRow'

interface WorkflowDetailProps {
  workflow: Workflow
}

export default function WorkflowDetail({ workflow }: WorkflowDetailProps) {
  return (
    <div>
      <div className="detail-header">
        <h1>{workflow.name}</h1>
        {workflow.description && <p style={{ color: 'var(--muted)', marginTop: 4 }}>{workflow.description}</p>}
        <div className="meta">
          <span>
            <span className={`step-type ${workflow.source}`}>{workflow.source}</span>
          </span>
          <span>{workflow.stepCount} steps</span>
          {workflow.plugin && <span>plugin: {workflow.plugin}</span>}
          <span style={{ fontSize: 11, color: 'var(--muted)' }}>{workflow.path}</span>
        </div>
      </div>

      <div className="steps-list">
        {workflow.steps.map((step, i) => (
          <StepRow key={(step as { id?: string }).id ?? i} step={step as any} index={i} />
        ))}
      </div>
    </div>
  )
}
