import Carbon.HIToolbox
import Foundation

/// Carbon-based global hotkey. Requires no Accessibility permission.
final class HotKey {
    static var handlers: [UInt32: @MainActor () -> Void] = [:]
    private static var installed = false
    private static var nextID: UInt32 = 1

    /// Returns false when the combination is already taken by another app.
    @discardableResult
    static func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping @MainActor () -> Void) -> Bool {
        if !installed {
            installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hk)
                let id = hk.id
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { HotKey.handlers[id]?() }
                }
                return noErr
            }, 1, &spec, nil, nil)
        }
        let id = nextID
        nextID += 1
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers,
                                         EventHotKeyID(signature: OSType(0x5A4D4E5A), id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr { handlers[id] = nil }
        return status == noErr
    }
}
