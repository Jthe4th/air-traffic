import Foundation

/// Tries the preferred data provider and, if it fails, the other one in the same poll, so a provider outage
/// never leaves a gap. After a failure the backup is used for `retryAfter` before the preferred one is tried again.
public final class FailoverFeed: AircraftFeed, @unchecked Sendable {
    private let primary: any AircraftFeed
    private let secondary: any AircraftFeed
    private let retryAfter: TimeInterval
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var backupUntil: Date?
    private var active: String

    public init(primary: any AircraftFeed, secondary: any AircraftFeed, retryAfter: TimeInterval = 120,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.primary = primary
        self.secondary = secondary
        self.retryAfter = retryAfter
        self.now = now
        self.active = primary.name
    }

    /// The provider that served the last successful request ("adsb.lol (backup)" when on the fallback).
    public var name: String { lock.withLock { active } }

    public func fetch(around center: GeoPoint, radiusNM: Double) async throws -> [Aircraft] {
        let usingBackup = lock.withLock { backupUntil.map { now() < $0 } ?? false }
        var primaryError: Error?

        if !usingBackup {
            do {
                let result = try await primary.fetch(around: center, radiusNM: radiusNM)
                lock.withLock { backupUntil = nil; active = primary.name }
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                primaryError = error
            }
        }

        do {
            let result = try await secondary.fetch(around: center, radiusNM: radiusNM)
            lock.withLock {
                if !usingBackup { backupUntil = now().addingTimeInterval(retryAfter) }
                active = "\(secondary.name) (backup)"
            }
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw primaryError ?? error
        }
    }
}
