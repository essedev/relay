import Core
import Foundation

/// Client minimo per un endpoint OpenAI-compatible (`POST <base>/chat/completions`), estratto dal
/// `NamingController` per tenere quello sulla sola policy: qui vivono URL, header, payload e
/// decodifica, lì la decisione di quando chiedere un nome e cosa farne.
///
/// Deliberatamente ridotto all'osso, perché serve a una cosa sola: un system + un user message,
/// risposta breve. Nessun errore tipizzato verso l'alto - il chiamante può solo riprovare più
/// tardi, quindi ogni fallimento (rete, HTTP, JSON) è `nil` e il contesto resta nel log.
struct ChatCompletionClient {
    /// Timeout corto: nominare un workspace è un extra, non deve tenere impegnata una richiesta.
    private static let timeout: TimeInterval = 10
    /// Il tetto deve coprire anche i **modelli di reasoning**, che spendono il budget pensando
    /// prima di scrivere: con un tetto stretto (era 16, quanto basta al nome) tornano
    /// `finish_reason: length` e `content: null`, cioè non nominano **mai**. Il costo resta
    /// trascurabile: è un massimale, non una spesa, e i modelli normali si fermano al nome.
    private static let maxTokens = 512

    let session: URLSession
    private let log = RelayLog.logger("naming")

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Manda i due messaggi e torna il contenuto grezzo della prima scelta, o `nil` su qualunque
    /// errore. `temperature: 0` per una risposta riproducibile: la variazione, quando serve, la
    /// chiede il prompt (vedi `WorkspaceNaming.prompt(avoiding:)`), non il sampling.
    func complete(
        system: String,
        user: String,
        apiKey: String,
        baseURL: String,
        model: String
    ) async -> String? {
        guard let url = Self.chatCompletionsURL(from: baseURL) else {
            log.error("naming request: invalid base URL")
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: system),
                .init(role: "user", content: user),
            ],
            temperature: 0,
            maxTokens: Self.maxTokens
        )
        guard let payload = try? JSONEncoder().encode(body) else { return nil }
        request.httpBody = payload
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                log.error("naming request: HTTP \(status)")
                return nil
            }
            let choice = try JSONDecoder().decode(ChatResponse.self, from: data).choices.first
            guard let content = choice?.message.content, !content.isEmpty else {
                // Risposta valida ma senza testo: tipicamente un modello di reasoning tagliato dal
                // tetto di token (`finish_reason: length`). Va detto per nome, o si legge come un
                // errore di rete.
                let reason = choice?.finishReason ?? "no choices"
                log.error("naming request: empty content (\(reason, privacy: .public))")
                return nil
            }
            return content
        } catch {
            // Il messaggio è di URLSession/JSONDecoder, non contiene payload utente né segreti:
            // pubblico, altrimenti in console resta `<private>` e la diagnosi si fa a mano.
            log.error("naming request failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Compone l'URL `/chat/completions` dalla base, tollerando un eventuale trailing slash.
    private static func chatCompletionsURL(from baseURL: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return URL(string: base + "/chat/completions")
    }
}

// MARK: - Payload OpenAI-compatible

private struct ChatRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int

    struct Message: Encodable {
        let role: String
        let content: String
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

private struct ChatResponse: Decodable {
    let choices: [ChatChoice]
}

private struct ChatChoice: Decodable {
    let message: ChatMessage
    /// Perché il modello ha smesso (`stop`, `length`, ...). Serve solo a spiegare nel log una
    /// risposta senza contenuto.
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

private struct ChatMessage: Decodable {
    /// **Opzionale**: un modello di reasoning che esaurisce il budget torna `content: null`. Con un
    /// `String` non opzionale il decode dell'intera risposta falliva, e ogni nomina diventava un
    /// generico "richiesta fallita".
    let content: String?
}
