# Changelog

All notable changes are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and versions follow [Semantic Versioning](https://semver.org/).

Pre-release builds are labelled `-beta`. Apple's bundle version field allows only digits and dots, so the app's
`CFBundleShortVersionString` holds the number (`1.1.2`) and the label lives in `AT_RELEASE_CHANNEL`
([project.yml](project.yml)); the app, this file and the git tags show them together (`1.1.2-beta`).

## [Unreleased]

## [1.1.2-beta] - 2026-11-01

### Added
- **International Space Station.** About 15 minutes before the station will be visible from your home (a bright, fast
  star crossing the sky after dark, lit by the Sun while your sky is dark and at least 20° above the horizon), a slim
  card says when and which way to look. In the last two minutes and during the pass it grows into a full card with a
  sky chart: when and where it appears, its highest point, where it sets or fades into Earth's shadow, how bright it
  will be and for how long. A gentle chime sounds when the card appears and a brighter one as the pass begins. The warning
  time is 5, 10, 15 or 30 minutes (Settings ▸ Space Station), and a sample card lets you see and hear it.
  When nothing is flying, Quiet skies shows the next pass.
- **The station on the map.** Whenever it flies over your home, day or night and seen or not, it is tracked like an
  aircraft: a station glyph and "ISS · In orbit" label on the map, a chip in the nearby strip, and its own card (altitude and
  speed in your units, heading, distance, how high in the sky, closest approach, whether the Sun is on it). It takes the
  featured card while it is in view, is recorded in Recent sightings, and is never given a route, a photo or a flyby card.
- The orbit is worked out on the Apple TV from the station's published orbital elements (SGP4, the standard method),
  downloaded from CelesTrak about every 8 hours and kept for a restart or an outage. The download names only the
  station, never your location. Elements more than 14 days old are not trusted.
- Design-preview scenes `issupcoming`, `issimminent`, `issnow`, `issover` and `issquiet`, and
  `design-preview --chimes <dir>` to write the two sounds as WAV files.
- 63 new tests. The orbit maths is checked against independent references (python-sgp4 for positions; Skyfield with
  NASA's DE421 ephemeris for sky angles, the Sun, Earth's shadow and a 12-day list of passes), and the physics, shadow,
  dark-sky, warning-time, flyby, off-map and chime behaviours were each broken on purpose to confirm a test fails.

## [1.1.1-beta] - 2026-10-30

### Added
- **Close-flyby card.** About 45 seconds before an aircraft passes within a couple of miles (and below 20,000 ft by
  default), a card says which way to look from your seat: a plain direction ("Behind you", "On your left") or your own
  name for that side of the room ("Back door"), how high, and whether it will cross left to right or right to left,
  with a small sky dial and the flight's details. It stays through the pass and a moment after, and an aircraft gets
  one card per pass (then a 10-minute cool-down). Settings ▸ Close flybys turns it off and sets what counts as close,
  the highest altitude, which way you face when watching TV, and the four names.
- **Exact home location from a street address.** Type your address in Settings ▸ Location and pick the match: the Apple
  TV looks it up with Apple Maps (the only place it is sent), and only the point and your town are kept, so a house
  number never shows on screen or in the saved settings. You can also paste coordinates (decimal, with N/S/E/W, or
  degrees-minutes-seconds). Settings shows how the location was chosen and says when it is only a city or ZIP centre,
  which can be a mile or more off.
- **Sample card** (Settings ▸ Close flybys) shows a plane due north of you, to check the direction settings against a
  compass.
- Design-preview scene `flyby`. 29 new tests; the left/right, grace-period and cool-down rules were each checked by
  breaking them and watching a test fail.

### Fixed
- **Every choice in Settings opened a blank page on the Apple TV** (Map radius, Overhead zone, Units, Hide controls, Aircraft
  data, Alerts, and the new flyby and direction settings): SwiftUI's built-in picker page never drew inside the Settings
  screen. Each now opens a list of its own with a checkmark on the current choice and the cursor on it.

- **Negative altitudes** (a plane on a runway reading -400 ft). ADS-B altitude is pressure altitude, measured against a
  fixed 1013.25 hPa, so near sea level on a high-pressure day it reads below zero. The app now works out the area's
  pressure setting from what nearby aircraft broadcast (the median of those flying below 12,000 ft, remembered for 30
  minutes) and corrects altitudes below 17,000 ft with it, so altitudes are above sea level, as a pilot's altimeter shows.
  Flight levels are untouched, and anything still below zero is shown as zero.
- **The names for each side of the room lost entries** when typed in a row: the keyboard's Enter key moves on to the next
  name, and with each keystroke being written straight into the saved settings, names were dropped or cut short. They now
  have a page of their own (Settings ▸ Close flybys ▸ Names for each side) that holds what you type and saves when a name
  is finished or the page closes.

### Changed
- **Location settings have their own page** (Settings ▸ Location ▸ Home location). It opens with where you are
  watching and how exact that is, then offers the street address as the best way to set it, and the Apple TV's
  location, a city or ZIP code, and coordinates as labelled alternatives. Saving says so and shows the new status. The
  main Settings page shows one row, and the Close flybys section points there when the location is only approximate.

## [1.1.0-beta] - 2026-10-30

### Added
- **Always-on display mode.** Controls (gear, zoom, nearby strip) fade after a period without remote input, and the
  first press afterwards only wakes them. Dimming between 10 PM and 6 AM. A slow few-pixel drift of the whole layout
  protects OLED panels from burn-in. Settings ▸ Display.
- **Alerts.** A banner, a pulsing red ring on the map and an EMERGENCY tag for aircraft squawking 7500/7600/7700 or
  reporting an emergency, and a banner for aircraft flagged as notable. An emergency on the map takes over the aircraft
  card unless you chose one. Emergencies must persist about 12 seconds so a code being dialled isn't reported.
- **Provider failover.** If the preferred data provider fails, the other answers in the same update; the preferred one
  is retried after two minutes. Can be turned off.
- **Connection diagnostics** in Settings: active provider, last update, response time, aircraft count, request tally
  and the last error.
- **App icon and Top Shelf images**, drawn in code (`design-preview --icons`) and built into the asset catalog by
  `scripts/make-icon-catalog.py`.
- **Continuous integration** on GitHub Actions: unit tests, tvOS and iOS builds, and an unsigned build of the app.
- Design-preview scenes `alert` and `ambient`.

### Fixed
- The photo area no longer shows an empty box while an aircraft photo loads; the silhouette backdrop stays visible
  and the photo fades in over it.

### Changed
- Menu on the Siri Remote no longer exits the app from the main screen. It unpins an aircraft you chose and
  otherwise does nothing; inside Settings it still closes Settings. The TV button still leaves the app.
## [1.0.1-beta] - 2026-10-30

First beta. tvOS only, installed from Xcode with a free Apple ID.

### Added

**Map**
- Full-screen dark map (OpenStreetMap tiles darkened in-app) centred on your home, with range rings at round numbers
  in your units, a dashed "overhead" zone, and compass points.
- Aircraft drawn as top-down silhouettes (jet, propeller, helicopter), coloured by altitude, sized by weight class,
  and gliding between 5-second updates by dead reckoning. Fading trails, a projected 6-minute path for the featured
  aircraft, and a marker where it will pass closest to you.
- Labels that dodge each other, with a budget so crowded skies stay readable; markers shrink as you zoom out.
- **+ / −** zoom buttons stepping through 5, 10, 25, 40 and 60 mi (or the metric and nautical equivalents). Zooming
  never clears the map: the app fetches about 1.9x the visible area, and the previous zoom's tiles stay underneath
  while new ones load.

**Featured aircraft**
- Photo from Planespotters with credit, airline badge, flight number, aircraft type, registration, and tags for
  military, notable and emergency squawks.
- Route with origin, destination, miles flown, miles to go and time remaining. Routes are shown only when the
  aircraft's position and heading fit them, because callsigns are reused.
- Live stat tiles that rotate through pages: altitude and climb rate, speed and Mach, heading, distance, bearing
  and elevation angle, closest approach, squawk, autopilot targets, wind aloft, outside temperature, airspeeds,
  bank angle, year built, size class, highest altitude seen, and ICAO address with data source.
- Picks the nearest aircraft, rotates through anything inside the overhead zone, and jumps to a newcomer.

**Around the screen**
- Strip of nearby aircraft; moving remote focus along it selects one for a minute. Play/Pause pins or unpins.
- "Quiet skies" screen with recent sightings, status pill (live, demo, offline), and a clock.
- Demo mode with fictional flights, used on first launch and offline.

**Settings**
- Location by the Apple TV's own location or by search: ZIP code, city, `City, ST`, `City, State`, or `City, Country`.
- Map radius, overhead zone, units (imperial, metric, nautical), trails, aircraft rotation, data provider
  (adsb.fi or adsb.lol), demo mode, and the contact sent with photo requests. Shows the app version.

**Data and privacy**
- Positions from adsb.fi or adsb.lol, routes from ADSB.lol standing data, photos from Planespotters, place search
  from Open-Meteo. No accounts, API keys or servers.
- Data providers see your location rounded to about 0.7 mi. The photo contact is sent only to Planespotters.
- Personal build values (contact, signing team) live in a git-ignored `Config/Local.xcconfig`.

**Engineering**
- `OverheadKit` (engine, no UI) and `OverheadUI` (SwiftUI) as a Swift package building for tvOS, iOS and macOS. MIT licensed.
- `design-preview` tool that renders the TV layout to PNG without a simulator.
- Xcode project generated by XcodeGen. 46 unit tests, including an anonymised adsb.fi capture and live geocoder checks
  (opt-in with `LIVE_TESTS=1`).

### Known limitations
- No app icon or Top Shelf image yet (blank Home screen tile).
- Menu on the Siri Remote exits the app from the main screen.
- Aircraft photos need a contact (email or website) configured; they are off without one.
- Free-account builds expire after 7 days and must be reinstalled from Xcode.
- Remote focus behaviour of the zoom buttons has not yet been confirmed on a real Apple TV.

[Unreleased]: https://github.com/Jthe4th/air-traffic/compare/v1.1.2-beta...HEAD
[1.1.2-beta]: https://github.com/Jthe4th/air-traffic/compare/v1.1.1-beta...v1.1.2-beta
[1.1.1-beta]: https://github.com/Jthe4th/air-traffic/compare/v1.1.0-beta...v1.1.1-beta
[1.1.0-beta]: https://github.com/Jthe4th/air-traffic/compare/v1.0.1-beta...v1.1.0-beta
[1.0.1-beta]: https://github.com/Jthe4th/air-traffic/releases/tag/v1.0.1-beta
