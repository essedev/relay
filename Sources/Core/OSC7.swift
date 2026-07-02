import Foundation

/// Parsing della working directory riportata dal terminale via OSC 7 (`file://host/path`).
/// Alcune shell mandano il path nudo: accettiamo anche quello.
public enum OSC7 {
    public static func path(from directory: String) -> String? {
        if directory.hasPrefix("/") { return directory }
        guard let url = URL(string: directory), url.scheme == "file" else { return nil }
        let path = url.path
        return path.isEmpty ? nil : path
    }
}
