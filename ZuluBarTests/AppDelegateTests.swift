import XCTest
@testable import ZuluBar

final class AppDelegateTests: XCTestCase {

    private var delegate: AppDelegate!
    private let defaults = UserDefaults.standard
    private let testKeys = ["showSeconds", "showDate", "dateFormat", "displaySuffix", "copyFormat"]

    override func setUp() {
        super.setUp()
        testKeys.forEach { defaults.removeObject(forKey: $0) }
        delegate = AppDelegate()
    }

    override func tearDown() {
        testKeys.forEach { defaults.removeObject(forKey: $0) }
        delegate = nil
        super.tearDown()
    }

    // MARK: - Default Values

    func testShowSecondsDefaultIsTrue() {
        XCTAssertTrue(delegate.showSeconds)
    }

    func testShowDateDefaultIsFalse() {
        XCTAssertFalse(delegate.showDate)
    }

    func testDisplaySuffixDefaultIsUTC() {
        XCTAssertEqual(delegate.displaySuffix, .utc)
    }

    func testCopyFormatDefaultIsHumanReadable() {
        XCTAssertEqual(delegate.copyFormat, .humanReadable)
    }

    func testDateFormatDefaultIsDayMonthDate() {
        XCTAssertEqual(delegate.dateFormat, .dayMonthDate)
    }

    // MARK: - Settings Persistence

    func testShowSecondsPersists() {
        delegate.showSeconds = false
        XCTAssertFalse(delegate.showSeconds)
        XCTAssertFalse(defaults.bool(forKey: "showSeconds"))
    }

    func testShowDatePersists() {
        delegate.showDate = true
        XCTAssertTrue(delegate.showDate)
        XCTAssertTrue(defaults.bool(forKey: "showDate"))
    }

    func testDisplaySuffixPersists() {
        delegate.displaySuffix = .z
        XCTAssertEqual(delegate.displaySuffix, .z)
        XCTAssertEqual(defaults.string(forKey: "displaySuffix"), "Z")
    }

    func testCopyFormatPersists() {
        delegate.copyFormat = .iso8601
        XCTAssertEqual(delegate.copyFormat, .iso8601)
        XCTAssertEqual(defaults.string(forKey: "copyFormat"), "ISO 8601")
    }

    func testDateFormatPersists() {
        delegate.dateFormat = .dayDateMonth
        XCTAssertEqual(delegate.dateFormat, .dayDateMonth)
        XCTAssertEqual(defaults.string(forKey: "dateFormat"), "Tue 2 Dec")
    }

    // MARK: - Copy Format Output

    func testCopyHumanReadableHasUTCSuffix() {
        delegate.copyFormat = .humanReadable
        let result = delegate.getFormattedTimeForCopy()
        XCTAssertTrue(result.hasSuffix(" UTC"), "Expected UTC suffix, got: \(result)")
        XCTAssertTrue(result.contains(":"), "Expected time with colons, got: \(result)")
    }

    func testCopyISO8601Format() {
        delegate.copyFormat = .iso8601
        let result = delegate.getFormattedTimeForCopy()
        let regex = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"#)
        let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result))
        XCTAssertNotNil(match, "Expected ISO 8601 format, got: \(result)")
    }

    func testCopyUnixTimestampIsInteger() {
        delegate.copyFormat = .unixTimestamp
        let result = delegate.getFormattedTimeForCopy()
        let timestamp = Int(result)
        XCTAssertNotNil(timestamp, "Expected integer, got: \(result)")
        XCTAssertGreaterThan(timestamp!, 0)
    }

    func testCopyRFC3339Format() {
        delegate.copyFormat = .rfc3339
        let result = delegate.getFormattedTimeForCopy()
        let regex = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"#)
        let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result))
        XCTAssertNotNil(match, "Expected RFC 3339 format, got: \(result)")
    }
}
