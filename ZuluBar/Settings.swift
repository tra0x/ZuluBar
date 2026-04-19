import Cocoa

/// Available formats for copying time to clipboard.
enum CopyFormat: String, CaseIterable {
    case display = "Display"
    case unixTimestamp = "Unix Timestamp"
    case rfc3339 = "RFC 3339"
}

/// UserDefaults-backed user preferences.
/// The `defaults` parameter is injectable so tests can use a scoped suite
/// instead of polluting `UserDefaults.standard`.
struct Settings {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Keys {
        static let showSeconds = "showSeconds"
        static let showDate = "showDate"
        static let dateFormat = "dateFormat"
        static let displaySuffix = "displaySuffix"
        static let copyFormat = "copyFormat"
        static let copyShortcutKeyCode = "copyShortcutKeyCode"
        static let copyShortcutModifiers = "copyShortcutModifiers"
        static let copyShortcutDisplay = "copyShortcutDisplay"  // legacy (pre-PR#2); no longer written
    }

    var showSeconds: Bool {
        get { defaults.object(forKey: Keys.showSeconds) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.showSeconds) }
    }

    var showDate: Bool {
        get { defaults.object(forKey: Keys.showDate) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.showDate) }
    }

    var dateFormat: DateFormat {
        get {
            guard let raw = defaults.string(forKey: Keys.dateFormat),
                  let format = DateFormat(rawValue: raw) else { return .dayMonthDate }
            return format
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.dateFormat) }
    }

    var displaySuffix: UTCTimeFormatter.Suffix {
        get {
            guard let raw = defaults.string(forKey: Keys.displaySuffix),
                  let suffix = UTCTimeFormatter.Suffix(rawValue: raw) else { return .z }
            return suffix
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.displaySuffix) }
    }

    var copyFormat: CopyFormat {
        get {
            if let raw = defaults.string(forKey: Keys.copyFormat) {
                if raw == "Human Readable" { return .display }  // legacy value (pre-0.2.0)
                if let format = CopyFormat(rawValue: raw) { return format }
            }
            return .display
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.copyFormat) }
    }

    var copyShortcut: HotKey? {
        get {
            guard let keyCodeInt = defaults.object(forKey: Keys.copyShortcutKeyCode) as? Int else { return nil }
            let keyCode = UInt16(clamping: keyCodeInt)
            let raw = UInt(bitPattern: defaults.integer(forKey: Keys.copyShortcutModifiers))
            return HotKey(keyCode: keyCode, modifierFlags: NSEvent.ModifierFlags(rawValue: raw))
        }
        set {
            if let shortcut = newValue {
                defaults.set(Int(shortcut.keyCode), forKey: Keys.copyShortcutKeyCode)
                defaults.set(Int(bitPattern: UInt(shortcut.modifierFlags.rawValue)), forKey: Keys.copyShortcutModifiers)
                defaults.removeObject(forKey: Keys.copyShortcutDisplay)  // drop legacy value on any write
            } else {
                defaults.removeObject(forKey: Keys.copyShortcutKeyCode)
                defaults.removeObject(forKey: Keys.copyShortcutModifiers)
                defaults.removeObject(forKey: Keys.copyShortcutDisplay)
            }
        }
    }
}
