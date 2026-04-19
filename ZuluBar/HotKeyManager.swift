import Carbon
import Cocoa

/// Owns the Carbon global hot-key registration for the app.
///
/// The API is deliberately shaped so UserDefaults and Carbon cannot drift
/// apart: `activate(_:)` returns `false` if registration fails, and the
/// caller is expected to persist the hotkey only after a successful return.
/// On failure, the previous binding is left intact.
final class HotKeyManager {

    /// Called on the main thread whenever the registered hot key fires.
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init() {
        installHandler()
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let handler = handlerRef { RemoveEventHandler(handler) }
    }

    /// Attempts to register `hotKey` as the global shortcut. Passing `nil`
    /// clears any current binding.
    /// - Returns: `true` on success (or when passed `nil`). On `false`, the
    ///   previous binding remains active.
    @discardableResult
    func activate(_ hotKey: HotKey?) -> Bool {
        guard let hotKey = hotKey else {
            unregister()
            return true
        }

        var id = EventHotKeyID()
        id.signature = 0x5A554C55  // "ZULU"
        id.id = 1

        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(hotKey.keyCode),
            hotKey.carbonModifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &newRef
        )

        guard status == noErr, let newRef = newRef else {
            return false
        }

        // New registration succeeded — safe to release the previous one.
        unregister()
        hotKeyRef = newRef
        return true
    }

    private func unregister() {
        guard let ref = hotKeyRef else { return }
        UnregisterEventHotKey(ref)
        hotKeyRef = nil
    }

    private func installHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let ptr = userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(ptr).takeUnretainedValue()
                manager.onTrigger?()
                return noErr
            },
            1,
            &eventSpec,
            selfPointer,
            &handlerRef
        )
    }
}
