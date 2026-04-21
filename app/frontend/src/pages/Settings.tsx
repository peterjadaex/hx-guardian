import { useEffect, useRef, useState } from 'react'
import { Shield, ShieldCheck, ShieldOff, QrCode, KeyRound, Eye, Copy, Check } from 'lucide-react'
import QRCode from 'qrcode'
import { Layout, PageHeader, Card, LoadingSpinner, ErrorMessage } from '../components/Layout'
import {
  get2faStatus, init2faSetup, confirm2faSetup,
  view2faQr, disable2fa,
} from '../lib/api'

// ─── Types ────────────────────────────────────────────────────────────────────

type UIState =
  | 'loading'
  | 'disabled'
  | 'setup-qr'      // showing QR for new setup or rekey
  | 'setup-confirm' // OTP prompt to finalize setup
  | 'enabled'
  | 'otp-for-viewqr'
  | 'show-current-qr'
  | 'otp-for-rekey'
  | 'otp-for-disable'

// ─── OTP Input ────────────────────────────────────────────────────────────────

function OtpInput({
  value,
  onChange,
  onSubmit,
  error,
  label = 'Enter 6-digit code from your authenticator app',
  loading = false,
}: {
  value: string
  onChange: (v: string) => void
  onSubmit: () => void
  error: string
  label?: string
  loading?: boolean
}) {
  const ref = useRef<HTMLInputElement>(null)
  useEffect(() => { ref.current?.focus() }, [])

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const v = e.target.value.replace(/\D/g, '').slice(0, 6)
    onChange(v)
    if (v.length === 6) setTimeout(onSubmit, 50)
  }

  return (
    <div className="space-y-3">
      <p className="text-slate-400 text-sm">{label}</p>
      <input
        ref={ref}
        type="text"
        inputMode="numeric"
        maxLength={6}
        value={value}
        onChange={handleChange}
        placeholder="000000"
        disabled={loading}
        className="w-36 bg-[#0a0e1a] border border-[#1e2d4a] rounded-lg px-4 py-3 text-white text-center text-2xl font-mono tracking-widest focus:outline-none focus:border-blue-500 disabled:opacity-50"
      />
      {error && <p className="text-red-400 text-sm">{error}</p>}
    </div>
  )
}

// ─── QR Display ──────────────────────────────────────────────────────────────

function QrDisplay({ provisioningUri }: { provisioningUri: string }) {
  const [qrDataUrl, setQrDataUrl] = useState('')
  const [showUri, setShowUri] = useState(false)
  const [copied, setCopied] = useState(false)

  useEffect(() => {
    QRCode.toDataURL(provisioningUri, {
      width: 200,
      margin: 2,
      color: { dark: '#000000', light: '#ffffff' },
    }).then(setQrDataUrl).catch(() => setShowUri(true))
  }, [provisioningUri])

  const handleCopy = () => {
    navigator.clipboard.writeText(provisioningUri).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    })
  }

  return (
    <div className="space-y-4">
      {qrDataUrl && (
        <div className="flex justify-center">
          <div className="p-3 bg-white rounded-xl inline-block">
            <img src={qrDataUrl} alt="2FA QR code" className="w-48 h-48" />
          </div>
        </div>
      )}
      <div className="text-center">
        <button
          onClick={() => setShowUri(v => !v)}
          className="text-slate-400 hover:text-slate-200 text-xs transition-colors underline underline-offset-2"
        >
          {showUri ? 'Hide' : "Can't scan? Show setup key"}
        </button>
      </div>
      {showUri && (
        <div className="bg-[#0a0e1a] border border-[#1e2d4a] rounded-lg p-3 flex items-start gap-2">
          <code className="text-xs text-slate-300 break-all flex-1 font-mono">{provisioningUri}</code>
          <button onClick={handleCopy} className="text-slate-500 hover:text-blue-400 transition-colors flex-shrink-0 mt-0.5">
            {copied ? <Check className="w-4 h-4 text-green-400" /> : <Copy className="w-4 h-4" />}
          </button>
        </div>
      )}
    </div>
  )
}

// ─── Main page ────────────────────────────────────────────────────────────────

export function Settings() {
  const [uiState, setUiState] = useState<UIState>('loading')
  const [statusData, setStatusData] = useState<any>(null)
  const [otp, setOtp] = useState('')
  const [otpError, setOtpError] = useState('')
  const [provisioningUri, setProvisioningUri] = useState('')
  const [pageError, setPageError] = useState('')
  const [loading, setLoading] = useState(false)

  const loadStatus = async () => {
    setPageError('')
    try {
      const data = await get2faStatus()
      setStatusData(data)
      setUiState(data.enabled ? 'enabled' : 'disabled')
    } catch (e: any) {
      setPageError(e.message)
      setUiState('disabled')
    }
  }

  useEffect(() => { loadStatus() }, [])

  const resetOtp = () => { setOtp(''); setOtpError('') }

  // ── Action handlers ────────────────────────────────────────────────────────

  const handleSetupStart = async () => {
    setLoading(true)
    setPageError('')
    try {
      const res = await init2faSetup()
      setProvisioningUri(res.provisioning_uri)
      resetOtp()
      setUiState('setup-qr')
    } catch (e: any) {
      setPageError(e.response?.data?.detail || e.message)
    } finally {
      setLoading(false)
    }
  }

  const handleSetupConfirm = async () => {
    if (otp.length !== 6) return
    setLoading(true)
    setOtpError('')
    try {
      await confirm2faSetup(otp)
      resetOtp()
      await loadStatus()
    } catch (e: any) {
      setOtpError(e.response?.data?.detail || 'Invalid code, try again')
    } finally {
      setLoading(false)
    }
  }

  const handleViewQrOtpConfirm = async () => {
    if (otp.length !== 6) return
    setLoading(true)
    setOtpError('')
    try {
      const res = await view2faQr(otp)
      setProvisioningUri(res.provisioning_uri)
      resetOtp()
      setUiState('show-current-qr')
    } catch (e: any) {
      setOtpError(e.response?.data?.detail || 'Invalid code, try again')
    } finally {
      setLoading(false)
    }
  }

  const handleRekeyOtpConfirm = async () => {
    if (otp.length !== 6) return
    setLoading(true)
    setOtpError('')
    try {
      const res = await init2faSetup(otp)
      setProvisioningUri(res.provisioning_uri)
      resetOtp()
      setUiState('setup-qr')
    } catch (e: any) {
      setOtpError(e.response?.data?.detail || 'Invalid code, try again')
    } finally {
      setLoading(false)
    }
  }

  const handleDisableOtpConfirm = async () => {
    if (otp.length !== 6) return
    setLoading(true)
    setOtpError('')
    try {
      await disable2fa(otp)
      resetOtp()
      await loadStatus()
    } catch (e: any) {
      setOtpError(e.response?.data?.detail || 'Invalid code, try again')
    } finally {
      setLoading(false)
    }
  }

  const handleCancel = () => {
    resetOtp()
    loadStatus()
  }

  // ── Render ─────────────────────────────────────────────────────────────────

  if (uiState === 'loading') return <Layout><LoadingSpinner /></Layout>

  return (
    <Layout>
      <PageHeader title="Settings" subtitle="Application configuration" />

      {pageError && <ErrorMessage message={pageError} />}

      <div className="px-6 pb-6 max-w-2xl space-y-6">

        {/* Section heading */}
        <p className="text-xs text-slate-500 uppercase tracking-widest font-medium">
          Admin Authentication
        </p>

        <Card className="p-5">
          {/* ── Header row ── */}
          <div className="flex items-start justify-between mb-5">
            <div className="flex items-start gap-3">
              <div className={`w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0 ${
                uiState === 'enabled' || uiState === 'otp-for-viewqr' || uiState === 'show-current-qr' || uiState === 'otp-for-rekey' || uiState === 'otp-for-disable'
                  ? 'bg-green-500/20' : 'bg-slate-700/50'
              }`}>
                {uiState === 'enabled' || uiState === 'otp-for-viewqr' || uiState === 'show-current-qr' || uiState === 'otp-for-rekey' || uiState === 'otp-for-disable'
                  ? <ShieldCheck className="w-5 h-5 text-green-400" />
                  : <Shield className="w-5 h-5 text-slate-400" />
                }
              </div>
              <div>
                <div className="text-white font-medium">Two-Factor Authentication</div>
                <div className="text-slate-400 text-sm mt-0.5">
                  TOTP via authenticator app (Google Authenticator, Authy, etc.)
                </div>
              </div>
            </div>
            {/* Status badge */}
            {(uiState === 'enabled' || uiState === 'otp-for-viewqr' || uiState === 'show-current-qr' || uiState === 'otp-for-rekey' || uiState === 'otp-for-disable') && (
              <span className="flex items-center gap-1.5 px-2.5 py-1 bg-green-500/10 border border-green-500/30 text-green-400 text-xs rounded-full font-medium flex-shrink-0">
                <span className="w-1.5 h-1.5 rounded-full bg-green-400" />
                Enabled
              </span>
            )}
            {uiState === 'disabled' && (
              <span className="flex items-center gap-1.5 px-2.5 py-1 bg-red-500/10 border border-red-500/30 text-red-400 text-xs rounded-full font-medium flex-shrink-0">
                <span className="w-1.5 h-1.5 rounded-full bg-red-400" />
                Disabled
              </span>
            )}
          </div>

          {/* Divider */}
          <div className="border-t border-[#1e2d4a] mb-5" />

          {/* ── State: disabled ── */}
          {uiState === 'disabled' && (
            <div className="space-y-4">
              <p className="text-slate-400 text-sm">
                Protect sensitive actions with a time-based one-time password. Scan the QR code with your authenticator app to get started.
              </p>
              <button
                onClick={handleSetupStart}
                disabled={loading}
                className="flex items-center gap-2 px-4 py-2 bg-blue-600/20 border border-blue-500/40 text-blue-400 text-sm rounded-lg hover:bg-blue-600/30 transition-colors disabled:opacity-50"
              >
                <KeyRound className="w-4 h-4" />
                Set Up 2FA
              </button>
            </div>
          )}

          {/* ── State: setup-qr (new setup or rekey) ── */}
          {uiState === 'setup-qr' && (
            <div className="space-y-5">
              <p className="text-slate-300 text-sm font-medium">Step 1 — Scan this QR code in your authenticator app</p>
              <QrDisplay provisioningUri={provisioningUri} />
              <div className="border-t border-[#1e2d4a] pt-5">
                <p className="text-slate-300 text-sm font-medium mb-4">Step 2 — Enter the 6-digit code to confirm</p>
                <OtpInput
                  value={otp}
                  onChange={setOtp}
                  onSubmit={handleSetupConfirm}
                  error={otpError}
                  loading={loading}
                />
                <div className="flex gap-2 mt-4">
                  <button
                    onClick={handleSetupConfirm}
                    disabled={otp.length !== 6 || loading}
                    className="px-4 py-2 bg-blue-600 hover:bg-blue-500 disabled:bg-blue-900 disabled:text-blue-700 text-white text-sm rounded-lg transition-colors font-medium"
                  >
                    {loading ? 'Verifying…' : 'Confirm & Enable'}
                  </button>
                  <button onClick={handleCancel} className="px-4 py-2 text-slate-400 hover:text-white text-sm transition-colors">
                    Cancel
                  </button>
                </div>
              </div>
            </div>
          )}

          {/* ── State: enabled ── */}
          {uiState === 'enabled' && (
            <div className="space-y-4">
              {statusData?.last_verified_at && (
                <p className="text-slate-500 text-xs">
                  Last verified: {new Date(statusData.last_verified_at).toLocaleString()}
                </p>
              )}
              <div className="flex flex-wrap gap-2">
                <button
                  onClick={() => { resetOtp(); setUiState('otp-for-viewqr') }}
                  className="flex items-center gap-2 px-3 py-2 bg-slate-700/40 border border-slate-600/40 text-slate-300 text-sm rounded-lg hover:bg-slate-700/70 transition-colors"
                >
                  <Eye className="w-4 h-4" />
                  View QR Code
                </button>
                <button
                  onClick={() => { resetOtp(); setUiState('otp-for-rekey') }}
                  className="flex items-center gap-2 px-3 py-2 bg-yellow-600/10 border border-yellow-600/30 text-yellow-400 text-sm rounded-lg hover:bg-yellow-600/20 transition-colors"
                >
                  <QrCode className="w-4 h-4" />
                  Change Key
                </button>
                <button
                  onClick={() => { resetOtp(); setUiState('otp-for-disable') }}
                  className="flex items-center gap-2 px-3 py-2 bg-red-600/10 border border-red-600/30 text-red-400 text-sm rounded-lg hover:bg-red-600/20 transition-colors"
                >
                  <ShieldOff className="w-4 h-4" />
                  Disable 2FA
                </button>
              </div>
            </div>
          )}

          {/* ── State: otp-for-viewqr ── */}
          {uiState === 'otp-for-viewqr' && (
            <div className="space-y-4">
              <p className="text-slate-300 text-sm font-medium">Verify identity to view QR code</p>
              <OtpInput
                value={otp}
                onChange={setOtp}
                onSubmit={handleViewQrOtpConfirm}
                error={otpError}
                loading={loading}
              />
              <div className="flex gap-2">
                <button
                  onClick={handleViewQrOtpConfirm}
                  disabled={otp.length !== 6 || loading}
                  className="px-4 py-2 bg-blue-600 hover:bg-blue-500 disabled:bg-blue-900 disabled:text-blue-700 text-white text-sm rounded-lg transition-colors font-medium"
                >
                  {loading ? 'Verifying…' : 'Show QR Code'}
                </button>
                <button onClick={handleCancel} className="px-4 py-2 text-slate-400 hover:text-white text-sm transition-colors">
                  Cancel
                </button>
              </div>
            </div>
          )}

          {/* ── State: show-current-qr ── */}
          {uiState === 'show-current-qr' && (
            <div className="space-y-5">
              <p className="text-slate-300 text-sm font-medium">Scan to add to a new device (this is your existing key)</p>
              <QrDisplay provisioningUri={provisioningUri} />
              <button onClick={handleCancel} className="px-4 py-2 bg-slate-700/40 border border-slate-600/40 text-slate-300 text-sm rounded-lg hover:bg-slate-700/70 transition-colors">
                Done
              </button>
            </div>
          )}

          {/* ── State: otp-for-rekey ── */}
          {uiState === 'otp-for-rekey' && (
            <div className="space-y-4">
              <p className="text-slate-300 text-sm font-medium">Verify current OTP to generate a new key</p>
              <p className="text-yellow-400/80 text-xs bg-yellow-500/10 border border-yellow-500/20 rounded-lg px-3 py-2">
                Changing the key will invalidate your current authenticator entry. You'll need to re-scan the new QR code.
              </p>
              <OtpInput
                value={otp}
                onChange={setOtp}
                onSubmit={handleRekeyOtpConfirm}
                error={otpError}
                label="Enter current 6-digit code to continue"
                loading={loading}
              />
              <div className="flex gap-2">
                <button
                  onClick={handleRekeyOtpConfirm}
                  disabled={otp.length !== 6 || loading}
                  className="px-4 py-2 bg-yellow-600/20 hover:bg-yellow-600/30 border border-yellow-600/40 text-yellow-400 text-sm rounded-lg transition-colors font-medium disabled:opacity-50"
                >
                  {loading ? 'Verifying…' : 'Continue'}
                </button>
                <button onClick={handleCancel} className="px-4 py-2 text-slate-400 hover:text-white text-sm transition-colors">
                  Cancel
                </button>
              </div>
            </div>
          )}

          {/* ── State: otp-for-disable ── */}
          {uiState === 'otp-for-disable' && (
            <div className="space-y-4">
              <p className="text-slate-300 text-sm font-medium">Verify identity to disable 2FA</p>
              <OtpInput
                value={otp}
                onChange={setOtp}
                onSubmit={handleDisableOtpConfirm}
                error={otpError}
                loading={loading}
              />
              <div className="flex gap-2">
                <button
                  onClick={handleDisableOtpConfirm}
                  disabled={otp.length !== 6 || loading}
                  className="px-4 py-2 bg-red-600/20 hover:bg-red-600/30 border border-red-600/40 text-red-400 text-sm rounded-lg transition-colors font-medium disabled:opacity-50"
                >
                  {loading ? 'Verifying…' : 'Disable 2FA'}
                </button>
                <button onClick={handleCancel} className="px-4 py-2 text-slate-400 hover:text-white text-sm transition-colors">
                  Cancel
                </button>
              </div>
            </div>
          )}
        </Card>
      </div>
    </Layout>
  )
}
