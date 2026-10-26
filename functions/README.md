# Cloud Functions — Razorpay (PasswordSaver)

Use a **separate Razorpay merchant account / API keys** for PasswordSaver.
Do not reuse Snapbilling keys — otherwise checkout shows Snapbilling branding
and payments mix between apps.

## Architecture

| Key | Where it lives | Purpose |
|-----|----------------|---------|
| **Key ID** (`rzp_live_…` / `rzp_test_…`) | Firebase secret `RAZORPAY_KEY_ID` → returned to app in `createRazorpayOrder` | Opens Razorpay checkout |
| **Key Secret** | Firebase secret `RAZORPAY_KEY_SECRET` only | Order create, signature verify, payment fetch |

The Flutter app **never** contains the Key Secret. Verification runs in
`verifyRazorpayPayment` on the server.

## 1. Prerequisites

- Firebase project `password-saver-b7f21` on **Blaze** plan
- PasswordSaver Razorpay account (dashboard.razorpay.com)
- Firebase CLI: `npm i -g firebase-tools` && `firebase login`

## 2. Set secrets (one time)

```bash
cp scripts/razorpay.env.example scripts/razorpay.env
# Edit scripts/razorpay.env with PasswordSaver Key ID + Secret

./scripts/deploy_functions.sh
```

Or manually:

```bash
firebase functions:secrets:set RAZORPAY_KEY_ID --project password-saver-b7f21
firebase functions:secrets:set RAZORPAY_KEY_SECRET --project password-saver-b7f21
firebase deploy --only functions --project password-saver-b7f21
```

In Razorpay Dashboard for PasswordSaver, set **Brand name** = PasswordSaver and
upload logo (or use checkout `image` URL from hosting).

## 3. App payment flow

1. App → `createRazorpayOrder({ months, planType })`
2. Server creates order with **PasswordSaver** keys, returns `orderId`, `keyId`, amount
3. App opens Razorpay checkout with returned `keyId`
4. On success → `verifyRazorpayPayment({ orderId, paymentId, signature, months })`
5. Server verifies HMAC with **Key Secret**, confirms with Razorpay API, activates plan

## Callable functions (region `asia-south1`)

- `createRazorpayOrder`
- `verifyRazorpayPayment`
- `getSubscriptionCatalog`
- `adminUpdateSubscriptionConfig`
- `adminUpdateSubscriptionGst`
