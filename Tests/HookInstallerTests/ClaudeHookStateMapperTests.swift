import AgentProtocol
import HookInstaller
import Testing

// Il mapper corregge lo stato dichiarato dall'hook in base al payload: il `PreToolUse` di un
// tool che apre un prompt bloccante è "aspetta input". Tutto il resto passa invariato.

@Test func askUserQuestionPreToolUseBecomesNeedsInput() {
    let state = ClaudeHookStateMapper.effectiveState(
        requested: .running,
        hookEventName: "PreToolUse",
        toolName: "AskUserQuestion"
    )
    #expect(state == .needsInput)
}

@Test func exitPlanModePreToolUseBecomesNeedsInput() {
    let state = ClaudeHookStateMapper.effectiveState(
        requested: .running,
        hookEventName: "PreToolUse",
        toolName: "ExitPlanMode"
    )
    #expect(state == .needsInput)
}

@Test func regularToolPreToolUseStaysRunning() {
    let state = ClaudeHookStateMapper.effectiveState(
        requested: .running,
        hookEventName: "PreToolUse",
        toolName: "Bash"
    )
    #expect(state == .running)
}

@Test func postToolUseOfPromptingToolStaysRunning() {
    // Il PostToolUse arriva solo dopo la risposta dell'utente: è la ripresa del lavoro.
    let state = ClaudeHookStateMapper.effectiveState(
        requested: .running,
        hookEventName: "PostToolUse",
        toolName: "AskUserQuestion"
    )
    #expect(state == .running)
}

@Test func missingPayloadFieldsKeepRequestedState() {
    // Evento non-tool (Stop, SessionStart) o CLI invocato con payload malformato.
    let state = ClaudeHookStateMapper.effectiveState(
        requested: .running,
        hookEventName: nil,
        toolName: nil
    )
    #expect(state == .running)
}

@Test func nonRunningStatesPassUnchanged() {
    // Solo la coppia PreToolUse+running viene corretta: gli altri stati non si toccano.
    for requested in [AgentState.idle, .needsInput, .error, .unknown] {
        let state = ClaudeHookStateMapper.effectiveState(
            requested: requested,
            hookEventName: "PreToolUse",
            toolName: "AskUserQuestion"
        )
        #expect(state == requested)
    }
}
