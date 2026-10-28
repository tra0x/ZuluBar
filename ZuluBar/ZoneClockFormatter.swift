import Foundation

/// The two display lines for one additional clock: short city label, then
/// weekday + time.
struct ZoneClockFace: Equatable {
    let label: String
    let time: String
}

/// Formats `AdditionalClock`s for display and clipboard copy. Never touches
/// `UTCTimeFormatter` or its UTC semantics.
enum ZoneClockFormatter {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")
    private static let gregorianCalendar = Calendar(identifier: .gregorian)

    // Cached per (timezone identifier, showSeconds) so formatters aren't
    // rebuilt every timer tick.
    private static var weekdayTimeFormatterCache: [String: DateFormatter] = [:]
    private static var rfc3339FormatterCache: [String: ISO8601DateFormatter] = [:]

    private static func weekdayTimeFormatter(for timeZone: TimeZone, showSeconds: Bool) -> DateFormatter {
        let key = "\(timeZone.identifier)|\(showSeconds)"
        if let cached = weekdayTimeFormatterCache[key] { return cached }
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = posixLocale
        formatter.calendar = gregorianCalendar
        formatter.dateFormat = showSeconds ? "E HH:mm:ss" : "E HH:mm"
        weekdayTimeFormatterCache[key] = formatter
        return formatter
    }

    private static func rfc3339Formatter(for timeZone: TimeZone) -> ISO8601DateFormatter {
        let key = timeZone.identifier
        if let cached = rfc3339FormatterCache[key] { return cached }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        rfc3339FormatterCache[key] = formatter
        return formatter
    }

    private static func offsetString(for timeZone: TimeZone, at date: Date) -> String {
        let totalSeconds = timeZone.secondsFromGMT(for: date)
        let sign = totalSeconds < 0 ? "-" : "+"
        let absSeconds = abs(totalSeconds)
        let hours = absSeconds / 3600
        let minutes = (absSeconds % 3600) / 60
        return String(format: "UTC%@%02d:%02d", sign, hours, minutes)
    }

    static func face(for clock: AdditionalClock, at date: Date, showSeconds: Bool) -> ZoneClockFace? {
        guard let timeZone = clock.timeZone else { return nil }
        let time = weekdayTimeFormatter(for: timeZone, showSeconds: showSeconds).string(from: date)
        return ZoneClockFace(label: clock.displayName, time: time)
    }

    /// Readable copy always spells out "UTC±HH:MM" — never a Z/UTC suffix
    /// standing in for a nonzero-offset local time. RFC3339 may use Z only
    /// when this zone's offset at `date` is actually zero.
    static func copy(for clock: AdditionalClock, at date: Date, format: CopyFormat, showSeconds: Bool) -> String? {
        guard let timeZone = clock.timeZone else { return nil }
        switch format {
        case .display:
            let time = weekdayTimeFormatter(for: timeZone, showSeconds: showSeconds).string(from: date)
            return "\(clock.displayName) \(time) \(offsetString(for: timeZone, at: date))"
        case .unixTimestamp:
            return String(Int(date.timeIntervalSince1970))
        case .rfc3339:
            return rfc3339Formatter(for: timeZone).string(from: date)
        }
    }
}
