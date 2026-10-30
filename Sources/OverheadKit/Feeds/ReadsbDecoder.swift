import Foundation

/// Decodes readsb-style JSON. One bad aircraft record never sinks the whole response.
public enum ReadsbDecoder {
    public static func decode(_ data: Data, fallbackNow: Date) throws -> [Aircraft] {
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) } catch { throw FeedError.malformed }

        let feedTime = response.now.map(normalizeEpoch) ?? fallbackNow
        let records = (response.aircraft ?? response.ac ?? []).compactMap(\.value)
        return records.compactMap { $0.aircraft(feedTime: feedTime) }
    }

    private static func normalizeEpoch(_ v: Double) -> Date {
        Date(timeIntervalSince1970: v > 1e11 ? v / 1000 : v)
    }

    struct Response: Decodable {
        var now: Double?
        var aircraft: [Lossy<Record>]?
        var ac: [Lossy<Record>]?
    }

    struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    enum AltBaro: Decodable {
        case feet(Double), ground
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) { self = .feet(d); return }
            if let s = try? c.decode(String.self), s.lowercased() == "ground" { self = .ground; return }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "alt_baro")
        }
    }

    struct FlexInt: Decodable {
        let value: Int?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let i = try? c.decode(Int.self) { value = i }
            else if let s = try? c.decode(String.self) { value = Int(s) }
            else { value = nil }
        }
    }

    struct Record: Decodable {
        var hex: String
        var type: String?
        var flight: String?
        var r: String?
        var t: String?
        var desc: String?
        var ownOp: String?
        var year: FlexInt?
        var alt_baro: AltBaro?
        var alt_geom: Double?
        var gs: Double?
        var track: Double?
        var baro_rate: Double?
        var geom_rate: Double?
        var squawk: String?
        var emergency: String?
        var category: String?
        var lat: Double?
        var lon: Double?
        var seen_pos: Double?
        var mach: Double?
        var ias: Double?
        var tas: Double?
        var true_heading: Double?
        var mag_heading: Double?
        var roll: Double?
        var nav_altitude_mcp: Double?
        var nav_altitude_fms: Double?
        var nav_heading: Double?
        var nav_modes: [String]?
        var wd: Double?
        var ws: Double?
        var oat: Double?
        var dbFlags: Int?

        func aircraft(feedTime: Date) -> Aircraft? {
            guard let lat, let lon else { return nil }
            let position = GeoPoint(latitude: lat, longitude: lon)
            guard position.isValid else { return nil }
            let age = seen_pos ?? 0
            guard age < 90 else { return nil }

            var ground = false
            var baro: Int?
            switch alt_baro {
            case .ground?: ground = true
            case .feet(let ft)?: baro = Int(ft.rounded())
            case nil: break
            }

            func clean(_ s: String?) -> String? {
                guard let t = s?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
                return t
            }

            return Aircraft(
                hex: hex.lowercased(),
                callsign: clean(flight),
                registration: clean(r),
                typeCode: clean(t),
                typeDescription: clean(desc),
                operatorName: clean(ownOp),
                yearBuilt: year?.value,
                position: position,
                positionTime: feedTime.addingTimeInterval(-age),
                onGround: ground,
                barometricAltitudeFt: baro,
                geometricAltitudeFt: alt_geom.map { Int($0.rounded()) },
                groundSpeedKt: gs,
                trackDeg: track,
                verticalRateFpm: (baro_rate ?? geom_rate).map { Int($0.rounded()) },
                squawk: clean(squawk),
                emergency: emergency == "none" ? nil : clean(emergency),
                wakeClass: WakeClass(category: category),
                flags: DatabaseFlags(rawValue: dbFlags ?? 0),
                mach: mach,
                indicatedAirspeedKt: ias,
                trueAirspeedKt: tas,
                trueHeadingDeg: true_heading,
                magneticHeadingDeg: mag_heading,
                rollDeg: roll,
                selectedAltitudeFt: (nav_altitude_mcp ?? nav_altitude_fms).map { Int($0.rounded()) },
                selectedHeadingDeg: nav_heading,
                autopilotModes: nav_modes ?? [],
                windDirectionDeg: wd,
                windSpeedKt: ws,
                outsideAirTempC: oat,
                sourceType: type
            )
        }
    }
}
