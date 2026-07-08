import AgentRuntime
import Core
import Foundation

/// Custode della API key per la nomina automatica dei workspace. La chiave è un segreto: **non** va
/// in UserDefaults (plist in chiaro), quindi vive in un file dedicato con permessi `0600` in
/// `~/.relay` (leggibile solo dall'utente). Scelta deliberata rispetto al Keychain finché la firma
/// del bundle è ad-hoc (cambia a ogni build/upgrade e farebbe scattare un prompt di accesso al
/// Keychain a ripetizione, vedi la gotcha sulla firma in CLAUDE.md); migrabile a Keychain quando
/// ci sarà una firma stabile.
///
/// Sta nel composition root (RelayApp), non in un modulo puro: fa I/O su disco, come `LayoutStore`.
/// Il path è iniettabile per non toccare il vero `~/.relay` nei test.
@MainActor
final class NamingCredentialStore {
    private let path: String
    private let log = RelayLog.logger("naming")

    /// Default: `~/.relay/naming-credentials.json`. Override del path per i test.
    init(path: String? = nil) {
        self.path = path ?? (RelayRuntimePaths.runtimeDirectory as NSString)
            .appendingPathComponent("naming-credentials.json")
    }

    /// La chiave salvata, o `nil` se il file manca/è illeggibile/vuoto. Senza chiave la feature è
    /// inerte (il `NamingController` non parte).
    func loadKey() -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        let key = payload.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    /// Salva (o cancella) la chiave. `nil`/vuoto rimuove il file. Scrittura atomica seguita da
    /// `chmod 0600`: il file nasce con i permessi di default della umask, li stringiamo subito.
    func saveKey(_ key: String?) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            try? FileManager.default.removeItem(atPath: path)
            return
        }
        do {
            try RelayRuntimePaths.ensureRuntimeDirectory()
            let data = try JSONEncoder().encode(Payload(apiKey: trimmed))
            let url = URL(fileURLWithPath: path)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: path
            )
        } catch {
            log.error("could not persist API key: \(error.localizedDescription)")
        }
    }

    /// `true` se esiste una chiave salvata (per l'indicatore nelle impostazioni, senza esporla).
    func hasKey() -> Bool {
        loadKey() != nil
    }

    private struct Payload: Codable {
        let apiKey: String
    }
}
