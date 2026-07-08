import Foundation

/// Versione semver ridotta (major.minor.patch), abbastanza per confrontare la versione installata
/// con l'ultima release. Tollera il prefisso `v` (tag GitHub) e ignora un eventuale suffisso di
/// pre-release (`-beta`) o build (`+sha`): per il confronto contano solo i tre numeri.
public struct SemanticVersion: Comparable, Equatable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parsa `"0.5.5"`, `"v0.5.5"`, `"1.2"` (patch = 0). Ritorna `nil` se non c'è nemmeno il major
    /// numerico. Il suffisso dopo `-`/`+` viene scartato prima del parsing.
    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        // Scarta pre-release/build: "1.2.3-beta.1+sha" -> "1.2.3".
        text = String(text.prefix { $0.isNumber || $0 == "." })
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard let first = parts.first, let major = Int(first) else { return nil }
        self.major = major
        minor = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        patch = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }
}
