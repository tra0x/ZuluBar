import XCTest
@testable import ZuluBar

/// Stand-in for the owner's existing status-item click handler, used to prove
/// the strip borrows and returns the button's target/action.
private final class StatusButtonClickSpy: NSObject {
    var clicks = 0

    @objc func statusItemClicked() {
        clicks += 1
    }
}

/// Thrown by `laidOutWindow(for:)` after it has already reported the failure
/// via `XCTFail`, purely to stop the calling test before it hit-tests a
/// window that never became ready.
private struct StatusWindowReadinessTimeout: Error {}

/// The strip is main-thread AppKit, so the whole case is main-actor isolated.
/// `setUp`/`tearDown` are deliberately not overridden — each test builds and
/// tears down its own status item instead, which keeps the isolation clean.
@MainActor
final class ClockStripControllerTests: XCTestCase {

    // MARK: - Fixtures

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        return item
    }

    private let toronto = ClockStripEntry(identifier: "America/Toronto", label: "Toronto", time: "Tue 09:41")
    private let tokyo = ClockStripEntry(identifier: "Asia/Tokyo", label: "Tokyo", time: "Tue 22:41")

    /// Distinct event numbers, as AppKit gives real clicks.
    private var eventNumber = 0

    private func mouseEvent(_ type: NSEvent.EventType,
                            at location: NSPoint = .zero,
                            windowNumber: Int = 0,
                            modifiers: NSEvent.ModifierFlags = []) -> NSEvent? {
        eventNumber += 1
        let isDown = type == .leftMouseDown || type == .rightMouseDown
        return NSEvent.mouseEvent(with: type,
                                  location: location,
                                  modifierFlags: modifiers,
                                  timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: windowNumber,
                                  context: nil,
                                  eventNumber: eventNumber,
                                  clickCount: 1,
                                  pressure: isDown ? 1 : 0)
    }

    /// Lays out the real status-item window so AppKit can hit-test the strip,
    /// matching the harness the native routing was verified with. Environments
    /// without a status-bar window skip rather than fail; a window that never
    /// becomes ready fails outright, since that is a genuine readiness bug
    /// rather than an absent harness.
    ///
    /// A freshly created status window reports a zero-height content view
    /// until native registration/WindowServer finishes, even though the
    /// button and clock cells already have positive sizes. This waits —
    /// bounded and condition-based, not a fixed sleep — for the window to
    /// actually be ready before forcing layout and hit-testing it.
    private func laidOutWindow(for button: NSStatusBarButton) throws -> NSWindow {
        guard let window = button.window else {
            throw XCTSkip("No status-bar window here, so native event routing can't be exercised")
        }

        let readiness = XCTNSPredicateExpectation(
            predicate: NSPredicate(block: { _, _ in
                (window.contentView?.bounds.height ?? 0) > 0
            }),
            object: window
        )
        if XCTWaiter.wait(for: [readiness], timeout: 3) != .completed {
            XCTFail("Status-bar window never reported a positive content height; native hit testing cannot proceed")
            throw StatusWindowReadinessTimeout()
        }

        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    /// Centre of a clock in window coordinates — what AppKit hit-tests with.
    private func center(of cell: ClockStripCellView) -> NSPoint {
        cell.convert(NSPoint(x: cell.bounds.midX, y: cell.bounds.midY), to: nil)
    }

    // MARK: - UTC-only layout

    func testUTCOnlyUsesStatusButtonTitleAndNoCustomViews() throws {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        let controller = ClockStripController(statusItem: item)

        controller.render(utcTitle: "12:00:00Z", additional: [])

        XCTAssertFalse(controller.isUsingStripLayout)
        XCTAssertTrue(controller.clockCells.isEmpty)
        XCTAssertEqual(button.title, "12:00:00Z")
        XCTAssertEqual(item.length, NSStatusItem.variableLength)
        XCTAssertNotEqual(button.accessibilityRole(), .group,
                          "UTC-only mode keeps the status button's own role")
    }

    func testRemovingLastExtraRestoresSingleLineStatusButton() throws {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        let controller = ClockStripController(statusItem: item)
        let originalRole = button.accessibilityRole()
        let originalAction = button.action

        controller.render(utcTitle: "12:00:00Z", additional: [toronto])
        XCTAssertTrue(controller.isUsingStripLayout)

        controller.render(utcTitle: "12:00:01Z", additional: [])

        XCTAssertFalse(controller.isUsingStripLayout)
        XCTAssertEqual(button.title, "12:00:01Z")
        XCTAssertEqual(item.length, NSStatusItem.variableLength)
        XCTAssertEqual(button.accessibilityRole(), originalRole,
                       "The status button's own accessibility is handed back")
        XCTAssertEqual(button.action, originalAction,
                       "The owner's original click path is handed back")
    }

    func testUTCOnlyTicksKeepVariableLengthWithoutNeedlessReassignment() throws {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        let controller = ClockStripController(statusItem: item)

        controller.render(utcTitle: "12:00:00Z", additional: [])
        controller.render(utcTitle: "12:00:01Z", additional: [])
        controller.render(utcTitle: "12:00:02Z", additional: [])

        XCTAssertEqual(item.length, NSStatusItem.variableLength,
                       "An already self-sizing status item stays self-sizing")
        XCTAssertEqual(button.title, "12:00:02Z", "Title updates are never suppressed")

        // The guard must not stop the layout from reclaiming a fixed width —
        // the strip leaves one behind on every multi-to-UTC transition.
        item.length = 120
        controller.render(utcTitle: "12:00:03Z", additional: [])
        XCTAssertEqual(item.length, NSStatusItem.variableLength)

        controller.render(utcTitle: "12:00:04Z", additional: [toronto])
        XCTAssertGreaterThan(item.length, 0, "The strip still measures its own width")
        controller.render(utcTitle: "12:00:05Z", additional: [])
        XCTAssertEqual(item.length, NSStatusItem.variableLength,
                       "Dropping the last extra hands the width back to AppKit")
    }

    // MARK: - Strip composition

    func testStripShowsUTCFirstThenConfiguredOrder() {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let controller = ClockStripController(statusItem: item)

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])

        XCTAssertEqual(controller.clockCells.map { $0.kind },
                       [.utc,
                        .additional(identifier: "America/Toronto"),
                        .additional(identifier: "Asia/Tokyo")])
        XCTAssertNil(controller.clockCells[0].labelText, "UTC stays on one line")
        XCTAssertEqual(controller.clockCells[0].timeText, "12:00:00Z")
        XCTAssertEqual(controller.clockCells[1].labelText, "Toronto")
        XCTAssertEqual(controller.clockCells[1].timeText, "Tue 09:41")
    }

    func testUTCClockIsMeasuredWithTheStatusButtonFont() throws {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        let font = try XCTUnwrap(button.font)
        let controller = ClockStripController(statusItem: item)

        controller.render(utcTitle: "12:00:00Z", additional: [toronto])

        let expected = ceil(("12:00:00Z" as NSString).size(withAttributes: [.font: font]).width)
            + 2 * ClockStripCellView.Metrics.horizontalPadding
        XCTAssertEqual(controller.clockCells[0].intrinsicContentSize.width, expected, accuracy: 0.5,
                       "UTC must keep the status button's own font and single-line metrics")
    }

    func testStripBorrowsTheStatusButtonActionSoGapClicksDoNotCopy() throws {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        let owner = StatusButtonClickSpy()
        button.target = owner
        button.action = #selector(StatusButtonClickSpy.statusItemClicked)
        let controller = ClockStripController(statusItem: item)

        controller.render(utcTitle: "12:00:00Z", additional: [toronto])
        XCTAssertFalse(button.target === owner, "The strip handles clicks that land between clocks")

        controller.render(utcTitle: "12:00:01Z", additional: [])
        XCTAssertTrue(button.target === owner, "The owner's click path comes back in UTC-only mode")
        XCTAssertEqual(button.action, #selector(StatusButtonClickSpy.statusItemClicked))
        XCTAssertEqual(owner.clicks, 0, "Rendering never fires the owner's click handler")
    }

    func testOrdinaryTickReusesClockViews() {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let controller = ClockStripController(statusItem: item)

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        let first = controller.clockCells

        controller.render(utcTitle: "12:00:01Z",
                          additional: [ClockStripEntry(identifier: "America/Toronto", label: "Toronto", time: "Tue 09:42"),
                                       ClockStripEntry(identifier: "Asia/Tokyo", label: "Tokyo", time: "Tue 22:42")])
        let second = controller.clockCells

        XCTAssertEqual(first.count, second.count)
        for (before, after) in zip(first, second) {
            XCTAssertTrue(before === after, "Ticks must reuse the existing clock views")
        }
        XCTAssertEqual(second[0].timeText, "12:00:01Z")
        XCTAssertEqual(second[1].timeText, "Tue 09:42")
    }

    func testReorderKeepsTheSameViewsInTheNewOrder() {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let controller = ClockStripController(statusItem: item)

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        let torontoCell = controller.clockCells[1]
        let tokyoCell = controller.clockCells[2]

        controller.render(utcTitle: "12:00:01Z", additional: [tokyo, toronto])

        XCTAssertTrue(controller.clockCells[1] === tokyoCell)
        XCTAssertTrue(controller.clockCells[2] === torontoCell)
        XCTAssertEqual(controller.clockCells.map { $0.kind },
                       [.utc,
                        .additional(identifier: "Asia/Tokyo"),
                        .additional(identifier: "America/Toronto")])
    }

    func testRemovingOneClockDropsOnlyThatView() {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let controller = ClockStripController(statusItem: item)

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        let utcCell = controller.clockCells[0]
        let torontoCell = controller.clockCells[1]
        let tokyoCell = controller.clockCells[2]

        controller.render(utcTitle: "12:00:01Z", additional: [toronto])

        XCTAssertEqual(controller.clockCells.count, 2)
        XCTAssertTrue(controller.clockCells[0] === utcCell)
        XCTAssertTrue(controller.clockCells[1] === torontoCell)
        XCTAssertNil(tokyoCell.superview, "The removed clock's view must leave the strip")
    }

    func testDuplicateIdentifiersCollapseToOneClock() {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let controller = ClockStripController(statusItem: item)

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, toronto])

        XCTAssertEqual(controller.additionalEntries.count, 1)
        XCTAssertEqual(controller.clockCells.count, 2)
    }

    func testStripWidthIsMeasuredAndGrowsWithEachClock() {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let controller = ClockStripController(statusItem: item)

        controller.render(utcTitle: "12:00:00Z", additional: [toronto])
        let oneClock = item.length

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        let twoClocks = item.length

        XCTAssertGreaterThan(oneClock, 0)
        XCTAssertGreaterThan(twoClocks, oneClock)
    }

    func testLongLabelIsClippedWhileTimeStaysFullyMeasured() {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let controller = ClockStripController(statusItem: item)
        let longLabel = "Port-au-Prince Extremely Long Label"
        let entry = ClockStripEntry(identifier: "America/Port-au-Prince", label: longLabel, time: "Tue 09:41:07")

        controller.render(utcTitle: "12:00:00Z", additional: [entry])
        let cell = controller.clockCells[1]

        let maxWidth = ClockStripCellView.Metrics.maxLabelWidth + 2 * ClockStripCellView.Metrics.horizontalPadding
        let timeWidth = ("Tue 09:41:07" as NSString)
            .size(withAttributes: [.font: ClockStripCellView.Metrics.stackedTimeFont]).width

        XCTAssertLessThanOrEqual(cell.intrinsicContentSize.width, maxWidth)
        XCTAssertGreaterThanOrEqual(cell.intrinsicContentSize.width, timeWidth,
                                    "The time line must never be clipped")
        XCTAssertEqual(cell.toolTip, "\(longLabel) · Tue 09:41:07 · America/Port-au-Prince")
    }

    // MARK: - Clicks and callbacks

    func testPressingAClockCopiesItsOwnZone() {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let controller = ClockStripController(statusItem: item)
        var copiedUTC = 0
        var copiedIdentifiers: [String] = []
        controller.onCopyUTC = { copiedUTC += 1 }
        controller.onCopyAdditional = { copiedIdentifiers.append($0) }

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        _ = controller.clockCells[0].accessibilityPerformPress()
        _ = controller.clockCells[2].accessibilityPerformPress()

        XCTAssertEqual(copiedUTC, 1)
        XCTAssertEqual(copiedIdentifiers, ["Asia/Tokyo"], "The configured identifier is passed, not an index")
    }

    func testOptionsMenuReceivesTheClickedClockView() {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let controller = ClockStripController(statusItem: item)
        var anchors: [NSView] = []
        controller.onOptionsMenu = { anchors.append($0) }

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        _ = controller.clockCells[1].accessibilityPerformShowMenu()

        XCTAssertEqual(anchors.count, 1)
        XCTAssertTrue(anchors.first === controller.clockCells[1])
    }

    func testRenderDoesNotTriggerCopyOrMenu() {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let controller = ClockStripController(statusItem: item)
        var sideEffects = 0
        controller.onCopyUTC = { sideEffects += 1 }
        controller.onCopyAdditional = { _ in sideEffects += 1 }
        controller.onOptionsMenu = { _ in sideEffects += 1 }

        controller.render(utcTitle: "12:00:00Z", additional: [])
        controller.render(utcTitle: "12:00:01Z", additional: [toronto])
        controller.render(utcTitle: "12:00:02Z", additional: [toronto, tokyo])

        XCTAssertEqual(sideEffects, 0)
    }

    // MARK: - Copied feedback

    func testFeedbackShowsOnOneClockAndResetsOnSchedule() {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        var pending: [() -> Void] = []
        let controller = ClockStripController(statusItem: item, schedule: { _, work in pending.append(work) })

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        controller.showCopiedFeedback(for: "Asia/Tokyo")

        XCTAssertFalse(controller.clockCells[0].isShowingCopiedFeedback)
        XCTAssertFalse(controller.clockCells[1].isShowingCopiedFeedback)
        XCTAssertTrue(controller.clockCells[2].isShowingCopiedFeedback)

        XCTAssertEqual(pending.count, 1)
        pending.removeFirst()()

        XCTAssertFalse(controller.clockCells[2].isShowingCopiedFeedback)
    }

    func testFeedbackDoesNotChangeStripWidth() {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        var pending: [() -> Void] = []
        let controller = ClockStripController(statusItem: item, schedule: { _, work in pending.append(work) })

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        let widthBefore = item.length
        let tokyoWidthBefore = controller.clockCells[2].intrinsicContentSize.width

        controller.showCopiedFeedback(for: "Asia/Tokyo")

        XCTAssertEqual(item.length, widthBefore)
        XCTAssertEqual(controller.clockCells[2].intrinsicContentSize.width, tokyoWidthBefore)

        pending.removeFirst()()
        XCTAssertEqual(item.length, widthBefore)
    }

    func testRapidCopiesKeepTheNewestFeedback() {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        var pending: [() -> Void] = []
        let controller = ClockStripController(statusItem: item, schedule: { _, work in pending.append(work) })

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        controller.showCopiedFeedback(for: "Asia/Tokyo")
        controller.showCopiedFeedback(for: "Asia/Tokyo")
        XCTAssertEqual(pending.count, 2)

        // The first copy's delayed reset must not cancel the second copy's
        // fresher indication.
        pending.removeFirst()()
        XCTAssertTrue(controller.clockCells[2].isShowingCopiedFeedback)

        pending.removeFirst()()
        XCTAssertFalse(controller.clockCells[2].isShowingCopiedFeedback)
    }

    func testOtherClocksKeepRefreshingWhileOneShowsFeedback() {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        var pending: [() -> Void] = []
        let controller = ClockStripController(statusItem: item, schedule: { _, work in pending.append(work) })

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        controller.showCopiedFeedback(for: "America/Toronto")
        controller.render(utcTitle: "12:00:01Z",
                          additional: [ClockStripEntry(identifier: "America/Toronto", label: "Toronto", time: "Tue 09:42"),
                                       ClockStripEntry(identifier: "Asia/Tokyo", label: "Tokyo", time: "Tue 22:42")])

        XCTAssertTrue(controller.clockCells[1].isShowingCopiedFeedback, "Feedback survives an ordinary tick")
        XCTAssertEqual(controller.clockCells[0].timeText, "12:00:01Z")
        XCTAssertEqual(controller.clockCells[2].timeText, "Tue 22:42")
        // The copied clock's own time updated underneath the indication.
        XCTAssertEqual(controller.clockCells[1].timeText, "Tue 09:42")

        pending.removeFirst()()
        XCTAssertFalse(controller.clockCells[1].isShowingCopiedFeedback)
    }

    func testRemovingAClockDuringItsFeedbackIsSafe() {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        var pending: [() -> Void] = []
        let controller = ClockStripController(statusItem: item, schedule: { _, work in pending.append(work) })

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        controller.showCopiedFeedback(for: "Asia/Tokyo")
        controller.render(utcTitle: "12:00:01Z", additional: [toronto])

        // The stale reset finds nothing to clear and must not disturb the strip.
        pending.removeFirst()()

        XCTAssertEqual(controller.clockCells.count, 2)
        XCTAssertFalse(controller.clockCells[0].isShowingCopiedFeedback)
        XCTAssertFalse(controller.clockCells[1].isShowingCopiedFeedback)
    }

    func testFeedbackForUnknownClockIsIgnored() {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        var pending: [() -> Void] = []
        let controller = ClockStripController(statusItem: item, schedule: { _, work in pending.append(work) })

        controller.render(utcTitle: "12:00:00Z", additional: [toronto])
        controller.showCopiedFeedback(for: "Pacific/Chatham")

        XCTAssertTrue(pending.isEmpty)
        XCTAssertFalse(controller.clockCells[1].isShowingCopiedFeedback)
    }

    func testUTCOnlyFeedbackKeepsTheNativeSingleLineTitle() throws {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        var pending: [() -> Void] = []
        let controller = ClockStripController(statusItem: item, schedule: { _, work in pending.append(work) })

        controller.render(utcTitle: "12:00:00Z", additional: [])
        controller.showCopiedFeedback(for: nil)

        XCTAssertFalse(controller.isUsingStripLayout, "No custom view is introduced for feedback")
        XCTAssertEqual(button.title, "✓ Copied")

        // Ticks during feedback must not overwrite the indication.
        controller.render(utcTitle: "12:00:01Z", additional: [])
        XCTAssertEqual(button.title, "✓ Copied")

        pending.removeFirst()()
        XCTAssertEqual(button.title, "12:00:01Z")
    }

    func testSwitchingLayoutDuringUTCFeedbackIsSafe() throws {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        var pending: [() -> Void] = []
        let controller = ClockStripController(statusItem: item, schedule: { _, work in pending.append(work) })

        controller.render(utcTitle: "12:00:00Z", additional: [toronto])
        controller.showCopiedFeedback(for: nil)
        XCTAssertTrue(controller.clockCells[0].isShowingCopiedFeedback)

        controller.render(utcTitle: "12:00:01Z", additional: [])
        XCTAssertEqual(button.title, "✓ Copied")

        pending.removeFirst()()
        XCTAssertEqual(button.title, "12:00:01Z")
    }

    // MARK: - Accessibility

    func testStripExposesOneAccessibleButtonPerClock() throws {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        let controller = ClockStripController(statusItem: item)

        controller.render(utcTitle: "12:00:00Z", additional: [toronto])

        XCTAssertEqual(button.accessibilityRole(), .group,
                       "The outer button must not read as a second, empty clock")
        XCTAssertEqual(button.title, "")
        let children = button.accessibilityChildren() as? [NSView]
        XCTAssertEqual(children?.count, 2)

        let utcCell = controller.clockCells[0]
        XCTAssertEqual(utcCell.accessibilityRole(), .button)
        XCTAssertEqual(utcCell.accessibilityLabel(), "UTC clock")
        XCTAssertEqual(utcCell.accessibilityValue() as? String, "12:00:00Z")
        XCTAssertTrue(utcCell.isAccessibilityElement())

        let torontoCell = controller.clockCells[1]
        XCTAssertEqual(torontoCell.accessibilityLabel(), "Toronto clock")
        XCTAssertEqual(torontoCell.accessibilityValue() as? String, "Tue 09:41")
        let help = try XCTUnwrap(torontoCell.accessibilityHelp())
        XCTAssertTrue(help.contains("America/Toronto"), "Help should name the zone, got: \(help)")
        XCTAssertTrue(help.lowercased().contains("copy"), "Help should mention the copy action, got: \(help)")
        XCTAssertTrue(help.lowercased().contains("menu"), "Help should mention the menu action, got: \(help)")
    }

    func testFeedbackIsAnnouncedAsTheClockValue() {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        var pending: [() -> Void] = []
        let controller = ClockStripController(statusItem: item, schedule: { _, work in pending.append(work) })

        controller.render(utcTitle: "12:00:00Z", additional: [toronto])
        controller.showCopiedFeedback(for: "America/Toronto")
        XCTAssertEqual(controller.clockCells[1].accessibilityValue() as? String, "Copied")

        pending.removeFirst()()
        XCTAssertEqual(controller.clockCells[1].accessibilityValue() as? String, "Tue 09:41")
    }

    func testOrdinaryTicksLeaveTheChildrenOverrideAloneButRefreshChildValues() throws {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        let controller = ClockStripController(statusItem: item)

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        let cells = controller.clockCells
        XCTAssertEqual((button.accessibilityChildren() as? [NSView])?.count, 3)

        // A sentinel nobody but a reconfigure would overwrite: if a plain tick
        // still rewrote the children, VoiceOver's traversal would be rebuilt
        // every second.
        let sentinel = [NSView()]
        button.setAccessibilityChildren(sentinel)

        controller.render(utcTitle: "12:00:01Z",
                          additional: [ClockStripEntry(identifier: "America/Toronto", label: "Toronto", time: "Tue 09:42"),
                                       ClockStripEntry(identifier: "Asia/Tokyo", label: "Tokyo", time: "Tue 22:42")])

        XCTAssertEqual((button.accessibilityChildren() as? [NSView])?.count, 1,
                       "An unchanged child set must not get a fresh children override")
        XCTAssertTrue((button.accessibilityChildren() as? [NSView])?.first === sentinel[0])
        XCTAssertTrue(controller.clockCells.elementsEqual(cells, by: { $0 === $1 }),
                      "The same clocks stay in the same order")
        XCTAssertEqual(controller.clockCells[0].accessibilityValue() as? String, "12:00:01Z")
        XCTAssertEqual(controller.clockCells[1].accessibilityValue() as? String, "Tue 09:42")
        XCTAssertEqual(controller.clockCells[2].accessibilityValue() as? String, "Tue 22:42")
    }

    func testAddRemoveAndReorderReinstallTheChildrenInDisplayOrder() throws {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        let controller = ClockStripController(statusItem: item)

        func children() -> [NSView] { (button.accessibilityChildren() as? [NSView]) ?? [] }

        controller.render(utcTitle: "12:00:00Z", additional: [toronto])
        XCTAssertTrue(children().elementsEqual(controller.clockCells, by: { $0 === $1 }))

        controller.render(utcTitle: "12:00:01Z", additional: [toronto, tokyo])
        XCTAssertTrue(children().elementsEqual(controller.clockCells, by: { $0 === $1 }),
                      "A new clock joins the children")
        XCTAssertEqual(children().count, 3)

        controller.render(utcTitle: "12:00:02Z", additional: [tokyo, toronto])
        XCTAssertTrue(children().elementsEqual(controller.clockCells, by: { $0 === $1 }),
                      "Reordering reinstalls the children in the new order")

        controller.render(utcTitle: "12:00:03Z", additional: [tokyo])
        XCTAssertTrue(children().elementsEqual(controller.clockCells, by: { $0 === $1 }))
        XCTAssertEqual(children().count, 2, "A removed clock leaves the children")

        controller.render(utcTitle: "12:00:04Z", additional: [])
        XCTAssertTrue(children().isEmpty, "UTC-only hands the button's own accessibility back")

        // Re-entering the strip must configure the group again from scratch.
        controller.render(utcTitle: "12:00:05Z", additional: [toronto])
        XCTAssertEqual(button.accessibilityRole(), .group)
        XCTAssertTrue(children().elementsEqual(controller.clockCells, by: { $0 === $1 }))
    }

    // MARK: - Group highlighting

    func testPressingOneClockMakesEveryClockUseSelectedMenuText() throws {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let controller = ClockStripController(statusItem: item)

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        for clockCell in controller.clockCells {
            XCTAssertEqual(clockCell.textColor, NSColor.labelColor)
        }

        controller.clockCells[1].mouseDown(with: try XCTUnwrap(mouseEvent(.leftMouseDown)))

        XCTAssertTrue(controller.isGroupHighlighted)
        for clockCell in controller.clockCells {
            XCTAssertTrue(clockCell.isGroupHighlighted)
            XCTAssertEqual(clockCell.textColor, NSColor.selectedMenuItemTextColor,
                           "The whole group is highlighted, so every clock must stay readable")
        }
    }

    func testHighlightLeavesTheCopiedIndicationAndWidthsAlone() throws {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        var pending: [() -> Void] = []
        let controller = ClockStripController(statusItem: item, schedule: { _, work in pending.append(work) })

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        controller.showCopiedFeedback(for: "Asia/Tokyo")
        let widthBefore = item.length
        let tokyoWidthBefore = controller.clockCells[2].intrinsicContentSize.width

        controller.clockCells[1].mouseDown(with: try XCTUnwrap(mouseEvent(.leftMouseDown)))

        XCTAssertTrue(controller.clockCells[2].isShowingCopiedFeedback,
                      "Only the clock that was copied says copied")
        XCTAssertFalse(controller.clockCells[0].isShowingCopiedFeedback)
        XCTAssertFalse(controller.clockCells[1].isShowingCopiedFeedback)
        XCTAssertEqual(item.length, widthBefore, "Highlighting must not resize the strip")
        XCTAssertEqual(controller.clockCells[2].intrinsicContentSize.width, tokyoWidthBefore)

        pending.removeFirst()()
        XCTAssertFalse(controller.clockCells[2].isShowingCopiedFeedback)
        XCTAssertTrue(controller.clockCells[2].isGroupHighlighted, "The press is still being held")
    }

    func testReorderingAndAddingDuringAPressKeepsOneConsistentHighlight() throws {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let controller = ClockStripController(statusItem: item)
        let paris = ClockStripEntry(identifier: "Europe/Paris", label: "Paris", time: "Tue 15:41")

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        let torontoCell = controller.clockCells[1]
        torontoCell.mouseDown(with: try XCTUnwrap(mouseEvent(.leftMouseDown)))

        controller.render(utcTitle: "12:00:01Z", additional: [tokyo, toronto, paris])

        XCTAssertTrue(controller.isGroupHighlighted, "The held clock is still there")
        XCTAssertTrue(controller.clockCells[2] === torontoCell)
        for clockCell in controller.clockCells {
            XCTAssertTrue(clockCell.isGroupHighlighted,
                          "A clock that appears mid-press joins the current state")
        }
    }

    func testRemovingTheHeldClockClearsTheHighlightEverywhere() throws {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let controller = ClockStripController(statusItem: item)

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        let tokyoCell = controller.clockCells[2]
        tokyoCell.mouseDown(with: try XCTUnwrap(mouseEvent(.leftMouseDown)))
        XCTAssertTrue(controller.isGroupHighlighted)

        controller.render(utcTitle: "12:00:01Z", additional: [toronto])

        XCTAssertFalse(controller.isGroupHighlighted,
                       "No mouse-up can arrive for a removed clock, so the highlight is dropped")
        XCTAssertFalse(tokyoCell.isGroupHighlighted, "The removed clock must not keep a stuck highlight")
        for clockCell in controller.clockCells {
            XCTAssertFalse(clockCell.isGroupHighlighted)
            XCTAssertEqual(clockCell.textColor, NSColor.labelColor)
        }

        // Re-adding the same zone starts from a clean state.
        controller.render(utcTitle: "12:00:02Z", additional: [toronto, tokyo])
        XCTAssertFalse(controller.isGroupHighlighted)
        XCTAssertTrue(controller.clockCells.allSatisfy { !$0.isGroupHighlighted })
    }

    func testDroppingToUTCOnlyDuringAPressClearsTheHighlight() throws {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let controller = ClockStripController(statusItem: item)

        controller.render(utcTitle: "12:00:00Z", additional: [toronto])
        let torontoCell = controller.clockCells[1]
        torontoCell.mouseDown(with: try XCTUnwrap(mouseEvent(.leftMouseDown)))
        XCTAssertTrue(controller.isGroupHighlighted)

        controller.render(utcTitle: "12:00:01Z", additional: [])

        XCTAssertFalse(controller.isGroupHighlighted)
        XCTAssertFalse(torontoCell.isGroupHighlighted)
    }

    func testShowingTheMenuHighlightsTheGroupOnlyWhileItIsUp() throws {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let controller = ClockStripController(statusItem: item)
        var highlightedDuringMenu: [Bool] = []
        controller.onOptionsMenu = { [weak controller] _ in
            guard let controller else { return }
            highlightedDuringMenu = controller.clockCells.map { $0.isGroupHighlighted }
        }

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        controller.clockCells[2].rightMouseDown(with: try XCTUnwrap(mouseEvent(.rightMouseDown)))

        XCTAssertEqual(highlightedDuringMenu, [true, true, true],
                       "The group is highlighted while the menu is up")
        XCTAssertFalse(controller.isGroupHighlighted, "Dismissing the menu releases the highlight")
        XCTAssertTrue(controller.clockCells.allSatisfy { !$0.isGroupHighlighted })
    }

    // MARK: - Native pointer events

    func testNativeLeftClickRoutesToTheClockUnderThePointer() throws {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        let controller = ClockStripController(statusItem: item)
        var copiedUTC = 0
        var copiedIdentifiers: [String] = []
        controller.onCopyUTC = { copiedUTC += 1 }
        controller.onCopyAdditional = { copiedIdentifiers.append($0) }

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        let window = try laidOutWindow(for: button)
        let tokyoCell = controller.clockCells[2]
        XCTAssertGreaterThan(tokyoCell.bounds.width, 0, "The strip must be laid out before hit testing")

        let point = center(of: tokyoCell)
        XCTAssertTrue(window.contentView?.hitTest(point) === tokyoCell,
                      "AppKit must hit-test the pointer onto Tokyo's own view")

        let down = try XCTUnwrap(mouseEvent(.leftMouseDown, at: point, windowNumber: window.windowNumber))
        NSApplication.shared.sendEvent(down)

        XCTAssertTrue(controller.isGroupHighlighted)
        XCTAssertTrue(controller.clockCells.allSatisfy { $0.isGroupHighlighted },
                      "Pressing one clock highlights the whole group readably")

        let up = try XCTUnwrap(mouseEvent(.leftMouseUp, at: point, windowNumber: window.windowNumber))
        NSApplication.shared.sendEvent(up)

        XCTAssertEqual(copiedIdentifiers, ["Asia/Tokyo"], "The clicked clock's own zone is copied")
        XCTAssertEqual(copiedUTC, 0)
        XCTAssertFalse(controller.isGroupHighlighted, "Releasing resets the highlight")
        XCTAssertTrue(controller.clockCells.allSatisfy { !$0.isGroupHighlighted })
        XCTAssertTrue(controller.clockCells.allSatisfy { $0.textColor == NSColor.labelColor })
    }

    func testNativeLeftClickOnUTCCopiesUTC() throws {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        let controller = ClockStripController(statusItem: item)
        var copiedUTC = 0
        var copiedIdentifiers: [String] = []
        controller.onCopyUTC = { copiedUTC += 1 }
        controller.onCopyAdditional = { copiedIdentifiers.append($0) }

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        let window = try laidOutWindow(for: button)
        let point = center(of: controller.clockCells[0])

        XCTAssertTrue(window.contentView?.hitTest(point) === controller.clockCells[0])
        NSApplication.shared.sendEvent(try XCTUnwrap(mouseEvent(.leftMouseDown, at: point, windowNumber: window.windowNumber)))
        NSApplication.shared.sendEvent(try XCTUnwrap(mouseEvent(.leftMouseUp, at: point, windowNumber: window.windowNumber)))

        XCTAssertEqual(copiedUTC, 1)
        XCTAssertTrue(copiedIdentifiers.isEmpty)
    }

    func testNativeDragOffCancelsTheCopyAndResetsTheHighlight() throws {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        let controller = ClockStripController(statusItem: item)
        var copies = 0
        controller.onCopyUTC = { copies += 1 }
        controller.onCopyAdditional = { _ in copies += 1 }

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        let window = try laidOutWindow(for: button)
        let torontoCell = controller.clockCells[1]
        let point = center(of: torontoCell)

        NSApplication.shared.sendEvent(try XCTUnwrap(mouseEvent(.leftMouseDown, at: point, windowNumber: window.windowNumber)))
        XCTAssertTrue(controller.isGroupHighlighted)

        // Released far outside the clock: a cancelled click, not a copy.
        let outside = NSPoint(x: point.x, y: point.y + torontoCell.bounds.height + 40)
        NSApplication.shared.sendEvent(try XCTUnwrap(mouseEvent(.leftMouseUp, at: outside, windowNumber: window.windowNumber)))

        XCTAssertEqual(copies, 0, "Dragging off the clock cancels the copy")
        XCTAssertFalse(controller.isGroupHighlighted, "A cancelled click still releases the highlight")
        XCTAssertTrue(controller.clockCells.allSatisfy { !$0.isGroupHighlighted })
    }

    func testNativeRightClickShowsTheMenuForThatClockOnce() throws {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        let controller = ClockStripController(statusItem: item)
        var anchors: [NSView] = []
        var copies = 0
        controller.onOptionsMenu = { anchors.append($0) }
        controller.onCopyUTC = { copies += 1 }
        controller.onCopyAdditional = { _ in copies += 1 }

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        let window = try laidOutWindow(for: button)
        let torontoCell = controller.clockCells[1]
        let point = center(of: torontoCell)

        NSApplication.shared.sendEvent(try XCTUnwrap(mouseEvent(.rightMouseDown, at: point, windowNumber: window.windowNumber)))
        NSApplication.shared.sendEvent(try XCTUnwrap(mouseEvent(.rightMouseUp, at: point, windowNumber: window.windowNumber)))

        XCTAssertEqual(anchors.count, 1, "Exactly one menu per secondary click")
        XCTAssertTrue(anchors.first === torontoCell, "The menu is anchored to the clicked clock")
        XCTAssertEqual(copies, 0)
        XCTAssertFalse(controller.isGroupHighlighted)
    }

    func testNativeControlClickShowsTheMenuWithoutCopying() throws {
        let item = makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        let controller = ClockStripController(statusItem: item)
        var anchors: [NSView] = []
        var copies = 0
        controller.onOptionsMenu = { anchors.append($0) }
        controller.onCopyUTC = { copies += 1 }
        controller.onCopyAdditional = { _ in copies += 1 }

        controller.render(utcTitle: "12:00:00Z", additional: [toronto, tokyo])
        let window = try laidOutWindow(for: button)
        let tokyoCell = controller.clockCells[2]
        let point = center(of: tokyoCell)

        NSApplication.shared.sendEvent(try XCTUnwrap(mouseEvent(.leftMouseDown,
                                                                at: point,
                                                                windowNumber: window.windowNumber,
                                                                modifiers: [.control])))
        NSApplication.shared.sendEvent(try XCTUnwrap(mouseEvent(.leftMouseUp,
                                                                at: point,
                                                                windowNumber: window.windowNumber,
                                                                modifiers: [.control])))

        XCTAssertEqual(anchors.count, 1)
        XCTAssertTrue(anchors.first === tokyoCell)
        XCTAssertEqual(copies, 0, "Control-click is a secondary click, never a copy")
        XCTAssertFalse(controller.isGroupHighlighted)
    }
}
