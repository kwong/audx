import AppKit
import Carbon

class HotKeyManager {
    static let shared = HotKeyManager()
    var onHotKeyPressed: (() -> Void)?
    
    private var hotKeyRef: EventHotKeyRef?
    
    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        // This C-function pointer is passed to Carbon
        let handler: EventHandlerUPP = { (_, _, _) -> OSStatus in
            DispatchQueue.main.async {
                HotKeyManager.shared.onHotKeyPressed?()
            }
            return noErr
        }
        
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)
    }
    
    func register(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        // Unregister previous hotkey if any
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        
        // Convert NSEvent modifiers to Carbon modifiers
        var carbonMods: UInt32 = 0
        if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if modifiers.contains(.option) { carbonMods |= UInt32(optionKey) }
        if modifiers.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
        
        // Create an ID specifically foraudx
        let hotKeyID = EventHotKeyID(signature: OSType(0x41554458), id: 1) // 'AUDX'
        
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), carbonMods, hotKeyID, GetApplicationEventTarget(), 0, &newRef)
        
        if status == noErr {
            hotKeyRef = newRef
        } else {
            print("Failed to register global hotkey, error \(status)")
        }
    }
    
    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
