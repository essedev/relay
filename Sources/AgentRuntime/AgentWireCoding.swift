import Foundation

/// Codifica sul filo degli eventi agente (JSON lines). Encoder e decoder condividono la stessa
/// strategia per le date: ISO 8601 **con frazioni di secondo** (millisecondi). La precisione
/// sub-secondo serve alla guardia di monotonicità a valle (store): gli hook sono processi
/// concorrenti e più eventi possono nascere nello stesso secondo; senza frazioni i timestamp
/// collassano e l'ordine di emissione va perso. Il decode resta tollerante col formato storico
/// senza frazioni (eventi da un CLI più vecchio); il client (CLI) e il receiver (app) devono
/// restare allineati.
enum AgentWireCoding {
    /// `Date.ISO8601FormatStyle` (e non `ISO8601DateFormatter`): value type `Sendable`, sicuro
    /// come costante condivisa sotto strict concurrency.
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(fractional))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = try? fractional.parse(string) { return date }
            if let date = try? plain.parse(string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "invalid ISO 8601 timestamp: \(string)"
            )
        }
        return decoder
    }
}
