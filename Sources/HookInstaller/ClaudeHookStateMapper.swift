import AgentProtocol

/// Correzione dello stato hook in base al payload. Gli hook dichiarano uno stato statico per
/// evento (`ClaudeHookInstaller.specs`), ma alcuni tool aprono un prompt bloccante e il turno non
/// prosegue finché l'utente non risponde: il loro `PreToolUse` significa "aspetta input", non
/// "sta lavorando". Il `PostToolUse` - che arriva solo dopo la risposta - riporta `running`.
///
/// Vive accanto all'installer: è l'altra metà del mapping evento Claude -> stato (la parte che
/// dipende dal payload e non può stare nel comando statico di settings.json).
public enum ClaudeHookStateMapper {
    /// Tool che presentano un prompt bloccante (domanda a scelta multipla, approvazione del
    /// piano). Non passano da `PermissionRequest` (non sono permessi) e non producono `Stop`
    /// finché l'utente non risponde: senza questa correzione una tab con una domanda aperta
    /// resterebbe `running` per sempre.
    public static let promptingTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    /// Stato effettivo da inviare per un hook che dichiara `requested`. `hookEventName` e
    /// `toolName` vengono dallo stdin JSON di Claude (`hook_event_name`, `tool_name`); campi
    /// assenti (evento non-tool, CLI vecchio) lasciano lo stato dichiarato.
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
}
