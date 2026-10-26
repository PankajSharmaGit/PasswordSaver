export type PlanEntry = {
  priceInr: number;
  priceUsd: number;
  maxAttachmentFiles: number;
};

export type SubscriptionGstConfig = {
  gstPercent: number;
  platformGstin: string;
  platformStateCode: string;
  platformLegalName: string;
  platformAddress: string;
};

export type SubscriptionCatalog = {
  schemaVersion?: number;
  inrToUsdRate: number;
  internationalMultiplier: number;
  plans: Record<string, PlanEntry>;
  fileUpgradePlans: Record<string, PlanEntry>;
  trial: { days: number; maxAttachmentFiles: number };
  maxAttachmentBytes: number;
  lifetimeFreeMaxAttachmentFiles?: number;
  gst?: SubscriptionGstConfig;
};

export type AdminStats = {
  totalUsers: number;
  trialActive: number;
  paidActive: number;
  blocked: number;
  expired: number;
  successTransactions: number;
  failedTransactions: number;
  pendingTransactions: number;
};

export type AdminUserRow = {
  uid: string;
  email: string;
  displayName: string;
  userId: string;
  planLabel: string;
  isBlocked: boolean;
  isTrialActive: boolean;
  hasActiveAccess: boolean;
  isLifetimeFree: boolean;
  primaryMobile?: string | null;
  subscriptionPlanMonths?: number | null;
  subscriptionExpiresAt?: string | null;
  countryCode?: string | null;
  countryName?: string | null;
  createdAt?: string | null;
  lastActiveAt?: string | null;
};

export type AdminTransaction = {
  orderId: string;
  userId: string;
  userEmail?: string | null;
  userDisplayName?: string | null;
  status: string;
  months?: number | null;
  priceInr?: number | null;
  priceUsd?: number | null;
  currency?: string | null;
  paymentId?: string | null;
  failReason?: string | null;
  createdAt?: string | null;
  paidAt?: string | null;
};

export type AdminDashboardData = {
  stats: AdminStats;
  users: AdminUserRow[];
  transactions: AdminTransaction[];
  auditLogs: AdminAuditLog[];
  catalog: SubscriptionCatalog;
};

export type AdminAuditLog = {
  id: string;
  action: string;
  adminUid: string;
  adminEmail: string;
  targetUserId?: string | null;
  targetEmail?: string | null;
  targetDisplayName?: string | null;
  payload: Record<string, unknown>;
  createdAt?: string | null;
};

export const AUDIT_ACTION_LABELS: Record<string, string> = {
  grant_plan: 'Plan granted',
  grant_lifetime_free: 'Lifetime free granted',
  revoke_plan: 'Plan revoked',
  block_user: 'User blocked',
  unblock_user: 'User unblocked',
  delete_user: 'User deleted',
};

export const PLAN_MONTHS = ['3', '6', '12', '24'] as const;

export function defaultGstConfig(): SubscriptionGstConfig {
  return {
    gstPercent: 18,
    platformGstin: '',
    platformStateCode: '',
    platformLegalName: 'PasswordSaver',
    platformAddress: '',
  };
}

export function parseGstConfig(raw: unknown): SubscriptionGstConfig {
  const def = defaultGstConfig();
  if (!raw || typeof raw !== 'object') return def;
  const m = raw as Record<string, unknown>;
  const pct = Number(m.gstPercent ?? def.gstPercent);
  return {
    gstPercent: Number.isFinite(pct) && pct >= 0 ? Math.min(40, pct) : def.gstPercent,
    platformGstin: String(m.platformGstin ?? def.platformGstin).trim().toUpperCase(),
    platformStateCode: String(m.platformStateCode ?? def.platformStateCode).trim().slice(0, 2),
    platformLegalName: String(m.platformLegalName ?? def.platformLegalName).trim() || def.platformLegalName,
    platformAddress: String(m.platformAddress ?? def.platformAddress).trim(),
  };
}

export function inrWithGst(taxableInr: number, gst: SubscriptionGstConfig): number {
  if (gst.gstPercent <= 0) return taxableInr;
  return taxableInr + Math.round((taxableInr * gst.gstPercent) / 100);
}

export function computeUsdFromInr(
  priceInr: number,
  catalog: Pick<SubscriptionCatalog, 'inrToUsdRate' | 'internationalMultiplier'>,
): number {
  const rate = catalog.inrToUsdRate ?? 0.012;
  const mult = catalog.internationalMultiplier ?? 1.5;
  return Math.round(priceInr * rate * mult * 100) / 100;
}

export function defaultCatalog(): SubscriptionCatalog {
  const base = {
    inrToUsdRate: 0.012,
    internationalMultiplier: 1.5,
  };
  const catalog: SubscriptionCatalog = {
    schemaVersion: 3,
    ...base,
    plans: {},
    fileUpgradePlans: {},
    gst: defaultGstConfig(),
    trial: { days: 15, maxAttachmentFiles: 8 },
    maxAttachmentBytes: 1048576,
    lifetimeFreeMaxAttachmentFiles: 25,
  };
  for (const months of PLAN_MONTHS) {
    const inr = { '3': 100, '6': 180, '12': 350, '24': 650 }[months] ?? 100;
    const files = { '3': 12, '6': 15, '12': 20, '24': 25 }[months] ?? 12;
    catalog.plans[months] = {
      priceInr: inr,
      priceUsd: computeUsdFromInr(inr, catalog),
      maxAttachmentFiles: files,
    };
    const fileInr = { '3': 70, '6': 120, '12': 200, '24': 350 }[months] ?? 70;
    const fileFiles = { '3': 30, '6': 50, '12': 100, '24': 200 }[months] ?? 30;
    catalog.fileUpgradePlans[months] = {
      priceInr: fileInr,
      priceUsd: computeUsdFromInr(fileInr, catalog),
      maxAttachmentFiles: fileFiles,
    };
  }
  return catalog;
}

function mapPlanEntryRaw(raw: unknown): PlanEntry {
  const m = (raw ?? {}) as Record<string, unknown>;
  return {
    priceInr: Number(m.priceInr ?? 0),
    priceUsd: Number(m.priceUsd ?? 0),
    maxAttachmentFiles: Number(m.maxAttachmentFiles ?? 0),
  };
}

export function parseCatalog(raw: unknown): SubscriptionCatalog {
  const def = defaultCatalog();
  if (!raw || typeof raw !== 'object') return def;
  const m = raw as Record<string, unknown>;
  const inrToUsdRate = Number(m.inrToUsdRate ?? def.inrToUsdRate);
  const internationalMultiplier = Number(
    m.internationalMultiplier ?? def.internationalMultiplier,
  );
  const shell = { inrToUsdRate, internationalMultiplier };
  const plans: Record<string, PlanEntry> = { ...def.plans };
  const fileUpgradePlans: Record<string, PlanEntry> = { ...def.fileUpgradePlans };

  if (m.plans && typeof m.plans === 'object') {
    for (const [k, v] of Object.entries(m.plans as Record<string, unknown>)) {
      const entry = mapPlanEntryRaw(v);
      plans[String(k)] = {
        ...entry,
        priceUsd:
          entry.priceUsd > 0
            ? entry.priceUsd
            : computeUsdFromInr(entry.priceInr, shell),
      };
    }
  }
  if (m.fileUpgradePlans && typeof m.fileUpgradePlans === 'object') {
    for (const [k, v] of Object.entries(
      m.fileUpgradePlans as Record<string, unknown>,
    )) {
      const entry = mapPlanEntryRaw(v);
      fileUpgradePlans[String(k)] = {
        ...entry,
        priceUsd:
          entry.priceUsd > 0
            ? entry.priceUsd
            : computeUsdFromInr(entry.priceInr, shell),
      };
    }
  }

  const trialRaw = (m.trial ?? {}) as Record<string, unknown>;
  return {
    schemaVersion: Number(m.schemaVersion ?? 3),
    inrToUsdRate,
    internationalMultiplier,
    plans,
    fileUpgradePlans,
    gst: parseGstConfig(m.gst),
    trial: {
      days: Number(trialRaw.days ?? def.trial.days),
      maxAttachmentFiles: Number(
        trialRaw.maxAttachmentFiles ?? def.trial.maxAttachmentFiles,
      ),
    },
    maxAttachmentBytes: Number(m.maxAttachmentBytes ?? def.maxAttachmentBytes),
    lifetimeFreeMaxAttachmentFiles: Number(
      m.lifetimeFreeMaxAttachmentFiles ?? def.lifetimeFreeMaxAttachmentFiles,
    ),
  };
}

export function mapUserRow(raw: unknown): AdminUserRow {
  const m = (raw ?? {}) as Record<string, unknown>;
  return {
    uid: String(m.uid ?? ''),
    email: String(m.email ?? ''),
    displayName: String(m.displayName ?? ''),
    userId: String(m.userId ?? ''),
    planLabel: String(m.planLabel ?? '—'),
    isBlocked: m.isBlocked === true,
    isTrialActive: m.isTrialActive !== false,
    hasActiveAccess: m.hasActiveAccess === true,
    isLifetimeFree: m.isLifetimeFree === true,
    primaryMobile: m.primaryMobile != null ? String(m.primaryMobile) : null,
    subscriptionPlanMonths:
      m.subscriptionPlanMonths != null
        ? Number(m.subscriptionPlanMonths)
        : null,
    subscriptionExpiresAt:
      m.subscriptionExpiresAt != null
        ? String(m.subscriptionExpiresAt)
        : null,
    countryCode: m.countryCode != null ? String(m.countryCode) : null,
    countryName: m.countryName != null ? String(m.countryName) : null,
    createdAt: m.createdAt != null ? String(m.createdAt) : null,
    lastActiveAt: m.lastActiveAt != null ? String(m.lastActiveAt) : null,
  };
}

export function mapTransaction(raw: unknown): AdminTransaction {
  const m = (raw ?? {}) as Record<string, unknown>;
  return {
    orderId: String(m.orderId ?? ''),
    userId: String(m.userId ?? ''),
    userEmail: m.userEmail != null ? String(m.userEmail) : null,
    userDisplayName:
      m.userDisplayName != null ? String(m.userDisplayName) : null,
    status: String(m.status ?? 'created'),
    months: m.months != null ? Number(m.months) : null,
    priceInr: m.priceInr != null ? Number(m.priceInr) : null,
    priceUsd: m.priceUsd != null ? Number(m.priceUsd) : null,
    currency: m.currency != null ? String(m.currency) : null,
    paymentId: m.paymentId != null ? String(m.paymentId) : null,
    failReason: m.failReason != null ? String(m.failReason) : null,
    createdAt: m.createdAt != null ? String(m.createdAt) : null,
    paidAt: m.paidAt != null ? String(m.paidAt) : null,
  };
}

export function mapAuditLog(raw: unknown): AdminAuditLog {
  const m = (raw ?? {}) as Record<string, unknown>;
  const payload =
    m.payload && typeof m.payload === 'object'
      ? (m.payload as Record<string, unknown>)
      : {};
  return {
    id: String(m.id ?? ''),
    action: String(m.action ?? ''),
    adminUid: String(m.adminUid ?? ''),
    adminEmail: String(m.adminEmail ?? ''),
    targetUserId: m.targetUserId != null ? String(m.targetUserId) : null,
    targetEmail: m.targetEmail != null ? String(m.targetEmail) : null,
    targetDisplayName:
      m.targetDisplayName != null ? String(m.targetDisplayName) : null,
    payload,
    createdAt: m.createdAt != null ? String(m.createdAt) : null,
  };
}

export function mapStats(raw: unknown): AdminStats {
  const m = (raw ?? {}) as Record<string, unknown>;
  return {
    totalUsers: Number(m.totalUsers ?? 0),
    trialActive: Number(m.trialActive ?? 0),
    paidActive: Number(m.paidActive ?? 0),
    blocked: Number(m.blocked ?? 0),
    expired: Number(m.expired ?? 0),
    successTransactions: Number(m.successTransactions ?? 0),
    failedTransactions: Number(m.failedTransactions ?? 0),
    pendingTransactions: Number(m.pendingTransactions ?? 0),
  };
}
