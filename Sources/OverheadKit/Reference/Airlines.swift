import Foundation

public struct Airline: Hashable, Sendable {
    public var icao: String
    public var iata: String
    public var name: String
    /// Approximate brand colour, 0xRRGGBB. Used for badges only.
    public var color: UInt32
}

public enum Airlines {
    /// Splits an ICAO-style callsign ("UAL2850", "DAL2479") into airline designator and flight number.
    public static func split(callsign: String?) -> (designator: String, number: String)? {
        guard let c = callsign?.trimmingCharacters(in: .whitespaces).uppercased(), c.count >= 4 else { return nil }
        let prefix = c.prefix(3)
        guard prefix.allSatisfy({ $0.isLetter }) else { return nil }
        let rest = c.dropFirst(3)
        guard let first = rest.first, first.isNumber else { return nil }
        return (String(prefix), String(rest))
    }

    public static func airline(forCallsign callsign: String?) -> Airline? {
        guard let s = split(callsign: callsign) else { return nil }
        return table[s.designator]
    }

    public static func airline(icao: String) -> Airline? { table[icao.uppercased()] }

    /// "UA 2850" when the airline is known, otherwise the raw callsign.
    public static func flightNumber(forCallsign callsign: String?) -> String? {
        guard let c = callsign?.trimmingCharacters(in: .whitespaces), !c.isEmpty else { return nil }
        guard let s = split(callsign: c) else { return c }
        if let a = table[s.designator] { return "\(a.iata) \(s.number)" }
        return "\(s.designator) \(s.number)"
    }

    private static let table: [String: Airline] = {
        var out: [String: Airline] = [:]
        for line in source.split(separator: "\n") {
            let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 4, let color = UInt32(f[3], radix: 16) else { continue }
            out[f[0]] = Airline(icao: f[0], iata: f[1], name: f[2], color: color)
        }
        return out
    }()

    // icao|iata|name|colour
    private static let source = """
    AAL|AA|American Airlines|0078D2
    DAL|DL|Delta Air Lines|C01933
    UAL|UA|United Airlines|1D4F91
    SWA|WN|Southwest Airlines|304CB2
    JBU|B6|JetBlue|0033A0
    ASA|AS|Alaska Airlines|01426A
    NKS|NK|Spirit Airlines|D4B300
    FFT|F9|Frontier Airlines|1B7F4B
    AAY|G4|Allegiant Air|00539F
    HAL|HA|Hawaiian Airlines|6E2C91
    SCX|SY|Sun Country Airlines|E26A1A
    VXP|XP|Avelo Airlines|5A2D82
    BRZ|MX|Breeze Airways|00A19B
    SKW|OO|SkyWest Airlines|1C3F94
    RPA|YX|Republic Airways|0F4C81
    ENY|MQ|Envoy Air|0078D2
    EDV|9E|Endeavor Air|C01933
    JIA|OH|PSA Airlines|0078D2
    PDT|PT|Piedmont Airlines|0078D2
    ASH|YV|Mesa Airlines|CC6A1B
    GJS|G7|GoJet Airlines|1C3F94
    CPZ|CP|Compass Airlines|1C3F94
    QXE|QX|Horizon Air|01426A
    UCA|C5|CommuteAir|1D4F91
    AWI|ZW|Air Wisconsin|1C3F94
    EJA|--|NetJets|8B1A1A
    LXJ|--|Flexjet|2B2B2B
    VJA|--|VistaJet|8B1A1A
    FDX|FX|FedEx Express|4D148C
    UPS|5X|UPS Airlines|5A3A1B
    GTI|5Y|Atlas Air|1C3F94
    ABX|GB|ABX Air|1C3F94
    ATN|8C|Air Transport International|1C3F94
    DHK|D0|DHL Air|D4A900
    CLX|CV|Cargolux|C01933
    CKS|K4|Kalitta Air|1C3F94
    ACA|AC|Air Canada|D4001A
    WJA|WS|WestJet|00A19B
    JZA|QK|Jazz Aviation|D4001A
    POE|PD|Porter Airlines|1C3F94
    AMX|AM|Aeroméxico|0B2265
    VOI|Y4|Volaris|6A2C91
    VIV|VB|Viva Aerobus|2B9E3E
    CMP|CM|Copa Airlines|0073C6
    AVA|AV|Avianca|C01933
    LAN|LA|LATAM Airlines|1B2A6B
    TAM|JJ|LATAM Brasil|1B2A6B
    GLO|G3|GOL|E26A1A
    AZU|AD|Azul|0A4D9E
    BAW|BA|British Airways|075AAA
    VIR|VS|Virgin Atlantic|C8102E
    EZY|U2|easyJet|E26A1A
    RYR|FR|Ryanair|073590
    DLH|LH|Lufthansa|05164D
    EWG|EW|Eurowings|8B1A7A
    CFG|DE|Condor|C79A00
    AFR|AF|Air France|002157
    KLM|KL|KLM|00A1DE
    SAS|SK|SAS|1C3F94
    IBE|IB|Iberia|D7192D
    VLG|VY|Vueling|D4A900
    TAP|TP|TAP Air Portugal|00844A
    SWR|LX|SWISS|D4001A
    AUA|OS|Austrian|C01933
    BEL|SN|Brussels Airlines|1C3F94
    FIN|AY|Finnair|0B1560
    ICE|FI|Icelandair|1C3F94
    EIN|EI|Aer Lingus|008C5F
    THY|TK|Turkish Airlines|C70A0C
    AEE|A3|Aegean Airlines|1C3F94
    LOT|LO|LOT Polish Airlines|1C3F94
    WZZ|W6|Wizz Air|C6007E
    NAX|DY|Norwegian|D81939
    UAE|EK|Emirates|D71921
    QTR|QR|Qatar Airways|5C0632
    ETD|EY|Etihad Airways|9C7A1B
    SVA|SV|Saudia|1B6B3A
    ELY|LY|El Al|1C3F94
    MSR|MS|EgyptAir|1C3F94
    ETH|ET|Ethiopian Airlines|1B7F4B
    SAA|SA|South African Airways|1C3F94
    KAL|KE|Korean Air|00256C
    AAR|OZ|Asiana Airlines|C01933
    JAL|JL|Japan Airlines|C8102E
    ANA|NH|All Nippon Airways|13448F
    CPA|CX|Cathay Pacific|005D63
    SIA|SQ|Singapore Airlines|00266B
    THA|TG|Thai Airways|5A2D82
    MAS|MH|Malaysia Airlines|C8102E
    EVA|BR|EVA Air|00844A
    CAL|CI|China Airlines|C01933
    CCA|CA|Air China|C8102E
    CES|MU|China Eastern|1C3F94
    CSN|CZ|China Southern|1C6FB5
    HVN|VN|Vietnam Airlines|1C3F94
    PAL|PR|Philippine Airlines|1C3F94
    GIA|GA|Garuda Indonesia|1C6FB5
    AIC|AI|Air India|C8102E
    QFA|QF|Qantas|E0001B
    ANZ|NZ|Air New Zealand|1C1C1C
    VOZ|VA|Virgin Australia|E0001B
    """
}
