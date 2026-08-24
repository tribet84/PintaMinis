# PintaMinis 🎨🔨

Miniature paint inventory, cross-platform (Android, iOS and web), built with **Flutter**.

- **Built-in catalog** with paints from **Citadel**, **Vallejo** (Model Color and Game Color), **The Army Painter** and **Green Stuff World**, searchable by name, code and range, with per-brand filters.
- **My inventory**: mark the paints you own and the ones that are **running low**.
- **Lists** in one place: the built-in shopping list first, then your own lists for a miniature, a unit or a whole army, each with a readiness verdict telling you whether its paints are running out.
- **Automatic shopping list**: nearly empty paints plus the ones you want to buy, grouped by section and brand, with **copy** and **share** buttons.
- **Recipes**: save how you painted a miniature, section by section, as **ordered steps** — "Basecoat: Leadbelcher (heavy drybrush) → Wash: Agrax Earthshade → …" — plus techniques, free-form notes, and links to the pages or videos that inspired it. One tap puts the paints you are missing on the shopping list.
- **Recipe sharing**: publish a recipe and share its link. Other painters **link** it into their account instead of cloning it, so when the author updates the recipe everyone sees the latest version, and the author sees how many painters have linked it. New accounts start with a deletable example recipe that shows how all of this works.
- **Sign-in** with email/password and **Google Sign-In** (Firebase Auth).
- **Cloud sync** with Cloud Firestore (works offline too).
- **English and Spanish UI** (follows the system language).
- **Ready for Google Ads (AdMob)**, disabled by default.

## Getting started

Requirements: [Flutter](https://docs.flutter.dev/get-started/install) 3.35+ (Dart SDK 3.9+).

```bash
flutter pub get
flutter gen-l10n   # also runs automatically on build
flutter test
```

### 1. Configure Firebase (required for sign-in and sync)

The app compiles without configuration, but boots in "setup pending" mode until you connect your Firebase project:

1. Create a project in the [Firebase Console](https://console.firebase.google.com/).
2. Install and run the FlutterFire CLI from the repo root:

   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```

   This regenerates `lib/firebase_options.dart` (currently a placeholder) and downloads `google-services.json` / `GoogleService-Info.plist`.
3. In Firebase Console → **Authentication → Sign-in method**, enable **Email/Password** and **Google**.
4. In Firebase Console → **Firestore Database**, create the database and deploy the bundled rules:

   ```bash
   firebase deploy --only firestore:rules
   ```

#### Platform notes

- **Bundle ID**: `com.robermac.paintforge` on both Android (`android/app/build.gradle.kts`) and iOS (`ios/Runner.xcodeproj`). Changing it requires re-running `flutterfire configure` so Firebase registers the new app.
- **Android**: for Google Sign-In you must register your keystore **SHA-1** fingerprint in the Firebase project settings (Project settings → Your apps → Add fingerprint).
- **iOS**: `flutterfire configure` needs the `xcodeproj` Ruby gem (`gem install --user-install xcodeproj`), otherwise it aborts with `cannot load such file -- xcodeproj`. The Google Sign-In callback scheme in `ios/Runner/Info.plist` must stay in sync with `REVERSED_CLIENT_ID` from `GoogleService-Info.plist`.
- **App Store**: if you ship on iOS with Google Sign-In, Apple also requires offering **Sign in with Apple**. It is not implemented yet; add it before publishing to the App Store.

### 2. Ads (AdMob) — optional, disabled by default

The `google_mobile_ads` integration is already in place and tested with Google's **test** IDs. To enable it:

1. Create the app in [AdMob](https://admob.google.com/) and get your **App ID** and **ad unit IDs**.
2. Replace the test IDs:
   - Android App ID: `android/app/src/main/AndroidManifest.xml` (`com.google.android.gms.ads.APPLICATION_ID`).
   - iOS App ID: `ios/Runner/Info.plist` (`GADApplicationIdentifier`).
   - Banner ad units: `lib/src/services/ads_service.dart`.
3. Build with the flag:

   ```bash
   flutter run --dart-define=ENABLE_ADS=true
   ```

Without the flag, the app never initializes the ads SDK nor shows banners.

### 3. Run

```bash
flutter run                # Android or iOS device/emulator
flutter run -d chrome      # web
```

### 4. Deploy to the web (Firebase Hosting)

**Every push to `main` deploys automatically** via
`.github/workflows/deploy.yml`: `flutter test` and `flutter analyze` gate the
deploy, then hosting (both `app` and `site`), Firestore rules/indexes and
Storage rules all go out together. Pull requests run the same test job
without deploying, so a broken PR shows red before it merges. There is no
longer a manual step to remember — this exists because a commit once sat on
`main`, fully merged, without ever reaching production.

The steps below are for local/manual deploys only — a hotfix from a laptop,
or testing a build before it lands on `main`.

**Cloud Functions deploy manually** (`firebase deploy --only functions`),
not through CI: the pipeline's service account is scoped to hosting and
rules on purpose, and the single function (`sharePreview`, the share-link
Open Graph previews) changes rarely enough that widening CI's blast radius
for it is a bad trade.

The repo ships with `firebase.json` (Hosting + Firestore rules) and `.firebaserc`
pointing at the `paintforge-d8cf2` project. Hosting serves `build/web` and rewrites
every route to `index.html`, so Flutter's router owns navigation.

```bash
flutter build web --release \
  --dart-define=RECAPTCHA_SITE_KEY=<key> \
  --dart-define=PHOTO_CDN_HOST=img.pintaminis.com \
  --dart-define=BUILD_STAMP=$(date +%Y-%m-%d)-$(git rev-parse --short HEAD)
firebase deploy --only hosting
```

**The `RECAPTCHA_SITE_KEY` define is not optional for production.** App Check
enforcement is ON for Firestore and Storage, so a build without the key signs
in fine (Auth is unenforced) and then hangs forever on the first loader: the
Firestore streams are rejected server-side, and the SDK just keeps retrying.
The key is not a secret (it ships inside `main.dart.js`); find it with
`gcloud recaptcha keys list --project=paintforge-d8cf2`.

Live at <https://pintaminis.com> — that domain also serves the project site
and legal documents (the `docs/` folder). The app itself is at
<https://app.pintaminis.com>.

Hosting serves two sites from one project: `app` (the Flutter build) and `site`
(the `docs/` folder, at the bare apex domain). Deploy them separately with
`--only hosting:app` or `--only hosting:site`.

Both domains resolve straight to Firebase Hosting's own global CDN — DNS-only,
deliberately NOT behind Cloudflare's proxy: Spanish ISPs block Cloudflare's
shared IP ranges during LaLiga match windows (anti-piracy court orders), and
proxied domains go down as collateral damage. Photos are the one exception:
`img.pintaminis.com` is a Cloudflare Worker that edge-caches Firebase Storage
downloads (Storage egress is the metric with a real ceiling on the free
tier). During a block window photos may fail on affected ISPs — they degrade
softly to an empty slot — while the app itself stays reachable.

To deploy the security rules together with the site:

```bash
firebase deploy --only hosting,firestore:rules
```

`index.html` and `flutter_bootstrap.js` are served with `no-cache` headers so a new
release is picked up immediately; the hashed asset bundles keep Hosting's default
long-lived caching.

## Paint catalog

The catalog lives in `assets/catalog/*.json` (one file per brand) and ships with the app, so search works offline. It is a representative starter catalog (~240 paints); to extend a brand just add entries to the JSON:

```json
{"id": "citadel-nuevo-color", "name": "Nuevo Color", "range": "Layer", "code": null, "hex": "#AABBCC"}
```

The `id` values must be unique: they are the key your inventory is stored under in Firestore, so do not change them once in use. The `hex` colors are approximate, for the UI swatch.

## Architecture

```
lib/
├── main.dart                  # bootstrap: Firebase, ads, catalog
├── firebase_options.dart      # placeholder → generated by flutterfire configure
├── l10n/                      # translations (app_en.arb, app_es.arb)
└── src/
    ├── app.dart               # MaterialApp, providers, auth gate
    ├── theme.dart             # Material 3, forge-orange seed
    ├── models/                # Paint, InventoryEntry, Purchase, PaintList
    ├── data/                  # catalog (assets), inventory, purchases, lists
    ├── services/              # AuthService, AdsService, ShoppingListFormatter
    ├── state/                 # InventoryProvider, PaintListsProvider
    ├── widgets/               # swatch, tiles, sheets, dialogs, banner
    └── features/              # auth, catalog, inventory, lists, shopping,
                               # history, settings
```

Paint states: **Owned** (`inStock`), **Running low** (`low`) and **To buy** (`wishlist`). The shopping list is the last two; the "Bought it" button asks for confirmation and a quantity, records the purchase and returns the paint to `inStock`.

### The shopping list is derived, not stored

The shopping list is pinned as the first entry of the Lists tab, cannot be deleted or renamed, and exists in every account from day one — because it is **not** a document. It is a query over the inventory: every paint marked `low` or `wishlist`.

Storing it as a `paintLists` document would create a second source of truth for "I need to buy this" that could drift from the paint statuses, and would need a bootstrap document per account plus rules to block its deletion. Deriving it removes all three problems.

Custom lists, by contrast, are stored: their membership is not implied by anything else.

### Provider scope

Every user-scoped provider is mounted **above** `MaterialApp`, never inside `home:`. A provider placed under `home:` sits below the root `Navigator`, so pushed routes and modal sheets cannot see it and fail at runtime with `ProviderNotFoundException` — something neither `flutter analyze` nor pure-Dart unit tests catch. `test/provider_scope_test.dart` guards this.

### Firestore layout

```
users/{uid}                        { sampleRecipeSeeded }
users/{uid}/inventory/{paintId}    { status, updatedAt }
users/{uid}/paintLists/{listId}    { name, paintIds[], updatedAt }
users/{uid}/recipes/{recipeId}     { name, description, sections[], links[], publishedId?, updatedAt }
users/{uid}/linkedRecipes/{pubId}  { linkedAt }
publishedRecipes/{pubId}           { ownerUid, authorName, name, description, sections[], links[], updatedAt }
publishedRecipes/{pubId}/links/{linkerUid}  { linkedAt }
```

Recipe cover photos live in Cloud Storage under `users/{uid}/recipePhotos/`, referenced from the recipe by download URL. Recipes saved before Storage was enabled carry base64 in a legacy `photo` field, which is still read so their picture keeps working but is never written again. Photos are compressed on the device before upload — a hard cap, so a 20 MB camera shot never leaves the phone at full size — and `storage.rules` enforces a second ceiling server-side for clients that skip it.

A recipe section is `{ name, steps[], techniques[], notes }` where each step is `{ title, paintId?, note }` — the **order of the steps is the recipe**. Section paint lists are derived from the steps. Readiness (for lists and recipes alike) is derived from the inventory by a single shared function: *ready* when every paint is in stock, *running low* when some pots are nearly empty, and *incomplete* when a paint is missing outright.

### Recipe sharing

Publishing copies the recipe to the top-level `publishedRecipes` collection (readable by any signed-in user, writable only by its owner — ownership can never be reassigned). Saving a published recipe pushes the update to the public copy, so **links follow the recipe instead of cloning it**: followers always see the author's latest version and its update date.

Linking writes two documents in one batch: `users/{uid}/linkedRecipes/{pubId}` (the follower's bookmark) and `publishedRecipes/{pubId}/links/{uid}` (a marker keyed by the linker's uid, so the link count comes from a `count()` aggregation and nobody can vote more than once). Share links use the hash form `https://…/#/r/{pubId}`; the id is captured at startup from `Uri.base` and the screen opens after sign-in.

New accounts get a sample recipe seeded client-side, guarded by a one-shot `sampleRecipeSeeded` flag on the user doc so deleting the example never brings it back. Every paint referenced by the sample is checked against the catalog in `test/sample_recipe_test.dart`.

Firestore keeps an offline cache, so the app works without a connection and syncs once the network is back. Every new subcollection needs a matching rule in `firestore.rules` — the default is deny, so forgetting one fails silently at runtime with `PERMISSION_DENIED`.

> Rules take up to a minute to propagate after `firebase deploy --only firestore:rules`. A 403 immediately after a deploy is usually propagation, not a broken rule.

### Admin panel

Settings shows an **Admin panel** entry, but only for accounts carrying the `admin` Auth **custom claim**. The panel (`lib/src/features/admin/admin_screen.dart`) shows platform-wide totals and weekly activity charts — everything computed with Firestore `count()` aggregations (`lib/src/data/admin_stats_repository.dart`), so no user documents are ever downloaded.

The client-side check (`AuthService.hasAdminClaim`) is cosmetic; the enforceable gate is `isPlatformAdmin()` in `firestore.rules`, which reads the same claim and grants **read-only** access across user subtrees via collection-group rules. The claim is deliberately NOT a Firestore field — user docs are client-writable, so a field could be self-granted — and no admin identity ever appears in this repository. Grant it server-side by uid:

```bash
curl -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "x-goog-user-project: paintforge-d8cf2" -H "Content-Type: application/json" \
  -d '{"localId":"<uid>","customAttributes":"{\"admin\":true}"}' \
  "https://identitytoolkit.googleapis.com/v1/projects/paintforge-d8cf2/accounts:update"
```

Claims ride in the ID token, so a freshly granted admin has to sign out and back in (or wait for the hourly token refresh) before the panel appears.

### Batched purchase feedback

Confirming several purchases in quick succession is a common enough flow (working through a shopping list) that it needs its own affordance: `ActionBatcher` (`lib/src/services/action_batcher.dart`) coalesces rapid repeated actions into one summary event instead of one queued SnackBar per tap that then plays out long after the user stopped tapping. `ShoppingListScreen` uses it for individual "bought it" confirmations — a single purchase still names the paint ("Abaddon Black marked as owned"), but several within ~900ms settle into one aggregate message ("3 paints marked as bought"). The bulk "mark all as bought" action discards any pending single-purchase batch first, so its own summary is never followed by a redundant, stale one a moment later.

### Account deletion

Settings → Danger zone → Delete account requires typing a confirmation phrase, then re-authenticating (password or Google, whichever the account uses) — Firebase requires a *recent* sign-in before it allows deleting the Auth account, and re-authenticating up front avoids ending up with the data wiped but the account still existing.

`FirestoreAccountRepository.deleteAllData()` runs **before** `AuthService.deleteAccount()`, deliberately: deleting the Auth account first would invalidate the ID token the Firestore deletes need, stranding the data undeletable. It removes, in order: inventory, paint lists, every `publishedRecipes` doc the user owns (and their `links` subcollections), recipes, this user's own link markers on *other* painters' published recipes, `linkedRecipes`, and finally the user doc itself.

Cleaning up markers under a published recipe you don't own (when unpublishing, or here) needs the recipe's owner to delete documents keyed by someone else's uid — the `links` subcollection rule allows that via a `get()` check against the parent doc's `ownerUid`, in addition to a linker deleting their own marker.

## Tests

```bash
flutter test
```

They cover catalog loading and search, inventory/shopping-list logic (with in-memory repositories), paint-list readiness, recipe serialization and readiness, shopping-list text formatting, batched purchase feedback, provider scoping, the Lists screen, the account-deletion confirmation flow, floating-action-button clearance, and the login screen (with a fake auth service).

Shared in-memory repositories live in `test/fakes.dart`.

> In widget tests, build providers **inside** the `testWidgets` body, never in `setUp`. A provider created in `setUp` opens its streams outside the tester's async zone, so `pump` never flushes their events and the screen renders stale data while the provider itself looks correct. `test/lists_screen_test.dart` uses a `_Harness` for exactly this reason.
