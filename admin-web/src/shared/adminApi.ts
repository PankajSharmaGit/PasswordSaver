import { httpsCallable } from 'firebase/functions';
import { functions } from './firebase';
import {
  defaultCatalog,
  mapAuditLog,
  mapStats,
  mapTransaction,
  mapUserRow,
  parseCatalog,
  parseGstConfig,
  type AdminDashboardData,
  type SubscriptionCatalog,
  type SubscriptionGstConfig,
} from './types';

function asMap(data: unknown): Record<string, unknown> {
  return data && typeof data === 'object'
    ? (data as Record<string, unknown>)
    : {};
}

export async function fetchAdminDashboard(): Promise<AdminDashboardData> {
  const result = await httpsCallable(functions, 'getAdminDashboard')({});
  const data = asMap(result.data);
  const catalog = parseCatalog(data.catalog ?? { plans: data.plans });
  return {
    stats: mapStats(data.stats),
    users: ((data.users as unknown[]) ?? []).map(mapUserRow),
    transactions: ((data.transactions as unknown[]) ?? []).map(mapTransaction),
    auditLogs: ((data.auditLogs as unknown[]) ?? []).map(mapAuditLog),
    catalog,
  };
}

export async function saveSubscriptionCatalog(
  catalog: SubscriptionCatalog,
): Promise<SubscriptionCatalog> {
  const result = await httpsCallable(
    functions,
    'adminUpdateSubscriptionConfig',
  )(catalog);
  const data = asMap(result.data);
  if (data.catalog) return parseCatalog(data.catalog);
  return catalog;
}

export async function saveSubscriptionGst(
  gst: SubscriptionGstConfig,
): Promise<SubscriptionGstConfig> {
  const result = await httpsCallable(functions, 'adminUpdateSubscriptionGst')(gst);
  const data = asMap(result.data);
  if (data.gst) return parseGstConfig(data.gst);
  return gst;
}

export async function updateUserPlan(input: {
  targetUserId: string;
  months?: number;
  lifetimeFree?: boolean;
  revokePlan?: boolean;
}): Promise<void> {
  await httpsCallable(functions, 'adminUpdateUserPlan')(input);
}

export async function deleteUser(input: {
  targetUserId: string;
  reason?: string;
}): Promise<void> {
  await httpsCallable(functions, 'adminDeleteUser')(input);
}

export async function setUserBlocked(input: {
  targetUserId: string;
  blocked: boolean;
}): Promise<void> {
  await httpsCallable(functions, 'adminSetUserBlocked')(input);
}

export { defaultCatalog };
