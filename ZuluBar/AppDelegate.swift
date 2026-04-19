import Carbon
import Cocoa
import ServiceManagement
#if IS_PAID_BUILD
import Sparkle
#endif

/// Main application delegate that manages the status bar item and user interactions
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    // MARK: - Types (Hot Key)

    /// A resolved keyboard shortcut binding.
    struct HotKey {
        let keyCode: UInt16
        let modifierFlags: NSEvent.ModifierFlags
        /// Human-readable display string, e.g. "⌘⇧C".
        let display: String
    }

    // MARK: - Properties

    var statusItem: NSStatusItem!
    var timer: Timer?
    var isShowingFeedback = false
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var recorderPanel: HotKeyRecorderPanel?
    #if IS_PAID_BUILD
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    #endif
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
        static let copyShortcutKeyCode = "copyShortcutKeyCode"
        static let copyShortcutModifiers = "copyShortcutModifiers"
        static let copyShortcutDisplay = "copyShortcutDisplay"
    }

    // MARK: - Types

    /// Available formats for copying time to clipboard
    enum CopyFormat: String, CaseIterable {
        case display = "Display"
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
            return .z
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: UserDefaultsKeys.displaySuffix) }
    }

    var copyFormat: CopyFormat {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: UserDefaultsKeys.copyFormat) {
                if rawValue == "Human Readable" {
                    return .display
                }
                if let format = CopyFormat(rawValue: rawValue) {
                    return format
                }
            }
            return .display
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: UserDefaultsKeys.copyFormat) }
    }

    var copyShortcut: HotKey? {
        get {
            guard let display = UserDefaults.standard.string(forKey: UserDefaultsKeys.copyShortcutDisplay),
                  !display.isEmpty else { return nil }
            let keyCode = UInt16(clamping: UserDefaults.standard.integer(forKey: UserDefaultsKeys.copyShortcutKeyCode))
            let raw = UInt(bitPattern: UserDefaults.standard.integer(forKey: UserDefaultsKeys.copyShortcutModifiers))
            return HotKey(keyCode: keyCode, modifierFlags: NSEvent.ModifierFlags(rawValue: raw), display: display)
        }
        set {
            if let shortcut = newValue {
                UserDefaults.standard.set(Int(shortcut.keyCode), forKey: UserDefaultsKeys.copyShortcutKeyCode)
                UserDefaults.standard.set(Int(bitPattern: UInt(shortcut.modifierFlags.rawValue)), forKey: UserDefaultsKeys.copyShortcutModifiers)
                UserDefaults.standard.set(shortcut.display, forKey: UserDefaultsKeys.copyShortcutDisplay)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.copyShortcutKeyCode)
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.copyShortcutModifiers)
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.copyShortcutDisplay)
            }
        }
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
        installHotKeyHandler()
        registerHotKey()
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

        let zSuffixItem = NSMenuItem(title: "Z (14:23:45Z)", action: #selector(setDisplaySuffixZ), keyEquivalent: "")
        zSuffixItem.state = displaySuffix == .z ? .on : .off
        displaySuffixSubmenu.addItem(zSuffixItem)

        let utcSuffixItem = NSMenuItem(title: "UTC (14:23:45 UTC)", action: #selector(setDisplaySuffixUTC), keyEquivalent: "")
        utcSuffixItem.state = displaySuffix == .utc ? .on : .off
        displaySuffixSubmenu.addItem(utcSuffixItem)

        let noneSuffixItem = NSMenuItem(title: "None (14:23:45)", action: #selector(setDisplaySuffixNone), keyEquivalent: "")
        noneSuffixItem.state = displaySuffix == .none ? .on : .off
        displaySuffixSubmenu.addItem(noneSuffixItem)

        displaySuffixItem.submenu = displaySuffixSubmenu
        menu.addItem(displaySuffixItem)

        // Copy Format submenu
        let copyFormatItem = NSMenuItem(title: "Copy Format", action: nil, keyEquivalent: "")
        let copyFormatSubmenu = NSMenu()

        let displayExample = UTCTimeFormatter.format(as: .humanReadable(showSeconds: showSeconds, suffix: convertDisplaySuffix(displaySuffix)))
        let displayItem = NSMenuItem(title: "Display (\(displayExample))", action: #selector(setCopyFormatDisplay), keyEquivalent: "")
        displayItem.state = copyFormat == .display ? .on : .off
        copyFormatSubmenu.addItem(displayItem)

        let unixTimestampItem = NSMenuItem(title: "Unix Timestamp (1733150625)", action: #selector(setCopyFormatUnixTimestamp), keyEquivalent: "")
        unixTimestampItem.state = copyFormat == .unixTimestamp ? .on : .off
        copyFormatSubmenu.addItem(unixTimestampItem)

        let rfc3339Item = NSMenuItem(title: "RFC 3339 (2025-12-02T14:23:45Z)", action: #selector(setCopyFormatRFC3339), keyEquivalent: "")
        rfc3339Item.state = copyFormat == .rfc3339 ? .on : .off
        copyFormatSubmenu.addItem(rfc3339Item)

        copyFormatItem.submenu = copyFormatSubmenu
        menu.addItem(copyFormatItem)

        // Copy Shortcut
        let shortcutTitle = copyShortcut.map { "Copy Shortcut (\($0.display))" } ?? "Copy Shortcut…"
        let copyShortcutItem = NSMenuItem(title: shortcutTitle, action: #selector(openShortcutRecorder), keyEquivalent: "")
        menu.addItem(copyShortcutItem)

        menu.addItem(NSMenuItem.separator())

        #if IS_PAID_BUILD
        let checkForUpdatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(checkForUpdatesItem)
        #endif

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

    @objc func setCopyFormatDisplay() {
        copyFormat = .display
    }

    @objc func setCopyFormatUnixTimestamp() {
        copyFormat = .unixTimestamp
    }

    @objc func setCopyFormatRFC3339() {
        copyFormat = .rfc3339
    }

    #if IS_PAID_BUILD
    @objc func checkForUpdates(_ sender: NSMenuItem) {
        updaterController.checkForUpdates(sender)
    }
    #endif

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
        case .display:
            // Match current display settings for copy output
            format = .humanReadable(showSeconds: showSeconds, suffix: convertDisplaySuffix(displaySuffix))
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

    // MARK: - Hot Key Management

    /// Installs the Carbon event handler that fires on every registered hot-key press.
    /// Call once at launch; the handler stays alive for the app's lifetime.
    private func installHotKeyHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let ptr = userData else { return OSStatus(eventNotHandledErr) }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue()
                delegate.copyTimeToClipboard()
                return noErr
            },
            1,
            &eventSpec,
            selfPointer,
            &hotKeyHandler
        )
    }

    /// Attempts to register the currently saved shortcut without disturbing the existing one.
    /// The old registration is only released after the new one succeeds, so a failed
    /// registration leaves the previous hotkey intact. Returns whether registration succeeded.
    @discardableResult
    func registerHotKey() -> Bool {
        guard let shortcut = copyShortcut else {
            unregisterHotKey()
            return true
        }

        var carbonModifiers: UInt32 = 0
        if shortcut.modifierFlags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if shortcut.modifierFlags.contains(.shift)   { carbonModifiers |= UInt32(shiftKey) }
        if shortcut.modifierFlags.contains(.option)  { carbonModifiers |= UInt32(optionKey) }
        if shortcut.modifierFlags.contains(.control) { carbonModifiers |= UInt32(controlKey) }

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = 0x5A554C55  // "ZULU"
        hotKeyID.id = 1

        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )

        guard status == noErr, let newRef = newRef else {
            print("ZuluBar: Failed to register hotkey (error \(status))")
            return false
        }

        // New registration succeeded — safe to release the previous one
        unregisterHotKey()
        hotKeyRef = newRef
        return true
    }

    private func unregisterHotKey() {
        guard let ref = hotKeyRef else { return }
        UnregisterEventHotKey(ref)
        hotKeyRef = nil
    }

    @objc private func openShortcutRecorder() {
        recorderPanel?.close()
        recorderPanel = HotKeyRecorderPanel(current: copyShortcut)
        recorderPanel?.onShortcutChanged = { [weak self] shortcut in
            guard let self = self else { return }
            let previous = self.copyShortcut
            self.copyShortcut = shortcut
            if !self.registerHotKey() {
                // Registration failed — roll back to the previous binding
                self.copyShortcut = previous
                self.registerHotKey()
                self.recorderPanel?.registrationFailed()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        recorderPanel?.makeKeyAndOrderFront(nil)
        recorderPanel?.center()
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
