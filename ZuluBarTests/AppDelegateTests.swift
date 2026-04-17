import XCTest
@testable import ZuluBar

final class AppDelegateTests: XCTestCase {

    private var delegate: AppDelegate!
    private let defaults = UserDefaults.standard
    private let testKeys = [
        "showSeconds", "showDate", "dateFormat", "displaySuffix", "copyFormat",
        "copyShortcutKeyCode", "copyShortcutModifiers", "copyShortcutDisplay",
    ]

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
        XCTAssertEqual(delegate.displaySuffix, .z)
    }

    func testCopyFormatDefaultIsDisplay() {
        XCTAssertEqual(delegate.copyFormat, .display)
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
        delegate.copyFormat = .rfc3339
        XCTAssertEqual(delegate.copyFormat, .rfc3339)
        XCTAssertEqual(defaults.string(forKey: "copyFormat"), "RFC 3339")
    }

    func testDateFormatPersists() {
        delegate.dateFormat = .dayDateMonth
        XCTAssertEqual(delegate.dateFormat, .dayDateMonth)
        XCTAssertEqual(defaults.string(forKey: "dateFormat"), "Tue 2 Dec")
    }

    // MARK: - Copy Shortcut

    func testCopyShortcutDefaultIsNil() {
        XCTAssertNil(delegate.copyShortcut)
    }

    func testCopyShortcutPersists() {
        let shortcut = AppDelegate.HotKey(
            keyCode: 8,
            modifierFlags: [.command],
            display: "⌘C"
        )
        delegate.copyShortcut = shortcut
        XCTAssertEqual(delegate.copyShortcut?.keyCode, 8)
        XCTAssertEqual(delegate.copyShortcut?.display, "⌘C")
        XCTAssertTrue(delegate.copyShortcut?.modifierFlags.contains(.command) == true)
        XCTAssertEqual(defaults.integer(forKey: "copyShortcutKeyCode"), 8)
        XCTAssertEqual(defaults.string(forKey: "copyShortcutDisplay"), "⌘C")
    }

    func testCopyShortcutClearRemovesAllKeys() {
        delegate.copyShortcut = AppDelegate.HotKey(keyCode: 8, modifierFlags: [.command], display: "⌘C")
        delegate.copyShortcut = nil
        XCTAssertNil(delegate.copyShortcut)
        XCTAssertNil(defaults.object(forKey: "copyShortcutKeyCode"))
        XCTAssertNil(defaults.object(forKey: "copyShortcutModifiers"))
        XCTAssertNil(defaults.object(forKey: "copyShortcutDisplay"))
    }

    func testCopyShortcutModifierRoundTrip() {
        let flags: NSEvent.ModifierFlags = [.command, .shift]
        delegate.copyShortcut = AppDelegate.HotKey(keyCode: 3, modifierFlags: flags, display: "⌘⇧F")
        let recovered = delegate.copyShortcut
        XCTAssertNotNil(recovered)
        XCTAssertTrue(recovered?.modifierFlags.contains(.command) == true)
        XCTAssertTrue(recovered?.modifierFlags.contains(.shift) == true)
        XCTAssertFalse(recovered?.modifierFlags.contains(.option) == true)
        XCTAssertFalse(recovered?.modifierFlags.contains(.control) == true)
    }

    // MARK: - Copy Format Output

    func testCopyDisplayMatchesSuffix() {
        delegate.copyFormat = .display
        let result = delegate.getFormattedTimeForCopy()
        XCTAssertTrue(result.hasSuffix("Z"), "Expected Z suffix, got: \(result)")
        XCTAssertTrue(result.contains(":"), "Expected time with colons, got: \(result)")
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
