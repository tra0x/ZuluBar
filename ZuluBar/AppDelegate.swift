import Cocoa
import ServiceManagement

/// Main application delegate that manages the status bar item and user interactions
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    // MARK: - Properties

    var statusItem: NSStatusItem!
    var timer: Timer?
    var isShowingFeedback = false
    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter
    }()

    // MARK: - UserDefaults Keys

    private enum UserDefaultsKeys {
        static let showSeconds = "showSeconds"
        static let showDate = "showDate"
        static let dateFormat = "dateFormat"
        static let displaySuffix = "displaySuffix"
        static let copyFormat = "copyFormat"
    }

    // MARK: - Types

    /// Available formats for copying time to clipboard
    enum CopyFormat: String, CaseIterable {
        case humanReadable = "Human Readable"
        case iso8601 = "ISO 8601"
        case unixTimestamp = "Unix Timestamp"
        case rfc3339 = "RFC 3339"
    }

    /// Available suffixes for status bar display
    enum DisplaySuffix: String, CaseIterable {
        case utc = "UTC"
        case z = "Z"
        case none = "None"
    }

    /// Available date formats for status bar display
    enum DateFormat: String, CaseIterable {
        case dayMonthDate = "Tue Dec 2"
        case dayDateMonth = "Tue 2 Dec"

        var formatString: String {
            switch self {
            case .dayMonthDate: return "E MMM d"      // Tue Dec 2
            case .dayDateMonth: return "E d MMM"      // Tue 2 Dec
            }
        }
    }

    // MARK: - Settings

    var showSeconds: Bool {
        get { UserDefaults.standard.object(forKey: UserDefaultsKeys.showSeconds) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.showSeconds) }
    }

    var showDate: Bool {
        get { UserDefaults.standard.object(forKey: UserDefaultsKeys.showDate) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.showDate) }
    }

    var dateFormat: DateFormat {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: UserDefaultsKeys.dateFormat),
               let format = DateFormat(rawValue: rawValue) {
                return format
            }
            return .dayMonthDate
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: UserDefaultsKeys.dateFormat) }
    }

    var displaySuffix: DisplaySuffix {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: UserDefaultsKeys.displaySuffix),
               let suffix = DisplaySuffix(rawValue: rawValue) {
                return suffix
            }
            return .utc
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: UserDefaultsKeys.displaySuffix) }
    }

    var copyFormat: CopyFormat {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: UserDefaultsKeys.copyFormat),
               let format = CopyFormat(rawValue: rawValue) {
                return format
            }
            return .humanReadable
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: UserDefaultsKeys.copyFormat) }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Launch at Login error: \(error)")
            }
        }
    }

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Build configuration verification
        #if IS_FREE_BUILD
        print("ZuluBar: Free build active")
        #elseif IS_PAID_BUILD
        print("ZuluBar: Paid build active")
        #else
        #error("Must define either IS_FREE_BUILD or IS_PAID_BUILD")
        #endif

        setupStatusItem()
        updateUTC()
        startTimer()
    }

    // MARK: - Setup

    /// Configures the status bar item with appropriate styling and click handlers
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    // MARK: - User Interaction

    /// Handles clicks on the status bar item
    /// - Left click: Copies current time to clipboard
    /// - Right click: Shows options menu
    @objc func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showOptionsMenu()
        } else {
            copyTimeToClipboard()
        }
    }

    /// Shows the options menu below the status bar item
    private func showOptionsMenu() {
        let menu = setupMenu()
        menu.delegate = self

        if let button = statusItem.button {
            let point = NSPoint(x: 0, y: button.frame.height)
            menu.popUp(positioning: nil, at: point, in: button)
        }
    }

    /// Copies the current time to clipboard and shows visual feedback
    private func copyTimeToClipboard() {
        let textToCopy = getFormattedTimeForCopy()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textToCopy, forType: .string)

        showCopiedFeedback()
    }

    /// Displays "Copied!" message briefly in the status bar
    private func showCopiedFeedback() {
        isShowingFeedback = true
        statusItem.button?.title = "✓ Copied"

        // Restore original time after 0.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isShowingFeedback = false
            self?.updateUTC()
        }
    }

    // MARK: - Menu Setup

    /// Creates and configures the options menu
    /// - Returns: Configured NSMenu with all options
    private func setupMenu() -> NSMenu {
        let menu = NSMenu()

        // Display seconds toggle
        let showSecondsItem = NSMenuItem(title: "Display Seconds", action: #selector(toggleSeconds), keyEquivalent: "")
        showSecondsItem.state = showSeconds ? .on : .off
        menu.addItem(showSecondsItem)

        // Date Format submenu
        let dateFormatItem = NSMenuItem(title: "Date Format", action: nil, keyEquivalent: "")
        let dateFormatSubmenu = NSMenu()

        let noneItem = NSMenuItem(title: "None", action: #selector(setDateFormatNone), keyEquivalent: "")
        noneItem.state = !showDate ? .on : .off
        dateFormatSubmenu.addItem(noneItem)

        let dayMonthDateItem = NSMenuItem(title: "Tue Dec 2", action: #selector(setDateFormatDayMonthDate), keyEquivalent: "")
        dayMonthDateItem.state = (showDate && dateFormat == .dayMonthDate) ? .on : .off
        dateFormatSubmenu.addItem(dayMonthDateItem)

        let dayDateMonthItem = NSMenuItem(title: "Tue 2 Dec", action: #selector(setDateFormatDayDateMonth), keyEquivalent: "")
        dayDateMonthItem.state = (showDate && dateFormat == .dayDateMonth) ? .on : .off
        dateFormatSubmenu.addItem(dayDateMonthItem)

        dateFormatItem.submenu = dateFormatSubmenu
        menu.addItem(dateFormatItem)

        // Display Suffix submenu
        let displaySuffixItem = NSMenuItem(title: "Display Suffix", action: nil, keyEquivalent: "")
        let displaySuffixSubmenu = NSMenu()

        let utcSuffixItem = NSMenuItem(title: "UTC (14:23:45 UTC)", action: #selector(setDisplaySuffixUTC), keyEquivalent: "")
        utcSuffixItem.state = displaySuffix == .utc ? .on : .off
        displaySuffixSubmenu.addItem(utcSuffixItem)

        let zSuffixItem = NSMenuItem(title: "Z (14:23:45Z)", action: #selector(setDisplaySuffixZ), keyEquivalent: "")
        zSuffixItem.state = displaySuffix == .z ? .on : .off
        displaySuffixSubmenu.addItem(zSuffixItem)

        let noneSuffixItem = NSMenuItem(title: "None (14:23:45)", action: #selector(setDisplaySuffixNone), keyEquivalent: "")
        noneSuffixItem.state = displaySuffix == .none ? .on : .off
        displaySuffixSubmenu.addItem(noneSuffixItem)

        displaySuffixItem.submenu = displaySuffixSubmenu
        menu.addItem(displaySuffixItem)

        // Copy Format submenu
        let copyFormatItem = NSMenuItem(title: "Copy Format", action: nil, keyEquivalent: "")
        let copyFormatSubmenu = NSMenu()

        let humanReadableItem = NSMenuItem(title: "Human Readable (14:23:45 UTC)", action: #selector(setCopyFormatHumanReadable), keyEquivalent: "")
        humanReadableItem.state = copyFormat == .humanReadable ? .on : .off
        copyFormatSubmenu.addItem(humanReadableItem)

        let iso8601Item = NSMenuItem(title: "ISO 8601 (2025-12-02T14:23:45Z)", action: #selector(setCopyFormatISO8601), keyEquivalent: "")
        iso8601Item.state = copyFormat == .iso8601 ? .on : .off
        copyFormatSubmenu.addItem(iso8601Item)

        let unixTimestampItem = NSMenuItem(title: "Unix Timestamp (1733150625)", action: #selector(setCopyFormatUnixTimestamp), keyEquivalent: "")
        unixTimestampItem.state = copyFormat == .unixTimestamp ? .on : .off
        copyFormatSubmenu.addItem(unixTimestampItem)

        let rfc3339Item = NSMenuItem(title: "RFC 3339 (2025-12-02T14:23:45Z)", action: #selector(setCopyFormatRFC3339), keyEquivalent: "")
        rfc3339Item.state = copyFormat == .rfc3339 ? .on : .off
        copyFormatSubmenu.addItem(rfc3339Item)

        copyFormatItem.submenu = copyFormatSubmenu
        menu.addItem(copyFormatItem)

        menu.addItem(NSMenuItem.separator())

        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.state = launchAtLogin ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Menu Actions

    @objc func toggleSeconds(_ sender: NSMenuItem) {
        showSeconds.toggle()
        sender.state = showSeconds ? .on : .off
        updateUTC()
    }

    @objc func setDateFormatNone() {
        showDate = false
        updateUTC()
    }

    @objc func setDateFormatDayMonthDate() {
        showDate = true
        dateFormat = .dayMonthDate
        updateUTC()
    }

    @objc func setDateFormatDayDateMonth() {
        showDate = true
        dateFormat = .dayDateMonth
        updateUTC()
    }

    @objc func setDisplaySuffixUTC() {
        displaySuffix = .utc
        updateUTC()
    }

    @objc func setDisplaySuffixZ() {
        displaySuffix = .z
        updateUTC()
    }

    @objc func setDisplaySuffixNone() {
        displaySuffix = .none
        updateUTC()
    }

    @objc func setCopyFormatHumanReadable() {
        copyFormat = .humanReadable
    }

    @objc func setCopyFormatISO8601() {
        copyFormat = .iso8601
    }

    @objc func setCopyFormatUnixTimestamp() {
        copyFormat = .unixTimestamp
    }

    @objc func setCopyFormatRFC3339() {
        copyFormat = .rfc3339
    }

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        launchAtLogin.toggle()
        sender.state = launchAtLogin ? .on : .off
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Time Formatting

    /// Formats the current time according to the selected copy format
    /// - Returns: Formatted time string ready for clipboard
    func getFormattedTimeForCopy() -> String {
        let format: UTCTimeFormatter.Format

        switch copyFormat {
        case .humanReadable:
            // Always copy with seconds and UTC suffix, regardless of display settings
            format = .humanReadable(showSeconds: true, suffix: .utc)
        case .iso8601:
            format = .iso8601
        case .unixTimestamp:
            format = .unixTimestamp
        case .rfc3339:
            format = .rfc3339
        }

        return UTCTimeFormatter.format(as: format)
    }

    /// Converts DisplaySuffix to UTCTimeFormatter.Suffix
    private func convertDisplaySuffix(_ suffix: DisplaySuffix) -> UTCTimeFormatter.Suffix {
        switch suffix {
        case .utc: return .utc
        case .z: return .z
        case .none: return .none
        }
    }

    // MARK: - Timer Management

    /// Starts the timer that updates the status bar display
    /// Syncs to the next whole second for precise timing
    func startTimer() {
        // Calculate time until next whole second for precise sync
        let now = Date()
        let calendar = Calendar.current
        let nanosecond = calendar.component(.nanosecond, from: now)
        let delayToNextSecond = Double(1_000_000_000 - nanosecond) / 1_000_000_000.0

        // Schedule first update at the next whole second
        let syncTimer = Timer(timeInterval: delayToNextSecond, repeats: false) { [weak self] _ in
            self?.updateUTC()

            // Now start repeating timer every 1 second (already synced)
            let repeatingTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.updateUTC()
            }
            RunLoop.main.add(repeatingTimer, forMode: .common)
            self?.timer = repeatingTimer
        }
        RunLoop.main.add(syncTimer, forMode: .common)
    }

    /// Updates the status bar with the current UTC time
    func updateUTC() {
        // Don't update if showing feedback
        guard !isShowingFeedback else { return }

        var displayText = ""

        // Add date if enabled
        if showDate {
            dateFormatter.dateFormat = dateFormat.formatString
            displayText = dateFormatter.string(from: Date()) + " "
        }

        // Add time
        let suffix = convertDisplaySuffix(displaySuffix)
        let format = UTCTimeFormatter.Format.humanReadable(showSeconds: showSeconds, suffix: suffix)
        displayText += UTCTimeFormatter.format(as: format)

        statusItem.button?.title = displayText
    }
}
