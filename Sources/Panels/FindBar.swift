import Core
import SwiftUI

/// Stato osservabile della ricerca nel terminale: query corrente e riepilogo posizione/totale.
/// Vive nel controller (composition root), la `FindBar` lo osserva e lo aggiorna.
@MainActor
@Observable
public final class FindModel {
    public var query: String = ""
    public var current: Int = 0
    public var total: Int = 0

    public init() {}

    /// Azzera i contatori (query lasciata invariata: la view la ripulisce alla chiusura).
    public func resetCounts() {
        current = 0
        total = 0
    }
}

/// Barra di ricerca flottante in alto a destra sul terminale (stile browser). Digita per cercare,
/// Invio o le frecce per scorrere i risultati, Esc per chiudere. Colori dal tema.
public struct FindBar: View {
    @Bindable var model: FindModel
    let theme: RelayTheme
    /// Esegue la ricerca nella direzione data (`true` = avanti). Chiamato mentre si digita e sui
    /// pulsanti/Invio.
    let onSearch: (Bool) -> Void
    let onClose: () -> Void
    @FocusState private var focused: Bool

    public init(
        model: FindModel,
        theme: RelayTheme,
        onSearch: @escaping (Bool) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.model = model
        self.theme = theme
        self.onSearch = onSearch
        self.onClose = onClose
    }

    private var colors: ChromeColors {
        ChromeColors(theme)
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(colors.secondary)
            field
            counter
            stepper(up: false)
            stepper(up: true)
            closeButton
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(colors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(colors.hover, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        )
    }

    private var field: some View {
        TextField("Cerca", text: $model.query)
            .textFieldStyle(.plain)
            .font(Theme.Typography.caption)
            .foregroundStyle(colors.foreground)
            .frame(width: 180)
            .focused($focused)
            .onAppear { focused = true }
            .onChange(of: model.query) { _, _ in onSearch(true) }
            .onSubmit { onSearch(true) }
            .onExitCommand(perform: onClose)
    }

    @ViewBuilder private var counter: some View {
        if !model.query.isEmpty {
            Text(model.total == 0 ? "0" : "\(model.current)/\(model.total)")
                .font(Theme.Typography.caption)
                .monospacedDigit()
                .foregroundStyle(model.total == 0 ? colors.secondary : colors.foreground)
        }
    }

    private func stepper(up: Bool) -> some View {
        Button { onSearch(!up) } label: {
            Image(systemName: up ? "chevron.down" : "chevron.up")
                .font(.system(size: 10, weight: .bold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.total == 0 ? colors.secondary.opacity(0.4) : colors.secondary)
        .disabled(model.total == 0)
        .help(up ? "Risultato successivo" : "Risultato precedente")
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(colors.secondary)
        .help("Chiudi (Esc)")
    }
}
