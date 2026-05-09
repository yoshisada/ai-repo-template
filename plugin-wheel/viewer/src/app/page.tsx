'use client'

import { useState, useEffect } from 'react'
import { ReactFlowProvider } from '@xyflow/react'
import Sidebar from '@/components/Sidebar'
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
  }

  return (
    <>
      <Sidebar
        activeProjectId={activeProjectId}
        activeWorkflow={activeWorkflow}
        projectId={activeProjectId}
        onSelectProject={id => {
          setActiveProjectId(id)
          setActiveWorkflow(null)
          setSelectedStepId(null)
        }}
        onSelectWorkflow={handleSelectWorkflow}
      />
      <div className="main-content">
      {activeWorkflow ? (
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