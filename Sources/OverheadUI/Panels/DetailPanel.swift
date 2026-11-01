import SwiftUI
import OverheadKit

/// The featured-aircraft card: photo, identity, route, and rotating pages of live telemetry.
struct DetailPanel: View {
    let tracked: TrackedAircraft
    let home: GeoPoint
    let settings: AppSettings
    var pinned: Bool = false
    @Environment(\.fixedNow) private var fixedNow

    static let width: CGFloat = 740

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let now = fixedNow ?? timeline.date
            let rel = tracked.aircraft.relative(to: home, at: now)
            let pages = AircraftFacts.pages(tracked, home: home, now: now, units: settings.units)
            let pageIndex = pages.count > 1 ? Int(now.timeIntervalSinceReferenceDate / 7) % pages.count : 0

            VStack(alignment: .leading, spacing: 18) {
                PhotoHeader(tracked: tracked, rel: rel, alertNM: settings.alertRadiusNM, units: settings.units, pinned: pinned)
                IdentityBlock(tracked: tracked)
                RouteBlock(tracked: tracked, now: now, units: settings.units)
                FactGrid(facts: pages[min(pageIndex, pages.count - 1)])
                    .id(pageIndex)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.45), value: pageIndex)
                PageDots(count: pages.count, index: pageIndex)
            }
            .padding(28)
            .frame(width: Self.width, alignment: .topLeading)
            .glassCard(radius: 40)
        }
    }
}

// MARK: - Photo

private struct PhotoHeader: View {
    let tracked: TrackedAircraft
    let rel: Relative
    let alertNM: Double
    let units: UnitSystem
    let pinned: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        let a = tracked.aircraft
        let tint = a.isSpacecraft ? Theme.station : Theme.altitudeColor(a.altitudeFt.map(Double.init), onGround: a.onGround)
        ZStack(alignment: .topLeading) {
            // The backdrop is always there, so the photo fades in over it instead of over an empty box.
            if a.isSpacecraft { spaceBackdrop } else { backdrop(tint: tint) }
            if let photo = tracked.photo {
                CachedImage(url: photo.imageURL)
                    .frame(width: DetailPanel.width - 56, height: 230)
                    .clipped()
            }
            LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)

            HStack(spacing: 10) {
                statusChip
                if pinned { chip("PINNED", color: Theme.warning) }
                Spacer()
            }
            .padding(16)

            if let photo = tracked.photo, let by = photo.photographer {
                Text("Photo: \(by) · planespotters.net")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .shadow(color: .black.opacity(0.8), radius: 3)
                    .padding(.horizontal, 16).padding(.bottom, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(width: DetailPanel.width - 56, height: 230)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1.2))
    }

    private func backdrop(tint: Color) -> some View {
        let airlineColor = tracked.airline.map { Theme.color(hex: $0.color) } ?? Color(red: 0.2, green: 0.26, blue: 0.34)
        return ZStack {
            LinearGradient(colors: [airlineColor.opacity(0.65), Theme.ink], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [tint.opacity(0.25), .clear], center: .center, startRadius: 10, endRadius: 330)
            SilhouetteView(kind: AircraftTypes.silhouette(for: tracked.aircraft))
                .fill(.white.opacity(0.13))
                .frame(width: 300, height: 300)
                .rotationEffect(.degrees(-28))
                .offset(x: 120, y: 18)
            SilhouetteView(kind: AircraftTypes.silhouette(for: tracked.aircraft))
                .stroke(.white.opacity(0.3), lineWidth: 2)
                .frame(width: 300, height: 300)
                .rotationEffect(.degrees(-28))
                .offset(x: 120, y: 18)
        }
        .frame(width: DetailPanel.width - 56, height: 230)
    }

    /// Night sky with the Earth's limb glowing along the bottom, and the station itself.
    private var spaceBackdrop: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.04, blue: 0.12), Color(red: 0.05, green: 0.09, blue: 0.22)], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                var seed: UInt64 = 0x2545F4914F6CDD1D
                func next() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
                for _ in 0..<70 {
                    let r = 0.8 + next() * 1.6
                    ctx.fill(Path(ellipseIn: CGRect(x: next() * size.width, y: next() * size.height * 0.85, width: r, height: r)),
                             with: .color(.white.opacity(0.25 + next() * 0.6)))
                }
            }
            Ellipse()
                .fill(RadialGradient(colors: [Color(red: 0.25, green: 0.55, blue: 1.0).opacity(0.55), Color(red: 0.1, green: 0.25, blue: 0.6).opacity(0.0)],
                                     center: .center, startRadius: 40, endRadius: 330))
                .frame(width: 900, height: 340)
                .offset(y: 190)
            SilhouetteView(kind: .station).fill(Theme.station.opacity(0.22)).frame(width: 250, height: 250).rotationEffect(.degrees(-24)).offset(x: 130, y: -6)
            SilhouetteView(kind: .station).stroke(Theme.station.opacity(0.6), lineWidth: 2).frame(width: 250, height: 250).rotationEffect(.degrees(-24)).offset(x: 130, y: -6)
        }
        .frame(width: DetailPanel.width - 56, height: 230)
    }

    @ViewBuilder private var statusChip: some View {
        if tracked.aircraft.onGround {
            chip("ON THE GROUND", color: Theme.secondary)
        } else if rel.distanceNM <= alertNM {
            chip(rel.approaching == false ? "OVERHEAD · LEAVING" : "OVERHEAD NOW", color: Theme.accent)
        } else {
            chip(rel.approaching == false ? "MOVING AWAY" : "APPROACHING", color: Theme.secondary)
        }
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 19, weight: .bold)).tracking(1.4)
            .foregroundStyle(color)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(.black.opacity(0.55)))
            .overlay(Capsule().strokeBorder(color.opacity(0.7), lineWidth: 1.5))
    }
}

// MARK: - Identity

private struct IdentityBlock: View {
    let tracked: TrackedAircraft

    var body: some View {
        let a = tracked.aircraft
        if let craft = a.spacecraft {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 18) {
                    AirlineBadge(size: 80, spacecraft: true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Crewed spacecraft").labelStyle(Theme.secondary).lineLimit(1)
                        Text(a.title).font(Theme.serif(68)).foregroundStyle(Theme.text)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 12) {
                    Text(craft.name).font(Theme.body(30, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.65)
                    Spacer(minLength: 0)
                    Text("IN ORBIT").font(.system(size: 18, weight: .bold)).tracking(1.2).foregroundStyle(Theme.station)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .overlay(Capsule().strokeBorder(Theme.station.opacity(0.8), lineWidth: 1.5))
                }
            }
        } else {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 18) {
                AirlineBadge(airline: tracked.airline, fallbackText: a.registration.map { String($0.prefix(2)) } ?? "", size: 80)
                VStack(alignment: .leading, spacing: 0) {
                    Text(tracked.operatorName ?? (a.operatorName == nil ? "Private aircraft" : a.operatorName!.capitalizedWords))
                        .labelStyle(Theme.secondary).lineLimit(1)
                    Text(tracked.flightNumber ?? a.title)
                        .font(Theme.serif(68)).foregroundStyle(Theme.text)
                        .lineLimit(1).minimumScaleFactor(0.55)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                Text(tracked.typeName ?? "Unknown type")
                    .font(Theme.body(30, weight: .semibold)).foregroundStyle(Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.65)
                if let reg = a.registration {
                    Text(reg)
                        .font(.system(size: 24, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.09)))
                }
                Spacer(minLength: 0)
                ForEach(tags(a), id: \.0) { tag in
                    Text(tag.0).font(.system(size: 18, weight: .bold)).tracking(1.2)
                        .foregroundStyle(tag.1)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .overlay(Capsule().strokeBorder(tag.1.opacity(0.8), lineWidth: 1.5))
                }
            }
        }
        }
    }

    private func tags(_ a: Aircraft) -> [(String, Color)] {
        var out: [(String, Color)] = []
        if let e = a.emergency { out.append((e.uppercased(), Theme.danger)) }
        else if Squawk.info(for: a.squawk)?.isEmergency == true { out.append(("EMERGENCY", Theme.danger)) }
        if a.flags.contains(.military) { out.append(("MILITARY", Theme.warning)) }
        if a.flags.contains(.interesting) { out.append(("NOTABLE", Theme.accent)) }
        return out
    }
}

// MARK: - Route

private struct RouteBlock: View {
    let tracked: TrackedAircraft
    let now: Date
    let units: UnitSystem

    var body: some View {
        if let craft = tracked.aircraft.spacecraft {
            HStack(spacing: 14) {
                Image(systemName: "globe.americas.fill").font(.system(size: 28, weight: .medium)).foregroundStyle(Theme.tertiary)
                Text("Circles the Earth every \(Int(craft.periodMinutes.rounded())) minutes")
                    .font(Theme.serif(29)).italic().foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
            }
            .padding(.vertical, 14)
        } else if let route = tracked.route {
            let progress = route.progress(position: tracked.aircraft.position(at: now), groundSpeedKt: tracked.aircraft.groundSpeedKt)
            VStack(spacing: 8) {
                HStack(alignment: .top) {
                    endpoint(route.origin, alignment: .leading)
                    Spacer(minLength: 12)
                    endpoint(route.destination, alignment: .trailing)
                }
                ProgressTrack(fraction: progress.fraction)
                HStack {
                    Text("\(units.longDistance(nm: progress.flownNM).text) flown")
                    Spacer()
                    Text(footer(progress))
                }
                .font(Theme.body(23)).foregroundStyle(Theme.secondary)
            }
        } else {
            let (headline, note) = noRouteText
            HStack(spacing: 14) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 26, weight: .medium)).foregroundStyle(Theme.tertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(Theme.serif(29)).italic().foregroundStyle(Theme.secondary)
                    if let note { Text(note).font(Theme.body(21)).foregroundStyle(Theme.tertiary) }
                }
                Spacer()
            }
            .padding(.vertical, 14)
        }
    }

    /// Why there is no route, in the viewer's terms. Route databases keep one route per flight number, so a listed route can
    /// be for another trip: that is "unconfirmed", not wrong data to show.
    private var noRouteText: (String, String?) {
        switch tracked.routeStatus {
        case .checking: ("Checking route…", nil)
        case .unconfirmed: ("Route unconfirmed", "Listed for a different trip")
        case .found, .unavailable: (tracked.airline != nil ? "Route not available" : "Private or unscheduled flight", nil)
        }
    }

    private func footer(_ p: FlightRoute.Progress) -> String {
        var s = "\(units.longDistance(nm: p.remainingNM).text) to go"
        if let eta = p.etaSeconds, p.remainingNM > 15 { s += " · \(humanInterval(eta))" }
        return s
    }

    private func endpoint(_ airport: Airport, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(airport.code).font(Theme.serif(62)).foregroundStyle(Theme.text)
            Text(airport.city).font(Theme.body(24, weight: .medium)).foregroundStyle(Theme.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: 300, alignment: alignment == .leading ? .leading : .trailing)
    }
}

private struct ProgressTrack: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = max(14, min(w - 14, w * fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14)).frame(height: 6)
                Capsule().fill(LinearGradient(colors: [Theme.accent.opacity(0.25), Theme.accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: x, height: 6)
                Image(systemName: "airplane")
                    .font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                    .shadow(color: Theme.accent.opacity(0.8), radius: 8)
                    .position(x: x, y: geo.size.height / 2)
            }
        }
        .frame(height: 34)
    }
}

// MARK: - Facts

private struct FactGrid: View {
    let facts: [Fact]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(facts) { fact in
                VStack(alignment: .leading, spacing: 3) {
                    Text(fact.label).labelStyle().lineLimit(1).minimumScaleFactor(0.7)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(fact.value)
                            .font(Theme.number(42)).foregroundStyle(fact.tint)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        if !fact.unit.isEmpty {
                            Text(fact.unit).font(Theme.body(22)).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                    }
                    Text(fact.note ?? " ").font(Theme.body(21)).foregroundStyle(Theme.secondary)
                        .lineLimit(1).minimumScaleFactor(0.65)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 124, maxHeight: 124, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.07)))
            }
        }
    }
}

private struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        if count > 1 {
            HStack(spacing: 8) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule().fill(i == index ? Theme.accent : .white.opacity(0.22))
                        .frame(width: i == index ? 26 : 9, height: 9)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.3), value: index)
        }
    }
}
