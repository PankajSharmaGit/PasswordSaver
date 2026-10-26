import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Ban, Crown, Loader2, Trash2 } from 'lucide-react';
import { useState } from 'react';
import {
  deleteUser,
  fetchAdminDashboard,
  setUserBlocked,
  updateUserPlan,
} from '../shared/adminApi';
import { PLAN_MONTHS, type AdminUserRow } from '../shared/types';

function UserRowActions({ user }: { user: AdminUserRow }) {
  const qc = useQueryClient();
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [deleteReason, setDeleteReason] = useState('');

  const invalidate = () =>
    void qc.invalidateQueries({ queryKey: ['admin-dashboard'] });

  const blockMut = useMutation({
    mutationFn: (blocked: boolean) =>
      setUserBlocked({ targetUserId: user.uid, blocked }),
    onSuccess: invalidate,
  });

  const planMut = useMutation({
    mutationFn: (input: {
      months?: number;
      lifetimeFree?: boolean;
      revokePlan?: boolean;
    }) => updateUserPlan({ targetUserId: user.uid, ...input }),
    onSuccess: invalidate,
  });

  const deleteMut = useMutation({
    mutationFn: () =>
      deleteUser({
        targetUserId: user.uid,
        reason: deleteReason.trim() || undefined,
      }),
    onSuccess: () => {
      setConfirmDelete(false);
      setDeleteReason('');
      invalidate();
    },
  });

  const busy =
    blockMut.isPending || planMut.isPending || deleteMut.isPending;

  if (confirmDelete) {
    return (
      <div className="max-w-xs space-y-2 rounded-xl border border-rose-800/60 bg-rose-950/30 p-3">
        <p className="text-xs font-semibold text-rose-200">
          Delete {user.email}? This removes vault data permanently.
        </p>
        <input
          type="text"
          value={deleteReason}
          onChange={(e) => setDeleteReason(e.target.value)}
          placeholder="Reason (optional, logged)"
          className="w-full rounded-lg border border-slate-700 bg-slate-900 px-2 py-1.5 text-xs text-white"
        />
        <div className="flex gap-2">
          <button
            type="button"
            disabled={busy}
            onClick={() => deleteMut.mutate()}
            className="rounded-lg bg-rose-600 px-2 py-1 text-xs font-semibold text-white hover:bg-rose-500 disabled:opacity-50"
          >
            {deleteMut.isPending ? 'Deleting…' : 'Confirm delete'}
          </button>
          <button
            type="button"
            disabled={busy}
            onClick={() => {
              setConfirmDelete(false);
              setDeleteReason('');
            }}
            className="rounded-lg border border-slate-600 px-2 py-1 text-xs text-slate-300"
          >
            Cancel
          </button>
        </div>
        {deleteMut.error instanceof Error && (
          <p className="text-xs text-rose-300">{deleteMut.error.message}</p>
        )}
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-2">
      <div className="flex flex-wrap gap-1.5">
        {PLAN_MONTHS.map((m) => (
          <button
            key={m}
            type="button"
            disabled={busy}
            onClick={() => planMut.mutate({ months: Number(m) })}
            className="rounded-lg border border-slate-700 px-2 py-1 text-xs font-semibold text-teal-300 hover:bg-teal-500/10 disabled:opacity-50"
          >
            {m}m
          </button>
        ))}
        <button
          type="button"
          disabled={busy || user.isLifetimeFree}
          onClick={() => planMut.mutate({ lifetimeFree: true })}
          className="inline-flex items-center gap-1 rounded-lg border border-amber-700/50 px-2 py-1 text-xs font-semibold text-amber-300 hover:bg-amber-500/10 disabled:opacity-50"
        >
          <Crown className="h-3 w-3" /> Lifetime
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={() => planMut.mutate({ revokePlan: true })}
          className="rounded-lg border border-slate-600 px-2 py-1 text-xs font-semibold text-slate-400 hover:bg-white/5 disabled:opacity-50"
        >
          Revoke
        </button>
      </div>
      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          disabled={busy}
          onClick={() => blockMut.mutate(!user.isBlocked)}
          className="inline-flex items-center gap-1 rounded-lg border border-rose-700/50 px-2 py-1 text-xs font-semibold text-rose-300 hover:bg-rose-500/10 disabled:opacity-50"
        >
          {busy ? (
            <Loader2 className="h-3 w-3 animate-spin" />
          ) : (
            <Ban className="h-3 w-3" />
          )}
          {user.isBlocked ? 'Unblock' : 'Block'}
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={() => setConfirmDelete(true)}
          className="inline-flex items-center gap-1 rounded-lg border border-rose-900/80 px-2 py-1 text-xs font-semibold text-rose-400 hover:bg-rose-950/50 disabled:opacity-50"
        >
          <Trash2 className="h-3 w-3" /> Delete
        </button>
      </div>
      {(planMut.error || blockMut.error) instanceof Error && (
        <p className="text-xs text-rose-300">
          {(planMut.error || blockMut.error)?.message}
        </p>
      )}
    </div>
  );
}

export function AdminUsersPage() {
  const { data, isLoading, error } = useQuery({
    queryKey: ['admin-dashboard'],
    queryFn: fetchAdminDashboard,
  });

  if (isLoading) return <p className="text-slate-400">Loading users…</p>;
  if (error) {
    return (
      <p className="text-rose-300">
        {error instanceof Error ? error.message : 'Failed to load users'}
      </p>
    );
  }

  const users = data!.users;

  return (
    <div>
      <h1 className="text-2xl font-bold text-white">Users</h1>
      <p className="mt-1 text-sm text-slate-400">
        {users.length} registered accounts — plan changes, blocks, and deletes
        are recorded in Activity log
      </p>

      <div className="mt-6 overflow-x-auto rounded-2xl border border-slate-800">
        <table className="min-w-full text-left text-sm">
          <thead className="bg-slate-900/80 text-xs uppercase text-slate-500">
            <tr>
              <th className="px-4 py-3">User</th>
              <th className="px-4 py-3">Plan</th>
              <th className="px-4 py-3">Country</th>
              <th className="px-4 py-3">Last active</th>
              <th className="px-4 py-3">Expires</th>
              <th className="px-4 py-3">Actions</th>
            </tr>
          </thead>
          <tbody>
            {users.map((u) => (
              <tr key={u.uid} className="border-t border-slate-800/80">
                <td className="px-4 py-3">
                  <p className="font-semibold text-white">
                    {u.displayName || u.email}
                  </p>
                  <p className="text-xs text-slate-500">{u.email}</p>
                </td>
                <td className="px-4 py-3">
                  <span
                    className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
                      u.isBlocked
                        ? 'bg-rose-500/20 text-rose-300'
                        : u.hasActiveAccess
                          ? 'bg-teal-500/20 text-teal-300'
                          : 'bg-slate-700 text-slate-300'
                    }`}
                  >
                    {u.planLabel}
                  </span>
                </td>
                <td className="px-4 py-3 text-slate-400">
                  {u.countryName ?? u.countryCode ?? '—'}
                </td>
                <td className="px-4 py-3 text-xs text-slate-500">
                  {(u.lastActiveAt ?? u.createdAt)
                    ?.slice(0, 16)
                    .replace('T', ' ') ?? '—'}
                </td>
                <td className="px-4 py-3 text-xs text-slate-500">
                  {u.isLifetimeFree
                    ? 'Never'
                    : (u.subscriptionExpiresAt?.slice(0, 10) ?? '—')}
                </td>
                <td className="px-4 py-3">
                  <UserRowActions user={u} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
