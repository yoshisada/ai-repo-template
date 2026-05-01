const BASE = ''

export async function apiHealth(): Promise<{ status: string; version: string }> {
  const res = await fetch(`${BASE}/api/health`)
  if (!res.ok) throw new Error(`Health check failed: ${res.status}`)
  return res.json()
}

export async function apiListProjects(): Promise<import('./types').Project[]> {
  const res = await fetch(`${BASE}/api/projects`)
  if (!res.ok) throw new Error(`List projects failed: ${res.status}`)
  return res.json()
}

export async function apiRegisterProject(
  path: string,
): Promise<import('./types').Project> {
  const res = await fetch(`${BASE}/api/projects`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ path }),
  })
  if (!res.ok) throw new Error(`Register project failed: ${res.status}`)
  return res.json()
}

export async function apiUnregisterProject(id: string): Promise<void> {
  const res = await fetch(`${BASE}/api/projects/${id}`, { method: 'DELETE' })
  if (res.status !== 204) throw new Error(`Unregister project failed: ${res.status}`)
}

export async function apiListWorkflows(
  projectId?: string,
): Promise<import('./types').WorkflowsResponse> {
  const url = projectId
    ? `${BASE}/api/workflows?projectId=${encodeURIComponent(projectId)}`
    : `${BASE}/api/workflows`
  const res = await fetch(url)
  if (!res.ok) throw new Error(`List workflows failed: ${res.status}`)
  return res.json()
}

export async function apiGetWorkflow(
  name: string,
  projectId?: string,
): Promise<import('./types').Workflow | null> {
  const params = new URLSearchParams()
  params.set('name', name)
  if (projectId) params.set('projectId', projectId)
  const url = `${BASE}/api/workflows?${params.toString()}`
  const res = await fetch(url)
  if (res.status === 404) return null
  if (!res.ok) throw new Error(`Get workflow failed: ${res.status}`)
  return res.json()
}

export async function apiGetFeedbackLoops(
  projectId?: string,
): Promise<import('./types').FeedbackLoopsResponse> {
  const url = projectId
    ? `${BASE}/api/feedback-loops?projectId=${encodeURIComponent(projectId)}`
    : `${BASE}/api/feedback-loops`
  const res = await fetch(url)
  if (!res.ok) throw new Error(`Get feedback loops failed: ${res.status}`)
  return res.json()
}
