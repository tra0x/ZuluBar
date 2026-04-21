import Cocoa
import ServiceManagement
#if IS_PAID_BUILD
import Sparkle
#endif

/// Main application delegate that manages the status bar item and user interactions.
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    // MARK: - Properties

    var statusItem: NSStatusItem!
    var timer: Timer?
    var isShowingFeedback = false
    var settings = Settings()
    private let hotKeyManager = HotKeyManager()
    private var recorderPanel: HotKeyRecorderPanel?
    #if IS_PAID_BUILD
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    #endif

    // MARK: - Launch at Login

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
        hotKeyManager.onTrigger = { [weak self] in self?.copyTimeToClipboard() }
        hotKeyManager.activate(settings.copyShortcut)
        updateUTC()
        startTimer()
    }

    // MARK: - Setup

    /// Configures the status bar item with appropriate styling and click handlers.
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    // MARK: - User Interaction

    /// Handles clicks on the status bar item.
    /// - Left click: copies current time to clipboard.
    /// - Right click: shows options menu.
    @objc func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showOptionsMenu()
        } else {
            copyTimeToClipboard()
        }
    }

    /// Shows the options menu below the status bar item.
    private func showOptionsMenu() {
        let menu = setupMenu()
        menu.delegate = self

        if let button = statusItem.button {
            let point = NSPoint(x: 0, y: button.frame.height)
            menu.popUp(positioning: nil, at: point, in: button)
        }
    }

    /// Copies the current time to clipboard and shows visual feedback.
    private func copyTimeToClipboard() {
        let textToCopy = getFormattedTimeForCopy()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textToCopy, forType: .string)

        showCopiedFeedback()
    }

    /// Displays "Copied!" message briefly in the status bar.
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

    /// Creates and configures the options menu.
    private func setupMenu() -> NSMenu {
        let menu = NSMenu()

        // Display seconds toggle
        let showSecondsItem = NSMenuItem(title: "Display Seconds", action: #selector(toggleSeconds), keyEquivalent: "")
        showSecondsItem.state = settings.showSeconds ? .on : .off
        menu.addItem(showSecondsItem)

        // Date Format submenu
        let dateFormatItem = NSMenuItem(title: "Date Format", action: nil, keyEquivalent: "")
        let dateFormatSubmenu = NSMenu()

        let noneItem = NSMenuItem(title: "None", action: #selector(setDateFormatNone), keyEquivalent: "")
        noneItem.state = !settings.showDate ? .on : .off
        dateFormatSubmenu.addItem(noneItem)

        let dayMonthDateItem = NSMenuItem(title: "Tue Dec 2", action: #selector(setDateFormatDayMonthDate), keyEquivalent: "")
        dayMonthDateItem.state = (settings.showDate && settings.dateFormat == .dayMonthDate) ? .on : .off
        dateFormatSubmenu.addItem(dayMonthDateItem)

        let dayDateMonthItem = NSMenuItem(title: "Tue 2 Dec", action: #selector(setDateFormatDayDateMonth), keyEquivalent: "")
        dayDateMonthItem.state = (settings.showDate && settings.dateFormat == .dayDateMonth) ? .on : .off
        dateFormatSubmenu.addItem(dayDateMonthItem)

        dateFormatItem.submenu = dateFormatSubmenu
        menu.addItem(dateFormatItem)

        // Display Suffix submenu
        let displaySuffixItem = NSMenuItem(title: "Display Suffix", action: nil, keyEquivalent: "")
        let displaySuffixSubmenu = NSMenu()

        let zSuffixItem = NSMenuItem(title: "Z (14:23:45Z)", action: #selector(setDisplaySuffixZ), keyEquivalent: "")
        zSuffixItem.state = settings.displaySuffix == .z ? .on : .off
        displaySuffixSubmenu.addItem(zSuffixItem)

        let utcSuffixItem = NSMenuItem(title: "UTC (14:23:45 UTC)", action: #selector(setDisplaySuffixUTC), keyEquivalent: "")
        utcSuffixItem.state = settings.displaySuffix == .utc ? .on : .off
        displaySuffixSubmenu.addItem(utcSuffixItem)

        let noneSuffixItem = NSMenuItem(title: "None (14:23:45)", action: #selector(setDisplaySuffixNone), keyEquivalent: "")
        noneSuffixItem.state = settings.displaySuffix == .none ? .on : .off
        displaySuffixSubmenu.addItem(noneSuffixItem)

        displaySuffixItem.submenu = displaySuffixSubmenu
        menu.addItem(displaySuffixItem)

        // Copy Format submenu
        let copyFormatItem = NSMenuItem(title: "Copy Format", action: nil, keyEquivalent: "")
        let copyFormatSubmenu = NSMenu()

        let displayExample = UTCTimeFormatter.format(as: .humanReadable(showSeconds: settings.showSeconds, suffix: settings.displaySuffix))
        let displayItem = NSMenuItem(title: "Display (\(displayExample))", action: #selector(setCopyFormatDisplay), keyEquivalent: "")
        displayItem.state = settings.copyFormat == .display ? .on : .off
        copyFormatSubmenu.addItem(displayItem)

        let unixTimestampItem = NSMenuItem(title: "Unix Timestamp (1733150625)", action: #selector(setCopyFormatUnixTimestamp), keyEquivalent: "")
        unixTimestampItem.state = settings.copyFormat == .unixTimestamp ? .on : .off
        copyFormatSubmenu.addItem(unixTimestampItem)

        let rfc3339Item = NSMenuItem(title: "RFC 3339 (2025-12-02T14:23:45Z)", action: #selector(setCopyFormatRFC3339), keyEquivalent: "")
        rfc3339Item.state = settings.copyFormat == .rfc3339 ? .on : .off
        copyFormatSubmenu.addItem(rfc3339Item)

        copyFormatItem.submenu = copyFormatSubmenu
        menu.addItem(copyFormatItem)

        // Copy Shortcut
        let shortcutTitle = settings.copyShortcut.map { "Copy Shortcut (\($0.display))" } ?? "Copy Shortcut…"
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

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Menu Actions

    @objc func toggleSeconds(_ sender: NSMenuItem) {
        settings.showSeconds.toggle()
        sender.state = settings.showSeconds ? .on : .off
        updateUTC()
    }

    @objc func setDateFormatNone() {
        settings.showDate = false
        updateUTC()
    }

    @objc func setDateFormatDayMonthDate() {
        settings.showDate = true
        settings.dateFormat = .dayMonthDate
        updateUTC()
    }

    @objc func setDateFormatDayDateMonth() {
        settings.showDate = true
        settings.dateFormat = .dayDateMonth
        updateUTC()
    }

    @objc func setDisplaySuffixUTC() {
        settings.displaySuffix = .utc
        updateUTC()
    }

    @objc func setDisplaySuffixZ() {
        settings.displaySuffix = .z
        updateUTC()
    }

    @objc func setDisplaySuffixNone() {
        settings.displaySuffix = .none
        updateUTC()
    }

    @objc func setCopyFormatDisplay() {
        settings.copyFormat = .display
    }

    @objc func setCopyFormatUnixTimestamp() {
        settings.copyFormat = .unixTimestamp
    }

    @objc func setCopyFormatRFC3339() {
        settings.copyFormat = .rfc3339
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

    /// Formats the current time according to the selected copy format.
    func getFormattedTimeForCopy() -> String {
        let format: UTCTimeFormatter.Format

        switch settings.copyFormat {
        case .display:
            // Match current display settings for copy output
            format = .humanReadable(showSeconds: settings.showSeconds, suffix: settings.displaySuffix)
        case .unixTimestamp:
            format = .unixTimestamp
        case .rfc3339:
            format = .rfc3339
        }

        return UTCTimeFormatter.format(as: format)
    }

    // MARK: - Shortcut Recorder

    @objc private func openShortcutRecorder() {
        recorderPanel?.close()
        recorderPanel = HotKeyRecorderPanel(current: settings.copyShortcut)
        recorderPanel?.onShortcutChanged = { [weak self] shortcut in
            guard let self = self else { return }
            if self.hotKeyManager.activate(shortcut) {
                // Persist only after Carbon registration succeeds, so UserDefaults
                // and the live binding can never drift out of sync.
                self.settings.copyShortcut = shortcut
            } else {
                self.recorderPanel?.registrationFailed()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        recorderPanel?.makeKeyAndOrderFront(nil)
        recorderPanel?.center()
    }

    // MARK: - Timer Management

    /// Starts the timer that updates the status bar display, synced to the next whole second.
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

    /// Updates the status bar with the current UTC time.
    func updateUTC() {
        guard !isShowingFeedback else { return }

        let display = StatusBarDisplay(
            dateFormat: settings.showDate ? settings.dateFormat : nil,
            timeFormat: .humanReadable(showSeconds: settings.showSeconds, suffix: settings.displaySuffix)
        )
        statusItem.button?.title = StatusBarRenderer.render(display)
    }
}
