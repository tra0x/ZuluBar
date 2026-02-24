import Foundation

/// Handles formatting of UTC time in various formats
struct UTCTimeFormatter {

    // MARK: - Types

    /// Available formats for time output
    enum Format {
        case humanReadable(showSeconds: Bool, suffix: Suffix)
        case iso8601
        case unixTimestamp
        case rfc3339
    }

    /// Available suffixes for human-readable format
    enum Suffix {
        case utc
        case z
        case none

        var stringValue: String {
            switch self {
            case .utc: return " UTC"
            case .z: return "Z"
            case .none: return ""
            }
        }
    }

    // MARK: - Formatting Methods
    private static let utcTimeZone = TimeZone(abbreviation: "UTC") ?? TimeZone(secondsFromGMT: 0)!
    private static let posixLocale = Locale(identifier: "en_US_POSIX")
    private static let gregorianCalendar = Calendar(identifier: .gregorian)

    private static func makeDateFormatter(dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.timeZone = utcTimeZone
        formatter.locale = posixLocale
        formatter.calendar = gregorianCalendar
        formatter.dateFormat = dateFormat
        return formatter
    }

    private static let humanReadableFormatterSeconds = makeDateFormatter(dateFormat: "HH:mm:ss")
    private static let humanReadableFormatterNoSeconds = makeDateFormatter(dateFormat: "HH:mm")
    private static let rfc3339Formatter = makeDateFormatter(dateFormat: "yyyy-MM-dd'T'HH:mm:ssZZZZZ")
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = utcTimeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Formats a date as UTC time in the specified format
    /// - Parameters:
    ///   - date: The date to format (defaults to current date)
    ///   - format: The desired output format
    /// - Returns: Formatted time string
    static func format(_ date: Date = Date(), as format: Format) -> String {
        switch format {
        case .humanReadable(let showSeconds, let suffix):
            let formatter = showSeconds ? humanReadableFormatterSeconds : humanReadableFormatterNoSeconds
            return formatter.string(from: date) + suffix.stringValue

        case .iso8601:
            return iso8601Formatter.string(from: date)

        case .unixTimestamp:
            return String(Int(date.timeIntervalSince1970))

        case .rfc3339:
            return rfc3339Formatter.string(from: date)
        }
    }
}
