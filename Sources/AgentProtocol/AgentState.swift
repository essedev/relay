/// Stato agente normalizzato, indipendente dallo specifico agente (Claude, Codex, ...).
/// Mapping degli eventi Claude -> stato in `docs/ARCHITECTURE.md`.
public enum AgentState: String, Sendable, Codable, CaseIterable {
    case running
    case idle
    case needsInput = "needs_input"
    case error
    case unknown
}
