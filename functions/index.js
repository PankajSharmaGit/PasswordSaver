/**
 * PasswordSaver — Razorpay via Firebase Cloud Functions.
 *
 * Deploy (Blaze plan required for outbound Razorpay API calls):
 *   cd functions && npm install
 *   firebase functions:secrets:set RAZORPAY_KEY_SECRET
 *   firebase functions:secrets:set RAZORPAY_KEY_ID
 *   firebase deploy --only functions
 *
 * Or for quick test without secrets API, set env in Google Cloud Console
 * for the function: RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");
const crypto = require("crypto");
const Razorpay = require("razorpay");

admin.initializeApp();
const db = admin.firestore();

setGlobalOptions({
  region: "asia-south1",
  maxInstances: 20,
});

const razorpayKeyId = defineSecret("RAZORPAY_KEY_ID");
const razorpayKeySecret = defineSecret("RAZORPAY_KEY_SECRET");

/** Must match AppConstants.subscriptionPlans fallback in the Flutter app. */
const SUBSCRIPTION_PLANS = {
  3: 100,
  6: 180,
  12: 350,
  24: 650,
};

const DEFAULT_PLAN_FILE_LIMITS = {
  3: 12,
  6: 15,
  12: 20,
  24: 25,
};

const DEFAULT_TRIAL_FILE_LIMIT = 8;

const DEFAULT_FILE_UPGRADE_PLANS = {
  3: { priceInr: 70, maxAttachmentFiles: 30 },
  6: { priceInr: 120, maxAttachmentFiles: 50 },
  12: { priceInr: 200, maxAttachmentFiles: 100 },
  24: { priceInr: 350, maxAttachmentFiles: 200 },
};

const CATALOG_SCHEMA_VERSION = 3;
const CONFIG_PATH = ["appConfig", "subscription"];
const GST_CONFIG_PATH = ["appConfig", "subscriptionGst"];

const DEFAULT_SUBSCRIPTION_GST = {
  gstPercent: 18,
  platformGstin: "",
  platformStateCode: "",
  platformLegalName: "PasswordSaver",
  platformAddress: "",
};

/** ₹100 → $1.20 base; international = base × multiplier (default 1.5 → $1.80). */
const DEFAULT_INR_TO_USD_RATE = 0.012;
const DEFAULT_INTERNATIONAL_MULTIPLIER = 1.5;

function computeUsdFromInr(priceInr, catalog) {
  const rate = Number(catalog?.inrToUsdRate ?? DEFAULT_INR_TO_USD_RATE);
  const mult = Number(
    catalog?.internationalMultiplier ?? DEFAULT_INTERNATIONAL_MULTIPLIER
  );
  return Math.round(Number(priceInr) * rate * mult * 100) / 100;
}

function isIndiaCountry(countryCode) {
  const code = String(countryCode || "")
    .trim()
    .toUpperCase();
  return !code || code === "IN";
}

function round2(n) {
  return Math.round((Number(n) || 0) * 100) / 100;
}

function stateCodeFromGstin(gstin) {
  const g = String(gstin || "")
    .trim()
    .toUpperCase();
  if (g.length >= 2 && /^\d{2}/.test(g)) return g.slice(0, 2);
  return "";
}

async function loadSubscriptionGstConfig() {
  try {
    const snap = await db.doc(GST_CONFIG_PATH.join("/")).get();
    if (snap.exists) {
      const d = snap.data() || {};
      const pct = Number(d.gstPercent);
      const platformStateCode =
        String(d.platformStateCode || "").trim().slice(0, 2) ||
        stateCodeFromGstin(d.platformGstin);
      return {
        gstPercent:
          Number.isFinite(pct) && pct >= 0
            ? Math.min(40, pct)
            : DEFAULT_SUBSCRIPTION_GST.gstPercent,
        platformGstin: String(d.platformGstin || "").trim().toUpperCase(),
        platformStateCode,
        platformLegalName:
          String(d.platformLegalName || "").trim() ||
          DEFAULT_SUBSCRIPTION_GST.platformLegalName,
        platformAddress: String(d.platformAddress || "").trim(),
      };
    }
  } catch (e) {
    console.warn("GST config read failed", e);
  }
  return { ...DEFAULT_SUBSCRIPTION_GST };
}

/** India subscription tax — same rules as Snapbilling (CGST/SGST or IGST). */
function computeSubscriptionTax(
  taxableAmount,
  gstPercent,
  buyerStateCode,
  sellerStateCode
) {
  const taxable = round2(Math.max(0, taxableAmount));
  const rate = Math.max(0, Number(gstPercent) || 0);
  const totalGst = round2((taxable * rate) / 100);
  const buyer = String(buyerStateCode || "").trim();
  const seller = String(sellerStateCode || "").trim();
  const known = buyer.length === 2 && seller.length === 2;
  const supplyType = known && buyer !== seller ? "INTER" : "INTRA";

  if (supplyType === "INTER") {
    return {
      taxableAmount: taxable,
      gstPercent: rate,
      supplyType,
      cgst: 0,
      sgst: 0,
      igst: totalGst,
      totalGst,
      grandTotal: round2(taxable + totalGst),
    };
  }
  const half = round2(totalGst / 2);
  const cgst = half;
  const sgst = round2(totalGst - half);
  return {
    taxableAmount: taxable,
    gstPercent: rate,
    supplyType,
    cgst,
    sgst,
    igst: 0,
    totalGst: round2(cgst + sgst),
    grandTotal: round2(taxable + cgst + sgst),
  };
}

function planPriceUsd(plan, catalog) {
  if (plan?.priceUsd != null && Number(plan.priceUsd) > 0) {
    return Number(plan.priceUsd);
  }
  return computeUsdFromInr(plan.priceInr, catalog);
}

function defaultCatalog() {
  const intl = {
    inrToUsdRate: DEFAULT_INR_TO_USD_RATE,
    internationalMultiplier: DEFAULT_INTERNATIONAL_MULTIPLIER,
  };
  const plans = {};
  for (const [months, priceInr] of Object.entries(SUBSCRIPTION_PLANS)) {
    plans[months] = {
      priceInr,
      priceUsd: computeUsdFromInr(priceInr, intl),
      maxAttachmentFiles: DEFAULT_PLAN_FILE_LIMITS[months] || 12,
    };
  }
  const fileUpgradePlans = {};
  for (const [months, cfg] of Object.entries(DEFAULT_FILE_UPGRADE_PLANS)) {
    fileUpgradePlans[months] = {
      priceInr: cfg.priceInr,
      priceUsd: computeUsdFromInr(cfg.priceInr, intl),
      maxAttachmentFiles: cfg.maxAttachmentFiles,
    };
  }
  return {
    schemaVersion: CATALOG_SCHEMA_VERSION,
    inrToUsdRate: DEFAULT_INR_TO_USD_RATE,
    internationalMultiplier: DEFAULT_INTERNATIONAL_MULTIPLIER,
    plans,
    fileUpgradePlans,
    trial: {
      days: 15,
      maxAttachmentFiles: DEFAULT_TRIAL_FILE_LIMIT,
    },
    maxAttachmentBytes: 1024 * 1024,
  };
}

async function loadCatalog() {
  const ref = db.collection(CONFIG_PATH[0]).doc(CONFIG_PATH[1]);
  const snap = await ref.get();
  const fallback = defaultCatalog();
  if (!snap.exists) {
    await ref.set(
      {
        ...fallback,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return fallback;
  }
  const data = snap.data() || {};
  const schemaVersion = Number(data.schemaVersion || 0);
  // Migrate older catalogs to v3 (international USD pricing).
  if (schemaVersion < CATALOG_SCHEMA_VERSION) {
    const merged = { ...fallback, ...data, schemaVersion: CATALOG_SCHEMA_VERSION };
    for (const months of Object.keys(SUBSCRIPTION_PLANS)) {
      const entry =
        (data.plans && (data.plans[months] || data.plans[Number(months)])) ||
        fallback.plans[months];
      const priceInr = Number(
        typeof entry === "number" ? entry : entry?.priceInr ?? SUBSCRIPTION_PLANS[months]
      );
      merged.plans[months] = {
        priceInr,
        priceUsd: computeUsdFromInr(priceInr, merged),
        maxAttachmentFiles: Number(
          typeof entry === "number"
            ? DEFAULT_PLAN_FILE_LIMITS[months]
            : entry?.maxAttachmentFiles ?? DEFAULT_PLAN_FILE_LIMITS[months]
        ),
      };
    }
    for (const months of Object.keys(DEFAULT_FILE_UPGRADE_PLANS)) {
      const entry =
        (data.fileUpgradePlans &&
          (data.fileUpgradePlans[months] ||
            data.fileUpgradePlans[Number(months)])) ||
        fallback.fileUpgradePlans[months];
      const def = DEFAULT_FILE_UPGRADE_PLANS[months];
      const priceInr = Number(entry?.priceInr ?? def.priceInr);
      merged.fileUpgradePlans[months] = {
        priceInr,
        priceUsd: computeUsdFromInr(priceInr, merged),
        maxAttachmentFiles: Number(
          entry?.maxAttachmentFiles ?? def.maxAttachmentFiles
        ),
      };
    }
    merged.inrToUsdRate = Number(
      data.inrToUsdRate ?? DEFAULT_INR_TO_USD_RATE
    );
    merged.internationalMultiplier = Number(
      data.internationalMultiplier ?? DEFAULT_INTERNATIONAL_MULTIPLIER
    );
    await ref.set(
      {
        ...merged,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        migratedFromSchema: schemaVersion,
      },
      { merge: true }
    );
    return merged;
  }

  const intlMeta = {
    inrToUsdRate: Number(data.inrToUsdRate ?? DEFAULT_INR_TO_USD_RATE),
    internationalMultiplier: Number(
      data.internationalMultiplier ?? DEFAULT_INTERNATIONAL_MULTIPLIER
    ),
  };

  const plans = {};
  const rawPlans = data.plans || {};
  for (const months of Object.keys(SUBSCRIPTION_PLANS)) {
    const entry = rawPlans[months] || rawPlans[Number(months)] || {};
    const price =
      typeof entry === "number"
        ? entry
        : Number(entry.priceInr || SUBSCRIPTION_PLANS[months]);
    const files =
      typeof entry === "number"
        ? DEFAULT_PLAN_FILE_LIMITS[months]
        : Number(
            entry.maxAttachmentFiles != null
              ? entry.maxAttachmentFiles
              : DEFAULT_PLAN_FILE_LIMITS[months]
          );
    const priceInr = price > 0 ? price : SUBSCRIPTION_PLANS[months];
    const planEntry = {
      priceInr,
      maxAttachmentFiles: files >= 0 ? files : DEFAULT_PLAN_FILE_LIMITS[months],
    };
    planEntry.priceUsd =
      typeof entry === "object" && entry.priceUsd != null
        ? Number(entry.priceUsd)
        : computeUsdFromInr(priceInr, intlMeta);
    plans[months] = planEntry;
  }

  const fileUpgradePlans = {};
  const rawFile = data.fileUpgradePlans || {};
  for (const months of Object.keys(DEFAULT_FILE_UPGRADE_PLANS)) {
    const entry = rawFile[months] || rawFile[Number(months)] || {};
    const def = DEFAULT_FILE_UPGRADE_PLANS[months];
    const priceInr = Number(
      entry.priceInr != null ? entry.priceInr : def.priceInr
    );
    fileUpgradePlans[months] = {
      priceInr,
      priceUsd:
        entry.priceUsd != null
          ? Number(entry.priceUsd)
          : computeUsdFromInr(priceInr, intlMeta),
      maxAttachmentFiles: Number(
        entry.maxAttachmentFiles != null
          ? entry.maxAttachmentFiles
          : def.maxAttachmentFiles
      ),
    };
  }

  const trial = data.trial || {};
  return {
    schemaVersion: CATALOG_SCHEMA_VERSION,
    inrToUsdRate: intlMeta.inrToUsdRate,
    internationalMultiplier: intlMeta.internationalMultiplier,
    plans,
    fileUpgradePlans,
    trial: {
      days: Number(trial.days || 15),
      maxAttachmentFiles: Number(
        trial.maxAttachmentFiles != null
          ? trial.maxAttachmentFiles
          : fallback.trial.maxAttachmentFiles
      ),
    },
    maxAttachmentBytes: Number(
      data.maxAttachmentBytes || fallback.maxAttachmentBytes
    ),
  };
}

function priceFromCatalog(catalog, months) {
  const plan = catalog.plans[String(months)] || catalog.plans[months];
  return plan ? Number(plan.priceInr) : null;
}

function fileUpgradeFromCatalog(catalog, months) {
  const plan =
    catalog.fileUpgradePlans[String(months)] ||
    catalog.fileUpgradePlans[months];
  if (!plan) return null;
  return {
    priceInr: Number(plan.priceInr),
    priceUsd: planPriceUsd(plan, catalog),
    maxAttachmentFiles: Number(plan.maxAttachmentFiles),
  };
}

function requireAuth(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  return request.auth.uid;
}

function getRazorpayClient() {
  const keyId = razorpayKeyId.value();
  const keySecret = razorpayKeySecret.value();
  if (!keyId || !keySecret) {
    throw new HttpsError(
      "failed-precondition",
      "Payment service is not configured"
    );
  }
  return new Razorpay({ key_id: keyId, key_secret: keySecret });
}

function addMonths(date, months) {
  const d = new Date(date.getTime());
  const day = d.getDate();
  d.setMonth(d.getMonth() + months);
  // Handle month overflow (e.g. Jan 31 + 1 month)
  if (d.getDate() < day) {
    d.setDate(0);
  }
  return d;
}

/** Matches app Razorpay checkout label (e.g. PasswordSaver upgrade to 6 month plan). */
function razorpayCheckoutLabel({ months, planType, includeFilePlan, user }) {
  if (planType === "file") {
    return `PasswordSaver ${months} month file add-on`;
  }
  const currentPlan = user.subscriptionPlanMonths
    ? Number(user.subscriptionPlanMonths)
    : null;
  const isTrialActive = user.isTrialActive !== false;
  const expiresAt = user.subscriptionExpiresAt
    ? new Date(user.subscriptionExpiresAt)
    : null;
  const hasPaidPlan =
    !isTrialActive &&
    currentPlan != null &&
    expiresAt &&
    expiresAt.getTime() > Date.now();
  const isUpgrade =
    hasPaidPlan && currentPlan != null && months > currentPlan;
  const isRenew =
    !hasPaidPlan &&
    !isTrialActive &&
    currentPlan != null &&
    months === currentPlan;
  const planPart =
    isUpgrade || isRenew
      ? `upgrade to ${months} month plan`
      : `${months} month plan`;
  let label = `PasswordSaver ${planPart}`;
  if (includeFilePlan) label += " + file plan";
  return label;
}

function verifySignature({ orderId, paymentId, signature, secret }) {
  const body = `${orderId}|${paymentId}`;
  const expected = crypto
    .createHmac("sha256", secret)
    .update(body)
    .digest("hex");
  const a = Buffer.from(expected, "utf8");
  const b = Buffer.from(String(signature || ""), "utf8");
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

/**
 * Creates a Razorpay order for the selected plan.
 * Input: {
 *   months: 3|6|12|24,
 *   planType?: "subscription"|"file",
 *   includeFilePlan?: boolean  // with subscription: charge base + file
 * }
 */
exports.createRazorpayOrder = onCall(
  { secrets: [razorpayKeyId, razorpayKeySecret], enforceAppCheck: false },
  async (request) => {
    const uid = requireAuth(request);
    const months = Number(request.data?.months);
    const planType =
      String(request.data?.planType || "subscription").toLowerCase() === "file"
        ? "file"
        : "subscription";
    const includeFilePlan = request.data?.includeFilePlan === true;
    const catalog = await loadCatalog();

    const userSnap = await db.collection("users").doc(uid).get();
    const user = userSnap.data() || {};
    const india = isIndiaCountry(user.countryCode);
    const currency = india ? "INR" : "USD";

    let priceInr = null;
    let priceUsd = null;
    let maxAttachmentFiles = null;
    let basePriceInr = null;
    let filePlanPriceInr = null;
    let basePriceUsd = null;
    let filePlanPriceUsd = null;

    if (planType === "file") {
      const filePlan = fileUpgradeFromCatalog(catalog, months);
      if (!filePlan || !filePlan.priceInr) {
        throw new HttpsError(
          "invalid-argument",
          "Invalid file upgrade plan. Use 3, 6, 12, or 24 months."
        );
      }
      const subExpiry = user.subscriptionExpiresAt
        ? new Date(user.subscriptionExpiresAt)
        : null;
      const hasPaidPlan =
        user.isTrialActive === false &&
        user.subscriptionPlanMonths &&
        subExpiry &&
        subExpiry.getTime() > Date.now();
      if (!hasPaidPlan) {
        throw new HttpsError(
          "failed-precondition",
          "Buy a base subscription first, then add a file plan."
        );
      }
      if (Number(user.subscriptionPlanMonths) !== months) {
        throw new HttpsError(
          "failed-precondition",
          `File plan must match your ${user.subscriptionPlanMonths}-month base plan.`
        );
      }
      priceInr = filePlan.priceInr;
      priceUsd = filePlan.priceUsd;
      maxAttachmentFiles = filePlan.maxAttachmentFiles;
      filePlanPriceInr = filePlan.priceInr;
      filePlanPriceUsd = filePlan.priceUsd;
    } else {
      const basePlan =
        catalog.plans[String(months)] || catalog.plans[months] || null;
      basePriceInr = basePlan ? Number(basePlan.priceInr) : null;
      if (!basePriceInr) {
        throw new HttpsError(
          "invalid-argument",
          "Invalid plan. Use 3, 6, 12, or 24 months."
        );
      }
      basePriceUsd = planPriceUsd(basePlan, catalog);

      const currentPlan = user.subscriptionPlanMonths
        ? Number(user.subscriptionPlanMonths)
        : null;
      const isTrialActive = user.isTrialActive !== false;
      const expiresAt = user.subscriptionExpiresAt
        ? new Date(user.subscriptionExpiresAt)
        : null;
      const hasPaidPlan =
        !isTrialActive &&
        currentPlan != null &&
        expiresAt &&
        expiresAt.getTime() > Date.now();

      if (hasPaidPlan && currentPlan === months) {
        throw new HttpsError("already-exists", "You are already on this plan");
      }
      if (hasPaidPlan && months < currentPlan) {
        throw new HttpsError(
          "failed-precondition",
          "Select a higher plan to upgrade"
        );
      }

      priceInr = basePriceInr;
      priceUsd = basePriceUsd;
      if (includeFilePlan) {
        const filePlan = fileUpgradeFromCatalog(catalog, months);
        if (!filePlan || !filePlan.priceInr) {
          throw new HttpsError(
            "failed-precondition",
            "File upgrade plan not available for this duration"
          );
        }
        filePlanPriceInr = filePlan.priceInr;
        filePlanPriceUsd = filePlan.priceUsd;
        maxAttachmentFiles = filePlan.maxAttachmentFiles;
        priceInr = basePriceInr + filePlanPriceInr;
        priceUsd =
          Math.round((basePriceUsd + filePlanPriceUsd) * 100) / 100;
      }
    }

    let taxBreakdown = null;
    let grandTotalInr = priceInr;
    const buyerGstin = String(request.data?.buyerGstin || "")
      .trim()
      .toUpperCase()
      .slice(0, 15);
    if (buyerGstin && !/^[0-9A-Z]{15}$/.test(buyerGstin)) {
      throw new HttpsError("invalid-argument", "Enter a valid 15-character GSTIN");
    }
    if (india) {
      const gstConfig = await loadSubscriptionGstConfig();
      const buyerStateCode = stateCodeFromGstin(buyerGstin);
      const sellerStateCode =
        String(gstConfig.platformStateCode || "").trim() ||
        stateCodeFromGstin(gstConfig.platformGstin);
      taxBreakdown = computeSubscriptionTax(
        priceInr,
        gstConfig.gstPercent,
        buyerStateCode,
        sellerStateCode
      );
      grandTotalInr = taxBreakdown.grandTotal;
    }

    const amountMinor = india
      ? Math.round(Number(grandTotalInr) * 100)
      : Math.round(Number(priceUsd) * 100);
    const checkoutLabel = razorpayCheckoutLabel({
      months,
      planType,
      includeFilePlan,
      user,
    });
    const razorpay = getRazorpayClient();
    let order;
    try {
      order = await razorpay.orders.create({
        amount: amountMinor,
        currency,
        receipt: `ps_${planType[0]}${includeFilePlan ? "f" : ""}_${uid.slice(0, 5)}_${months}m_${Date.now()}`.slice(
          0,
          40
        ),
        notes: {
          userId: uid,
          months: String(months),
          planType,
          includeFilePlan: includeFilePlan ? "1" : "0",
          countryCode: String(user.countryCode || ""),
          product: "passwordsaver_subscription",
          checkoutLabel,
          buyerGstin: buyerGstin || "",
        },
      });
    } catch (e) {
      console.error("Razorpay order create failed", e);
      throw new HttpsError("internal", "Could not start payment. Please try again.");
    }

    await db.collection("paymentOrders").doc(order.id).set({
      userId: uid,
      userEmail: user.email || "",
      orderId: order.id,
      months,
      priceInr,
      priceUsd,
      grandTotalInr: india ? grandTotalInr : null,
      taxableAmountInr: taxBreakdown ? taxBreakdown.taxableAmount : null,
      gstPercent: taxBreakdown ? taxBreakdown.gstPercent : null,
      cgst: taxBreakdown ? taxBreakdown.cgst : null,
      sgst: taxBreakdown ? taxBreakdown.sgst : null,
      igst: taxBreakdown ? taxBreakdown.igst : null,
      totalGst: taxBreakdown ? taxBreakdown.totalGst : null,
      supplyType: taxBreakdown ? taxBreakdown.supplyType : null,
      basePriceInr,
      filePlanPriceInr,
      basePriceUsd,
      filePlanPriceUsd,
      amountPaise: amountMinor,
      amountMinor,
      currency,
      countryCode: user.countryCode || null,
      planType,
      includeFilePlan: planType === "subscription" ? includeFilePlan : true,
      maxAttachmentFiles,
      buyerGstin: buyerGstin || null,
      buyerStateCode: buyerGstin ? stateCodeFromGstin(buyerGstin) : null,
      status: "created",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      orderId: order.id,
      amountPaise: amountMinor,
      amountMinor,
      currency,
      keyId: razorpayKeyId.value(),
      months,
      priceInr,
      priceUsd,
      grandTotalInr: india ? grandTotalInr : null,
      taxableAmountInr: taxBreakdown ? taxBreakdown.taxableAmount : null,
      gstPercent: taxBreakdown ? taxBreakdown.gstPercent : null,
      totalGst: taxBreakdown ? taxBreakdown.totalGst : null,
      cgst: taxBreakdown ? taxBreakdown.cgst : null,
      sgst: taxBreakdown ? taxBreakdown.sgst : null,
      igst: taxBreakdown ? taxBreakdown.igst : null,
      supplyType: taxBreakdown ? taxBreakdown.supplyType : null,
      basePriceInr,
      filePlanPriceInr,
      basePriceUsd,
      filePlanPriceUsd,
      planType,
      includeFilePlan: planType === "subscription" ? includeFilePlan : true,
      maxAttachmentFiles,
    };
  }
);

/**
 * Verifies Razorpay payment signature and activates the subscription in Firestore.
 * Input: {
 *   razorpayOrderId, razorpayPaymentId, razorpaySignature, months, planType?
 * }
 * Output: { ok, expiresAt, months, priceInr, paymentId, planType }
 */
exports.verifyRazorpayPayment = onCall(
  { secrets: [razorpayKeyId, razorpayKeySecret], enforceAppCheck: false },
  async (request) => {
    const uid = requireAuth(request);
    const orderId = String(request.data?.razorpayOrderId || "").trim();
    const paymentId = String(request.data?.razorpayPaymentId || "").trim();
    const signature = String(request.data?.razorpaySignature || "").trim();
    const months = Number(request.data?.months);

    if (!orderId || !paymentId || !signature) {
      throw new HttpsError(
        "invalid-argument",
        "orderId, paymentId and signature are required"
      );
    }
    const catalog = await loadCatalog();
    const orderRef = db.collection("paymentOrders").doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
      throw new HttpsError("not-found", "Payment order not found");
    }
    const order = orderSnap.data() || {};
    const planType =
      String(order.planType || request.data?.planType || "subscription")
        .toLowerCase() === "file"
        ? "file"
        : "subscription";

    if (planType === "file") {
      if (!fileUpgradeFromCatalog(catalog, months)) {
        throw new HttpsError("invalid-argument", "Invalid file upgrade plan");
      }
    } else if (!priceFromCatalog(catalog, months)) {
      throw new HttpsError("invalid-argument", "Invalid plan months");
    }

    const secret = razorpayKeySecret.value();
    const valid = verifySignature({
      orderId,
      paymentId,
      signature,
      secret,
    });
    if (!valid) {
      throw new HttpsError(
        "permission-denied",
        "Payment signature verification failed"
      );
    }

    if (order.userId !== uid) {
      throw new HttpsError(
        "permission-denied",
        "This payment order belongs to another user"
      );
    }
    if (Number(order.months) !== months) {
      throw new HttpsError(
        "failed-precondition",
        "Plan months do not match the order"
      );
    }
    if (order.status === "paid") {
      // Idempotent success — already activated.
      return {
        ok: true,
        alreadyProcessed: true,
        expiresAt: order.expiresAt || null,
        months: order.months,
        priceInr: order.priceInr,
        paymentId: order.paymentId || paymentId,
        planType,
      };
    }

    // Optional: confirm payment with Razorpay API
    try {
      const razorpay = getRazorpayClient();
      const payment = await razorpay.payments.fetch(paymentId);
      if (payment.order_id !== orderId) {
        throw new HttpsError(
          "failed-precondition",
          "Payment does not match order"
        );
      }
      if (payment.status !== "captured" && payment.status !== "authorized") {
        throw new HttpsError(
          "failed-precondition",
          `Payment status is ${payment.status}`
        );
      }
      if (Number(payment.amount) !== Number(order.amountPaise)) {
        throw new HttpsError("failed-precondition", "Payment amount mismatch");
      }
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("Razorpay payment fetch failed", e);
      throw new HttpsError("internal", "Could not confirm payment. Please try again.");
    }

    const userRef = db.collection("users").doc(uid);
    const userSnap = await userRef.get();
    const user = userSnap.data() || {};
    const now = new Date();

    // File-only add-on — expires with base subscription.
    if (planType === "file") {
      const filePlan =
        fileUpgradeFromCatalog(catalog, months) ||
        DEFAULT_FILE_UPGRADE_PLANS[months];
      const subExpiry = user.subscriptionExpiresAt
        ? new Date(user.subscriptionExpiresAt)
        : null;
      if (
        user.isTrialActive !== false ||
        !user.subscriptionPlanMonths ||
        !subExpiry ||
        subExpiry.getTime() <= now.getTime()
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Active base subscription required for file plan"
        );
      }
      if (Number(user.subscriptionPlanMonths) !== months) {
        throw new HttpsError(
          "failed-precondition",
          "File plan duration must match your base plan"
        );
      }
      const expiresAtIso = subExpiry.toISOString();
      const maxFiles = Number(
        order.maxAttachmentFiles || filePlan.maxAttachmentFiles
      );

      const batch = db.batch();
      batch.set(
        userRef,
        {
          filePlanMonths: months,
          filePlanMaxFiles: maxFiles,
          filePlanExpiresAt: expiresAtIso,
          filePlanPriceInr: order.priceInr,
          filePlanUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      batch.set(
        orderRef,
        {
          status: "paid",
          paymentId,
          signature,
          expiresAt: expiresAtIso,
          planType: "file",
          maxAttachmentFiles: maxFiles,
          paidAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      await batch.commit();

      await writeSubscriptionBill({
        uid,
        user,
        order,
        orderId,
        paymentId,
        months,
        planType: "file",
        expiresAtIso,
      });

      return {
        ok: true,
        expiresAt: expiresAtIso,
        months,
        priceInr: order.priceInr,
        paymentId,
        planType: "file",
        maxAttachmentFiles: maxFiles,
      };
    }

    const currentPlan = user.subscriptionPlanMonths
      ? Number(user.subscriptionPlanMonths)
      : null;
    const isTrialActive = user.isTrialActive !== false;
    const currentExpiry = user.subscriptionExpiresAt
      ? new Date(user.subscriptionExpiresAt)
      : null;
    const hasPaidPlan =
      !isTrialActive &&
      currentPlan != null &&
      currentExpiry &&
      currentExpiry.getTime() > now.getTime();

    if (hasPaidPlan && currentPlan === months) {
      throw new HttpsError("already-exists", "You are already on this plan");
    }
    if (hasPaidPlan && months < currentPlan) {
      throw new HttpsError(
        "failed-precondition",
        "Select a higher plan to upgrade"
      );
    }

    const isUpgrade = hasPaidPlan && months > currentPlan;
    // Upgrade/renew replaces the base plan — leftover base days are not carried over.
    const expiry = addMonths(now, months);
    const expiresAtIso = expiry.toISOString();
    const priceInr = Number(order.priceInr);

    const subPayload = {
      userId: uid,
      type: "paid",
      months,
      priceInr,
      activatedAt: now.toISOString(),
      expiresAt: expiresAtIso,
      lastExpiresAt: expiresAtIso,
      subscriptionPlan: `${months}_month`,
      isUpgrade: isUpgrade === true,
      razorpayPaymentId: paymentId,
      razorpayOrderId: orderId,
      razorpaySignature: signature,
      paymentGateway: "razorpay",
      verifiedBy: "cloud_function",
      verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const userPayload = {
      subscriptionExpiresAt: expiresAtIso,
      lastExpiresAt: expiresAtIso,
      isTrialActive: false,
      subscriptionPlanMonths: months,
      subscriptionPlan: `${months}_month`,
      isLifetimeFree: false,
      razorpayPaymentId: paymentId,
      paymentGateway: "razorpay",
    };

    // Bundled file plan → new file quota until new base expiry.
    // Without bundle → keep any remaining previous file plan as-is.
    if (order.includeFilePlan === true) {
      const filePlan =
        fileUpgradeFromCatalog(catalog, months) ||
        DEFAULT_FILE_UPGRADE_PLANS[months];
      const maxFiles = Number(
        order.maxAttachmentFiles || filePlan.maxAttachmentFiles
      );
      userPayload.filePlanMonths = months;
      userPayload.filePlanMaxFiles = maxFiles;
      userPayload.filePlanExpiresAt = expiresAtIso;
      userPayload.filePlanPriceInr = Number(
        order.filePlanPriceInr || filePlan.priceInr
      );
      userPayload.filePlanUpdatedAt =
        admin.firestore.FieldValue.serverTimestamp();
      subPayload.includeFilePlan = true;
      subPayload.filePlanMaxFiles = maxFiles;
    } else {
      subPayload.includeFilePlan = false;
      subPayload.preservedExistingFilePlan = true;
    }

    const batch = db.batch();
    batch.set(db.collection("subscriptions").doc(uid), subPayload, {
      merge: true,
    });
    batch.set(userRef, userPayload, { merge: true });
    batch.set(
      orderRef,
      {
        status: "paid",
        paymentId,
        signature,
        expiresAt: expiresAtIso,
        includeFilePlan: order.includeFilePlan === true,
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    await batch.commit();

    await writeSubscriptionBill({
      uid,
      user,
      order,
      orderId,
      paymentId,
      months,
      planType: "subscription",
      expiresAtIso,
    });

    return {
      ok: true,
      expiresAt: expiresAtIso,
      months,
      priceInr,
      paymentId,
      planType: "subscription",
      includeFilePlan: order.includeFilePlan === true,
      maxAttachmentFiles:
        order.includeFilePlan === true
          ? Number(order.maxAttachmentFiles || 0)
          : null,
    };
  }
);

async function writeSubscriptionBill({
  uid,
  user,
  order,
  orderId,
  paymentId,
  months,
  planType,
  expiresAtIso,
}) {
  try {
    const gstConfig = await loadSubscriptionGstConfig();
    const buyerGstin = String(order.buyerGstin || "").trim().toUpperCase();
    const now = new Date();
    const billNo = `PS-${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, "0")}${String(now.getDate()).padStart(2, "0")}-${String(orderId).slice(-6).toUpperCase()}`;
    const planLabel =
      planType === "file"
        ? `${months}-month file add-on`
        : `${months}-month plan${order.includeFilePlan ? " + file plan" : ""}`;

    await db.collection("subscriptionBills").add({
      userId: uid,
      orderId,
      paymentId,
      billNo,
      billDate: now.toISOString(),
      planLabel,
      months,
      planType,
      sellerName: gstConfig.platformLegalName || "PasswordSaver",
      sellerGstin: gstConfig.platformGstin || "",
      sellerStateCode:
        gstConfig.platformStateCode ||
        stateCodeFromGstin(gstConfig.platformGstin),
      sellerAddress: gstConfig.platformAddress || "",
      buyerName: user.displayName || user.email || "",
      buyerGstin: buyerGstin || "",
      buyerStateCode:
        order.buyerStateCode || stateCodeFromGstin(buyerGstin) || "",
      taxableAmount: order.taxableAmountInr ?? order.priceInr ?? 0,
      gstPercent: order.gstPercent ?? gstConfig.gstPercent,
      supplyType: order.supplyType || "",
      cgst: order.cgst ?? 0,
      sgst: order.sgst ?? 0,
      igst: order.igst ?? 0,
      totalGst: order.totalGst ?? 0,
      grandTotal: order.grandTotalInr ?? order.priceInr ?? 0,
      currency: order.currency || "INR",
      status: "paid",
      expiresAt: expiresAtIso || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    if (buyerGstin) {
      await db.collection("users").doc(uid).set({ buyerGstin }, { merge: true });
    }
  } catch (e) {
    console.warn("subscription bill write skipped", e.message);
  }
}

const ADMIN_EMAIL = "passwordsaver@gryzion.com";

/** ISO codes allowed for onboarding — must match app SupportedCountries. */
const ALLOWED_COUNTRIES = {
  IN: "India",
  US: "United States",
  GB: "United Kingdom",
  CA: "Canada",
  AU: "Australia",
  AE: "United Arab Emirates",
  SA: "Saudi Arabia",
  SG: "Singapore",
  MY: "Malaysia",
  DE: "Germany",
  FR: "France",
  IT: "Italy",
  ES: "Spain",
  NL: "Netherlands",
  BE: "Belgium",
  CH: "Switzerland",
  SE: "Sweden",
  NO: "Norway",
  DK: "Denmark",
  FI: "Finland",
  IE: "Ireland",
  PT: "Portugal",
  PL: "Poland",
  AT: "Austria",
  CZ: "Czech Republic",
  GR: "Greece",
  RO: "Romania",
  HU: "Hungary",
  RU: "Russia",
  UA: "Ukraine",
  TR: "Turkey",
  IL: "Israel",
  EG: "Egypt",
  ZA: "South Africa",
  NG: "Nigeria",
  KE: "Kenya",
  PK: "Pakistan",
  BD: "Bangladesh",
  LK: "Sri Lanka",
  NP: "Nepal",
  AF: "Afghanistan",
  ID: "Indonesia",
  PH: "Philippines",
  TH: "Thailand",
  VN: "Vietnam",
  JP: "Japan",
  KR: "South Korea",
  CN: "China",
  HK: "Hong Kong",
  TW: "Taiwan",
  NZ: "New Zealand",
  MX: "Mexico",
  BR: "Brazil",
  AR: "Argentina",
  CL: "Chile",
  CO: "Colombia",
  PE: "Peru",
  QA: "Qatar",
  KW: "Kuwait",
  OM: "Oman",
  BH: "Bahrain",
  JO: "Jordan",
  LB: "Lebanon",
  IQ: "Iraq",
  IR: "Iran",
  MA: "Morocco",
  DZ: "Algeria",
  TN: "Tunisia",
  GH: "Ghana",
  ET: "Ethiopia",
  MU: "Mauritius",
  XX: "Other",
};

function requireAdmin(request) {
  requireAuth(request);
  const email = (request.auth.token.email || "").toLowerCase();
  if (email !== ADMIN_EMAIL.toLowerCase()) {
    throw new HttpsError("permission-denied", "Admin access only");
  }
}

function adminIdentity(request) {
  return {
    adminUid: request.auth.uid,
    adminEmail: (request.auth.token.email || "").toLowerCase(),
  };
}

async function writeAdminAuditLog(request, entry) {
  const { adminUid, adminEmail } = adminIdentity(request);
  await db.collection("adminAuditLogs").add({
    action: entry.action,
    adminUid,
    adminEmail,
    targetUserId: entry.targetUserId || null,
    targetEmail: entry.targetEmail || null,
    targetDisplayName: entry.targetDisplayName || null,
    payload: entry.payload || {},
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function deleteQueryBatch(query) {
  const snapshot = await query.get();
  if (snapshot.empty) return;
  const batch = db.batch();
  snapshot.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
  if (snapshot.size >= 100) {
    await deleteQueryBatch(query);
  }
}

async function deleteCollection(collectionRef) {
  const query = collectionRef.orderBy("__name__").limit(100);
  await deleteQueryBatch(query);
}

async function deleteUserStorageFiles(userId) {
  try {
    const bucket = admin.storage().bucket();
    const [files] = await bucket.getFiles({ prefix: `users/${userId}/` });
    await Promise.all(files.map((file) => file.delete().catch(() => null)));
  } catch (err) {
    console.warn("deleteUserStorageFiles:", userId, err.message);
  }
}

function isProtectedAdminUser(userData) {
  const email = (userData?.email || "").toLowerCase();
  return email === ADMIN_EMAIL.toLowerCase();
}

function mapUserDoc(id, data) {
  const d = data || {};
  const expiresAt = d.subscriptionExpiresAt || d.lastExpiresAt || null;
  const isLifetimeFree = d.isLifetimeFree === true;
  const isTrial =
    !isLifetimeFree && d.isTrialActive !== false && !d.subscriptionPlanMonths;
  const now = new Date();
  const expiryDate = expiresAt ? new Date(expiresAt) : null;
  const hasAccess = isLifetimeFree
    ? d.isBlocked !== true
    : expiryDate
      ? expiryDate.getTime() > now.getTime()
      : true;
  return {
    uid: id,
    email: d.email || "",
    displayName: d.displayName || "",
    userId: d.userId || "",
    primaryMobile: d.primaryMobile || null,
    secondaryMobile: d.secondaryMobile || null,
    countryCode: d.countryCode || null,
    countryName: d.countryName || null,
    hasSelectedCountry:
      typeof d.countryCode === "string" && d.countryCode.trim().length >= 2,
    createdAt: d.createdAt || null,
    lastActiveAt: d.lastActiveAt || d.createdAt || null,
    trialStartedAt: d.trialStartedAt || d.createdAt || null,
    subscriptionExpiresAt: isLifetimeFree ? null : expiresAt,
    lastExpiresAt: isLifetimeFree ? null : d.lastExpiresAt || expiresAt,
    isTrialActive: isLifetimeFree ? false : d.isTrialActive !== false,
    subscriptionPlanMonths: d.subscriptionPlanMonths || null,
    subscriptionPlan:
      d.subscriptionPlan ||
      (isLifetimeFree ? "lifetime_free" : isTrial ? "trial" : null),
    isLifetimeFree,
    isBlocked: d.isBlocked === true,
    hasActiveAccess: hasAccess && d.isBlocked !== true,
    planLabel: (() => {
      if (d.isBlocked === true) return "Blocked";
      if (isLifetimeFree) return "Lifetime free";
      if (!isTrial && d.subscriptionPlanMonths && hasAccess) {
        return `${d.subscriptionPlanMonths}-month plan`;
      }
      if (isTrial && hasAccess) return "Free trial";
      if (isTrial) return "Trial expired";
      return "Plan expired";
    })(),
  };
}

/** Admin dashboard: counts, users, transactions. */
exports.getAdminDashboard = onCall(async (request) => {
  requireAdmin(request);

  const [usersSnap, ordersSnap, auditSnap] = await Promise.all([
    db.collection("users").get(),
    db
      .collection("paymentOrders")
      .orderBy("createdAt", "desc")
      .limit(200)
      .get()
      .catch(async () => db.collection("paymentOrders").limit(200).get()),
    db
      .collection("adminAuditLogs")
      .orderBy("createdAt", "desc")
      .limit(200)
      .get()
      .catch(async () => db.collection("adminAuditLogs").limit(200).get()),
  ]);

  const users = [];
  let trialActive = 0;
  let paidActive = 0;
  let blocked = 0;
  let expired = 0;

  usersSnap.forEach((doc) => {
    const u = mapUserDoc(doc.id, doc.data());
    users.push(u);
    if (u.isBlocked) blocked += 1;
    else if (u.isLifetimeFree && u.hasActiveAccess) paidActive += 1;
    else if (u.isTrialActive && u.hasActiveAccess) trialActive += 1;
    else if (!u.isTrialActive && u.subscriptionPlanMonths && u.hasActiveAccess) {
      paidActive += 1;
    } else expired += 1;
  });

  users.sort((a, b) =>
    String(b.lastActiveAt || b.createdAt || "").localeCompare(
      String(a.lastActiveAt || a.createdAt || "")
    )
  );

  const emailByUid = {};
  const nameByUid = {};
  for (const u of users) {
    emailByUid[u.uid] = u.email || "";
    nameByUid[u.uid] = u.displayName || "";
  }

  const transactions = [];
  let successCount = 0;
  let failedCount = 0;
  let pendingCount = 0;

  ordersSnap.forEach((doc) => {
    const o = doc.data() || {};
    const status = o.status || "created";
    if (status === "paid") successCount += 1;
    else if (status === "failed") failedCount += 1;
    else pendingCount += 1;

    let createdAt = null;
    if (o.createdAt && typeof o.createdAt.toDate === "function") {
      createdAt = o.createdAt.toDate().toISOString();
    } else if (o.createdAt) {
      createdAt = String(o.createdAt);
    }

    const uid = o.userId || "";
    transactions.push({
      orderId: o.orderId || doc.id,
      userId: uid,
      userEmail:
        o.userEmail ||
        emailByUid[uid] ||
        "",
      userDisplayName: nameByUid[uid] || "",
      months: o.months || null,
      priceInr: o.priceInr || null,
      priceUsd: o.priceUsd || null,
      currency: o.currency || null,
      amountPaise: o.amountPaise || null,
      status,
      paymentId: o.paymentId || null,
      failReason: o.failReason || null,
      createdAt,
      paidAt:
        o.paidAt && typeof o.paidAt.toDate === "function"
          ? o.paidAt.toDate().toISOString()
          : o.paidAt || null,
    });
  });

  const catalog = await loadCatalog();
  const gst = await loadSubscriptionGstConfig();

  const auditLogs = [];
  auditSnap.forEach((doc) => {
    const a = doc.data() || {};
    let createdAt = null;
    if (a.createdAt && typeof a.createdAt.toDate === "function") {
      createdAt = a.createdAt.toDate().toISOString();
    } else if (a.createdAt) {
      createdAt = String(a.createdAt);
    }
    auditLogs.push({
      id: doc.id,
      action: a.action || "",
      adminUid: a.adminUid || "",
      adminEmail: a.adminEmail || "",
      targetUserId: a.targetUserId || null,
      targetEmail: a.targetEmail || null,
      targetDisplayName: a.targetDisplayName || null,
      payload: a.payload || {},
      createdAt,
    });
  });

  return {
    stats: {
      totalUsers: users.length,
      trialActive,
      paidActive,
      blocked,
      expired,
      successTransactions: successCount,
      failedTransactions: failedCount,
      pendingTransactions: pendingCount,
    },
    users,
    transactions,
    auditLogs,
    plans: catalog.plans,
    catalog: { ...catalog, gst },
  };
});

/** Public (signed-in) catalog: prices + file limits + GST config. */
exports.getSubscriptionCatalog = onCall(async (request) => {
  requireAuth(request);
  const catalog = await loadCatalog();
  const gst = await loadSubscriptionGstConfig();
  return { ...catalog, gst };
});

/** Admin: update plan pricing + max attachment file counts. */
exports.adminUpdateSubscriptionConfig = onCall(async (request) => {
  requireAdmin(request);
  const incoming = request.data || {};
  const fallback = defaultCatalog();
  const inrToUsdRate = Number(
    incoming.inrToUsdRate != null
      ? incoming.inrToUsdRate
      : fallback.inrToUsdRate
  );
  const internationalMultiplier = Number(
    incoming.internationalMultiplier != null
      ? incoming.internationalMultiplier
      : fallback.internationalMultiplier
  );
  if (!Number.isFinite(inrToUsdRate) || inrToUsdRate <= 0) {
    throw new HttpsError("invalid-argument", "Invalid INR→USD rate");
  }
  if (
    !Number.isFinite(internationalMultiplier) ||
    internationalMultiplier < 1
  ) {
    throw new HttpsError(
      "invalid-argument",
      "International multiplier must be at least 1"
    );
  }
  const intlMeta = { inrToUsdRate, internationalMultiplier };
  const plans = {};

  for (const months of Object.keys(SUBSCRIPTION_PLANS)) {
    const src =
      (incoming.plans && (incoming.plans[months] || incoming.plans[Number(months)])) ||
      {};
    const priceInr = Number(
      src.priceInr != null ? src.priceInr : fallback.plans[months].priceInr
    );
    const maxAttachmentFiles = Number(
      src.maxAttachmentFiles != null
        ? src.maxAttachmentFiles
        : fallback.plans[months].maxAttachmentFiles
    );
    const priceUsd = Number(
      src.priceUsd != null
        ? src.priceUsd
        : computeUsdFromInr(priceInr, intlMeta)
    );
    if (!Number.isFinite(priceInr) || priceInr < 1) {
      throw new HttpsError(
        "invalid-argument",
        `Invalid INR price for ${months}-month plan`
      );
    }
    if (!Number.isFinite(priceUsd) || priceUsd < 0.5) {
      throw new HttpsError(
        "invalid-argument",
        `Invalid USD price for ${months}-month plan`
      );
    }
    if (!Number.isFinite(maxAttachmentFiles) || maxAttachmentFiles < 0) {
      throw new HttpsError(
        "invalid-argument",
        `Invalid file limit for ${months}-month plan`
      );
    }
    plans[months] = {
      priceInr: Math.round(priceInr),
      priceUsd: Math.round(priceUsd * 100) / 100,
      maxAttachmentFiles: Math.round(maxAttachmentFiles),
    };
  }

  const trialFiles = Number(
    (incoming.trial && incoming.trial.maxAttachmentFiles) != null
      ? incoming.trial.maxAttachmentFiles
      : incoming.trialMaxAttachmentFiles != null
        ? incoming.trialMaxAttachmentFiles
        : fallback.trial.maxAttachmentFiles
  );
  if (!Number.isFinite(trialFiles) || trialFiles < 0) {
    throw new HttpsError("invalid-argument", "Invalid trial file limit");
  }

  const maxAttachmentBytes = Number(
    incoming.maxAttachmentBytes != null
      ? incoming.maxAttachmentBytes
      : fallback.maxAttachmentBytes
  );

  const fileUpgradePlans = {};
  for (const months of Object.keys(DEFAULT_FILE_UPGRADE_PLANS)) {
    const src =
      (incoming.fileUpgradePlans &&
        (incoming.fileUpgradePlans[months] ||
          incoming.fileUpgradePlans[Number(months)])) ||
      {};
    const def = fallback.fileUpgradePlans[months];
    const priceInr = Number(
      src.priceInr != null ? src.priceInr : def.priceInr
    );
    const priceUsd = Number(
      src.priceUsd != null
        ? src.priceUsd
        : computeUsdFromInr(priceInr, intlMeta)
    );
    const maxAttachmentFiles = Number(
      src.maxAttachmentFiles != null
        ? src.maxAttachmentFiles
        : def.maxAttachmentFiles
    );
    if (!Number.isFinite(priceInr) || priceInr < 1) {
      throw new HttpsError(
        "invalid-argument",
        `Invalid file-upgrade INR price for ${months}-month plan`
      );
    }
    if (!Number.isFinite(priceUsd) || priceUsd < 0.5) {
      throw new HttpsError(
        "invalid-argument",
        `Invalid file-upgrade USD price for ${months}-month plan`
      );
    }
    if (!Number.isFinite(maxAttachmentFiles) || maxAttachmentFiles < 0) {
      throw new HttpsError(
        "invalid-argument",
        `Invalid file-upgrade limit for ${months}-month plan`
      );
    }
    fileUpgradePlans[months] = {
      priceInr: Math.round(priceInr),
      priceUsd: Math.round(priceUsd * 100) / 100,
      maxAttachmentFiles: Math.round(maxAttachmentFiles),
    };
  }

  const catalog = {
    schemaVersion: CATALOG_SCHEMA_VERSION,
    inrToUsdRate,
    internationalMultiplier,
    plans,
    fileUpgradePlans,
    trial: {
      days: 15,
      maxAttachmentFiles: Math.round(trialFiles),
    },
    maxAttachmentBytes: Math.round(maxAttachmentBytes),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: request.auth.uid,
  };

  await db.collection(CONFIG_PATH[0]).doc(CONFIG_PATH[1]).set(catalog, {
    merge: true,
  });

  return {
    ok: true,
    catalog: await loadCatalog(),
  };
});

/** Admin: subscription GST (India checkout adds GST on top of catalog INR price). */
exports.adminUpdateSubscriptionGst = onCall(async (request) => {
  requireAdmin(request);
  const incoming = request.data || {};
  const fallback = { ...DEFAULT_SUBSCRIPTION_GST };
  const gstPercent = Number(
    incoming.gstPercent != null ? incoming.gstPercent : fallback.gstPercent
  );
  if (!Number.isFinite(gstPercent) || gstPercent < 0 || gstPercent > 40) {
    throw new HttpsError("invalid-argument", "GST percent must be 0–40");
  }
  const platformGstin = String(incoming.platformGstin ?? fallback.platformGstin)
    .trim()
    .toUpperCase();
  const platformStateCode =
    String(incoming.platformStateCode ?? "").trim().slice(0, 2) ||
    stateCodeFromGstin(platformGstin) ||
    fallback.platformStateCode;
  const platformLegalName = String(
    incoming.platformLegalName ?? fallback.platformLegalName
  ).trim();
  const platformAddress = String(
    incoming.platformAddress ?? fallback.platformAddress
  ).trim();

  const gst = {
    gstPercent: Math.round(gstPercent * 100) / 100,
    platformGstin,
    platformStateCode,
    platformLegalName: platformLegalName || fallback.platformLegalName,
    platformAddress,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: request.auth.uid,
  };

  await db.doc(GST_CONFIG_PATH.join("/")).set(gst, { merge: true });
  return { ok: true, gst: await loadSubscriptionGstConfig() };
});

/** Admin: assign paid months plan, lifetime free, or revoke plan. */
exports.adminUpdateUserPlan = onCall(async (request) => {
  requireAdmin(request);
  const targetUserId = String(request.data?.targetUserId || "").trim();
  const lifetimeFree = request.data?.lifetimeFree === true;
  const revokePlan = request.data?.revokePlan === true;
  const months = Number(request.data?.months);
  const catalog = await loadCatalog();

  if (!targetUserId) {
    throw new HttpsError("invalid-argument", "targetUserId required");
  }

  const userRef = db.collection("users").doc(targetUserId);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpsError("not-found", "User not found");
  }
  const user = userSnap.data() || {};
  if (isProtectedAdminUser(user)) {
    throw new HttpsError(
      "failed-precondition",
      "Cannot change plan for the admin account"
    );
  }
  const now = new Date();
  const beforePlan = mapUserDoc(targetUserId, user);

  if (revokePlan) {
    await db.collection("subscriptions").doc(targetUserId).set(
      {
        userId: targetUserId,
        type: "revoked",
        months: null,
        priceInr: 0,
        activatedAt: now.toISOString(),
        expiresAt: now.toISOString(),
        lastExpiresAt: now.toISOString(),
        subscriptionPlan: "revoked",
        isLifetimeFree: false,
        paymentGateway: "admin",
        updatedByAdmin: true,
        verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    await userRef.set(
      {
        subscriptionExpiresAt: now.toISOString(),
        lastExpiresAt: now.toISOString(),
        isTrialActive: false,
        subscriptionPlanMonths: admin.firestore.FieldValue.delete(),
        subscriptionPlan: "revoked",
        isLifetimeFree: false,
        paymentGateway: "admin",
      },
      { merge: true }
    );

    await writeAdminAuditLog(request, {
      action: "revoke_plan",
      targetUserId,
      targetEmail: user.email || "",
      targetDisplayName: user.displayName || "",
      payload: {
        before: {
          planLabel: beforePlan.planLabel,
          subscriptionPlanMonths: beforePlan.subscriptionPlanMonths,
          isLifetimeFree: beforePlan.isLifetimeFree,
        },
        after: { planLabel: "Plan expired" },
      },
    });

    return {
      ok: true,
      revoked: true,
      user: mapUserDoc(targetUserId, {
        ...user,
        subscriptionExpiresAt: now.toISOString(),
        lastExpiresAt: now.toISOString(),
        isTrialActive: false,
        subscriptionPlanMonths: null,
        subscriptionPlan: "revoked",
        isLifetimeFree: false,
      }),
    };
  }

  if (lifetimeFree) {
    const lifetimeFiles =
      Number(catalog?.lifetimeFreeMaxAttachmentFiles) ||
      Number(catalog?.plans?.["24"]?.maxAttachmentFiles) ||
      Number(catalog?.plans?.[24]?.maxAttachmentFiles) ||
      25;

    await db.collection("subscriptions").doc(targetUserId).set(
      {
        userId: targetUserId,
        type: "lifetime_free",
        months: null,
        priceInr: 0,
        activatedAt: now.toISOString(),
        expiresAt: null,
        lastExpiresAt: null,
        subscriptionPlan: "lifetime_free",
        isLifetimeFree: true,
        maxAttachmentFiles: lifetimeFiles,
        paymentGateway: "admin",
        updatedByAdmin: true,
        verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    await userRef.set(
      {
        subscriptionExpiresAt: admin.firestore.FieldValue.delete(),
        lastExpiresAt: admin.firestore.FieldValue.delete(),
        isTrialActive: false,
        subscriptionPlanMonths: admin.firestore.FieldValue.delete(),
        subscriptionPlan: "lifetime_free",
        isLifetimeFree: true,
        lifetimeFreeMaxAttachmentFiles: lifetimeFiles,
        paymentGateway: "admin",
      },
      { merge: true }
    );

    await writeAdminAuditLog(request, {
      action: "grant_lifetime_free",
      targetUserId,
      targetEmail: user.email || "",
      targetDisplayName: user.displayName || "",
      payload: {
        before: {
          planLabel: beforePlan.planLabel,
          subscriptionPlanMonths: beforePlan.subscriptionPlanMonths,
          isLifetimeFree: beforePlan.isLifetimeFree,
        },
        after: { planLabel: "Lifetime free", isLifetimeFree: true },
      },
    });

    return {
      ok: true,
      lifetimeFree: true,
      expiresAt: null,
      months: null,
      priceInr: 0,
      user: mapUserDoc(targetUserId, {
        ...user,
        subscriptionExpiresAt: null,
        lastExpiresAt: null,
        isTrialActive: false,
        subscriptionPlanMonths: null,
        subscriptionPlan: "lifetime_free",
        isLifetimeFree: true,
      }),
    };
  }

  const priceInr = priceFromCatalog(catalog, months);
  if (!priceInr) {
    throw new HttpsError("invalid-argument", "Invalid plan months");
  }

  // Admin plan changes also replace from now (no leftover carry-over).
  const expiry = addMonths(now, months);
  const expiresAtIso = expiry.toISOString();

  await db.collection("subscriptions").doc(targetUserId).set(
    {
      userId: targetUserId,
      type: "paid",
      months,
      priceInr,
      activatedAt: now.toISOString(),
      expiresAt: expiresAtIso,
      lastExpiresAt: expiresAtIso,
      subscriptionPlan: `${months}_month`,
      isLifetimeFree: false,
      paymentGateway: "admin",
      updatedByAdmin: true,
      verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  await userRef.set(
    {
      subscriptionExpiresAt: expiresAtIso,
      lastExpiresAt: expiresAtIso,
      isTrialActive: false,
      subscriptionPlanMonths: months,
      subscriptionPlan: `${months}_month`,
      isLifetimeFree: false,
      paymentGateway: "admin",
    },
    { merge: true }
  );

  await writeAdminAuditLog(request, {
    action: "grant_plan",
    targetUserId,
    targetEmail: user.email || "",
    targetDisplayName: user.displayName || "",
    payload: {
      months,
      priceInr,
      expiresAt: expiresAtIso,
      before: {
        planLabel: beforePlan.planLabel,
        subscriptionPlanMonths: beforePlan.subscriptionPlanMonths,
        isLifetimeFree: beforePlan.isLifetimeFree,
      },
      after: {
        planLabel: `${months}-month plan`,
        subscriptionPlanMonths: months,
        expiresAt: expiresAtIso,
      },
    },
  });

  return {
    ok: true,
    lifetimeFree: false,
    expiresAt: expiresAtIso,
    months,
    priceInr,
    user: mapUserDoc(targetUserId, {
      ...user,
      subscriptionExpiresAt: expiresAtIso,
      lastExpiresAt: expiresAtIso,
      isTrialActive: false,
      subscriptionPlanMonths: months,
      isLifetimeFree: false,
    }),
  };
});

/** Admin: block / unblock user. */
exports.adminSetUserBlocked = onCall(async (request) => {
  requireAdmin(request);
  const targetUserId = String(request.data?.targetUserId || "").trim();
  const blocked = request.data?.blocked === true;

  if (!targetUserId) {
    throw new HttpsError("invalid-argument", "targetUserId required");
  }

  const userRef = db.collection("users").doc(targetUserId);
  const snap = await userRef.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "User not found");
  }
  const email = (snap.data()?.email || "").toLowerCase();
  if (isProtectedAdminUser(snap.data())) {
    throw new HttpsError(
      "failed-precondition",
      "Cannot block the admin account"
    );
  }

  const userData = snap.data() || {};

  await userRef.set(
    {
      isBlocked: blocked,
      blockedAt: blocked
        ? admin.firestore.FieldValue.serverTimestamp()
        : admin.firestore.FieldValue.delete(),
    },
    { merge: true }
  );

  await writeAdminAuditLog(request, {
    action: blocked ? "block_user" : "unblock_user",
    targetUserId,
    targetEmail: userData.email || "",
    targetDisplayName: userData.displayName || "",
    payload: { blocked },
  });

  return { ok: true, targetUserId, blocked };
});

/** Admin: permanently delete user account + vault data (audit log kept). */
exports.adminDeleteUser = onCall(async (request) => {
  requireAdmin(request);
  const targetUserId = String(request.data?.targetUserId || "").trim();

  if (!targetUserId) {
    throw new HttpsError("invalid-argument", "targetUserId required");
  }

  if (targetUserId === request.auth.uid) {
    throw new HttpsError(
      "failed-precondition",
      "Cannot delete your own admin account"
    );
  }

  const userRef = db.collection("users").doc(targetUserId);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpsError("not-found", "User not found");
  }

  const userData = userSnap.data() || {};
  if (isProtectedAdminUser(userData)) {
    throw new HttpsError(
      "failed-precondition",
      "Cannot delete the admin account"
    );
  }

  const userSnapshot = mapUserDoc(targetUserId, userData);

  await writeAdminAuditLog(request, {
    action: "delete_user",
    targetUserId,
    targetEmail: userData.email || "",
    targetDisplayName: userData.displayName || "",
    payload: {
      deletedUser: userSnapshot,
      reason: String(request.data?.reason || "").slice(0, 500) || null,
    },
  });

  await Promise.all([
    deleteCollection(userRef.collection("credentials")),
    deleteCollection(userRef.collection("groups")),
  ]);

  await deleteUserStorageFiles(targetUserId);

  await Promise.all([
    userRef.delete(),
    db.collection("subscriptions").doc(targetUserId).delete(),
  ]);

  try {
    await admin.auth().deleteUser(targetUserId);
  } catch (err) {
    console.warn("adminDeleteUser auth:", targetUserId, err.message);
  }

  return { ok: true, targetUserId, deleted: true };
});

/** Mark own payment order failed / cancelled. */
exports.markPaymentFailed = onCall(async (request) => {
  const uid = requireAuth(request);
  const orderId = String(request.data?.orderId || "").trim();
  const reason = String(request.data?.reason || "cancelled").slice(0, 200);
  if (!orderId) {
    throw new HttpsError("invalid-argument", "orderId required");
  }
  const ref = db.collection("paymentOrders").doc(orderId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Order not found");
  }
  const data = snap.data() || {};
  if (data.userId !== uid) {
    throw new HttpsError("permission-denied", "Not your order");
  }
  if (data.status === "paid") {
    return { ok: true, alreadyPaid: true };
  }
  await ref.set(
    {
      status: "failed",
      failReason: reason,
      failedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  return { ok: true };
});

/**
 * Sends a 6-digit OTP to verify recovery mobile or recovery email.
 * Input: { channel: "mobile"|"email", target: string }
 * Stores hashed OTP on users/{uid}.recoveryOtp*
 * Without SMTP, returns debugOtp so the app can still complete verification in test.
 */
exports.sendRecoveryOtp = onCall(async (request) => {
  const uid = requireAuth(request);
  const channel = String(request.data?.channel || "").trim().toLowerCase();
  const target = String(request.data?.target || "").trim();

  if (channel !== "mobile" && channel !== "email") {
    throw new HttpsError("invalid-argument", "channel must be mobile or email");
  }
  if (!target) {
    throw new HttpsError("invalid-argument", "target required");
  }
  if (channel === "mobile" && target.replace(/\D/g, "").length < 10) {
    throw new HttpsError("invalid-argument", "Enter a valid mobile number");
  }
  if (channel === "email" && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(target)) {
    throw new HttpsError("invalid-argument", "Enter a valid recovery email");
  }

  const otp = String(Math.floor(100000 + Math.random() * 900000));
  const salt = crypto.randomBytes(16).toString("hex");
  const hash = crypto
    .createHash("sha256")
    .update(`${uid}:${channel}:${target}:${otp}:${salt}`)
    .digest("hex");
  const expiresAt = Date.now() + 10 * 60 * 1000;

  await db
    .collection("users")
    .doc(uid)
    .set(
      {
        recoveryOtpHash: hash,
        recoveryOtpSalt: salt,
        recoveryOtpChannel: channel,
        recoveryOtpTarget: target,
        recoveryOtpExpiresAt: expiresAt,
        recoveryOtpUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

  // Queue for Trigger Email extension (optional). Harmless if unused.
  try {
    if (channel === "email") {
      await db.collection("mail").add({
        to: [target],
        message: {
          subject: "PasswordSaver recovery email verification",
          text: `Your PasswordSaver verification code is ${otp}. It expires in 10 minutes.`,
          html: `<p>Your PasswordSaver verification code is <strong>${otp}</strong>.</p><p>It expires in 10 minutes.</p>`,
        },
      });
    }
  } catch (_) {
    // Ignore mail queue failures — OTP still verifiable via debug/test path.
  }

  return {
    ok: true,
    channel,
    target,
    expiresInSec: 600,
    // Returned so OTP works without SMS/SMTP during setup. Remove later for prod.
    debugOtp: otp,
  };
});

/**
 * Verifies recovery OTP and marks the field verified on the user profile.
 * Input: { channel: "mobile"|"email", target: string, otp: string }
 */
exports.verifyRecoveryOtp = onCall(async (request) => {
  const uid = requireAuth(request);
  const channel = String(request.data?.channel || "").trim().toLowerCase();
  const target = String(request.data?.target || "").trim();
  const otp = String(request.data?.otp || "").trim();

  if (channel !== "mobile" && channel !== "email") {
    throw new HttpsError("invalid-argument", "channel must be mobile or email");
  }
  if (!/^\d{6}$/.test(otp)) {
    throw new HttpsError("invalid-argument", "Enter the 6-digit OTP");
  }
  if (!target) {
    throw new HttpsError("invalid-argument", "target required");
  }

  const ref = db.collection("users").doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "User profile not found");
  }
  const d = snap.data() || {};
  const expiresAt = Number(d.recoveryOtpExpiresAt || 0);
  if (!d.recoveryOtpHash || !d.recoveryOtpSalt || Date.now() > expiresAt) {
    throw new HttpsError("failed-precondition", "OTP expired. Request a new one.");
  }
  if (d.recoveryOtpChannel !== channel || d.recoveryOtpTarget !== target) {
    throw new HttpsError(
      "failed-precondition",
      "OTP does not match this number/email. Request a new one."
    );
  }

  const expected = crypto
    .createHash("sha256")
    .update(`${uid}:${channel}:${target}:${otp}:${d.recoveryOtpSalt}`)
    .digest("hex");
  const a = Buffer.from(expected, "utf8");
  const b = Buffer.from(String(d.recoveryOtpHash || ""), "utf8");
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    throw new HttpsError("permission-denied", "Incorrect OTP");
  }

  const patch = {
    recoveryOtpHash: admin.firestore.FieldValue.delete(),
    recoveryOtpSalt: admin.firestore.FieldValue.delete(),
    recoveryOtpChannel: admin.firestore.FieldValue.delete(),
    recoveryOtpTarget: admin.firestore.FieldValue.delete(),
    recoveryOtpExpiresAt: admin.firestore.FieldValue.delete(),
    recoveryOtpVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (channel === "mobile") {
    patch.primaryMobile = target;
    patch.primaryMobileVerified = true;
  } else {
    patch.secondaryMobile = target;
    patch.recoveryEmail = target;
    patch.recoveryEmailVerified = true;
  }

  await ref.set(patch, { merge: true });
  return { ok: true, channel, target, verified: true };
});

/**
 * Saves the user's country once after login.
 * Input: { countryCode: "IN", countryName: "India" }
 */
exports.setUserCountry = onCall(async (request) => {
  const uid = requireAuth(request);
  const countryCode = String(request.data?.countryCode || "")
    .trim()
    .toUpperCase();
  const countryNameInput = String(request.data?.countryName || "").trim();

  if (!countryCode || countryCode.length !== 2) {
    throw new HttpsError("invalid-argument", "Invalid country code");
  }

  const canonicalName = ALLOWED_COUNTRIES[countryCode];
  if (!canonicalName) {
    throw new HttpsError("invalid-argument", "Country not supported");
  }
  if (
    countryNameInput &&
    countryNameInput.toLowerCase() !== canonicalName.toLowerCase()
  ) {
    throw new HttpsError("invalid-argument", "Country name does not match code");
  }

  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  const user = userSnap.data() || {};

  const existing = String(user.countryCode || "")
    .trim()
    .toUpperCase();
  if (existing) {
    if (existing !== countryCode) {
      throw new HttpsError(
        "failed-precondition",
        "Country already selected and cannot be changed"
      );
    }
    return {
      ok: true,
      countryCode: existing,
      countryName: user.countryName || ALLOWED_COUNTRIES[existing],
      alreadySet: true,
    };
  }

  await userRef.set(
    {
      countryCode,
      countryName: canonicalName,
      countrySelectedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return {
    ok: true,
    countryCode,
    countryName: canonicalName,
    alreadySet: false,
  };
});
