# AGENTS.md

Guidance for AI coding agents (and humans) working in this repository.

## What this is

Air Traffic is a living-room display for Apple TV showing the aircraft flying near your home: a dark live map, the
nearest or overhead aircraft in detail, and a strip of the rest. It is a standalone SwiftUI app with no server and
no accounts. See [README.md](README.md) for setup, [CHANGELOG.md](CHANGELOG.md) for history and
[ROADMAP.md](ROADMAP.md) for plans.

## Layout

```
Sources/OverheadKit    Engine, no UI: feeds, geometry, route validation, tracking, reference data
Sources/OverheadUI     SwiftUI views shared by tvOS, iOS and macOS
Sources/DesignPreview  macOS tool that renders the TV layout to PNG (the way UI is verified without a simulator)
Apps/tvOS              App target: @main and Info.plist only
Config/                App.xcconfig (shared defaults); Local.xcconfig is git-ignored and personal
Tests/OverheadKitTests Swift Testing suites and an adsb.fi capture with identifying details removed (keep it that way)
project.yml            XcodeGen definition. AirTraffic.xcodeproj is generated from it and committed.
```

`OverheadKit` must not import SwiftUI or any UI framework. All engine state is `@MainActor` and `@Observable`.
The Swift language mode is 5; there are no third-party dependencies.

## Commands

Keep build output out of the repo (it can live in a cloud-synced folder): pass `--scratch-path` somewhere outside.

```bash
S=~/Library/Caches/air-traffic-build
swift test --scratch-path $S                       # unit tests; LIVE_TESTS=1 adds network checks

# Compile the shared code against the real SDKs (works without a simulator):
swift build --target OverheadUI --sdk "$(xcrun --sdk appletvos --show-sdk-path)" --triple arm64-apple-tvos17.0 --scratch-path $S-tvos
swift build --target OverheadUI --sdk "$(xcrun --sdk iphoneos --show-sdk-path)" --triple arm64-apple-ios17.0 --scratch-path $S-ios

# Render the UI to images and look at them:
swift run --scratch-path $S design-preview ./Preview busy quiet nophoto welcome zoomin zoomout crowded photoloading

swift run --scratch-path $S design-preview --icons /tmp/icons && python3 scripts/make-icon-catalog.py /tmp/icons   # after changing AppIconArtwork
xcodegen generate                                   # after editing project.yml
xcrun devicectl list devices                        # find the Apple TV's identifier
xcodebuild -project AirTraffic.xcodeproj -scheme AirTraffic \
  -destination 'platform=tvOS,id=<DEVICE_ID>' -allowProvisioningUpdates build
```

Install and launch with `xcrun devicectl device install app` and `... process launch com.feezerj.AirTraffic`.

## Verification expectations

Type-checking and tests prove correctness, not that the UI looks right. After a UI change, render the relevant
`design-preview` scenes and view them. The preview cannot show blur, focus effects or performance, so say plainly
when something is unverified on a real Apple TV. Add or update tests for engine changes; a test should be able to
fail (write it, watch it fail, then fix).

## Things that have already bitten

- **Version:** Apple's version field allows only digits and dots. `MARKETING_VERSION` holds the number (with
  `CURRENT_PROJECT_VERSION` the build) and the `-beta` is `AT_RELEASE_CHANNEL`; `AppVersion.display` joins them. Bump both in `project.yml` and add a changelog entry.
- **Personal config:** `Config/Local.xcconfig` holds the photo contact email and the signing team. It is
  git-ignored. Never commit it, and never put personal values in `project.yml`, docs or tests. Regenerating the
  project without a team in `Local.xcconfig` drops signing.
- **Contact privacy:** `ClientIdentity.photoUserAgent` is the only place the contact may be sent, and only to
  Planespotters. Everything else uses `ClientIdentity.userAgent`. A test enforces this.
- **Route data lies:** callsigns are reused. Always run routes through `RouteValidator`; never display an unvalidated one.
- **Maps:** CARTO's free dark tiles need an API key. The default is OpenStreetMap darkened with a colour filter
  in `TileLayer`; a custom tile URL is assumed to already be dark. airplanes.live also needs contact for access.
- **Zoom:** the view radius (`settings.mapRadiusNM`) differs from the fetch radius (`fetchRadiusNM`, 1.9x). A test
  proves each zoom step is already covered by the previous fetch. Changing the view must never restart polling
  or clear aircraft.
- **Platform gaps:** tvOS has no `scrollContentBackground` and no web view; iOS has no `focusSection`. SwiftUI's
  `Settings` collides with ours, hence `AppSettings`. `ImageRenderer` cannot draw `ScrollView`, so `NearbyStrip`
  uses a plain stack on macOS for previews only.
- **Always-on behaviour:** `Ambient` owns idle fading, night dimming and the pixel drift. A press on hidden controls
  must only wake them (`consumeWakeUp`); remote movement is detected through `UIFocusSystem.didUpdateNotification`.
- **Alerts:** an emergency must persist `emergencyConfirmAfter` (12 s) before it shows; tests set it to 0.
- **Failover:** `FailoverFeed` retries the preferred provider after a window; its tests inject a clock. Never treat
  `CancellationError` as an outage.
- **Icons:** the Top Shelf images are JPEG (opaque, about a tenth the size); the layered icon stays PNG. Keep the
  asset catalog small.
- **CI:** `.github/workflows/ci.yml` mirrors the local commands. It can't be run locally, so after changing it push
  and watch the run.
- **Menu button:** the main screen deliberately swallows Menu (`onExitCommand` in `TVDashboardView`) so it can't close
  an always-on display; Settings is left to dismiss itself. This may conflict with App Store review (see ROADMAP).
- **Focus:** use `FlatButtonStyle` and read `@Environment(\.isFocused)` inside the label, so tvOS's built-in lift
  does not stack on custom focus styling.
- **Demo traffic** flies a fixed-size loop (`DemoFeed.loopRadiusNM`) so zooming never moves it.
- **Test data:** never commit captures that name a private owner, a private aircraft's registration, or the point you queried from.
- **Network in tests:** live checks must stay opt-in (`LIVE_TESTS=1`); keep the default suite offline.

## Style

Match the surrounding code. Default to no comments; add one only to explain a non-obvious why. Prefer editing
existing files, keep changes scoped to the request, and do not add dependencies or abstractions for hypothetical
needs.

## Git

Do not commit unless asked. Never commit `Config/Local.xcconfig`, build products or `Preview/` output.
