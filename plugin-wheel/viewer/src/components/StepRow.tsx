'use client'

import { useState } from 'react'
import type { Step } from '@/lib/types'

interface StepRowProps {
  step: Step
  index: number
}

export default function StepRow({ step, index }: StepRowProps) {
  const [open, setOpen] = useState(false)

  const typeClass = step.type ?? 'command'

  return (
    <div className="step-row">
      <div className="step-header" onClick={() => setOpen(o => !o)}>
        <span className={`step-expand ${open ? 'open' : ''}`}>▶</span>
        <span className="step-id">{step.id ?? `step-${index}`}</span>
        <span className={`step-type ${typeClass}`}>{typeClass}</span>
        <span className="step-description">{step.description ?? step.prompt ?? step.command ?? ''}</span>
      </div>
      {open && (
        <div className="step-body">
          {step.command && (
            <div className="step-field">
              <div className="step-field-label">command</div>
              <pre>{step.command}</pre>
            </div>
          )}
          {step.prompt && (
            <div className="step-field">
              <div className="step-field-label">prompt</div>
              <pre>{step.prompt}</pre>
            </div>
          )}
          {step.agent && (
            <div className="step-field">
              <div className="step-field-label">agent</div>
              <pre>{JSON.stringify(step.agent, null, 2)}</pre>
            </div>
          )}
          {step.model && (
            <div className="step-field">
              <div className="step-field-label">model</div>
              <div className="step-field-value">{step.model}</div>
            </div>
          )}
          {step.inputs && (
            <div className="step-field">
              <div className="step-field-label">inputs</div>
              <pre>{JSON.stringify(step.inputs, null, 2)}</pre>
            </div>
          )}
          {step.output && (
            <div className="step-field">
              <div className="step-field-label">output</div>
              <div className="step-field-value">{step.output}</div>
            </div>
          )}
          {step.context_from && step.context_from.length > 0 && (
            <div className="step-field">
              <div className="step-field-label">context_from</div>
              <div className="step-field-value">{step.context_from.join(', ')}</div>
            </div>
          )}
          {step.requires_plugins && step.requires_plugins.length > 0 && (
            <div className="step-field">
              <div className="step-field-label">requires_plugins</div>
              <div className="step-field-value">{step.requires_plugins.join(', ')}</div>
            </div>
          )}
          {step.skip && (
            <div className="step-field">
              <div className="step-field-label">skip</div>
              <div className="step-field-value">{step.skip}</div>
            </div>
          )}
          {step.on_error && (
            <div className="step-field">
              <div className="step-field-label">on_error</div>
              <div className="step-field-value">{step.on_error}</div>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
