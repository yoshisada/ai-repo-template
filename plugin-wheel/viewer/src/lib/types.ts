// Type definitions for the wheel viewer.
//
// FR-2.1 — StepType union widened to include the four team primitives
//          (team-create, team-wait, team-delete, teammate).
// FR-2.3 — Step interface formalizes the team-step fields (team_name, team,
//          workflow, assign, workflow_definition).
// FR-6.3 — Workflow gains an optional `discoveryMode` field distinguishing
//          installed-via-marketplace from source-checkout discovery.

export interface Project {
  id: string
  path: string
  addedAt: string
}

// FR-2.1 — extended StepType union (was: command/agent/workflow/branch/loop/parallel/approval).
export type StepType =
  | 'command'
  | 'agent'
  | 'workflow'
  | 'branch'
  | 'loop'
  | 'parallel'
  | 'approval'
  | 'team-create'
  | 'team-wait'
  | 'team-delete'
  | 'teammate'

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

  // FR-2.3 — team-step fields (formalize what was previously informally stored
  // under the generic `agent: Record<string, unknown>` blob). All optional;
  // semantics depend on the step's `type`:
  //   team-create:  team_name (declared team identity)
  //   team-wait:    team (which team to wait on) + output (capture path)
  //   team-delete:  team (which team to dissolve) + terminal (final-step badge)
  //   teammate:     team (parent team), workflow (sub-workflow path),
  //                 assign (initial assignment payload), workflow_definition
  //                 (inline expansion shown in RightPanel).
  team_name?: string
  team?: string
  workflow?: string
  assign?: Record<string, unknown>
  workflow_definition?: Record<string, unknown>

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
  // FR-6.3 — discovery origin. Optional for backwards compatibility.
  //   'installed' = found via ~/.claude/plugins/installed_plugins.json.
  //   'source'    = found via projectPath/plugin-*/ scan (FR-6.2).
  //   'local'     = local workflow under projectPath/workflows/.
  // Omitted on legacy callers that don't set it.
  discoveryMode?: 'installed' | 'source' | 'local'
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
