import XCTest
@testable import ZuluBar

final class AdditionalClockTests: XCTestCase {

    // MARK: - AdditionalClock struct

    func testIdEqualsIdentifier() {
        let clock = AdditionalClock(identifier: "America/Toronto")
        XCTAssertEqual(clock.id, "America/Toronto")
    }

    func testLabelDefaultsToNil() {
        let clock = AdditionalClock(identifier: "America/Toronto")
        XCTAssertNil(clock.label)
    }

    func testDisplayNameUsesTrimmedLabelWhenPresent() {
        let clock = AdditionalClock(identifier: "America/Toronto", label: "  Home  ")
        XCTAssertEqual(clock.displayName, "Home")
    }

    func testDisplayNameFallsBackToIdentifierWhenUnknownToCatalog() {
        // PST8PDT is a valid Foundation TimeZone identifier but not a
        // geographic city, so it is deliberately absent from the catalog.
        let clock = AdditionalClock(identifier: "PST8PDT")
        XCTAssertEqual(clock.displayName, "PST8PDT")
    }

    func testDisplayNameTreatsWhitespaceOnlyLabelAsAbsent() {
        let clock = AdditionalClock(identifier: "PST8PDT", label: "   ")
        XCTAssertEqual(clock.displayName, "PST8PDT")
    }

    func testDisplayNameCollapsesMultilineLabelToSingleLine() {
        let clock = AdditionalClock(identifier: "America/Toronto", label: "Line1\nLine2")
        XCTAssertFalse(clock.displayName.contains("\n"))
        XCTAssertEqual(clock.displayName, "Line1 Line2")
    }

    func testDisplayNameBoundsVeryLongLabel() {
        let longLabel = String(repeating: "x", count: 500)
        let clock = AdditionalClock(identifier: "America/Toronto", label: longLabel)
        XCTAssertLessThan(clock.displayName.count, 500)
    }

    func testTimeZoneResolvesForValidIdentifier() {
        let clock = AdditionalClock(identifier: "America/Toronto")
        XCTAssertEqual(clock.timeZone?.identifier, "America/Toronto")
    }

    func testTimeZoneIsNilForInvalidIdentifier() {
        let clock = AdditionalClock(identifier: "Not/AZone")
        XCTAssertNil(clock.timeZone)
    }

    func testPreservesSelectedIdentifierWithoutNormalizing() {
        // Montreal must not be silently collapsed into its link target.
        let clock = AdditionalClock(identifier: "America/Montreal")
        XCTAssertEqual(clock.identifier, "America/Montreal")
        XCTAssertNotEqual(clock.identifier, "America/Toronto")
    }

    @MainActor
    func testCodableRoundTrip() throws {
        let clock = AdditionalClock(identifier: "Europe/Paris", label: "Office")
        let data = try JSONEncoder().encode(clock)
        let decoded = try JSONDecoder().decode(AdditionalClock.self, from: data)
        XCTAssertEqual(decoded, clock)
    }

    // MARK: - Settings.additionalClocks persistence

    private var suiteName: String!
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.zulubar.tests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testAdditionalClocksDefaultIsEmpty() {
        let settings = Settings(defaults: testDefaults)
        XCTAssertEqual(settings.additionalClocks, [])
    }

    func testAdditionalClocksRoundTripPreservesOrder() {
        var settings = Settings(defaults: testDefaults)
        let clocks = [
            AdditionalClock(identifier: "America/Toronto"),
            AdditionalClock(identifier: "America/Montreal", label: "Cousin"),
            AdditionalClock(identifier: "Asia/Kathmandu"),
        ]
        settings.additionalClocks = clocks
        XCTAssertEqual(settings.additionalClocks, clocks)
    }

    func testReadingDoesNotMutateDefaults() {
        var settings = Settings(defaults: testDefaults)
        settings.additionalClocks = [AdditionalClock(identifier: "America/Toronto")]
        let before = testDefaults.data(forKey: "additionalClocks.v1")
        _ = settings.additionalClocks
        let after = testDefaults.data(forKey: "additionalClocks.v1")
        XCTAssertEqual(before, after)
    }

    func testDuplicateIdentifiersKeepFirstOccurrenceAndOrder() {
        let json = """
        [
            {"identifier": "America/Toronto", "label": "First"},
            {"identifier": "Asia/Kathmandu"},
            {"identifier": "America/Toronto", "label": "Second"}
        ]
        """
        testDefaults.set(json.data(using: .utf8), forKey: "additionalClocks.v1")
        let settings = Settings(defaults: testDefaults)
        let result = settings.additionalClocks
        XCTAssertEqual(result.map { $0.identifier }, ["America/Toronto", "Asia/Kathmandu"])
        XCTAssertEqual(result.first?.label, "First")
    }

    func testInvalidIdentifierEntryIsSkippedWithoutDiscardingValidOnes() {
        let json = """
        [
            {"identifier": "America/Toronto"},
            {"identifier": "Not/AZone"},
            {"identifier": "Asia/Kathmandu"}
        ]
        """
        testDefaults.set(json.data(using: .utf8), forKey: "additionalClocks.v1")
        let settings = Settings(defaults: testDefaults)
        XCTAssertEqual(settings.additionalClocks.map { $0.identifier }, ["America/Toronto", "Asia/Kathmandu"])
    }

    func testMalformedEntryIsSkippedWithoutDiscardingValidOnes() {
        let json = """
        [
            {"identifier": "America/Toronto"},
            {"notIdentifier": "oops"},
            {"identifier": "Asia/Kathmandu"}
        ]
        """
        testDefaults.set(json.data(using: .utf8), forKey: "additionalClocks.v1")
        let settings = Settings(defaults: testDefaults)
        XCTAssertEqual(settings.additionalClocks.map { $0.identifier }, ["America/Toronto", "Asia/Kathmandu"])
    }

    func testCorruptTopLevelDataSafelyReadsAsEmpty() {
        testDefaults.set("not json at all".data(using: .utf8), forKey: "additionalClocks.v1")
        let settings = Settings(defaults: testDefaults)
        XCTAssertEqual(settings.additionalClocks, [])
    }

    func testNonArrayTopLevelDataSafelyReadsAsEmpty() {
        let json = #"{"identifier": "America/Toronto"}"#
        testDefaults.set(json.data(using: .utf8), forKey: "additionalClocks.v1")
        let settings = Settings(defaults: testDefaults)
        XCTAssertEqual(settings.additionalClocks, [])
    }

    func testUTCAliasIdentifiersAreDisallowed() {
        let json = """
        [
            {"identifier": "UTC"},
            {"identifier": "Etc/UTC"},
            {"identifier": "Zulu"},
            {"identifier": "Etc/Zulu"},
            {"identifier": "Universal"},
            {"identifier": "UCT"},
            {"identifier": "GMT"},
            {"identifier": "America/Toronto"}
        ]
        """
        testDefaults.set(json.data(using: .utf8), forKey: "additionalClocks.v1")
        let settings = Settings(defaults: testDefaults)
        XCTAssertEqual(settings.additionalClocks.map { $0.identifier }, ["America/Toronto"])
    }

    func testZeroOffsetGeographicZoneIsNotTreatedAsUTCAlias() {
        var settings = Settings(defaults: testDefaults)
        settings.additionalClocks = [AdditionalClock(identifier: "Africa/Abidjan")]
        XCTAssertEqual(settings.additionalClocks.map { $0.identifier }, ["Africa/Abidjan"])
    }

    func testReadingDoesNotMutateDefaultsEvenWhenCleaningInvalidEntries() {
        let json = """
        [
            {"identifier": "America/Toronto"},
            {"identifier": "Not/AZone"},
            {"identifier": "America/Toronto"}
        ]
        """
        let originalData = json.data(using: .utf8)!
        testDefaults.set(originalData, forKey: "additionalClocks.v1")
        let settings = Settings(defaults: testDefaults)
        _ = settings.additionalClocks
        XCTAssertEqual(testDefaults.data(forKey: "additionalClocks.v1"), originalData)
    }
}
