import Foundation

public enum AircraftKind: String, Sendable {
    case narrowBody = "Narrow-body jet"
    case wideBody = "Wide-body jet"
    case regionalJet = "Regional jet"
    case turboprop = "Turboprop"
    case businessJet = "Business jet"
    case lightPiston = "Light aircraft"
    case helicopter = "Helicopter"
    case military = "Military"
    case spacecraft = "Space station"
    case other = "Aircraft"

    public enum Silhouette: Sendable { case jet, prop, helicopter, station }

    public var silhouette: Silhouette {
        switch self {
        case .spacecraft: .station
        case .helicopter: .helicopter
        case .turboprop, .lightPiston: .prop
        default: .jet
        }
    }
}

public struct AircraftTypeInfo: Sendable, Hashable {
    public var code: String
    public var name: String
    public var kind: AircraftKind
}

/// Friendly names for common ICAO type designators. Anything missing falls back to the feed's own description.
public enum AircraftTypes {
    public static func info(for code: String?) -> AircraftTypeInfo? {
        guard let code = code?.uppercased(), !code.isEmpty else { return nil }
        return table[code]
    }

    public static func silhouette(for aircraft: Aircraft) -> AircraftKind.Silhouette {
        if let kind = info(for: aircraft.typeCode)?.kind { return kind.silhouette }
        switch aircraft.wakeClass {
        case .rotorcraft: return .helicopter
        case .light, .glider, .ultralight, .lighterThanAir: return .prop
        default: return .jet
        }
    }

    private static let table: [String: AircraftTypeInfo] = {
        var out: [String: AircraftTypeInfo] = [:]
        for line in source.split(separator: "\n") {
            let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 3, let kind = kinds[f[2]] else { continue }
            out[f[0]] = AircraftTypeInfo(code: f[0], name: f[1], kind: kind)
        }
        return out
    }()

    private static let kinds: [String: AircraftKind] = [
        "nb": .narrowBody, "wb": .wideBody, "rj": .regionalJet, "tp": .turboprop,
        "bj": .businessJet, "lp": .lightPiston, "he": .helicopter, "mil": .military, "sc": .spacecraft,
    ]

    // code|name|kind
    private static let source = """
    ISS|International Space Station|sc
    A318|Airbus A318|nb
    A319|Airbus A319|nb
    A320|Airbus A320|nb
    A321|Airbus A321|nb
    A19N|Airbus A319neo|nb
    A20N|Airbus A320neo|nb
    A21N|Airbus A321neo|nb
    BCS1|Airbus A220-100|nb
    BCS3|Airbus A220-300|nb
    A306|Airbus A300-600|wb
    A310|Airbus A310|wb
    A332|Airbus A330-200|wb
    A333|Airbus A330-300|wb
    A338|Airbus A330-800neo|wb
    A339|Airbus A330-900neo|wb
    A342|Airbus A340-200|wb
    A343|Airbus A340-300|wb
    A345|Airbus A340-500|wb
    A346|Airbus A340-600|wb
    A359|Airbus A350-900|wb
    A35K|Airbus A350-1000|wb
    A388|Airbus A380-800|wb
    A3ST|Airbus Beluga|wb
    B712|Boeing 717-200|nb
    B722|Boeing 727-200|nb
    B732|Boeing 737-200|nb
    B733|Boeing 737-300|nb
    B734|Boeing 737-400|nb
    B735|Boeing 737-500|nb
    B736|Boeing 737-600|nb
    B737|Boeing 737-700|nb
    B738|Boeing 737-800|nb
    B739|Boeing 737-900|nb
    B37M|Boeing 737 MAX 7|nb
    B38M|Boeing 737 MAX 8|nb
    B39M|Boeing 737 MAX 9|nb
    B3XM|Boeing 737 MAX 10|nb
    B741|Boeing 747-100|wb
    B742|Boeing 747-200|wb
    B743|Boeing 747-300|wb
    B744|Boeing 747-400|wb
    B748|Boeing 747-8|wb
    B752|Boeing 757-200|nb
    B753|Boeing 757-300|nb
    B762|Boeing 767-200|wb
    B763|Boeing 767-300|wb
    B764|Boeing 767-400|wb
    B772|Boeing 777-200|wb
    B77L|Boeing 777-200LR|wb
    B773|Boeing 777-300|wb
    B77W|Boeing 777-300ER|wb
    B778|Boeing 777-8|wb
    B779|Boeing 777-9|wb
    B788|Boeing 787-8 Dreamliner|wb
    B789|Boeing 787-9 Dreamliner|wb
    B78X|Boeing 787-10 Dreamliner|wb
    DC10|McDonnell Douglas DC-10|wb
    MD11|McDonnell Douglas MD-11|wb
    MD82|McDonnell Douglas MD-82|nb
    MD83|McDonnell Douglas MD-83|nb
    MD88|McDonnell Douglas MD-88|nb
    MD90|McDonnell Douglas MD-90|nb
    E135|Embraer ERJ-135|rj
    E145|Embraer ERJ-145|rj
    E170|Embraer 170|rj
    E75S|Embraer 175|rj
    E75L|Embraer 175 (long wing)|rj
    E190|Embraer 190|rj
    E195|Embraer 195|rj
    E290|Embraer 190-E2|rj
    E295|Embraer 195-E2|rj
    CRJ1|Bombardier CRJ-100|rj
    CRJ2|Bombardier CRJ-200|rj
    CRJ7|Bombardier CRJ-700|rj
    CRJ9|Bombardier CRJ-900|rj
    CRJX|Bombardier CRJ-1000|rj
    DH8A|De Havilland Dash 8-100|tp
    DH8B|De Havilland Dash 8-200|tp
    DH8C|De Havilland Dash 8-300|tp
    DH8D|De Havilland Dash 8-400|tp
    AT42|ATR 42|tp
    AT45|ATR 42-500|tp
    AT72|ATR 72|tp
    AT75|ATR 72-500|tp
    AT76|ATR 72-600|tp
    SF34|Saab 340|tp
    SB20|Saab 2000|tp
    B190|Beechcraft 1900|tp
    JS32|BAe Jetstream 32|tp
    JS41|BAe Jetstream 41|tp
    SW4|Fairchild Metroliner|tp
    BE20|Beechcraft King Air 200|tp
    BE9L|Beechcraft King Air 90|tp
    BE30|Beechcraft King Air 300|tp
    B350|Beechcraft King Air 350|tp
    PC12|Pilatus PC-12|tp
    TBM7|Daher TBM 700|tp
    TBM8|Daher TBM 850|tp
    TBM9|Daher TBM 900|tp
    C208|Cessna 208 Caravan|tp
    GLF4|Gulfstream IV|bj
    GLF5|Gulfstream V|bj
    GLF6|Gulfstream G650|bj
    GLEX|Bombardier Global Express|bj
    GL5T|Bombardier Global 5000|bj
    GL7T|Bombardier Global 7500|bj
    CL30|Bombardier Challenger 300|bj
    CL35|Bombardier Challenger 350|bj
    CL60|Bombardier Challenger 600|bj
    C25A|Cessna Citation CJ2|bj
    C25B|Cessna Citation CJ3|bj
    C25C|Cessna Citation CJ4|bj
    C510|Cessna Citation Mustang|bj
    C525|Cessna CitationJet|bj
    C550|Cessna Citation II|bj
    C560|Cessna Citation V|bj
    C56X|Cessna Citation Excel|bj
    C680|Cessna Citation Sovereign|bj
    C68A|Cessna Citation Latitude|bj
    C700|Cessna Citation Longitude|bj
    C750|Cessna Citation X|bj
    LJ35|Learjet 35|bj
    LJ45|Learjet 45|bj
    LJ60|Learjet 60|bj
    LJ75|Learjet 75|bj
    FA7X|Dassault Falcon 7X|bj
    FA8X|Dassault Falcon 8X|bj
    F2TH|Dassault Falcon 2000|bj
    F900|Dassault Falcon 900|bj
    H25B|Hawker 800|bj
    HDJT|Honda HondaJet|bj
    E55P|Embraer Phenom 300|bj
    E50P|Embraer Phenom 100|bj
    BE40|Beechcraft Beechjet 400|bj
    EA50|Eclipse 500|bj
    SF50|Cirrus Vision Jet|bj
    PC24|Pilatus PC-24|bj
    C150|Cessna 150|lp
    C152|Cessna 152|lp
    C172|Cessna 172 Skyhawk|lp
    C177|Cessna 177 Cardinal|lp
    C182|Cessna 182 Skylane|lp
    C206|Cessna 206 Stationair|lp
    C210|Cessna 210 Centurion|lp
    C310|Cessna 310|lp
    C340|Cessna 340|lp
    C414|Cessna 414 Chancellor|lp
    C421|Cessna 421 Golden Eagle|lp
    PA18|Piper Super Cub|lp
    PA28|Piper Cherokee|lp
    P28A|Piper Cherokee Warrior|lp
    P28R|Piper Cherokee Arrow|lp
    PA32|Piper Cherokee Six|lp
    PA34|Piper Seneca|lp
    PA44|Piper Seminole|lp
    PA46|Piper Malibu|lp
    P46T|Piper Malibu Meridian|tp
    SR20|Cirrus SR20|lp
    SR22|Cirrus SR22|lp
    DA40|Diamond DA40|lp
    DA42|Diamond DA42 Twin Star|lp
    DA62|Diamond DA62|lp
    BE33|Beechcraft Bonanza 33|lp
    BE35|Beechcraft Bonanza|lp
    BE36|Beechcraft Bonanza 36|lp
    BE55|Beechcraft Baron 55|lp
    BE58|Beechcraft Baron 58|lp
    M20P|Mooney M20|lp
    M20T|Mooney M20 Turbo|lp
    AA5|Grumman Tiger|lp
    R22|Robinson R22|he
    R44|Robinson R44|he
    R66|Robinson R66|he
    B06|Bell 206 JetRanger|he
    B407|Bell 407|he
    B412|Bell 412|he
    B429|Bell 429|he
    B505|Bell 505|he
    EC20|Airbus H120|he
    EC30|Airbus H130|he
    EC35|Airbus H135|he
    EC45|Airbus H145|he
    EC55|Airbus H155|he
    AS50|Airbus AS350 Écureuil|he
    AS55|Airbus AS355|he
    A109|Agusta A109|he
    A139|Leonardo AW139|he
    S76|Sikorsky S-76|he
    S92|Sikorsky S-92|he
    H60|Sikorsky UH-60 Black Hawk|he
    H64|Boeing AH-64 Apache|he
    B212|Bell 212|he
    C130|Lockheed C-130 Hercules|mil
    C30J|Lockheed C-130J Super Hercules|mil
    C17|Boeing C-17 Globemaster III|mil
    C5M|Lockheed C-5M Super Galaxy|mil
    K35R|Boeing KC-135 Stratotanker|mil
    KC10|McDonnell Douglas KC-10 Extender|mil
    K46|Boeing KC-46 Pegasus|mil
    B52|Boeing B-52 Stratofortress|mil
    F15|McDonnell Douglas F-15 Eagle|mil
    F16|General Dynamics F-16 Fighting Falcon|mil
    F18|McDonnell Douglas F/A-18 Hornet|mil
    F18S|Boeing F/A-18E/F Super Hornet|mil
    F22|Lockheed Martin F-22 Raptor|mil
    F35|Lockheed Martin F-35 Lightning II|mil
    A10|Fairchild A-10 Thunderbolt II|mil
    E3TF|Boeing E-3 Sentry (AWACS)|mil
    E6|Boeing E-6 Mercury|mil
    P8|Boeing P-8 Poseidon|mil
    V22|Bell Boeing V-22 Osprey|mil
    T38|Northrop T-38 Talon|mil
    T6|Beechcraft T-6 Texan II|mil
    U2|Lockheed U-2|mil
    """
}
