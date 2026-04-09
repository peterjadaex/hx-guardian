import { useEffect, useState } from 'react'
import { RefreshCw, Download, CheckCircle, XCircle, ChevronDown, ChevronRight } from 'lucide-react'
import { Layout, PageHeader, Card, LoadingSpinner, ErrorMessage } from '../components/Layout'
import { getMdmProfiles, refreshMdmProfiles } from '../lib/api'

export function MdmProfiles() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [data, setData] = useState<any>(null)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())

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

  if (loading) return <Layout><LoadingSpinner /></Layout>

  const profiles = data?.profiles || []
  const installedCount = profiles.filter((p: any) => p.is_installed).length

  return (
    <Layout>
      <PageHeader title="MDM Profiles" subtitle={`${profiles.length} profiles — ${installedCount} installed`}>
        <button onClick={handleRefresh}
          className="flex items-center gap-2 px-3 py-2 bg-blue-600/20 border border-blue-700/50 text-blue-400 text-sm rounded-lg transition-colors hover:bg-blue-600/30">
          <RefreshCw className="w-4 h-4" />
          Check Installed
        </button>
      </PageHeader>

      {error && <ErrorMessage message={error} />}

      <div className="mx-6 mb-4 p-4 bg-blue-900/20 border border-blue-700/30 rounded-lg">
        <p className="text-blue-300 text-sm">
          <strong>52 rules require MDM profiles</strong> — they cannot be enforced via shell scripts.
          Download the profiles below and install them via Apple Configurator or your MDM solution.
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
                <th className="text-left text-slate-400 font-medium px-4 py-3">Installed</th>
                <th className="text-left text-slate-400 font-medium px-4 py-3">Actions</th>
              </tr>
            </thead>
            <tbody>
              {profiles.map((p: any) => (
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
                      {p.is_installed === null ? (
                        <span className="text-slate-500 text-xs">Not checked</span>
                      ) : p.is_installed ? (
                        <span className="flex items-center gap-1 text-green-400 text-xs"><CheckCircle className="w-3.5 h-3.5" />Installed</span>
                      ) : (
                        <span className="flex items-center gap-1 text-red-400 text-xs"><XCircle className="w-3.5 h-3.5" />Not Installed</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <a
                        href={`/api/device/profiles/${encodeURIComponent(p.profile_id)}/download`}
                        download
                        className="flex items-center gap-1.5 text-xs px-2.5 py-1 bg-slate-700/40 hover:bg-slate-700/60 text-slate-300 rounded-lg transition-colors"
                      >
                        <Download className="w-3 h-3" />
                        Download
                      </a>
                    </td>
                  </tr>
                  {expanded.has(p.profile_id) && p.rules?.length > 0 && (
                    <tr key={`${p.profile_id}-rules`} className="border-b border-[#1e2d4a]/50 bg-[#080d1a]">
                      <td></td>
                      <td colSpan={5} className="px-4 py-3">
                        <div className="text-slate-500 text-xs mb-2">Rules covered by this profile:</div>
                        <div className="flex flex-wrap gap-1.5">
                          {p.rules.map((r: string) => (
                            <span key={r} className="text-xs font-mono px-2 py-0.5 bg-[#0f1629] border border-[#1e2d4a] text-slate-400 rounded">{r}</span>
                          ))}
                        </div>
                      </td>
                    </tr>
                  )}
                </>
              ))}
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
