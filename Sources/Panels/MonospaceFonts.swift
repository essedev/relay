import AppKit

/// Elenco dei font monospace installati, per il picker delle impostazioni. Il terminale ha senso
/// solo con font a spaziatura fissa, quindi filtriamo i family il cui font rappresentativo è
/// `isFixedPitch`. Calcolato una volta (l'enumerazione dei font non è gratis).
enum MonospaceFonts {
    static let families: [String] = {
        let manager = NSFontManager.shared
        return manager.availableFontFamilies.filter { family in
            let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
            guard let font = NSFont(descriptor: descriptor, size: 12) else { return false }
            return font.isFixedPitch
        }
        .sorted()
    }()
}
