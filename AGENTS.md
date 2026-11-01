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

The tvOS 27 simulator runs the app, which is how to check anything the preview cannot draw (settings pages, pickers, focus):
build with `-sdk appletvsimulator -destination 'platform=tvOS Simulator,id=<SIM_ID>'`, then `xcrun simctl boot/install/launch`,
and drive it with the iOS Simulator control tool (`attach`, `press_key` for arrows and return, `screenshot`). Wait a couple of
seconds between presses: a press that lands during a transition is lost. Don't use Device Hub for this (see below).

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
  `LiveRouteProvider` asks ADSB.lol standing data, then adsbdb, and validates every listed route against the aircraft; it
  reports `RouteLookup` (found, unconfirmed, unavailable, or couldn't ask) and the engine records it as `RouteStatus` so the
  card can say "Checking route…" or "Route unconfirmed" instead of a blanket "Route not available". Both databases hold one
  static route per callsign, so most "unconfirmed" flights are correct rejections, not bugs; measure before loosening the
  corridor in `RouteValidator`.
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
  Nothing makes a sound while `ambient.isNight` (the Space Station chimes are checked in `TVDashboardView`).
- **Alerts:** an emergency must persist `emergencyConfirmAfter` (12 s) before it shows; tests set it to 0.
- **Failover:** `FailoverFeed` retries the preferred provider after a window; its tests inject a clock. Never treat
  `CancellationError` as an outage.
- **Icons:** the Top Shelf images are JPEG (opaque, about a tenth the size); the layered icon stays PNG. Keep the
  asset catalog small.
- **CI:** `.github/workflows/ci.yml` mirrors the local commands. It can't be run locally, so after changing it push
  and watch the run.
- **Device Hub:** while Xcode's Device Hub app is connected to the Apple TV (screen view or remote buttons), tvOS draws
  two thin red lines across the top and bottom of the screen. They are a system overlay, absent from
  `devicectl device capture screenshot`, and they survive closing the window and rebooting the TV. Quit the whole app
  when you are done. Prefer `devicectl` (install, launch, capture screenshot) where it can answer the question.
- **Flybys:** `viewerHeadingDeg` is the direction the viewer *looks* when watching (seat toward the screen), not the way
  the screen faces; "ahead" is past the TV. "Left to right" always means the aircraft's compass bearing is increasing
  (`PassMotion`). Home from a city or ZIP search is only a place centre (`HomeSource.place`), so exact directions need a
  street address or coordinates. Address lookup is MapKit's `MKLocalSearch` (`AddressSearch`, in OverheadUI): it returns
  something even for nonsense, so the viewer confirms from a list, and the street address is never stored or shown
  (`AddressMatch`: only the point and the town name are kept). One card per pass with a 10-minute cool-down. The left/right, grace-period and cool-down rules were each
  checked by breaking them and watching a test fail.
- **Pickers:** SwiftUI's `Picker` comes up blank on tvOS inside the Settings screen (found on the real TV, not in any
  preview). Use `ChoiceRow`, which pushes a list page of its own.
- **Text fields:** the tvOS keyboard is a screen of its own, and its Enter key reads "next" and jumps to the next text field
  in the form. Don't bind a `TextField` straight to `engine.settings` (every keystroke redraws Settings under the keyboard),
  and don't reload a page's values in `onAppear` (the page "reappears" after each field and overwrites what was typed).
  Hold the text in local `@State` read once in `init`, and commit on `onSubmit` and `onDisappear` (`DirectionNamesView`).
- **Altitude:** `barometricAltitudeFt` is *pressure* altitude (1013.25 hPa), which reads below zero near sea level on a
  high-pressure day. `Aircraft.altitudeFt` is the corrected, never-negative number; the engine sets `qnhCorrectionFt` at
  ingest from the median `nav_qnh` of low aircraft (`Altimetry`). Use `altitudeFt`, never the raw field, for display.
- **Space stations:** `SpaceObject` is the catalogue (ISS, Tiangong): catalogue number, names, aircraft id, silhouette, standard
  magnitude, and `announceBrighterThan` (a floor that drops Tiangong's faint low passes; the ISS has none). Everything is
  per object: orbits, passes, aircraft entries (found by `object.id`, never "any spacecraft"), switches, card ids. Tiangong's
  standard magnitude (-0.5) is an estimate; re-check it if its passes look wrong. The orbit is computed on the TV (`Sources/OverheadKit/Space`): `SGP4` (near-Earth only; deep-space
  orbits are refused) from CelesTrak elements, `Sky` for time, frames, Sun and shadow, `PassFinder` for visible passes
  (10° up, Sun below -6°, station sunlit, peak at least 20°). The engine adds the station to `aircraft` once a second while
  it is within range, flagged by `Aircraft.spacecraft`; everything that assumes an aircraft (routes, photos, flyby
  cards, projection lines, feet and knots) checks `isSpacecraft`. `ingest` must not let it coast between feed reports
  (it moves 4 NM a second). Only the catalogue number is ever sent to CelesTrak. Tests and previews stay off the network
  unless they pass an `orbits:` provider. Reference numbers in `SpaceTests.swift` came from python-sgp4 and Skyfield with
  DE421 (a throwaway venv, nothing added to the repo); after changing the maths, regenerate them the same way, don't loosen
  the tolerances. A pass card never claims a pass is visible unless the Sun, shadow and sky all agree.
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
