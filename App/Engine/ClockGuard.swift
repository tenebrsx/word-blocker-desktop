import Foundation

/// Tamper resistance for the days-strong counter.
///
/// - Rollback: if the device clock goes backwards more than an hour from the
///   last trusted time, the last trusted time is used instead (the counter
///   doesn't drop or reset because of a clock change).
/// - Server check: when online, an HTTPS `Date` header gives a trusted
///   offset. If the device clock was pushed forward, the offset pulls "now"
///   back and the inflated last-trusted time is corrected.
struct ClockGuard: Codable, Equatable {
    static let rollbackTolerance: TimeInterval = 3600
    /// Offsets smaller than this are treated as normal clock drift.
    static let driftTolerance: TimeInterval = 300

    var lastTrusted: Date
    /// server time - device time, from the last successful check (nil = none).
    var serverOffset: TimeInterval?
    var rollbackDetected = false

    init(lastTrusted: Date, serverOffset: TimeInterval? = nil) {
        self.lastTrusted = lastTrusted
        self.serverOffset = serverOffset
    }

    /// Trusted "now" for the given device time. Updates the state.
    mutating func trustedNow(system: Date) -> Date {
        var now = system
        if let offset = serverOffset, abs(offset) > Self.driftTolerance {
            now = system.addingTimeInterval(offset)
        }
        if now < lastTrusted.addingTimeInterval(-Self.rollbackTolerance) {
            rollbackDetected = true
            return lastTrusted
        }
        rollbackDetected = false
        if now > lastTrusted { lastTrusted = now }
        return now
    }

    /// Records an HTTPS Date header reading taken at device time `system`.
    mutating func applyServerTime(_ server: Date, system: Date) {
        let offset = server.timeIntervalSince(system)
        serverOffset = abs(offset) > Self.driftTolerance ? offset : nil
        // A forward-tampered clock may have pushed lastTrusted into the future.
        if lastTrusted > server.addingTimeInterval(Self.rollbackTolerance) {
            lastTrusted = server
        }
        rollbackDetected = false
    }

    /// Parses an HTTP `Date` header (RFC 7231 IMF-fixdate).
    static func parseHTTPDate(_ value: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.date(from: value)
    }

    /// Whole calendar days from `start` to `now` (never negative).
    static func days(from start: Date, to now: Date, calendar: Calendar = .current) -> Int {
        let d = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: now)).day ?? 0
        return max(0, d)
    }
}
