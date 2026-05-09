'use client'

// FR-3 / FR-5 / FR-7 — page-level orchestration:
//   - Owns selectedForDiff (Set of workflow keys) so DiffView can consume two workflows.
//   - Owns diffPair → when set, renders DiffView in place of FlowDiagram + RightPanel.
//   - Tracks loaded workflows for empty-state UX (FR-7.2 — "no workflows discovered").

import { useState, useEffect } from 'react'
import { ReactFlowProvider } from '@xyflow/react'
import Sidebar, { workflowKey } from '@/components/Sidebar'
import FlowDiagram from '@/components/FlowDiagram'
import RightPanel from '@/components/RightPanel'
import type { Project, Workflow } from '@/lib/types'
import { apiListProjects, apiListWorkflows, apiGetWorkflow } from '@/lib/api'

export default function Page() {
  const [projects, setProjects] = useState<Project[]>([])
  const [activeProjectId, setActiveProjectId] = useState<string | null>(null)
  const [activeWorkflow, setActiveWorkflow] = useState<Workflow | null>(null)
  const [selectedStepId, setSelectedStepId] = useState<string | null>(null)
  const [expandedWorkflows, setExpandedWorkflows] = useState<Map<string, Workflow>>(new Map())
  // FR-7 — track loaded workflows for empty-state detection.
  const [loadedWorkflows, setLoadedWorkflows] = useState<Workflow[]>([])
  // FR-5.1 — workflows selected for diff (shift-click). Stored by stable key.
  const [selectedForDiff, setSelectedForDiff] = useState<Set<string>>(new Set())
  // FR-5 — when set, page renders DiffView in place of FlowDiagram + RightPanel.
  const [diffPair, setDiffPair] = useState<[Workflow, Workflow] | null>(null)

  const activeProject = projects.find(p => p.id === activeProjectId)

  useEffect(() => {
    apiListProjects()
      .then(p => {
        setProjects(p)
        if (p.length > 0 && !activeProjectId) {
          setActiveProjectId(p[0].id)
        }
      })
      .catch(console.error)
  }, [])

  useEffect(() => {
    if (!activeProjectId) return
    apiListWorkflows(activeProjectId)
      .then(({ local, plugin }) => {
        const all = [...local, ...plugin]
        if (all.length > 0 && !activeWorkflow) {
          setActiveWorkflow(all[0])
          setSelectedStepId(null)
        }
      })
      .catch(console.error)
  }, [activeProjectId])

  const handleSelectWorkflow = (wf: Workflow) => {
    setSelectedStepId(null)
    setActiveWorkflow(wf)
    // Selecting a workflow exits diff mode (FR-5).
    setDiffPair(null)
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
        onWorkflowsLoaded={setLoadedWorkflows}
        onToggleDiffSelection={handleToggleDiffSelection}
        onRequestDiff={handleRequestDiff}
        onClearDiffSelection={handleClearDiffSelection}
      />
      <div className="main-content">
      {diffPair ? (
        // FR-5.2 — DiffView placeholder; full component lands when lib/diff.ts ships (T026).
        <div className="diff-view-placeholder">
          <div className="flow-header">
            <div className="flow-header-info">
              <h2>Diff: {diffPair[0].name} ↔ {diffPair[1].name}</h2>
              <span className="repo-path">DiffView component coming next commit</span>
            </div>
            <div className="meta">
              <button type="button" className="diff-btn" onClick={handleClearDiffSelection}>
                Close diff
              </button>
            </div>
          </div>
        </div>
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
              onSelectStep={(id) => {
                setSelectedStepId(id)
                // Auto-expand sub-workflow on double-click if not already expanded
                if (!expandedWorkflows.has(id)) {
                  const step = activeWorkflow.steps.find((s: unknown) => (s as { id?: string }).id === id) as { type?: string; workflow_name?: string; workflow?: string } | undefined
                  if (step?.type === 'workflow' && (step.workflow_name || step.workflow)) {
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
