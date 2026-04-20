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
        XCTAssertTrue(delegate.settings.showSeconds)
    }

    func testShowDateDefaultIsFalse() {
        XCTAssertFalse(delegate.settings.showDate)
    }

    func testDisplaySuffixDefaultIsZ() {
        XCTAssertEqual(delegate.settings.displaySuffix, .z)
    }

    func testCopyFormatDefaultIsDisplay() {
        XCTAssertEqual(delegate.settings.copyFormat, .display)
    }

    func testDateFormatDefaultIsDayMonthDate() {
        XCTAssertEqual(delegate.settings.dateFormat, .dayMonthDate)
    }

    // MARK: - Settings Persistence

    func testShowSecondsPersists() {
        delegate.settings.showSeconds = false
        XCTAssertFalse(delegate.settings.showSeconds)
        XCTAssertFalse(defaults.bool(forKey: "showSeconds"))
    }

    func testShowDatePersists() {
        delegate.settings.showDate = true
        XCTAssertTrue(delegate.settings.showDate)
        XCTAssertTrue(defaults.bool(forKey: "showDate"))
    }

    func testDisplaySuffixPersists() {
        delegate.settings.displaySuffix = .z
        XCTAssertEqual(delegate.settings.displaySuffix, .z)
        XCTAssertEqual(defaults.string(forKey: "displaySuffix"), "Z")
    }

    func testCopyFormatPersists() {
        delegate.settings.copyFormat = .rfc3339
        XCTAssertEqual(delegate.settings.copyFormat, .rfc3339)
        XCTAssertEqual(defaults.string(forKey: "copyFormat"), "RFC 3339")
    }

    func testDateFormatPersists() {
        delegate.settings.dateFormat = .dayDateMonth
        XCTAssertEqual(delegate.settings.dateFormat, .dayDateMonth)
        XCTAssertEqual(defaults.string(forKey: "dateFormat"), "Tue 2 Dec")
    }

    // MARK: - Copy Shortcut

    func testCopyShortcutDefaultIsNil() {
        XCTAssertNil(delegate.settings.copyShortcut)
    }

    func testCopyShortcutPersists() {
        let shortcut = HotKey(keyCode: 8, modifierFlags: [.command])
        delegate.settings.copyShortcut = shortcut
        XCTAssertEqual(delegate.settings.copyShortcut?.keyCode, 8)
        XCTAssertTrue(delegate.settings.copyShortcut?.modifierFlags.contains(.command) == true)
        XCTAssertEqual(defaults.integer(forKey: "copyShortcutKeyCode"), 8)
    }

    func testCopyShortcutDisplayIsComputed() {
        // keyCode 8 is "C" on a US keyboard; combined with ⌘ the display should start with ⌘.
        let shortcut = HotKey(keyCode: 8, modifierFlags: [.command])
        delegate.settings.copyShortcut = shortcut
        XCTAssertTrue(delegate.settings.copyShortcut?.display.hasPrefix("⌘") == true)
    }

    func testCopyShortcutClearRemovesAllKeys() {
        delegate.settings.copyShortcut = HotKey(keyCode: 8, modifierFlags: [.command])
        delegate.settings.copyShortcut = nil
        XCTAssertNil(delegate.settings.copyShortcut)
        XCTAssertNil(defaults.object(forKey: "copyShortcutKeyCode"))
        XCTAssertNil(defaults.object(forKey: "copyShortcutModifiers"))
        XCTAssertNil(defaults.object(forKey: "copyShortcutDisplay"))
    }

    func testCopyShortcutModifierRoundTrip() {
        let flags: NSEvent.ModifierFlags = [.command, .shift]
        delegate.settings.copyShortcut = HotKey(keyCode: 3, modifierFlags: flags)
        let recovered = delegate.settings.copyShortcut
        XCTAssertNotNil(recovered)
        XCTAssertTrue(recovered?.modifierFlags.contains(.command) == true)
        XCTAssertTrue(recovered?.modifierFlags.contains(.shift) == true)
        XCTAssertFalse(recovered?.modifierFlags.contains(.option) == true)
        XCTAssertFalse(recovered?.modifierFlags.contains(.control) == true)
    }

    // MARK: - Copy Format Output

    func testCopyDisplayMatchesSuffix() {
        delegate.settings.copyFormat = .display
        let result = delegate.getFormattedTimeForCopy()
        XCTAssertTrue(result.hasSuffix("Z"), "Expected Z suffix, got: \(result)")
        XCTAssertTrue(result.contains(":"), "Expected time with colons, got: \(result)")
    }

    func testCopyUnixTimestampIsInteger() {
        delegate.settings.copyFormat = .unixTimestamp
        let result = delegate.getFormattedTimeForCopy()
        let timestamp = Int(result)
        XCTAssertNotNil(timestamp, "Expected integer, got: \(result)")
        XCTAssertGreaterThan(timestamp!, 0)
    }

    func testCopyRFC3339Format() {
        delegate.settings.copyFormat = .rfc3339
        let result = delegate.getFormattedTimeForCopy()
        let regex = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"#)
        let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result))
        XCTAssertNotNil(match, "Expected RFC 3339 format, got: \(result)")
    }
}
