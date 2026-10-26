#!/usr/bin/env bash
# Deploy PasswordSaver Cloud Functions + Firestore rules + Razorpay secrets.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="${FIREBASE_PROJECT:-password-saver-b7f21}"

if [[ -f "$ROOT/scripts/razorpay.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/scripts/razorpay.env"
fi

KEY_ID="${RAZORPAY_KEY_ID:-}"
KEY_SECRET="${RAZORPAY_KEY_SECRET:-}"

echo "==> Project: $PROJECT"
firebase use "$PROJECT"

echo "==> Installing functions dependencies"
(cd functions && npm install)

if [[ -z "$KEY_ID" || -z "$KEY_SECRET" ]]; then
  echo ""
  echo "PasswordSaver Razorpay keys required (do NOT use Snapbilling keys)."
  echo ""
  echo "Option A — create scripts/razorpay.env from example:"
  echo "  cp scripts/razorpay.env.example scripts/razorpay.env"
  echo "  # edit with PasswordSaver Key ID + Secret from Razorpay Dashboard"
  echo "  ./scripts/deploy_functions.sh"
  echo ""
  echo "Option B — export env vars:"
  echo "  export RAZORPAY_KEY_ID='rzp_live_...'"
  echo "  export RAZORPAY_KEY_SECRET='...'"
  echo "  ./scripts/deploy_functions.sh"
  exit 1
fi

if [[ "$KEY_ID" == *"TKc6lOuSqifXtE"* ]]; then
  echo "ERROR: Detected Snapbilling test Key ID. Use PasswordSaver Razorpay keys."
  exit 1
fi

echo "==> Setting RAZORPAY_KEY_ID secret (PasswordSaver)"
printf '%s' "$KEY_ID" | firebase functions:secrets:set RAZORPAY_KEY_ID --data-file=- --project "$PROJECT"

echo "==> Setting RAZORPAY_KEY_SECRET secret (Firebase only — never in app)"
printf '%s' "$KEY_SECRET" | firebase functions:secrets:set RAZORPAY_KEY_SECRET --data-file=- --project "$PROJECT"

echo "==> Deploying functions + firestore rules"
firebase deploy --only functions,firestore:rules --project "$PROJECT"

echo ""
echo "✅ Done."
echo "Key ID is returned to the app from createRazorpayOrder."
echo "Key Secret stays in Firebase — used only for verifyRazorpayPayment."
echo "Callables (asia-south1): createRazorpayOrder, verifyRazorpayPayment"
