import Foundation

/// Distinguishes Option-key text entry from app shortcuts. On international layouts Option often
/// behaves like AltGr: the physical key still has the Option modifier, but the user's intent is to
/// type the composed character reported by macOS.
public enum KeyboardTextInput {
    public static func optionGeneratedText(
        characters: String?,
        charactersIgnoringModifiers: String?,
        hasOption: Bool,
        hasCommand: Bool,
        hasControl: Bool
    ) -> String? {
        guard hasOption, !hasCommand, !hasControl else { return nil }
        guard let characters, !characters.isEmpty else { return nil }
        guard characters != charactersIgnoringModifiers else { return nil }
        guard isPrintableText(characters) else { return nil }
        return characters
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
