'use client'

// FR-2.4 — StepDetail extracted from RightPanel into its own file so the panel
// stays under the 500-LOC quality gate after we add team-step sections + Lint tab.
//
// Renders a single Step's full detail view: type-specific field sections,
// expand-nested-workflow affordance, common fields. Pure presentation.

import type { Step, Workflow } from '@/lib/types'

interface StepDetailProps {
  step: Step
  workflow: Workflow
  onToggleExpand: (stepId: string, subWorkflow: Workflow) => void
  expandedWorkflows: Map<string, Workflow>
}

export default function StepDetail({
  step,
  workflow: _workflow, // reserved for future workflow-level cross-references
  onToggleExpand,
  expandedWorkflows,
}: StepDetailProps) {
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

      {/* FR-2.3 — team-create: team_name field. */}
      {stepType === 'team-create' && (
        <>
          {step.team_name && (
            <div className="step-field">
              <div className="step-field-label">team_name</div>
              <div className="step-field-value">
                <span className="mono">{step.team_name}</span>
              </div>
            </div>
          )}
        </>
      )}

      {/* FR-2.3 — team-wait: team ref + output capture path. */}
      {stepType === 'team-wait' && (
        <>
          {step.team && (
            <div className="step-field">
              <div className="step-field-label">team</div>
              <div className="step-field-value">
                <span className="mono">{step.team}</span>
              </div>
            </div>
          )}
          {step.output && (
            <div className="step-field">
              <div className="step-field-label">output</div>
              <div className="step-field-value">{step.output}</div>
            </div>
          )}
        </>
      )}

      {/* FR-2.3 — team-delete: team ref + terminal badge. */}
      {stepType === 'team-delete' && (
        <>
          {step.team && (
            <div className="step-field">
              <div className="step-field-label">team</div>
              <div className="step-field-value">
                <span className="mono">{step.team}</span>
              </div>
            </div>
          )}
          {step.terminal !== undefined && (
            <div className="step-field">
              <div className="step-field-label">terminal</div>
              <div className="step-field-value">
                {step.terminal ? (
                  <span className="terminal-badge">terminal: true</span>
                ) : (
                  'false'
                )}
              </div>
            </div>
          )}
        </>
      )}

      {/* FR-2.3 / FR-2.4 — teammate: team ref, sub-workflow link, model, full assign JSON. */}
      {stepType === 'teammate' && (
        <>
          {step.team && (
            <div className="step-field">
              <div className="step-field-label">team</div>
              <div className="step-field-value">
                <span className="mono">{step.team}</span>
              </div>
            </div>
          )}
          {step.workflow && (
            <div className="step-field">
              <div className="step-field-label">workflow</div>
              <div className="step-field-value">
                <span className="mono">{step.workflow}</span>
              </div>
            </div>
          )}
          {step.model && (
            <div className="step-field">
              <div className="step-field-label">model</div>
              <div className="step-field-value">{step.model}</div>
            </div>
          )}
          {step.assign && Object.keys(step.assign).length > 0 && (
            <div className="step-field">
              <div className="step-field-label">assign (full JSON)</div>
              <div className="step-field-value">
                <pre className="json-value">{JSON.stringify(step.assign, null, 2)}</pre>
              </div>
            </div>
          )}
          {/* FR-2.4 — full workflow_definition for inline sub-workflow expansion. */}
          {step.workflow_definition && Object.keys(step.workflow_definition).length > 0 && (
            <div className="step-field">
              <div className="step-field-label">workflow_definition (inline)</div>
              <div className="step-field-value">
                <pre className="json-value">{JSON.stringify(step.workflow_definition, null, 2)}</pre>
              </div>
            </div>
          )}
        </>
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
              <div className="step-field-value">{step.agents.join(', ')}</div>
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
              <div className="step-field-value">{step.agents.join(', ')}</div>
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
      {step.output && stepType !== 'team-wait' && (
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
      {step.terminal !== undefined && stepType !== 'team-delete' && (
        <div className="step-field">
          <div className="step-field-label">terminal</div>
          <div className="step-field-value">{step.terminal ? 'true' : 'false'}</div>
        </div>
      )}
    </div>
  )
}
