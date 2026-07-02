import SwiftUI
import WorkspaceModel

/// Pannello impostazioni (Cmd+,): tema e dimensione font. Le scelte passano per i setter di
/// `AppSettings`, che validano e persistono in UserDefaults.
public struct SettingsView: View {
    let settings: AppSettings

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: themeBinding) {
                    ForEach(settings.availableThemes, id: \.name) { theme in
                        Text(theme.name).tag(theme.name)
                    }
                }
                Stepper(value: fontBinding, in: fontRange, step: 1) {
                    Text("Font size: \(Int(settings.fontSize)) pt")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
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
