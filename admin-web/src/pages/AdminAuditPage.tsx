import { useQuery } from '@tanstack/react-query';
import { fetchAdminDashboard } from '../shared/adminApi';
import { AUDIT_ACTION_LABELS } from '../shared/types';

function formatPayload(payload: Record<string, unknown>): string {
  const parts: string[] = [];
  if (typeof payload.months === 'number') {
    parts.push(`${payload.months}-month plan`);
  }
  if (payload.expiresAt) {
    parts.push(`expires ${String(payload.expiresAt).slice(0, 10)}`);
  }
  if (payload.blocked === true) parts.push('blocked');
  if (payload.blocked === false) parts.push('unblocked');
  if (payload.reason) parts.push(`reason: ${String(payload.reason)}`);
  const before = payload.before as Record<string, unknown> | undefined;
  const after = payload.after as Record<string, unknown> | undefined;
  if (before?.planLabel && after?.planLabel) {
    parts.push(`${String(before.planLabel)} → ${String(after.planLabel)}`);
  }
  return parts.length ? parts.join(' · ') : '—';
}

export function AdminAuditPage() {
  const { data, isLoading, error } = useQuery({
    queryKey: ['admin-dashboard'],
    queryFn: fetchAdminDashboard,
  });

  if (isLoading) return <p className="text-slate-400">Loading activity…</p>;
  if (error) {
    return (
      <p className="text-rose-300">
        {error instanceof Error ? error.message : 'Failed to load activity log'}
      </p>
    );
  }

  const logs = data!.auditLogs;

  return (
    <div>
      <h1 className="text-2xl font-bold text-white">Activity log</h1>
      <p className="mt-1 text-sm text-slate-400">
        Admin actions on users — last {logs.length} entries (stored in
        Firestore, not deleted when user is removed)
      </p>

      <div className="mt-6 overflow-x-auto rounded-2xl border border-slate-800">
        <table className="min-w-full text-left text-sm">
          <thead className="bg-slate-900/80 text-xs uppercase text-slate-500">
            <tr>
              <th className="px-4 py-3">When</th>
              <th className="px-4 py-3">Action</th>
              <th className="px-4 py-3">Target user</th>
              <th className="px-4 py-3">Admin</th>
              <th className="px-4 py-3">Details</th>
            </tr>
          </thead>
          <tbody>
            {logs.length === 0 ? (
              <tr>
                <td colSpan={5} className="px-4 py-8 text-center text-slate-500">
                  No admin actions recorded yet
                </td>
              </tr>
            ) : (
              logs.map((log) => (
                <tr key={log.id} className="border-t border-slate-800/80">
                  <td className="whitespace-nowrap px-4 py-3 text-xs text-slate-500">
                    {log.createdAt
                      ? log.createdAt.replace('T', ' ').slice(0, 19)
                      : '—'}
                  </td>
                  <td className="px-4 py-3">
                    <span className="rounded-full bg-slate-800 px-2 py-0.5 text-xs font-semibold text-slate-200">
                      {AUDIT_ACTION_LABELS[log.action] ?? log.action}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    <p className="font-medium text-white">
                      {log.targetDisplayName || log.targetEmail || '—'}
                    </p>
                    <p className="text-xs text-slate-500">
                      {log.targetEmail ?? log.targetUserId ?? '—'}
                    </p>
                  </td>
                  <td className="px-4 py-3 text-xs text-slate-400">
                    {log.adminEmail || log.adminUid}
                  </td>
                  <td className="max-w-xs px-4 py-3 text-xs text-slate-400">
                    {formatPayload(log.payload)}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
