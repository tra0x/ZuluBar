import Carbon
import Cocoa

/// A resolved keyboard shortcut binding (key code + modifiers).
/// `display` and `carbonModifiers` are computed from the stored fields, so
/// persistence only needs to serialize `keyCode` and `modifierFlags`.
struct HotKey: Equatable {
    let keyCode: UInt16
    let modifierFlags: NSEvent.ModifierFlags

    /// Human-readable display string, e.g. "⌘⇧C".
    var display: String {
        var result = ""
        if modifierFlags.contains(.control) { result += "⌃" }
        if modifierFlags.contains(.option)  { result += "⌥" }
        if modifierFlags.contains(.shift)   { result += "⇧" }
        if modifierFlags.contains(.command) { result += "⌘" }
        result += Self.keyName(for: keyCode)
        return result
    }

    /// Carbon modifier flags corresponding to `modifierFlags`.
    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifierFlags.contains(.command) { result |= UInt32(cmdKey) }
        if modifierFlags.contains(.shift)   { result |= UInt32(shiftKey) }
        if modifierFlags.contains(.option)  { result |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    // MARK: - Key name translation

    private static let namedKeys: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
        101: "F9", 103: "F11", 105: "F13", 107: "F14", 109: "F10",
        111: "F12", 113: "F15", 115: "↖", 116: "⇞", 117: "⌦",
        118: "F4", 119: "↘", 120: "F2", 121: "⇟", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    private static func keyName(for keyCode: UInt16) -> String {
        if let name = namedKeys[keyCode] { return name }
        return characterName(for: keyCode) ?? "(\(keyCode))"
    }

    /// Translates a virtual key code to its unmodified character using the current keyboard layout.
    private static func characterName(for keyCode: UInt16) -> String? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        guard let layoutDataRef = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataRef).takeUnretainedValue() as Data

        return layoutData.withUnsafeBytes { rawBuffer -> String? in
            guard let layoutPtr = rawBuffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var unicodeChars = [UniChar](repeating: 0, count: 4)
            var charCount = 0
            let status = UCKeyTranslate(
                layoutPtr,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                4,
                &charCount,
                &unicodeChars
            )
            guard status == noErr, charCount > 0 else { return nil }
            let scalars = unicodeChars[0..<charCount].compactMap { Unicode.Scalar(UInt32($0)) }
            let string = String(String.UnicodeScalarView(scalars)).uppercased()
            return string.isEmpty ? nil : string
        }
    }
}
