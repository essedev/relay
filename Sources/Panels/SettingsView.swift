import SwiftUI
import WorkspaceModel

/// Pannello impostazioni (Cmd+,): tema e dimensione font, con anteprima della palette. Colori
/// derivati dal tema corrente, come il resto della chrome. Le scelte passano per i setter di
/// `AppSettings`, che validano e persistono in UserDefaults.
public struct SettingsView: View {
    let settings: AppSettings

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            themeSection(colors)
            Divider()
            fontRow(colors)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 380, height: 220, alignment: .topLeading)
        .background(colors.background)
    }

    private func themeSection(_ colors: ChromeColors) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Theme")
                .font(Theme.Typography.title)
                .foregroundStyle(colors.foreground)
            Picker("Theme", selection: themeBinding) {
                ForEach(settings.availableThemes, id: \.name) { theme in
                    Text(theme.name).tag(theme.name)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            palettePreview
        }
    }

    /// Anteprima della palette del tema selezionato: gli ANSI 1-6 più foreground su background.
    private var palettePreview: some View {
        let theme = settings.theme
        return HStack(spacing: Theme.Spacing.xs) {
            ForEach(1 ..< 7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(theme.ansiColor(index)))
                    .frame(width: 18, height: 18)
            }
            Spacer()
            Text("Aa")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(theme.foreground))
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(theme.background))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color(theme.selection), lineWidth: 1)
                        )
                )
        }
        .padding(.top, Theme.Spacing.xxs)
    }

    private func fontRow(_ colors: ChromeColors) -> some View {
        HStack {
            Text("Font size")
                .font(Theme.Typography.item)
                .foregroundStyle(colors.foreground)
            Spacer()
            Stepper(value: fontBinding, in: fontRange, step: 1) {
                Text("\(Int(settings.fontSize)) pt")
                    .font(Theme.Typography.item.monospacedDigit())
                    .foregroundStyle(colors.foreground)
            }
            .fixedSize()
        }
    }

    private var fontRange: ClosedRange<Double> {
        AppSettings.minFontSize ... AppSettings.maxFontSize
    }

    private var themeBinding: Binding<String> {
        Binding(get: { settings.themeName }, set: { settings.selectTheme($0) })
    }

    private var fontBinding: Binding<Double> {
        Binding(get: { settings.fontSize }, set: { settings.setFontSize($0) })
    }
}
