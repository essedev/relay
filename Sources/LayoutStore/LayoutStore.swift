import Core
import Foundation
import WorkspaceModel

public enum LayoutStoreError: Error, Equatable {
    /// Lo snapshot è degradato (0 workspace, o un workspace senza tab): non lo scriviamo, per non
    /// sovrascrivere un layout buono con uno stato che a runtime non può esistere (il cascade
    /// impedisce workspace vuoti; `ensureAtLeastOneWorkspace` impedisce 0 workspace). Un save del
    /// genere è il sintomo di una race, non uno stato utente da persistere.
    case degenerateSnapshot
}

/// Persistenza del layout su disco: legge/scrive uno `LayoutSnapshot` come JSON. Il path è
/// iniettato (il composition root passa `RelayRuntimePaths.layoutPath`, i test una dir temporanea):
/// così questo modulo non conosce `~/.relay` né override d'ambiente. Nessun tipo AppKit, nessuna
/// dipendenza dallo store osservabile: solo il DTO puro.
///
/// Difesa dei dati utente (dati che l'utente non può ricreare a mano): ogni `save` conserva il
/// primario valido precedente in un backup (`.bak`) prima di sovrascriverlo, e la `load` ricade sul
/// backup se il primario è mancante/corrotto/degradato. Un save di uno snapshot degradato è
/// rifiutato: meglio tenere l'ultimo layout buono che scriverne uno rotto.
public struct LayoutStore {
    private static let log = RelayLog.logger("layout")

    private let path: String

    public init(path: String) {
        self.path = path
    }

    /// Path del backup: il primario con suffisso `.bak`, nella stessa directory.
    private var backupPath: String {
        path + ".bak"
    }

    /// Carica il primario; se manca/corrotto/degradato o di versione ignota, ricade sul backup.
    /// `nil` solo se nessuno dei due è recuperabile. In ogni caso di fallimento il chiamante ricade
    /// sul seed di default: mai un crash al boot.
    public func load() -> LayoutSnapshot? {
        if let snapshot = loadFile(at: path) { return snapshot }
        if let snapshot = loadFile(at: backupPath) {
            Self.log.notice("layout ripristinato dal backup: primario non valido o assente")
            return snapshot
        }
        return nil
    }

    private func loadFile(at path: String) -> LayoutSnapshot? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        do {
            let snapshot = try JSONDecoder().decode(LayoutSnapshot.self, from: data)
            guard snapshot.version == LayoutSnapshot.currentVersion else {
                Self.log.notice("layout ignorato: versione \(snapshot.version) non supportata")
                return nil
            }
            guard Self.isValidForPersistence(snapshot) else {
                // Un file degradato (workspace senza tab) non è un layout utente: ignoralo, così la
                // load prova il backup invece di restaurare workspace vuoti.
                Self.log.error("layout ignorato: degradato (workspace senza tab o vuoto)")
                return nil
            }
            return snapshot
        } catch {
            Self.log.error("layout corrotto, ignorato: \(error)")
            return nil
        }
    }

    /// Scrive lo snapshot in modo atomico, creando la directory se manca. Rifiuta uno snapshot
    /// degradato (`degenerateSnapshot`) e conserva il primario buono in `.bak` prima di
    /// sovrascriverlo. Propaga l'errore: il chiamante (autosave) logga e non tocca l'ultimo layout
    /// valido.
    public func save(_ snapshot: LayoutSnapshot) throws {
        guard Self.isValidForPersistence(snapshot) else {
            Self.log.error("save rifiutato: snapshot degradato (non sovrascrivo il layout buono)")
            throw LayoutStoreError.degenerateSnapshot
        }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Backup del primario buono prima di sovrascrivere: una scrittura futura interrotta o una
        // race non lasciano l'utente senza rete. Il primario su disco è sempre valido (save valida
        // sempre), quindi il backup lo è.
        backupExistingPrimary()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    private func backupExistingPrimary() {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else { return }
        try? fileManager.removeItem(atPath: backupPath)
        try? fileManager.copyItem(atPath: path, toPath: backupPath)
    }

    /// Invariante di un layout persistibile: almeno un workspace, e ogni workspace con almeno una
    /// tab. A runtime è sempre vero (cascade + `ensureAtLeastOneWorkspace`); uno snapshot che lo
    /// viola è il prodotto di una race e non va scritto. Puro, testabile.
    static func isValidForPersistence(_ snapshot: LayoutSnapshot) -> Bool {
        !snapshot.workspaces.isEmpty && snapshot.workspaces.allSatisfy { !$0.tabs.isEmpty }
    }
}
