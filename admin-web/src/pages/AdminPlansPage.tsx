import { type FormEvent, useEffect, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Crown, Globe, Loader2, Save } from 'lucide-react';
import { fetchAdminDashboard, saveSubscriptionCatalog, saveSubscriptionGst } from '../shared/adminApi';
import {
  PLAN_MONTHS,
  computeUsdFromInr,
  defaultCatalog,
  defaultGstConfig,
  inrWithGst,
  type PlanEntry,
  type SubscriptionCatalog,
  type SubscriptionGstConfig,
} from '../shared/types';

function PlanFields({
  title,
  entry,
  catalog,
  gst,
  onChange,
}: {
  title: string;
  entry: PlanEntry;
  catalog: Pick<SubscriptionCatalog, 'inrToUsdRate' | 'internationalMultiplier'>;
  gst: SubscriptionGstConfig;
  onChange: (next: PlanEntry) => void;
}) {
  const suggestedUsd = computeUsdFromInr(entry.priceInr, catalog);
  const indiaTotal = inrWithGst(entry.priceInr, gst);

  return (
    <section className="rounded-2xl border border-slate-800 bg-slate-900/50 p-5">
      <h2 className="mb-4 text-lg font-bold text-white">{title}</h2>
      <div className="grid gap-3 sm:grid-cols-3">
        <label className="block text-xs font-semibold text-slate-400">
          India price (₹ excl. GST)
          <input
            type="number"
            min={1}
            value={entry.priceInr}
            onChange={(e) => {
              const priceInr = Number(e.target.value) || 0;
              onChange({
                ...entry,
                priceInr,
                priceUsd: computeUsdFromInr(priceInr, catalog),
              });
            }}
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-white"
          />
          <span className="mt-1 block text-[11px] font-normal text-teal-400/90">
            Checkout: ₹{indiaTotal} incl. {gst.gstPercent}% GST
          </span>
        </label>
        <label className="block text-xs font-semibold text-slate-400">
          International price ($)
          <input
            type="number"
            min={0.5}
            step={0.01}
            value={entry.priceUsd}
            onChange={(e) =>
              onChange({ ...entry, priceUsd: Number(e.target.value) || 0 })
            }
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-white"
          />
          <span className="mt-1 block text-[11px] font-normal text-slate-500">
            Auto: ${suggestedUsd.toFixed(2)} (INR × rate ×{' '}
            {catalog.internationalMultiplier}×)
          </span>
        </label>
        <label className="block text-xs font-semibold text-slate-400">
          Max attachment files
          <input
            type="number"
            min={0}
            value={entry.maxAttachmentFiles}
            onChange={(e) =>
              onChange({
                ...entry,
                maxAttachmentFiles: Number(e.target.value) || 0,
              })
            }
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-white"
          />
        </label>
      </div>
    </section>
  );
}

function recalcAllUsd(
  catalog: SubscriptionCatalog,
  rate: number,
  mult: number,
): SubscriptionCatalog {
  const shell = { inrToUsdRate: rate, internationalMultiplier: mult };
  const plans = { ...catalog.plans };
  const fileUpgradePlans = { ...catalog.fileUpgradePlans };
  for (const months of PLAN_MONTHS) {
    if (plans[months]) {
      plans[months] = {
        ...plans[months],
        priceUsd: computeUsdFromInr(plans[months].priceInr, shell),
      };
    }
    if (fileUpgradePlans[months]) {
      fileUpgradePlans[months] = {
        ...fileUpgradePlans[months],
        priceUsd: computeUsdFromInr(fileUpgradePlans[months].priceInr, shell),
      };
    }
  }
  return {
    ...catalog,
    inrToUsdRate: rate,
    internationalMultiplier: mult,
    plans,
    fileUpgradePlans,
  };
}

export function AdminPlansPage() {
  const qc = useQueryClient();
  const { data, isLoading, error } = useQuery({
    queryKey: ['admin-dashboard'],
    queryFn: fetchAdminDashboard,
  });

  const [draft, setDraft] = useState<SubscriptionCatalog>(defaultCatalog());
  const [savedMsg, setSavedMsg] = useState<string | null>(null);

  useEffect(() => {
    if (data?.catalog) setDraft(structuredClone(data.catalog));
  }, [data?.catalog]);

  const saveMut = useMutation({
    mutationFn: async () => {
      const gst = draft.gst ?? defaultGstConfig();
      await saveSubscriptionGst(gst);
      return saveSubscriptionCatalog({ ...draft, gst });
    },
    onSuccess: (catalog) => {
      setDraft(catalog);
      setSavedMsg('Pricing saved — mobile app will pick this up on next refresh.');
      void qc.invalidateQueries({ queryKey: ['admin-dashboard'] });
      setTimeout(() => setSavedMsg(null), 4000);
    },
  });

  function onSubmit(e: FormEvent) {
    e.preventDefault();
    saveMut.mutate();
  }

  const intlShell = {
    inrToUsdRate: draft.inrToUsdRate,
    internationalMultiplier: draft.internationalMultiplier,
  };
  const gst = draft.gst ?? defaultGstConfig();

  if (isLoading) return <p className="text-slate-400">Loading plans…</p>;
  if (error) {
    return (
      <p className="text-rose-300">
        {error instanceof Error ? error.message : 'Failed to load plans'}
      </p>
    );
  }

  return (
    <form onSubmit={onSubmit}>
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-bold text-white">
            <Crown className="h-6 w-6 text-amber-300" />
            Pricing & plans
          </h1>
          <p className="mt-1 max-w-2xl text-sm text-slate-400">
            India users pay in INR. Other countries pay in USD at +50% on the
            converted base rate. Razorpay checkout uses the server price at
            payment time based on the user&apos;s saved country.
          </p>
        </div>
        <button
          type="submit"
          disabled={saveMut.isPending}
          className="inline-flex items-center gap-2 rounded-xl bg-teal-600 px-4 py-2.5 text-sm font-bold text-white hover:bg-teal-500 disabled:opacity-60"
        >
          {saveMut.isPending ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <Save className="h-4 w-4" />
          )}
          Save pricing
        </button>
      </div>

      {savedMsg && (
        <p className="mt-4 rounded-xl border border-teal-500/30 bg-teal-500/10 px-4 py-3 text-sm text-teal-200">
          {savedMsg}
        </p>
      )}
      {saveMut.error && (
        <p className="mt-4 rounded-xl border border-rose-500/30 bg-rose-500/10 px-4 py-3 text-sm text-rose-200">
          {saveMut.error instanceof Error
            ? saveMut.error.message
            : 'Save failed'}
        </p>
      )}

      <section className="mt-8 rounded-2xl border border-slate-800 bg-slate-900/50 p-5">
        <h2 className="mb-1 flex items-center gap-2 text-lg font-bold text-white">
          <Globe className="h-5 w-5 text-sky-300" />
          International pricing
        </h2>
        <p className="mb-4 text-xs text-slate-500">
          USD = INR × rate × multiplier. Default: ₹100 → $1.20 base → $1.80
          international (1.5×).
        </p>
        <div className="grid gap-3 sm:grid-cols-2">
          <label className="block text-xs font-semibold text-slate-400">
            INR → USD rate
            <input
              type="number"
              min={0.001}
              step={0.001}
              value={draft.inrToUsdRate}
              onChange={(e) => {
                const rate = Number(e.target.value) || 0.012;
                setDraft((d) => recalcAllUsd(d, rate, d.internationalMultiplier));
              }}
              className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-white"
            />
          </label>
          <label className="block text-xs font-semibold text-slate-400">
            International multiplier (+50% = 1.5)
            <input
              type="number"
              min={1}
              step={0.1}
              value={draft.internationalMultiplier}
              onChange={(e) => {
                const mult = Number(e.target.value) || 1.5;
                setDraft((d) => recalcAllUsd(d, d.inrToUsdRate, mult));
              }}
              className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-white"
            />
          </label>
        </div>
      </section>

      <section className="mt-6 rounded-2xl border border-slate-800 bg-slate-900/50 p-5">
        <h2 className="mb-1 text-lg font-bold text-white">India GST (Razorpay)</h2>
        <p className="mb-4 text-xs text-slate-500">
          Catalog INR prices are taxable amount. India checkout charges price + GST
          (same as Snapbilling). International USD has no GST.
        </p>
        <div className="grid gap-3 sm:grid-cols-2">
          <label className="block text-xs font-semibold text-slate-400">
            GST %
            <input
              type="number"
              min={0}
              max={40}
              step={0.5}
              value={gst.gstPercent}
              onChange={(e) =>
                setDraft((d) => ({
                  ...d,
                  gst: {
                    ...(d.gst ?? defaultGstConfig()),
                    gstPercent: Number(e.target.value) || 0,
                  },
                }))
              }
              className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-white"
            />
          </label>
          <label className="block text-xs font-semibold text-slate-400">
            Legal name (invoice)
            <input
              type="text"
              value={gst.platformLegalName}
              onChange={(e) =>
                setDraft((d) => ({
                  ...d,
                  gst: {
                    ...(d.gst ?? defaultGstConfig()),
                    platformLegalName: e.target.value,
                  },
                }))
              }
              className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-white"
            />
          </label>
          <label className="block text-xs font-semibold text-slate-400">
            Platform GSTIN
            <input
              type="text"
              value={gst.platformGstin}
              onChange={(e) =>
                setDraft((d) => ({
                  ...d,
                  gst: {
                    ...(d.gst ?? defaultGstConfig()),
                    platformGstin: e.target.value.toUpperCase(),
                  },
                }))
              }
              className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-white"
            />
          </label>
          <label className="block text-xs font-semibold text-slate-400">
            State code (2 digits)
            <input
              type="text"
              maxLength={2}
              value={gst.platformStateCode}
              onChange={(e) =>
                setDraft((d) => ({
                  ...d,
                  gst: {
                    ...(d.gst ?? defaultGstConfig()),
                    platformStateCode: e.target.value.replace(/\D/g, '').slice(0, 2),
                  },
                }))
              }
              className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-white"
            />
          </label>
        </div>
      </section>

      <div className="mt-8 space-y-4">
        <h2 className="text-sm font-bold uppercase tracking-wide text-slate-500">
          Base plans (India ₹ · International $)
        </h2>
        {PLAN_MONTHS.map((months) => (
          <PlanFields
            key={`base-${months}`}
            title={`${months}-month base plan`}
            entry={
              draft.plans[months] ?? {
                priceInr: 0,
                priceUsd: 0,
                maxAttachmentFiles: 0,
              }
            }
            catalog={intlShell}
            gst={gst}
            onChange={(next) =>
              setDraft((d) => ({
                ...d,
                plans: { ...d.plans, [months]: next },
              }))
            }
          />
        ))}

        <h2 className="pt-4 text-sm font-bold uppercase tracking-wide text-slate-500">
          File upgrade add-ons
        </h2>
        {PLAN_MONTHS.map((months) => (
          <PlanFields
            key={`file-${months}`}
            title={`${months}-month file plan`}
            entry={
              draft.fileUpgradePlans[months] ?? {
                priceInr: 0,
                priceUsd: 0,
                maxAttachmentFiles: 0,
              }
            }
            catalog={intlShell}
            gst={gst}
            onChange={(next) =>
              setDraft((d) => ({
                ...d,
                fileUpgradePlans: { ...d.fileUpgradePlans, [months]: next },
              }))
            }
          />
        ))}

        <section className="rounded-2xl border border-slate-800 bg-slate-900/50 p-5">
          <h2 className="mb-4 text-lg font-bold text-white">Trial & limits</h2>
          <div className="grid gap-3 sm:grid-cols-3">
            <label className="block text-xs font-semibold text-slate-400">
              Trial max files
              <input
                type="number"
                min={0}
                value={draft.trial.maxAttachmentFiles}
                onChange={(e) =>
                  setDraft((d) => ({
                    ...d,
                    trial: {
                      ...d.trial,
                      maxAttachmentFiles: Number(e.target.value) || 0,
                    },
                  }))
                }
                className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-white"
              />
            </label>
            <label className="block text-xs font-semibold text-slate-400">
              Max file size (bytes)
              <input
                type="number"
                min={1}
                value={draft.maxAttachmentBytes}
                onChange={(e) =>
                  setDraft((d) => ({
                    ...d,
                    maxAttachmentBytes: Number(e.target.value) || 1048576,
                  }))
                }
                className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-white"
              />
            </label>
            <label className="block text-xs font-semibold text-slate-400">
              Lifetime free max files
              <input
                type="number"
                min={0}
                value={draft.lifetimeFreeMaxAttachmentFiles ?? 25}
                onChange={(e) =>
                  setDraft((d) => ({
                    ...d,
                    lifetimeFreeMaxAttachmentFiles: Number(e.target.value) || 0,
                  }))
                }
                className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-white"
              />
            </label>
          </div>
          <p className="mt-3 text-xs text-slate-500">
            Trial duration is fixed at {draft.trial.days} days in the app.
          </p>
        </section>
      </div>
    </form>
  );
}
