import AppKit
import WorkspaceModel

/// Converte un `NSEvent` di tastiera nella `KeyCombo` pura del model (che non conosce AppKit). Vive
/// in Panels così lo usano sia il recorder (qui) sia il monitor nel composition root (relay sta
/// sopra Panels). Tasti speciali per keyCode (stabile), caratteri normali via
/// `charactersIgnoringModifiers` minuscolo; scarta caratteri di controllo/funzione non gestiti.
public enum KeyEventBridge {
    public static func combo(from event: NSEvent) -> KeyCombo? {
        guard let key = keyName(from: event) else { return nil }
        var mods: KeyCombo.Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        return KeyCombo(key: key, modifiers: mods)
    }

    static func keyName(from event: NSEvent) -> String? {
        if let name = specialKeys[event.keyCode] { return name }
        guard let chars = event.charactersIgnoringModifiers, chars.count == 1,
              let scalar = chars.unicodeScalars.first,
              scalar.value >= 0x20, scalar.value < 0x7F
        else { return nil }
        return chars.lowercased()
    }

    private static let specialKeys: [UInt16: String] = [
        48: "tab", 49: "space", 36: "return", 51: "delete", 53: "escape",
        123: "left", 124: "right", 125: "down", 126: "up",
    ]
}
