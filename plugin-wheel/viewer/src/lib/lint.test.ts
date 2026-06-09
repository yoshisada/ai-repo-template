// Lint module rule coverage — tests every L-001..L-010 rule (positive + negative)
// per SC-014, plus the clean-workflow case, the compound-issues case, and the
// hand-crafted broken fixture under plugin-wheel/tests/lint-fixture-broken.json
// (positive multi-rule fixture for AC-8).
//
// FR-4.3 / FR-4.4 / SC-014 — pure-functional lint, deterministic output.

import * as fs from 'fs'
import * as path from 'path'
import { describe, it, expect } from 'vitest'
import {
  lintWorkflow,
  workflowLintBadge,
  type LintContext,
  type LintIssue,
} from './lint'
import type { Workflow } from './types'

// ---------- helpers ----------

function makeWorkflow(steps: Workflow['steps'], overrides?: Partial<Workflow>): Workflow {
  return {
    name: 'fixture',
    path: '/tmp/fixture.json',
    source: 'local',
    stepCount: steps.length,
    steps,
    localOverride: false,
    ...overrides,
  }
}

function rules(issues: LintIssue[]): string[] {
  return issues.map(i => i.ruleId)
}

// ---------- L-001: every step must have a non-empty id ----------

describe('L-001 — step id required', () => {
  it('flags a step with missing id', () => {
    // FR-4.3 L-001 — error
    const wf = makeWorkflow([{ type: 'command' }])
    const issues = lintWorkflow(wf)
    expect(rules(issues)).toContain('L-001')
    const issue = issues.find(i => i.ruleId === 'L-001')!
    expect(issue.severity).toBe('error')
  })

  it('flags a step with empty-string id', () => {
    // FR-4.3 L-001 — empty string counts as missing
    const wf = makeWorkflow([{ id: '', type: 'command' }])
    expect(rules(lintWorkflow(wf))).toContain('L-001')
  })

  it('does not flag a step with valid id', () => {
    const wf = makeWorkflow([{ id: 's1', type: 'command' }])
    expect(rules(lintWorkflow(wf))).not.toContain('L-001')
  })
})

// ---------- L-002: step type must be a known StepType union member ----------

describe('L-002 — step type required and recognized', () => {
  it('flags a step with missing type', () => {
    // FR-4.3 L-002 — error
    const wf = makeWorkflow([{ id: 's1' }])
    expect(rules(lintWorkflow(wf))).toContain('L-002')
  })

  it('flags a step with unknown type', () => {
    // FR-4.3 L-002 — `nope` is not in StepType union
    const wf = makeWorkflow([{ id: 's1', type: 'nope' as unknown as Workflow['steps'][0]['type'] }])
    expect(rules(lintWorkflow(wf))).toContain('L-002')
  })

  it('does not flag a step with valid type', () => {
    const wf = makeWorkflow([{ id: 's1', type: 'command' }])
    expect(rules(lintWorkflow(wf))).not.toContain('L-002')
  })

  it('accepts the team-step types (FR-2.1)', () => {
    const wf = makeWorkflow([
      { id: 's1', type: 'team-create', team_name: 'workers' },
      { id: 's2', type: 'team-wait', team: 'workers' },
      { id: 's3', type: 'team-delete', team: 'workers' },
    ])
    expect(rules(lintWorkflow(wf))).not.toContain('L-002')
  })
})

// ---------- L-003: branch step's if_zero / if_nonzero target must resolve ----------

describe('L-003 — branch target must resolve to a sibling step id', () => {
  it('flags an if_zero target that does not match any sibling id', () => {
    // FR-4.3 L-003 — error
    const wf = makeWorkflow([
      { id: 's1', type: 'branch', if_zero: 'missing', if_nonzero: 's2' },
      { id: 's2', type: 'command' },
    ])
    expect(rules(lintWorkflow(wf))).toContain('L-003')
  })

  it('flags an if_nonzero target that does not match', () => {
    const wf = makeWorkflow([
      { id: 's1', type: 'branch', if_zero: 's2', if_nonzero: 'missing' },
      { id: 's2', type: 'command' },
    ])
    expect(rules(lintWorkflow(wf))).toContain('L-003')
  })

  it('does not flag a branch step with both targets resolving', () => {
    const wf = makeWorkflow([
      { id: 's1', type: 'branch', if_zero: 's2', if_nonzero: 's3' },
      { id: 's2', type: 'command' },
      { id: 's3', type: 'command' },
    ])
    expect(rules(lintWorkflow(wf))).not.toContain('L-003')
  })
})

// ---------- L-004: skip target must resolve to a sibling step id ----------

describe('L-004 — skip target must resolve', () => {
  it('flags an unresolved skip target', () => {
    // FR-4.3 L-004 — error
    const wf = makeWorkflow([
      { id: 's1', type: 'command', skip: 'nowhere' },
      { id: 's2', type: 'command' },
    ])
    expect(rules(lintWorkflow(wf))).toContain('L-004')
  })

  it('does not flag a resolved skip target', () => {
    const wf = makeWorkflow([
      { id: 's1', type: 'command', skip: 's2' },
      { id: 's2', type: 'command' },
    ])
    expect(rules(lintWorkflow(wf))).not.toContain('L-004')
  })
})

// ---------- L-005: loop step must define a substep ----------

describe('L-005 — loop step must define a substep', () => {
  it('flags a loop step with no substep', () => {
    // FR-4.3 L-005 — error
    const wf = makeWorkflow([{ id: 'loop1', type: 'loop' }])
    expect(rules(lintWorkflow(wf))).toContain('L-005')
  })

  it('does not flag a loop step with a substep', () => {
    const wf = makeWorkflow([
      { id: 'loop1', type: 'loop', substep: { id: 'inner', type: 'command' } },
    ])
    expect(rules(lintWorkflow(wf))).not.toContain('L-005')
  })
})

// ---------- L-006: no duplicate step ids within a workflow ----------

describe('L-006 — duplicate step ids', () => {
  it('flags duplicate ids', () => {
    // FR-4.3 L-006 — error
    const wf = makeWorkflow([
      { id: 'dup', type: 'command' },
      { id: 'dup', type: 'command' },
    ])
    const issues = lintWorkflow(wf)
    expect(rules(issues)).toContain('L-006')
    // Surfaced once per workflow (workflow-level), stepId is empty string per contracts.
    const dupIssues = issues.filter(i => i.ruleId === 'L-006')
    expect(dupIssues).toHaveLength(1)
    expect(dupIssues[0].stepId).toBe('')
  })

  it('does not flag unique ids', () => {
    const wf = makeWorkflow([
      { id: 'a', type: 'command' },
      { id: 'b', type: 'command' },
    ])
    expect(rules(lintWorkflow(wf))).not.toContain('L-006')
  })
})

// ---------- L-007: requires_plugins references unknown plugin ----------

describe('L-007 — requires_plugins reference check (uses LintContext)', () => {
  it('flags a plugin not in installedPlugins and not source-discovered', () => {
    // FR-4.3 L-007 — warning
    const wf = makeWorkflow([
      { id: 's1', type: 'command', requires_plugins: ['ghost'] },
    ])
    const ctx: LintContext = {
      installedPlugins: ['kiln', 'wheel'],
      sourceDiscoveredPlugins: ['shelf'],
    }
    const issues = lintWorkflow(wf, ctx)
    expect(rules(issues)).toContain('L-007')
    expect(issues.find(i => i.ruleId === 'L-007')!.severity).toBe('warning')
  })

  it('does not flag a plugin present in installedPlugins', () => {
    const wf = makeWorkflow([
      { id: 's1', type: 'command', requires_plugins: ['kiln'] },
    ])
    const ctx: LintContext = { installedPlugins: ['kiln'], sourceDiscoveredPlugins: [] }
    expect(rules(lintWorkflow(wf, ctx))).not.toContain('L-007')
  })

  it('does not flag a plugin present in sourceDiscoveredPlugins', () => {
    const wf = makeWorkflow([
      { id: 's1', type: 'command', requires_plugins: ['shelf'] },
    ])
    const ctx: LintContext = { installedPlugins: [], sourceDiscoveredPlugins: ['shelf'] }
    expect(rules(lintWorkflow(wf, ctx))).not.toContain('L-007')
  })

  it('skips L-007 entirely when ctx is omitted (does not fail)', () => {
    // FR-4.4 — when no LintContext is provided, L-007 is not evaluated.
    const wf = makeWorkflow([
      { id: 's1', type: 'command', requires_plugins: ['anything'] },
    ])
    expect(rules(lintWorkflow(wf))).not.toContain('L-007')
  })
})

// ---------- L-008: team-create missing team_name ----------

describe('L-008 — team-create missing team_name', () => {
  it('flags team-create with no team_name', () => {
    // FR-4.3 L-008 — warning
    const wf = makeWorkflow([{ id: 't1', type: 'team-create' }])
    const issues = lintWorkflow(wf)
    expect(rules(issues)).toContain('L-008')
    expect(issues.find(i => i.ruleId === 'L-008')!.severity).toBe('warning')
  })

  it('does not flag team-create with team_name set', () => {
    const wf = makeWorkflow([{ id: 't1', type: 'team-create', team_name: 'workers' }])
    expect(rules(lintWorkflow(wf))).not.toContain('L-008')
  })
})

// ---------- L-009: teammate missing team / workflow / assign ----------

describe('L-009 — teammate missing required fields', () => {
  it('flags teammate missing team', () => {
    // FR-4.3 L-009 — warning
    const wf = makeWorkflow([
      { id: 'm1', type: 'teammate', workflow: 'sub.json', assign: { task: 'x' } },
    ])
    expect(rules(lintWorkflow(wf))).toContain('L-009')
  })

  it('flags teammate missing workflow', () => {
    const wf = makeWorkflow([
      { id: 'm1', type: 'teammate', team: 'workers', assign: { task: 'x' } },
    ])
    expect(rules(lintWorkflow(wf))).toContain('L-009')
  })

  it('flags teammate missing assign', () => {
    const wf = makeWorkflow([
      { id: 'm1', type: 'teammate', team: 'workers', workflow: 'sub.json' },
    ])
    expect(rules(lintWorkflow(wf))).toContain('L-009')
  })

  it('does not flag teammate with all three fields', () => {
    const wf = makeWorkflow([
      {
        id: 'm1',
        type: 'teammate',
        team: 'workers',
        workflow: 'sub.json',
        assign: { task: 'x' },
      },
    ])
    expect(rules(lintWorkflow(wf))).not.toContain('L-009')
  })
})

// ---------- L-010: team-wait references a team not previously created ----------

describe('L-010 — team-wait must follow a team-create with the same team ref', () => {
  it('flags team-wait whose team has no prior team-create', () => {
    // FR-4.3 L-010 — warning
    const wf = makeWorkflow([
      { id: 'w1', type: 'team-wait', team: 'orphans' },
    ])
    expect(rules(lintWorkflow(wf))).toContain('L-010')
  })

  it('flags team-wait that comes BEFORE the matching team-create', () => {
    const wf = makeWorkflow([
      { id: 'w1', type: 'team-wait', team: 'workers' },
      { id: 'c1', type: 'team-create', team_name: 'workers' },
    ])
    expect(rules(lintWorkflow(wf))).toContain('L-010')
  })

  it('does not flag team-wait following a matching team-create', () => {
    const wf = makeWorkflow([
      { id: 'c1', type: 'team-create', team_name: 'workers' },
      { id: 'w1', type: 'team-wait', team: 'workers' },
    ])
    expect(rules(lintWorkflow(wf))).not.toContain('L-010')
  })
})

// ---------- clean-workflow + compound-issues + sort-order ----------

describe('lintWorkflow — aggregate behavior', () => {
  it('returns [] for a clean workflow', () => {
    const wf = makeWorkflow([
      { id: 'c1', type: 'team-create', team_name: 'workers' },
      { id: 'm1', type: 'teammate', team: 'workers', workflow: 'sub.json', assign: {} },
      { id: 'w1', type: 'team-wait', team: 'workers' },
    ])
    expect(lintWorkflow(wf)).toEqual([])
  })

  it('surfaces both errors AND warnings in one pass', () => {
    // L-001 (error: missing id) + L-008 (warning: team-create missing team_name)
    const wf = makeWorkflow([
      { type: 'command' }, // missing id → L-001
      { id: 'tc', type: 'team-create' }, // missing team_name → L-008
    ])
    const issues = lintWorkflow(wf)
    const ids = rules(issues)
    expect(ids).toContain('L-001')
    expect(ids).toContain('L-008')
    // Sort: errors before warnings.
    const firstError = issues.findIndex(i => i.severity === 'error')
    const firstWarning = issues.findIndex(i => i.severity === 'warning')
    expect(firstError).toBeLessThan(firstWarning)
  })

  it('sorts issues deterministically: errors first, then by step index, then by ruleId', () => {
    // FR-4.4 — deterministic output for screenshot fixtures.
    const wf = makeWorkflow([
      { id: 'a', type: 'loop' }, // L-005 (error, idx 0)
      { type: 'command' }, // L-001 (error, idx 1) + L-002? (no — type is set)
    ])
    const issues = lintWorkflow(wf)
    // First error should be L-005 at idx 0; second should be L-001 at idx 1.
    expect(issues[0].ruleId).toBe('L-005')
    expect(issues[1].ruleId).toBe('L-001')
  })
})

// ---------- workflowLintBadge helper ----------

describe('workflowLintBadge', () => {
  it("returns 'clean' on empty issue list", () => {
    expect(workflowLintBadge([])).toBe('clean')
  })

  it("returns 'warning' on warnings only", () => {
    const issues: LintIssue[] = [
      { severity: 'warning', stepId: 's1', ruleId: 'L-008', message: 'x' },
    ]
    expect(workflowLintBadge(issues)).toBe('warning')
  })

  it("returns 'error' when any error is present", () => {
    const issues: LintIssue[] = [
      { severity: 'warning', stepId: 's1', ruleId: 'L-008', message: 'x' },
      { severity: 'error', stepId: 's2', ruleId: 'L-001', message: 'y' },
    ]
    expect(workflowLintBadge(issues)).toBe('error')
  })
})

// ---------- AC-8 / SC-008 broken-fixture integration ----------

describe('lint-fixture-broken.json — AC-8 / SC-008 multi-rule fixture', () => {
  // FR-4.3 — fixture under plugin-wheel/tests/ triggers L-001, L-003, L-005, L-008.
  const fixturePath = path.resolve(
    __dirname,
    '..',
    '..',
    '..',
    '..',
    'plugin-wheel',
    'tests',
    'lint-fixture-broken.json',
  )

  it('the fixture file exists at the expected path', () => {
    expect(fs.existsSync(fixturePath)).toBe(true)
  })

  it('triggers L-001, L-003, L-005, L-008 simultaneously', () => {
    const raw = fs.readFileSync(fixturePath, 'utf8')
    const json = JSON.parse(raw)
    const wf: Workflow = {
      name: json.name,
      description: json.description,
      path: fixturePath,
      source: 'local',
      stepCount: json.steps.length,
      steps: json.steps,
      localOverride: false,
    }
    const issues = lintWorkflow(wf)
    const ids = rules(issues)
    expect(ids).toContain('L-001')
    expect(ids).toContain('L-003')
    expect(ids).toContain('L-005')
    expect(ids).toContain('L-008')
  })
})
