import { Navigate } from 'react-router-dom';
import type { ReactNode } from 'react';
import { useAuth } from '../shared/authContext';

export function RequireAdmin({ children }: { children: ReactNode }) {
  const { ready, user, isAdmin } = useAuth();

  if (!ready) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-950 text-slate-300">
        Verifying admin session…
      </div>
    );
  }

  if (!user) {
    return <Navigate to="/admin/login" replace />;
  }

  if (!isAdmin) {
    return <Navigate to="/admin/login" replace state={{ denied: true }} />;
  }

  return <>{children}</>;
}
