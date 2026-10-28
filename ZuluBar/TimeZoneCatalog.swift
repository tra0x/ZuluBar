import Foundation

/// A single searchable city/zone choice in the bundled timezone catalog.
struct TimeZoneCatalogEntry: Decodable, Equatable, Identifiable {
    let identifier: String
    let city: String
    let countryCodes: [String]
    let aliases: [String]

    var id: String { identifier }
}

/// Name/search metadata for IANA timezones, generated offline by
/// scripts/generate-timezone-catalog.py and bundled as TimeZoneCatalog.json.
enum TimeZoneCatalog {

    enum LoadError: Error, Equatable {
        case resourceMissing
        case invalidData(String)
    }

    private struct Envelope: Decodable {
        let entries: [TimeZoneCatalogEntry]
    }

    /// Cached result of loading the bundled catalog, computed once at
    /// first access. A missing/corrupt bundled resource is exposed here
    /// explicitly so UI can detect it and disable adding new clocks,
    /// rather than crashing the process; UTC and already-configured
    /// clocks must keep working regardless.
    static let loadResult: Result<[TimeZoneCatalogEntry], LoadError> = load()

    /// Geographic choices available to the picker UI. Filtered by whether
    /// Foundation's `TimeZone` actually accepts the identifier on this OS,
    /// not by `TimeZone.knownTimeZoneIdentifiers` membership (which is known
    /// to omit valid identifiers like `Asia/Kolkata` and `US/Eastern`).
    /// Falls back to an empty catalog on a failed load; see `loadResult`
    /// for the explicit error.
    static var entries: [TimeZoneCatalogEntry] { resolvedEntries(from: loadResult) }

    /// Pure derivation of entries from a load result, independent of the
    /// cached `loadResult`, so the failed-load fallback (`[]`) is testable
    /// without needing to swap out the bundled resource.
    static func resolvedEntries(from result: Result<[TimeZoneCatalogEntry], LoadError>) -> [TimeZoneCatalogEntry] {
        switch result {
        case .success(let entries):
            return entries
        case .failure:
            return []
        }
    }

    static func load(bundle: Bundle = .main) -> Result<[TimeZoneCatalogEntry], LoadError> {
        guard let url = bundle.url(forResource: "TimeZoneCatalog", withExtension: "json") else {
            return .failure(.resourceMissing)
        }
        guard let data = try? Data(contentsOf: url) else {
            return .failure(.invalidData("bundled timezone catalog file is unreadable"))
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return .failure(.invalidData("could not decode JSON envelope"))
        }
        let validated = envelope.entries.filter { TimeZone(identifier: $0.identifier) != nil }
        return .success(validated)
    }

    /// Case/diacritic-insensitive search across city, identifier, country
    /// code/name (both English and the display locale's own name), and
    /// aliases. Exact city/identifier/alias matches sort before partial
    /// matches; ties keep catalog order (stable sort). Empty query returns
    /// every geographic choice.
    static func search(_ query: String) -> [TimeZoneCatalogEntry] {
        search(query, displayLocale: .current)
    }

    /// Same as `search(_:)`, with the locale used for country-name matching
    /// made explicit so behavior with a non-English display locale is
    /// deterministically testable. Production callers should keep using
    /// `search(_:)`, which always uses `Locale.current`.
    static func search(_ query: String, displayLocale: Locale) -> [TimeZoneCatalogEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }

        let normalizedQuery = normalize(trimmed)
        let englishLocale = Locale(identifier: "en_US")

        func matches(_ entry: TimeZoneCatalogEntry) -> Bool {
            if normalize(entry.city).contains(normalizedQuery) { return true }
            if normalize(entry.identifier).contains(normalizedQuery) { return true }
            for alias in entry.aliases where normalize(alias).contains(normalizedQuery) {
                return true
            }
            for code in entry.countryCodes {
                if normalize(code).contains(normalizedQuery) { return true }
                if let name = englishLocale.localizedString(forRegionCode: code), normalize(name).contains(normalizedQuery) {
                    return true
                }
                if let name = displayLocale.localizedString(forRegionCode: code), normalize(name).contains(normalizedQuery) {
                    return true
                }
            }
            return false
        }

        func isExactMatch(_ entry: TimeZoneCatalogEntry) -> Bool {
            if normalize(entry.city) == normalizedQuery { return true }
            if normalize(entry.identifier) == normalizedQuery { return true }
            if entry.aliases.contains(where: { normalize($0) == normalizedQuery }) { return true }
            return false
        }

        // Array.sorted is a stable sort since its Swift 5 introduction, and
        // SE-0372 (Swift 5.8) made that guarantee official, so ties here
        // preserve catalog order instead of needing manual index bookkeeping.
        return entries.filter(matches).sorted { lhs, rhs in
            isExactMatch(lhs) && !isExactMatch(rhs)
        }
    }

    static func entry(for identifier: String) -> TimeZoneCatalogEntry? {
        if let exact = entries.first(where: { $0.identifier == identifier }) { return exact }
        return entries.first(where: { $0.aliases.contains(identifier) })
    }

    /// Falls back to the last path component (underscores replaced by
    /// spaces) when the catalog has no entry for `identifier` — e.g. a
    /// missing/corrupt catalog, or a non-geographic identifier like
    /// `PST8PDT`, which has no path separator and is returned unchanged.
    static func displayName(for identifier: String) -> String {
        guard let entry = entry(for: identifier) else {
            let lastComponent = identifier.split(separator: "/").last.map(String.init) ?? identifier
            return lastComponent.replacingOccurrences(of: "_", with: " ")
        }
        return entry.city
    }

    private static func normalize(_ string: String) -> String {
        string.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
