# Roadmap

Where the project is going. Nothing here is a promise or a date; it is ordered by what is most useful next.
Shipped work is in [CHANGELOG.md](CHANGELOG.md).

## Next up: finish the Apple TV app

- **Confirm on a real Apple TV:** remote focus around the strip, gear and zoom buttons, and smoothness on older
  hardware (development has used an Apple TV 4K, 3rd generation).
- **Settings polish for the TV:** search as you type with focus moving to the results, and a cleaner layout than
  the default form.

## Soon

- **iPhone and iPad app with a sky view:** point the device at the sky (compass and motion sensors) and see the
  aircraft overhead labelled. The engine and views already build for iOS; this adds the sensors and the camera
  overlay.
- **Local ADS-B receiver as a data source:** read a readsb or dump1090 box on your own network for lower latency
  and no rate limits. The feed layer already speaks that format.
- **Real airline logos,** replacing the brand-coloured letter badges, once licensing is checked.
- **Broader reference data:** more airlines and aircraft types, and friendlier names for unusual aircraft.
- **Quieter map near airports:** option to hide ground traffic labels.
- **A second route source** for airliners the first has no route for.
- **Today at a glance:** planes seen, highest, fastest and busiest hour, from the sightings history.
- **Accessibility and localisation:** VoiceOver labels, larger-text support, translations.

## Before sharing it beyond a personal build

- **Replace the personal photo contact** in the built-in default with a project support address or website.
- **Review each free service's terms for an app with many users.** OpenStreetMap's tile servers discourage heavy
  use from distributed apps, so a tile provider with its own plan is likely needed. Check adsb.fi, adsb.lol and
  Planespotters too, including how photographers must be credited.
- **Join the paid Apple Developer Program** to distribute through TestFlight or the App Store. Free-account builds
  only run on your own devices and expire after 7 days.
- **Revisit the Menu button for App Store review.** Apple's guidelines expect Menu to leave the app from its top
  screen, and this app currently swallows it. Reviewers may object; an alternative such as a long press may be needed.
- **Privacy details:** a privacy policy and App Store privacy answers covering the location it uses.

## Ideas

- **Air traffic audio:** play a live ATC stream beside the map. Start small: a stream URL in Settings (nothing
  bundled), a play/mute button in the header, a "now listening" chip, muted during night dimming, off by default.
  Later, pick the feed from the featured aircraft's phase of flight (arriving, departing, overhead) using a small
  editable airport-to-feed table.
  - *Source:* LiveATC allows personal, non-commercial use, and a forum post quotes its homepage as prohibiting
    third-party use of its streams. Read its terms and ask first; this also rules out bundling feeds. A local RTL-SDR
    receiver streaming on the home network avoids the question. Broadcastify needs an account or licence.
  - *Caveats:* streams are often plain `http` (needs an App Transport Security exception, a mark against App Store
    release) and run behind real time, so the audio won't match the map exactly. Transcribing calls isn't practical:
    Apple's speech recognition is unavailable on tvOS, and the alternatives are heavy or need an account.
- **Refine the home location by moving a pin on the map,** for addresses Apple Maps places a little off (long
  driveways, new builds). A street address or pasted coordinates work today.
- **Flyby cards that adapt:** quiet hours, a stronger "straight overhead" treatment, a lead time you can set, and
  choosing which aircraft qualify (military, helicopters, a favourite airline).
- A web radar version that runs in any browser, as a no-account option for other TVs.
- A macOS menu-bar widget showing the nearest aircraft.
- Statistics such as highest, fastest and most frequent aircraft over your home.
- More than one saved home location.

## Not planned

Accounts, a backend server, advertising, or tracking of viewers.
