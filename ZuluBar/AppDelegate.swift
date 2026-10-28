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
    var settings = Settings()
    private let hotKeyManager = HotKeyManager()
    private var recorderPanel: HotKeyRecorderPanel?
    private var clockStripController: ClockStripController?
    private var timeZonesPanel: TimeZonesPanel?
    #if IS_PAID_BUILD
    private let updateKeyStore = UpdateKeyStore()
    private let paidFeedBaseURL = Bundle.main.object(forInfoDictionaryKey: "ZuluBarFeedBaseURL") as? String ?? "https://zulubar.app/appcast.xml"
    private lazy var updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
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
        #if IS_PAID_BUILD
        // Defer starting Sparkle until a customer key exists so it never sees a
        // nil feed URL at startup.
        if updateKeyStore.load() != nil {
            updaterController.startUpdater()
        }
        configureAutomaticUpdateChecks()
        #endif
        updateUTC()
        startTimer()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refreshAfterSystemChange),
            name: NSWorkspace.didWakeNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshAfterSystemChange),
            name: .NSSystemClockDidChange, object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func refreshAfterSystemChange(_ notification: Notification) {
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

        let controller = ClockStripController(statusItem: statusItem)
        controller.onCopyUTC = { [weak self] in self?.copyTimeToClipboard() }
        controller.onCopyAdditional = { [weak self] identifier in
            self?.copyAdditionalClock(identifier: identifier)
        }
        controller.onOptionsMenu = { [weak self] anchor in
            self?.showOptionsMenu(from: anchor)
        }
        clockStripController = controller
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

    /// Opens the shared options menu at whichever clock was clicked.
    private func showOptionsMenu(from anchor: NSView? = nil) {
        let menu = setupMenu()
        menu.delegate = self

        if let anchor = anchor ?? statusItem?.button {
            let point = NSPoint(x: 0, y: anchor.bounds.height)
            menu.popUp(positioning: nil, at: point, in: anchor)
        }
    }

    /// The status-button UTC path and global shortcut always copy UTC.
    private func copyTimeToClipboard() {
        copyToClipboard(getFormattedTimeForCopy(), clockIdentifier: nil)
    }

    private func copyAdditionalClock(identifier: String) {
        guard let text = getFormattedTimeForAdditionalClock(identifier: identifier) else { return }
        copyToClipboard(text, clockIdentifier: identifier)
    }

    private func copyToClipboard(_ text: String, clockIdentifier: String?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        clockStripController?.showCopiedFeedback(for: clockIdentifier)
    }

    // MARK: - Menu Setup

    /// Creates and configures the options menu.
    private func setupMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let timeZonesItem = NSMenuItem(title: "Time Zones…", action: #selector(openTimeZones), keyEquivalent: "")
        timeZonesItem.target = self
        menu.addItem(timeZonesItem)
        menu.addItem(NSMenuItem.separator())

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
        let updateKeyItem = NSMenuItem(title: "Update Key…", action: #selector(openUpdateKeyPrompt), keyEquivalent: "")
        menu.addItem(updateKeyItem)

        let checkForUpdatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        checkForUpdatesItem.isEnabled = updateKeyStore.load() != nil
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

    @objc private func openTimeZones() {
        if let panel = timeZonesPanel {
            panel.update(clocks: settings.additionalClocks)
        } else {
            let availability: TimeZonesPanel.CatalogAvailability
            switch TimeZoneCatalog.loadResult {
            case .success: availability = .available
            case .failure(let error): availability = .unavailable(error)
            }
            let panel = TimeZonesPanel(clocks: settings.additionalClocks, catalog: availability)
            panel.onClocksChanged = { [weak self] clocks in
                guard let self else { return }
                self.settings.additionalClocks = clocks
                self.timeZonesPanel?.update(clocks: self.settings.additionalClocks)
                self.updateUTC()
            }
            timeZonesPanel = panel
            panel.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        timeZonesPanel?.makeKeyAndOrderFront(nil)
    }

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
        guard updateKeyStore.load() != nil else {
            showUpdateKeyRequiredAlert()
            return
        }
        updaterController.checkForUpdates(sender)
    }

    @objc private func openUpdateKeyPrompt() {
        let alert = NSAlert()
        alert.messageText = "Update Key"
        alert.informativeText = "Enter the update key from your ZuluBar purchase to enable paid app updates."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        if updateKeyStore.load() != nil {
            alert.addButton(withTitle: "Remove")
        }

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        input.placeholderString = "Customer update key"
        input.stringValue = updateKeyStore.load() ?? ""
        alert.accessoryView = input

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            let key = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                showUpdateKeySaveFailedAlert(message: "The update key cannot be empty.")
                return
            }
            do {
                try updateKeyStore.save(key)
                updaterController.startUpdater()
                configureAutomaticUpdateChecks()
                showUpdateKeySavedAlert()
            } catch {
                showUpdateKeySaveFailedAlert(message: "ZuluBar could not save the update key.")
            }
        case .alertThirdButtonReturn:
            do {
                try updateKeyStore.delete()
                configureAutomaticUpdateChecks()
                showUpdateKeyRemovedAlert()
            } catch {
                showUpdateKeySaveFailedAlert(message: "ZuluBar could not remove the update key.")
            }
        default:
            break
        }
    }

    private func showUpdateKeyRequiredAlert() {
        let alert = NSAlert()
        alert.messageText = "Update Key Required"
        alert.informativeText = "Enter your ZuluBar update key before checking for paid app updates."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showUpdateKeySavedAlert() {
        let alert = NSAlert()
        alert.messageText = "Update Key Saved"
        alert.informativeText = "ZuluBar paid updates are now enabled."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showUpdateKeyRemovedAlert() {
        let alert = NSAlert()
        alert.messageText = "Update Key Removed"
        alert.informativeText = "ZuluBar paid updates are disabled until a new update key is entered."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showUpdateKeySaveFailedAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Update Key Not Saved"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showInvalidUpdateKeyAlert() {
        let alert = NSAlert()
        alert.messageText = "Update Key Invalid"
        alert.informativeText = "ZuluBar could not verify your update key. Re-enter the key from your purchase email or recover your purchase from zulubar.app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func configureAutomaticUpdateChecks() {
        updaterController.updater.automaticallyChecksForUpdates = updateKeyStore.load() != nil
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

    /// UTC clipboard output, independent of any added city clocks.
    func getFormattedTimeForCopy(at date: Date = Date()) -> String {
        let format: UTCTimeFormatter.Format

        switch settings.copyFormat {
        case .display:
            format = .humanReadable(showSeconds: settings.showSeconds, suffix: settings.displaySuffix)
        case .unixTimestamp:
            format = .unixTimestamp
        case .rfc3339:
            format = .rfc3339
        }

        return UTCTimeFormatter.format(date, as: format)
    }

    /// Resolve the configured identifier again so a click on a removed clock
    /// cannot accidentally copy another clock after a reorder/removal.
    func getFormattedTimeForAdditionalClock(identifier: String, at date: Date = Date()) -> String? {
        guard let clock = settings.additionalClocks.first(where: { $0.identifier == identifier }) else { return nil }
        return ZoneClockFormatter.copy(for: clock, at: date, format: settings.copyFormat, showSeconds: settings.showSeconds)
    }

    /// Every clock in one refresh is derived from the same captured instant.
    func statusBarContent(at date: Date) -> (utcTitle: String, additional: [ClockStripEntry]) {
        let showSeconds = settings.showSeconds
        let display = StatusBarDisplay(
            dateFormat: settings.showDate ? settings.dateFormat : nil,
            timeFormat: .humanReadable(showSeconds: showSeconds, suffix: settings.displaySuffix)
        )
        let entries = settings.additionalClocks.compactMap { clock -> ClockStripEntry? in
            guard let face = ZoneClockFormatter.face(for: clock, at: date, showSeconds: showSeconds) else { return nil }
            return ClockStripEntry(identifier: clock.identifier, label: face.label, time: face.time)
        }
        return (StatusBarRenderer.render(display, at: date), entries)
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

    /// One shared timer, restarted after wake/clock changes and aligned to the
    /// next whole second. Retain the initial timer too, so restarts cancel it.
    func startTimer() {
        timer?.invalidate()
        let now = Date()
        let nanosecond = Calendar.current.component(.nanosecond, from: now)
        let delayToNextSecond = Double(1_000_000_000 - nanosecond) / 1_000_000_000.0

        let syncTimer = Timer(timeInterval: delayToNextSecond, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.updateUTC()
            let repeatingTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.updateUTC()
            }
            RunLoop.main.add(repeatingTimer, forMode: .common)
            self.timer = repeatingTimer
        }
        timer = syncTimer
        RunLoop.main.add(syncTimer, forMode: .common)
    }

    /// Feedback is per-clock presentation state; it never pauses other clocks.
    func updateUTC() {
        guard let clockStripController else { return }
        let content = statusBarContent(at: Date())
        clockStripController.render(utcTitle: content.utcTitle, additional: content.additional)
    }
}

#if IS_PAID_BUILD
extension AppDelegate: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard updateKeyStore.load() != nil else {
            throw NSError(
                domain: "app.zulubar.updates",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Enter your ZuluBar update key before checking for updates."]
            )
        }
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        UpdateFeedURLBuilder.build(baseURLString: paidFeedBaseURL, key: updateKeyStore.load())
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        guard Self.isInvalidKeyError(error) else {
            return
        }
        showInvalidUpdateKeyAlert()
    }

    private static func isInvalidKeyError(_ error: Error) -> Bool {
        guard let statusCode = httpStatusCode(in: error) else {
            return false
        }
        return statusCode == 401 || statusCode == 403
    }

    private static func httpStatusCode(in error: Error) -> Int? {
        var current: NSError? = error as NSError
        var seen = Set<ObjectIdentifier>()

        while let nsError = current {
            let identifier = ObjectIdentifier(nsError)
            guard !seen.contains(identifier) else {
                return nil
            }
            seen.insert(identifier)

            if let statusCode = nsError.userInfo["NSHTTPPropertyStatusCodeKey"] as? Int {
                return statusCode
            }

            if let response = nsError.userInfo["NSURLErrorFailingURLResponseErrorKey"] as? HTTPURLResponse {
                return response.statusCode
            }

            if let response = nsError.userInfo["NSErrorFailingURLResponseKey"] as? HTTPURLResponse {
                return response.statusCode
            }

            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }

        return nil
    }
}
#endif
