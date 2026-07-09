import SwiftUI
import WorkspaceModel

public struct RuntimeStatsSnapshot: Equatable, Sendable {
    public var memoryBytes: UInt64
    public var cpuPercent: Double
    public var workspaceCount: Int
    public var visibleWorkspaceCount: Int
    public var archivedWorkspaceCount: Int
    public var tabCount: Int
    public var activeAgentTabCount: Int
    public var liveSurfaceCount: Int
    public var surfaceCap: Int
    public var sampledAt: Date

    public init(
        memoryBytes: UInt64 = 0,
        cpuPercent: Double = 0,
        workspaceCount: Int = 0,
        visibleWorkspaceCount: Int = 0,
        archivedWorkspaceCount: Int = 0,
        tabCount: Int = 0,
        activeAgentTabCount: Int = 0,
        liveSurfaceCount: Int = 0,
        surfaceCap: Int = 0,
        sampledAt: Date = Date()
    ) {
        self.memoryBytes = memoryBytes
        self.cpuPercent = cpuPercent
        self.workspaceCount = workspaceCount
        self.visibleWorkspaceCount = visibleWorkspaceCount
        self.archivedWorkspaceCount = archivedWorkspaceCount
        self.tabCount = tabCount
        self.activeAgentTabCount = activeAgentTabCount
        self.liveSurfaceCount = liveSurfaceCount
        self.surfaceCap = surfaceCap
        self.sampledAt = sampledAt
    }
}

@Observable
public final class RuntimeStatsModel {
    public var snapshot: RuntimeStatsSnapshot

    public init(snapshot: RuntimeStatsSnapshot = RuntimeStatsSnapshot()) {
        self.snapshot = snapshot
    }
}

public struct RuntimeStatsView: View {
    let settings: AppSettings
    let model: RuntimeStatsModel

    public init(settings: AppSettings, model: RuntimeStatsModel) {
        self.settings = settings
        self.model = model
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        let snapshot = model.snapshot
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header(snapshot, colors)
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: Theme.Spacing.md
            ) {
                StatCard(
                    title: "Memory",
                    value: memoryString(snapshot.memoryBytes),
                    colors: colors
                )
                StatCard(title: "CPU", value: percentString(snapshot.cpuPercent), colors: colors)
                StatCard(
                    title: "Workspaces",
                    value: "\(snapshot.workspaceCount)",
                    detail: "\(snapshot.visibleWorkspaceCount) visible, "
                        + "\(snapshot.archivedWorkspaceCount) archived",
                    colors: colors
                )
                StatCard(
                    title: "Tabs",
                    value: "\(snapshot.tabCount)",
                    detail: "\(snapshot.activeAgentTabCount) active agents",
                    colors: colors
                )
                StatCard(
                    title: "Surfaces",
                    value: "\(snapshot.liveSurfaceCount)",
                    detail: "cap \(snapshot.surfaceCap)",
                    colors: colors
                )
            }
            Text("Stats update only while this panel is open.")
                .font(Theme.Typography.subtitle)
                .foregroundStyle(colors.secondary)
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 420)
        .background(colors.background)
    }

    private func header(_ snapshot: RuntimeStatsSnapshot, _ colors: ChromeColors) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Runtime Stats")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colors.foreground)
                Text("Updated \(snapshot.sampledAt.formatted(date: .omitted, time: .standard))")
                    .font(Theme.Typography.subtitle)
                    .foregroundStyle(colors.secondary)
            }
            Spacer()
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(colors.accent)
        }
    }

    private func memoryString(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    private func percentString(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    var detail: String?
    let colors: ChromeColors

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(colors.secondary)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(colors.foreground)
            if let detail {
                Text(detail)
                    .font(Theme.Typography.subtitle)
                    .foregroundStyle(colors.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .padding(Theme.Spacing.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(colors.surface))
    }
}
