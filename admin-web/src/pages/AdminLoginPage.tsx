import { type FormEvent, useState } from 'react';
import { Navigate } from 'react-router-dom';
import { Loader2, Lock, Mail, Shield } from 'lucide-react';
import { useAuth } from '../shared/authContext';

export function AdminLoginPage() {
  const { ready, user, isAdmin, signIn } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  if (!ready) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-950 text-slate-300">
        Loading…
      </div>
    );
  }

  if (user && isAdmin) {
    return <Navigate to="/admin" replace />;
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      const trimmed = email.trim();
      if (!isPlatformAdminAfterLogin(trimmed)) {
        setError('This account is not an admin.');
        setBusy(false);
        return;
      }
      await signIn(trimmed, password);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed');
    } finally {
      setBusy(false);
    }
  }

  function isPlatformAdminAfterLogin(inputEmail: string) {
    const list =
      import.meta.env.VITE_ADMIN_EMAILS?.trim() ||
      'passwordsaver@gryzion.com';
    return list
      .split(',')
      .map((e: string) => e.trim().toLowerCase())
      .includes(inputEmail.trim().toLowerCase());
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-950 px-4 py-10 text-slate-100">
      <div className="w-full max-w-md">
        <div className="mb-8 text-center">
          <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl bg-teal-500/20 text-2xl font-bold text-teal-300">
            PS
          </div>
          <h1 className="mt-4 text-2xl font-bold text-white">PasswordSaver Admin</h1>
          <p className="mt-1 text-sm text-slate-400">
            Manage pricing, users & payments
          </p>
        </div>

        <form
          onSubmit={onSubmit}
          className="rounded-2xl border border-slate-800 bg-slate-900/80 p-6 shadow-2xl"
        >
          <div className="mb-5 flex items-center gap-2 text-teal-300">
            <Shield className="h-5 w-5" />
            <span className="text-sm font-semibold">Admin sign in</span>
          </div>

          {error && (
            <div className="mb-4 rounded-xl border border-rose-500/30 bg-rose-500/10 px-4 py-3 text-sm text-rose-200">
              {error}
            </div>
          )}

          <label className="mb-3 block text-xs font-semibold text-slate-400">
            Email
            <div className="relative mt-1.5">
              <Mail className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-500" />
              <input
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="w-full rounded-xl border border-slate-700 bg-slate-950 py-2.5 pl-10 pr-3 text-sm text-white focus:border-teal-400 focus:outline-none"
                placeholder="passwordsaver@gryzion.com"
              />
            </div>
          </label>

          <label className="mb-5 block text-xs font-semibold text-slate-400">
            Password
            <div className="relative mt-1.5">
              <Lock className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-500" />
              <input
                type="password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="w-full rounded-xl border border-slate-700 bg-slate-950 py-2.5 pl-10 pr-3 text-sm text-white focus:border-teal-400 focus:outline-none"
              />
            </div>
          </label>

          <button
            type="submit"
            disabled={busy}
            className="flex w-full items-center justify-center gap-2 rounded-xl bg-teal-600 py-3 text-sm font-bold text-white hover:bg-teal-500 disabled:opacity-60"
          >
            {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
            Sign in
          </button>
        </form>
      </div>
    </div>
  );
}
