import AgentProtocol
import AgentRuntime
import Foundation

/// Simulatore di sessioni agente: recita una chat finta e manda eventi REALI al socket del
/// receiver (stesso `AgentEventClient`, stesso wire format degli hook). Da lanciare dentro una tab
/// di Relay: eredita `RELAY_TAB_ID` esattamente come una sessione Claude vera, quindi esercita
/// binding, trasporto, reducer e badge end-to-end senza sessioni reali.
enum SimulateCommand {
    private struct Step {
        let state: AgentState
        let message: String
        let delay: TimeInterval
    }

    private static let scenarios: [String: [Step]] = [
        "coding": [
            Step(state: .idle, message: "session started", delay: 0.8),
            Step(state: .running, message: "you   > fix the flaky reducer test", delay: 2.0),
            Step(state: .running, message: "claude: reading WorkspaceModel tests...", delay: 2.5),
            Step(
                state: .running,
                message: "claude: editing AgentStateReducerTests.swift",
                delay: 3.0
            ),
            Step(
                state: .needsInput,
                message: "claude: permission needed - run `swift test`? (waiting 6s)",
                delay: 6.0
            ),
            Step(state: .running, message: "you   > approved, running tests", delay: 2.5),
            Step(state: .running, message: "claude: 66 tests passed", delay: 1.5),
            Step(
                state: .idle,
                message: "claude: done (completed check if tab not in view)",
                delay: 1.0
            ),
        ],
        "permission": [
            Step(state: .idle, message: "session started", delay: 0.5),
            Step(state: .running, message: "you   > deploy to staging", delay: 1.5),
            Step(
                state: .needsInput,
                message: "claude: permission needed - `railway up`? (holding 15s)",
                delay: 15.0
            ),
            Step(state: .running, message: "you   > approved", delay: 2.0),
            Step(state: .idle, message: "claude: deployed", delay: 1.0),
        ],
        "burst": [
            Step(state: .running, message: "task 1: refactor imports", delay: 1.2),
            Step(state: .idle, message: "task 1 done", delay: 1.0),
            Step(state: .running, message: "task 2: update docs", delay: 1.2),
            Step(state: .idle, message: "task 2 done", delay: 1.0),
            Step(state: .running, message: "task 3: run linters", delay: 1.2),
            Step(state: .idle, message: "task 3 done", delay: 1.0),
        ],
    ]

    static func run(_ args: [String]) -> Int32 {
        guard let paneId = ProcessInfo.processInfo.environment["RELAY_TAB_ID"], !paneId.isEmpty
        else {
            print("simulate: RELAY_TAB_ID not set - run this inside a Relay tab")
            return 1
        }

        let name = args.first { !$0.hasPrefix("--") } ?? "coding"
        guard let steps = scenarios[name] else {
            print("simulate: unknown scenario '\(name)'")
            print("available: \(scenarios.keys.sorted().joined(separator: " | "))")
            return 1
        }

        let fast = args.contains("--fast")
        let loops = loopCount(from: args)
        let sessionId = "sim-\(UInt32.random(in: 1000 ... 9999))"

        print("simulating '\(name)' (session \(sessionId), \(loops) loop\(loops > 1 ? "s" : ""))")
        print("switch to another tab or workspace to watch the badges\n")

        for loop in 1 ... loops {
            if loops > 1 { print("-- loop \(loop)/\(loops)") }
            for step in steps {
                guard emit(step, sessionId: sessionId, paneId: paneId) else { return 2 }
                Thread.sleep(forTimeInterval: fast ? step.delay / 4 : step.delay)
            }
        }
        print("\nsimulation finished")
        return 0
    }

    private static func emit(_ step: Step, sessionId: String, paneId: String) -> Bool {
        let event = AgentStateEvent(
            agent: "claude",
            sessionId: sessionId,
            paneId: paneId,
            state: step.state,
            source: .hook,
            confidence: 1,
            timestamp: Date()
        )
        do {
            try AgentEventClient.send(event)
        } catch {
            print("simulate: cannot reach the Relay receiver - is the app running?")
            return false
        }
        print("[\(step.state.rawValue)] \(step.message)")
        return true
    }

    private static func loopCount(from args: [String]) -> Int {
        guard let index = args.firstIndex(of: "--loops"), index + 1 < args.count,
              let count = Int(args[index + 1]), count > 0 else { return 1 }
        return count
    }
}
