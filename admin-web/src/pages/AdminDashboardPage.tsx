import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { ArrowRight, Crown, Receipt, Users } from 'lucide-react';
import { fetchAdminDashboard } from '../shared/adminApi';

export function AdminDashboardPage() {
  const { data, isLoading, error } = useQuery({
    queryKey: ['admin-dashboard'],
    queryFn: fetchAdminDashboard,
  });

  if (isLoading) return <p className="text-slate-400">Loading dashboard…</p>;
  if (error) {
    return (
      <p className="text-rose-300">
        {error instanceof Error ? error.message : 'Failed to load dashboard'}
      </p>
    );
  }

  const stats = data!.stats;
  const cards = [
    {
      title: 'Total users',
      value: stats.totalUsers,
      hint: `${stats.trialActive} trial · ${stats.paidActive} paid`,
      to: '/admin/users',
      icon: Users,
    },
    {
      title: 'Pricing plans',
      value: Object.keys(data!.catalog.plans).length,
      hint: 'Dynamic — app reads from Firestore',
      to: '/admin/plans',
      icon: Crown,
    },
    {
      title: 'Payments',
      value: stats.successTransactions + stats.failedTransactions + stats.pendingTransactions,
      hint: `${stats.successTransactions} paid · ${stats.failedTransactions} failed`,
      to: '/admin/payments',
      icon: Receipt,
    },
  ];

  return (
    <div>
      <h1 className="text-2xl font-bold text-white">Overview</h1>
      <p className="mt-1 text-sm text-slate-400">
        PasswordSaver admin — pricing changes apply to the mobile app on next catalog refresh.
      </p>

      <div className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {cards.map((card) => {
          const Icon = card.icon;
          return (
            <Link
              key={card.title}
              to={card.to}
              className="group rounded-2xl border border-slate-800 bg-slate-900/50 p-5 transition hover:border-teal-500/40"
            >
              <div className="flex items-start justify-between">
                <div className="rounded-xl bg-teal-500/10 p-2 text-teal-300">
                  <Icon className="h-5 w-5" />
                </div>
                <ArrowRight className="h-4 w-4 text-slate-600 group-hover:text-teal-300" />
              </div>
              <p className="mt-4 text-3xl font-bold text-white">{card.value}</p>
              <p className="mt-1 text-sm font-semibold text-slate-200">{card.title}</p>
              <p className="mt-1 text-xs text-slate-500">{card.hint}</p>
            </Link>
          );
        })}
      </div>

      <div className="mt-8 grid gap-4 sm:grid-cols-4">
        {[
          ['Trial active', stats.trialActive],
          ['Paid active', stats.paidActive],
          ['Blocked', stats.blocked],
          ['Expired', stats.expired],
        ].map(([label, value]) => (
          <div
            key={label}
            className="rounded-xl border border-slate-800 bg-slate-900/40 px-4 py-3"
          >
            <p className="text-xs text-slate-500">{label}</p>
            <p className="text-xl font-bold text-white">{value}</p>
          </div>
        ))}
      </div>
    </div>
  );
}
