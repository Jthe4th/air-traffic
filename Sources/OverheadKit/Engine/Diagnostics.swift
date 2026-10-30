import Foundation

/// A running tally of how the data connection is doing, shown in Settings.
public struct Diagnostics: Equatable, Sendable {
    public var startedAt = Date()
    public var lastSuccess: Date?
    public var lastFailure: Date?
    public var lastError: String?
    public var successes = 0
    public var failures = 0
    public var lastLatencyMs: Int?
    public var lastAircraftCount: Int?
    public var lastRadiusNM: Double?

    public init() {}

    mutating func recordSuccess(at date: Date, latency: TimeInterval, count: Int, radiusNM: Double) {
        lastSuccess = date
        successes += 1
        lastLatencyMs = Int((latency * 1000).rounded())
        lastAircraftCount = count
        lastRadiusNM = radiusNM
    }

    mutating func recordFailure(at date: Date, message: String) {
        lastFailure = date
        failures += 1
        lastError = message
    }
}
