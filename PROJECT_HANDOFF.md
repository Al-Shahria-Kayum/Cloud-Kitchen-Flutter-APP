# Cloud Kitchen MVP — Project Handoff & Context Document

**Purpose of this file:** a self-contained snapshot of the project so it can be handed to any other AI assistant, developer, or platform and work can resume without re-explaining anything. It covers what the app is, how it's built, everything implemented so far, known issues that were fixed (and why, so they aren't reintroduced), and a full list of remaining work — including native mobile and desktop builds, which have **not** been done yet.

> Superseded docs: `walkthrough.md` and the "Configuration Required" steps in `README.md` describe an **earlier version** of this app (wallet top-up, automatic 5%/85% payout split) that has since been replaced by a manual bKash payment flow. Treat this document as the current source of truth; `walkthrough.md` can be deleted or ignored.

---

## 1. What this project is

A cloud-kitchen food delivery MVP for the Bangladesh market, built with **Flutter** (single codebase) and **Supabase** (Postgres + Auth + Storage + Realtime) as the backend. Three user roles share one app:

- **Customer** — browses nearby kitchens, orders food, pays via bKash (manual "Send Money" flow, no payment gateway integration), tracks delivery live on a map, chats with kitchen/rider, confirms delivery, rates & reviews, downloads PDF receipts.
- **Kitchen owner** — registers a kitchen (location auto-captured from live GPS), manages a menu (multi-photo items, BDT pricing), accepts/rejects orders, confirms customer bKash payments, pays the rider their delivery fee, tracks orders on a map, chats, views reviews and order history.
- **Rider** — sees available deliveries, accepts one, updates delivery stage (picked up → on the way → arrived → delivered), broadcasts live GPS the whole time, confirms receiving their payout from the kitchen, chats, views earnings and history.

Currency is **BDT (Bangladeshi Taka)** everywhere — this was deliberately migrated away from USD earlier in the project. Payments are **manual/trust-based bKash** (customer sends money to the kitchen's/rider's personal bKash number and reports the transaction ID; the receiving party confirms in-app) — there is **no real payment gateway integration**, by deliberate choice, because automated verification of a personal bKash number isn't technically possible without a merchant API.

---

## 2. Tech stack

| Layer | Choice |
|---|---|
| Client | Flutter (Dart), single codebase targeting Android, iOS, Web, Windows, macOS, Linux |
| State management | `provider` (`ChangeNotifier` per domain) |
| Backend | Supabase — Postgres (with RLS), Auth, Storage, Realtime (`.stream()` subscriptions + broadcast channels) |
| Maps | `flutter_map` + OpenStreetMap tiles (`tile.openstreetmap.org`), `latlong2` |
| Location | `geolocator` (device GPS), reverse geocoding via OpenStreetMap **Nominatim** (free tier — see Known Limitations) |
| Images | `image_picker` (pick), Supabase Storage (host), `cached_network_image` (render/cache) |
| PDF receipts | `pdf` + `printing` packages; `PdfGoogleFonts.notoSansBengaliRegular/Bold` for Bengali-script text (menu items are often named in Bengali) |
| Local notifications | `flutter_local_notifications` — **foreground-only**, not push (see Known Limitations) |
| Currency/date formatting | `intl`, plus small custom utils (`lib/utils/currency_format.dart`, `lib/utils/date_format.dart`) |

Flutter SDK constraint: `^3.12.2` (see `pubspec.yaml`). Full dependency list is in `pubspec.yaml` — don't duplicate it here, just read that file.

---

## 3. Repository structure

```
lib/
  config/supabase_config.dart      # Supabase URL + publishable (anon) key — hardcoded, see §9
  main.dart                        # App bootstrap, MultiProvider wiring, "not configured" fallback screen
  models/                          # Plain Dart data classes (Order, Kitchen, MenuItem, Profile, Review/Rating, Chat/Message)
  providers/                       # ChangeNotifier business logic: auth, customer, kitchen, rider, chat
  screens/
    auth/                          # Splash, login, signup, role-based gate
    customer/                      # Home (nearby kitchens), kitchen details + order sheet, order details/tracking
    kitchen/                       # Home/dashboard, menu management, order details, order history
    rider/                         # Home (available/active deliveries), order details, order history
    shared/                        # Chat, ratings (submit), reviews (view), bKash number settings sheet
  services/                        # GeocodingService, LocationService, NotificationService, ReceiptPdfService
  theme/app_theme.dart             # Colors, spacing, radii, motion constants, light/dark theme
  utils/                           # currency_format, date_format, delivery_stage, error_mapper, async_guard
  widgets/                         # Reusable UI: PhotoCarousel, FullScreenImageViewer, LiveLocationText,
                                    # NetworkFoodImage, StatusPill, EmptyState, InitialsAvatar, shimmer, etc.
test/                              # Unit tests for models/services/utils (see §7)
supabase_schema.sql                # Full bootstrap SQL — tables, RLS policies, triggers, storage buckets.
                                    # Kept in sync with every migration applied to the live project (see §9).
android/ ios/ web/ windows/ macos/ linux/   # Platform scaffolding from `flutter create` — present but largely untested (see §8)
```

---

## 4. How to run this project (fresh machine / fresh AI session)

1. **Supabase project**: already exists and is live — credentials are in `lib/config/supabase_config.dart` (URL + publishable/anon key; safe to keep as-is, it's the public client key, not a secret). If starting a *new* Supabase project instead, run the entirety of `supabase_schema.sql` in the SQL Editor — it drops and recreates everything, creates storage buckets (`menu-images`, `avatars`, `review-photos`, `chat-photos`) and their RLS policies, and installs the central order-lifecycle trigger (see §5).
2. `flutter pub get`
3. Run for whichever target you need:
   - Web (what this session has been testing with): `flutter build web --pwa-strategy=none` then serve `build/web` with any static server (e.g. `python -m http.server`). `--pwa-strategy=none` avoids a Flutter-web service-worker caching gotcha hit during this project — see §6.
   - Desktop debug run: `flutter run -d windows` / `-d macos` / `-d linux`
   - Mobile: `flutter run -d <device-id>` with an emulator/device attached, or `flutter build apk` / `flutter build appbundle` / `flutter build ios`
4. `flutter analyze` and `flutter test` should both be clean before considering any change done — see §7 for the testing convention this project follows.

---

## 5. Data model & backend architecture

### Tables (Postgres, all RLS-enabled)
`profiles`, `kitchens`, `menu_items`, `orders`, `order_items`, `chats`, `messages`, `ratings` (this one table backs both "ratings" and "reviews" in the UI — `photo_urls` holds review photos).

### Storage buckets (all public-read, owner-scoped write via RLS)
`menu-images`, `avatars`, `review-photos`, `chat-photos`.

### The core architectural pattern: DB-enforced state machine
All order status/payment/payout transitions are gated by a single Postgres `BEFORE UPDATE` trigger function, `check_order_assignment()`, on the `orders` table. **This is the authoritative source of truth — not app-level validation.** Any new order-lifecycle feature should extend this trigger, not just add a Flutter-side check. Order status flow:

```
pending → accepted / rejected → preparing → ready → awaiting_rider → rider_assigned
  → picked_up → on_the_way → arrived → delivered → completed
```

Key gates enforced in the trigger:
- Kitchen can't `accept` until `payment_status = 'payment_confirmed'` (customer reported a bKash txn ID, kitchen verified it in their own bKash app/SMS and confirmed in-app).
- Customer can't `confirm delivery` (delivered → completed) until the **rider** has confirmed receiving their payout from the kitchen (`rider_payment_confirmed`) — the kitchen marking it paid (`rider_payout_confirmed`) alone is *not* sufficient; the rider must separately acknowledge it. This two-step gate exists because the kitchen's claim alone isn't trustworthy.
- **24-hour safety valve**: if the rider was never paid, the customer's confirmation is allowed through anyway once `delivered_at` is >24h old, and the kitchen owner's account gets flagged (`payout_overdue_flagged_at`) — so an unresponsive kitchen/rider can never trap a customer's order forever.

### Payment/payout field reference (on `orders`)
- `payment_status` (`awaiting_payment` → `payment_reported` → `payment_confirmed`), `customer_bkash_txn_id`, `payment_reported_at`, `payment_confirmed_at`
- `rider_payout_confirmed`, `rider_payout_txn_id`, `rider_paid_at` — kitchen owner marking the rider paid
- `rider_payment_confirmed`, `rider_payment_confirmed_at` — rider confirming they actually received it (added this session)
- `receipt_issued_at`, `payout_overdue_flagged_at`

---

## 6. Feature inventory — what's already built (and bugs already fixed)

Everything below is implemented, tested (`flutter analyze` + `flutter test`, 30 tests passing), and last verified against a `flutter build web` run in this session.

### Auth & roles
Signup/login, role selection (customer/kitchen/rider), role-based routing via `AuthGate`.

### Kitchen onboarding & location
- First-time setup **auto-captures the device's live GPS position once** and saves it permanently as the kitchen's registered pickup location — there is **no manual lat/lng entry** (that used to default silently to Dhaka's center, 23.8103/90.4125, and mis-registered kitchens there).
- An "Update kitchen location" button (map-pin icon in the dashboard app bar) lets the owner re-capture their GPS position any time (e.g. after moving premises) and re-geocodes it to a human-readable address.
- The kitchen order-details map now centers on the **delivery destination / rider's live position**, not the kitchen's own static location — it used to always center on the kitchen's fixed address regardless of where the order was actually going.

### Menu management (kitchen)
- Multi-photo upload per menu item; the first photo mirrors into a legacy `image_url` column for any older code path.
- List-row thumbnails and the customer-facing order sheet both use a swipeable `PhotoCarousel` with dot indicators.
- Tapping any photo opens a **full-screen, swipeable gallery** (`FullScreenImageViewer.showGallery`) starting at the tapped photo — not just that one photo with no way to see the rest.
- **Delete now actually works and explains itself.** A menu item that's already been ordered can't be *hard*-deleted (there's a plain, non-cascading FK from `order_items.menu_item_id` — by design, to keep historical orders/receipts accurate). The provider (`KitchenProvider.deleteMenuItem`) returns a `MenuItemDeleteOutcome` enum (`success` / `hasOrderHistory` / `error`); the UI now reacts to it — showing a clear explanation and a one-tap "Mark Unavailable" fallback instead of silently doing nothing (which is what it did before this fix).

### Customer ordering
- Nearby-kitchens list sorted by live distance (Haversine).
- Order sheet prefills the delivery address from the customer's **actual live GPS**, reverse-geocoded — it used to default to the kitchen's own address with a fake coordinate offset ("Simulate coordinate mapping" — this was a real bug, now fixed).
- BDT currency throughout (`formatCurrency`), no USD anywhere.

### Manual bKash payment flow
Customer reports a bKash transaction ID → kitchen owner checks their own bKash app/SMS and confirms in-app → order can be accepted. See `bkash_settings_sheet.dart` for how each role sets their own receiving bKash number.

### Rider payout confirmation loop (added this session)
Kitchen marks rider paid → **rider must separately confirm they received it** (new "Confirm You Received the Payment" button on the rider's order-details screen, backed by `RiderProvider.confirmPaymentReceived`) → only then can the customer confirm delivery. All three role-facing screens (kitchen's payout card, rider's action button, customer's blocked-confirmation message) reflect the current step accurately. 24h timeout safety valve as described in §5.

### Live location & maps
- `LocationService` wraps `geolocator` for one-shot fetches and continuous streams; falls back to a Dhaka-center default only if permission is denied/unavailable.
- `GeocodingService` reverse-geocodes coordinates via Nominatim into short human-readable strings (e.g. "Bosila, Mohammadpur"), with an in-memory cache and a coordinate-string fallback on failure.
- `LiveLocationText` widget renders that everywhere a location needs to be human-readable instead of raw coordinates.
- Kitchen/customer/rider all broadcast live position to `profiles.latitude/longitude`; order-details screens on all three sides show `flutter_map` + OSM tiles with role-colored pins (kitchen/customer/rider), fed by realtime subscriptions.

### PDF receipts
`ReceiptPdfService.downloadReceipt` generates a role-specific PDF (customer sees itemized total; kitchen owner sees the payout breakdown — commission/rider fee/net). **Fixed a real crash**: menu item/person names are frequently Bengali script (e.g. "ইলিশ মাছ"), and the `pdf` package's default fonts have no Bengali glyphs, which silently failed generation ("could not generate the receipt"). Now loads `PdfGoogleFonts.notoSansBengaliRegular/Bold` and applies them as the document theme.

### Chat (per order)
Text messages, swipe-to-reply with quoted preview, typing indicator (ephemeral broadcast channel, not a DB table), read receipts, emoji quick-bar. **Photo sharing added this session**: an attach button uploads to the `chat-photos` bucket and sends as a message (`image_url` column, `message_text` now nullable-in-practice via a DB check constraint requiring at least one of text/image); bubbles render images inline with tap-to-zoom full-screen.

### Reviews & ratings
Customers rate kitchen + rider per order with optional multi-photo reviews (`ratings` table, `photo_urls` array). Review photo thumbnails also open the swipeable full-screen gallery (same fix as menu photos, applied to `reviews_screen.dart` too).

### Order history
Separate history screens for kitchen, customer (embedded in home), and rider, showing completed orders with items, amounts, and dates.

---

## 7. Bugs fixed this session — read this before touching image/location/payment code again

These are real bugs that were found and fixed, with root causes, so they aren't reintroduced:

1. **Duplicate Hero-tag collision** (`lib/widgets/full_screen_image_viewer.dart`, `network_food_image.dart`) — tapping a menu photo would freeze on a small thumbnail image, top-of-screen, on an otherwise black screen, with no swipe/indicators. Root cause: the full-screen viewer used a `Hero` animation keyed by `photo-${url.hashCode}`; menu items commonly reuse the same seed/placeholder photo URL, so multiple `Hero` widgets with the *same tag* ended up mounted simultaneously in the same route — which Flutter disallows (max one `Hero` per tag per route) and the transition broke. **Fix: removed the `Hero` transition entirely** in favor of a plain fade — it wasn't essential, and a fade can't collide.
2. **Full-screen photo viewer only showed the single tapped photo**, never the rest of a multi-photo set, despite the small carousel's pagination dots. Root cause: `NetworkFoodImage`'s tap handler always opened `FullScreenImageViewer.show(url)` with just that one URL. Fixed by threading the full photo list + tapped index through (`galleryUrls`/`galleryIndex` on `NetworkFoodImage`, `FullScreenImageViewer.showGallery`), so the viewer is a real swipeable `PageView` with a page counter and dot indicators.
3. **Kitchen order-details map centered on the kitchen's own fixed address**, not the delivery destination — so it visually looked "stuck" showing the kitchen's neighborhood instead of where the order was actually going. Fixed the `initialCenter` priority to `rider live position → delivery destination → kitchen address`.
4. **Customer delivery address defaulted to the kitchen's own registered address**, and delivery coordinates were a fake offset from the kitchen's own lat/lng (`kitchen.latitude + 0.003`, literally commented "Simulate coordinate mapping for delivery location"). Fixed by wiring the customer's actual live GPS through to the order sheet.
5. **Menu item delete silently did nothing** for any item that had ever been ordered. Root cause: a real, correct FK constraint (`order_items.menu_item_id` has no `ON DELETE` action) rejecting the delete — but the UI ignored the returned success/failure entirely. Fixed per §6 above (this is a *feature* fix, not just a bug fix — hard-deleting order-referenced data would itself have been a data-integrity bug).
6. **PDF receipt generation failed on Bengali text** — see §6, Bengali font fix.
7. **Multi-photo thumbnails only appeared in the "add item" sheet, not the list-row thumbnails** — upgraded list rows to use `PhotoCarousel` directly.
8. **Disk space**: this dev machine's C: drive repeatedly runs low (~16MB free at one point) during `flutter build`/`flutter test`. If you hit "not enough space on disk, errno=112", clean `%TEMP%` (excluding any active tool-session folder) before retrying — this is an environment quirk, not a code issue.
9. **"Still broken" reports that were actually stale builds**: on at least two occasions during this project, a reported bug was actually the tester's browser running an old cached build, not a real code issue — verified in both cases by querying the live Supabase DB directly and grepping source to confirm the code was already correct. **Always rebuild + reserve on a fresh port (or with `--pwa-strategy=none`) before concluding a fix didn't work**, and ask whoever's testing to hard-refresh or use a private window.

---

## 8. Current build/verification status — READ THIS: mobile & desktop are NOT yet built

This entire project has so far only been verified via:
- `flutter analyze` (clean)
- `flutter test` (30 unit tests, all passing — models, services, utils; **no widget or integration tests exist yet**)
- `flutter build web` (repeatedly, after every change) + manual testing by serving the static build locally

**Android, iOS, Windows, macOS, and Linux have NOT been built or run even once in this project's history so far**, despite all five platform folders existing (they're default `flutter create` scaffolding, untouched). The user has explicitly said **both a desktop app and a mobile app are required** — this is the single biggest gap between "web MVP that works" and "shippable product," and should be the next major phase of work.

---

## 9. Known limitations / things to fix before real launch

- **Supabase credentials are hardcoded** in `lib/config/supabase_config.dart` (URL + publishable/anon key). The anon key is *meant* to be public (RLS is the real security boundary), but for a production app this should still move to `--dart-define` / environment-specific config so debug/staging/prod can differ without editing source.
- **Nominatim (OpenStreetMap) reverse geocoding is rate-limited to ~1 req/sec for public use** and explicitly not meant for production volume — swap for a paid geocoder (Google/Mapbox) or a self-hosted Nominatim instance before scaling. The call site (`GeocodingService.reverseGeocode`) is the only thing that needs to change.
- **No push notifications** — `NotificationService` wraps `flutter_local_notifications`, which only fires while the app is running/foregrounded. Real push (FCM for Android/web, APNs for iOS) needs a server-side trigger (e.g. a Supabase Edge Function reacting to order updates) plus device token registration — not built.
- **No real payment gateway** — bKash flow is manual/trust-based by deliberate choice (see §1). If moving to automated payments, look at bKash's own Merchant API or a local aggregator (SSLCommerz, etc.).
- **`supabase_schema.sql` vs. live migrations**: schema changes this session were applied live via direct migrations (Supabase MCP `apply_migration`) and then hand-mirrored into `supabase_schema.sql` to keep the bootstrap script in sync. Going forward, prefer tracked migration files (`supabase/migrations/`) over ad hoc application, or at minimum keep religiously mirroring every change into `supabase_schema.sql` — it's currently the only complete, authoritative schema reference.
- **No admin/ops view** — no dashboard beyond the three role apps for platform-level oversight (commission totals, dispute handling, kitchen approval/moderation).
- **No i18n framework** — UI copy is English-only; Bengali only appears in actual user-entered data (names), handled at the font-rendering layer (PDF), not as translated UI strings.
- **No crash/error monitoring** (Sentry, Firebase Crashlytics, etc.) wired up.
- **No CI/CD** — all verification so far is manual (`flutter analyze`/`test`/`build` run by hand each time).

---

## 10. Roadmap — everything left to do

### Phase A — Get it running as real apps (highest priority; nothing below matters until this works)
- [ ] **Android**: `flutter build apk`/`appbundle`, test on a real device and at least one emulator API level; verify location permissions, image picker, notifications, deep linking (if any) all work outside a browser.
- [ ] **iOS**: needs a Mac + Xcode + Apple Developer account to build/sign; verify the same permission/feature set as Android; iOS-specific `Info.plist` entries for location/camera/photo-library usage descriptions almost certainly need to be added/reviewed.
- [ ] **Windows desktop**: `flutter build windows`; audit every screen for layout at desktop window sizes/aspect ratios — this UI was designed mobile-first and has never been checked on a wide/resizable window (menus, maps, chat, forms may need responsive breakpoints).
- [ ] **macOS desktop**: `flutter build macos`; same layout audit as Windows, plus macOS-specific entitlements for location/camera/network.
- [ ] **Linux desktop**: `flutter build linux`; same layout audit.
- [ ] App icons for every platform (the `flutter_launcher_icons` config in `pubspec.yaml` already points at `assets/icon/` — verify those source images actually exist and look right at every generated size).
- [ ] Splash screens per platform.
- [ ] Decide on desktop-specific navigation (mobile bottom-nav/stacked-screen patterns vs. a sidebar/multi-pane layout more appropriate for a wide desktop window) — this is a design decision, not just a build task.

### Phase B — Production readiness
- [ ] Real push notifications (FCM/APNs) replacing/augmenting the current foreground-only local notifications.
- [ ] Move Supabase config to environment-based (`--dart-define`) rather than hardcoded, with separate dev/staging/prod projects.
- [ ] Swap Nominatim for a production-grade geocoder.
- [ ] Crash/error monitoring integration.
- [ ] CI pipeline: run `flutter analyze` + `flutter test` on every push at minimum; add build jobs per platform once Phase A lands.
- [ ] Expand automated test coverage: currently zero widget/integration tests exist — the 30 passing tests are all model/service/util unit tests. Screens, providers, and the order-status state machine have no automated coverage.
- [ ] Security review pass (RLS policies, storage bucket policies, and the `check_order_assignment()` trigger have all been extended repeatedly this session — worth a dedicated audit before launch).
- [ ] Formalize migrations (`supabase/migrations/`) instead of ad hoc `apply_migration` calls kept in sync by hand.

### Phase C — Product features not yet built
- [ ] Kitchen/menu search & filtering (by cuisine, rating, price) — current customer home just lists nearby kitchens sorted by distance.
- [ ] Admin/ops dashboard — commission reporting, dispute resolution, kitchen approval/moderation, payout-overdue follow-up (the `payout_overdue_flagged_at` flag currently has nowhere to be *acted on*).
- [ ] Order search/filter in history screens (currently just a chronological list).
- [ ] Real payment gateway integration, if/when moving beyond manual bKash.
- [ ] Internationalization framework if targeting non-English-first users beyond the current Bengali-name-only support.
- [ ] Accessibility audit (screen reader labels, contrast, tap-target sizes) — not yet done anywhere in the app.
- [ ] Load-testing Supabase Realtime channels (order streams, typing indicators, location broadcasts) at a scale beyond the current single-digit test dataset.

### Phase D — Launch logistics
- [ ] Google Play listing (screenshots, privacy policy, terms of service, data-safety declarations).
- [ ] Apple App Store listing (same, plus App Store Review Guidelines compliance — location/background-location usage justification will get extra scrutiny).
- [ ] Desktop distribution story (Microsoft Store vs. direct download/installer for Windows; notarization for macOS; AppImage/Flatpak/deb for Linux).

---

## 11. Testing convention this project follows (keep doing this)

After **every** code change:
1. `flutter analyze` — must stay clean (pre-existing `use_build_context_synchronously` infos are accepted baseline noise; don't introduce new *errors*).
2. `flutter test` — all tests must pass (currently 30).
3. `flutter build web --pwa-strategy=none` — the closest thing to an end-to-end smoke test available in this environment (no browser automation tool has been available this session; the user declined installing one). Serve the fresh `build/web` output on a **new port** each time (or with the service-worker disabled) to avoid stale-cache false negatives — see §7, item 9.
4. Report concrete verification (test counts, analyze output), not just "should work now."

---

## 12. Open questions for whoever resumes this

- Desktop layout strategy: adapt the existing mobile-first screens responsively, or design dedicated desktop layouts (sidebar nav, multi-pane views)?
- Which push-notification backend: Firebase Cloud Messaging (cross-platform, most common with Flutter) vs. something else?
- Real payment gateway timeline — is manual bKash acceptable for an initial launch, or is a merchant API integration a launch blocker?
- Any specific target Android API level / iOS minimum version requirements not yet decided (`min_sdk_android: 21` is currently just the `flutter_launcher_icons` default, not a deliberate product decision).
