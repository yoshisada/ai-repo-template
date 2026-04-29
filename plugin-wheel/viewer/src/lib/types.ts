export interface Project {
  id: string
  path: string
  addedAt: string
}

export type StepType = 'command' | 'agent' | 'workflow' | 'branch' | 'loop' | 'parallel' | 'approval'

export interface Step {
  id?: string
  type?: StepType
  description?: string

  // agent fields
  instruction?: string
  prompt?: string
  agent?: Record<string, unknown>
  agent_type?: string
  agents?: string[]
  agent_instructions?: Record<string, string>
  model?: string
  allow_user_input?: boolean
  contract_emitted?: boolean

  // command fields
  command?: string

  // workflow step fields
  workflow_name?: string
  workflow_plugin?: string

  // branch fields
  condition?: string
  if_zero?: string
  if_nonzero?: string

  // loop fields
  max_iterations?: number
  on_exhaustion?: 'fail' | 'continue'
  substep?: Step

  // common fields
  inputs?: Record<string, unknown>
  output?: string
  output_schema?: Record<string, unknown>
  context_from?: string[]
  requires_plugins?: string[]
  on_error?: string
  skip?: string
  message?: string
  terminal?: boolean

  // nested steps (when expanded)
  steps?: Step[]
}

export interface Workflow {
  name: string
  description?: string
  path: string
  source: 'local' | 'plugin'
  plugin?: string
  version?: string
  stepCount: number
  steps: Step[]
  localOverride: boolean
}

export interface WorkflowsResponse {
  local: Workflow[]
  plugin: Workflow[]
}

// Group workflows by plugin/folder for display
export interface WorkflowGroup {
  name: string
  workflows: Workflow[]
}

export interface FeedbackLoop {
  name: string
  _meta: {
    kind: 'feedback'
    status: 'active' | 'paused' | 'archived'
    owner: string
    triggers: string[]
    metrics?: string
    anti_patterns: string[]
    related_loops: string[]
    last_audited?: string
  }
  steps: FeedbackLoopStep[]
  _mermaid?: string
}

export interface FeedbackLoopStep {
  id: string
  _meta: {
    actor: 'Claude' | 'Human' | 'System'
    doc: string
    prompts?: string[]
    checks?: string[]
  }
  [key: string]: unknown
}

export interface FeedbackLoopsResponse {
  kilnInstalled: boolean
  loops: FeedbackLoop[]
}