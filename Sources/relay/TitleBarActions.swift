import AppKit

/// Con full-size content view le nostre view coprono la title bar: il doppio click di sistema
/// (zoom/minimizza) non arriva più alla finestra. Lo ripristiniamo a mano, rispettando la
/// preferenza utente di macOS (System Settings > Desktop & Dock > Double-click title bar).
@MainActor
enum TitleBarActions {
    static func handleDoubleClick(in window: NSWindow?) {
        guard let window else { return }
        let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
        switch action {
        case "Minimize":
            window.performMiniaturize(nil)
        case "None":
            break
        default:
            window.performZoom(nil)
        }
    }
}
