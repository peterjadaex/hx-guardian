import { useEffect, useState, useCallback } from 'react'
import { RefreshCw, Download, CheckCircle, XCircle, ChevronDown, ChevronRight, Shield, Loader2, AlertTriangle, PlayCircle } from 'lucide-react'
import { Layout, PageHeader, Card, LoadingSpinner, ErrorMessage } from '../components/Layout'
import { getMdmProfiles, refreshMdmProfiles, installMdmProfile } from '../lib/api'
import { useSSE } from '../lib/sse'

interface InstallResult {
  status: string
  message: string
}

interface BatchProgress {
  progress: number
  total: number
  current: string
  installed: number
  failed: number
}

export function MdmProfiles() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [data, setData] = useState<any>(null)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const [installing, setInstalling] = useState<Set<string>>(new Set())
  const [installResults, setInstallResults] = useState<Map<string, InstallResult>>(new Map())
  const [batchInstalling, setBatchInstalling] = useState(false)
  const [batchProgress, setBatchProgress] = useState<BatchProgress | null>(null)
  const [batchStreamPath, setBatchStreamPath] = useState<string | null>(null)

  useEffect(() => { load() }, [])

  const load = async () => {
    setLoading(true)
    try { setData(await getMdmProfiles()) }
    catch (e: any) { setError(e.message) }
    finally { setLoading(false) }
  }

  const handleRefresh = async () => {
    try {
      await refreshMdmProfiles()
      await load()
    } catch (e: any) {
      setError(e.message)
    }
  }

  const toggleExpand = (id: string) => {
    setExpanded(prev => {
      const next = new Set(prev)
      next.has(id) ? next.delete(id) : next.add(id)
      return next
    })
  }

  const handleInstall = async (profileId: string) => {
    setInstalling(prev => new Set(prev).add(profileId))
    setInstallResults(prev => { const m = new Map(prev); m.delete(profileId); return m })
    try {
      const result = await installMdmProfile(profileId)
      setInstallResults(prev => new Map(prev).set(profileId, {
        status: result.status,
        message: result.message,
      }))
      if (result.status === 'INSTALLED') {
        await load()
      }
    } catch (e: any) {
      setInstallResults(prev => new Map(prev).set(profileId, {
        status: 'ERROR',
        message: e.response?.data?.detail || e.message,
      }))
    } finally {
      setInstalling(prev => { const s = new Set(prev); s.delete(profileId); return s })
    }
  }

  const handleBatchInstall = (standard?: string) => {
    setBatchInstalling(true)
    setBatchProgress({ progress: 0, total: 0, current: '', installed: 0, failed: 0 })
    setInstallResults(new Map())
    const params = standard ? `?standard=${encodeURIComponent(standard)}` : ''
    setBatchStreamPath(`/api/device/profiles/install-all/stream${params}`)
  }

  const onSSEMessage = useCallback((eventType: string, data: any) => {
    if (eventType === 'profile_install') {
      setBatchProgress(prev => ({
        progress: data.progress || (prev?.progress || 0) + 1,
        total: data.total || prev?.total || 0,
        current: data.display_name || '',
        installed: (prev?.installed || 0) + (data.status === 'INSTALLED' ? 1 : 0),
        failed: (prev?.failed || 0) + (data.status !== 'INSTALLED' ? 1 : 0),
      }))
      setInstallResults(prev => new Map(prev).set(data.profile_id, {
        status: data.status,
        message: data.message,
      }))
    }
    if (eventType === 'complete') {
      setBatchInstalling(false)
      setBatchStreamPath(null)
      load()
    }
    if (eventType === 'error') {
      setBatchInstalling(false)
      setBatchStreamPath(null)
      setError(data.message || 'Batch install failed')
    }
  }, [])

  useSSE(batchStreamPath, onSSEMessage)

  if (loading) return <Layout><LoadingSpinner /></Layout>

  const profiles = data?.profiles || []
  const installedCount = profiles.filter((p: any) => p.is_installed).length
  const notInstalledCount = profiles.length - installedCount

  // Group counts by standard
  const standardCounts: Record<string, { total: number; notInstalled: number }> = {}
  for (const p of profiles) {
    if (!standardCounts[p.standard]) standardCounts[p.standard] = { total: 0, notInstalled: 0 }
    standardCounts[p.standard].total++
    if (!p.is_installed) standardCounts[p.standard].notInstalled++
  }

  return (
    <Layout>
      <PageHeader title="MDM Profiles" subtitle={`${profiles.length} profiles — ${installedCount} installed`}>
        <div className="flex items-center gap-2">
          {notInstalledCount > 0 && !batchInstalling && (
            <button onClick={() => handleBatchInstall()}
              className="flex items-center gap-2 px-3 py-2 bg-green-600/20 border border-green-700/50 text-green-400 text-sm rounded-lg transition-colors hover:bg-green-600/30">
              <PlayCircle className="w-4 h-4" />
              Install All ({notInstalledCount})
            </button>
          )}
          <button onClick={handleRefresh} disabled={batchInstalling}
            className="flex items-center gap-2 px-3 py-2 bg-blue-600/20 border border-blue-700/50 text-blue-400 text-sm rounded-lg transition-colors hover:bg-blue-600/30 disabled:opacity-50">
            <RefreshCw className="w-4 h-4" />
            Check Installed
          </button>
        </div>
      </PageHeader>

      {error && <ErrorMessage message={error} />}

      {/* Batch install progress banner */}
      {batchInstalling && batchProgress && (
        <div className="mx-6 mb-4 p-4 bg-green-900/20 border border-green-700/30 rounded-lg">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-2 text-green-300 text-sm">
              <Loader2 className="w-4 h-4 animate-spin" />
              Installing profiles... {batchProgress.progress}/{batchProgress.total}
            </div>
            <div className="text-xs text-slate-400">
              <span className="text-green-400">{batchProgress.installed} installed</span>
              {batchProgress.failed > 0 && (
                <span className="text-red-400 ml-2">{batchProgress.failed} failed</span>
              )}
            </div>
          </div>
          <div className="w-full bg-slate-700/50 rounded-full h-1.5">
            <div className="bg-green-500 h-1.5 rounded-full transition-all duration-300"
              style={{ width: `${batchProgress.total > 0 ? (batchProgress.progress / batchProgress.total) * 100 : 0}%` }} />
          </div>
          {batchProgress.current && (
            <div className="text-xs text-slate-500 mt-1.5">{batchProgress.current}</div>
          )}
        </div>
      )}

      {/* Install per-standard buttons */}
      {!batchInstalling && Object.keys(standardCounts).length > 1 && (
        <div className="mx-6 mb-4 flex gap-2 flex-wrap">
          {Object.entries(standardCounts).map(([std, counts]) => (
            counts.notInstalled > 0 && (
              <button key={std} onClick={() => handleBatchInstall(std)}
                className={`flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg border transition-colors ${
                  std === '800-53r5_high' ? 'bg-purple-900/20 border-purple-700/40 text-purple-400 hover:bg-purple-900/30' :
                  std === 'cisv8' ? 'bg-blue-900/20 border-blue-700/40 text-blue-400 hover:bg-blue-900/30' :
                  'bg-teal-900/20 border-teal-700/40 text-teal-400 hover:bg-teal-900/30'
                }`}>
                <Shield className="w-3 h-3" />
                Install {std} ({counts.notInstalled})
              </button>
            )
          ))}
        </div>
      )}

      <div className="mx-6 mb-4 p-4 bg-blue-900/20 border border-blue-700/30 rounded-lg">
        <p className="text-blue-300 text-sm">
          <strong>52 rules require MDM profiles</strong> — they cannot be enforced via shell scripts.
          Install profiles directly from this page, or download them for manual installation via Apple Configurator.
        </p>
      </div>

      <div className="px-6 pb-6">
        <Card className="overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-[#1e2d4a]">
                <th className="text-left text-slate-400 font-medium px-4 py-3 w-8"></th>
                <th className="text-left text-slate-400 font-medium px-4 py-3">Profile</th>
                <th className="text-left text-slate-400 font-medium px-4 py-3">Standard</th>
                <th className="text-left text-slate-400 font-medium px-4 py-3">Rules</th>
                <th className="text-left text-slate-400 font-medium px-4 py-3">Status</th>
                <th className="text-left text-slate-400 font-medium px-4 py-3">Actions</th>
              </tr>
            </thead>
            <tbody>
              {profiles.map((p: any) => {
                const result = installResults.get(p.profile_id)
                return (
                  <>
                    <tr key={p.profile_id} className="border-b border-[#1e2d4a]/50 hover:bg-white/[0.02]">
                      <td className="px-4 py-3">
                        <button onClick={() => toggleExpand(p.profile_id)} className="text-slate-500 hover:text-white">
                          {expanded.has(p.profile_id) ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
                        </button>
                      </td>
                      <td className="px-4 py-3">
                        <div className="text-white font-medium text-xs">{p.display_name}</div>
                        <div className="text-slate-500 text-xs font-mono mt-0.5">{p.profile_id}</div>
                      </td>
                      <td className="px-4 py-3">
                        <span className={`text-xs px-2 py-0.5 rounded ${
                          p.standard === '800-53r5_high' ? 'bg-purple-900/30 text-purple-400' :
                          p.standard === 'cisv8' ? 'bg-blue-900/30 text-blue-400' :
                          'bg-teal-900/30 text-teal-400'
                        }`}>{p.standard}</span>
                      </td>
                      <td className="px-4 py-3">
                        <span className="text-slate-400 text-xs">{p.rules?.length || 0} rules</span>
                      </td>
                      <td className="px-4 py-3">
                        {installing.has(p.profile_id) ? (
                          <span className="flex items-center gap-1 text-blue-400 text-xs"><Loader2 className="w-3.5 h-3.5 animate-spin" />Installing...</span>
                        ) : result?.status === 'INSTALLED' || p.is_installed ? (
                          <span className="flex items-center gap-1 text-green-400 text-xs"><CheckCircle className="w-3.5 h-3.5" />Installed</span>
                        ) : result?.status === 'USER_APPROVAL_REQUIRED' ? (
                          <span className="flex items-center gap-1 text-yellow-400 text-xs" title="Open System Settings > Privacy & Security > Profiles to approve">
                            <AlertTriangle className="w-3.5 h-3.5" />Needs Approval
                          </span>
                        ) : result?.status === 'ERROR' ? (
                          <span className="flex items-center gap-1 text-red-400 text-xs" title={result.message}>
                            <XCircle className="w-3.5 h-3.5" />Failed
                          </span>
                        ) : p.is_installed === null ? (
                          <span className="text-slate-500 text-xs">Not checked</span>
                        ) : (
                          <span className="flex items-center gap-1 text-red-400 text-xs"><XCircle className="w-3.5 h-3.5" />Not Installed</span>
                        )}
                      </td>
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-1.5">
                          {!p.is_installed && !installing.has(p.profile_id) && result?.status !== 'INSTALLED' && (
                            <button
                              onClick={() => handleInstall(p.profile_id)}
                              disabled={batchInstalling}
                              className="flex items-center gap-1.5 text-xs px-2.5 py-1 bg-green-700/30 hover:bg-green-700/50 text-green-300 rounded-lg transition-colors disabled:opacity-50"
                            >
                              <Shield className="w-3 h-3" />
                              Install
                            </button>
                          )}
                          <a
                            href={`/api/device/profiles/${encodeURIComponent(p.profile_id)}/download`}
                            download
                            className="flex items-center gap-1.5 text-xs px-2.5 py-1 bg-slate-700/40 hover:bg-slate-700/60 text-slate-300 rounded-lg transition-colors"
                          >
                            <Download className="w-3 h-3" />
                            Download
                          </a>
                        </div>
                      </td>
                    </tr>
                    {expanded.has(p.profile_id) && (
                      <tr key={`${p.profile_id}-details`} className="border-b border-[#1e2d4a]/50 bg-[#080d1a]">
                        <td></td>
                        <td colSpan={5} className="px-4 py-3">
                          {result?.message && result.status !== 'INSTALLED' && (
                            <div className={`text-xs mb-2 px-2 py-1 rounded ${
                              result.status === 'USER_APPROVAL_REQUIRED' ? 'bg-yellow-900/20 text-yellow-400' : 'bg-red-900/20 text-red-400'
                            }`}>
                              {result.message}
                              {result.status === 'USER_APPROVAL_REQUIRED' && (
                                <span className="block mt-1 text-yellow-500/70">Open System Settings &gt; Privacy &amp; Security &gt; Profiles to approve this profile.</span>
                              )}
                            </div>
                          )}
                          {p.rules?.length > 0 && (
                            <>
                              <div className="text-slate-500 text-xs mb-2">Rules covered by this profile:</div>
                              <div className="flex flex-wrap gap-1.5">
                                {p.rules.map((r: string) => (
                                  <span key={r} className="text-xs font-mono px-2 py-0.5 bg-[#0f1629] border border-[#1e2d4a] text-slate-400 rounded">{r}</span>
                                ))}
                              </div>
                            </>
                          )}
                          {(!p.rules || p.rules.length === 0) && !result?.message && (
                            <div className="text-slate-500 text-xs">No rules mapped to this profile.</div>
                          )}
                        </td>
                      </tr>
                    )}
                  </>
                )
              })}
              {profiles.length === 0 && (
                <tr><td colSpan={6} className="px-4 py-12 text-center text-slate-500">No profiles found</td></tr>
              )}
            </tbody>
          </table>
        </Card>
      </div>
    </Layout>
  )
}
