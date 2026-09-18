import Core
import SwiftUI
import WorkspaceModel

// Le pagine dell'onboarding (la pagina "attenzione" vive in OnboardingAttention.swift). Ogni
// pagina mostra i componenti veri del design system (badge, keycap, temi) al posto di screenshot:
// dimostrano se stessi e seguono il tema corrente.

// MARK: - Welcome

struct WelcomePage: View {
    let colors: ChromeColors

    var body: some View {
        // Niente Spacer per centrare: la pagina sta in uno ScrollView, dove uno Spacer collassa.
        // Il centraggio verticale lo fa l'allineamento del contenitore (`OnboardingView.panel`).
        VStack(spacing: Theme.Spacing.sm) {
            RelayMarkView(size: 88)
                .padding(.bottom, Theme.Spacing.sm)
            Text("Welcome to Relay")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(colors.foreground)
            Text("The agent-aware terminal")
                .font(Theme.Typography.item)
                .foregroundStyle(colors.secondary)
            HStack(spacing: Theme.Spacing.sm) {
                feature("square.grid.2x2", "Workspaces",
                        "One calm home for every project and its tabs.")
                feature("dot.radiowaves.left.and.right", "Live agent state",
                        "Relay reads Claude Code and Codex hooks, not terminal output.")
                feature("bell.badge", "Attention signals",
                        "Know what needs you, ignore what does not.")
            }
            .padding(.top, Theme.Spacing.lg)
        }
        .frame(maxWidth: .infinity)
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(colors.accent)
                .frame(height: 22)
            Text(title)
                .font(Theme.Typography.item.weight(.medium))
                .foregroundStyle(colors.foreground)
            Text(detail)
                .font(Theme.Typography.caption)
                .foregroundStyle(colors.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(colors.selection.opacity(0.3))
        )
    }
}

/// Icona di Relay disegnata in SwiftUI (stessa geometria di `bundle/make-icon.swift`): sempre
/// disponibile e nitida, anche nei build di sviluppo senza bundle (dove `NSApp` non ha l'icona).
/// Palette fissa Relay Dark, come l'icona vera: è il marchio, non segue il tema.
struct RelayMarkView: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.196, green: 0.220, blue: 0.267), // #323844
                            Color(red: 0.129, green: 0.145, blue: 0.169), // #21252B
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .stroke(.white.opacity(0.06), lineWidth: 1)
                )
            chevron
                .stroke(
                    Color(red: 0.380, green: 0.686, blue: 0.937), // #61AFEF
                    style: StrokeStyle(lineWidth: size * 0.094, lineCap: .round, lineJoin: .round)
                )
            RoundedRectangle(cornerRadius: size * 0.026, style: .continuous)
                .fill(Color(red: 0.851, green: 0.863, blue: 0.886)) // #D9DCE2
                .frame(width: size * 0.170, height: size * 0.469)
                .offset(x: size * (0.569 + 0.170 / 2 - 0.5), y: size * (0.279 + 0.469 / 2 - 0.5))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: size * 0.07, y: size * 0.03)
    }

    /// Coordinate normalizzate sullo squircle, ricavate da `bundle/make-icon.swift`.
    private var chevron: Path {
        Path { path in
            path.move(to: CGPoint(x: size * 0.307, y: size * 0.373))
            path.addLine(to: CGPoint(x: size * 0.464, y: size * 0.514))
            path.addLine(to: CGPoint(x: size * 0.307, y: size * 0.655))
        }
    }
}

// MARK: - Hooks

/// L'unica pagina azionabile: senza hook Relay è un terminale muto. Riusa `AgentHooksBlock`
/// (Impostazioni > Agents): stato live + install con il relay-cli impacchettato.
struct HooksPage: View {
    let colors: ChromeColors
    let hooks: [HookControls]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            PageHeader(
                "Connect your coding agents",
                subtitle: "Relay reads Claude Code and Codex hooks: callbacks that report "
                    + "when a session starts, asks for input or finishes. No output parsing.",
                colors: colors
            )
            if hooks.isEmpty {
                manualSetup
            } else {
                ForEach(hooks) { controls in
                    AgentHooksBlock(hooks: controls, colors: colors)
                        .padding(Theme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.md)
                                .fill(colors.surface)
                        )
                }
            }
            HStack(spacing: Theme.Spacing.sm) {
                CommandChip(colors: colors) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("\u{276F}")
                            .foregroundStyle(colors.accent)
                        Text("claude / codex")
                    }
                }
                Text("Once installed, run either agent in any tab: the badge lights up "
                    + "on its own.")
                    .font(Theme.Typography.item)
                    .foregroundStyle(colors.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Theme.Spacing.xs)
            Text("Install or remove them anytime in Settings > Agents. Relay preserves your "
                + "existing hooks. In Codex, review the configuration with /hooks after setup "
                + "and whenever the hook definitions change.")
                .font(Theme.Typography.caption)
                .foregroundStyle(colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var manualSetup: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("The bundled relay-cli is not reachable from this build. Install the hooks "
                + "from a terminal:")
                .font(Theme.Typography.item)
                .foregroundStyle(colors.foreground)
                .fixedSize(horizontal: false, vertical: true)
            CommandChip("relay-cli hooks setup all", colors: colors, selectable: true)
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(colors.surface)
        )
    }
}

// MARK: - Navigation

/// Le scorciatoie chiave, lette dai binding correnti (`settings.binding`): se l'utente rimappa,
/// l'onboarding mostra le combo vere. `Cmd/Option+1..9` sono fissi. `Grid` per colonne allineate.
struct NavigationPage: View {
    let colors: ChromeColors
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            PageHeader(
                "Find your way",
                subtitle: "Everything is one keystroke away. These are the ones worth "
                    + "learning first.",
                colors: colors
            )
            // Otto righe, non tutte: questa è la lista minima per partire. L'elenco completo
            // (Option come testo, clear, e il resto) è in Help > Relay Guide.
            Grid(
                alignment: .leadingFirstTextBaseline,
                horizontalSpacing: Theme.Spacing.lg,
                verticalSpacing: Theme.Spacing.sm
            ) {
                shortcut(combo(.toggleDashboard), "Dashboard",
                         "every session sorted by urgency; type to filter, Return to jump")
                shortcut(combo(.nextAttention), "Next attention",
                         "cycle through whatever is waiting for you")
                shortcut("\u{2318}1\u{2013}9", "Switch workspace", "follows the sidebar order")
                shortcut("\u{2325}1\u{2013}9", "Switch tab", "within the current workspace")
                shortcut(combo(.newTab), "New tab", "inherits the directory you are working in")
                shortcut(combo(.splitRight), "Split the view",
                         "a pane beside this one; \(combo(.splitDown)) splits below")
                shortcut(combo(.focusNextPane), "Next pane",
                         "move the keyboard between the panes on screen")
                shortcut(combo(.find), "Find in terminal", "with next and previous matches")
            }
            Text("Every shortcut except \u{2318}1\u{2013}9 and non-text \u{2325}1\u{2013}9 is "
                + "remappable in Settings > Shortcuts.")
                .font(Theme.Typography.caption)
                .foregroundStyle(colors.secondary)
                .padding(.top, Theme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func combo(_ action: ShortcutAction) -> String {
        settings.binding(for: action).display
    }

    private func shortcut(_ keys: String, _ title: String, _ detail: String) -> some View {
        GridRow {
            CommandChip(keys, colors: colors, minWidth: 48)
                .gridColumnAlignment(.trailing)
            Text(title)
                .font(Theme.Typography.item.weight(.medium))
                .foregroundStyle(colors.foreground)
                .fixedSize()
            Text(detail)
                .font(Theme.Typography.caption)
                .foregroundStyle(colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .gridColumnAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading) // usa tutta la larghezza
        }
    }
}

// MARK: - Customize

/// Personalizzazione: gli swatch dei temi sono selezionabili dal vivo (tutta l'app si ridipinge,
/// onboarding compreso: la demo migliore del sistema di temi).
struct CustomizePage: View {
    let colors: ChromeColors
    let settings: AppSettings

    private static let columns = 4

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            PageHeader(
                "Make it yours",
                subtitle: "Pick a theme. Terminal, chrome and badges follow the same palette.",
                colors: colors
            )
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm),
                    count: Self.columns
                ),
                spacing: Theme.Spacing.sm
            ) {
                ForEach(settings.availableThemes, id: \.name) { theme in
                    ThemeSwatch(
                        theme: theme,
                        selected: theme.name == settings.theme.name,
                        colors: colors
                    ) { settings.selectTheme(theme.name) }
                }
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                // Non "quando Relay non è in primo piano": la regola vera è che la tab non sia a
                // schermo in una finestra che stai guardando (vedi `isVisible`).
                bullet("bell", "Notifications fire when a session needs you and you are not "
                    + "looking at it.")
                bullet("macwindow", "Right-click a workspace to move it to its own window: "
                    + "its sessions keep running.")
                bullet("arrow.clockwise", "Resume Claude Code or Codex sessions after a restart "
                    + "with the Resume bar.")
                // La nomina è l'altro passo azionabile oltre agli hook, e l'unico che spende
                // soldi dell'utente: va detto qui, non solo in fondo a un pannello.
                bullet("text.badge.checkmark", "Let a model name your workspaces after what they "
                    + "are doing: add an API key in Settings > Agents.")
                bullet("questionmark.circle", "This is the short tour. The full guide is in "
                    + "Help > Relay Guide.")
            }
            .padding(.top, Theme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Image(systemName: symbol)
                .font(Theme.Typography.subtitle)
                .foregroundStyle(colors.accent)
                .frame(width: 16)
            Text(text)
                .font(Theme.Typography.caption)
                .foregroundStyle(colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Anteprima cliccabile di un tema: fondo e foreground del tema ("Aa"), quattro punti ANSI,
/// nome sotto.
struct ThemeSwatch: View {
    let theme: RelayTheme
    let selected: Bool
    let colors: ChromeColors
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text("Aa")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(theme.foreground))
                    ForEach(1 ..< 5, id: \.self) { index in
                        Circle()
                            .fill(Color(theme.ansiColor(index)))
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .fill(Color(theme.background))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(
                            selected ? colors.accent : colors.hover,
                            lineWidth: selected ? 1.5 : 1
                        )
                )
                Text(theme.name)
                    .font(.system(size: 9))
                    .foregroundStyle(selected ? colors.foreground : colors.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .buttonStyle(.plain)
        .help(theme.name)
    }
}

// MARK: - Shared

/// Testata di pagina condivisa: titolo grande + sottotitolo che introduce il contenuto.
struct PageHeader: View {
    let title: String
    let subtitle: String
    let colors: ChromeColors

    init(_ title: String, subtitle: String, colors: ChromeColors) {
        self.title = title
        self.subtitle = subtitle
        self.colors = colors
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(colors.foreground)
            Text(subtitle)
                .font(Theme.Typography.item)
                .foregroundStyle(colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
