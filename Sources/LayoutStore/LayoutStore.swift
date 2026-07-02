import Core
import Foundation
import WorkspaceModel

/// Persistenza del layout su disco: legge/scrive uno `LayoutSnapshot` come JSON. Il path è
/// iniettato (il composition root passa `RelayRuntimePaths.layoutPath`, i test una dir temporanea):
/// così questo modulo non conosce `~/.relay` né override d'ambiente. Nessun tipo AppKit, nessuna
/// dipendenza dallo store osservabile: solo il DTO puro.
public struct LayoutStore {
    private static let log = RelayLog.logger("layout")

    private let path: String

    public init(path: String) {
        self.path = path
    }

    /// Carica lo snapshot, o `nil` se il file manca, è illeggibile, corrotto, o di versione ignota.
    /// In tutti i casi di fallimento il chiamante ricade sul seed di default: mai un crash al boot.
    public func load() -> LayoutSnapshot? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        do {
            let snapshot = try JSONDecoder().decode(LayoutSnapshot.self, from: data)
            guard snapshot.version == LayoutSnapshot.currentVersion else {
                Self.log.info("layout ignorato: versione \(snapshot.version) non supportata")
                return nil
            }
            return snapshot
        } catch {
            Self.log.error("layout corrotto, ignorato: \(error)")
            return nil
        }
    }

    /// Scrive lo snapshot in modo atomico, creando la directory se manca. Propaga l'errore: il
    /// chiamante logga (il salvataggio non deve mai far cadere l'app).
    public func save(_ snapshot: LayoutSnapshot) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }
}
