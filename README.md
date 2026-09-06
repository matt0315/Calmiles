# Calmiles

**Calmiles: Mileage Tracker** — automatic mileage / trip logger for freelancers and sole traders (US / AU / UK / CA).

Detect trips → classify business / personal / undecided → export CSV & PDF with IRS / ATO / HMRC / CRA rate presets (estimates only — not tax advice).

Built by **Botland Studio** (Mathew Smith).

## Product

| | |
| --- | --- |
| App Store title | Calmiles: Mileage Tracker |
| Subtitle | Auto Mileage Log & Export |
| Bundle ID | `studio.botland.calmiles` |
| Min iOS | 17.0 |
| Version | 1.0.0 (1) |
| Stack | SwiftUI · SwiftData · Core Location · WidgetKit · StoreKit 2 |

**Non-goals:** bank linking, insurance, tax filing, tax advice.

## Architecture

```
Calmiles/
  App/              # @main, root tabs
  DesignSystem/     # palette, type, shared controls
  Domain/           # models + pure services (distance, rates, classification)
  Data/             # SwiftData, location, export, StoreKit, analytics stubs
  Features/         # Onboarding, Home, Trips, Export, Settings, Paywall
CalmilesWidget/     # Weekly summary WidgetKit extension
CalmilesTests/      # Unit tests
Configuration/      # StoreKit Configuration file
```

## Brand palette

| Token | Hex |
| --- | --- |
| Slate indigo | `#1B2436` |
| Ink | `#0E1420` |
| Mist | `#E8EEF7` |
| Cloud | `#F5F7FB` |
| Sand | `#D4C4A8` |
| Copper | `#A67C52` |
| Copper soft | `#C4A574` |
| Success | `#6B8F71` |
| Danger | `#B56B6B` |

## Setup

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
2. Clone and generate:

```bash
cd /Users/matt/Developer/Calmiles
xcodegen generate
open Calmiles.xcodeproj
```

3. Set your **Development Team** in Xcode (Signing & Capabilities). `DEVELOPMENT_TEAM` is intentionally empty in source — never commit secrets.
4. Enable capabilities in the Apple Developer portal / Xcode:
   - App Groups: `group.studio.botland.calmiles`
   - iCloud / CloudKit: `iCloud.studio.botland.calmiles`
   - Background Modes: Location updates
5. For local IAP testing, select the scheme → Run → Options → StoreKit Configuration → `Configuration/Calmiles.storekit`.

### Simulator tip

Use **Settings → Inject sample trip (DEBUG)** or the Home toolbar **Sample** button to add a DEBUG trip without GPS.

## Build & test

```bash
xcodegen generate
xcodebuild -scheme Calmiles -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build
xcodebuild -scheme Calmiles -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:CalmilesTests
```

## Monetization

| Product ID | Price |
| --- | --- |
| `calmiles_pro_monthly` | $9.99 |
| `calmiles_pro_yearly` | $59.99 |

Free tier: **40 auto-detected trips / month**. Manual trips unlimited.

## Privacy

Honest Info.plist strings disclose background location and battery impact. Analytics / crash reporting are **os_log stubs** only — wire a privacy-first provider before production if needed.

## Support

- Email: [support@botland.studio](mailto:support@botland.studio)
- Website / support: [botland.studio](https://botland.studio)
- Privacy: [botland.studio/privacy](https://botland.studio/privacy)
- Terms: [botland.studio/terms](https://botland.studio/terms)

## License

Proprietary — Botland Studio. All rights reserved.
