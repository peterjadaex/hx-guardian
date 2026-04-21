import { useEffect, useRef, useState } from 'react'
import { Plus, Trash2, AlertTriangle, Lock } from 'lucide-react'
import { Layout, PageHeader, Card, LoadingSpinner, ErrorMessage } from '../components/Layout'
import { getExemptions, grantExemption, revokeExemption, getRules, get2faStatus, verify2fa } from '../lib/api'

// ─── Inline OTP prompt ───────────────────────────────────────────────────────

function OtpPrompt({
  onVerified,
  onCancel,
}: {
  onVerified: (token: string) => void
  onCancel: () => void
}) {
  const [otp, setOtp] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => { inputRef.current?.focus() }, [])

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const v = e.target.value.replace(/\D/g, '').slice(0, 6)
    setOtp(v)
    if (v.length === 6) setTimeout(() => submit(v), 50)
  }

  const submit = async (code: string) => {
    setLoading(true)
    setError('')
    try {
      const res = await verify2fa(code)
      if (res.valid && res.session_token) {
        onVerified(res.session_token)
      } else {
        setError('Invalid code — try again')
        setOtp('')
        inputRef.current?.focus()
      }
    } catch {
      setError('Verification failed')
      setOtp('')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="mx-6 mb-4 p-4 bg-blue-950/30 border border-blue-700/40 rounded-lg flex items-start gap-3">
      <Lock className="w-4 h-4 text-blue-400 flex-shrink-0 mt-2.5" />
      <div className="flex-1 space-y-3">
        <div>
          <p className="text-blue-300 text-sm font-medium">2FA verification required</p>
          <p className="text-slate-400 text-xs mt-0.5">Enter the 6-digit code from your authenticator app</p>
        </div>
        <div className="flex items-center gap-3">
          <input
            ref={inputRef}
            type="text"
            inputMode="numeric"
            maxLength={6}
            value={otp}
            onChange={handleChange}
            disabled={loading}
            placeholder="000000"
            className="w-28 bg-[#0a0e1a] border border-[#1e2d4a] rounded-lg px-3 py-2 text-white text-center text-lg font-mono tracking-widest focus:outline-none focus:border-blue-500 disabled:opacity-50"
          />
          <button
            onClick={() => submit(otp)}
            disabled={otp.length !== 6 || loading}
            className="px-3 py-2 bg-blue-600/30 border border-blue-500/40 text-blue-300 text-sm rounded-lg hover:bg-blue-600/40 transition-colors disabled:opacity-40"
          >
            {loading ? 'Verifying...' : 'Verify'}
          </button>
          <button
            onClick={onCancel}
            className="px-3 py-2 text-slate-500 hover:text-slate-300 text-sm transition-colors"
          >
            Cancel
          </button>
        </div>
        {error && <p className="text-red-400 text-xs">{error}</p>}
      </div>
    </div>
  )
}

// ─── Main page ───────────────────────────────────────────────────────────────

export function Exemptions() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [exemptions, setExemptions] = useState<any[]>([])
  const [showForm, setShowForm] = useState(false)
  const [ruleSearch, setRuleSearch] = useState('')
  const [reason, setReason] = useState('')
  const [expiresAt, setExpiresAt] = useState('')
  const [ruleOptions, setRuleOptions] = useState<any[]>([])

  // 2FA state
  const [twoFaEnabled, setTwoFaEnabled] = useState(false)
  const [twoFaToken, setTwoFaToken] = useState('')
  const [showOtpPrompt, setShowOtpPrompt] = useState(false)
  const [pendingAction, setPendingAction] = useState<((token: string) => Promise<void>) | null>(null)

  useEffect(() => {
    load()
    getRules().then(d => setRuleOptions(d.rules || [])).catch(() => {})
    get2faStatus()
      .then(d => setTwoFaEnabled(d.enabled))
      .catch(() => {})
  }, [])

  const load = async () => {
    setLoading(true)
    try { setExemptions((await getExemptions()).exemptions || []) }
    catch (e: any) { setError(e.message) }
    finally { setLoading(false) }
  }

  const require2fa = (action: (token: string) => Promise<void>) => {
    if (!twoFaEnabled || twoFaToken) {
      action(twoFaToken)
      return
    }
    setPendingAction(() => action)
    setShowOtpPrompt(true)
  }

  const handleOtpVerified = (token: string) => {
    setTwoFaToken(token)
    setShowOtpPrompt(false)
    if (pendingAction) {
      pendingAction(token)
      setPendingAction(null)
    }
  }

  const handleOtpCancel = () => {
    setShowOtpPrompt(false)
    setPendingAction(null)
  }

  const handleGrant = () => {
    if (!ruleSearch || !reason) return
    require2fa(async (token) => {
      try {
        await grantExemption(
          { rule: ruleSearch, reason, expires_at: expiresAt || undefined },
          token || undefined,
        )
        setShowForm(false)
        setRuleSearch('')
        setReason('')
        setExpiresAt('')
        await load()
      } catch (e: any) { setError(e.message) }
    })
  }

  const handleRevoke = (rule: string) => {
    if (!confirm(`Revoke exemption for ${rule}?`)) return
    require2fa(async (token) => {
      try {
        await revokeExemption(rule, token || undefined)
        await load()
      } catch (e: any) { setError(e.message) }
    })
  }

  if (loading) return <Layout><LoadingSpinner /></Layout>
  const now = new Date()

  return (
    <Layout>
      <PageHeader title="Exemptions" subtitle={`${exemptions.filter(e => e.is_active).length} active exemptions`}>
        <button onClick={() => setShowForm(true)}
          className="flex items-center gap-2 px-4 py-2 bg-yellow-600/20 border border-yellow-700/50 text-yellow-400 text-sm rounded-lg transition-colors hover:bg-yellow-600/30">
          <Plus className="w-4 h-4" />
          Grant Exemption
        </button>
      </PageHeader>

      {error && <ErrorMessage message={error} />}

      {/* 2FA OTP prompt */}
      {showOtpPrompt && (
        <OtpPrompt onVerified={handleOtpVerified} onCancel={handleOtpCancel} />
      )}

      {showForm && (
        <div className="mx-6 mb-4">
          <Card className="p-5">
            <div className="text-slate-300 font-medium mb-4">Grant New Exemption</div>
            <div className="space-y-3">
              <div>
                <label className="text-slate-400 text-xs mb-1 block">Rule *</label>
                <input
                  list="rule-options"
                  value={ruleSearch}
                  onChange={e => setRuleSearch(e.target.value)}
                  placeholder="Type rule name..."
                  className="w-full bg-[#0a0e1a] border border-[#1e2d4a] rounded-lg px-3 py-2 text-sm text-white placeholder-slate-600 focus:outline-none focus:border-blue-500 font-mono"
                />
                <datalist id="rule-options">
                  {ruleOptions.slice(0, 50).map((r: any) => <option key={r.rule} value={r.rule} />)}
                </datalist>
              </div>
              <div>
                <label className="text-slate-400 text-xs mb-1 block">Reason *</label>
                <textarea value={reason} onChange={e => setReason(e.target.value)}
                  placeholder="Business justification for exemption..."
                  rows={3}
                  className="w-full bg-[#0a0e1a] border border-[#1e2d4a] rounded-lg px-3 py-2 text-sm text-white placeholder-slate-600 focus:outline-none focus:border-blue-500 resize-none"
                />
              </div>
              <div>
                <label className="text-slate-400 text-xs mb-1 block">Expiry Date (optional)</label>
                <input type="date" value={expiresAt} onChange={e => setExpiresAt(e.target.value)}
                  className="bg-[#0a0e1a] border border-[#1e2d4a] rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-blue-500" />
              </div>
              <div className="flex gap-2">
                <button onClick={handleGrant} disabled={!ruleSearch || !reason}
                  className="px-4 py-2 bg-yellow-600/20 hover:bg-yellow-600/30 border border-yellow-700/50 text-yellow-400 text-sm rounded-lg transition-colors disabled:opacity-50">
                  Grant Exemption
                </button>
                <button onClick={() => setShowForm(false)}
                  className="px-4 py-2 text-slate-400 hover:text-white text-sm transition-colors">
                  Cancel
                </button>
              </div>
            </div>
          </Card>
        </div>
      )}

      <div className="px-6 pb-6">
        <Card className="overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-[#1e2d4a]">
                <th className="text-left text-slate-400 font-medium px-4 py-3">Rule</th>
                <th className="text-left text-slate-400 font-medium px-4 py-3">Reason</th>
                <th className="text-left text-slate-400 font-medium px-4 py-3">Granted</th>
                <th className="text-left text-slate-400 font-medium px-4 py-3">Expires</th>
                <th className="text-left text-slate-400 font-medium px-4 py-3">Status</th>
                <th className="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody>
              {exemptions.map((e: any) => {
                const expired = e.expires_at && new Date(e.expires_at) < now
                return (
                  <tr key={e.id} className={`border-b border-[#1e2d4a]/50 hover:bg-white/[0.02] ${!e.is_active ? 'opacity-50' : ''}`}>
                    <td className="px-4 py-3 font-mono text-white text-xs">{e.rule}</td>
                    <td className="px-4 py-3 text-slate-400 max-w-xs truncate" title={e.reason}>{e.reason}</td>
                    <td className="px-4 py-3 text-slate-500 text-xs">{new Date(e.granted_at).toLocaleDateString()}</td>
                    <td className="px-4 py-3 text-xs">
                      {e.expires_at ? (
                        <span className={expired ? 'text-red-400' : 'text-slate-400'}>
                          {expired && <AlertTriangle className="w-3 h-3 inline mr-1" />}
                          {new Date(e.expires_at).toLocaleDateString()}
                        </span>
                      ) : <span className="text-slate-600">Permanent</span>}
                    </td>
                    <td className="px-4 py-3">
                      {!e.is_active ? (
                        <span className="text-xs text-slate-500">Revoked</span>
                      ) : expired ? (
                        <span className="text-xs text-red-400">Expired</span>
                      ) : (
                        <span className="text-xs text-green-400">Active</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      {e.is_active && !expired && (
                        <button onClick={() => handleRevoke(e.rule)}
                          className="text-slate-500 hover:text-red-400 transition-colors">
                          <Trash2 className="w-4 h-4" />
                        </button>
                      )}
                    </td>
                  </tr>
                )
              })}
              {exemptions.length === 0 && (
                <tr><td colSpan={6} className="px-4 py-12 text-center text-slate-500">No exemptions granted</td></tr>
              )}
            </tbody>
          </table>
        </Card>
      </div>
    </Layout>
  )
}
