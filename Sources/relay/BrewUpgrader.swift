import Core
import Foundation

/// Esegue `brew update` e poi `brew upgrade --cask` per la pill di aggiornamento, senza bloccare il
/// main thread. Come leggere l'esito lo decide `Core.BrewUpgrade`; qui solo processi e file.
///
/// `brew` sostituisce il bundle mentre l'app gira: safe su APFS, il processo vivo tiene l'inode
/// vecchio e la versione nuova parte al riavvio. Per questo il cask **non** deve avere
/// `uninstall quit`: chiuderebbe Relay a metà upgrade, con tutte le sessioni e questo processo.
enum BrewUpgrader {
    struct Failure: Error {
        let message: String
        let output: String
    }

    /// Dove cercare brew: un'app aperta dal Finder non eredita il PATH della shell.
    private static let prefixes = ["/opt/homebrew/bin", "/usr/local/bin"]

    private static var brewPath: String? {
        prefixes.map { "\($0)/brew" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// I due comandi in sequenza; il primo che esce con un errore ferma tutto.
    static func run() async throws {
        guard let brew = brewPath else {
            throw Failure(
                message: "Homebrew wasn't found in /opt/homebrew or /usr/local.", output: ""
            )
        }
        for arguments in [["update"], ["upgrade", "--cask", BrewUpgrade.cask]] {
            let (status, output) = try await execute(brew, arguments)
            guard status == 0 else {
                throw Failure(message: BrewUpgrade.failureMessage(output: output), output: output)
            }
        }
    }

    /// La versione dell'Info.plist del bundle **sul disco**: `Bundle.main` tiene in cache quella
    /// con cui l'app è partita, che dopo l'upgrade non è più vera.
    static func versionOnDisk(of bundleURL: URL) -> String? {
        let plist = bundleURL.appendingPathComponent("Contents/Info.plist")
        let info = NSDictionary(contentsOf: plist)
        return info?["CFBundleShortVersionString"] as? String
    }

    /// L'output va su un file e non su una pipe: `brew update` può scriverne abbastanza da
    /// riempire il buffer di una pipe e restare bloccato finché nessuno la legge.
    private static func execute(
        _ path: String, _ arguments: [String]
    ) async throws -> (Int32, String) {
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-brew-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: log)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        return (status, (try? String(contentsOf: log, encoding: .utf8)) ?? "")
    }

    /// L'ambiente dell'app con un PATH che trova brew e i suoi strumenti. `NO_AUTO_UPDATE` perché
    /// `brew update` è già il primo comando; `NO_ENV_HINTS` toglie i consigli dall'output, che
    /// finirebbero nel messaggio d'errore.
    private static var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = (prefixes + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"])
            .joined(separator: ":")
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        return environment
    }
}
