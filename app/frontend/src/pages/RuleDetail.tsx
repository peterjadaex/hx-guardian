import { useEffect, useRef, useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { ArrowLeft, Play, Wrench, ShieldOff, RotateCcw, Lock } from 'lucide-react'
import { Layout, Card, LoadingSpinner, ErrorMessage } from '../components/Layout'
import { StatusBadge } from '../components/StatusBadge'
import { getRuleDetail, scanRule, fixRule, undoFix, getFixHistory, grantExemption, revokeExemption, get2faStatus, verify2fa } from '../lib/api'

// ─── Inline OTP prompt (same pattern as Connections page) ────────────────────

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
    <div className="mb-4 p-4 bg-blue-950/30 border border-blue-700/40 rounded-lg flex items-start gap-3">
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

export function RuleDetail() {
  const { ruleName } = useParams<{ ruleName: string }>()
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [rule, setRule] = useState<any>(null)
  const [fixHistory, setFixHistory] = useState<any[]>([])
  const [scanning, setScanning] = useState(false)
  const [fixing, setFixing] = useState(false)
  const [undoing, setUndoing] = useState(false)
  const [scanOutput, setScanOutput] = useState<string | null>(null)
  const [fixOutput, setFixOutput] = useState<string | null>(null)
  const [exemptReason, setExemptReason] = useState('')
  const [exemptExpiry, setExemptExpiry] = useState('')
  const [showExemptForm, setShowExemptForm] = useState(false)

  // 2FA state
  const [twoFaEnabled, setTwoFaEnabled] = useState(false)
  const [twoFaToken, setTwoFaToken] = useState('')
  const [showOtpPrompt, setShowOtpPrompt] = useState(false)
  const [pendingAction, setPendingAction] = useState<((token: string) => Promise<void>) | null>(null)

  useEffect(() => {
    if (!ruleName) return
    loadRule()
    get2faStatus()
      .then(d => setTwoFaEnabled(d.enabled))
      .catch(() => {})
  }, [ruleName])

  const loadRule = async () => {
    setLoading(true)
    try {
      const [ruleData, histData] = await Promise.allSettled([
        getRuleDetail(ruleName!),
        getFixHistory(ruleName!),
      ])
      if (ruleData.status === 'fulfilled') setRule(ruleData.value)
      if (histData.status === 'fulfilled') setFixHistory(histData.value.history || [])
    } catch (e: any) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  const require2fa = (action: (token: string) => Promise<void>) => {
    if (!twoFaEnabled || twoFaToken) {
      action(twoFaToken)
      return
    }
    setPendingAction(() => async () => { /* will be called after OTP */ })
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

  const handleScan = async () => {
    setScanning(true)
    setScanOutput(null)
    try {
      const res = await scanRule(ruleName!)
      setScanOutput(JSON.stringify(res, null, 2))
      await loadRule()
    } catch (e: any) {
      setScanOutput(`Error: ${e.response?.data?.detail || e.message}`)
    } finally {
      setScanning(false)
    }
  }

  const handleFix = () => {
    if (!confirm('Apply fix to this rule? This will modify system settings.')) return
    require2fa(async (token) => {
      setFixing(true)
      setFixOutput(null)
      try {
        const res = await fixRule(ruleName!, token || undefined)
        setFixOutput(JSON.stringify(res, null, 2))
        await loadRule()
      } catch (e: any) {
        setFixOutput(`Error: ${e.message}`)
      } finally {
        setFixing(false)
      }
    })
  }

  const handleUndoFix = () => {
    if (!confirm('Undo the most recent fix? This attempts to restore the prior system state.')) return
    require2fa(async (token) => {
      setUndoing(true)
      setFixOutput(null)
      try {
        const res = await undoFix(ruleName!, token || undefined)
        setFixOutput(JSON.stringify(res, null, 2))
        await loadRule()
      } catch (e: any) {
        setFixOutput(`Error: ${e.response?.data?.detail || e.message}`)
      } finally {
        setUndoing(false)
      }
    })
  }

  const handleGrantExemption = () => {
    if (!exemptReason.trim()) return
    require2fa(async (token) => {
      try {
        await grantExemption(
          { rule: ruleName!, reason: exemptReason, expires_at: exemptExpiry || undefined },
          token || undefined,
        )
        setShowExemptForm(false)
        setExemptReason('')
        setExemptExpiry('')
        await loadRule()
      } catch (e: any) {
        setError(e.message)
      }
    })
  }

  const handleRevokeExemption = () => {
    if (!confirm('Revoke exemption? The rule will be evaluated normally again.')) return
    require2fa(async (token) => {
      try {
        await revokeExemption(ruleName!, token || undefined)
        await loadRule()
      } catch (e: any) {
        setError(e.message)
      }
    })
  }

  if (loading) return <Layout><LoadingSpinner /></Layout>
  if (!rule) return <Layout><ErrorMessage message={error || 'Rule not found'} /></Layout>

  return (
    <Layout>
      <div className="px-6 pt-6 pb-2 flex items-center gap-3">
        <Link to="/rules" className="text-slate-500 hover:text-white transition-colors">
          <ArrowLeft className="w-4 h-4" />
        </Link>
        <div>
          <h1 className="text-xl font-semibold text-white font-mono">{rule.rule}</h1>
          <p className="text-slate-400 text-sm mt-0.5">{rule.description}</p>
        </div>
      </div>

      {error && <ErrorMessage message={error} />}

      <div className="px-6 pb-6 space-y-4">
        {/* 2FA OTP prompt */}
        {showOtpPrompt && (
          <OtpPrompt onVerified={handleOtpVerified} onCancel={handleOtpCancel} />
        )}

        {/* Status + Actions */}
        <Card className="p-5">
          <div className="flex items-start justify-between gap-4">
            <div className="flex items-center gap-4">
              <StatusBadge status={rule.current_status} size="lg" />
              <div className="text-slate-400 text-sm">
                <span className="text-slate-300">Category:</span> {rule.category}
                {rule.last_scan?.scanned_at && (
                  <span className="ml-4"><span className="text-slate-300">Last scanned:</span> {new Date(rule.last_scan.scanned_at).toLocaleString()}</span>
                )}
              </div>
            </div>
            <div className="flex items-center gap-2">
              {rule.has_scan && (
                <button onClick={handleScan} disabled={scanning}
                  className="flex items-center gap-2 px-3 py-1.5 bg-blue-600/20 hover:bg-blue-600/30 border border-blue-700/50 text-blue-400 text-sm rounded-lg transition-colors disabled:opacity-50">
                  <Play className="w-3.5 h-3.5" />
                  {scanning ? 'Scanning...' : 'Scan Now'}
                </button>
              )}
              {rule.has_fix && (
                <button onClick={handleFix} disabled={fixing}
                  className="flex items-center gap-2 px-3 py-1.5 bg-green-600/20 hover:bg-green-600/30 border border-green-700/50 text-green-400 text-sm rounded-lg transition-colors disabled:opacity-50">
                  <Wrench className="w-3.5 h-3.5" />
                  {fixing ? 'Fixing...' : 'Apply Fix'}
                </button>
              )}
              {rule.has_undo_fix && (
                <button onClick={handleUndoFix} disabled={undoing}
                  className="flex items-center gap-2 px-3 py-1.5 bg-amber-600/20 hover:bg-amber-600/30 border border-amber-700/50 text-amber-400 text-sm rounded-lg transition-colors disabled:opacity-50">
                  <RotateCcw className="w-3.5 h-3.5" />
                  {undoing ? 'Undoing...' : 'Undo Fix'}
                </button>
              )}
            </div>
          </div>

          {/* Standards badges */}
          <div className="flex gap-2 mt-4">
            {rule.standards?.['800-53r5_high'] && <span className="text-xs px-2 py-1 bg-purple-900/30 text-purple-400 rounded border border-purple-800/30">NIST 800-53r5 High</span>}
            {rule.standards?.cisv8 && <span className="text-xs px-2 py-1 bg-blue-900/30 text-blue-400 rounded border border-blue-800/30">CIS Controls v8</span>}
            {rule.standards?.cis_lvl2 && <span className="text-xs px-2 py-1 bg-teal-900/30 text-teal-400 rounded border border-teal-800/30">CIS Level 2</span>}
          </div>

          {/* Script paths */}
          <div className="mt-4 space-y-1">
            {rule.scan_script && (
              <div className="text-xs font-mono text-slate-500">Scan: <span className="text-slate-400">{rule.scan_script}</span></div>
            )}
            {rule.fix_script && (
              <div className="text-xs font-mono text-slate-500">Fix: <span className="text-slate-400">{rule.fix_script}</span></div>
            )}
            {!rule.scan_script && (
              <div className="text-xs text-blue-400 mt-2">⚡ MDM Required — Deploy via configuration profile</div>
            )}
          </div>
        </Card>

        {/* Scan output terminal */}
        {(scanOutput || fixing || undoing || fixOutput) && (
          <Card className="p-5">
            <div className="text-slate-400 text-xs font-medium mb-3">
              {fixOutput ? (undoing ? 'UNDO OUTPUT' : 'FIX OUTPUT') : 'SCAN OUTPUT'}
            </div>
            <div className="terminal">{fixOutput || scanOutput || 'Running...'}</div>
          </Card>
        )}

        {/* Scan history */}
        {rule.scan_history?.length > 0 && (
          <Card className="p-5">
            <div className="text-slate-400 text-xs font-medium mb-3">SCAN HISTORY (LAST 30)</div>
            <div className="flex gap-1 flex-wrap">
              {rule.scan_history.map((h: any, i: number) => (
                <div key={i} title={`${h.status} — ${new Date(h.scanned_at).toLocaleString()}`}
                  className={`w-4 h-4 rounded-sm cursor-default ${
                    h.status === 'PASS' ? 'bg-green-500/70' :
                    h.status === 'FAIL' ? 'bg-red-500/70' :
                    h.status === 'EXEMPT' ? 'bg-yellow-500/70' :
                    'bg-slate-600/50'
                  }`} />
              ))}
            </div>
          </Card>
        )}

        {/* Exemption management */}
        <Card className="p-5">
          <div className="flex items-center justify-between mb-3">
            <div className="text-slate-400 text-xs font-medium">EXEMPTION</div>
            {!rule.exemption && !showExemptForm && (
              <button onClick={() => setShowExemptForm(true)}
                className="flex items-center gap-1.5 text-xs px-3 py-1.5 bg-yellow-600/20 hover:bg-yellow-600/30 border border-yellow-700/50 text-yellow-400 rounded-lg transition-colors">
                <ShieldOff className="w-3 h-3" />
                Grant Exemption
              </button>
            )}
          </div>

          {rule.exemption ? (
            <div className="space-y-2">
              <div className="text-sm text-slate-300">
                <span className="text-slate-500">Reason:</span> {rule.exemption.reason}
              </div>
              {rule.exemption.expires_at && (
                <div className="text-sm text-slate-400">
                  <span className="text-slate-500">Expires:</span> {new Date(rule.exemption.expires_at).toLocaleDateString()}
                </div>
              )}
              <button onClick={handleRevokeExemption}
                className="flex items-center gap-1.5 text-xs px-3 py-1.5 bg-red-600/20 hover:bg-red-600/30 border border-red-700/50 text-red-400 rounded-lg transition-colors mt-2">
                <RotateCcw className="w-3 h-3" />
                Revoke Exemption
              </button>
            </div>
          ) : showExemptForm ? (
            <div className="space-y-3">
              <textarea
                value={exemptReason}
                onChange={e => setExemptReason(e.target.value)}
                placeholder="Reason for exemption..."
                rows={3}
                className="w-full bg-[#0a0e1a] border border-[#1e2d4a] rounded-lg px-3 py-2 text-sm text-white placeholder-slate-600 focus:outline-none focus:border-blue-500 resize-none"
              />
              <div className="flex items-center gap-3">
                <input
                  type="date"
                  value={exemptExpiry}
                  onChange={e => setExemptExpiry(e.target.value)}
                  className="bg-[#0a0e1a] border border-[#1e2d4a] rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-blue-500"
                />
                <span className="text-slate-500 text-xs">Expiry date (optional)</span>
              </div>
              <div className="flex gap-2">
                <button onClick={handleGrantExemption}
                  className="px-4 py-2 bg-yellow-600/20 hover:bg-yellow-600/30 border border-yellow-700/50 text-yellow-400 text-sm rounded-lg transition-colors">
                  Grant Exemption
                </button>
                <button onClick={() => setShowExemptForm(false)}
                  className="px-4 py-2 text-slate-400 hover:text-white text-sm transition-colors">
                  Cancel
                </button>
              </div>
            </div>
          ) : (
            <div className="text-slate-600 text-sm">No active exemption</div>
          )}
        </Card>

        {/* Fix history */}
        {fixHistory.length > 0 && (
          <Card className="p-5">
            <div className="text-slate-400 text-xs font-medium mb-3">FIX HISTORY</div>
            <div className="space-y-2">
              {fixHistory.map((h: any) => (
                <div key={h.id} className="flex items-start justify-between text-sm border-b border-[#1e2d4a]/50 pb-2 last:border-0">
                  <div>
                    <span className={`font-medium ${h.action === 'EXECUTED' ? 'text-green-400' : 'text-orange-400'}`}>{h.action}</span>
                    {h.message && <span className="text-slate-500 ml-2 text-xs">{h.message}</span>}
                    {h.scan_before && h.scan_after && (
                      <span className="text-slate-500 ml-2 text-xs">{h.scan_before} → {h.scan_after}</span>
                    )}
                  </div>
                  <span className="text-slate-600 text-xs">{new Date(h.executed_at).toLocaleString()}</span>
                </div>
              ))}
            </div>
          </Card>
        )}
      </div>
    </Layout>
  )
}
