import SwiftUI

/// Pallino di stato riusabile: pieno o anello vuoto, dimensione dai token `Theme.Metrics`. Il
/// colore (con l'eventuale opacità) lo passa il chiamante, così distinzioni come `unseen` (pieno)
/// vs `pending` (anello) o le opacità 0.55/0.50 restano governate a monte, non nel componente.
struct StatusDot: View {
    enum Style {
        case solid
        case ring
    }

    let color: Color
    var style: Style = .solid
    var size: CGFloat = Theme.Metrics.statusDot

    var body: some View {
        Group {
            switch style {
            case .solid:
                Circle().fill(color)
            case .ring:
                Circle().strokeBorder(color, lineWidth: Theme.Metrics.statusRingWidth)
            }
        }
        .frame(width: size, height: size)
    }
}
