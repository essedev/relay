import AppKit
import Core
import Foundation
import Panels
import WorkspaceModel

/// Check aggiornamenti (canale brew): confronta la versione installata con l'ultima GitHub Release
/// e, se più recente, accende la pill in sidebar. Dalla pill lancia l'aggiornamento via brew
/// (`BrewUpgrader`) e ne tiene la fase in `availability.phase`; il riavvio lo fa il composition
/// root, che conosce le sessioni. La logica di confronto è pura in `Core.ReleaseCheck`, quella
/// dell'esito di brew in `Core.BrewUpgrade`.
///
/// Funziona solo dal bundle `.app` (la versione arriva da `CFBundleShortVersionString`, assente da
/// `swift run`): senza versione nota `makeSidebarConfig()` torna `nil` e i check sono no-op, come
/// le
/// notifiche.
@MainActor
final class UpdateController {
    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/essedev/relay/releases/latest"
    )!

    /// Errori che valgono un retry: falliscono **subito** perché la rete non è ancora pronta
    /// (interfaccia su ma resolver DNS non caldo al lancio, risveglio dal sleep, switch VPN).
    /// `.timedOut` è escluso di proposito: lì la prima chiamata ha già consumato i 15s di
    /// `timeoutInterval`, e ritentare porterebbe il check manuale a 30s prima dell'alert.
    private static let retriableCodes: Set<URLError.Code> = [
        .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .networkConnectionLost,
    ]
    private static let retryDelay = Duration.seconds(3)

    let availability = UpdateAvailability()

    private let log = RelayLog.logger("update")
    private let settings: AppSettings
    private let session: URLSession
    private let launchSession: URLSession

    /// Due sessioni perché `waitsForConnectivity` è della **configuration**, non della richiesta:
    /// il check al lancio può partire da offline (Wi-Fi non ancora associato) e aspetta che la rete
    /// arrivi, quello manuale deve fallire in fretta e dire cosa è successo.
    init(
        settings: AppSettings,
        session: URLSession = .shared,
        launchSession: URLSession? = nil
    ) {
        self.settings = settings
        self.session = session
        self.launchSession = launchSession ?? Self.makeLaunchSession()
    }

    private static func makeLaunchSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }

    /// Versione installata (nil da `swift run`: nessun Info.plist).
    private var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// Config per la sidebar, o `nil` se non conosciamo la versione (niente pill). `onRestart` lo
    /// fornisce il composition root, che ha lo store e le surface per chiedere conferma.
    func makeSidebarConfig(onRestart: @escaping () -> Void) -> SidebarUpdateConfig? {
        guard let current = currentVersion else { return nil }
        return SidebarUpdateConfig(
            availability: availability,
            currentVersion: current,
            upgradeCommand: BrewUpgrade.command,
            onCopyCommand: { [weak self] in self?.copyCommand() },
            onUpgrade: { [weak self] in self?.upgrade() },
            onRestart: onRestart,
            onOpenRelease: { [weak self] in self?.openRelease() },
            onSkip: { [weak self] in self?.skip() }
        )
    }

    /// Check automatico al lancio: silenzioso, solo se la preferenza è attiva e siamo nel bundle.
    func checkOnLaunch() {
        guard settings.checkForUpdatesAutomatically, currentVersion != nil else { return }
        Task { await check(manual: false) }
    }

    /// Check manuale (menu "Check for Updates…"): dà sempre un feedback, anche "sei aggiornato".
    func checkManually() {
        guard currentVersion != nil else { return }
        Task { await check(manual: true) }
    }

    private func check(manual: Bool) async {
        guard let current = currentVersion else { return }
        do {
            let latest = try await fetchLatest(using: manual ? session : launchSession)
            let actionable = ReleaseCheck.actionableUpdate(
                currentVersion: current,
                latest: latest,
                skipped: settings.skippedUpdateVersion
            )
            availability.latest = actionable
            log.info("update check: latest \(latest.version.description), current \(current)")
            if manual, actionable == nil {
                presentAlert(
                    title: "You're up to date",
                    info: "Relay \(current) is the latest version."
                )
            }
        } catch is BadResponse {
            log.error("update check: bad response")
            if manual { presentAlert(
                title: "Couldn't check for updates",
                info: "Please try again later."
            ) }
        } catch {
            log.error("update check failed: \(error.localizedDescription)")
            if manual { presentAlert(
                title: "Couldn't check for updates",
                info: Self.userFacingMessage(for: error)
            ) }
        }
    }

    /// Risposta HTTP arrivata ma inutilizzabile (status != 200, JSON non parsabile). Distinta dagli
    /// errori di rete: non si ritenta e il messaggio all'utente è un altro.
    private struct BadResponse: Error {}

    /// Una richiesta, più **un solo** retry a distanza di `retryDelay` sugli errori transitori.
    private func fetchLatest(using session: URLSession) async throws -> LatestRelease {
        do {
            return try await requestLatest(using: session)
        } catch let error as URLError where Self.retriableCodes.contains(error.code) {
            log.info("update check: \(error.code.rawValue), retrying once in 3s")
            try await Task.sleep(for: Self.retryDelay)
            return try await requestLatest(using: session)
        }
    }

    private func requestLatest(using session: URLSession) async throws -> LatestRelease {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Relay-Updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let latest = ReleaseCheck.parseLatest(from: data)
        else { throw BadResponse() }
        return latest
    }

    /// Il testo grezzo di URLSession ("A server with the specified hostname could not be found")
    /// descrive il meccanismo, non la causa: per gli errori di rete dice all'utente cosa guardare.
    private static func userFacingMessage(for error: Error) -> String {
        guard let error = error as? URLError else { return error.localizedDescription }
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed,
             .cannotConnectToHost, .timedOut:
            return "Relay couldn't reach GitHub. Check your internet connection and try again."
        default:
            return error.localizedDescription
        }
    }

    // MARK: - Azioni della pill

    /// Lancia brew e porta la fase a `.installed` solo se il bundle da cui gira Relay ha davvero la
    /// versione nuova: brew può riuscire e aggiornare un'altra copia (quella in /Applications
    /// quando questa è altrove), e "riavvia" riaprirebbe la vecchia.
    private func upgrade() {
        guard availability.phase != .running, let latest = availability.latest else { return }
        availability.phase = .running
        log.info("upgrade: running brew for \(latest.version.description, privacy: .public)")
        Task { [weak self] in
            do {
                try await BrewUpgrader.run()
            } catch let failure as BrewUpgrader.Failure {
                self?.log.error("upgrade failed: \(failure.output.suffix(2000), privacy: .public)")
                self?.availability.phase = .failed(failure.message)
                return
            } catch {
                self?.log.error("upgrade failed: \(error.localizedDescription, privacy: .public)")
                self?.availability.phase = .failed(error.localizedDescription)
                return
            }
            self?.finishUpgrade(expected: latest.version)
        }
    }

    private func finishUpgrade(expected: SemanticVersion) {
        let bundleURL = Bundle.main.bundleURL
        let onDisk = BrewUpgrader.versionOnDisk(of: bundleURL)
        switch BrewUpgrade.verify(onDisk: onDisk, expected: expected) {
        case .installed:
            log.info("upgrade: \(onDisk ?? "?", privacy: .public) installed, restart pending")
            availability.phase = .installed
        case let .notReplaced(found):
            log.error("upgrade: bundle still at \(found ?? "?", privacy: .public)")
            availability.phase = .failed(
                BrewUpgrade.notReplacedMessage(onDisk: found, bundlePath: bundleURL.path)
            )
        }
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(BrewUpgrade.command, forType: .string)
    }

    private func openRelease() {
        guard let url = availability.latest?.releaseURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func skip() {
        guard let version = availability.latest?.version.description else { return }
        settings.skipUpdateVersion(version)
        availability.latest = nil
    }

    /// Feedback del check manuale: sheet sulla key window se c'è, altrimenti app-modal.
    private func presentAlert(title: String, info: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.addButton(withTitle: "OK")
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
