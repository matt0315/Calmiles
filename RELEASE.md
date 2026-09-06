# Calmiles — Release & TestFlight

**Studio:** Botland Studio · **Apple account:** Mathew Smith  
**Bundle ID:** `studio.botland.calmiles` · **Version:** 1.0.0 (1)

This document covers human-gated signing and App Store Connect steps. No secrets belong in the repo.

## Prerequisites

1. Apple Developer Program membership (Mathew Smith / Botland Studio).
2. App ID `studio.botland.calmiles` with capabilities:
   - Associated App Groups: `group.studio.botland.calmiles`
   - iCloud (CloudKit) container: `iCloud.studio.botland.calmiles`
   - Push optional (not required for MVP)
3. Widget extension App ID: `studio.botland.calmiles.widget` (same App Group).
4. Certificates / provisioning profiles via Xcode Automatic Signing (recommended).

## Signing (Xcode)

1. Open `Calmiles.xcodeproj` (generate with `xcodegen generate` first).
2. Select target **Calmiles** → Signing & Capabilities:
   - Team: Mathew Smith / Botland Studio
   - Bundle Identifier: `studio.botland.calmiles`
   - Confirm App Groups + iCloud capabilities match entitlements.
3. Select **CalmilesWidgetExtension** → same Team; bundle `studio.botland.calmiles.widget`.
4. Leave `DEVELOPMENT_TEAM` out of committed project settings if you prefer local overrides; do **not** invent or commit team IDs / keys as secrets in git.

## App Store Connect

1. Create app:
   - Name: **Calmiles: Mileage Tracker**
   - Subtitle: **Auto Mileage Log & Export**
   - Bundle ID: `studio.botland.calmiles`
   - SKU: `calmiles-ios`
2. Age rating / export compliance: encryption uses only standard HTTPS / OS crypto (`ITSAppUsesNonExemptEncryption = false` in Info.plist).
3. Privacy Nutrition Labels: Location (precise) for app functionality; no tracking for ads.
4. App Privacy Policy URL: replace placeholder `https://botland.studio/calmiles/privacy` with live page before review.
5. Support URL + marketing URL as needed.
6. Primary category: Finance or Business (confirm ASO choice).
7. App Review notes: explain background location for automatic trip detection; link to battery disclosure copy; note DEBUG injector is `#if DEBUG` only.

## In-App Purchases

Create subscription group **Calmiles Pro**:

| Reference | Product ID | Price |
| --- | --- | --- |
| Pro Monthly | `calmiles_pro_monthly` | USD 9.99 |
| Pro Yearly | `calmiles_pro_yearly` | USD 59.99 |

Optional intro: 1-week free (matches StoreKit Configuration). Localize display names / descriptions. Submit IAPs with the binary.

## Icons

Use locked Concept B **dark.png** as the 1024 App Store master (already in `Assets.xcassets/AppIcon.appiconset`). Light / tinted / mono variants included for appearance variants.

## Archive & TestFlight

1. Scheme **Calmiles** → Any iOS Device (arm64) → Product → Archive.
2. Distribute → App Store Connect → Upload.
3. In ASC → TestFlight → add internal testers (Mathew Smith + studio).
4. External testing requires Beta App Review once.
5. Smoke checklist on device:
   - Onboarding country + location prompts
   - Background trip after a short drive (or manual add)
   - One-tap Business / Personal / Undecided
   - CSV + PDF export share sheet
   - Paywall restore + Manage Subscription
   - Widget added to Home Screen
   - Dark Mode + Dynamic Type

## Review risk notes

- Background location + battery: Info.plist strings are honest; onboarding discloses impact.
- “Not tax advice” appears on rates, export, and estimates.
- No bank linking / tax filing claims.

## What’s left for humans

- [ ] Assign Development Team & create App IDs / profiles
- [ ] Create ASC app record + IAP products
- [ ] Publish privacy & terms pages
- [ ] Archive & upload build
- [ ] TestFlight internal → external
- [ ] App Review submission
- [ ] Optional: wire real crash/analytics (stubs only today)

## Support

support@botland.studio
