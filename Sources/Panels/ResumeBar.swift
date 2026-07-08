import Core
import SwiftUI

/// Barra slim in cima al terminale: propone di riprendere una sessione agente ripristinata dopo un
/// riavvio. Semplice, colori dal tema. `Resume` inietta il comando di resume; la x scarta.
public struct ResumeBar: View {
    let label: String
    let theme: RelayTheme
    let onResume: () -> Void
    let onDismiss: () -> Void

    public init(
        label: String,
        theme: RelayTheme,
        onResume: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.label = label
        self.theme = theme
        self.onResume = onResume
        self.onDismiss = onDismiss
    }

    private var colors: ChromeColors {
        ChromeColors(theme)
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "arrow.clockwise")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(colors.accent)
            Text("Resume the Claude session")
                .font(Theme.Typography.caption)
                .foregroundStyle(colors.foreground)
            if !label.isEmpty {
                Text(label)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(colors.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Theme.Spacing.sm)
            resumeButton
            dismissButton
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(colors.hover)
        .overlay(alignment: .bottom) {
            Rectangle().fill(colors.accent.opacity(0.35)).frame(height: 1)
        }
    }

    private var resumeButton: some View {
        Button(action: onResume) {
            Text("Resume")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(colors.accent)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(colors.accent.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help("Resume the Claude session in this tab")
    }

    private var dismissButton: some View {
        CloseButton(color: colors.secondary, help: "Dismiss", action: onDismiss)
    }
}
