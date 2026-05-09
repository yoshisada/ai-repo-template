'use client'

// FR-3 / FR-5 / FR-7 — page-level orchestration:
//   - Owns selectedForDiff (Set of workflow keys) so DiffView can consume two workflows.
//   - Owns diffPair → when set, renders DiffView in place of FlowDiagram + RightPanel.
//   - Tracks loaded workflows for empty-state UX (FR-7.2 — "no workflows discovered").
//   - Renders FR-7.1 onboarding panel when no projects are registered.
//   - Renders FR-7.3 lint-error banner above FlowDiagram.

import { useState, useEffect, useMemo } from 'react'
import { ReactFlowProvider } from '@xyflow/react'
import Sidebar, { workflowKey } from '@/components/Sidebar'
import FlowDiagram from '@/components/FlowDiagram'
import RightPanel, { type RightPanelTab } from '@/components/RightPanel'
import DiffView from '@/components/DiffView'
import type { Project, Workflow } from '@/lib/types'
import { apiListProjects, apiListWorkflows, apiGetWorkflow, apiRegisterProject } from '@/lib/api'
import { lintWorkflow } from '@/lib/lint'
import { diffWorkflows } from '@/lib/diff'

export default function Page() {
  const [projects, setProjects] = useState<Project[]>([])
  const [activeProjectId, setActiveProjectId] = useState<string | null>(null)
  const [activeWorkflow, setActiveWorkflow] = useState<Workflow | null>(null)
  const [selectedStepId, setSelectedStepId] = useState<string | null>(null)
  const [expandedWorkflows, setExpandedWorkflows] = useState<Map<string, Workflow>>(new Map())
  // FR-7 — track loaded workflows for empty-state detection.
  const [loadedWorkflows, setLoadedWorkflows] = useState<Workflow[]>([])
  // FR-7.2 — local-only count for the active project. Plugin workflows are
  // global from installed_plugins.json, so they don't satisfy "this project
  // has workflows". The empty-workflows panel gates on this counter being 0
  // (qa-engineer flagged that the previous loadedWorkflows.length === 0 gate
  // never fired because installed plugins always populated the list).
  const [activeProjectLocalCount, setActiveProjectLocalCount] = useState(0)
  // FR-5.1 — workflows selected for diff (shift-click). Stored by stable key.
  const [selectedForDiff, setSelectedForDiff] = useState<Set<string>>(new Set())
  // FR-5 — when set, page renders DiffView in place of FlowDiagram + RightPanel.
  const [diffPair, setDiffPair] = useState<[Workflow, Workflow] | null>(null)
  // FR-4.2 — RightPanel active tab lifted here so the lint banner can flip it.
  const [rightPanelTab, setRightPanelTab] = useState<RightPanelTab>('detail')
  // FR-7.1 — onboarding form state for the zero-projects panel.
  const [onboardingPath, setOnboardingPath] = useState('')
  const [onboardingError, setOnboardingError] = useState<string | null>(null)
  const [onboardingBusy, setOnboardingBusy] = useState(false)
  // FR-7 — once we've completed at least one workflow load, we know if the active
  // project's workflows/ directory was empty. Distinguishes "loading" from "empty".
  const [hasFetchedWorkflows, setHasFetchedWorkflows] = useState(false)

  const activeProject = projects.find(p => p.id === activeProjectId)

  // FR-4 — compute lint issues for the active workflow once. Pure module, cheap.
  const activeWorkflowLint = useMemo(() => {
    if (!activeWorkflow) return []
    return lintWorkflow(activeWorkflow)
  }, [activeWorkflow])

  const activeWorkflowHasLintErrors = activeWorkflowLint.some(i => i.severity === 'error')

  // FR-5 — diff between the two pinned workflows. Pure module, recomputed on pair change.
  const diff = useMemo(() => {
    if (!diffPair) return null
    return diffWorkflows(diffPair[0], diffPair[1])
  }, [diffPair])

  useEffect(() => {
    apiListProjects()
      .then(p => {
        setProjects(p)
        if (p.length > 0 && !activeProjectId) {
          setActiveProjectId(p[0].id)
        }
      })
      .catch(console.error)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    if (!activeProjectId) {
      setHasFetchedWorkflows(false)
      setActiveProjectLocalCount(0)
      return
    }
    setHasFetchedWorkflows(false)
    apiListWorkflows(activeProjectId)
      .then(({ local, plugin }) => {
        // FR-7.2 — only auto-select if the project has its OWN workflows.
        // Auto-selecting from `plugin` (global installed workflows) hides the
        // FR-7.2 "No workflows discovered" panel for projects that have no
        // workflows/ directory.
        if (local.length > 0 && !activeWorkflow) {
          setActiveWorkflow(local[0])
          setSelectedStepId(null)
        }
        setActiveProjectLocalCount(local.length)
        // Best-effort: keep loadedWorkflows in sync even if Sidebar's onLoad
        // hasn't fired yet (page.tsx and Sidebar both call apiListWorkflows
        // due to legacy parallel state — should be consolidated in a future
        // PR). Diff lookup uses loadedWorkflows so it must include plugins.
        setLoadedWorkflows(prev => prev.length === 0 ? [...local, ...plugin] : prev)
        setHasFetchedWorkflows(true)
      })
      .catch(err => {
        console.error(err)
        setActiveProjectLocalCount(0)
        setHasFetchedWorkflows(true)
      })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeProjectId])

  const handleSelectWorkflow = (wf: Workflow) => {
    setSelectedStepId(null)
    setActiveWorkflow(wf)
    // Selecting a workflow exits diff mode (FR-5).
    setDiffPair(null)
    // Reset to Detail tab — the new workflow's Lint state is fresh.
    setRightPanelTab('detail')
  }

  // FR-5.1 — toggle a workflow into/out of the diff selection.
  const handleToggleDiffSelection = (wf: Workflow) => {
    const key = workflowKey(wf)
    setSelectedForDiff(prev => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })
  }

  // FR-5.1 — open diff view: requires exactly two selected workflows.
  const handleRequestDiff = () => {
    if (selectedForDiff.size !== 2) return
    const matched = loadedWorkflows.filter(w => selectedForDiff.has(workflowKey(w)))
    if (matched.length !== 2) return
    setDiffPair([matched[0], matched[1]])
  }

  const handleClearDiffSelection = () => {
    setSelectedForDiff(new Set())
    setDiffPair(null)
  }

  // FR-7.1 — onboarding-panel project registration.
  const handleOnboardingSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!onboardingPath.trim() || onboardingBusy) return
    setOnboardingBusy(true)
    setOnboardingError(null)
    try {
      const p = await apiRegisterProject(onboardingPath.trim())
      setProjects(prev => (prev.find(x => x.id === p.id) ? prev : [...prev, p]))
      setActiveProjectId(p.id)
      setOnboardingPath('')
    } catch (err) {
      console.error('Failed to register project', err)
      setOnboardingError('Could not register that path. Check it exists and is readable.')
    } finally {
      setOnboardingBusy(false)
    }
  }

  // FR-7.1 — when no projects are registered, show the onboarding panel
  // INSTEAD OF rendering Sidebar + main content. The sidebar's existing
  // add-project form is preserved when projects exist (different UX).
  if (projects.length === 0) {
    return (
      <>
        <Sidebar
          activeProjectId={null}
          activeWorkflow={null}
          projectId={null}
          selectedForDiff={new Set()}
          onSelectProject={id => setActiveProjectId(id)}
          onSelectWorkflow={() => {}}
          onWorkflowsLoaded={(wfs, localCount) => {
          setLoadedWorkflows(wfs)
          setActiveProjectLocalCount(localCount)
        }}
          onToggleDiffSelection={() => {}}
          onRequestDiff={() => {}}
          onClearDiffSelection={() => {}}
        />
        <div className="main-content">
          <div className="onboarding-panel" role="main" aria-labelledby="onboarding-title">
            <svg className="onboarding-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
              <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5" />
            </svg>
            <h2 id="onboarding-title">Add a project to get started</h2>
            <p className="onboarding-explanation">
              Add a project path to view its workflows.
            </p>
            <form className="onboarding-form" onSubmit={handleOnboardingSubmit}>
              <input
                type="text"
                className="onboarding-input"
                placeholder="/Users/you/projects/my-app"
                value={onboardingPath}
                onChange={e => setOnboardingPath(e.target.value)}
                aria-label="Absolute path to a project directory"
                autoFocus
              />
              <button
                type="submit"
                className="onboarding-submit"
                disabled={onboardingBusy || !onboardingPath.trim()}
              >
                {onboardingBusy ? 'Adding…' : 'Add project'}
              </button>
            </form>
            {onboardingError && (
              <p className="onboarding-error" role="alert">{onboardingError}</p>
            )}
            <p className="onboarding-hint">
              The path should be the root of a repo containing <code>workflows/</code> or
              <code> plugin-*/</code> directories.
            </p>
          </div>
        </div>
      </>
    )
  }

  return (
    <>
      <Sidebar
        activeProjectId={activeProjectId}
        activeWorkflow={activeWorkflow}
        projectId={activeProjectId}
        selectedForDiff={selectedForDiff}
        onSelectProject={id => {
          setActiveProjectId(id)
          setActiveWorkflow(null)
          setSelectedStepId(null)
          setSelectedForDiff(new Set())
          setDiffPair(null)
        }}
        onSelectWorkflow={handleSelectWorkflow}
        onWorkflowsLoaded={(wfs, localCount) => {
          setLoadedWorkflows(wfs)
          setActiveProjectLocalCount(localCount)
        }}
        onToggleDiffSelection={handleToggleDiffSelection}
        onRequestDiff={handleRequestDiff}
        onClearDiffSelection={handleClearDiffSelection}
      />
      <div className="main-content">
      {diffPair && diff ? (
        // FR-5 — DiffView replaces FlowDiagram + RightPanel.
        <DiffView
          left={diffPair[0]}
          right={diffPair[1]}
          diff={diff}
          onClose={handleClearDiffSelection}
        />
      ) : activeWorkflow ? (
        <>
          <div className="flow-header">
            <div className="flow-header-info">
              <h2>{activeWorkflow.name}</h2>
              {activeProject && (
                <span className="repo-path">{activeProject.path}</span>
              )}
            </div>
            <div className="meta">
              <div className="meta-item">
                <span className={`type-badge ${activeWorkflow.source}`}>{activeWorkflow.source}</span>
              </div>
              <div className="meta-item">
                <span>{activeWorkflow.stepCount}</span>
                <span>steps</span>
              </div>
              {activeWorkflow.plugin && (
                <div className="meta-item">
                  <span>{activeWorkflow.plugin}</span>
                </div>
              )}
            </div>
          </div>

          {/* FR-7.3 — lint-error banner above FlowDiagram offering to switch to Lint tab. */}
          {activeWorkflowHasLintErrors && rightPanelTab !== 'lint' && (
            <div className="lint-banner" role="alert">
              <span className="lint-banner-icon" aria-hidden="true">✕</span>
              <span className="lint-banner-message">
                {activeWorkflowLint.filter(i => i.severity === 'error').length} lint error
                {activeWorkflowLint.filter(i => i.severity === 'error').length === 1 ? '' : 's'}
                {' '}detected on this workflow.
              </span>
              <button
                type="button"
                className="lint-banner-action"
                onClick={() => setRightPanelTab('lint')}
              >
                View in Lint tab →
              </button>
            </div>
          )}

          <div className="content-area">
            <ReactFlowProvider>
              <FlowDiagram
                workflow={activeWorkflow}
                selectedStepId={selectedStepId}
                onSelectStep={setSelectedStepId}
                expandedWorkflows={expandedWorkflows}
              />
            </ReactFlowProvider>

            <RightPanel
              workflow={activeWorkflow}
              projectId={activeProjectId}
              selectedStepId={selectedStepId}
              tab={rightPanelTab}
              onTabChange={setRightPanelTab}
              lintIssues={activeWorkflowLint}
              onSelectStep={(id) => {
                setSelectedStepId(id)
                // Auto-expand sub-workflow on double-click if not already expanded
                if (!expandedWorkflows.has(id)) {
                  const step = activeWorkflow.steps.find((s: unknown) => (s as { id?: string }).id === id) as { type?: string; workflow_name?: string; workflow?: string } | undefined
                  // FR-1.6 / FR-2.4 — `teammate` steps reference a sub-workflow
                  // via `workflow` and must auto-expand alongside `workflow`-typed
                  // steps. Mirrors RightPanel.tsx's isExpandable widening.
                  if ((step?.type === 'workflow' || step?.type === 'teammate') && (step.workflow_name || step.workflow)) {
                    const wfName = (step.workflow_name || step.workflow) as string
                    apiGetWorkflow(wfName, activeProjectId ?? undefined).then(subWf => {
                      if (subWf) {
                        setExpandedWorkflows(prev => {
                          const next = new Map(prev)
                          next.set(id, subWf)
                          return next
                        })
                      }
                    })
                  }
                }
              }}
              onCloseStep={() => setSelectedStepId(null)}
              expandedWorkflows={expandedWorkflows}
              onToggleExpand={(stepId, subWf) => {
                setExpandedWorkflows(prev => {
                  const next = new Map(prev)
                  if (next.has(stepId)) {
                    next.delete(stepId)
                  } else {
                    next.set(stepId, subWf)
                  }
                  return next
                })
              }}
            />
          </div>
        </>
      ) : hasFetchedWorkflows && activeProjectLocalCount === 0 && activeProject ? (
        // FR-7.2 — project registered but workflows/ directory missing or empty.
        // Gates on local-only count (NOT loadedWorkflows.length) because plugin
        // workflows are global from installed_plugins.json — they don't count
        // as "this project has workflows."
        <div className="empty-workflows-panel" role="status">
          <svg className="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
            <path d="M3 7h18M3 12h18M3 17h18" />
          </svg>
          <h2>No workflows discovered</h2>
          <p>
            <code>{activeProject.path}</code> has no workflows registered yet.
          </p>
          <ul className="empty-workflows-hints">
            <li>
              Run <code>/wheel:wheel-init</code> in this project to scaffold a <code>workflows/</code> directory.
            </li>
            <li>
              Or check that <code>{activeProject.path}/workflows/</code> exists and contains <code>.json</code> files.
            </li>
            <li>
              For source-checkout authors: add this project's repo root and we&apos;ll auto-discover sibling
              <code> plugin-*/</code> directories.
            </li>
          </ul>
        </div>
      ) : (
        <div className="empty-state">
          <svg className="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
            <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5" />
          </svg>
          <h2>No workflow selected</h2>
          <p>Add a project and select a workflow from the sidebar to explore its flow.</p>
        </div>
      )}
      </div>
    </>
  )
}
