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

    private static let panelWidth: CGFloat = 660
    private static let panelHeight: CGFloat = 500
    private static let footerHeight: CGFloat = 48

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
        GeometryReader { geo in
            ZStack {
                // Backdrop: attenua il resto e chiude al click fuori (si riapre da Help).
                Color.black.opacity(0.35)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                panel(colors, size: Self.panelSize(in: geo.size))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Fissa ma clampata alla finestra, come dashboard e guida: il minimo finestra è 700x460 e un
    /// frame fisso puro verrebbe tagliato ai bordi.
    static func panelSize(in available: CGSize) -> CGSize {
        let inset = Theme.Spacing.lg * 2
        return CGSize(
            width: min(panelWidth, max(0, available.width - inset)),
            height: min(panelHeight, max(0, available.height - inset))
        )
    }

    /// L'area del contenuto ha **altezza fissa** e il contenuto ci scorre dentro: le pagine hanno
    /// altezza intrinseca (testi `fixedSize`) e senza scroll una pagina più alta della scatola
    /// traboccava, si prendeva il footer e il `clipShape` tagliava titolo e bottoni. Il footer sta
    /// fuori dallo scroll, sempre a fondo pannello. `minHeight` sul contenuto riempie il viewport
    /// quando la pagina è più corta, così l'allineamento verticale resta quello voluto.
    private func panel(_ colors: ChromeColors, size: CGSize) -> some View {
        let contentHeight = max(0, size.height - Self.footerHeight - 1)
        return VStack(spacing: 0) {
            ScrollView {
                pageContent(colors)
                    .padding(.horizontal, Theme.Spacing.lg * 2)
                    .padding(.vertical, Theme.Spacing.lg + Theme.Spacing.sm)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: contentHeight,
                        alignment: model.page == .welcome ? .center : .topLeading
                    )
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: contentHeight)
            Divider()
            footer(colors)
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
            case .organize: OrganizePage(colors: colors)
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
        .frame(height: Self.footerHeight)
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
