'use client'

// FR-5.2 / FR-5.3 / FR-5.4 — Side-by-side workflow diff view.
//
// Pure presentation: receives precomputed `diff: WorkflowDiff` from page.tsx.
// Renders two parallel step lists annotated with diffStatus on each row.
//
// Step alignment uses `id` as the join key. The diff data is shaped by
// lib/diff.ts (impl-data-layer); this component is responsible only for the
// visual layout, summary header, and routing per-row diffStatus / fieldDiff
// to StepRow.

import type { Step, Workflow } from '@/lib/types'
import type { WorkflowDiff, FieldDiff, ModifiedStep } from '@/lib/diff'
import StepRow from './StepRow'

export interface DiffViewProps {
  left: Workflow
  right: Workflow
  diff: WorkflowDiff
  onClose: () => void
}

type DiffStatus = 'added' | 'removed' | 'modified' | 'unchanged'

interface AnnotatedRow {
  step: Step
  status: DiffStatus
  fieldDiff?: FieldDiff[]
}

// FR-5.3 — annotate left.steps with status by checking which bucket each id
// falls into. Steps without an `id` fall through as their unsided status.
function annotateLeft(left: Workflow, diff: WorkflowDiff): AnnotatedRow[] {
  const removedIds = new Set(diff.removed.map(s => s.id ?? '').filter(Boolean))
  const modifiedById = new Map<string, ModifiedStep>()
  for (const m of diff.modified) modifiedById.set(m.id, m)
  const unchangedIds = new Set(diff.unchanged.map(s => s.id ?? '').filter(Boolean))

  return left.steps.map(step => {
    const id = step.id ?? ''
    if (id && removedIds.has(id)) {
      return { step, status: 'removed' as DiffStatus }
    }
    if (id && modifiedById.has(id)) {
      return {
        step,
        status: 'modified' as DiffStatus,
        fieldDiff: modifiedById.get(id)!.fieldDiff,
      }
    }
    if (id && unchangedIds.has(id)) {
      return { step, status: 'unchanged' as DiffStatus }
    }
    // Steps without id fall through — render as removed (left-only is removed).
    return { step, status: 'removed' as DiffStatus }
  })
}

function annotateRight(right: Workflow, diff: WorkflowDiff): AnnotatedRow[] {
  const addedIds = new Set(diff.added.map(s => s.id ?? '').filter(Boolean))
  const modifiedById = new Map<string, ModifiedStep>()
  for (const m of diff.modified) modifiedById.set(m.id, m)
  const unchangedIds = new Set(diff.unchanged.map(s => s.id ?? '').filter(Boolean))

  return right.steps.map(step => {
    const id = step.id ?? ''
    if (id && addedIds.has(id)) {
      return { step, status: 'added' as DiffStatus }
    }
    if (id && modifiedById.has(id)) {
      return {
        step,
        status: 'modified' as DiffStatus,
        fieldDiff: modifiedById.get(id)!.fieldDiff,
      }
    }
    if (id && unchangedIds.has(id)) {
      return { step, status: 'unchanged' as DiffStatus }
    }
    return { step, status: 'added' as DiffStatus }
  })
}

export default function DiffView({ left, right, diff, onClose }: DiffViewProps) {
  const leftRows = annotateLeft(left, diff)
  const rightRows = annotateRight(right, diff)

  // FR-5.4 — header summary counts.
  const summary = `${diff.added.length} added · ${diff.removed.length} removed · ${diff.modified.length} modified · ${diff.unchanged.length} unchanged`

  return (
    <div className="diff-view">
      <header className="diff-view-header">
        <div className="diff-view-titles">
          <h2>Diff</h2>
          <div className="diff-view-pair">
            <span className="diff-view-name diff-removed">{left.name}</span>
            <span className="diff-view-arrow">↔</span>
            <span className="diff-view-name diff-added">{right.name}</span>
          </div>
        </div>
        <div className="diff-view-summary">{summary}</div>
        <button
          type="button"
          className="diff-view-close"
          onClick={onClose}
          title="Close diff and return to single workflow view"
        >
          Close
        </button>
      </header>

      <div className="diff-view-columns">
        <section className="diff-view-column" aria-label={`Left: ${left.name}`}>
          <header className="diff-view-column-header diff-side-left">
            <span className="diff-view-column-label">Left</span>
            <span className="diff-view-column-name">{left.name}</span>
            <span className="diff-view-column-meta">{leftRows.length} steps</span>
          </header>
          <div className="diff-view-step-list">
            {leftRows.length === 0 ? (
              <div className="diff-view-empty-side">
                <em>This side has no steps.</em>
              </div>
            ) : (
              leftRows.map((row, i) => (
                <StepRow
                  key={`L-${row.step.id ?? i}`}
                  step={row.step}
                  index={i}
                  diffStatus={row.status}
                  fieldDiff={row.fieldDiff}
                />
              ))
            )}
          </div>
        </section>

        <section className="diff-view-column" aria-label={`Right: ${right.name}`}>
          <header className="diff-view-column-header diff-side-right">
            <span className="diff-view-column-label">Right</span>
            <span className="diff-view-column-name">{right.name}</span>
            <span className="diff-view-column-meta">{rightRows.length} steps</span>
          </header>
          <div className="diff-view-step-list">
            {rightRows.length === 0 ? (
              <div className="diff-view-empty-side">
                <em>This side has no steps.</em>
              </div>
            ) : (
              rightRows.map((row, i) => (
                <StepRow
                  key={`R-${row.step.id ?? i}`}
                  step={row.step}
                  index={i}
                  diffStatus={row.status}
                  fieldDiff={row.fieldDiff}
                />
              ))
            )}
          </div>
        </section>
      </div>
    </div>
  )
}
