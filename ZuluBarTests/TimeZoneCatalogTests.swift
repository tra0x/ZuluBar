import XCTest
@testable import ZuluBar

final class TimeZoneCatalogTests: XCTestCase {

    // MARK: - load(bundle:) failure/success paths (resource-independent)
    //
    // These build throwaway flat-file "bundles" on disk so the explicit
    // failure path is testable without crashing the shared `entries` global
    // used by the tests below, which rely on the real generated/bundled
    // TimeZoneCatalog.json (see handoff notes).

    private func makeTempBundleDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testLoadFailsExplicitlyWhenResourceIsMissing() throws {
        let dir = try makeTempBundleDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bundle = Bundle(url: dir)!

        let result = TimeZoneCatalog.load(bundle: bundle)
        switch result {
        case .success:
            XCTFail("Expected resourceMissing failure")
        case .failure(let error):
            XCTAssertEqual(error, .resourceMissing)
        }
    }

    func testLoadFailsExplicitlyWhenResourceIsCorrupt() throws {
        let dir = try makeTempBundleDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("TimeZoneCatalog.json")
        try "not valid json".write(to: fileURL, atomically: true, encoding: .utf8)
        let bundle = Bundle(url: dir)!

        let result = TimeZoneCatalog.load(bundle: bundle)
        switch result {
        case .success:
            XCTFail("Expected invalidData failure")
        case .failure(let error):
            if case .invalidData = error {
                // expected
            } else {
                XCTFail("Expected invalidData, got \(error)")
            }
        }
    }

    func testLoadUnreadableFileErrorDoesNotExposeFilePath() throws {
        // A directory where the catalog file is expected to be forces the
        // "unreadable file" branch (unlike the corrupt-JSON case above, which
        // takes the decode-failure branch) without leaking its absolute path
        // into the user-facing error text.
        let dir = try makeTempBundleDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("TimeZoneCatalog.json")
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
        let bundle = Bundle(url: dir)!

        let result = TimeZoneCatalog.load(bundle: bundle)
        switch result {
        case .success:
            XCTFail("Expected invalidData failure")
        case .failure(let error):
            guard case .invalidData(let message) = error else {
                return XCTFail("Expected invalidData, got \(error)")
            }
            XCTAssertFalse(message.contains(dir.path), "Error text must not contain the bundle's absolute path")
            XCTAssertFalse(message.contains("/"), "Error text must not look like a file path")
        }
    }

    func testLoadSucceedsAndFiltersUnsupportedIdentifiers() throws {
        let dir = try makeTempBundleDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("TimeZoneCatalog.json")
        let json = """
        {
            "generatedNote": "fixture",
            "sourceVersion": "0",
            "sourceURLs": [],
            "entries": [
                {"identifier": "Europe/London", "city": "London", "countryCodes": ["GB"], "aliases": ["Europe/Belfast"]},
                {"identifier": "Not/AZone", "city": "Nowhere", "countryCodes": [], "aliases": []}
            ]
        }
        """
        try json.write(to: fileURL, atomically: true, encoding: .utf8)
        let bundle = Bundle(url: dir)!

        let result = TimeZoneCatalog.load(bundle: bundle)
        switch result {
        case .success(let entries):
            XCTAssertEqual(entries.map { $0.identifier }, ["Europe/London"])
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testResolvedEntriesFromFailedLoadIsEmpty() {
        XCTAssertEqual(TimeZoneCatalog.resolvedEntries(from: .failure(.resourceMissing)), [])
        XCTAssertEqual(TimeZoneCatalog.resolvedEntries(from: .failure(.invalidData("x"))), [])
    }

    func testResolvedEntriesFromSuccessfulLoadPassesThrough() {
        let entry = TimeZoneCatalogEntry(identifier: "Europe/London", city: "London", countryCodes: ["GB"], aliases: [])
        XCTAssertEqual(TimeZoneCatalog.resolvedEntries(from: .success([entry])), [entry])
    }

    func testLoadResultIsCachedAndBacksEntries() {
        // A missing/corrupt bundled resource must never crash this process;
        // loadResult is the explicit, testable signal UI can check instead.
        switch TimeZoneCatalog.loadResult {
        case .success(let loaded):
            XCTAssertEqual(loaded, TimeZoneCatalog.entries)
        case .failure:
            XCTAssertEqual(TimeZoneCatalog.entries, [])
        }
    }

    func testDisplayNameFallbackSurvivesMissingEntryWithUnderscoresAndSlashes() {
        // Simulates what a missing/corrupt catalog would produce for any
        // otherwise-geographic identifier: no crash, and no long raw ID —
        // just the last path component with underscores replaced by spaces.
        let identifier = "Pacific/Not_A_Real_City"
        XCTAssertNil(TimeZoneCatalog.entry(for: identifier))
        XCTAssertEqual(TimeZoneCatalog.displayName(for: identifier), "Not A Real City")
    }

    // MARK: - Catalog content (depends on the real generated + bundled resource)

    func testTorontoAndMontrealAreDistinctCities() {
        guard let toronto = TimeZoneCatalog.entry(for: "America/Toronto") else {
            return XCTFail("Expected America/Toronto in catalog")
        }
        guard let montreal = TimeZoneCatalog.entry(for: "America/Montreal") else {
            return XCTFail("Expected America/Montreal in catalog")
        }
        XCTAssertEqual(toronto.city, "Toronto")
        XCTAssertEqual(montreal.city, "Montreal")
        XCTAssertNotEqual(toronto.city, montreal.city)
    }

    func testCanadaEasternFindsToronto() {
        let results = TimeZoneCatalog.search("Canada/Eastern")
        XCTAssertTrue(results.contains { $0.identifier == "America/Toronto" })
        XCTAssertEqual(TimeZoneCatalog.entry(for: "Canada/Eastern")?.identifier, "America/Toronto")
    }

    func testNoTechnicalUSEasternCityRow() {
        XCTAssertFalse(TimeZoneCatalog.entries.contains { $0.identifier == "US/Eastern" })
    }

    func testCalcuttaFindsKolkata() {
        let results = TimeZoneCatalog.search("Calcutta")
        XCTAssertTrue(results.contains { $0.identifier == "Asia/Kolkata" })
        XCTAssertEqual(TimeZoneCatalog.entry(for: "Asia/Calcutta")?.identifier, "Asia/Kolkata")
    }

    func testKievFindsKyiv() {
        let results = TimeZoneCatalog.search("Kiev")
        XCTAssertTrue(results.contains { $0.identifier == "Europe/Kyiv" })
        XCTAssertEqual(TimeZoneCatalog.entry(for: "Europe/Kiev")?.identifier, "Europe/Kyiv")
    }

    func testTorontoAndNewYorkDoNotCollapse() {
        let toronto = TimeZoneCatalog.entry(for: "America/Toronto")
        let newYork = TimeZoneCatalog.entry(for: "America/New_York")
        XCTAssertNotNil(toronto)
        XCTAssertNotNil(newYork)
        XCTAssertNotEqual(toronto?.identifier, newYork?.identifier)
    }

    func testEmptySearchReturnsAllEntries() {
        XCTAssertEqual(TimeZoneCatalog.search("").count, TimeZoneCatalog.entries.count)
        XCTAssertEqual(TimeZoneCatalog.search("   ").count, TimeZoneCatalog.entries.count)
    }

    func testSearchIsCaseInsensitive() {
        XCTAssertTrue(TimeZoneCatalog.search("toronto").contains { $0.identifier == "America/Toronto" })
        XCTAssertTrue(TimeZoneCatalog.search("TORONTO").contains { $0.identifier == "America/Toronto" })
    }

    func testSearchRanksExactCityMatchBeforePartialMatches() {
        let results = TimeZoneCatalog.search("Paris")
        guard let firstIndex = results.firstIndex(where: { $0.city == "Paris" }) else {
            return XCTFail("Expected an exact 'Paris' city match")
        }
        XCTAssertEqual(firstIndex, 0)
    }

    func testSearchMatchesLocalizedCountryNameInDisplayLocale() {
        let frenchResults = TimeZoneCatalog.search("Allemagne", displayLocale: Locale(identifier: "fr_FR"))
        XCTAssertTrue(frenchResults.contains { $0.countryCodes.contains("DE") })

        let englishResults = TimeZoneCatalog.search("Germany", displayLocale: Locale(identifier: "fr_FR"))
        XCTAssertTrue(englishResults.contains { $0.countryCodes.contains("DE") })
    }

    func testDefaultSearchStillMatchesEnglishCountryName() {
        XCTAssertTrue(TimeZoneCatalog.search("Germany").contains { $0.countryCodes.contains("DE") })
    }

    func testDisplayNameFallsBackToRawIdentifierWhenUnknown() {
        XCTAssertEqual(TimeZoneCatalog.displayName(for: "PST8PDT"), "PST8PDT")
    }

    func testEntriesExcludeInvalidIdentifiers() {
        for entry in TimeZoneCatalog.entries {
            XCTAssertNotNil(TimeZone(identifier: entry.identifier), "\(entry.identifier) should be a valid TimeZone")
        }
    }
}
