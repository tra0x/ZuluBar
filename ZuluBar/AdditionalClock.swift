import Foundation

/// A user-chosen, opt-in city clock shown alongside the mandatory UTC clock.
struct AdditionalClock: Codable, Equatable, Identifiable {
    /// The geographic IANA identifier the user picked, e.g. "America/Montreal".
    /// Preserved exactly as selected — never normalized to a linked city.
    let identifier: String
    var label: String?

    init(identifier: String, label: String? = nil) {
        self.identifier = identifier
        self.label = label
    }

    var id: String { identifier }

    /// Presentation only — labels never act as a timezone selector.
    /// Falls back to the catalog's city name (or the raw identifier if the
    /// catalog doesn't know it) when no usable label is set.
    var displayName: String {
        let maxLabelLength = 40
        if let label {
            let singleLine = label.components(separatedBy: .newlines).joined(separator: " ")
            let trimmed = singleLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed.count > maxLabelLength ? String(trimmed.prefix(maxLabelLength)) : trimmed
            }
        }
        return TimeZoneCatalog.displayName(for: identifier)
    }

    var timeZone: TimeZone? {
        TimeZone(identifier: identifier)
    }
}
