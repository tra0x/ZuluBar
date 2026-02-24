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

    /// Formats a date as UTC time in the specified format
    /// - Parameters:
    ///   - date: The date to format (defaults to current date)
    ///   - format: The desired output format
    /// - Returns: Formatted time string
    static func format(_ date: Date = Date(), as format: Format) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)

        switch format {
        case .humanReadable(let showSeconds, let suffix):
            let timeFormat = showSeconds ? "HH:mm:ss" : "HH:mm"
            formatter.dateFormat = timeFormat
            return formatter.string(from: date) + suffix.stringValue

        case .iso8601:
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            return formatter.string(from: date)

        case .unixTimestamp:
            return String(Int(date.timeIntervalSince1970))

        case .rfc3339:
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
            return formatter.string(from: date)
        }
    }
}
