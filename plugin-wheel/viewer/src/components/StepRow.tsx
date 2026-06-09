'use client'

// StepRow — collapsible per-step row for the right-panel step list and the
// diff side-by-side view.
//
// FR-2.3 — body fields cover team-step shapes (team_name, team, workflow,
//          assign, terminal badge).
// FR-5.2 — `diffStatus` + `fieldDiff` props enable diff highlighting +
//          per-field diff display when StepRow is consumed by DiffView.
// Default behavior unchanged when both props are omitted.

import { useState } from 'react'
import type { Step } from '@/lib/types'
import type { FieldDiff } from '@/lib/diff'

export interface StepRowProps {
  step: Step
  index: number
  /** FR-5.2 — diff status for the row (added / removed / modified / unchanged). */
  diffStatus?: 'added' | 'removed' | 'modified' | 'unchanged'
  /** FR-5.2 — when diffStatus === 'modified', the per-field diff to optionally expand. */
  fieldDiff?: FieldDiff[]
}

export default function StepRow({ step, index, diffStatus, fieldDiff }: StepRowProps) {
  const [open, setOpen] = useState(false)

  const typeClass = step.type ?? 'command'
  // FR-5.2 — diff status is purely a visual annotation; absence means default styling.
  const diffClass = diffStatus ? `diff-${diffStatus}` : ''

  return (
    <div className={`step-row ${diffClass}`}>
      <div className="step-header" onClick={() => setOpen((o) => !o)}>
        <span className={`step-expand ${open ? 'open' : ''}`}>▶</span>
        <span className="step-id">{step.id ?? `step-${index}`}</span>
        <span className={`step-type ${typeClass}`}>{typeClass}</span>
        <span className="step-description">
          {step.description ?? step.prompt ?? step.command ?? ''}
        </span>
        {/* FR-5.2 — diff badge surfaces status without requiring expansion. */}
        {diffStatus && <span className={`step-diff-badge diff-${diffStatus}`}>{diffStatus}</span>}
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
          {/* FR-2.3 — team-step fields. */}
          {step.team_name && (
            <div className="step-field">
              <div className="step-field-label">team_name</div>
              <div className="step-field-value">{step.team_name}</div>
            </div>
          )}
          {step.team && (
            <div className="step-field">
              <div className="step-field-label">team</div>
              <div className="step-field-value">{step.team}</div>
            </div>
          )}
          {step.workflow && (
            <div className="step-field">
              <div className="step-field-label">workflow</div>
              <div className="step-field-value">{step.workflow}</div>
            </div>
          )}
          {step.assign && (
            <div className="step-field">
              <div className="step-field-label">assign</div>
              <pre>{JSON.stringify(step.assign, null, 2)}</pre>
            </div>
          )}
          {step.terminal && (
            <div className="step-field">
              <div className="step-field-label">terminal</div>
              <div className="step-field-value">true</div>
            </div>
          )}
          {/* FR-5.2 — per-field diff, shown when StepRow is rendered for a modified row. */}
          {diffStatus === 'modified' && fieldDiff && fieldDiff.length > 0 && (
            <div className="step-field">
              <div className="step-field-label">field diff</div>
              <ul className="step-field-diff">
                {fieldDiff.map((f) => (
                  <li key={f.path}>
                    <span className="step-field-diff-path">{f.path}</span>
                    <span className="step-field-diff-arrow">→</span>
                    <span className="step-field-diff-left">{JSON.stringify(f.left)}</span>
                    <span className="step-field-diff-arrow">⇒</span>
                    <span className="step-field-diff-right">{JSON.stringify(f.right)}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
