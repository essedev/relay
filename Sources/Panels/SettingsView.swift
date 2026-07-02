import SwiftUI
import WorkspaceModel

/// Pannello impostazioni (Cmd+,): tema e dimensione font. Le scelte passano per i setter di
/// `AppSettings`, che validano e persistono in UserDefaults. Dimensione esplicita: hostato in una
/// NSWindow via NSHostingController, che si dimensiona sul fitting size della view.
public struct SettingsView: View {
    let settings: AppSettings

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Appearance")
                .font(.headline)

            HStack {
                Text("Theme")
                Spacer()
                Picker("", selection: themeBinding) {
                    ForEach(settings.availableThemes, id: \.name) { theme in
                        Text(theme.name).tag(theme.name)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            HStack {
                Text("Font size")
                Spacer()
                Stepper("\(Int(settings.fontSize)) pt", value: fontBinding, in: fontRange, step: 1)
                    .fixedSize()
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 360, height: 170, alignment: .topLeading)
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
