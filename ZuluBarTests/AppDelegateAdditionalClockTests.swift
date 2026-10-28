import XCTest
@testable import ZuluBar

final class AppDelegateAdditionalClockTests: XCTestCase {
    // Tuesday, 2025-12-02 00:30:45 UTC: Monday in Toronto and Los Angeles.
    private let instant = Date(timeIntervalSince1970: 1_764_635_445)

    @MainActor
    private func withDelegate(_ body: (AppDelegate) -> Void) {
        let suite = "com.zulubar.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let delegate = AppDelegate()
        delegate.settings = Settings(defaults: defaults)
        defer {
            delegate.timer?.invalidate()
            defaults.removePersistentDomain(forName: suite)
        }
        body(delegate)
    }

    @MainActor
    func testNoExtraClocksPreservesLegacyUTCDisplay() {
        withDelegate { delegate in
            let content = delegate.statusBarContent(at: instant)
            XCTAssertEqual(content.utcTitle, "00:30:45Z")
            XCTAssertTrue(content.additional.isEmpty)
        }
    }

    @MainActor
    func testOneInstantRendersLocalWeekdaysAndConfiguredOrder() {
        withDelegate { delegate in
            delegate.settings.showSeconds = false
            delegate.settings.additionalClocks = [
                AdditionalClock(identifier: "America/Los_Angeles"),
                AdditionalClock(identifier: "Asia/Tokyo"),
                AdditionalClock(identifier: "America/Toronto"),
            ]
            let content = delegate.statusBarContent(at: instant)
            XCTAssertEqual(content.utcTitle, "00:30Z")
            XCTAssertEqual(content.additional.map(\.identifier), ["America/Los_Angeles", "Asia/Tokyo", "America/Toronto"])
            XCTAssertEqual(content.additional.map(\.time), ["Mon 16:30", "Tue 09:30", "Mon 19:30"])
        }
    }

    @MainActor
    func testDateAndSuffixRemainUTCOnlyWhileSecondsApplyToAll() {
        withDelegate { delegate in
            delegate.settings.showDate = true
            delegate.settings.displaySuffix = .utc
            delegate.settings.additionalClocks = [AdditionalClock(identifier: "America/Toronto")]
            let content = delegate.statusBarContent(at: instant)
            XCTAssertEqual(content.utcTitle, "Tue Dec 2 00:30:45 UTC")
            XCTAssertEqual(content.additional.first?.label, "Toronto")
            XCTAssertEqual(content.additional.first?.time, "Mon 19:30:45")
        }
    }

    @MainActor
    func testExtraClocksNeverChangeGlobalUTCCopyPath() {
        withDelegate { delegate in
            delegate.settings.additionalClocks = [AdditionalClock(identifier: "America/Toronto")]
            XCTAssertEqual(delegate.getFormattedTimeForCopy(at: instant), "00:30:45Z")
            delegate.settings.copyFormat = .rfc3339
            XCTAssertEqual(delegate.getFormattedTimeForCopy(at: instant), "2025-12-02T00:30:45Z")
        }
    }

    @MainActor
    func testExtraClockCopyUsesItsOwnZoneAndFormat() {
        withDelegate { delegate in
            delegate.settings.additionalClocks = [AdditionalClock(identifier: "America/Toronto")]
            XCTAssertEqual(delegate.getFormattedTimeForAdditionalClock(identifier: "America/Toronto", at: instant),
                           "Toronto Mon 19:30:45 UTC-05:00")
            delegate.settings.copyFormat = .rfc3339
            XCTAssertEqual(delegate.getFormattedTimeForAdditionalClock(identifier: "America/Toronto", at: instant),
                           "2025-12-01T19:30:45-05:00")
            delegate.settings.copyFormat = .unixTimestamp
            XCTAssertEqual(delegate.getFormattedTimeForAdditionalClock(identifier: "America/Toronto", at: instant),
                           delegate.getFormattedTimeForCopy(at: instant))
        }
    }

    @MainActor
    func testReorderingDoesNotRetargetCopyAndRemovalInvalidatesStaleClick() {
        withDelegate { delegate in
            let toronto = AdditionalClock(identifier: "America/Toronto")
            let tokyo = AdditionalClock(identifier: "Asia/Tokyo")
            delegate.settings.additionalClocks = [toronto, tokyo]
            let before = delegate.getFormattedTimeForAdditionalClock(identifier: toronto.identifier, at: instant)
            delegate.settings.additionalClocks = [tokyo, toronto]
            XCTAssertEqual(delegate.getFormattedTimeForAdditionalClock(identifier: toronto.identifier, at: instant), before)
            delegate.settings.additionalClocks = [tokyo]
            XCTAssertNil(delegate.getFormattedTimeForAdditionalClock(identifier: toronto.identifier, at: instant))
        }
    }

    @MainActor
    func testTimerRestartInvalidatesThePendingInitialTimer() {
        withDelegate { delegate in
            delegate.startTimer()
            let first = delegate.timer
            XCTAssertEqual(first?.isValid, true)
            delegate.startTimer()
            XCTAssertEqual(first?.isValid, false)
            XCTAssertEqual(delegate.timer?.isValid, true)
            XCTAssertFalse(delegate.timer === first)
        }
    }
}
