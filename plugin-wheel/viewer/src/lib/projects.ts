import { v4 as uuidv4 } from 'uuid'
import type { Project } from './types'

// Use globalThis to persist across Next.js serverless invocations
const globalStore = globalThis as typeof globalThis & { __wheelViewProjects?: Map<string, Project> }
if (!globalStore.__wheelViewProjects) {
  globalStore.__wheelViewProjects = new Map()
}
const projects = globalStore.__wheelViewProjects

export function listProjects(): Project[] {
  return Array.from(projects.values())
}

export function registerProject(repoPath: string): Project {
  const normalized = repoPath.replace(/\/$/, '')

  for (const p of projects.values()) {
    if (p.path === normalized) return p
  }

  const project: Project = {
    id: uuidv4(),
    path: normalized,
    addedAt: new Date().toISOString(),
  }
  projects.set(project.id, project)
  return project
}

export function unregisterProject(id: string): boolean {
  return projects.delete(id)
}

export function getProject(id: string): Project | undefined {
  return projects.get(id)
}

export function firstProject(): Project | undefined {
  const values = Array.from(projects.values())
  return values[0]
}
