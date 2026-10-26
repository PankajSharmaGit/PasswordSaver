import { useQuery } from '@tanstack/react-query';
import { fetchAdminDashboard } from '../shared/adminApi';

function statusClass(status: string) {
  if (status === 'paid') return 'bg-teal-500/20 text-teal-300';
  if (status === 'failed') return 'bg-rose-500/20 text-rose-300';
  return 'bg-slate-700 text-slate-300';
}

export function AdminPaymentsPage() {
  const { data, isLoading, error } = useQuery({
    queryKey: ['admin-dashboard'],
    queryFn: fetchAdminDashboard,
  });

  if (isLoading) return <p className="text-slate-400">Loading payments…</p>;
  if (error) {
    return (
      <p className="text-rose-300">
        {error instanceof Error ? error.message : 'Failed to load payments'}
      </p>
    );
  }

  const txns = data!.transactions;

  return (
    <div>
      <h1 className="text-2xl font-bold text-white">Payments</h1>
      <p className="mt-1 text-sm text-slate-400">
        Razorpay orders via Cloud Functions — last {txns.length} transactions
      </p>

      <div className="mt-6 overflow-x-auto rounded-2xl border border-slate-800">
        <table className="min-w-full text-left text-sm">
          <thead className="bg-slate-900/80 text-xs uppercase text-slate-500">
            <tr>
              <th className="px-4 py-3">Order</th>
              <th className="px-4 py-3">User email</th>
              <th className="px-4 py-3">Plan</th>
              <th className="px-4 py-3">Amount</th>
              <th className="px-4 py-3">Status</th>
              <th className="px-4 py-3">Date</th>
            </tr>
          </thead>
          <tbody>
            {txns.length === 0 ? (
              <tr>
                <td colSpan={6} className="px-4 py-8 text-center text-slate-500">
                  No payment orders yet
                </td>
              </tr>
            ) : (
              txns.map((t) => (
                <tr key={t.orderId} className="border-t border-slate-800/80">
                  <td className="px-4 py-3 font-mono text-xs text-slate-300">
                    {t.orderId.slice(0, 18)}…
                  </td>
                  <td className="px-4 py-3">
                    <p className="text-sm text-white">
                      {t.userEmail?.trim() || '—'}
                    </p>
                    {t.userDisplayName?.trim() ? (
                      <p className="text-xs text-slate-500">
                        {t.userDisplayName}
                      </p>
                    ) : null}
                    <p className="font-mono text-[10px] text-slate-600">
                      {t.userId ? `${t.userId.slice(0, 10)}…` : ''}
                    </p>
                  </td>
                  <td className="px-4 py-3 text-slate-300">
                    {t.months ? `${t.months} months` : '—'}
                  </td>
                  <td className="px-4 py-3 text-white">
                    {t.currency === 'USD' && t.priceUsd != null
                      ? `$${t.priceUsd.toFixed(2)}`
                      : t.priceInr != null
                        ? `₹${t.priceInr}`
                        : '—'}
                  </td>
                  <td className="px-4 py-3">
                    <span
                      className={`rounded-full px-2 py-0.5 text-xs font-semibold ${statusClass(t.status)}`}
                    >
                      {t.status}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-xs text-slate-500">
                    {(t.paidAt ?? t.createdAt)?.slice(0, 16).replace('T', ' ') ??
                      '—'}
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
