import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import { AdminAuditPage } from './pages/AdminAuditPage';
import { AdminDashboardPage } from './pages/AdminDashboardPage';
import { AdminLayout } from './pages/AdminLayout';
import { AdminLoginPage } from './pages/AdminLoginPage';
import { AdminPaymentsPage } from './pages/AdminPaymentsPage';
import { AdminPlansPage } from './pages/AdminPlansPage';
import { AdminUsersPage } from './pages/AdminUsersPage';
import { RequireAdmin } from './pages/RequireAdmin';

export function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Navigate to="/admin" replace />} />
        <Route path="/admin/login" element={<AdminLoginPage />} />
        <Route
          path="/admin"
          element={
            <RequireAdmin>
              <AdminLayout />
            </RequireAdmin>
          }
        >
          <Route index element={<AdminDashboardPage />} />
          <Route path="plans" element={<AdminPlansPage />} />
          <Route path="payments" element={<AdminPaymentsPage />} />
          <Route path="users" element={<AdminUsersPage />} />
          <Route path="activity" element={<AdminAuditPage />} />
        </Route>
        <Route path="*" element={<Navigate to="/admin" replace />} />
      </Routes>
    </BrowserRouter>
  );
}
