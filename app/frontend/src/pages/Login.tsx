import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Shield } from 'lucide-react'
import { setToken, verifyToken } from '../lib/api'

export function Login() {
  const [token, setTokenInput] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const navigate = useNavigate()

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!token.trim()) return
    setLoading(true)
    setError('')
    try {
      const res = await verifyToken(token.trim())
      if (res.valid) {
        setToken(token.trim())
        navigate('/')
      } else {
        setError('Invalid token. Check the terminal where hxg_server is running.')
      }
    } catch {
      setError('Could not connect to HX-Guardian server. Make sure it is running.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen bg-[#0a0e1a] flex items-center justify-center p-4">
      <div className="w-full max-w-md">
        <div className="flex flex-col items-center mb-8">
          <div className="w-16 h-16 rounded-2xl bg-blue-600 flex items-center justify-center mb-4">
            <Shield className="w-9 h-9 text-white" />
          </div>
          <h1 className="text-2xl font-bold text-white">HX-Guardian</h1>
          <p className="text-slate-400 text-sm mt-2">Security Compliance Dashboard</p>
        </div>

        <div className="bg-[#0f1629] border border-[#1e2d4a] rounded-2xl p-8">
          <h2 className="text-white font-semibold mb-1">Enter Session Token</h2>
          <p className="text-slate-400 text-sm mb-6">
            Copy the token printed in the terminal when the server started.
          </p>

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <input
                type="password"
                value={token}
                onChange={e => setTokenInput(e.target.value)}
                placeholder="Paste session token here..."
                className="w-full bg-[#0a0e1a] border border-[#1e2d4a] rounded-lg px-4 py-3 text-white placeholder-slate-600 focus:outline-none focus:border-blue-500 font-mono text-sm"
                autoFocus
              />
            </div>

            {error && (
              <div className="text-red-400 text-sm bg-red-900/20 border border-red-700/50 rounded-lg px-4 py-3">
                {error}
              </div>
            )}

            <button
              type="submit"
              disabled={loading || !token.trim()}
              className="w-full bg-blue-600 hover:bg-blue-500 disabled:bg-blue-900 disabled:text-blue-700 text-white font-semibold py-3 rounded-lg transition-colors"
            >
              {loading ? 'Verifying...' : 'Access Dashboard'}
            </button>
          </form>

          <p className="text-slate-600 text-xs mt-6 text-center">
            HX-Guardian runs locally on 127.0.0.1:8000 only.
            <br />This dashboard is not accessible from the network.
          </p>
        </div>
      </div>
    </div>
  )
}
