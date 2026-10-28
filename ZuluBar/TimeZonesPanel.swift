import Cocoa

/// A small floating panel for choosing which extra city clocks appear next to
/// UTC in the menu bar.
///
/// The panel is pure UI: it reports the full ordered list through
/// `onClocksChanged` after every valid change and never writes settings,
/// retains itself, activates the app or shows itself. The owner decides when
/// to show, center and persist.
///
/// Usage:
/// ```swift
/// let panel = TimeZonesPanel(clocks: settings.additionalClocks)
/// panel.onClocksChanged = { [weak self] clocks in self?.apply(clocks) }
/// NSApp.activate(ignoringOtherApps: true)
/// panel.makeKeyAndOrderFront(nil)
/// panel.center()
/// ```
final class TimeZonesPanel: NSPanel {

    /// Whether the bundled searchable catalog is usable. Resolved once per
    /// panel so a missing or corrupt resource degrades into an explained,
    /// add-disabled picker instead of an empty "successful" one — the already
    /// configured clocks stay removable and reorderable either way.
    enum CatalogAvailability {
        case available
        case unavailable(TimeZoneCatalog.LoadError)

        static func resolve(bundle: Bundle = .main) -> CatalogAvailability {
            switch TimeZoneCatalog.load(bundle: bundle) {
            case .success:
                return .available
            case .failure(let error):
                return .unavailable(error)
            }
        }
    }

    // MARK: - Public

    /// Called immediately after a valid add, remove or reorder, with the full
    /// ordered extra-clock list. Never called by `update(clocks:)`.
    var onClocksChanged: (([AdditionalClock]) -> Void)?

    // MARK: - Private state

    private let catalog: CatalogAvailability
    private let now: () -> Date

    private var configured: [AdditionalClock]
    private var results: [TimeZoneCatalogEntry] = []

    private let searchField = NSSearchField()
    private let resultsTable = NSTableView()
    private let configuredTable = NSTableView()
    private let resultsScrollView = NSScrollView()
    private let configuredScrollView = NSScrollView()
    private let catalogErrorLabel = NSTextField(labelWithString: "")
    private let addRow = NSStackView()
    private let addButton = NSButton()
    private let removeButton = NSButton()
    private let moveUpButton = NSButton()
    private let moveDownButton = NSButton()
    private let doneButton = NSButton()

    private enum Layout {
        static let width: CGFloat = 520
        static let height: CGFloat = 470
        static let horizontalInset: CGFloat = 20
        static let resultsHeight: CGFloat = 168
        static let configuredHeight: CGFloat = 124
        static let rowHeight: CGFloat = 34
    }

    /// Fixed first row of the configured list. UTC is always shown first and
    /// can be neither removed nor reordered.
    private let utcRowCount = 1

    private static let cellIdentifier = NSUserInterfaceItemIdentifier("TimeZonesPanelRow")

    // MARK: - Init

    init(clocks: [AdditionalClock],
         catalog: CatalogAvailability = .resolve(),
         now: @escaping () -> Date = Date.init) {
        self.configured = clocks
        self.catalog = catalog
        self.now = now
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = "Additional Clocks"
        isFloatingPanel = true
        level = .floating
        isReleasedWhenClosed = false
        setupUI()
        refreshResults()
        reloadConfigured(selecting: nil)
        updateControlStates()
    }

    // MARK: - Public API

    /// Replaces the configured list from the owner — e.g. after it persisted a
    /// change elsewhere. Keeps the typed search text, and keeps the selection
    /// when that clock is still configured.
    func update(clocks: [AdditionalClock]) {
        let previousSelection = selectedConfiguredIdentifier
        configured = clocks
        reloadConfigured(selecting: previousSelection)
        refreshResultMarkers()
        updateControlStates()
    }

    // MARK: - UI setup

    private func setupUI() {
        guard let contentView else { return }

        searchField.placeholderString = "Search city, time zone, or country"
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)
        searchField.sendsWholeSearchString = false
        searchField.setAccessibilityLabel("Search time zones")

        configure(table: resultsTable, in: resultsScrollView, accessibilityLabel: "Time zone search results")
        resultsTable.target = self
        resultsTable.doubleAction = #selector(addSelectedResult)
        configure(table: configuredTable, in: configuredScrollView, accessibilityLabel: "Your clocks")

        catalogErrorLabel.font = .systemFont(ofSize: 11)
        catalogErrorLabel.textColor = .systemRed
        catalogErrorLabel.lineBreakMode = .byWordWrapping
        catalogErrorLabel.maximumNumberOfLines = 0
        catalogErrorLabel.preferredMaxLayoutWidth = Layout.width - 2 * Layout.horizontalInset
        catalogErrorLabel.stringValue = catalogErrorMessage ?? ""
        catalogErrorLabel.isHidden = catalogErrorMessage == nil

        let isCatalogAvailable = catalogErrorMessage == nil
        searchField.isEnabled = isCatalogAvailable
        resultsScrollView.isHidden = !isCatalogAvailable
        searchField.isHidden = !isCatalogAvailable

        configure(button: addButton, title: "Add", action: #selector(addSelectedResult))
        configure(button: removeButton, title: "Remove", action: #selector(removeSelectedClock))
        configure(button: moveUpButton, title: "Move Up", action: #selector(moveSelectedClockUp))
        configure(button: moveDownButton, title: "Move Down", action: #selector(moveSelectedClockDown))
        // Deliberately no Return key equivalent: Return belongs to the search
        // field while typing, and must never close the panel or add a clock.
        // Escape and the Done button are the ways out.
        configure(button: doneButton, title: "Done", action: #selector(closePanel))

        let yourClocksLabel = NSTextField(labelWithString: "Your clocks")
        yourClocksLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        let footnote = NSTextField(labelWithString: "UTC is always first. Every extra clock takes up space in the menu bar.")
        footnote.font = .systemFont(ofSize: 11)
        footnote.textColor = .secondaryLabelColor
        footnote.lineBreakMode = .byWordWrapping
        footnote.maximumNumberOfLines = 0
        footnote.preferredMaxLayoutWidth = Layout.width - 2 * Layout.horizontalInset

        addRow.orientation = .horizontal
        addRow.spacing = 8
        addRow.addView(addButton, in: .leading)
        // Nothing can be added without the catalog, so the row goes with the
        // search and results rather than sitting there permanently disabled.
        addRow.isHidden = !isCatalogAvailable

        let clockActionsRow = NSStackView()
        clockActionsRow.orientation = .horizontal
        clockActionsRow.spacing = 8
        clockActionsRow.addView(removeButton, in: .leading)
        clockActionsRow.addView(moveUpButton, in: .leading)
        clockActionsRow.addView(moveDownButton, in: .leading)

        let doneRow = NSStackView()
        doneRow.orientation = .horizontal
        doneRow.addView(doneButton, in: .trailing)

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 16,
                                       left: Layout.horizontalInset,
                                       bottom: 16,
                                       right: Layout.horizontalInset)
        root.translatesAutoresizingMaskIntoConstraints = false
        // `detachesHiddenViews` keeps the hidden search/results area from
        // leaving a gap in the catalog-unavailable layout.
        root.detachesHiddenViews = true
        let rows: [NSView] = [searchField, resultsScrollView, addRow, catalogErrorLabel,
                              yourClocksLabel, configuredScrollView, clockActionsRow, footnote, doneRow]
        for view in rows {
            root.addView(view, in: .top)
        }
        contentView.addSubview(root)

        var constraints: [NSLayoutConstraint] = [
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            resultsScrollView.heightAnchor.constraint(equalToConstant: Layout.resultsHeight),
            configuredScrollView.heightAnchor.constraint(equalToConstant: Layout.configuredHeight),
            doneRow.heightAnchor.constraint(equalTo: doneButton.heightAnchor),
        ]
        // Every row spans the panel, so the button rows' trailing gravity and
        // the wrapping labels get the full content width.
        for view in rows {
            constraints.append(view.widthAnchor.constraint(equalTo: root.widthAnchor,
                                                           constant: -2 * Layout.horizontalInset))
        }
        NSLayoutConstraint.activate(constraints)

        initialFirstResponder = isCatalogAvailable ? searchField : configuredTable
    }

    private func configure(table: NSTableView, in scrollView: NSScrollView, accessibilityLabel: String) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("zone"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = Layout.rowHeight
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.style = .inset
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel(accessibilityLabel)

        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
    }

    private func configure(button: NSButton, title: String, action: Selector) {
        button.title = title
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
    }

    // MARK: - Test/owner-visible state

    var configuredClocks: [AdditionalClock] { configured }

    var visibleResults: [TimeZoneCatalogEntry] { results }

    var searchQuery: String { searchField.stringValue }

    var isSearchEnabled: Bool { searchField.isEnabled }

    var isAddEnabled: Bool { addButton.isEnabled }

    /// False when the catalog failed, where an Add row would be an orphan: the
    /// containing stack detaches it, so no empty gap is left behind.
    var isAddRowVisible: Bool { !addRow.isHidden }

    /// Moves keyboard focus to the search field, as opening the panel does.
    @discardableResult
    func focusSearchField() -> Bool {
        makeFirstResponder(searchField)
    }

    /// True while the search field — or its field editor, once it is being
    /// typed into — holds keyboard focus.
    var isSearchFieldFocused: Bool {
        guard let responder = firstResponder else { return false }
        return responder === searchField || responder === searchField.currentEditor()
    }

    var isRemoveEnabled: Bool { removeButton.isEnabled }

    var isMoveUpEnabled: Bool { moveUpButton.isEnabled }

    var isMoveDownEnabled: Bool { moveDownButton.isEnabled }

    /// Non-nil when the bundled catalog could not be loaded.
    var catalogErrorMessage: String? {
        switch catalog {
        case .available:
            return nil
        case .unavailable(let error):
            let shared = "New clocks can't be added right now. Reinstalling ZuluBar restores the list. "
                + "Clocks you already added can still be removed or reordered below."
            switch error {
            case .resourceMissing:
                return "ZuluBar can't find its built-in time zone list. " + shared
            case .invalidData(let detail):
                return "ZuluBar can't read its built-in time zone list (\(detail)). " + shared
            }
        }
    }

    var selectedResultIdentifier: String? {
        let row = resultsTable.selectedRow
        guard results.indices.contains(row) else { return nil }
        return results[row].identifier
    }

    var selectedConfiguredIdentifier: String? {
        guard let index = selectedConfiguredIndex else { return nil }
        return configured[index].identifier
    }

    /// Row count of the configured list, including the fixed UTC row.
    var configuredRowCount: Int { configured.count + utcRowCount }

    /// The fixed UTC row is readable but not selectable, so it can never be
    /// removed or reordered.
    func canSelectConfiguredRow(_ row: Int) -> Bool { row >= utcRowCount }

    @discardableResult
    func setSearchQuery(_ query: String) -> [TimeZoneCatalogEntry] {
        searchField.stringValue = query
        refreshResults()
        return results
    }

    @discardableResult
    func selectResult(identifier: String) -> Bool {
        guard let row = results.firstIndex(where: { $0.identifier == identifier }) else { return false }
        resultsTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        updateControlStates()
        return true
    }

    @discardableResult
    func selectConfiguredClock(identifier: String) -> Bool {
        guard let index = configured.firstIndex(where: { $0.identifier == identifier }) else { return false }
        let row = index + utcRowCount
        configuredTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        updateControlStates()
        return true
    }

    // MARK: - Search

    @objc private func searchFieldChanged() {
        // Typing and Return only filter — adding a clock is always an
        // explicit Add, double-click or press on a selected row.
        refreshResults()
    }

    private func refreshResults() {
        let previousSelection = selectedResultIdentifier
        switch catalog {
        case .available:
            results = TimeZoneCatalog.search(searchField.stringValue)
        case .unavailable:
            results = []
        }
        resultsTable.reloadData()
        // Keep the selected zone selected when it survived the new query;
        // otherwise drop the selection instead of leaving the old row index
        // pointing at an unrelated zone.
        if let previousSelection,
           let row = results.firstIndex(where: { $0.identifier == previousSelection }) {
            resultsTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            resultsTable.deselectAll(nil)
        }
        updateControlStates()
    }

    /// Refreshes result row text (the "Added" marker) without disturbing the
    /// current selection.
    private func refreshResultMarkers() {
        guard !results.isEmpty else { return }
        resultsTable.reloadData(forRowIndexes: IndexSet(integersIn: 0..<results.count),
                                columnIndexes: IndexSet(integer: 0))
    }

    // MARK: - Actions

    @objc func addSelectedResult() {
        guard case .available = catalog else { return }
        let row = resultsTable.selectedRow
        guard results.indices.contains(row) else { return }
        let entry = results[row]
        guard !configured.contains(where: { $0.identifier == entry.identifier }) else { return }

        configured.append(AdditionalClock(identifier: entry.identifier))
        reloadConfigured(selecting: entry.identifier)
        refreshResultMarkers()
        updateControlStates()
        onClocksChanged?(configured)
    }

    @objc func removeSelectedClock() {
        guard let index = selectedConfiguredIndex else { return }
        configured.remove(at: index)

        // Keep a usable selection: the clock that slid into this slot, or the
        // new last one.
        let nextSelection = configured.indices.contains(index)
            ? configured[index].identifier
            : configured.last?.identifier
        reloadConfigured(selecting: nextSelection)
        refreshResultMarkers()
        updateControlStates()
        onClocksChanged?(configured)
    }

    @objc func moveSelectedClockUp() {
        guard let index = selectedConfiguredIndex, index > 0 else { return }
        move(from: index, to: index - 1)
    }

    @objc func moveSelectedClockDown() {
        guard let index = selectedConfiguredIndex, index < configured.count - 1 else { return }
        move(from: index, to: index + 1)
    }

    private func move(from index: Int, to destination: Int) {
        let moved = configured.remove(at: index)
        configured.insert(moved, at: destination)
        reloadConfigured(selecting: moved.identifier)
        updateControlStates()
        onClocksChanged?(configured)
    }

    @objc func closePanel() {
        orderOut(nil)
    }

    override func cancelOperation(_ sender: Any?) {
        closePanel()
    }

    // MARK: - Configured list

    private var selectedConfiguredIndex: Int? {
        let row = configuredTable.selectedRow
        guard canSelectConfiguredRow(row) else { return nil }
        let index = row - utcRowCount
        return configured.indices.contains(index) ? index : nil
    }

    private func reloadConfigured(selecting identifier: String?) {
        configuredTable.reloadData()
        guard let identifier,
              let index = configured.firstIndex(where: { $0.identifier == identifier }) else {
            configuredTable.deselectAll(nil)
            return
        }
        configuredTable.selectRowIndexes(IndexSet(integer: index + utcRowCount), byExtendingSelection: false)
    }

    private func updateControlStates() {
        let isCatalogAvailable = catalogErrorMessage == nil
        let selectedResultIsNew = selectedResultIdentifier.map { identifier in
            !configured.contains(where: { $0.identifier == identifier })
        } ?? false
        addButton.isEnabled = isCatalogAvailable && selectedResultIsNew

        let index = selectedConfiguredIndex
        removeButton.isEnabled = index != nil
        moveUpButton.isEnabled = (index ?? 0) > 0
        moveDownButton.isEnabled = index.map { $0 < configured.count - 1 } ?? false
    }

    // MARK: - Row text

    /// Display name for a configured clock. Falls back to the user's label or
    /// the raw identifier when the catalog is unavailable, since
    /// `AdditionalClock.displayName` reads the catalog. Internal so tests can
    /// assert both paths.
    func title(for clock: AdditionalClock) -> String {
        switch catalog {
        case .available:
            return clock.displayName
        case .unavailable:
            let trimmed = (clock.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? clock.identifier : trimmed
        }
    }

    /// Secondary row text: identifier, country when the catalog knows one, and
    /// the zone's current offset. Internal so tests can assert the composition
    /// against an injected `now`.
    func subtitle(for identifier: String, countryCodes: [String]) -> String {
        var parts = [identifier]
        // Country only when the catalog actually knows one — never invented.
        if let code = countryCodes.first,
           let country = Locale.current.localizedString(forRegionCode: code) {
            parts.append(country)
        }
        if let offset = offsetDescription(for: identifier) {
            parts.append(offset)
        }
        return parts.joined(separator: " · ")
    }

    /// Current offset straight from Foundation, never from stored metadata.
    func offsetDescription(for identifier: String) -> String? {
        guard let timeZone = TimeZone(identifier: identifier) else { return nil }
        let seconds = timeZone.secondsFromGMT(for: now())
        let sign = seconds < 0 ? "-" : "+"
        let magnitude = abs(seconds)
        return String(format: "UTC%@%02d:%02d", sign, magnitude / 3600, (magnitude % 3600) / 60)
    }

    private func makeRowView(in tableView: NSTableView, title: String, subtitle: String, dimmed: Bool) -> NSView {
        let view = tableView.makeView(withIdentifier: Self.cellIdentifier, owner: self) as? TwoLineRowView
            ?? TwoLineRowView(identifier: Self.cellIdentifier)
        view.configure(title: title, subtitle: subtitle, dimmed: dimmed)
        return view
    }
}

// MARK: - Table data

extension TimeZonesPanel: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === resultsTable ? results.count : configuredRowCount
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === resultsTable {
            guard results.indices.contains(row) else { return nil }
            let entry = results[row]
            let isConfigured = configured.contains { $0.identifier == entry.identifier }
            var detail = subtitle(for: entry.identifier, countryCodes: entry.countryCodes)
            if isConfigured { detail += " · Added" }
            let view = makeRowView(in: tableView, title: entry.city, subtitle: detail, dimmed: isConfigured)
            view.toolTip = "\(entry.city) · \(detail)"
            return view
        }

        if row < utcRowCount {
            let view = makeRowView(in: tableView,
                                   title: "UTC",
                                   subtitle: "Always shown first · can't be removed or moved",
                                   dimmed: true)
            view.toolTip = "Coordinated Universal Time is always the first clock."
            return view
        }

        let index = row - utcRowCount
        guard configured.indices.contains(index) else { return nil }
        let clock = configured[index]
        // Country metadata is catalog-backed, so it is only consulted when the
        // catalog actually loaded.
        var countryCodes: [String] = []
        if case .available = catalog {
            countryCodes = TimeZoneCatalog.entry(for: clock.identifier)?.countryCodes ?? []
        }
        let detail = subtitle(for: clock.identifier, countryCodes: countryCodes)
        let view = makeRowView(in: tableView, title: title(for: clock), subtitle: detail, dimmed: false)
        view.toolTip = "\(title(for: clock)) · \(detail)"
        return view
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard tableView === configuredTable else { return true }
        return canSelectConfiguredRow(row)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateControlStates()
    }
}

// MARK: - Search field

extension TimeZonesPanel: NSSearchFieldDelegate {

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSSearchField) === searchField else { return }
        refreshResults()
    }
}

/// Two-line list row: city/clock name over identifier, country and current
/// offset.
private final class TwoLineRowView: NSTableCellView {

    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        titleField.font = .systemFont(ofSize: 13)
        titleField.lineBreakMode = .byTruncatingTail
        subtitleField.font = .systemFont(ofSize: 10)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingTail

        for field in [titleField, subtitleField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            addSubview(field)
        }
        textField = titleField

        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 3),

            subtitleField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            subtitleField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
            subtitleField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, subtitle: String, dimmed: Bool) {
        titleField.stringValue = title
        titleField.textColor = dimmed ? .secondaryLabelColor : .labelColor
        subtitleField.stringValue = subtitle
    }
}
