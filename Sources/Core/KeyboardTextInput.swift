import Foundation

/// Distinguishes Option-key text entry from app shortcuts. On international layouts Option often
/// behaves like AltGr: the physical key still has the Option modifier, but the user's intent is to
/// type the composed character reported by macOS. Exception: Option+1..9 (no Shift) is the fixed
/// select-tab shortcut and always wins over the typographic symbol the layout would compose
/// (e.g. Option+1 = "«" on Italian) - those symbols are unreachable while the shortcut exists.
public enum KeyboardTextInput {
    /// Modifier state of the key event, decoupled from AppKit so the policy stays pure.
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public init(option: Bool, shift: Bool, command: Bool, control: Bool) {
            var value = Modifiers()
            if option { value.insert(.option) }
            if shift { value.insert(.shift) }
            if command { value.insert(.command) }
            if control { value.insert(.control) }
            self = value
        }

        public static let option = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let command = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }

    public static func optionGeneratedText(
        characters: String?,
        charactersIgnoringModifiers: String?,
        modifiers: Modifiers
    ) -> String? {
        guard modifiers.contains(.option),
              modifiers.isDisjoint(with: [.command, .control]) else { return nil }
        if !modifiers.contains(.shift), isFixedSelectDigit(charactersIgnoringModifiers) {
            return nil
        }
        guard let characters, !characters.isEmpty else { return nil }
        guard characters != charactersIgnoringModifiers else { return nil }
        guard isPrintableText(characters) else { return nil }
        return characters
    }

    /// Base key of the fixed Option+1..9 tab shortcuts. `charactersIgnoringModifiers` still applies
    /// Shift, so on layouts where digits need Shift this only matches the unshifted digit row.
    private static func isFixedSelectDigit(_ base: String?) -> Bool {
        guard let base, base.count == 1, let digit = Int(base) else { return false }
        return (1 ... 9).contains(digit)
    }

    private static func isPrintableText(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x00 ..< 0x20, 0x7F ..< 0xA0:
                false
            case 0xF700 ... 0xF8FF:
                false
            default:
                !CharacterSet.controlCharacters.contains(scalar)
            }
        }
    }
}
