import axios from 'axios'

const TOKEN_KEY = 'hxg_token'

export function getToken(): string {
  return localStorage.getItem(TOKEN_KEY) || ''
}

export function setToken(token: string): void {
  localStorage.setItem(TOKEN_KEY, token)
}

export function clearToken(): void {
  localStorage.removeItem(TOKEN_KEY)
}

const api = axios.create({
  baseURL: '/api',
  timeout: 30000,
})

api.interceptors.request.use((config) => {
  const token = getToken()
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

api.interceptors.response.use(
  (res) => res,
  (err) => {
    if (err.response?.status === 401) {
      clearToken()
      window.location.href = '/login'
    }
    return Promise.reject(err)
  }
)

export default api

// ─── Rules ────────────────────────────────────────────────────────────────────

export const getRules = (params?: Record<string, string>) =>
  api.get('/rules', { params }).then(r => r.data)

export const getRuleMeta = () =>
  api.get('/rules/meta').then(r => r.data)

export const getRuleDetail = (rule: string) =>
  api.get(`/rules/${rule}`).then(r => r.data)

export const scanRule = (rule: string) =>
  api.post(`/rules/${rule}/scan`).then(r => r.data)

export const fixRule = (rule: string) =>
  api.post(`/rules/${rule}/fix`).then(r => r.data)

export const getFixHistory = (rule: string) =>
  api.get(`/rules/${rule}/fix-history`).then(r => r.data)

// ─── Scans ────────────────────────────────────────────────────────────────────

export const startScan = (filter?: object) =>
  api.post('/scans', { filter }).then(r => r.data)

export const getSession = (id: number) =>
  api.get(`/scans/${id}`).then(r => r.data)

export const getSessionResults = (id: number, params?: Record<string, unknown>) =>
  api.get(`/scans/${id}/results`, { params }).then(r => r.data)

// ─── History ──────────────────────────────────────────────────────────────────

export const getHistory = (params?: object) =>
  api.get('/history', { params }).then(r => r.data)

export const getTrends = (days = 30) =>
  api.get('/history/trends', { params: { days } }).then(r => r.data)

export const getCategoryBreakdown = (sessionId?: number) =>
  api.get('/history/categories', { params: sessionId ? { session_id: sessionId } : undefined }).then(r => r.data)

// ─── Exemptions ───────────────────────────────────────────────────────────────

export const getExemptions = () =>
  api.get('/exemptions').then(r => r.data)

export const grantExemption = (data: { rule: string; reason: string; expires_at?: string }) =>
  api.post('/exemptions', data).then(r => r.data)

export const revokeExemption = (rule: string) =>
  api.delete(`/exemptions/${rule}`).then(r => r.data)

// ─── Device ───────────────────────────────────────────────────────────────────

export const getDeviceStatus = () =>
  api.get('/device/status').then(r => r.data)

export const getConnections = () =>
  api.get('/device/connections').then(r => r.data)

export const getPreflight = () =>
  api.get('/preflight').then(r => r.data)

// ─── MDM ──────────────────────────────────────────────────────────────────────

export const getMdmProfiles = () =>
  api.get('/device/profiles').then(r => r.data)

export const refreshMdmProfiles = () =>
  api.get('/device/profiles/refresh').then(r => r.data)

// ─── Logs ─────────────────────────────────────────────────────────────────────

export const getSystemLog = (params?: object) =>
  api.get('/logs/system', { params }).then(r => r.data)

// ─── Schedule ─────────────────────────────────────────────────────────────────

export const getSchedules = () =>
  api.get('/schedule').then(r => r.data)

export const createSchedule = (data: object) =>
  api.post('/schedule', data).then(r => r.data)

export const updateSchedule = (id: number, data: object) =>
  api.put(`/schedule/${id}`, data).then(r => r.data)

export const deleteSchedule = (id: number) =>
  api.delete(`/schedule/${id}`).then(r => r.data)

export const runScheduleNow = (id: number) =>
  api.post(`/schedule/${id}/run`).then(r => r.data)

// ─── Reports ──────────────────────────────────────────────────────────────────

export const getReportHtml = (sessionId?: number) =>
  `/api/reports/html${sessionId ? `?session_id=${sessionId}` : ''}`

export const getReportCsv = (sessionId?: number) =>
  `/api/reports/csv${sessionId ? `?session_id=${sessionId}` : ''}`

// ─── Audit Log ────────────────────────────────────────────────────────────────

export const getAuditLog = (params?: object) =>
  api.get('/audit-log', { params }).then(r => r.data)

export const exportAuditCsv = () => '/api/audit-log/export/csv'

// ─── Health ───────────────────────────────────────────────────────────────────

export const getHealth = () =>
  api.get('/health').then(r => r.data)

export const verifyToken = (token: string) =>
  axios.get('/api/token/verify', {
    headers: { Authorization: `Bearer ${token}` }
  }).then(r => r.data)
