# PasswordSaver Admin Web

Browser admin console for **PasswordSaver** — dynamic pricing, users, and Razorpay payments.

Uses the same Firebase project (`password-saver-b7f21`) and Cloud Functions as the mobile app.

## Setup

```bash
cd admin-web
cp .env.example .env
# Edit .env — add Firebase Web App ID from Firebase Console
npm install
npm run dev
```

Open http://localhost:5174/admin/login

**Admin login:** `passwordsaver@gryzion.com` (same as mobile admin)

## Features

| Page | Description |
|------|-------------|
| Overview | User & payment stats |
| Pricing & Plans | Edit base plans, file upgrades, trial limits — **app reads dynamically** |
| Payments | Razorpay order history |
| Users | Block/unblock, grant plan, lifetime free |

## Run locally (Firebase Hosting disabled)

```bash
npm run dev
```

Open http://localhost:5174/admin/login

## Deploy (optional — hosting not configured in firebase.json)

Admin web runs locally only. To re-enable Firebase Hosting, add a `hosting` block back to `firebase.json` and run `firebase deploy --only hosting`.

## How dynamic pricing works

1. Admin saves pricing in this web console
2. `adminUpdateSubscriptionConfig` Cloud Function writes to `appConfig/subscription`
3. Mobile app calls `getSubscriptionCatalog` on startup / subscription screen
4. Razorpay checkout uses **server-side** prices from the same catalog
