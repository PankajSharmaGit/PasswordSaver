import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import {
  Crown,
  History,
  LayoutDashboard,
  LogOut,
  Receipt,
  Shield,
  Users,
} from 'lucide-react';
import { useAuth } from '../shared/authContext';

const NAV = [
  { to: '/admin', end: true, label: 'Overview', icon: LayoutDashboard },
  { to: '/admin/plans', label: 'Pricing & Plans', icon: Crown },
  { to: '/admin/payments', label: 'Payments', icon: Receipt },
  { to: '/admin/users', label: 'Users', icon: Users },
  { to: '/admin/activity', label: 'Activity log', icon: History },
];

export function AdminLayout() {
  const { user, signOut } = useAuth();
  const navigate = useNavigate();

  async function logout() {
    await signOut();
    navigate('/admin/login', { replace: true });
  }

  return (
    <div className="flex min-h-screen bg-slate-950 text-slate-100">
      <aside className="hidden w-64 shrink-0 flex-col border-r border-slate-800 bg-slate-900/80 lg:flex">
        <div className="border-b border-slate-800 px-5 py-5">
          <p className="text-sm font-bold text-white">PasswordSaver</p>
          <p className="flex items-center gap-1 text-[11px] text-teal-300">
            <Shield className="h-3 w-3" /> Admin console
          </p>
        </div>
        <nav className="flex-1 space-y-1 p-3">
          {NAV.map((item) => {
            const Icon = item.icon;
            return (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.end}
                className={({ isActive }) =>
                  `flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-semibold transition ${
                    isActive
                      ? 'bg-teal-500/20 text-white ring-1 ring-teal-400/30'
                      : 'text-slate-400 hover:bg-white/5 hover:text-white'
                  }`
                }
              >
                <Icon className="h-4 w-4" />
                {item.label}
              </NavLink>
            );
          })}
        </nav>
        <div className="border-t border-slate-800 p-4">
          <p className="truncate text-xs text-slate-500">{user?.email}</p>
          <button
            type="button"
            onClick={() => void logout()}
            className="mt-2 inline-flex items-center gap-2 text-xs font-semibold text-rose-300 hover:text-rose-200"
          >
            <LogOut className="h-3.5 w-3.5" /> Sign out
          </button>
        </div>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="border-b border-slate-800 bg-slate-950/90 px-4 py-3 lg:hidden">
          <p className="text-sm font-semibold">PasswordSaver Admin</p>
          <div className="mt-2 flex flex-wrap gap-2">
            {NAV.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.end}
                className={({ isActive }) =>
                  `rounded-lg px-2 py-1 text-xs font-semibold ${
                    isActive ? 'bg-teal-500/20 text-teal-200' : 'text-slate-400'
                  }`
                }
              >
                {item.label}
              </NavLink>
            ))}
          </div>
        </header>
        <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-8 sm:px-6">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
