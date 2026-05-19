import Carbon
import AppKit

// C-compatible free function for the Carbon event callback
private func carbonHotkeyCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ theEvent: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let ptr = userData else { return OSStatus(noErr) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()
    DispatchQueue.main.async { manager.fire() }
    return OSStatus(noErr)
}

/// Registers a system-wide Shift+Space hotkey via Carbon Event Manager.
/// Does NOT require Accessibility permission.
class HotkeyManager {
    var onHotkeyPressed: (() -> Void)?

    private var handlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    func register(keyCode: UInt32, modifiers: UInt32) {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // InstallEventHandler on the application event target
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyCallback,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )

        guard status == noErr else {
            print("HotkeyManager: failed to install event handler (\(status))")
            return
        }

        var hotkeyID = EventHotKeyID()
        hotkeyID.signature = OSType(0x4D53594E)  // 'MSYN'
        hotkeyID.id = 1

        let regStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if regStatus == noErr {
            print("HotkeyManager: Shift+Space registered (Carbon)")
        } else {
            print("HotkeyManager: registration failed (\(regStatus))")
        }
    }

    func unregister() {
        if let ref = hotKeyRef  { UnregisterEventHotKey(ref) }
        if let ref = handlerRef { RemoveEventHandler(ref) }
        hotKeyRef  = nil
        handlerRef = nil
    }

    func fire() {
        onHotkeyPressed?()
    }
}
