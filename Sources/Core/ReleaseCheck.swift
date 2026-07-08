import Foundation

/// Ultima release pubblicata, estratta dall'API GitHub Releases (`/releases/latest`). Solo i due
/// campi che servono: la versione (dal tag) e la pagina della release (per aprirla nel browser).
public struct LatestRelease: Equatable, Sendable {
    public let version: SemanticVersion
    public let releaseURL: URL

    public init(version: SemanticVersion, releaseURL: URL) {
        self.version = version
        self.releaseURL = releaseURL
    }
}

/// Campi che ci interessano della JSON di `/releases/latest`. GitHub esclude già draft e prerelease
/// da quell'endpoint, ma li teniamo per robustezza (una risposta con `prerelease` true non è un
/// candidato di aggiornamento stabile). Top-level (non annidato in `ReleaseCheck`): così
/// `CodingKeys`
/// non sfora il limite di annidamento.
private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let htmlURL: String
    let draft: Bool?
    let prerelease: Bool?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}

/// Logica pura del check aggiornamenti: parsing della risposta GitHub e decisione se c'è un update
/// azionabile. Niente I/O di rete (quello vive nel composition root, `UpdateController`): qui solo
/// trasformazioni testabili.
public enum ReleaseCheck {
    /// Estrae la release dall'API. `nil` se la JSON non è valida, il tag non è una versione, l'URL
    /// non parsa, o è una draft/prerelease.
    public static func parseLatest(from data: Data) -> LatestRelease? {
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(GitHubReleasePayload.self, from: data) else {
            return nil
        }
        if payload.draft == true || payload.prerelease == true { return nil }
        guard let version = SemanticVersion(payload.tagName),
              let url = URL(string: payload.htmlURL) else { return nil }
        return LatestRelease(version: version, releaseURL: url)
    }

    /// Decide se proporre l'aggiornamento: c'è update solo se `latest` è più recente della versione
    /// installata e non è stato messo in "skip" dall'utente (si salta finché non ne esce una ancora
    /// più nuova). Ritorna la release da mostrare, o `nil` se non c'è niente da proporre.
    public static func actionableUpdate(
        currentVersion: String,
        latest: LatestRelease,
        skipped: String?
    ) -> LatestRelease? {
        guard let current = SemanticVersion(currentVersion) else { return nil }
        guard latest.version > current else { return nil }
        let alreadySkipped = skipped
            .flatMap(SemanticVersion.init)
            .map { latest.version <= $0 } ?? false
        if alreadySkipped { return nil }
        return latest
    }
}
