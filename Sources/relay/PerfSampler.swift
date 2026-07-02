import AppKit
import Core
import Darwin
import Foundation
import WorkspaceModel

/// Strumentazione di performance (misure M3), dev tooling come demo/simulate: attiva solo con
/// `RELAY_PERF=1`, a regime spenta e a costo zero. Campiona due budget di ARCHITECTURE.md:
///
/// - **latenza input aggiunta dallo shell**: durata del monitor `Cmd/Option` che gira su ogni
///   keyDown prima che SwiftTerm veda l'evento. E' l'unica latenza che Relay aggiunge sul path di
///   tastiera (l'emulatore e il rendering, fuori dal nostro controllo, sono di SwiftTerm);
/// - **memoria residente vs surface vive**: RSS del processo correlato al numero di surface in
///   memoria, per tarare il cap LRU.
///
/// Con `RELAY_PERF_CYCLE=1` cicla anche il focus tra tutte le tab per realizzare le surface e
/// osservare la memoria salire fino al cap. Con `RELAY_SURFACE_CAP=N` (letto altrove) si esplora
/// la pendenza memoria/surface oltre il default.
@MainActor
final class PerfSampler {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["RELAY_PERF"] == "1"
    }

    private static var shouldCycle: Bool {
        ProcessInfo.processInfo.environment["RELAY_PERF_CYCLE"] == "1"
    }

    private let store: WorkspaceStore
    private let liveSurfaceCount: () -> Int
    /// Il codice che gira su ogni keyDown prima del terminale (`handleNavigationKey`), passato dal
    /// composition root per poterlo cronometrare senza esporre il monitor.
    private let inputHook: (NSEvent) -> Void
    private let log = RelayLog.logger("perf")
    private var inputSamples: [Double] = []
    private var timer: Timer?
    private var cycleTimer: Timer?
    private var cycleIndex = 0

    init(
        store: WorkspaceStore,
        liveSurfaceCount: @escaping () -> Int,
        inputHook: @escaping (NSEvent) -> Void
    ) {
        self.store = store
        self.liveSurfaceCount = liveSurfaceCount
        self.inputHook = inputHook
    }

    func start() {
        emit("perf sampler on (RELAY_PERF=1)")
        benchmarkInput()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        if Self.shouldCycle {
            cycleTimer = Timer
                .scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.cycleFocus() }
                }
        }
    }

    /// Cronometra l'`inputHook` su un keyDown dell'hot path (carattere semplice, ramo non gestito)
    /// migliaia di volte: dà una p99 stabile della latenza che lo shell aggiunge, senza simulare
    /// l'hardware. Il monitor vivo continua a campionare anche i keystroke reali dell'utente.
    private func benchmarkInput() {
        guard let event = Self.syntheticKeyDown() else { return }
        for _ in 0 ..< 5000 {
            let start = DispatchTime.now().uptimeNanoseconds
            inputHook(event)
            recordInputHook(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
    }

    /// keyDown sintetico di un carattere semplice (nessun modificatore): il caso comune del
    /// digitare.
    private static func syntheticKeyDown() -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        )
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cycleTimer?.invalidate()
        cycleTimer = nil
    }

    /// Registra la durata (ms) di una invocazione dell'hook: la latenza che lo shell aggiunge sul
    /// path di tastiera.
    private func recordInputHook(_ milliseconds: Double) {
        inputSamples.append(milliseconds)
    }

    private func sample() {
        let stats = LatencyStats(samples: inputSamples)
        let rssMB = Double(Self.residentBytes()) / 1_048_576
        let live = liveSurfaceCount()
        let line = String(
            format: "rss=%.1fMB surfaces=%d input(n=%d p50=%.4f p99=%.4f max=%.4f)ms",
            rssMB, live, stats.count, stats.p50, stats.p99, stats.max
        )
        emit(line)
    }

    /// Cicla il focus tra tutte le tab di tutti i workspace: realizza le surface così la memoria
    /// sale e la LRU entra in gioco. Solo per la misura, mai a regime.
    private func cycleFocus() {
        let pairs = store.workspaces.flatMap { workspace in
            workspace.tabs.map { (workspace, $0) }
        }
        guard !pairs.isEmpty else { return }
        let (workspace, tab) = pairs[cycleIndex % pairs.count]
        cycleIndex += 1
        store.selectWorkspace(workspace.id)
        store.selectTab(tab.id, in: workspace)
    }

    /// Output di misura al livello `.notice` (persistito e mostrato di default da `log stream`,
    /// diversamente da `.info`). I valori dinamici sono `.public`: senza, li redige a `<private>`.
    private func emit(_ message: String) {
        log.notice("\(message, privacy: .public)")
    }

    /// Memoria residente del processo in byte (task_info / MACH_TASK_BASIC_INFO).
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
}
