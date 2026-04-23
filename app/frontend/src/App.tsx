import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'

import { Dashboard } from './pages/Dashboard'
import { Rules } from './pages/Rules'
import { RuleDetail } from './pages/RuleDetail'
import { History } from './pages/History'
import { Device } from './pages/Device'
import { Connections } from './pages/Connections'
import { Logs } from './pages/Logs'
import { Exemptions } from './pages/Exemptions'
import { Schedule } from './pages/Schedule'
import { Reports } from './pages/Reports'
import { AuditLog } from './pages/AuditLog'
import { Settings } from './pages/Settings'

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Dashboard />} />
        <Route path="/rules" element={<Rules />} />
        <Route path="/rules/:ruleName" element={<RuleDetail />} />
        <Route path="/history" element={<History />} />
        <Route path="/device" element={<Device />} />
        <Route path="/connections" element={<Connections />} />
        <Route path="/logs" element={<Logs />} />
        <Route path="/exemptions" element={<Exemptions />} />
        <Route path="/schedule" element={<Schedule />} />
        <Route path="/reports" element={<Reports />} />
        <Route path="/audit-log" element={<AuditLog />} />
        <Route path="/settings" element={<Settings />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  )
}
