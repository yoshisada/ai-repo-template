'use client'

import { useState } from 'react'
import type { Workflow, Step } from '@/lib/types'
import { apiGetWorkflow } from '@/lib/api'

interface RightPanelProps {
  workflow: Workflow
  projectId: string | null
  selectedStepId: string | null
  onSelectStep: (stepId: string) => void
  onCloseStep: () => void
  expandedWorkflows: Map<string, Workflow>
  onToggleExpand: (stepId: string, subWorkflow: Workflow) => void
}

function getTypeBadge(type: string): string {
  const map: Record<string, string> = {
    agent: 'A', command: 'C', workflow: 'W', branch: 'B', loop: 'L', parallel: 'P', approval: 'AP'
  }
  return map[type] || '?'
}

function getTypeClass(type: string): string {
  if (type === 'agent') return 'agent'
  if (type === 'command') return 'command'
  if (type === 'workflow') return 'workflow'
  if (type === 'branch') return 'branch'
  if (type === 'loop') return 'loop'
  if (type === 'parallel') return 'parallel'
  if (type === 'approval') return 'approval'
  return 'default'
}

function StepDetail({
  step,
  workflow,
  onToggleExpand,
  expandedWorkflows,
}: {
  step: Step
  workflow: Workflow
  onToggleExpand: (stepId: string, subWorkflow: Workflow) => void
  expandedWorkflows: Map<string, Workflow>
}) {
  const stepType = step.type || 'command'
  const stepId = step.id || 'unknown'

  return (
    <div className="step-detail-view">
      <div className="step-detail-header">
        <div className="step-detail-title">
          <span className="step-detail-id">{stepId}</span>
          <span className={`step-detail-type ${stepType}`}>{stepType}</span>
        </div>
      </div>

      {step.description && (
        <div className="step-detail-description">{step.description}</div>
      )}

      {/* Branch fields */}
      {stepType === 'branch' && (
        <>
          {step.condition && (
            <div className="step-field">
              <div className="step-field-label">condition</div>
              <div className="step-field-value">
                <span className="mono">{step.condition}</span>
              </div>
            </div>
          )}
          {step.if_zero && (
            <div className="step-field">
              <div className="step-field-label">if_zero</div>
              <div className="step-field-value">{step.if_zero}</div>
            </div>
          )}
          {step.if_nonzero && (
            <div className="step-field">
              <div className="step-field-label">if_nonzero</div>
              <div className="step-field-value">{step.if_nonzero}</div>
            </div>
          )}
        </>
      )}

      {/* Loop fields */}
      {stepType === 'loop' && (
        <>
          {step.condition && (
            <div className="step-field">
              <div className="step-field-label">condition</div>
              <div className="step-field-value">
                <span className="mono">{step.condition}</span>
              </div>
            </div>
          )}
          {step.max_iterations !== undefined && (
            <div className="step-field">
              <div className="step-field-label">max_iterations</div>
              <div className="step-field-value">{step.max_iterations}</div>
            </div>
          )}
          {step.on_exhaustion && (
            <div className="step-field">
              <div className="step-field-label">on_exhaustion</div>
              <div className="step-field-value">{step.on_exhaustion}</div>
            </div>
          )}
          {step.substep && (
            <div className="step-field">
              <div className="step-field-label">substep</div>
              <div className="step-field-value">
                <span className="mono">{step.substep.id || 'inline'}</span>
              </div>
            </div>
          )}
        </>
      )}

      {/* Agent fields */}
      {(stepType === 'agent' || step.agents) && (
        <>
          {step.instruction && (
            <div className="step-field">
              <div className="step-field-label">instruction</div>
              <div className="step-field-value">
                <span className="mono">{step.instruction}</span>
              </div>
            </div>
          )}
          {step.prompt && (
            <div className="step-field">
              <div className="step-field-label">prompt</div>
              <div className="step-field-value">
                <span className="mono">{step.prompt}</span>
              </div>
            </div>
          )}
          {step.agent && Object.keys(step.agent).length > 0 && (
            <div className="step-field">
              <div className="step-field-label">agent</div>
              <div className="step-field-value">
                <pre className="json-value">{JSON.stringify(step.agent, null, 2)}</pre>
              </div>
            </div>
          )}
          {step.agent_type && (
            <div className="step-field">
              <div className="step-field-label">agent_type</div>
              <div className="step-field-value">{step.agent_type}</div>
            </div>
          )}
          {step.agents && step.agents.length > 0 && (
            <div className="step-field">
              <div className="step-field-label">agents</div>
              <div className="step-field-value">
                {step.agents.join(', ')}
              </div>
            </div>
          )}
          {step.agent_instructions && Object.keys(step.agent_instructions).length > 0 && (
            <div className="step-field">
              <div className="step-field-label">agent_instructions</div>
              <div className="step-field-value">
                <pre className="json-value">{JSON.stringify(step.agent_instructions, null, 2)}</pre>
              </div>
            </div>
          )}
          {step.model && (
            <div className="step-field">
              <div className="step-field-label">model</div>
              <div className="step-field-value">{step.model}</div>
            </div>
          )}
          {step.allow_user_input !== undefined && (
            <div className="step-field">
              <div className="step-field-label">allow_user_input</div>
              <div className="step-field-value">{step.allow_user_input ? 'true' : 'false'}</div>
            </div>
          )}
          {step.output_schema && Object.keys(step.output_schema).length > 0 && (
            <div className="step-field">
              <div className="step-field-label">output_schema</div>
              <div className="step-field-value">
                <pre className="json-value">{JSON.stringify(step.output_schema, null, 2)}</pre>
              </div>
            </div>
          )}
        </>
      )}

      {/* Command fields */}
      {stepType === 'command' && step.command && (
        <div className="step-field">
          <div className="step-field-label">command</div>
          <div className="step-field-value">
            <span className="mono">{step.command}</span>
          </div>
        </div>
      )}

      {/* Workflow step fields */}
      {stepType === 'workflow' && (
        <>
          {(step as { workflow_name?: string }).workflow_name && (
            <div className="step-field">
              <div className="step-field-label">workflow_name</div>
              <div className="step-field-value">{(step as { workflow_name: string }).workflow_name}</div>
            </div>
          )}
          {(step as { workflow?: string }).workflow && (
            <div className="step-field">
              <div className="step-field-label">workflow</div>
              <div className="step-field-value">{(step as { workflow: string }).workflow}</div>
            </div>
          )}
          {step.workflow_plugin && (
            <div className="step-field">
              <div className="step-field-label">workflow_plugin</div>
              <div className="step-field-value">{step.workflow_plugin}</div>
            </div>
          )}
          {expandedWorkflows.has(stepId) && (
            <div className="step-field">
              <div className="step-field-label">expanded workflow</div>
              <div className="step-field-value nested-steps">
                <em>Expanded inline - see flow diagram</em>
              </div>
            </div>
          )}
          {!expandedWorkflows.has(stepId) && ((step as { workflow_name?: string }).workflow_name || (step as { workflow?: string }).workflow) && (
            <div className="step-field">
              <button
                className="expand-btn"
                onClick={() => onToggleExpand(stepId, {} as Workflow)}
              >
                + Expand nested workflow
              </button>
            </div>
          )}
        </>
      )}

      {/* Approval fields */}
      {stepType === 'approval' && step.message && (
        <div className="step-field">
          <div className="step-field-label">message</div>
          <div className="step-field-value">
            <span className="mono">{step.message}</span>
          </div>
        </div>
      )}

      {/* Parallel fields */}
      {stepType === 'parallel' && (
        <>
          {step.agents && step.agents.length > 0 && (
            <div className="step-field">
              <div className="step-field-label">agents</div>
              <div className="step-field-value">
                {step.agents.join(', ')}
              </div>
            </div>
          )}
          {step.agent_instructions && Object.keys(step.agent_instructions).length > 0 && (
            <div className="step-field">
              <div className="step-field-label">agent_instructions</div>
              <div className="step-field-value">
                <pre className="json-value">{JSON.stringify(step.agent_instructions, null, 2)}</pre>
              </div>
            </div>
          )}
        </>
      )}

      {/* Common fields */}
      {step.inputs && Object.keys(step.inputs).length > 0 && (
        <div className="step-field">
          <div className="step-field-label">inputs</div>
          <div className="step-field-value">
            <pre className="json-value">{JSON.stringify(step.inputs, null, 2)}</pre>
          </div>
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
      {step.terminal !== undefined && (
        <div className="step-field">
          <div className="step-field-label">terminal</div>
          <div className="step-field-value">{step.terminal ? 'true' : 'false'}</div>
        </div>
      )}
    </div>
  )
}

export default function RightPanel({
  workflow,
  projectId,
  selectedStepId,
  onSelectStep,
  onCloseStep,
  expandedWorkflows,
  onToggleExpand,
}: RightPanelProps) {
  const selectedStep = selectedStepId
    ? workflow.steps.find((s: unknown) => (s as { id?: string }).id === selectedStepId) as Step | undefined
    : null

  // For nested expanded steps (e.g. "expanded-propose-manifest-improvement-reflect"), derive the actual step
  // The prefix is "expanded-{parentId}" but parentId itself may contain dashes, so we iterate through expandedWorkflows
  const isNestedStep = selectedStepId?.startsWith('expanded-')
  const nestedStepData = isNestedStep && selectedStepId
    ? (() => {
        // Try to find which parent workflow this belongs to
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

  if (effectiveSelectedStep) {
    return (
      <div className="right-panel">
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