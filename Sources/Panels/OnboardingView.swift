import SwiftUI
import WorkspaceModel

/// Overlay di benvenuto: primo avvio + riapribile da Help > Welcome to Relay. Cinque pagine che
/// spiegano cosa fa Relay coi componenti reali (badge, keycap, temi) invece di screenshot, così
/// restano sempre coerenti col tema corrente. Nessun auto-ciclo: avanza l'utente (dot, frecce,
/// bottoni). Wiring nel composition root (`AppControllerOnboarding`), stesso overlay full-window
/// della dashboard.
public struct OnboardingView: View {
    let settings: AppSettings
    let hooks: HookControls?
    let onClose: () -> Void

    @State private var model = OnboardingModel()
    @FocusState private var focused: Bool

    public init(
        settings: AppSettings,
        hooks: HookControls?,
        onClose: @escaping () -> Void
    ) {
        self.settings = settings
        self.hooks = hooks
        self.onClose = onClose
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        ZStack {
            // Backdrop: attenua il resto e chiude al click fuori (si riapre da Help).
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
            panel(colors)
                .padding(Theme.Spacing.lg)
        }
    }

    private func panel(_ colors: ChromeColors) -> some View {
        VStack(spacing: 0) {
            pageContent(colors)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(Theme.Spacing.lg * 2)
            Divider()
            footer(colors)
        }
        .frame(maxWidth: 660, maxHeight: 440)
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
        // Tastiera: il pannello prende il focus (first responder deferito nel composition root,
        // come la dashboard) e gestisce frecce/Invio/Esc da solo; il monitor globale si fa da
        // parte mentre l'overlay è aperto.
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onExitCommand(perform: onClose)
        .onKeyPress(.leftArrow) { move { $0.back() } }
        .onKeyPress(.rightArrow) { move { $0.advance() } }
        .onKeyPress(.return) {
            if model.isLast { onClose() } else { _ = move { $0.advance() } }
            return .handled
        }
    }

    private func pageContent(_ colors: ChromeColors) -> some View {
        Group {
            switch model.page {
            case .welcome: WelcomePage(colors: colors)
            case .hooks: HooksPage(colors: colors, hooks: hooks)
            case .attention: AttentionPage(colors: colors)
            case .navigation: NavigationPage(colors: colors, settings: settings)
            case .customize: CustomizePage(colors: colors, settings: settings)
            }
        }
        .id(model.page)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.08), value: model.page)
    }

    // MARK: - Footer

    /// Dot centrati in assoluto (ZStack, non tra spacer: Skip e Continue hanno larghezze diverse),
    /// Skip a sinistra, Back/Continue a destra. Ultima pagina: "Get Started" chiude.
    private func footer(_ colors: ChromeColors) -> some View {
        ZStack {
            dots(colors)
            HStack(spacing: Theme.Spacing.sm) {
                if !model.isLast {
                    Button("Skip", action: onClose)
                        .buttonStyle(.plain)
                        .font(Theme.Typography.item)
                        .foregroundStyle(colors.secondary)
                }
                Spacer()
                if !model.isFirst {
                    Button("Back") { _ = move { $0.back() } }
                        .buttonStyle(.plain)
                        .font(Theme.Typography.item)
                        .foregroundStyle(colors.secondary)
                }
                primaryButton(model.isLast ? "Get Started" : "Continue", colors) {
                    if model.isLast { onClose() } else { _ = move { $0.advance() } }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: 48)
    }

    private func dots(_ colors: ChromeColors) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(OnboardingPage.allCases) { page in
                Button {
                    withAnimation { model.select(page) }
                } label: {
                    Circle()
                        .fill(page == model.page ? colors.accent : colors.secondary.opacity(0.35))
                        .frame(width: 7, height: 7)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func primaryButton(
        _ title: String,
        _ colors: ChromeColors,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.item.weight(.medium))
                .foregroundStyle(colors.background) // testo del colore del fondo, su accent
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.sm).fill(colors.accent))
        }
        .buttonStyle(.plain)
    }

    private func move(_ transform: (inout OnboardingModel) -> Void) -> KeyPress.Result {
        withAnimation(.easeOut(duration: 0.08)) { transform(&model) }
        return .handled
    }
}
