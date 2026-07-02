import Foundation

/// Codifica sul filo degli eventi agente (JSON lines). Encoder e decoder condividono la stessa
/// strategia per le date (ISO 8601): il client (CLI) e il receiver (app) devono restare allineati.
enum AgentWireCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
