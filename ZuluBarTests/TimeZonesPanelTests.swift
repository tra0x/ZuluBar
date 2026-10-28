import XCTest
@testable import ZuluBar

/// AppKit panel, so the whole case is main-actor isolated. `setUp`/`tearDown`
/// are deliberately not overridden — each test builds its own panel.
///
/// Search/add tests run against the real bundled catalog (like
/// `TimeZoneCatalogTests`); the failure path is driven by injecting
/// `.unavailable` instead of corrupting the app bundle.
@MainActor
final class TimeZonesPanelTests: XCTestCase {

    // MARK: - Fixtures

    private let toronto = "America/Toronto"
    private let tokyo = "Asia/Tokyo"
    private let paris = "Europe/Paris"

    private func makePanel(clocks: [String] = [],
                           catalog: TimeZonesPanel.CatalogAvailability = .available,
                           now: @escaping () -> Date = Date.init) -> TimeZonesPanel {
        TimeZonesPanel(clocks: clocks.map { AdditionalClock(identifier: $0) },
                       catalog: catalog,
                       now: now)
    }

    private func identifiers(_ panel: TimeZonesPanel) -> [String] {
        panel.configuredClocks.map { $0.identifier }
    }

    /// Ambiguity in what is actually on screen. Hidden rows are skipped: the
    /// stack detaches them, so their frames are deliberately undetermined.
    private func hasAmbiguousLayout(_ view: NSView) -> Bool {
        guard !view.isHidden else { return false }
        return view.hasAmbiguousLayout || view.subviews.contains { hasAmbiguousLayout($0) }
    }

    /// A real Return key-down, so the panel's own key-equivalent dispatch is
    /// exercised rather than a stand-in.
    private func returnKeyEvent(for panel: NSPanel) -> NSEvent? {
        NSEvent.keyEvent(with: .keyDown,
                         location: .zero,
                         modifierFlags: [],
                         timestamp: ProcessInfo.processInfo.systemUptime,
                         windowNumber: panel.windowNumber,
                         context: nil,
                         characters: "\r",
                         charactersIgnoringModifiers: "\r",
                         isARepeat: false,
                         keyCode: 36)
    }

    // MARK: - Search

    func testEmptyQueryListsTheWholeCatalog() {
        let panel = makePanel()
        XCTAssertEqual(panel.visibleResults.count, TimeZoneCatalog.entries.count)
    }

    func testSearchFindsCityCountryAndLegacyAlias() {
        let panel = makePanel()

        panel.setSearchQuery("Toronto")
        XCTAssertTrue(panel.visibleResults.contains { $0.identifier == self.toronto })

        panel.setSearchQuery("Calcutta")
        XCTAssertTrue(panel.visibleResults.contains { $0.identifier == "Asia/Kolkata" },
                      "Legacy aliases must stay searchable")

        panel.setSearchQuery("Japan")
        XCTAssertTrue(panel.visibleResults.contains { $0.identifier == self.tokyo })
    }

    func testTypingAloneNeverAddsAClock() {
        let panel = makePanel()
        var emissions: [[AdditionalClock]] = []
        panel.onClocksChanged = { emissions.append($0) }

        panel.setSearchQuery("Toronto")
        panel.setSearchQuery("Tor")
        panel.setSearchQuery("")

        XCTAssertTrue(panel.configuredClocks.isEmpty)
        XCTAssertTrue(emissions.isEmpty)
        XCTAssertFalse(panel.isAddEnabled, "Add stays disabled until a result is selected")
    }

    func testSearchKeepsSelectionWhenTheRowSurvivesFiltering() {
        let panel = makePanel()

        panel.setSearchQuery("Toronto")
        XCTAssertTrue(panel.selectResult(identifier: toronto))
        panel.setSearchQuery("Toron")

        XCTAssertEqual(panel.selectedResultIdentifier, toronto)
        XCTAssertTrue(panel.isAddEnabled)
    }

    // MARK: - Add

    func testAddEmitsTheFullOrderedList() {
        let panel = makePanel()
        var emissions: [[AdditionalClock]] = []
        panel.onClocksChanged = { emissions.append($0) }

        panel.setSearchQuery("Toronto")
        XCTAssertFalse(panel.isAddEnabled)
        XCTAssertTrue(panel.selectResult(identifier: toronto))
        XCTAssertTrue(panel.isAddEnabled)
        panel.addSelectedResult()

        panel.setSearchQuery("Tokyo")
        XCTAssertTrue(panel.selectResult(identifier: tokyo))
        panel.addSelectedResult()

        XCTAssertEqual(identifiers(panel), [toronto, tokyo])
        XCTAssertEqual(emissions.count, 2)
        XCTAssertEqual(emissions.last?.map { $0.identifier }, [toronto, tokyo])
    }

    func testAddSelectsTheNewClockAndMarksTheResultRow() {
        let panel = makePanel()

        panel.setSearchQuery("Toronto")
        XCTAssertTrue(panel.selectResult(identifier: toronto))
        panel.addSelectedResult()

        XCTAssertEqual(panel.selectedConfiguredIdentifier, toronto)
        XCTAssertFalse(panel.isAddEnabled, "The selected result is now configured")
        XCTAssertTrue(panel.isRemoveEnabled)
    }

    func testExactDuplicateIdentifierCannotBeAddedTwice() {
        let panel = makePanel(clocks: [toronto])
        var emissions: [[AdditionalClock]] = []
        panel.onClocksChanged = { emissions.append($0) }

        panel.setSearchQuery("Toronto")
        XCTAssertTrue(panel.selectResult(identifier: toronto))
        XCTAssertFalse(panel.isAddEnabled)
        panel.addSelectedResult()

        XCTAssertEqual(identifiers(panel), [toronto])
        XCTAssertTrue(emissions.isEmpty)
    }

    func testDistinctCitiesSharingAnOffsetAreBothAddable() {
        let panel = makePanel()

        panel.setSearchQuery("Toronto")
        XCTAssertTrue(panel.selectResult(identifier: toronto))
        panel.addSelectedResult()

        panel.setSearchQuery("Montreal")
        XCTAssertTrue(panel.selectResult(identifier: "America/Montreal"))
        XCTAssertTrue(panel.isAddEnabled)
        panel.addSelectedResult()

        XCTAssertEqual(identifiers(panel), [toronto, "America/Montreal"])
    }

    // MARK: - Remove

    func testRemoveEmitsAndKeepsAUsableSelection() {
        let panel = makePanel(clocks: [toronto, tokyo, paris])
        var emissions: [[AdditionalClock]] = []
        panel.onClocksChanged = { emissions.append($0) }

        XCTAssertTrue(panel.selectConfiguredClock(identifier: tokyo))
        panel.removeSelectedClock()

        XCTAssertEqual(identifiers(panel), [toronto, paris])
        XCTAssertEqual(panel.selectedConfiguredIdentifier, paris, "Selection slides to the next clock")
        XCTAssertEqual(emissions.map { $0.map { $0.identifier } }, [[toronto, paris]])
    }

    func testRemovingTheLastClockSelectsTheNewLastOne() {
        let panel = makePanel(clocks: [toronto, tokyo])

        XCTAssertTrue(panel.selectConfiguredClock(identifier: tokyo))
        panel.removeSelectedClock()

        XCTAssertEqual(identifiers(panel), [toronto])
        XCTAssertEqual(panel.selectedConfiguredIdentifier, toronto)
    }

    func testRemovingTheOnlyClockClearsSelectionAndDisablesActions() {
        let panel = makePanel(clocks: [toronto])

        XCTAssertTrue(panel.selectConfiguredClock(identifier: toronto))
        panel.removeSelectedClock()

        XCTAssertTrue(panel.configuredClocks.isEmpty)
        XCTAssertNil(panel.selectedConfiguredIdentifier)
        XCTAssertFalse(panel.isRemoveEnabled)
        XCTAssertFalse(panel.isMoveUpEnabled)
        XCTAssertFalse(panel.isMoveDownEnabled)
    }

    func testRemoveWithoutSelectionDoesNothing() {
        let panel = makePanel(clocks: [toronto])
        var emissions = 0
        panel.onClocksChanged = { _ in emissions += 1 }

        XCTAssertFalse(panel.isRemoveEnabled)
        panel.removeSelectedClock()

        XCTAssertEqual(identifiers(panel), [toronto])
        XCTAssertEqual(emissions, 0)
    }

    // MARK: - Reorder

    func testMoveUpAndDownReorderAndKeepTheMovedClockSelected() {
        let panel = makePanel(clocks: [toronto, tokyo, paris])
        var emissions: [[String]] = []
        panel.onClocksChanged = { emissions.append($0.map { $0.identifier }) }

        XCTAssertTrue(panel.selectConfiguredClock(identifier: paris))
        panel.moveSelectedClockUp()

        XCTAssertEqual(identifiers(panel), [toronto, paris, tokyo])
        XCTAssertEqual(panel.selectedConfiguredIdentifier, paris)

        panel.moveSelectedClockDown()

        XCTAssertEqual(identifiers(panel), [toronto, tokyo, paris])
        XCTAssertEqual(panel.selectedConfiguredIdentifier, paris)
        XCTAssertEqual(emissions, [[toronto, paris, tokyo], [toronto, tokyo, paris]])
    }

    func testReorderButtonsAreDisabledAtTheEdges() {
        let panel = makePanel(clocks: [toronto, tokyo])

        XCTAssertTrue(panel.selectConfiguredClock(identifier: toronto))
        XCTAssertFalse(panel.isMoveUpEnabled)
        XCTAssertTrue(panel.isMoveDownEnabled)

        XCTAssertTrue(panel.selectConfiguredClock(identifier: tokyo))
        XCTAssertTrue(panel.isMoveUpEnabled)
        XCTAssertFalse(panel.isMoveDownEnabled)
    }

    func testSingleClockCannotBeReordered() {
        let panel = makePanel(clocks: [toronto])

        XCTAssertTrue(panel.selectConfiguredClock(identifier: toronto))
        XCTAssertFalse(panel.isMoveUpEnabled)
        XCTAssertFalse(panel.isMoveDownEnabled)
    }

    // MARK: - Fixed UTC row

    func testUTCRowIsListedFirstAndIsNotSelectable() {
        let panel = makePanel(clocks: [toronto, tokyo])

        XCTAssertEqual(panel.configuredRowCount, 3, "UTC occupies a fixed extra row")
        XCTAssertFalse(panel.canSelectConfiguredRow(0))
        XCTAssertTrue(panel.canSelectConfiguredRow(1))
        XCTAssertTrue(panel.canSelectConfiguredRow(2))
    }

    func testUTCRowIsNotSelectableEvenWithNoExtraClocks() {
        let panel = makePanel()

        XCTAssertEqual(panel.configuredRowCount, 1)
        XCTAssertFalse(panel.canSelectConfiguredRow(0))
        XCTAssertNil(panel.selectedConfiguredIdentifier)
        XCTAssertFalse(panel.isRemoveEnabled)
    }

    // MARK: - Owner-driven refresh

    func testUpdateReplacesClocksWithoutEmittingOrResettingSearch() {
        let panel = makePanel(clocks: [toronto])
        var emissions = 0
        panel.onClocksChanged = { _ in emissions += 1 }

        panel.setSearchQuery("Tokyo")
        panel.update(clocks: [AdditionalClock(identifier: toronto), AdditionalClock(identifier: tokyo)])

        XCTAssertEqual(identifiers(panel), [toronto, tokyo])
        XCTAssertEqual(panel.searchQuery, "Tokyo", "A refresh must not wipe the typed query")
        XCTAssertEqual(emissions, 0, "update(clocks:) is the owner talking, not a user change")
    }

    func testUpdateKeepsSelectionWhenTheClockSurvives() {
        let panel = makePanel(clocks: [toronto, tokyo])

        XCTAssertTrue(panel.selectConfiguredClock(identifier: tokyo))
        panel.update(clocks: [AdditionalClock(identifier: tokyo)])

        XCTAssertEqual(panel.selectedConfiguredIdentifier, tokyo)
        XCTAssertTrue(panel.isRemoveEnabled)
        XCTAssertFalse(panel.isMoveUpEnabled)
    }

    func testUpdateClearsSelectionWhenTheClockIsGone() {
        let panel = makePanel(clocks: [toronto, tokyo])

        XCTAssertTrue(panel.selectConfiguredClock(identifier: tokyo))
        panel.update(clocks: [AdditionalClock(identifier: toronto)])

        XCTAssertNil(panel.selectedConfiguredIdentifier)
        XCTAssertFalse(panel.isRemoveEnabled)
    }

    func testUpdateKeepsStaleShortcutsOutOfTheResultMarkers() {
        let panel = makePanel()

        panel.setSearchQuery("Toronto")
        XCTAssertTrue(panel.selectResult(identifier: toronto))
        XCTAssertTrue(panel.isAddEnabled)

        panel.update(clocks: [AdditionalClock(identifier: toronto)])
        XCTAssertFalse(panel.isAddEnabled, "A clock added elsewhere must disable Add here too")

        panel.update(clocks: [])
        XCTAssertTrue(panel.isAddEnabled)
    }

    // MARK: - Catalog failure

    func testCatalogFailureExplainsItselfAndDisablesAdding() {
        let panel = makePanel(clocks: [toronto], catalog: .unavailable(.resourceMissing))

        let message = panel.catalogErrorMessage
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("ZuluBar") == true)
        XCTAssertTrue(message?.lowercased().contains("time zone list") == true,
                      "The message should say what is missing, got: \(message ?? "nil")")
        XCTAssertFalse(panel.isSearchEnabled)
        XCTAssertFalse(panel.isAddEnabled)
        XCTAssertTrue(panel.visibleResults.isEmpty)
        XCTAssertTrue(panel.setSearchQuery("Toronto").isEmpty, "No silent empty picker to click through")
        XCTAssertFalse(panel.isAddEnabled)
    }

    func testCatalogFailureStillAllowsManagingExistingClocks() {
        let panel = makePanel(clocks: [toronto, tokyo, paris], catalog: .unavailable(.invalidData("bad json")))
        var emissions: [[String]] = []
        panel.onClocksChanged = { emissions.append($0.map { $0.identifier }) }

        XCTAssertEqual(panel.configuredRowCount, 4)
        XCTAssertTrue(panel.selectConfiguredClock(identifier: paris))
        panel.moveSelectedClockUp()
        XCTAssertEqual(identifiers(panel), [toronto, paris, tokyo])

        panel.removeSelectedClock()
        XCTAssertEqual(identifiers(panel), [toronto, tokyo])
        XCTAssertEqual(emissions, [[toronto, paris, tokyo], [toronto, tokyo]])
    }

    func testCatalogFailureMessageNamesTheDecodingDetail() {
        let panel = makePanel(catalog: .unavailable(.invalidData("could not decode JSON envelope")))
        XCTAssertTrue(panel.catalogErrorMessage?.contains("could not decode JSON envelope") == true)
    }

    func testCatalogFailureHidesTheWholeAddAreaAndLaysOutUnambiguously() throws {
        let panel = makePanel(clocks: [toronto], catalog: .unavailable(.resourceMissing))
        let contentView = try XCTUnwrap(panel.contentView)

        XCTAssertFalse(panel.isAddRowVisible,
                       "An Add button with nothing to add is an orphan, not a disabled control")
        XCTAssertFalse(panel.isSearchEnabled)

        contentView.layoutSubtreeIfNeeded()
        XCTAssertFalse(hasAmbiguousLayout(contentView),
                       "The catalog-failure layout must be fully determined")
        // The explained error and the existing clocks are what is left.
        XCTAssertNotNil(panel.catalogErrorMessage)
        XCTAssertEqual(panel.configuredRowCount, 2)
        XCTAssertTrue(panel.selectConfiguredClock(identifier: toronto))
        XCTAssertTrue(panel.isRemoveEnabled)
    }

    func testAvailableCatalogKeepsTheAddRowVisibleAndUnambiguous() throws {
        let panel = makePanel(clocks: [toronto])
        let contentView = try XCTUnwrap(panel.contentView)

        XCTAssertTrue(panel.isAddRowVisible)
        XCTAssertTrue(panel.isSearchEnabled)

        contentView.layoutSubtreeIfNeeded()
        XCTAssertFalse(hasAmbiguousLayout(contentView))
    }

    // MARK: - Existing labels

    func testConfiguredLabelsAreShownAndSurviveReordering() {
        let labelled = AdditionalClock(identifier: toronto, label: "HQ")
        let panel = TimeZonesPanel(clocks: [labelled, AdditionalClock(identifier: tokyo)],
                                   catalog: .available,
                                   now: Date.init)

        XCTAssertEqual(panel.title(for: labelled), "HQ")
        XCTAssertEqual(panel.title(for: AdditionalClock(identifier: tokyo)), "Tokyo",
                       "Unlabelled clocks fall back to the catalog city")

        XCTAssertTrue(panel.selectConfiguredClock(identifier: toronto))
        panel.moveSelectedClockDown()

        XCTAssertEqual(identifiers(panel), [tokyo, toronto])
        XCTAssertEqual(panel.configuredClocks.last?.label, "HQ", "A configured label must survive a reorder")
    }

    func testLabelsStillDisplayWhenTheCatalogIsUnavailable() {
        let panel = makePanel(catalog: .unavailable(.resourceMissing))

        XCTAssertEqual(panel.title(for: AdditionalClock(identifier: toronto, label: "HQ")), "HQ")
        XCTAssertEqual(panel.title(for: AdditionalClock(identifier: toronto, label: "   ")), toronto,
                       "A blank label falls back to the identifier, not an empty row")
        XCTAssertEqual(panel.title(for: AdditionalClock(identifier: toronto)), toronto)
    }

    // MARK: - Secondary row text

    func testOffsetsComeFromFoundationAtTheGivenMoment() {
        // 2026-01-15T12:00:00Z — northern winter, so New York is on EST.
        let winter = Date(timeIntervalSince1970: 1_768_478_400)
        let panel = makePanel(now: { winter })

        XCTAssertEqual(panel.offsetDescription(for: "America/New_York"), "UTC-05:00")
        XCTAssertEqual(panel.offsetDescription(for: "Asia/Kolkata"), "UTC+05:30")
        XCTAssertEqual(panel.offsetDescription(for: "Europe/London"), "UTC+00:00")
        XCTAssertNil(panel.offsetDescription(for: "Not/AZone"))
    }

    func testOffsetFollowsDaylightSavingAtTheGivenMoment() {
        // 2026-07-15T12:00:00Z — northern summer, so New York is on EDT.
        let summer = Date(timeIntervalSince1970: 1_784_116_800)
        let panel = makePanel(now: { summer })

        XCTAssertEqual(panel.offsetDescription(for: "America/New_York"), "UTC-04:00")
    }

    func testSubtitleOmitsCountryWhenTheCatalogHasNone() {
        let winter = Date(timeIntervalSince1970: 1_768_478_400)
        let panel = makePanel(now: { winter })

        let withoutCountry = panel.subtitle(for: "America/New_York", countryCodes: [])
        let withCountry = panel.subtitle(for: "America/New_York", countryCodes: ["US"])

        XCTAssertEqual(withoutCountry, "America/New_York · UTC-05:00", "No invented country metadata")
        XCTAssertEqual(withCountry.components(separatedBy: " · ").count, 3)
        XCTAssertTrue(withCountry.hasPrefix("America/New_York · "))
        XCTAssertTrue(withCountry.hasSuffix(" · UTC-05:00"))
    }

    // MARK: - Panel lifecycle

    func testPanelIsOwnerRetainedAndClosesOnEscape() {
        let panel = makePanel(clocks: [toronto])

        XCTAssertFalse(panel.isReleasedWhenClosed, "The owner keeps the panel alive between openings")

        panel.orderFront(nil)
        panel.cancelOperation(nil)

        XCTAssertFalse(panel.isVisible)
    }

    func testDoneClosesThePanelWithoutChangingClocks() {
        let panel = makePanel(clocks: [toronto])
        var emissions = 0
        panel.onClocksChanged = { _ in emissions += 1 }

        panel.orderFront(nil)
        panel.closePanel()

        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(identifiers(panel), [toronto])
        XCTAssertEqual(emissions, 0)
    }

    func testReturnWhileSearchingNeitherClosesThePanelNorAdds() throws {
        let panel = makePanel()
        var emissions = 0
        panel.onClocksChanged = { _ in emissions += 1 }

        panel.makeKeyAndOrderFront(nil)
        XCTAssertTrue(panel.focusSearchField())
        XCTAssertTrue(panel.isSearchFieldFocused, "The search field holds focus while typing")
        panel.setSearchQuery("Toronto")
        XCTAssertTrue(panel.selectResult(identifier: toronto))
        XCTAssertTrue(panel.isAddEnabled)

        let returnKey = try XCTUnwrap(returnKeyEvent(for: panel))
        XCTAssertFalse(panel.performKeyEquivalent(with: returnKey),
                       "No control may claim Return while the search field is focused")

        XCTAssertTrue(panel.isVisible, "Return must not close the panel while searching")
        XCTAssertTrue(panel.configuredClocks.isEmpty, "Return must not add a clock")
        XCTAssertEqual(emissions, 0)
        XCTAssertEqual(panel.searchQuery, "Toronto", "The typed query survives Return")

        panel.closePanel()
    }

    func testReturnWithoutSearchFocusStillDoesNotClosePanel() throws {
        let panel = makePanel(clocks: [toronto])

        panel.makeKeyAndOrderFront(nil)
        XCTAssertTrue(panel.selectConfiguredClock(identifier: toronto))

        let returnKey = try XCTUnwrap(returnKeyEvent(for: panel))
        XCTAssertFalse(panel.performKeyEquivalent(with: returnKey))

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(identifiers(panel), [toronto], "Return is not a shortcut for any action here")

        // Escape and Done remain the ways out.
        panel.cancelOperation(nil)
        XCTAssertFalse(panel.isVisible)
    }
}
