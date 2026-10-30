import SwiftUI
import OverheadKit

struct Fact: Identifiable {
    var label: String
    var value: String
    var unit: String = ""
    var note: String?
    var tint: Color = Theme.text
    var id: String { label }
}

/// Turns an aircraft's raw telemetry into display tiles. Page 1 is always the essentials;
/// later pages hold whatever extra the aircraft happens to broadcast.
enum AircraftFacts {
    static func pages(_ t: TrackedAircraft, home: GeoPoint, now: Date, units: UnitSystem) -> [[Fact]] {
        let rel = t.aircraft.relative(to: home, at: now)
        var pages = [essentials(t, rel: rel, now: now, units: units)]
        let extra = extras(t, now: now, units: units)
        var rest = extra[...]
        while !rest.isEmpty && pages.count < 3 {
            let chunk = Array(rest.prefix(6))
            rest = rest.dropFirst(chunk.count)
            if chunk.count >= 3 || pages.count == 1 { pages.append(chunk) }
        }
        return pages
    }

    static func essentials(_ t: TrackedAircraft, rel: Relative, now: Date, units: UnitSystem) -> [Fact] {
        let a = t.aircraft
        var out: [Fact] = []

        // Altitude + vertical movement
        if a.onGround {
            out.append(Fact(label: "Altitude", value: "Ground", note: a.isMoving ? "Taxiing" : "Stationary"))
        } else if let ft = a.altitudeFt(at: now) {
            let q = units.altitude(ft: ft)
            var notes: [String] = []
            if let fl = flightLevelText(altitudeFt: Int(ft)) { notes.append(fl) }
            var tint = Theme.text
            if let vr = a.verticalRateFpm, abs(vr) >= 100 {
                let v = units.verticalRate(fpm: Double(vr))
                notes.append("\(vr > 0 ? "▲" : "▼") \(v.value) \(v.unit)")
                tint = vr > 0 ? Theme.climb : Theme.descend
            } else if a.verticalRateFpm != nil {
                notes.append("Level")
            }
            out.append(Fact(label: "Altitude", value: q.value, unit: q.unit, note: notes.joined(separator: " · "), tint: tint))
        }

        // Speed
        if let gs = a.groundSpeedKt {
            let q = units.speed(kt: gs)
            out.append(Fact(label: "Speed", value: q.value, unit: q.unit,
                            note: a.mach.map { String(format: "Mach %.2f", $0) } ?? "Ground speed"))
        }

        // Heading
        if let track = a.trackDeg {
            out.append(Fact(label: "Heading", value: String(format: "%.0f°", track), note: "Bound \(Geo.compass(track))"))
        }

        // Distance from the viewer
        let d = units.distance(nm: rel.distanceNM)
        var dnote = "\(Geo.compass(rel.bearingDeg)) of you"
        if let e = rel.elevationDeg, e >= 2 { dnote += " · \(Int(e.rounded()))° up" }
        out.append(Fact(label: "Distance", value: d.value, unit: d.unit, note: dnote))

        // Closest approach
        if let cpa = rel.closestApproach, !a.onGround {
            if cpa.movingAway {
                out.append(Fact(label: "Closest", value: "Leaving", note: "Heading away", tint: Theme.secondary))
            } else {
                let close = units.distance(nm: cpa.distanceNM)
                let note = cpa.distanceNM < 0.4 ? "Directly overhead" : "Passes \(close.text) away"
                out.append(Fact(label: "Closest", value: clockInterval(cpa.seconds), unit: "min", note: note,
                                tint: cpa.distanceNM < 1.5 ? Theme.accent : Theme.text))
            }
        }

        // Transponder
        if let sq = a.squawk {
            let info = Squawk.info(for: sq)
            out.append(Fact(label: "Squawk", value: sq, note: info?.meaning ?? "Transponder code",
                            tint: info?.isEmergency == true ? Theme.danger : Theme.text))
        } else {
            out.append(Fact(label: "In range", value: clockInterval(now.timeIntervalSince(t.firstSeen)), unit: "min", note: "Since first seen"))
        }
        return Array(out.prefix(6))
    }

    static func extras(_ t: TrackedAircraft, now: Date, units: UnitSystem) -> [Fact] {
        let a = t.aircraft
        var out: [Fact] = []

        if let alt = a.selectedAltitudeFt {
            let q = units.altitude(ft: Double(alt))
            var notes: [String] = []
            if let h = a.selectedHeadingDeg { notes.append(String(format: "Hdg %.0f°", h)) }
            let detail = a.autopilotModes.filter { $0 != "tcas" && $0 != "autopilot" }
            if let mode = detail.first { notes.append(mode.uppercased()) }
            else if a.autopilotModes.contains("autopilot") { notes.append("Autopilot") }
            out.append(Fact(label: "Autopilot set", value: q.value, unit: q.unit, note: notes.joined(separator: " · ").nilIfEmpty ?? "Selected altitude"))
        }
        if let ws = a.windSpeedKt, let wd = a.windDirectionDeg {
            let q = units.speed(kt: ws)
            out.append(Fact(label: "Wind aloft", value: q.value, unit: q.unit, note: String(format: "From %.0f° %@", wd, Geo.compass(wd))))
        }
        if let oat = a.outsideAirTempC {
            let q = units.temperature(celsius: oat)
            out.append(Fact(label: "Outside air", value: q.value, unit: q.unit, note: "At altitude"))
        }
        if let ias = a.indicatedAirspeedKt {
            let q = units.speed(kt: ias)
            out.append(Fact(label: "Airspeed", value: q.value, unit: q.unit,
                            note: a.trueAirspeedKt.map { "True \(units.speed(kt: $0).text)" } ?? "Indicated"))
        }
        if let roll = a.rollDeg, abs(roll) >= 3 {
            out.append(Fact(label: "Bank", value: String(format: "%.0f°", abs(roll)), note: roll > 0 ? "Turning right" : "Turning left"))
        }
        if let year = a.yearBuilt {
            let age = Calendar.current.component(.year, from: now) - year
            out.append(Fact(label: "Built", value: String(year), note: age <= 0 ? "Brand new" : "\(age) years old"))
        }
        if let title = a.wakeClass.title {
            let parts = title.split(separator: "(", maxSplits: 1).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " )")) }
            out.append(Fact(label: "Size class", value: parts[0], note: parts.count > 1 ? parts[1] : nil))
        }
        if let max = t.maxAltitudeFt, !a.onGround, t.trail.count > 8 {
            let q = units.altitude(ft: Double(max))
            out.append(Fact(label: "Seen up to", value: q.value, unit: q.unit, note: "Highest while tracked"))
        }
        if a.squawk != nil {
            out.append(Fact(label: "In range", value: clockInterval(now.timeIntervalSince(t.firstSeen)), unit: "min", note: "Since first seen"))
        }
        out.append(Fact(label: "ICAO address", value: a.hex.uppercased(), note: positionSource(a, now: now)))
        return out
    }

    private static func positionSource(_ a: Aircraft, now: Date) -> String {
        let source: String = switch a.sourceType {
        case "mlat": "Multilateration"
        case "adsb_icao", "adsb_icao_nt", "adsb_other", "adsr_icao", "adsr_other": "ADS-B"
        case let s? where s.hasPrefix("tisb"): "TIS-B"
        case "mode_s": "Mode S"
        default: "Transponder"
        }
        let age = max(0, now.timeIntervalSince(a.positionTime))
        return "\(source) · \(age < 10 ? String(format: "%.0f", age) : "10+") s ago"
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
