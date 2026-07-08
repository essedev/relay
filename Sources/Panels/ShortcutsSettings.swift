import AppKit
import SwiftUI
import WorkspaceModel

/// Riga di una scorciatoia rimappabile: label + campo combo (clic per registrare) + reset. La
/// registrazione installa un monitor locale temporaneo e alza `settings.isCapturingShortcut`, così
/// il monitor globale si fa da parte. Rifiuta le combo di sistema e segnala i conflitti.
struct ShortcutRow: View {
    let action: ShortcutAction
    let settings: AppSettings
    let colors: ChromeColors
    /// Chi sta registrando, condiviso tra le righe: parte una sola registrazione alla volta e le
    /// altre si spengono da sole (niente monitor concorrenti che si calpestano il flag globale).
    @Binding var recordingAction: ShortcutAction?

    @State private var monitor: Any?
    @State private var warning: String?

    private var recording: Bool {
        recordingAction == action
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(action.label)
                .font(Theme.Typography.item)
                .foregroundStyle(colors.foreground)
            Spacer(minLength: Theme.Spacing.sm)
            if let warning {
                Text(warning)
                    .font(.system(size: 10))
                    .foregroundStyle(colors.error)
            }
            comboButton
            resetButton
        }
        // Un'altra riga ha preso la registrazione: smonta il monitor locale (senza toccare il flag
        // globale, che appartiene al nuovo recorder).
        .onChange(of: recordingAction) { _, current in
            if current != action { teardownMonitor() }
        }
        // La finestra si chiude (o la lista si ricostruisce) mentre registro: senza questo il
        // monitor resterebbe vivo a ingoiare ogni tasto dell'app e il flag resterebbe alzato.
        .onDisappear { if recording { stopRecording() } }
    }

    private var comboButton: some View {
        Button(action: toggleRecording) {
            CommandChip(
                recording ? "Type shortcut…" : settings.binding(for: action).display,
                colors: colors,
                foreground: recording ? colors.accent : nil,
                minWidth: 58,
                fill: recording ? 0.8 : 0.4,
                border: recording ? colors.accent : nil
            )
        }
        .buttonStyle(.plain)
    }

    private var resetButton: some View {
        Button { settings.resetBinding(for: action) } label: {
            Image(systemName: "arrow.uturn.backward").font(.system(size: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(colors.secondary)
        .help("Reset to default")
    }

    private func toggleRecording() {
        if recording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        warning = nil
        recordingAction = action // spegne ogni altra riga in registrazione (onChange)
        settings.isCapturingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleCapture(event)
            return nil // consuma durante la registrazione
        }
    }

    private func handleCapture(_ event: NSEvent) {
        if event.keyCode == 53 { stopRecording(); return } // Esc annulla
        // Serve un modificatore forte (⌘/⌃/⌥): un tasto nudo o solo-shift è digitazione, aspetta.
        guard let combo = KeyEventBridge.combo(from: event), combo.hasStrongModifier else { return }
        if let rejection = combo.recordingRejection {
            warning = Self.warningText(for: rejection)
            stopRecording()
            return
        }
        if let other = settings.conflict(for: combo, excluding: action) {
            warning = "Used by \(other.label)"
            stopRecording()
            return
        }
        settings.setBinding(combo, for: action)
        stopRecording()
    }

    private func stopRecording() {
        teardownMonitor()
        if recordingAction == action { recordingAction = nil }
        settings.isCapturingShortcut = false
    }

    /// Smonta solo il monitor locale, senza toccare lo stato condiviso: usato quando un'altra riga
    /// subentra nella registrazione.
    private func teardownMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func warningText(for rejection: ShortcutRejection) -> String {
        switch rejection {
        case .system: "Reserved by macOS"
        case .terminal: "Used by the terminal"
        case .fixedSelect: "Reserved (⌘/⌥ 1–9)"
        }
    }
}

/// Lista delle scorciatoie nel pannello impostazioni: azioni rimappabili per gruppo (con recorder),
/// reset globale e una sezione di sola lettura per i select-by-number, che restano fissi.
struct ShortcutsList: View {
    let settings: AppSettings
    let colors: ChromeColors

    @State private var recordingAction: ShortcutAction?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header
            ForEach(ShortcutGroup.allCases) { group in
                section(group.title.uppercased()) {
                    ForEach(ShortcutAction.allCases.filter { $0.group == group }) { action in
                        ShortcutRow(
                            action: action,
                            settings: settings,
                            colors: colors,
                            recordingAction: $recordingAction
                        )
                    }
                }
            }
            section("FIXED") {
                fixedRow("Select workspace 1–9", "⌘1–9")
                fixedRow("Select tab 1–9", "⌥1–9")
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Shortcuts")
                .font(Theme.Typography.title)
                .foregroundStyle(colors.foreground)
            Spacer()
            Button("Reset all") { settings.resetAllShortcuts() }
                .buttonStyle(.plain)
                .font(Theme.Typography.caption)
                .foregroundStyle(colors.accent)
                .help("Reset all shortcuts to defaults")
        }
    }

    private func section(
        _ title: String,
        @ViewBuilder _ rows: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.secondary)
            rows()
        }
    }

    private func fixedRow(_ label: String, _ combo: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Typography.item)
                .foregroundStyle(colors.foreground)
            Spacer()
            Text(combo)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(colors.secondary)
        }
    }
}
