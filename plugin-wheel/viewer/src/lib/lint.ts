// FR-4 — Structural lint for workflow JSON.
//
// Pure-functional, deterministic, no I/O. The `installed_plugins.json` snapshot
// (and the source-discovered plugin name list) is passed in via LintContext —
// loading it is the caller's responsibility (FR-4.4).
//
// Output is sorted: errors before warnings, then by step index ascending,
// then by ruleId ascending. Workflow-level issues (e.g. duplicate-id) sort
// before all step-level issues within their severity by using index = -1.
//
// Rules:
//   L-001 (error)   step has no `id` (or empty string)
//   L-002 (error)   step `type` missing or not in StepType union
//   L-003 (error)   `branch` step's if_zero / if_nonzero target unresolved
//   L-004 (error)   `skip` target unresolved
//   L-005 (error)   `loop` step has no `substep` defined
//   L-006 (error)   duplicate step ids within the workflow
//   L-007 (warning) `requires_plugins` references a plugin not in installedPlugins
//                   AND not in sourceDiscoveredPlugins (skipped if ctx omitted)
//   L-008 (warning) `team-create` step missing `team_name`
//   L-009 (warning) `teammate` step missing `team` / `workflow` / `assign`
//   L-010 (warning) `team-wait` step's `team` ref doesn't match any prior `team-create`

import type { Step, StepType, Workflow } from './types'

export type LintSeverity = 'error' | 'warning'

export type LintRuleId =
  | 'L-001' | 'L-002' | 'L-003' | 'L-004' | 'L-005'
  | 'L-006' | 'L-007' | 'L-008' | 'L-009' | 'L-010'

export interface LintIssue {
  severity: LintSeverity
  /** Empty string for workflow-level issues (e.g. L-006 surfaced once). */
  stepId: string
  ruleId: LintRuleId
  message: string
}

export interface LintContext {
  /** Snapshot of installed_plugins.json keys, e.g. ['kiln', 'wheel']. Empty = unknown. */
  installedPlugins: string[]
  /** Source-discovered plugin short names (FR-6.2), e.g. ['kiln', 'shelf']. */
  sourceDiscoveredPlugins: string[]
}

export type LintBadge = 'clean' | 'warning' | 'error'

// FR-2.1 — recognized StepType union, mirrored here for runtime-time check.
const VALID_STEP_TYPES: ReadonlySet<string> = new Set<string>([
  'command',
  'agent',
  'workflow',
  'branch',
  'loop',
  'parallel',
  'approval',
  'team-create',
  'team-wait',
  'team-delete',
  'teammate',
])

// Indexed issue used during collection so the final sort can be stable
// (workflow-level issues use _index = -1).
interface IndexedIssue extends LintIssue {
  _index: number
}

function emit(
  out: IndexedIssue[],
  severity: LintSeverity,
  ruleId: LintRuleId,
  index: number,
  stepId: string,
  message: string,
): void {
  out.push({ severity, stepId, ruleId, message, _index: index })
}

/**
 * FR-4.4 — Pure, deterministic, synchronous. No I/O.
 *
 * @param wf  The workflow whose top-level `steps` array is linted.
 * @param ctx Optional. When omitted, L-007 is skipped (not failed).
 * @returns   Sorted lint issues (errors first, then by step index, then by ruleId).
 */
export function lintWorkflow(wf: Workflow, ctx?: LintContext): LintIssue[] {
  // FR-4.4 — collect, then sort. v1 lints top-level steps only; substep lint
  // is out of scope per spec.md edge case.
  const indexed: IndexedIssue[] = []
  const steps: Step[] = wf.steps ?? []

  // ---- per-step rules: L-001, L-002, L-003, L-004, L-005, L-007, L-008, L-009, L-010 ----

  // Build sibling-id set up front so L-003 / L-004 are O(N) lookups.
  const siblingIds = new Set<string>()
  for (const step of steps) {
    if (typeof step.id === 'string' && step.id.length > 0) {
      siblingIds.add(step.id)
    }
  }

  // Track team-create names seen so far (in order) for L-010.
  const teamCreatesSeenSoFar = new Set<string>()

  for (let i = 0; i < steps.length; i++) {
    const step = steps[i]
    const sid = typeof step.id === 'string' ? step.id : ''

    // L-001: every step must have a non-empty id
    if (sid === '') {
      emit(indexed, 'error', 'L-001', i, '', `step at index ${i} has no \`id\``)
    }

    // L-002: step type must be a known StepType union member
    if (typeof step.type !== 'string' || !VALID_STEP_TYPES.has(step.type)) {
      emit(
        indexed,
        'error',
        'L-002',
        i,
        sid,
        `step \`${sid || `<index ${i}>`}\` has missing/unknown type ${
          step.type ? `'${String(step.type)}'` : '(undefined)'
        }`,
      )
    }

    // L-003: branch step targets must resolve
    if (step.type === 'branch') {
      if (typeof step.if_zero === 'string' && step.if_zero.length > 0
          && !siblingIds.has(step.if_zero)) {
        emit(
          indexed,
          'error',
          'L-003',
          i,
          sid,
          `branch step \`${sid}\` if_zero target '${step.if_zero}' does not resolve to a sibling step id`,
        )
      }
      if (typeof step.if_nonzero === 'string' && step.if_nonzero.length > 0
          && !siblingIds.has(step.if_nonzero)) {
        emit(
          indexed,
          'error',
          'L-003',
          i,
          sid,
          `branch step \`${sid}\` if_nonzero target '${step.if_nonzero}' does not resolve to a sibling step id`,
        )
      }
    }

    // L-004: skip target must resolve
    if (typeof step.skip === 'string' && step.skip.length > 0
        && !siblingIds.has(step.skip)) {
      emit(
        indexed,
        'error',
        'L-004',
        i,
        sid,
        `step \`${sid}\` skip target '${step.skip}' does not resolve to a sibling step id`,
      )
    }

    // L-005: loop step must define a substep
    if (step.type === 'loop' && (step.substep == null || typeof step.substep !== 'object')) {
      emit(
        indexed,
        'error',
        'L-005',
        i,
        sid,
        `loop step \`${sid}\` has no \`substep\` defined`,
      )
    }

    // L-007: requires_plugins reference check (warning, requires LintContext).
    if (ctx && Array.isArray(step.requires_plugins)) {
      const installed = new Set(ctx.installedPlugins)
      const sourceDisc = new Set(ctx.sourceDiscoveredPlugins)
      for (const plugin of step.requires_plugins) {
        if (!installed.has(plugin) && !sourceDisc.has(plugin)) {
          emit(
            indexed,
            'warning',
            'L-007',
            i,
            sid,
            `step \`${sid}\` requires_plugins references unknown plugin '${plugin}' (not installed and not source-discovered)`,
          )
        }
      }
    }

    // L-008: team-create missing team_name
    if (step.type === 'team-create'
        && (typeof step.team_name !== 'string' || step.team_name.length === 0)) {
      emit(
        indexed,
        'warning',
        'L-008',
        i,
        sid,
        `team-create step \`${sid}\` is missing \`team_name\``,
      )
    }

    // L-009: teammate missing team / workflow / assign
    if (step.type === 'teammate') {
      const missing: string[] = []
      if (typeof step.team !== 'string' || step.team.length === 0) missing.push('team')
      if (typeof step.workflow !== 'string' || step.workflow.length === 0) missing.push('workflow')
      if (step.assign == null || typeof step.assign !== 'object') missing.push('assign')
      if (missing.length > 0) {
        emit(
          indexed,
          'warning',
          'L-009',
          i,
          sid,
          `teammate step \`${sid}\` missing required field(s): ${missing.join(', ')}`,
        )
      }
    }

    // L-010: team-wait must follow a team-create with the same team ref.
    // Track team-create names seen so far in iteration order.
    if (step.type === 'team-wait') {
      const ref = typeof step.team === 'string' ? step.team : ''
      if (ref.length > 0 && !teamCreatesSeenSoFar.has(ref)) {
        emit(
          indexed,
          'warning',
          'L-010',
          i,
          sid,
          `team-wait step \`${sid}\` references team '${ref}' but no prior team-create defines it`,
        )
      }
    }

    // Update team-create tracker AFTER L-010 evaluation so a team-wait that
    // appears at the same index as its own team-create (impossible, but
    // illustrative) doesn't self-resolve.
    if (step.type === 'team-create' && typeof step.team_name === 'string'
        && step.team_name.length > 0) {
      teamCreatesSeenSoFar.add(step.team_name)
    }
  }

  // ---- workflow-level rules: L-006 ----

  // L-006: duplicate step ids — surface once per workflow (stepId = '', _index = -1
  // sorts before all step-level issues within its severity).
  const seenIds = new Set<string>()
  const dupIds = new Set<string>()
  for (const step of steps) {
    if (typeof step.id === 'string' && step.id.length > 0) {
      if (seenIds.has(step.id)) dupIds.add(step.id)
      seenIds.add(step.id)
    }
  }
  if (dupIds.size > 0) {
    emit(
      indexed,
      'error',
      'L-006',
      -1,
      '',
      `duplicate step id(s): ${Array.from(dupIds).sort().join(', ')}`,
    )
  }

  // ---- sort + strip _index ----
  // FR-4.4 — deterministic sort: errors before warnings, then by step index, then by ruleId.
  indexed.sort((a, b) => {
    const sevRank = (s: LintSeverity) => (s === 'error' ? 0 : 1)
    const sa = sevRank(a.severity)
    const sb = sevRank(b.severity)
    if (sa !== sb) return sa - sb
    if (a._index !== b._index) return a._index - b._index
    return a.ruleId < b.ruleId ? -1 : a.ruleId > b.ruleId ? 1 : 0
  })

  return indexed.map(({ _index: _, ...issue }) => issue)
}

/**
 * FR-4.1 — Helper used by the Sidebar to derive a workflow-level severity badge.
 *
 * Returns:
 *   'error'   if any issue.severity === 'error'
 *   'warning' if any issue.severity === 'warning' (and zero errors)
 *   'clean'   otherwise
 */
export function workflowLintBadge(issues: LintIssue[]): LintBadge {
  let hasWarning = false
  for (const issue of issues) {
    if (issue.severity === 'error') return 'error'
    if (issue.severity === 'warning') hasWarning = true
  }
  return hasWarning ? 'warning' : 'clean'
}
