# PasswordSaver

End-to-end encrypted password vault built with **Flutter + Clean Architecture + Firebase**.

## Features (mapped to requirements)

| # | Feature | Status |
|---|---------|--------|
| 1 | Splash + PIN gate | Done |
| 2 | Login (Google / email) + device details | Done |
| 3 | Sign-up + email verify (Firebase) | Done |
| 4 | Reset password | Done |
| 5 | Terms & Conditions (E2E encryption) | Done |
| 6 | Dashboard for daily platforms | Done |
| 7 | AES-256 encryption | Done |
| 8 | Re-verify to view password | Done |
| 9 | App PIN every launch | Done |
| 10 | Settings toggle + PIN update / recovery | Done |
| 11 | Two-way recovery | Done |
| 12 | Multiple accounts per platform | Done |
| 13 | Delete / update with PIN | Done |
| 14 | Free 3-month trial | Done |
| 15 | Plans 3/6/12/24 (₹100/180/350/650) | Done |
| 16 | Header/footer AdMob banners only | Done |
| 17 | Nav: Home / Settings / Ads / Profile | Done |
| 18 | Advanced UI | Done |
| 19 | Disable screenshot / recording | Done |
| 20 | Disable rotation | Done |
| 21 | Firebase wiring | Done (needs your project config) |

## Clean Architecture

```
lib/
  core/           # theme, constants, security helpers
  domain/         # entities + repository contracts
  data/           # Firebase / local demo implementations
  presentation/   # screens, providers, widgets, shell
```

## Run

```bash
flutter pub get
flutter run
```

Firebase Auth (Email/Password + Google) and Firestore must be enabled in project `password-saver-b7f21`.

## Enable Firebase (production)

1. Android app package: `com.gryzion.passwordsaver` — `android/app/google-services.json` is already in place.
2. Enable **Email/Password** and **Google** sign-in in Firebase Authentication.
3. Add your debug/release SHA-1 fingerprints in Firebase Console for Google Sign-In.
4. Create Firestore; deploy rules: `firebase deploy --only firestore:rules` (see `firestore.rules`).
5. Replace AdMob test IDs in `lib/core/constants/app_constants.dart` and `AndroidManifest.xml`.

### Cross-device login

The AES master key is stored on Firebase **only as ciphertext**:

| Field | Contents |
|-------|----------|
| `wrappedMasterKey` | Master key encrypted with a wrap key |
| `masterKeyWrapSalt` | Salt used to derive the wrap key |

- **Email login:** wrap key = PBKDF2(account password + salt)
- **Google login:** wrap key = PBKDF2(stable Google account id + salt)

Plaintext `masterKeyBase64` is never stored. On a new device, login unwraps the key so synced passwords decrypt.

## Security notes

- Passwords are encrypted with **AES-256-CBC** on-device; only ciphertext is synced to Firestore.
- The AES master key is uploaded **wrapped** (not plaintext); Firebase cannot read vault passwords without the account secret.
- App PIN is stored as a **salted SHA-256 hash** in secure storage — never plaintext.
- Android `FLAG_SECURE` + `screen_protector` block screenshots/recording.
- Portrait orientation is locked in Flutter and AndroidManifest.
