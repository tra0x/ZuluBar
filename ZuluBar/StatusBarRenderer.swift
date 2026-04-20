import Foundation

/// Formats for the date prefix displayed before the time in the status bar.
enum DateFormat: String, CaseIterable {
    case dayMonthDate = "Tue Dec 2"
    case dayDateMonth = "Tue 2 Dec"

    var formatString: String {
        switch self {
        case .dayMonthDate: return "E MMM d"
        case .dayDateMonth: return "E d MMM"
        }
    }
}

/// Describes what should be rendered into the status bar title.
struct StatusBarDisplay {
    /// Optional date prefix. When `nil`, no date is shown.
    let dateFormat: DateFormat?
    let timeFormat: UTCTimeFormatter.Format
}

/// Renders a `StatusBarDisplay` into the final status bar title string.
/// Composes `UTCTimeFormatter` for the time half and owns the `DateFormatter`
/// for the date prefix, so callers stay out of formatting details.
enum StatusBarRenderer {

    // Cached DateFormatters — configured once, always UTC/POSIX/Gregorian.
    // DateFormatter is not thread-safe; these are only used from the main thread.
    private static let dayMonthDateFormatter = makeDateFormatter(dateFormat: DateFormat.dayMonthDate.formatString)
    private static let dayDateMonthFormatter = makeDateFormatter(dateFormat: DateFormat.dayDateMonth.formatString)

    private static func makeDateFormatter(dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = dateFormat
        return formatter
    }

    private static func dateFormatter(for format: DateFormat) -> DateFormatter {
        switch format {
        case .dayMonthDate: return dayMonthDateFormatter
        case .dayDateMonth: return dayDateMonthFormatter
        }
    }

    static func render(_ display: StatusBarDisplay, at date: Date = Date()) -> String {
        var result = ""
        if let dateFormat = display.dateFormat {
            result = dateFormatter(for: dateFormat).string(from: date) + " "
        }
        result += UTCTimeFormatter.format(date, as: display.timeFormat)
        return result
    }
}
