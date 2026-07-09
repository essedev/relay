import AgentProtocol
import Darwin
import Foundation
import Panels
import WorkspaceModel

@MainActor
final class RuntimeStatsSampler {
    private let store: WorkspaceStore
    private let model: RuntimeStatsModel
    private let liveSurfaceCount: () -> Int
    private var timer: Timer?

    init(
        store: WorkspaceStore,
        model: RuntimeStatsModel,
        liveSurfaceCount: @escaping () -> Int
    ) {
        self.store = store
        self.model = model
        self.liveSurfaceCount = liveSurfaceCount
    }

    func start() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        let workspaces = store.workspaces
        let tabs = workspaces.flatMap(\.tabs)
        model.snapshot = RuntimeStatsSnapshot(
            memoryBytes: Self.residentBytes(),
            cpuPercent: Self.processCPUPercent(),
            workspaceCount: workspaces.count,
            visibleWorkspaceCount: workspaces.count { !$0.archived },
            archivedWorkspaceCount: workspaces.count { $0.archived },
            tabCount: tabs.count,
            activeAgentTabCount: tabs.filter(Self.hasActiveAgent).count,
            liveSurfaceCount: liveSurfaceCount(),
            surfaceCap: Self.surfaceCap,
            sampledAt: Date()
        )
    }

    private static func hasActiveAgent(_ tab: WorkspaceModel.Tab) -> Bool {
        switch tab.agentState {
        case .running, .needsInput, .error: true
        case .idle, .unknown: false
        }
    }

    private static var surfaceCap: Int {
        let raw = ProcessInfo.processInfo.environment["RELAY_SURFACE_CAP"].flatMap(Int.init) ?? 0
        return raw > 0 ? raw : 12
    }

    private static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    private static func processCPUPercent() -> Double {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threadList else { return 0 }
        defer {
            let bytes = vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadList)), bytes)
        }

        var total: Double = 0
        for index in 0 ..< Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(THREAD_INFO_MAX)
            let threadResult = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                    thread_info(
                        threadList[index],
                        thread_flavor_t(THREAD_BASIC_INFO),
                        rebound,
                        &count
                    )
                }
            }
            guard threadResult == KERN_SUCCESS, info.flags & TH_FLAGS_IDLE == 0 else { continue }
            total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
        }
        return total
    }
}
