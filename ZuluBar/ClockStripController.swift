import Cocoa

/// One additional clock's ready-to-draw strip content.
///
/// The owner formats both strings (via `ZoneClockFormatter`) and passes the
/// configured identifier along for click routing — the strip itself holds no
/// time logic and never resolves a `TimeZone`.
struct ClockStripEntry: Equatable {
    let identifier: String
    let label: String
    let time: String
}

/// Owns what the single status item shows: the mandatory UTC clock plus any
/// opt-in extra city clocks.
///
/// With no extras the real `NSStatusBarButton` title is used, so the UTC-only
/// appearance and click path stay exactly what they were. As soon as there is
/// one extra clock the button hosts a strip of individually clickable clock
/// views; the button's own target/action is borrowed for that time and handed
/// back when the last extra goes away.
///
/// The controller owns transient presentation state only. It never formats
/// time, touches the clipboard, pops up a menu or writes settings — it reports
/// intent through the callbacks and leaves the refresh timer to the owner.
///
/// Usage:
/// ```swift
/// let strip = ClockStripController(statusItem: statusItem)
/// strip.onCopyUTC = { [weak self] in self?.copyTimeToClipboard() }
/// strip.onCopyAdditional = { [weak self] identifier in self?.copy(identifier) }
/// strip.onOptionsMenu = { [weak self] anchor in self?.showOptionsMenu(from: anchor) }
/// strip.render(utcTitle: title, additional: entries)   // every tick
/// ```
final class ClockStripController: NSObject {

    /// Schedules the delayed end of a copied indication. Injectable so tests
    /// can run the reset synchronously instead of waiting on the main queue.
    typealias FeedbackScheduler = (TimeInterval, @escaping () -> Void) -> Void

    // MARK: - Callbacks

    /// Left-click (or VoiceOver press) on the UTC clock.
    var onCopyUTC: (() -> Void)?

    /// Left-click (or VoiceOver press) on an extra clock. Carries the
    /// configured identifier — never an array index or a current offset.
    var onCopyAdditional: ((String) -> Void)?

    /// Right-click/Control-click (or VoiceOver "show menu") on any clock.
    /// The view handed back is the clock that was actually clicked, so the
    /// owner's shared menu pops up at the correct anchor.
    var onOptionsMenu: ((NSView) -> Void)?

    // MARK: - Rendered state

    /// Last UTC title handed to `render`, shown as-is.
    private(set) var utcTitle: String = ""

    /// Last extra clocks handed to `render`, duplicates dropped.
    private(set) var additionalEntries: [ClockStripEntry] = []

    /// Clock views in display order, UTC first. Empty in UTC-only mode, where
    /// the status button's own title is used instead.
    private(set) var clockCells: [ClockStripCellView] = []

    /// True while the grouped multi-clock strip is installed.
    var isUsingStripLayout: Bool { stripView != nil }

    /// True while a clock is pressed and the whole status item is drawn
    /// highlighted, as the menu bar does for any other item.
    private(set) var isGroupHighlighted = false

    // MARK: - Private

    private enum ClockKey: Hashable {
        case utc
        case additional(String)

        init(identifier: String?) {
            if let identifier {
                self = .additional(identifier)
            } else {
                self = .utc
            }
        }
    }

    private enum Layout {
        /// Space kept on each side of the strip inside the status item.
        static let stripInset: CGFloat = 4
        /// Gap between neighbouring clocks.
        static let clockSpacing: CGFloat = 10
        /// Matches the existing UTC-only copied indication.
        static let singleLineFeedbackTitle = "✓ Copied"
    }

    private let statusItem: NSStatusItem
    private let feedbackDuration: TimeInterval
    private let schedule: FeedbackScheduler

    private var stripView: NSStackView?
    private var cellsByKey: [ClockKey: ClockStripCellView] = [:]

    /// The clocks currently installed as the status button's accessibility
    /// children. Kept so the outer group override is only rewritten when the
    /// child set or order actually changes, instead of on every tick.
    private var accessibilityChildren: [ClockStripCellView] = []

    /// Which clocks are currently showing a copied indication, each with the
    /// token of the copy that started it. A delayed reset only clears its own
    /// token, so a newer copy is never wiped by an older timer.
    private var feedbackTokens: [ClockKey: Int] = [:]
    private var feedbackCounter = 0

    /// The clock whose press turned the group highlight on, so a highlight can
    /// never outlive the clock that owns it.
    private weak var pressedCell: ClockStripCellView?

    private var borrowedButtonState = false
    private weak var savedButtonTarget: AnyObject?
    private var savedButtonAction: Selector?
    private var savedButtonRole: NSAccessibility.Role?
    private var savedButtonLabel: String?

    // MARK: - Init

    init(statusItem: NSStatusItem,
         feedbackDuration: TimeInterval = 0.5,
         schedule: @escaping FeedbackScheduler = { delay, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay) { work() }
         }) {
        self.statusItem = statusItem
        self.feedbackDuration = feedbackDuration
        self.schedule = schedule
        super.init()
    }

    // MARK: - Rendering

    /// Refreshes the cached render state and the views. Safe to call on every
    /// timer tick: clock views are reused, an active copied indication is kept,
    /// and nothing is copied, popped up or persisted here.
    func render(utcTitle: String, additional: [ClockStripEntry]) {
        self.utcTitle = utcTitle
        self.additionalEntries = Self.deduplicated(additional)
        pruneFeedbackForRemovedClocks()

        if additionalEntries.isEmpty {
            applySingleClockLayout()
        } else {
            applyStripLayout()
        }
    }

    /// Shows a short copied indication on one clock — `nil` means UTC,
    /// otherwise the configured identifier.
    ///
    /// Other clocks keep refreshing underneath, widths stay put, and an
    /// unknown or just-removed identifier is a no-op rather than an error.
    func showCopiedFeedback(for identifier: String?) {
        let key = ClockKey(identifier: identifier)
        if case .additional(let id) = key,
           !additionalEntries.contains(where: { $0.identifier == id }) {
            return
        }

        feedbackCounter += 1
        let token = feedbackCounter
        feedbackTokens[key] = token
        applyFeedbackState()

        schedule(feedbackDuration) { [weak self] in
            guard let self else { return }
            // A newer copy on the same clock bumped the token — leave its
            // indication alone and let its own reset finish the job.
            guard self.feedbackTokens[key] == token else { return }
            self.feedbackTokens.removeValue(forKey: key)
            self.applyFeedbackState()
        }
    }

    // MARK: - UTC-only layout

    private func applySingleClockLayout() {
        teardownStripIfNeeded()
        // Same native single-clock behaviour, minus the redundant per-tick
        // assignment: the status item already sizes itself to its title.
        if statusItem.length != NSStatusItem.variableLength {
            statusItem.length = NSStatusItem.variableLength
        }
        statusItem.button?.title = singleLineTitle
    }

    private var singleLineTitle: String {
        feedbackTokens[.utc] != nil ? Layout.singleLineFeedbackTitle : utcTitle
    }

    // MARK: - Multi-clock layout

    private func applyStripLayout() {
        let strip = stripView ?? makeStripView()
        borrowStatusButtonIfNeeded()

        var ordered: [ClockStripCellView] = []
        var liveKeys: Set<ClockKey> = []

        let utcCell = cell(for: .utc)
        utcCell.update(labelText: nil, timeText: utcTitle, singleLineFont: statusButtonFont)
        utcCell.toolTip = utcTitle.isEmpty ? "Coordinated Universal Time" : "\(utcTitle) · Coordinated Universal Time"
        ordered.append(utcCell)
        liveKeys.insert(.utc)

        for entry in additionalEntries {
            let key = ClockKey.additional(entry.identifier)
            let clockCell = cell(for: key)
            clockCell.update(labelText: entry.label, timeText: entry.time)
            clockCell.toolTip = "\(entry.label) · \(entry.time) · \(entry.identifier)"
            ordered.append(clockCell)
            liveKeys.insert(key)
        }

        for (key, staleCell) in cellsByKey where !liveKeys.contains(key) {
            // A clock that is leaving must not keep a highlight it can no
            // longer release.
            staleCell.setGroupHighlighted(false)
            staleCell.removeFromSuperview()
            cellsByKey.removeValue(forKey: key)
        }

        // The clock holding the highlight is gone (or was never released), so
        // no mouse-up can clear it — drop it here instead of leaving the whole
        // status item stuck highlighted.
        let pressedSurvives = pressedCell.map { pressed in ordered.contains { $0 === pressed } } ?? false
        if isGroupHighlighted, !pressedSurvives {
            setGroupHighlighted(false, from: nil)
        }

        // Only rearrange when the set or order actually changed, so an
        // ordinary tick is a text update on existing views.
        if !strip.views.elementsEqual(ordered, by: { $0 === $1 }) {
            strip.setViews(ordered, in: .leading)
        }

        clockCells = ordered
        // A clock added or reordered mid-press joins the current group state
        // rather than inheriting a stale one.
        for clockCell in ordered {
            clockCell.setGroupHighlighted(isGroupHighlighted)
        }
        applyFeedbackState()
        configureStripAccessibilityIfNeeded(cells: ordered)
        updateStatusItemLength()
    }

    private func makeStripView() -> NSStackView {
        let strip = NSStackView()
        strip.orientation = .horizontal
        strip.alignment = .centerY
        strip.distribution = .fill
        strip.spacing = Layout.clockSpacing
        strip.detachesHiddenViews = true
        strip.translatesAutoresizingMaskIntoConstraints = false
        // The strip groups the clocks; the clocks themselves are the
        // accessible elements, so this layer stays out of the way.
        strip.setAccessibilityElement(false)
        stripView = strip

        if let button = statusItem.button {
            button.addSubview(strip)
            NSLayoutConstraint.activate([
                strip.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                strip.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
        }
        return strip
    }

    private func cell(for key: ClockKey) -> ClockStripCellView {
        if let existing = cellsByKey[key] { return existing }

        let kind: ClockStripCellView.Kind
        switch key {
        case .utc:
            kind = .utc
        case .additional(let identifier):
            kind = .additional(identifier: identifier)
        }

        let created = ClockStripCellView(kind: kind)
        created.onCopy = { [weak self] clock in self?.handleCopy(from: clock) }
        created.onShowMenu = { [weak self] clock in self?.onOptionsMenu?(clock) }
        created.onHighlightChange = { [weak self] clock, highlighted in
            self?.setGroupHighlighted(highlighted, from: highlighted ? clock : nil)
        }
        cellsByKey[key] = created
        return created
    }

    /// Mirrors the owner's status-button font for the UTC clock so the two
    /// layouts show identical UTC text.
    private var statusButtonFont: NSFont? {
        statusItem.button?.font
    }

    private func updateStatusItemLength() {
        guard let strip = stripView else { return }
        strip.layoutSubtreeIfNeeded()
        let width = ceil(strip.fittingSize.width + 2 * Layout.stripInset)
        guard width > 0, abs(statusItem.length - width) > 0.5 else { return }
        statusItem.length = width
    }

    private func teardownStripIfNeeded() {
        guard let strip = stripView else { return }
        // Drop any highlight first, while the clocks and the borrowed button
        // are still around to be reset.
        setGroupHighlighted(false, from: nil)
        strip.removeFromSuperview()
        stripView = nil
        for (_, staleCell) in cellsByKey { staleCell.removeFromSuperview() }
        cellsByKey.removeAll()
        clockCells = []
        returnStatusButton()
    }

    // MARK: - Highlighting

    /// A pressed clock highlights the whole status item, as the menu bar does
    /// for any item. Every clock therefore switches to the selected-menu text
    /// colour, so none of them stays unreadable on the highlighted background;
    /// the copied indication stays on the clicked clock alone.
    private func setGroupHighlighted(_ highlighted: Bool, from clock: ClockStripCellView?) {
        pressedCell = clock
        guard highlighted != isGroupHighlighted else { return }
        isGroupHighlighted = highlighted
        statusItem.button?.highlight(highlighted)
        for clockCell in clockCells {
            clockCell.setGroupHighlighted(highlighted)
        }
    }

    // MARK: - Status button borrowing

    /// Clicks that land between clocks still belong to the status item, so the
    /// button's action is borrowed while the strip is installed. The owner's
    /// original target/action is restored in UTC-only mode, keeping the
    /// untouched single-clock click path.
    private func borrowStatusButtonIfNeeded() {
        guard let button = statusItem.button, !borrowedButtonState else { return }
        savedButtonTarget = button.target
        savedButtonAction = button.action
        savedButtonRole = button.accessibilityRole()
        savedButtonLabel = button.accessibilityLabel()
        borrowedButtonState = true
        button.title = ""
        button.target = self
        button.action = #selector(stripBackgroundClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func returnStatusButton() {
        guard let button = statusItem.button, borrowedButtonState else { return }
        button.target = savedButtonTarget
        button.action = savedButtonAction
        // Hand back exactly the accessibility the button had before the strip,
        // rather than assuming AppKit's defaults.
        button.setAccessibilityChildren(nil)
        button.setAccessibilityRole(savedButtonRole)
        button.setAccessibilityLabel(savedButtonLabel)
        button.setAccessibilityValue(nil)
        accessibilityChildren = []
        borrowedButtonState = false
        savedButtonTarget = nil
        savedButtonAction = nil
        savedButtonRole = nil
        savedButtonLabel = nil
    }

    /// A click on the gap between clocks: open the menu on a secondary click,
    /// and deliberately copy nothing on a primary one.
    @objc private func stripBackgroundClicked() {
        guard let event = NSApp.currentEvent, let button = statusItem.button else { return }
        let isSecondary = event.type == .rightMouseUp
            || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
        guard isSecondary else { return }
        onOptionsMenu?(button)
    }

    // MARK: - Clicks

    private func handleCopy(from clock: ClockStripCellView) {
        switch clock.kind {
        case .utc:
            onCopyUTC?()
        case .additional(let identifier):
            onCopyAdditional?(identifier)
        }
    }

    // MARK: - Feedback

    private func applyFeedbackState() {
        if stripView == nil {
            statusItem.button?.title = singleLineTitle
            return
        }
        for clockCell in clockCells {
            clockCell.setFeedback(feedbackTokens[key(for: clockCell)] != nil)
        }
        updateStatusItemLength()
    }

    private func key(for clockCell: ClockStripCellView) -> ClockKey {
        switch clockCell.kind {
        case .utc: return .utc
        case .additional(let identifier): return .additional(identifier)
        }
    }

    /// Feedback for a clock the user just removed is dropped; its pending
    /// reset finds no token and does nothing.
    private func pruneFeedbackForRemovedClocks() {
        let liveIdentifiers = Set(additionalEntries.map { $0.identifier })
        for key in Array(feedbackTokens.keys) {
            guard case .additional(let identifier) = key else { continue }
            if !liveIdentifiers.contains(identifier) {
                feedbackTokens.removeValue(forKey: key)
            }
        }
    }

    // MARK: - Accessibility

    /// Installs the outer group override only when the child set or order
    /// changed. An ordinary tick updates each clock's own label and value and
    /// leaves the children alone, so VoiceOver traversal stays stable instead
    /// of being handed a fresh children array every second.
    private func configureStripAccessibilityIfNeeded(cells: [ClockStripCellView]) {
        guard let button = statusItem.button else { return }
        guard !accessibilityChildren.elementsEqual(cells, by: { $0 === $1 }) else { return }
        // The outer button carries no clock of its own in this layout — it is
        // the group, and the clocks are its children, so VoiceOver never reads
        // an extra empty clock.
        button.setAccessibilityRole(.group)
        button.setAccessibilityLabel("ZuluBar clocks")
        button.setAccessibilityValue(nil)
        button.setAccessibilityChildren(cells)
        accessibilityChildren = cells
    }

    // MARK: - Helpers

    /// Defensive: identifiers key the reused views, so a duplicated entry
    /// collapses to its first occurrence instead of fighting over a view.
    private static func deduplicated(_ entries: [ClockStripEntry]) -> [ClockStripEntry] {
        var seen = Set<String>()
        return entries.filter { seen.insert($0.identifier).inserted }
    }
}

/// One clickable clock inside the grouped strip.
///
/// Custom-drawn rather than an `NSButton` subclass because the strip needs a
/// centred two-line layout, truncation on the label only, and menu-bar text
/// colours for the normal and highlighted states — none of which fit a single
/// button title. Accessibility and activation are wired up explicitly instead.
final class ClockStripCellView: NSView {

    enum Kind: Equatable {
        case utc
        case additional(identifier: String)
    }

    /// Fonts and spacing live in one place so the menu-bar fit can be tuned
    /// without reading the drawing code.
    enum Metrics {
        static let labelFont = NSFont.systemFont(ofSize: 9)
        static let stackedTimeFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        /// Used only if the status button has no font of its own.
        static let fallbackSingleLineFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        /// Labels wider than this truncate; the tooltip keeps the full text.
        static let maxLabelWidth: CGFloat = 86
        static let horizontalPadding: CGFloat = 3
        static let lineSpacing: CGFloat = 0
        static let feedbackText = "✓ Copied"
        static let compactFeedbackText = "✓"
    }

    let kind: Kind

    /// Top line. `nil` renders the clock on one line, like UTC.
    private(set) var labelText: String?
    private(set) var timeText: String = ""
    private(set) var isShowingCopiedFeedback = false

    /// True while the status item around this clock is drawn highlighted —
    /// including when a *different* clock is the one being pressed, so the
    /// whole group stays readable.
    private(set) var isGroupHighlighted = false

    var onCopy: ((ClockStripCellView) -> Void)?
    var onShowMenu: ((ClockStripCellView) -> Void)?
    /// Reports this clock pressing and releasing, so the owner can highlight
    /// the whole status item and know which clock started it.
    var onHighlightChange: ((ClockStripCellView, Bool) -> Void)?

    /// Width frozen while a copied indication is showing, so neighbouring
    /// clocks never shift.
    private var reservedWidth: CGFloat?
    private var singleLineFont: NSFont = Metrics.fallbackSingleLineFont
    private var isPressed = false

    // MARK: - Init

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        updateAccessibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Content

    func update(labelText: String?, timeText: String, singleLineFont: NSFont? = nil) {
        let resolvedFont = singleLineFont ?? self.singleLineFont
        guard labelText != self.labelText
            || timeText != self.timeText
            || resolvedFont != self.singleLineFont else { return }

        self.labelText = labelText
        self.timeText = timeText
        self.singleLineFont = resolvedFont
        invalidateIntrinsicContentSize()
        needsDisplay = true
        updateAccessibility()
    }

    /// Adopts the group's highlighted presentation. Redraw only; the pressed
    /// clock's own state, the copied indication and the frozen width are
    /// untouched.
    func setGroupHighlighted(_ highlighted: Bool) {
        guard highlighted != isGroupHighlighted else { return }
        isGroupHighlighted = highlighted
        needsDisplay = true
    }

    func setFeedback(_ showing: Bool) {
        guard showing != isShowingCopiedFeedback else { return }
        reservedWidth = showing ? contentWidth() : nil
        isShowingCopiedFeedback = showing
        invalidateIntrinsicContentSize()
        needsDisplay = true
        updateAccessibility()
    }

    // MARK: - Measurement

    override var intrinsicContentSize: NSSize {
        NSSize(width: reservedWidth ?? contentWidth(), height: contentHeight())
    }

    override var isFlipped: Bool { false }

    private func contentWidth() -> CGFloat {
        let padding = 2 * Metrics.horizontalPadding
        guard let labelText else {
            return ceil(width(of: timeText, font: singleLineFont)) + padding
        }
        let timeWidth = ceil(width(of: timeText, font: Metrics.stackedTimeFont))
        let labelWidth = min(ceil(width(of: labelText, font: Metrics.labelFont)), Metrics.maxLabelWidth)
        return max(timeWidth, labelWidth) + padding
    }

    private func contentHeight() -> CGFloat {
        guard labelText != nil else { return ceil(lineHeight(of: singleLineFont)) }
        return ceil(lineHeight(of: Metrics.labelFont))
            + Metrics.lineSpacing
            + ceil(lineHeight(of: Metrics.stackedTimeFont))
    }

    private func width(of string: String, font: NSFont) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }

    private func lineHeight(of font: NSFont) -> CGFloat {
        font.ascender - font.descender + font.leading
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let color = textColor
        let available = max(bounds.width - 2 * Metrics.horizontalPadding, 0)

        if isShowingCopiedFeedback {
            let font = labelText == nil ? singleLineFont : Metrics.stackedTimeFont
            let fits = width(of: Metrics.feedbackText, font: font) <= available
            let text = fits ? Metrics.feedbackText : Metrics.compactFeedbackText
            drawLine(text, font: font, color: color, centeredIn: available, truncates: false)
            return
        }

        guard let labelText else {
            drawLine(timeText, font: singleLineFont, color: color, centeredIn: available, truncates: false)
            return
        }

        let labelHeight = ceil(lineHeight(of: Metrics.labelFont))
        let timeHeight = ceil(lineHeight(of: Metrics.stackedTimeFont))
        let total = labelHeight + Metrics.lineSpacing + timeHeight
        let top = bounds.midY + total / 2

        // Only the label truncates — the time always stays readable because
        // the clock is never narrower than its time line.
        draw(labelText,
             font: Metrics.labelFont,
             color: color,
             truncates: true,
             in: NSRect(x: Metrics.horizontalPadding, y: top - labelHeight, width: available, height: labelHeight))
        draw(timeText,
             font: Metrics.stackedTimeFont,
             color: color,
             truncates: false,
             in: NSRect(x: Metrics.horizontalPadding, y: top - total, width: available, height: timeHeight))
    }

    private func drawLine(_ text: String, font: NSFont, color: NSColor, centeredIn available: CGFloat, truncates: Bool) {
        let height = ceil(lineHeight(of: font))
        let rect = NSRect(x: Metrics.horizontalPadding,
                          y: bounds.midY - height / 2,
                          width: available,
                          height: height)
        draw(text, font: font, color: color, truncates: truncates, in: rect)
    }

    private func draw(_ text: String, font: NSFont, color: NSColor, truncates: Bool, in rect: NSRect) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = truncates ? .byTruncatingTail : .byClipping
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ])
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin])
    }

    /// Follows the menu bar: the label colour tracks light/dark, and while the
    /// status item is highlighted every clock uses the highlighted menu colour
    /// like any other menu-bar item. Internal so the drawing choice can be
    /// asserted without rasterising the view.
    var textColor: NSColor {
        isPressed || isGroupHighlighted ? .selectedMenuItemTextColor : .labelColor
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        // Control-click is a secondary click by macOS convention.
        if event.modifierFlags.contains(.control) {
            showMenu()
            return
        }
        setPressed(true)
    }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = isPressed
        setPressed(false)
        let location = convert(event.locationInWindow, from: nil)
        guard wasPressed, bounds.contains(location) else { return }
        onCopy?(self)
    }

    override func rightMouseDown(with event: NSEvent) {
        showMenu()
    }

    private func showMenu() {
        setPressed(true)
        // The owner's `popUp` runs the menu before returning, so the
        // highlight is released once it has been dismissed.
        onShowMenu?(self)
        setPressed(false)
    }

    private func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        onHighlightChange?(self, pressed)
        needsDisplay = true
    }

    // MARK: - Accessibility

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let characters = event.charactersIgnoringModifiers ?? ""
        guard characters == " " || characters == "\r" else {
            super.keyDown(with: event)
            return
        }
        onCopy?(self)
    }

    override func accessibilityPerformPress() -> Bool {
        onCopy?(self)
        return true
    }

    override func accessibilityPerformShowMenu() -> Bool {
        onShowMenu?(self)
        return true
    }

    private func updateAccessibility() {
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityClockName)
        setAccessibilityValue(isShowingCopiedFeedback ? "Copied" : timeText)
        setAccessibilityHelp("\(accessibilityZoneDescription). Press to copy this clock's time, or show the menu for ZuluBar options.")
    }

    private var accessibilityClockName: String {
        switch kind {
        case .utc:
            return "UTC clock"
        case .additional(let identifier):
            let name = labelText.flatMap { $0.isEmpty ? nil : $0 } ?? identifier
            return "\(name) clock"
        }
    }

    private var accessibilityZoneDescription: String {
        switch kind {
        case .utc:
            return "Coordinated Universal Time"
        case .additional(let identifier):
            return identifier
        }
    }
}
