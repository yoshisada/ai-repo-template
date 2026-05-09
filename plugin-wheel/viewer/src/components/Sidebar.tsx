'use client'

// FR-3 — Sidebar gains search + step-type chip filter + clear-all + post-filter group counts.
// FR-5.1 — Multi-select for diff via shift-click; "Diff" affordance when exactly two selected.
// FR-6.3 — Source-discovered workflows show "(source)" suffix on the type badge.
// FR-4.1 — Lint badge per workflow (consumes workflowLintBadge) — deferred until lib/lint.ts ships.

import { useState, useEffect, useMemo } from 'react'
import type { Project, Workflow, WorkflowsResponse, WorkflowGroup } from '@/lib/types'
import { apiListProjects, apiRegisterProject, apiUnregisterProject, apiListWorkflows } from '@/lib/api'

interface SidebarProps {
  activeProjectId: string | null
  activeWorkflow: Workflow | null
  projectId: string | null
  selectedForDiff: Set<string>
  onSelectProject: (id: string) => void
  onSelectWorkflow: (wf: Workflow) => void
  onWorkflowsLoaded?: (wfs: Workflow[]) => void
  onToggleDiffSelection: (wf: Workflow) => void
  onRequestDiff: () => void
  onClearDiffSelection: () => void
}

// FR-5.1 — stable identity for a workflow row across diff-selection state.
export function workflowKey(w: Workflow): string {
  return `${w.source}-${w.plugin || 'local'}-${w.name}`
}

// FR-3 — pure filter helper; testable in isolation.
function applyFilter(wfs: Workflow[], query: string, activeTypes: Set<string>): Workflow[] {
  const q = query.trim().toLowerCase()
  return wfs.filter(w => {
    if (q && !w.name.toLowerCase().includes(q)) return false
    if (activeTypes.size > 0) {
      const wfTypes = new Set<string>()
      for (const s of w.steps) {
        const t = (s as { type?: string }).type
        if (t) wfTypes.add(t)
      }
      // FR-3.2 — chip filters compose as AND (workflow must contain *every* active type).
      for (const t of activeTypes) {
        if (!wfTypes.has(t)) return false
      }
    }
    return true
  })
}

// FR-3.2 — dedupe step types across all discovered workflows for the chip strip.
function collectStepTypes(wfs: Workflow[]): string[] {
  const set = new Set<string>()
  for (const w of wfs) {
    for (const s of w.steps) {
      const t = (s as { type?: string }).type
      if (t) set.add(t)
    }
  }
  return Array.from(set).sort()
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
  selectedForDiff,
  onSelectProject,
  onSelectWorkflow,
  onWorkflowsLoaded,
  onToggleDiffSelection,
  onRequestDiff,
  onClearDiffSelection,
}: SidebarProps) {
  const [projects, setProjects] = useState<Project[]>([])
  const [workflows, setWorkflows] = useState<WorkflowsResponse>({ local: [], plugin: [] })
  const [groups, setGroups] = useState<WorkflowGroup[]>([])
  const [expandedGroups, setExpandedGroups] = useState<Set<string>>(new Set())
  const [newPath, setNewPath] = useState('')
  const [loading, setLoading] = useState(false)

  // FR-3.1 — search input value.
  const [searchQuery, setSearchQuery] = useState('')
  // FR-3.2 — chip-strip active step-type filter set.
  const [activeTypes, setActiveTypes] = useState<Set<string>>(new Set())

  // FR-3 (implementation note) — restore filter state from URL query params on mount,
  // then keep URL in sync as state changes. Shareable links (?q=team&types=branch,loop).
  useEffect(() => {
    if (typeof window === 'undefined') return
    const params = new URLSearchParams(window.location.search)
    const q = params.get('q')
    const types = params.get('types')
    if (q) setSearchQuery(q)
    if (types) setActiveTypes(new Set(types.split(',').filter(Boolean)))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    if (typeof window === 'undefined') return
    const params = new URLSearchParams(window.location.search)
    if (searchQuery) params.set('q', searchQuery)
    else params.delete('q')
    if (activeTypes.size > 0) params.set('types', Array.from(activeTypes).sort().join(','))
    else params.delete('types')
    const qs = params.toString()
    window.history.replaceState(null, '', qs ? `?${qs}` : window.location.pathname)
  }, [searchQuery, activeTypes])

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
    if (!activeProjectId) {
      setWorkflows({ local: [], plugin: [] })
      setGroups([])
      onWorkflowsLoaded?.([])
      return
    }
    apiListWorkflows(activeProjectId)
      .then(w => {
        setWorkflows(w)
        const g = groupWorkflows(w)
        setGroups(g)
        // Expand all groups by default
        setExpandedGroups(new Set(g.map(x => x.name)))
        onWorkflowsLoaded?.([...w.local, ...w.plugin])
      })
      .catch(console.error)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeProjectId])

  // FR-3.2 — derive chip palette from currently loaded workflows.
  const allStepTypes = useMemo(
    () => collectStepTypes([...workflows.local, ...workflows.plugin]),
    [workflows],
  )

  // FR-3.3, FR-3.4 — per-group filtered view + post-filter counts.
  const filteredView = useMemo(() => {
    return groups.map(g => {
      const filtered = applyFilter(g.workflows, searchQuery, activeTypes)
      return { name: g.name, total: g.workflows.length, workflows: filtered }
    })
  }, [groups, searchQuery, activeTypes])

  const filterIsActive = searchQuery.trim().length > 0 || activeTypes.size > 0
  const totalVisible = filteredView.reduce((acc, g) => acc + g.workflows.length, 0)

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

  // FR-3.2 — toggle a chip's active state.
  const toggleType = (t: string) => {
    setActiveTypes(prev => {
      const next = new Set(prev)
      if (next.has(t)) next.delete(t)
      else next.add(t)
      return next
    })
  }

  // FR-3.3 — clear-all wipes search + chips.
  const clearAllFilters = () => {
    setSearchQuery('')
    setActiveTypes(new Set())
  }

  const isActiveWorkflow = (wf: Workflow) =>
    activeWorkflow?.name === wf.name && activeWorkflow?.source === wf.source && activeWorkflow?.plugin === wf.plugin

  // FR-5.1 — shift-click toggles a workflow's diff selection; plain click selects.
  const handleWorkflowClick = (e: React.MouseEvent, wf: Workflow) => {
    if (e.shiftKey) {
      e.preventDefault()
      onToggleDiffSelection(wf)
      return
    }
    onSelectWorkflow(wf)
  }

  const diffSelectionCount = selectedForDiff.size

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
        <>
          {/* FR-3.1 — search input above workflow list. Real-time substring filter (case-insensitive). */}
          <div className="sidebar-filter">
            <input
              type="search"
              className="workflow-search"
              placeholder="Search workflows…"
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
              aria-label="Search workflows by name"
            />
            {/* FR-3.2 — step-type chip strip below search. */}
            {allStepTypes.length > 0 && (
              <div className="step-type-chips" role="group" aria-label="Filter by step type">
                {allStepTypes.map(t => {
                  const active = activeTypes.has(t)
                  return (
                    <button
                      key={t}
                      className={`step-type-chip ${active ? 'active' : ''}`}
                      onClick={() => toggleType(t)}
                      type="button"
                      aria-pressed={active}
                      title={`Filter to workflows containing a ${t} step`}
                    >
                      {t}
                    </button>
                  )
                })}
              </div>
            )}
            {/* FR-3.3 — clear-all button surfaces only when ≥1 filter is active. */}
            {filterIsActive && (
              <button
                className="clear-filters"
                type="button"
                onClick={clearAllFilters}
                title="Clear search + step-type filters"
              >
                Clear filters
              </button>
            )}
          </div>

          {/* FR-5.1 — diff affordance: visible when exactly two workflows selected. */}
          {diffSelectionCount > 0 && (
            <div className="diff-affordance">
              <span className="diff-count">
                {diffSelectionCount} selected for diff
              </span>
              <div className="diff-actions">
                <button
                  type="button"
                  className="diff-btn"
                  onClick={onRequestDiff}
                  disabled={diffSelectionCount !== 2}
                  title={
                    diffSelectionCount === 2
                      ? 'Open side-by-side diff'
                      : 'Select exactly two workflows (shift-click)'
                  }
                >
                  Diff
                </button>
                <button
                  type="button"
                  className="diff-btn diff-btn-clear"
                  onClick={onClearDiffSelection}
                  title="Clear diff selection"
                >
                  Cancel
                </button>
              </div>
            </div>
          )}

          <div className="workflow-list">
            {filteredView.map(group => {
              const isExpanded = expandedGroups.has(group.name)
              const isLocal = group.name === 'Local'
              const showCount =
                filterIsActive && group.workflows.length !== group.total
                  ? `${group.workflows.length} of ${group.total}`
                  : `${group.total}`
              // FR-3.4 — hide groups that have zero post-filter visible workflows when filtering.
              if (filterIsActive && group.workflows.length === 0) return null
              return (
                <div key={group.name} className="workflow-group">
                  <div
                    className="workflow-group-header"
                    onClick={() => toggleGroup(group.name)}
                  >
                    <span className="group-toggle">{isExpanded ? '▼' : '▶'}</span>
                    <span className={`group-name ${isLocal ? 'local' : 'plugin'}`}>{group.name}</span>
                    <span className="count">{showCount}</span>
                  </div>
                  {isExpanded && group.workflows.map(w => {
                    const key = workflowKey(w)
                    const inDiff = selectedForDiff.has(key)
                    // FR-6.3 — surface (source) suffix when discoveryMode === 'source'.
                    const isSource = w.discoveryMode === 'source'
                    return (
                      <div
                        key={key}
                        className={`workflow-item ${isActiveWorkflow(w) ? 'active' : ''} ${inDiff ? 'diff-selected' : ''}`}
                        onClick={e => handleWorkflowClick(e, w)}
                        title={inDiff ? 'Selected for diff (shift-click to toggle)' : 'Click to view; shift-click to add to diff'}
                      >
                        <span className={`type-badge ${w.source} ${isSource ? 'source' : ''}`}>
                          {w.source === 'local' ? 'L' : (w.plugin?.slice(0, 2).toUpperCase() || '?')}
                        </span>
                        <span className="name">
                          {w.name}
                          {isSource && <span className="source-tag" title="Discovered from source checkout (plugin-*/)">(source)</span>}
                        </span>
                        <span className="step-count">{w.stepCount}</span>
                      </div>
                    )
                  })}
                </div>
              )
            })}
            {/* Empty result hint when filters narrow to zero. */}
            {filterIsActive && totalVisible === 0 && (
              <div className="filter-empty">
                <p>No workflows match the current filter.</p>
                <button type="button" className="clear-filters-inline" onClick={clearAllFilters}>
                  Clear filters
                </button>
              </div>
            )}
          </div>
        </>
      )}
    </div>
  )
}
