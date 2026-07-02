import Foundation

/// Riferimento per riprendere la sessione di un agente in una tab dopo un riavvio: l'agente, il suo
/// `sessionId` e un `label` leggibile (il titolo della tab al momento della cattura, così la barra
/// di resume lo mostra anche dopo che la shell fresca ha ridipinto il titolo via OSC).
///
/// Sicurezza (vedi ARCHITECTURE #Resume): solo questi campi. Mai prompt, token, credenziali.
public struct ResumeBinding: Codable, Equatable, Sendable {
    public let agent: String
    public let sessionId: String
    public let label: String

    public init(agent: String, sessionId: String, label: String) {
        self.agent = agent
        self.sessionId = sessionId
        self.label = label
    }

    /// Comando per riprendere la sessione. V1: solo Claude (`claude --resume <id>`); il valore
    /// `agent` degli hook è il nome del binary.
    public var resumeCommand: String {
        "\(agent) --resume \(sessionId)"
    }
}
