import axios from 'axios'

const api = axios.create({
  baseURL: '/api',
  timeout: 30000,
})

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

export const fixRule = (rule: string, twoFaToken?: string) =>
  api.post(`/rules/${rule}/fix`, null, {
    headers: twoFaToken ? { 'X-2FA-Token': twoFaToken } : undefined,
  }).then(r => r.data)

export const undoFix = (rule: string, twoFaToken?: string) =>
  api.post(`/rules/${rule}/undo-fix`, null, {
    headers: twoFaToken ? { 'X-2FA-Token': twoFaToken } : undefined,
  }).then(r => r.data)

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

export const grantExemption = (data: { rule: string; reason: string; expires_at?: string }, twoFaToken?: string) =>
  api.post('/exemptions', data, {
    headers: twoFaToken ? { 'X-2FA-Token': twoFaToken } : undefined,
  }).then(r => r.data)

export const revokeExemption = (rule: string, twoFaToken?: string) =>
  api.delete(`/exemptions/${rule}`, {
    headers: twoFaToken ? { 'X-2FA-Token': twoFaToken } : undefined,
  }).then(r => r.data)

// ─── Device ───────────────────────────────────────────────────────────────────

export const getDeviceStatus = () =>
  api.get('/device/status').then(r => r.data)

export const getConnections = () =>
  api.get('/device/connections').then(r => r.data)

export const getUsbWhitelist = () =>
  api.get('/device/usb-whitelist').then(r => r.data)

export const addUsbWhitelist = (
  data: { name: string; vendor?: string; product_id?: string; serial?: string; volume_uuid?: string; notes?: string },
  twoFaToken?: string,
) => api.post('/device/usb-whitelist', data, {
  headers: twoFaToken ? { 'X-2FA-Token': twoFaToken } : undefined,
}).then(r => r.data)

export const removeUsbWhitelist = (id: number, twoFaToken?: string) =>
  api.delete(`/device/usb-whitelist/${id}`, {
    headers: twoFaToken ? { 'X-2FA-Token': twoFaToken } : undefined,
  }).then(r => r.data)

export const getUsbSecurityEvents = (page = 0, limit = 10) =>
  api.get('/audit-log', { params: { action: 'USB_UNAUTHORIZED_DEVICE', limit, offset: page * limit } }).then(r => r.data)

export const getPreflight = () =>
  api.get('/preflight').then(r => r.data)

// ─── MDM ──────────────────────────────────────────────────────────────────────

export const getMdmProfiles = () =>
  api.get('/device/profiles').then(r => r.data)

export const refreshMdmProfiles = () =>
  api.get('/device/profiles/refresh').then(r => r.data)

export const installMdmProfile = (profileId: string) =>
  api.post(`/device/profiles/${encodeURIComponent(profileId)}/install`).then(r => r.data)

export const installAllMdmProfiles = (standard?: string) =>
  api.post('/device/profiles/install-all', standard ? { standard } : {}).then(r => r.data)

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

type ExportParams = { from?: string; to?: string; action?: string }

const buildExportUrl = (base: string, p?: ExportParams) => {
  const qs = new URLSearchParams()
  if (p?.from) qs.set('from', p.from)
  if (p?.to) qs.set('to', p.to)
  if (p?.action) qs.set('action', p.action)
  const s = qs.toString()
  return s ? `${base}?${s}` : base
}

export const exportAuditCsv = (p?: ExportParams) =>
  buildExportUrl('/api/audit-log/export/csv', p)

export const exportAuditJsonl = (p?: ExportParams) =>
  buildExportUrl('/api/audit-log/export/jsonl', p)

// ─── Shell Log ────────────────────────────────────────────────────────────────

export const getShellLog = (params?: object) =>
  api.get('/shell-log', { params }).then(r => r.data)

type ShellExportParams = {
  from?: string
  to?: string
  source?: string
  user?: string
  q?: string
}

export const exportShellJsonl = (p?: ShellExportParams) => {
  const qs = new URLSearchParams()
  if (p?.from) qs.set('from', p.from)
  if (p?.to) qs.set('to', p.to)
  if (p?.source) qs.set('source', p.source)
  if (p?.user) qs.set('user', p.user)
  if (p?.q) qs.set('q', p.q)
  const s = qs.toString()
  return s ? `/api/shell-log/export/jsonl?${s}` : '/api/shell-log/export/jsonl'
}

// ─── Biometric Log ────────────────────────────────────────────────────────────

export const getBiometricLog = (params?: object) =>
  api.get('/biometric-log', { params }).then(r => r.data)

type BiometricExportParams = {
  from?: string
  to?: string
  event_class?: string
  user?: string
  q?: string
  include_teardown?: boolean
}

export const exportBiometricJsonl = (p?: BiometricExportParams) => {
  const qs = new URLSearchParams()
  if (p?.from) qs.set('from', p.from)
  if (p?.to) qs.set('to', p.to)
  if (p?.event_class) qs.set('event_class', p.event_class)
  if (p?.user) qs.set('user', p.user)
  if (p?.q) qs.set('q', p.q)
  if (p?.include_teardown) qs.set('include_teardown', 'true')
  const s = qs.toString()
  return s ? `/api/biometric-log/export/jsonl?${s}` : '/api/biometric-log/export/jsonl'
}

// ─── Health ───────────────────────────────────────────────────────────────────

export const getHealth = () =>
  api.get('/health').then(r => r.data)

// ─── Settings / 2FA ───────────────────────────────────────────────────────────

export const get2faStatus = () =>
  api.get('/settings/2fa/status').then(r => r.data)

export const init2faSetup = (otp?: string) =>
  api.post('/settings/2fa/setup/init', { otp }).then(r => r.data)

export const confirm2faSetup = (otp: string) =>
  api.post('/settings/2fa/setup/confirm', { otp }).then(r => r.data)

export const view2faQr = (otp: string) =>
  api.post('/settings/2fa/view-qr', { otp }).then(r => r.data)

export const verify2fa = (otp: string) =>
  api.post('/settings/2fa/verify', { otp }).then(r => r.data)

export const disable2fa = (otp: string) =>
  api.post('/settings/2fa/disable', { otp }).then(r => r.data)
