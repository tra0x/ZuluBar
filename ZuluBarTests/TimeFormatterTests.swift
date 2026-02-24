import XCTest
@testable import ZuluBar

final class TimeFormatterTests: XCTestCase {

    // MARK: - Test Data

    /// Fixed date for consistent testing: 2025-12-02 14:23:45 UTC
    private let testDate: Date = {
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 2
        components.hour = 14
        components.minute = 23
        components.second = 45
        components.timeZone = TimeZone(abbreviation: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    // MARK: - Human Readable Format Tests

    func testHumanReadableWithSecondsAndUTCSuffix() {
        let format = UTCTimeFormatter.Format.humanReadable(showSeconds: true, suffix: .utc)
        let result = UTCTimeFormatter.format(testDate, as: format)
        XCTAssertEqual(result, "14:23:45 UTC")
    }

    func testHumanReadableWithSecondsAndZSuffix() {
        let format = UTCTimeFormatter.Format.humanReadable(showSeconds: true, suffix: .z)
        let result = UTCTimeFormatter.format(testDate, as: format)
        XCTAssertEqual(result, "14:23:45Z")
    }

    func testHumanReadableWithSecondsAndNoSuffix() {
        let format = UTCTimeFormatter.Format.humanReadable(showSeconds: true, suffix: .none)
        let result = UTCTimeFormatter.format(testDate, as: format)
        XCTAssertEqual(result, "14:23:45")
    }

    func testHumanReadableWithoutSecondsAndUTCSuffix() {
        let format = UTCTimeFormatter.Format.humanReadable(showSeconds: false, suffix: .utc)
        let result = UTCTimeFormatter.format(testDate, as: format)
        XCTAssertEqual(result, "14:23 UTC")
    }

    func testHumanReadableWithoutSecondsAndZSuffix() {
        let format = UTCTimeFormatter.Format.humanReadable(showSeconds: false, suffix: .z)
        let result = UTCTimeFormatter.format(testDate, as: format)
        XCTAssertEqual(result, "14:23Z")
    }

    func testHumanReadableWithoutSecondsAndNoSuffix() {
        let format = UTCTimeFormatter.Format.humanReadable(showSeconds: false, suffix: .none)
        let result = UTCTimeFormatter.format(testDate, as: format)
        XCTAssertEqual(result, "14:23")
    }

    // MARK: - ISO 8601 Format Tests

    func testISO8601Format() {
        let format = UTCTimeFormatter.Format.iso8601
        let result = UTCTimeFormatter.format(testDate, as: format)
        XCTAssertEqual(result, "2025-12-02T14:23:45Z")
    }

    // MARK: - Unix Timestamp Format Tests

    func testUnixTimestampFormat() {
        let format = UTCTimeFormatter.Format.unixTimestamp
        let result = UTCTimeFormatter.format(testDate, as: format)

        // Verify it's a valid integer
        XCTAssertNotNil(Int(result))

        // Verify it's approximately correct (within a few seconds for test execution time)
        if let timestamp = Int(result) {
            let expectedTimestamp = Int(testDate.timeIntervalSince1970)
            XCTAssertEqual(timestamp, expectedTimestamp)
        }
    }

    // MARK: - RFC 3339 Format Tests

    func testRFC3339Format() {
        let format = UTCTimeFormatter.Format.rfc3339
        let result = UTCTimeFormatter.format(testDate, as: format)
        XCTAssertEqual(result, "2025-12-02T14:23:45Z")
    }
}
