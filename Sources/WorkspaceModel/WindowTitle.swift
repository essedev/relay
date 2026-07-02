import Foundation

/// Titolo contestuale della finestra, dalla tab attiva. Priorità:
/// 1. titolo impostato dal programma o dall'utente (Claude Code manda il nome della chat via OSC,
///    zsh manda `user@host:path`);
/// 2. working directory corrente della tab (OSC 7), abbreviata con `~`;
/// 3. cartella del workspace, poi il suo nome.
@MainActor
public enum WindowTitle {
    public static func compose(
        workspace: Workspace?,
        tab: Tab?,
        home: String = NSHomeDirectory()
    ) -> String {
        guard let workspace else { return "Relay" }
        guard let tab else { return workspace.name }
        if tab.title != Tab.defaultTitle { return tab.title }
        if let directory = tab.currentDirectory { return abbreviate(directory, home: home) }
        if let root = workspace.rootPath { return abbreviate(root, home: home) }
        return workspace.name
    }

    /// `~` al posto della home, come nei prompt.
    static func abbreviate(_ path: String, home: String) -> String {
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
