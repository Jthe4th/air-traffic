# Air Traffic

**Version 1.0.1-beta** · tvOS · [Changelog](CHANGELOG.md) · [Roadmap](ROADMAP.md) · [Notes for contributors and AI agents](AGENTS.md)

A living-room display for Apple TV that shows the aircraft flying near your home: a dark live map, the plane
that's closest or overhead featured in detail (photo, airline, route, progress, altitude, speed, vertical rate,
closest approach, squawk, autopilot targets, wind aloft and more), and a strip of everything else in range.
No Home Assistant, no server, no paid Apple developer account needed.

![preview](docs/preview.png)

*Rendered from the real SwiftUI views by `design-preview` with demo traffic. Blur and focus effects look better on a TV.*

## Run it on your Apple TV (free Apple ID)

1. `open AirTraffic.xcodeproj`
2. Target **AirTraffic ▸ Signing & Capabilities**: pick your Personal Team (or set `DEVELOPMENT_TEAM` in
   `Config/Local.xcconfig`). If the bundle ID is taken, change it (`com.feezerj.AirTraffic` in [project.yml](project.yml)).
3. Pair the Apple TV: on the TV, **Settings ▸ Remotes and Devices ▸ Remote App and Devices**; in Xcode,
   **Window ▸ Devices and Simulators ▸ +** and enter the code. Both must be on the same network.
4. Choose the Apple TV as the run destination and press Run.
5. First launch shows demo traffic. Open the gear (swipe up from the aircraft strip) and set your location by
   ZIP/city, or use the Apple TV's own location.

Free-account builds expire after 7 days; run again from Xcode to refresh. If you change `project.yml`,
regenerate the project with `xcodegen generate` (`brew install xcodegen`).

**Remote:** swipe along the bottom strip to pick an aircraft (it stays featured for a minute), Play/Pause
pins or unpins, otherwise it follows the nearest and rotates through anything inside the overhead zone.
The **+ / −** buttons on the map's right edge (swipe down from the gear) step the view through round radii
(5, 10, 25, 40, 60 mi, or the metric/nautical equivalents) and remember the choice. Zooming never reloads or
clears the map; the app already fetches a wider area than it shows.

## Aircraft photos and your contact

Photos come from Planespotters, whose API needs no account or key but asks every app to identify a contact
(an email or website) in its requests. Photos stay off until one is set, and it is sent **only to Planespotters**;
map and flight-data services see a generic app name.

- **Built-in default:** `AT_CONTACT` in [Config/App.xcconfig](Config/App.xcconfig). Put yours in
  `Config/Local.xcconfig` (git-ignored; copy `Local.xcconfig.example`) so it never lands in the source.
  If you distribute the app, use a support URL or project email here, not a personal address.
- **Per-viewer override:** Settings ▸ Aircraft photos ▸ contact. It wins over the default, and applies a moment
  after you stop typing. Only well-formed emails and web addresses are accepted.

`Local.xcconfig` also holds `DEVELOPMENT_TEAM` (your signing team) so regenerating the project keeps it, and
can set `AT_TILE_URL` / `AT_TILE_ATTRIBUTION` to use another map tile server (add `@2x` for 512 px tiles).

## How it's built

```
Sources/OverheadKit   engine, no UI: feeds, geometry, routes, tracking, reference data   (tvOS/iOS/macOS)
Sources/OverheadUI    SwiftUI: map, aircraft card, strip, settings                       (tvOS/iOS/macOS)
Sources/DesignPreview macOS tool that renders the TV layout to PNG
Apps/tvOS             the app target (just @main + Info.plist)
Tests/OverheadKitTests  unit tests, including an anonymised adsb.fi capture
```

- **Positions:** adsb.fi (or adsb.lol) every 5 s; planes glide between updates by dead reckoning.
  Providers only ever see your location rounded to ~0.7 mi.
- **Routes:** ADSB.lol standing data per callsign, shown only if the plane's position and heading actually fit
  the route. Callsigns get reused (the database says UAL2850 is SFO→ONT even when it's flying near Dulles),
  so a wrong route is rejected rather than displayed. See `RouteValidator`.
- **Maps:** OpenStreetMap raster tiles (your viewed area is visible to the tile server). Keep personal-scale.
- **Check each provider's current terms.** adsb.fi's open API is for personal, non-commercial use.
  (airplanes.live now requires contacting them for API access, so it isn't used.)

## Dev

```bash
swift test --scratch-path ~/Library/Caches/air-traffic-build            # unit tests
swift run --scratch-path ~/Library/Caches/air-traffic-build design-preview ./Preview busy quiet nophoto welcome zoomin zoomout crowded
```

Keep build output outside this folder; it lives in OneDrive. Scenes ending in `2` or `3` show the later
telemetry pages. Verified by: tests, compiling OverheadKit/OverheadUI against the tvOS and iOS SDKs, an unsigned
`xcodebuild` of the app for tvOS, and the rendered previews. Run by hand on an Apple TV 4K; older hardware is untested.

## What's next

See [ROADMAP.md](ROADMAP.md). Known gaps today: no app icon, Menu exits the app, photos need a contact configured,
and remote focus around the newest controls and performance on older Apple TV hardware are unconfirmed.

## License

[MIT](LICENSE). Third-party data and marks (airline names, aircraft photos, map tiles, flight data) belong to their
owners and stay subject to each provider's terms.
