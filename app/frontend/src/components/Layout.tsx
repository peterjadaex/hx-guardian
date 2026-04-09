import { NavLink, useNavigate } from 'react-router-dom'
import { clsx } from 'clsx'
import {
  Shield, LayoutDashboard, ListChecks, History, Monitor,
  FileText, Usb, Settings, LogOut, Cpu, Calendar,
  ClipboardList, BookOpen
} from 'lucide-react'
import { clearToken } from '../lib/api'

const NAV_ITEMS = [
  { path: '/',            label: 'Dashboard',     icon: LayoutDashboard },
  { path: '/rules',       label: 'Rules',         icon: ListChecks },
  { path: '/history',     label: 'Scan History',  icon: History },
  { path: '/device',      label: 'Device Status', icon: Monitor },
  { path: '/connections', label: 'Connections',   icon: Usb },
  { path: '/logs',        label: 'Device Logs',   icon: FileText },
  { path: '/mdm',         label: 'MDM Profiles',  icon: Cpu },
  { path: '/exemptions',  label: 'Exemptions',    icon: Settings },
  { path: '/schedule',    label: 'Schedule',      icon: Calendar },
  { path: '/reports',     label: 'Reports',       icon: ClipboardList },
  { path: '/audit-log',   label: 'Audit Log',     icon: BookOpen },
]

export function Layout({ children }: { children: React.ReactNode }) {
  const navigate = useNavigate()

  const handleLogout = () => {
    clearToken()
    navigate('/login')
  }

  return (
    <div className="flex h-screen overflow-hidden bg-[#0a0e1a]">
      {/* Sidebar */}
      <aside className="w-60 flex-shrink-0 flex flex-col bg-[#0d1424] border-r border-[#1e2d4a]">
        {/* Logo */}
        <div className="flex items-center gap-3 px-5 py-5 border-b border-[#1e2d4a]">
          <div className="w-8 h-8 rounded-lg bg-blue-600 flex items-center justify-center">
            <Shield className="w-5 h-5 text-white" />
          </div>
          <div>
            <div className="text-white font-bold text-sm">HX-Guardian</div>
            <div className="text-slate-500 text-xs">Security Dashboard</div>
          </div>
        </div>

        {/* Navigation */}
        <nav className="flex-1 overflow-y-auto px-3 py-4 space-y-0.5">
          {NAV_ITEMS.map(({ path, label, icon: Icon }) => (
            <NavLink
              key={path}
              to={path}
              end={path === '/'}
              className={({ isActive }) => clsx(
                'flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors',
                isActive
                  ? 'bg-blue-600/20 text-blue-400 font-medium'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-white/5'
              )}
            >
              <Icon className="w-4 h-4 flex-shrink-0" />
              {label}
            </NavLink>
          ))}
        </nav>

        {/* Footer */}
        <div className="px-3 py-4 border-t border-[#1e2d4a] space-y-0.5">
          <button
            onClick={handleLogout}
            className="w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-slate-400 hover:text-red-400 hover:bg-red-900/10 transition-colors"
          >
            <LogOut className="w-4 h-4" />
            Logout
          </button>
        </div>
      </aside>

      {/* Main content */}
      <main className="flex-1 overflow-y-auto">
        {children}
      </main>
    </div>
  )
}

// ─── Shared UI primitives ─────────────────────────────────────────────────────

export function PageHeader({ title, subtitle, children }: {
  title: string
  subtitle?: string
  children?: React.ReactNode
}) {
  return (
    <div className="flex items-start justify-between px-6 pt-6 pb-4">
      <div>
        <h1 className="text-xl font-semibold text-white">{title}</h1>
        {subtitle && <p className="text-slate-400 text-sm mt-1">{subtitle}</p>}
      </div>
      {children && <div className="flex items-center gap-3">{children}</div>}
    </div>
  )
}

export function Card({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <div className={clsx('bg-[#0f1629] border border-[#1e2d4a] rounded-xl', className)}>
      {children}
    </div>
  )
}

export function LoadingSpinner() {
  return (
    <div className="flex items-center justify-center p-12">
      <div className="w-8 h-8 border-2 border-blue-600 border-t-transparent rounded-full animate-spin" />
    </div>
  )
}

export function ErrorMessage({ message }: { message: string }) {
  return (
    <div className="mx-6 p-4 bg-red-900/20 border border-red-700/50 rounded-lg text-red-400 text-sm">
      {message}
    </div>
  )
}
