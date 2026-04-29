'use client'

import { useState, useEffect } from 'react'
import type { Project, Workflow, WorkflowsResponse, WorkflowGroup } from '@/lib/types'
import { apiListProjects, apiRegisterProject, apiUnregisterProject, apiListWorkflows } from '@/lib/api'

interface SidebarProps {
  activeProjectId: string | null
  activeWorkflow: Workflow | null
  projectId: string | null
  onSelectProject: (id: string) => void
  onSelectWorkflow: (wf: Workflow) => void
}

function groupWorkflows(workflows: WorkflowsResponse): WorkflowGroup[] {
  const groups: Map<string, Workflow[]> = new Map()

  for (const w of workflows.local) {
    const key = 'Local'
    if (!groups.has(key)) groups.set(key, [])
    groups.get(key)!.push(w)
  }

  for (const w of workflows.plugin) {
    const key = w.plugin || 'Unknown'
    if (!groups.has(key)) groups.set(key, [])
    groups.get(key)!.push(w)
  }

  return Array.from(groups.entries()).map(([name, ws]) => ({ name, workflows: ws }))
}

export default function Sidebar({
  activeProjectId,
  activeWorkflow,
  projectId,
  onSelectProject,
  onSelectWorkflow,
}: SidebarProps) {
  const [projects, setProjects] = useState<Project[]>([])
  const [workflows, setWorkflows] = useState<WorkflowsResponse>({ local: [], plugin: [] })
  const [groups, setGroups] = useState<WorkflowGroup[]>([])
  const [expandedGroups, setExpandedGroups] = useState<Set<string>>(new Set())
  const [newPath, setNewPath] = useState('')
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    apiListProjects()
      .then(p => {
        setProjects(p)
        if (p.length > 0 && !activeProjectId) {
          onSelectProject(p[0].id)
        }
      })
      .catch(console.error)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    if (!activeProjectId) return
    apiListWorkflows(activeProjectId)
      .then(w => {
        setWorkflows(w)
        const g = groupWorkflows(w)
        setGroups(g)
        // Expand all groups by default
        setExpandedGroups(new Set(g.map(x => x.name)))
      })
      .catch(console.error)
  }, [activeProjectId])

  const handleAddProject = async () => {
    if (!newPath.trim() || loading) return
    setLoading(true)
    try {
      const p = await apiRegisterProject(newPath.trim())
      setProjects(prev => {
        if (prev.find(x => x.id === p.id)) return prev
        return [...prev, p]
      })
      onSelectProject(p.id)
      setNewPath('')
    } catch (e) {
      console.error('Failed to register project', e)
    } finally {
      setLoading(false)
    }
  }

  const handleRemoveProject = async (e: React.MouseEvent, id: string) => {
    e.stopPropagation()
    try {
      await apiUnregisterProject(id)
      setProjects(prev => prev.filter(p => p.id !== id))
      if (activeProjectId === id) {
        const remaining = projects.filter(p => p.id !== id)
        onSelectProject(remaining[0]?.id ?? '')
      }
    } catch (e) {
      console.error('Failed to remove project', e)
    }
  }

  const toggleGroup = (name: string) => {
    setExpandedGroups(prev => {
      const next = new Set(prev)
      if (next.has(name)) next.delete(name)
      else next.add(name)
      return next
    })
  }

  const isActiveWorkflow = (wf: Workflow) =>
    activeWorkflow?.name === wf.name && activeWorkflow?.source === wf.source && activeWorkflow?.plugin === wf.plugin

  return (
    <div className="sidebar">
      <div className="sidebar-header">
        <div className="logo">W</div>
        <h1>Wheel View</h1>
        <span className="version">v0.1</span>
      </div>

      <div className="sidebar-section">
        <div className="section-header">
          <span>Projects</span>
          <span className="count">{projects.length}</span>
        </div>
        <div className="project-list">
          {projects.map(p => (
            <div
              key={p.id}
              className={`project-item ${activeProjectId === p.id ? 'active' : ''}`}
              onClick={() => onSelectProject(p.id)}
            >
              <span className="name">{p.path.split('/').pop()}</span>
              <button
                className="remove"
                onClick={e => handleRemoveProject(e, p.id)}
                title="Remove project"
              >
                ×
              </button>
            </div>
          ))}
        </div>
        <div className="add-project">
          <input
            placeholder="/path/to/repo"
            value={newPath}
            onChange={e => setNewPath(e.target.value)}
            onKeyDown={e => e.key === 'Enter' && handleAddProject()}
          />
          <button onClick={handleAddProject} disabled={loading || !newPath.trim()}>
            {loading ? '...' : 'Add Project'}
          </button>
        </div>
      </div>

      {activeProjectId && (
        <div className="workflow-list">
          {groups.map(group => {
            const isExpanded = expandedGroups.has(group.name)
            const isLocal = group.name === 'Local'
            return (
              <div key={group.name} className="workflow-group">
                <div
                  className="workflow-group-header"
                  onClick={() => toggleGroup(group.name)}
                >
                  <span className="group-toggle">{isExpanded ? '▼' : '▶'}</span>
                  <span className={`group-name ${isLocal ? 'local' : 'plugin'}`}>{group.name}</span>
                  <span className="count">{group.workflows.length}</span>
                </div>
                {isExpanded && group.workflows.map(w => (
                  <div
                    key={`${w.source}-${w.plugin || 'local'}-${w.name}`}
                    className={`workflow-item ${isActiveWorkflow(w) ? 'active' : ''}`}
                    onClick={() => onSelectWorkflow(w)}
                  >
                    <span className={`type-badge ${w.source}`}>
                      {w.source === 'local' ? 'L' : (w.plugin?.slice(0, 2).toUpperCase() || '?')}
                    </span>
                    <span className="name">{w.name}</span>
                    <span className="step-count">{w.stepCount}</span>
                  </div>
                ))}
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}