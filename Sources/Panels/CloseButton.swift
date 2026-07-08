import SwiftUI

/// Bottone di chiusura/dismiss condiviso: la `xmark` bold nuda (`.plain`, nessun bezel), colore e
/// dimensione dal chiamante (default 9; le affordance dense - tab bar, card dashboard - passano 8).
/// `help` obbligatorio (tooltip/accessibilità). Eventuali controlli di visibilità (es. `.opacity`
/// su hover) li applica il chiamante sopra la vista.
struct CloseButton: View {
    let color: Color
    var size: CGFloat = 9
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: size, weight: .bold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(color)
        .help(help)
    }
}
