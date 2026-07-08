import Core
import SwiftUI
import WorkspaceModel

/// Pannello impostazioni (Cmd+,). Layout master-detail: sidebar con ricerca + lista categorie a
/// sinistra, contenuto a destra. Ogni impostazione è un "blocco" dichiarativo (categoria + keywords
/// + vista): unica fonte per categorie e ricerca, così aggiungere una voce è una riga. Le scelte
/// passano per i setter di `AppSettings`.
public struct SettingsView: View {
    let settings: AppSettings
    let hooks: HookControls?
    let naming: NamingControls?
    @State private var search = ""
    @State private var category: SettingsCategory = .appearance

    public init(
        settings: AppSettings,
        hooks: HookControls? = nil,
        naming: NamingControls? = nil
    ) {
        self.settings = settings
        self.hooks = hooks
        self.naming = naming
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        HStack(spacing: 0) {
            sidebar(colors)
            Divider()
            detail(colors)
        }
        .frame(width: 580, height: 400)
        .background(colors.background)
    }

    // MARK: - Sidebar

    private func sidebar(_ colors: ChromeColors) -> some View {
        VStack(spacing: 0) {
            searchBar(colors)
            Divider()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(SettingsCategory.allCases) { item in
                        CategoryRow(
                            category: item,
                            selected: category == item && search.isEmpty,
                            colors: colors,
                            onSelect: {
                                category = item
                                search = ""
                            }
                        )
                    }
                }
                .padding(Theme.Spacing.sm)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 184)
    }

    private func searchBar(_ colors: ChromeColors) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(colors.secondary)
            TextField("Search", text: $search)
                .textFieldStyle(.plain)
                .font(Theme.Typography.item)
                .foregroundStyle(colors.foreground)
            if !search.isEmpty {
                Button { search = "" } label: {
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

    private func detail(_ colors: ChromeColors) -> some View {
        let blocks = allBlocks(colors)
        let shown: [SettingsBlock]
        let empty: String?
        if search.isEmpty {
            shown = blocks.filter { $0.category == category }
            empty = nil
        } else {
            let query = search.lowercased()
            shown = blocks.filter { block in block.keywords.contains { $0.contains(query) } }
            empty = "No settings match \u{201C}\(search)\u{201D}"
        }

        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if shown.isEmpty, let empty {
                    Text(empty)
                        .font(Theme.Typography.item)
                        .foregroundStyle(colors.secondary)
                } else {
                    ForEach(shown) { $0.view }
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
