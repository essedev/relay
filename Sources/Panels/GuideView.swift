import SwiftUI
import WorkspaceModel

/// Il manuale dentro l'app (Help > Relay Guide): overlay full-window con lista sezioni a sinistra,
/// contenuto a destra e ricerca, sul modello di `SettingsView`. Il contenuto **non** è qui: viene
/// da `Guide.sections` (WorkspaceModel), la stessa fonte da cui `make guide-md` genera
/// `docs/GUIDE.md`. Qui c'è solo la resa: come si disegna un blocco.
///
/// Perché non dentro le impostazioni: le impostazioni sono il posto dove si **cambia** qualcosa,
/// la guida quello dove si **legge**. Tenerle separate lascia corte le liste di `Cmd+,`.
public struct GuideView: View {
    let settings: AppSettings
    let onClose: () -> Void

    @State private var query = ""
    @State private var selectedID = Guide.sections.first?.id ?? ""
    @FocusState private var searchFocused: Bool

    private static let panelWidth: CGFloat = 820
    private static let panelHeight: CGFloat = 580

    public init(settings: AppSettings, onClose: @escaping () -> Void) {
        self.settings = settings
        self.onClose = onClose
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.35)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                panel(colors, size: Self.panelSize(in: geo.size))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onExitCommand(perform: onClose)
        // Come la dashboard: il focus al campo va ritentato, il set in `onAppear` è una race col
        // primo layout e, se cade, il pannello resta sordo a Esc e frecce.
        .task { searchFocused = true }
    }

    /// Fissa ma clampata alla finestra, stessa regola della dashboard (il minimo finestra è
    /// 700x460: un frame fisso puro verrebbe tagliato).
    static func panelSize(in available: CGSize) -> CGSize {
        let inset = Theme.Spacing.lg * 2
        return CGSize(
            width: min(panelWidth, max(0, available.width - inset)),
            height: min(panelHeight, max(0, available.height - inset))
        )
    }

    private var matches: [GuideSection] {
        Guide.sections.filter { $0.matches(query) }
    }

    private var shown: GuideSection? {
        matches.first { $0.id == selectedID } ?? matches.first
    }

    private func panel(_ colors: ChromeColors, size: CGSize) -> some View {
        HStack(spacing: 0) {
            sidebar(colors)
            Divider()
            detail(colors)
        }
        .frame(width: size.width, height: size.height)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(colors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(colors.hover, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    // MARK: - Sidebar

    private func sidebar(_ colors: ChromeColors) -> some View {
        VStack(spacing: 0) {
            searchBar(colors)
            Divider()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(matches) { section in
                        GuideSectionRow(
                            section: section,
                            selected: section.id == shown?.id,
                            colors: colors,
                            onSelect: { selectedID = section.id }
                        )
                    }
                    if matches.isEmpty {
                        Text("Nothing matches \u{201C}\(query)\u{201D}")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(colors.secondary)
                            .padding(.top, Theme.Spacing.md)
                    }
                }
                .padding(Theme.Spacing.sm)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 208)
    }

    private func searchBar(_ colors: ChromeColors) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.subtitle)
                .foregroundStyle(colors.secondary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.Typography.item)
                .foregroundStyle(colors.foreground)
                .focused($searchFocused)
                .onExitCommand(perform: onClose)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(colors.secondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: 40)
    }

    // MARK: - Detail

    @ViewBuilder
    private func detail(_ colors: ChromeColors) -> some View {
        if let section = shown {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(section.title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(colors.foreground)
                        Text(section.summary)
                            .font(Theme.Typography.item)
                            .foregroundStyle(colors.secondary)
                    }
                    ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                        GuideBlockView(block: block, settings: settings, colors: colors)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // La sezione cambia sotto lo scroll: riparti dall'alto invece che a metà pagina.
            .id(section.id)
        } else {
            Spacer()
        }
    }
}

/// Riga di una sezione nella lista: simbolo, titolo, selezione e hover dal tema (come `CategoryRow`
/// delle impostazioni, che però è chiavata su `SettingsCategory`).
struct GuideSectionRow: View {
    let section: GuideSection
    let selected: Bool
    let colors: ChromeColors
    let onSelect: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: section.symbol)
                .font(Theme.Typography.rowIcon)
                .frame(width: 18)
                .foregroundStyle(selected ? colors.accent : colors.secondary)
            Text(section.title)
                .font(Theme.Typography.item)
                .foregroundStyle(colors.foreground)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(selected ? colors.selection : hovered ? colors.hover : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovered = $0 }
    }
}
