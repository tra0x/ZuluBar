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
        static let additionalClocks = "additionalClocks.v1"
    }

    // Links from the tzdb 'backward' file that resolve to the fixed-zero
    // UTC/GMT zone — not geographic zones that merely happen to sit at
    // offset zero today (e.g. Africa/Abidjan), which stay selectable.
    private static let utcAliasIdentifiers: Set<String> = [
        "UTC", "Etc/UTC", "Zulu", "Etc/Zulu", "Universal", "Etc/Universal",
        "UCT", "Etc/UCT", "GMT", "Etc/GMT", "GMT0", "Etc/GMT0",
        "GMT+0", "Etc/GMT+0", "GMT-0", "Etc/GMT-0", "Greenwich", "Etc/Greenwich",
    ]

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

    /// Ordered, opt-in extra city clocks. Decoding is entry-by-entry so one
    /// malformed/duplicate/disallowed entry doesn't discard the rest; a
    /// corrupt or non-array top-level value safely reads as `[]`. Never
    /// mutates `defaults` as a side effect of reading.
    var additionalClocks: [AdditionalClock] {
        get {
            guard let data = defaults.data(forKey: Keys.additionalClocks) else { return [] }
            guard let rawObject = try? JSONSerialization.jsonObject(with: data) else { return [] }
            guard let rawArray = rawObject as? [Any] else { return [] }

            var seenIdentifiers = Set<String>()
            var result: [AdditionalClock] = []
            for rawEntry in rawArray {
                guard let dict = rawEntry as? [String: Any],
                      let entryData = try? JSONSerialization.data(withJSONObject: dict),
                      let clock = try? JSONDecoder().decode(AdditionalClock.self, from: entryData) else { continue }
                guard TimeZone(identifier: clock.identifier) != nil else { continue }
                guard !Self.utcAliasIdentifiers.contains(clock.identifier) else { continue }
                guard !seenIdentifiers.contains(clock.identifier) else { continue }
                seenIdentifiers.insert(clock.identifier)
                result.append(clock)
            }
            return result
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Keys.additionalClocks)
        }
    }
}
