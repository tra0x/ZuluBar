import Cocoa
import Carbon

/// A small floating panel that lets the user record or clear a keyboard shortcut.
///
/// Usage:
/// ```swift
/// let panel = HotKeyRecorderPanel(current: settings.copyShortcut)
/// panel.onShortcutChanged = { [weak self] shortcut in ... }
/// panel.makeKeyAndOrderFront(nil)
/// ```
class HotKeyRecorderPanel: NSPanel {

    // MARK: - Public

    /// Called immediately when the user records a new shortcut or clears the existing one.
    var onShortcutChanged: ((HotKey?) -> Void)?

    // MARK: - Private

    private let shortcutLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let recordButton = NSButton()
    private let clearButton = NSButton()
    private let doneButton = NSButton()

    private var currentShortcut: HotKey?
    private var shortcutBeforeAttempt: HotKey?
    private var isRecording = false
    private var localEventMonitor: Any?

    // MARK: - Init

    init(current: HotKey?) {
        self.currentShortcut = current
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 150),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = "Copy Shortcut"
        isFloatingPanel = true
        level = .floating
        isReleasedWhenClosed = false
        setupUI()
        updateDisplay(animated: false)
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = contentView else { return }

        // Shortcut label — large display of the current binding
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutLabel.alignment = .center
        shortcutLabel.font = .monospacedSystemFont(ofSize: 22, weight: .medium)
        contentView.addSubview(shortcutLabel)

        // Hint label — secondary instruction text
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.alignment = .center
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        contentView.addSubview(hintLabel)

        // Record button
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.bezelStyle = .rounded
        recordButton.target = self
        recordButton.action = #selector(toggleRecording)
        contentView.addSubview(recordButton)

        // Clear button
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.title = "Clear"
        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(clearShortcut)
        contentView.addSubview(clearButton)

        // Done button (default action)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.title = "Done"
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.target = self
        doneButton.action = #selector(done)
        contentView.addSubview(doneButton)

        NSLayoutConstraint.activate([
            shortcutLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            shortcutLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            shortcutLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16),
            shortcutLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),

            hintLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: shortcutLabel.bottomAnchor, constant: 4),

            recordButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            recordButton.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 10),
            recordButton.widthAnchor.constraint(equalToConstant: 140),

            clearButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            clearButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            doneButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            doneButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    // MARK: - Display

    private func updateDisplay(animated: Bool) {
        if isRecording {
            shortcutLabel.stringValue = "…"
            shortcutLabel.textColor = .tertiaryLabelColor
            hintLabel.stringValue = "Press a key combination  (Esc to cancel)"
            recordButton.title = "Cancel"
            clearButton.isEnabled = false
        } else if let shortcut = currentShortcut {
            shortcutLabel.stringValue = shortcut.display
            shortcutLabel.textColor = .labelColor
            hintLabel.stringValue = "Click Record to change"
            recordButton.title = "Record"
            clearButton.isEnabled = true
        } else {
            shortcutLabel.stringValue = "—"
            shortcutLabel.textColor = .tertiaryLabelColor
            hintLabel.stringValue = "No shortcut set"
            recordButton.title = "Record"
            clearButton.isEnabled = false
        }
    }

    // MARK: - Actions

    @objc private func toggleRecording() {
        if isRecording {
            stopRecording(restoreDisplay: true)
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        updateDisplay(animated: true)

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleCapturedKey(event)
            return nil  // consume the event
        }
    }

    private func stopRecording(restoreDisplay: Bool) {
        isRecording = false
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if restoreDisplay {
            updateDisplay(animated: false)
        }
    }

    private func handleCapturedKey(_ event: NSEvent) {
        // Esc cancels without saving
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording(restoreDisplay: true)
            return
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

        // Require at least one of ⌘, ⌃, or ⌥ — shift-only shortcuts are not valid
        guard modifiers.contains(.command) || modifiers.contains(.option) || modifiers.contains(.control) else {
            shortcutLabel.stringValue = "Add ⌘, ⌃, or ⌥"
            shortcutLabel.textColor = .systemOrange
            return
        }

        let shortcut = HotKey(keyCode: event.keyCode, modifierFlags: modifiers)

        stopRecording(restoreDisplay: false)
        shortcutBeforeAttempt = currentShortcut
        currentShortcut = shortcut
        updateDisplay(animated: false)
        onShortcutChanged?(shortcut)
        // If registration failed, registrationFailed() was called synchronously above
        // and has already restored currentShortcut and updated the display.
    }

    @objc private func clearShortcut() {
        stopRecording(restoreDisplay: false)
        currentShortcut = nil
        updateDisplay(animated: false)
        onShortcutChanged?(nil)
    }

    /// Called by the owner when a shortcut recorded via `onShortcutChanged` could not be
    /// registered (e.g. the key combo is claimed by macOS or another app). Rolls the
    /// display back to the previous binding and shows a brief error message.
    func registrationFailed() {
        currentShortcut = shortcutBeforeAttempt
        shortcutLabel.stringValue = "Already claimed"
        shortcutLabel.textColor = .systemRed
        hintLabel.stringValue = "That combo is taken by another app"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.updateDisplay(animated: false)
        }
    }

    @objc private func done() {
        stopRecording(restoreDisplay: false)
        orderOut(nil)
    }

    // MARK: - Panel Lifecycle

    override func close() {
        stopRecording(restoreDisplay: false)
        super.close()
    }
}
