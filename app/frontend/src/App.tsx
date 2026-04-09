import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { getToken } from './lib/api'

import { Login } from './pages/Login'
import { Dashboard } from './pages/Dashboard'
import { Rules } from './pages/Rules'
import { RuleDetail } from './pages/RuleDetail'
import { History } from './pages/History'
import { Device } from './pages/Device'
import { Connections } from './pages/Connections'
import { Logs } from './pages/Logs'
import { MdmProfiles } from './pages/MdmProfiles'
import { Exemptions } from './pages/Exemptions'
import { Schedule } from './pages/Schedule'
import { Reports } from './pages/Reports'
import { AuditLog } from './pages/AuditLog'

function RequireAuth({ children }: { children: React.ReactNode }) {
  if (!getToken()) return <Navigate to="/login" replace />
  return <>{children}</>
}

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/" element={<RequireAuth><Dashboard /></RequireAuth>} />
        <Route path="/rules" element={<RequireAuth><Rules /></RequireAuth>} />
        <Route path="/rules/:ruleName" element={<RequireAuth><RuleDetail /></RequireAuth>} />
        <Route path="/history" element={<RequireAuth><History /></RequireAuth>} />
        <Route path="/device" element={<RequireAuth><Device /></RequireAuth>} />
        <Route path="/connections" element={<RequireAuth><Connections /></RequireAuth>} />
        <Route path="/logs" element={<RequireAuth><Logs /></RequireAuth>} />
        <Route path="/mdm" element={<RequireAuth><MdmProfiles /></RequireAuth>} />
        <Route path="/exemptions" element={<RequireAuth><Exemptions /></RequireAuth>} />
        <Route path="/schedule" element={<RequireAuth><Schedule /></RequireAuth>} />
        <Route path="/reports" element={<RequireAuth><Reports /></RequireAuth>} />
        <Route path="/audit-log" element={<RequireAuth><AuditLog /></RequireAuth>} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  )
}
