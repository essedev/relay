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

    @State private var recording = false
    @State private var monitor: Any?
    @State private var warning: String?

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
    }

    private var comboButton: some View {
        Button(action: toggleRecording) {
            Text(recording ? "Type shortcut…" : settings.binding(for: action).display)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(recording ? colors.accent : colors.foreground)
                .frame(minWidth: 58)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .fill(colors.hover.opacity(recording ? 0.8 : 0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(recording ? colors.accent : Color.clear, lineWidth: 1)
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
        recording = true
        settings.isCapturingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleCapture(event)
            return nil // consuma durante la registrazione
        }
    }

    private func handleCapture(_ event: NSEvent) {
        if event.keyCode == 53 { stopRecording(); return } // Esc annulla
        guard let combo = KeyEventBridge.combo(from: event),
              !combo.modifiers.isEmpty else { return }
        if Self.reserved.contains(combo) {
            warning = "Reserved"
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
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        settings.isCapturingShortcut = false
        recording = false
    }

    /// Combinazioni di sistema non registrabili (romperebbero quit/settings/copia/incolla).
    private static let reserved: Set<KeyCombo> = [
        KeyCombo(key: "q", modifiers: [.command]),
        KeyCombo(key: ",", modifiers: [.command]),
        KeyCombo(key: "c", modifiers: [.command]),
        KeyCombo(key: "v", modifiers: [.command]),
        KeyCombo(key: "a", modifiers: [.command]),
    ]
}

/// Lista delle scorciatoie nel pannello impostazioni: azioni rimappabili per gruppo (con recorder),
/// reset globale e una sezione di sola lettura per i select-by-number, che restano fissi.
struct ShortcutsList: View {
    let settings: AppSettings
    let colors: ChromeColors

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header
            ForEach(ShortcutGroup.allCases) { group in
                section(group.title.uppercased()) {
                    ForEach(ShortcutAction.allCases.filter { $0.group == group }) { action in
                        ShortcutRow(action: action, settings: settings, colors: colors)
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
                .help("Ripristina tutte le scorciatoie ai valori di default")
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
