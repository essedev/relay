import SwiftUI

/// Pill monospace condivisa: keycap delle scorciatoie e chip dei comandi shell. Font mono 11 con
/// sfondo tenue derivato da `hover` e angoli `Radius.sm`. Le differenze reali dei call-site sono
/// parametri (peso, colore del testo, larghezza minima, opacità dello sfondo, bordo dello stato
/// "recording", selezionabilità); il contenuto è generico per i chip a due tinte (prompt colorato
/// + comando). Il padding verticale (3) vive qui: è la metrica del chip, tarata sull'allineamento
/// della griglia dei keycap.
struct CommandChip<Content: View>: View {
    private let colors: ChromeColors
    private let weight: Font.Weight
    private let foreground: Color?
    private let minWidth: CGFloat?
    private let fill: Double
    private let border: Color?
    private let selectable: Bool
    private let content: Content

    init(
        colors: ChromeColors,
        weight: Font.Weight = .medium,
        foreground: Color? = nil,
        minWidth: CGFloat? = nil,
        fill: Double = 0.4,
        border: Color? = nil,
        selectable: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.colors = colors
        self.weight = weight
        self.foreground = foreground
        self.minWidth = minWidth
        self.fill = fill
        self.border = border
        self.selectable = selectable
        self.content = content()
    }

    var body: some View {
        let styled = content
            .font(.system(size: 11, weight: weight, design: .monospaced))
            .foregroundStyle(foreground ?? colors.foreground)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 3)
            .frame(minWidth: minWidth)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(colors.hover.opacity(fill))
            )
            .overlay {
                if let border {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(border, lineWidth: 1)
                }
            }
        // `.disabled` è già il default: applico `.enabled` solo quando serve (i due
        // TextSelectability sono tipi distinti, quindi non un ternario).
        if selectable {
            styled.textSelection(.enabled)
        } else {
            styled
        }
    }
}

extension CommandChip where Content == Text {
    /// Chip da una stringa (keycap o comando).
    init(
        _ label: String,
        colors: ChromeColors,
        weight: Font.Weight = .medium,
        foreground: Color? = nil,
        minWidth: CGFloat? = nil,
        fill: Double = 0.4,
        border: Color? = nil,
        selectable: Bool = false
    ) {
        self.init(
            colors: colors,
            weight: weight,
            foreground: foreground,
            minWidth: minWidth,
            fill: fill,
            border: border,
            selectable: selectable
        ) { Text(label) }
    }
}
