'use client'

// FR-2.4 — RightPanel renders step-list, step detail (via StepDetail), AND a Lint tab.
// FR-4.2 — Lint tab lists LintIssue rows with severity icon, step ID, message, jump-to-step.
//
// StepDetail extracted to its own file (StepDetail.tsx) so this stays under the
// 500-LOC quality gate.

import type { Workflow, Step } from '@/lib/types'
import type { LintIssue } from '@/lib/lint'
import { apiGetWorkflow } from '@/lib/api'
import StepDetail from './StepDetail'

export type RightPanelTab = 'detail' | 'lint'

interface RightPanelProps {
  workflow: Workflow
  projectId: string | null
  selectedStepId: string | null
  onSelectStep: (stepId: string) => void
  onCloseStep: () => void
  expandedWorkflows: Map<string, Workflow>
  onToggleExpand: (stepId: string, subWorkflow: Workflow) => void
  // FR-4.2 — controlled tab state lifted to parent so the lint banner above
  // FlowDiagram can flip into the Lint tab without imperative refs.
  tab: RightPanelTab
  onTabChange: (tab: RightPanelTab) => void
  lintIssues: LintIssue[]
}

function getTypeBadge(type: string): string {
  // FR-2.2 — team-step icons match WorkflowNode for visual continuity.
  const map: Record<string, string> = {
    agent: 'A',
    command: 'C',
    workflow: 'W',
    branch: 'B',
    loop: 'L',
    parallel: 'P',
    approval: 'AP',
    'team-create': '⊕',
    'team-wait': '⊞',
    'team-delete': '⊖',
    teammate: '◐',
  }
  return map[type] || '?'
}

function getTypeClass(type: string): string {
  // Whitelist keeps unknown types defaulting to neutral styling.
  const known = [
    'agent', 'command', 'workflow', 'branch', 'loop', 'parallel', 'approval',
    'team-create', 'team-wait', 'team-delete', 'teammate',
  ]
  return known.includes(type) ? type : 'default'
}

// FR-4.2 — Lint tab severity glyph (rendered as a symbol since this app avoids
// emoji per the broader CLAUDE.md guidance — short text glyphs only).
function severityGlyph(sev: 'error' | 'warning'): string {
  return sev === 'error' ? '✕' : '!'
}

export default function RightPanel({
  workflow,
  projectId,
  selectedStepId,
  onSelectStep,
  onCloseStep,
  expandedWorkflows,
  onToggleExpand,
  tab,
  onTabChange,
  lintIssues,
}: RightPanelProps) {
  const selectedStep = selectedStepId
    ? workflow.steps.find((s: unknown) => (s as { id?: string }).id === selectedStepId) as Step | undefined
    : null

  // For nested expanded steps (e.g. "expanded-propose-manifest-improvement-reflect"), derive the actual step
  const isNestedStep = selectedStepId?.startsWith('expanded-')
  const nestedStepData = isNestedStep && selectedStepId
    ? (() => {
        for (const [parentId, subWf] of expandedWorkflows) {
          const prefix = `expanded-${parentId}-`
          if (selectedStepId.startsWith(prefix)) {
            const subStepId = selectedStepId.slice(prefix.length)
            const subStep = subWf.steps.find((s: unknown) => (s as { id?: string }).id === subStepId) as Step | undefined
            return subStep || null
          }
        }
        return null
      })()
    : null

  const effectiveSelectedStep = isNestedStep && nestedStepData ? nestedStepData : selectedStep

  const handleToggleExpand = async (stepId: string) => {
    if (expandedWorkflows.has(stepId)) {
      onToggleExpand(stepId, {} as Workflow)
      return
    }

    const step = workflow.steps.find((s: unknown) => (s as { id?: string }).id === stepId) as Step | undefined
    if (!step) return
    const wfName = step.workflow_name || (step as { workflow?: string }).workflow
    if (!wfName) return

    try {
      const subWf = await apiGetWorkflow(wfName, projectId ?? undefined)
      if (subWf) {
        onToggleExpand(stepId, subWf)
      }
    } catch (e) {
      console.error('Failed to load nested workflow', e)
    }
  }

  // FR-4.2 — jump-to-step: switch to Detail tab + select the step + clear nested
  // path qualifier (lint operates on top-level steps per spec edge case note).
  const handleJumpToStep = (stepId: string) => {
    if (!stepId) return
    onTabChange('detail')
    onSelectStep(stepId)
  }

  // Tab strip — rendered above all other RightPanel content.
  const tabStrip = (
    <div className="right-panel-tabs" role="tablist">
      <button
        type="button"
        role="tab"
        aria-selected={tab === 'detail'}
        className={`right-panel-tab ${tab === 'detail' ? 'active' : ''}`}
        onClick={() => onTabChange('detail')}
      >
        Detail
      </button>
      <button
        type="button"
        role="tab"
        aria-selected={tab === 'lint'}
        className={`right-panel-tab ${tab === 'lint' ? 'active' : ''}`}
        onClick={() => onTabChange('lint')}
      >
        Lint
        {lintIssues.length > 0 && (
          <span className={`tab-badge ${lintIssues.some(i => i.severity === 'error') ? 'error' : 'warning'}`}>
            {lintIssues.length}
          </span>
        )}
      </button>
    </div>
  )

  // FR-4.2 — Lint tab body.
  if (tab === 'lint') {
    return (
      <div className="right-panel">
        {tabStrip}
        <div className="lint-tab">
          {lintIssues.length === 0 ? (
            <div className="lint-empty">
              <p>Lint clean — no issues found.</p>
            </div>
          ) : (
            <ul className="lint-issue-list" role="list">
              {lintIssues.map((issue, i) => (
                <li key={`${issue.ruleId}-${issue.stepId}-${i}`} className={`lint-issue ${issue.severity}`}>
                  <span className={`lint-severity ${issue.severity}`} aria-label={issue.severity}>
                    {severityGlyph(issue.severity)}
                  </span>
                  <div className="lint-issue-body">
                    <div className="lint-issue-row">
                      <span className="lint-rule-id">{issue.ruleId}</span>
                      {issue.stepId ? (
                        <button
                          type="button"
                          className="lint-step-jump"
                          onClick={() => handleJumpToStep(issue.stepId)}
                          title="Jump to this step in the Detail tab"
                        >
                          {issue.stepId}
                        </button>
                      ) : (
                        <span className="lint-step-id workflow-level">workflow</span>
                      )}
                    </div>
                    <div className="lint-message">{issue.message}</div>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    )
  }

  // Detail tab — selected-step view OR step list.
  if (effectiveSelectedStep) {
    return (
      <div className="right-panel">
        {tabStrip}
        <button className="back-btn" onClick={onCloseStep}>
          Back to steps
        </button>
        <StepDetail
          step={effectiveSelectedStep}
          workflow={isNestedStep && nestedStepData ? expandedWorkflows.get(selectedStepId!.split('-')[1]) || workflow : workflow}
          onToggleExpand={handleToggleExpand}
          expandedWorkflows={expandedWorkflows}
        />
      </div>
    )
  }

  return (
    <div className="right-panel">
      {tabStrip}
      <div className="right-panel-header">
        <h3>Steps</h3>
        <span className="count">{workflow.stepCount}</span>
      </div>

      <div className="step-list">
        {workflow.steps.map((step: unknown, i: number) => {
          const s = step as { id?: string; type?: string; description?: string; instruction?: string; command?: string; prompt?: string; workflow_name?: string; workflow?: string }
          const stepId = s.id || `step-${i}`
          const stepType = s.type || 'command'
          const isExpandable = stepType === 'workflow' && (s.workflow_name || s.workflow)
          const isExpanded = expandedWorkflows.has(stepId)
          const subWf = expandedWorkflows.get(stepId)

          let preview = ''
          if (s.type === 'agent' && s.instruction) {
            preview = s.instruction.slice(0, 50).replace(/\n/g, ' ') + '...'
          } else if (s.type === 'agent' && s.prompt) {
            preview = String(s.prompt).slice(0, 50).replace(/\n/g, ' ') + '...'
          } else if (s.type === 'command' && s.command) {
            preview = s.command.slice(0, 50).split('\n')[0].trim() + '...'
          } else if (s.description) {
            preview = s.description.slice(0, 50)
          }

          return (
            <div key={stepId}>
              <div
                className={`step-item ${selectedStepId === stepId ? 'selected' : ''}`}
                onClick={() => onSelectStep(stepId)}
              >
                <span className={`step-type-badge ${getTypeClass(stepType)}`}>
                  {getTypeBadge(stepType)}
                </span>
                <div className="step-item-content">
                  <span className="step-item-id">{stepId}</span>
                  {preview && <span className="step-item-preview">{preview}</span>}
                </div>
                {isExpandable && (
                  <button
                    className={`expand-btn ${isExpanded ? 'expanded' : ''}`}
                    onClick={(e) => {
                      e.stopPropagation()
                      handleToggleExpand(stepId)
                    }}
                    title={isExpanded ? 'Collapse' : 'Expand nested workflow'}
                  >
                    {isExpanded ? '−' : '+'}
                  </button>
                )}
              </div>
              {/* Nested sub-steps for expanded workflows */}
              {isExpanded && subWf && subWf.steps && (
                <div className="nested-steps">
                  <div className="nested-steps-header">
                    <span className="nested-label">▼ {subWf.name}</span>
                  </div>
                  {subWf.steps.map((subStep: unknown, j: number) => {
                    const subS = subStep as { id?: string; type?: string; description?: string; instruction?: string; command?: string }
                    const subStepId = subS.id ?? String(j)
                    const subType = subS.type || 'command'

                    let subPreview = ''
                    if (subS.type === 'agent' && subS.instruction) {
                      subPreview = subS.instruction.slice(0, 40).replace(/\n/g, ' ') + '...'
                    } else if (subS.type === 'command' && subS.command) {
                      subPreview = subS.command.slice(0, 40).split('\n')[0].trim() + '...'
                    } else if (subS.description) {
                      subPreview = subS.description.slice(0, 40)
                    }

                    return (
                      <div
                        key={subStepId}
                        className={`step-item nested ${selectedStepId === subStepId ? 'selected' : ''}`}
                        onClick={(e) => {
                          e.stopPropagation()
                          // Pass prefixed ID so Page knows this is a nested step
                          const prefixedId = `expanded-${stepId}-${subStepId}`
                          onSelectStep(prefixedId)
                        }}
                      >
                        <span className={`step-type-badge ${getTypeClass(subType)}`} style={{ opacity: 0.7 }}>
                          {getTypeBadge(subType)}
                        </span>
                        <div className="step-item-content">
                          <span className="step-item-id">{subStepId}</span>
                          {subPreview && <span className="step-item-preview">{subPreview}</span>}
                        </div>
                      </div>
                    )
                  })}
                </div>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}
