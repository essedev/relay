import AgentProtocol

/// Correzioni dipendenti dal payload per gli hook Codex.
public enum CodexHookStateMapper {
    /// Nomi osservabili del tool che presenta una domanda bloccante all'utente. La richiesta di
    /// permesso normale è coperta dall'evento dedicato `PermissionRequest`.
    public static let promptingTools: Set<String> = ["request_user_input", "requestUserInput"]

    public static func effectiveState(
        requested: AgentState,
        hookEventName: String?,
        toolName: String?
    ) -> AgentState {
        guard requested == .running,
              hookEventName == "PreToolUse",
              let toolName, promptingTools.contains(toolName) else { return requested }
        return .needsInput
    }

    public static func shouldSuppress(hookEventName: String?, source: String?) -> Bool {
        hookEventName == "SessionStart" && source == "compact"
    }

    /// Un interrupt torna idle ma non è un lavoro completato: azzera l'attenzione invece di
    /// generare marker e notifica da `running -> idle`.
    public static func resetsAttention(hookEventName: String?, source: String?) -> Bool {
        hookEventName == "Interrupt" || source == "clear" || source == "resume"
    }
}
