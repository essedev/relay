import AppKit
import Core
import Foundation

// Astrazione sottile sull'engine terminale. Il resto dell'app parla con questi tipi, mai con
// SwiftTerm o libghostty direttamente: così cambiare backend è un update localizzato.
// Backend v1: SwiftTerm. Espone solo `NSView` (tipo di piattaforma), mai tipi SwiftTerm.

@MainActor
public protocol TerminalSurfaceHandle: AnyObject {
    var id: UUID { get }
    /// La view da inserire nell'albero AppKit. Tipo di piattaforma, non dell'engine.
    var view: NSView { get }
    /// Notifica quando il programma cambia il titolo (OSC). Usato per auto-titolare la tab.
    var onTitleChanged: ((String) -> Void)? { get set }
    /// Notifica quando la shell riporta la working directory (OSC 7). Path assoluto, già parsato.
    var onDirectoryChanged: ((String) -> Void)? { get set }
    /// Avvia shell/processo. Lazy: chiamato al primo focus del pane (vedi lifecycle ARCHITECTURE).
    func start()
    /// Termina il processo e rilascia le risorse (chiusura tab/workspace).
    func teardown()
    /// Applica un tema (palette, colori base, font). Chiamato alla creazione e sui cambi.
    func apply(theme: RelayTheme)
    /// Nome del comando in esecuzione in foreground nel pty, o `nil` se la shell è al prompt
    /// (nessun comando attivo). Usato per chiedere conferma prima di chiudere una tab "occupata".
    /// Confina i tipi dell'engine: espone solo un `String`.
    func foregroundProcessName() -> String?
    /// Argv completa del processo in foreground nel pty (basename escluso: path grezzo di argv[0] +
    /// argomenti), o `nil` se la shell è al prompt (nessun comando) o la surface non è avviata. A
    /// differenza di `foregroundProcessName` **non** filtra le shell né formatta: espone l'argv
    /// grezza, e la policy (shell nuda -> niente, formattazione) vive nel puro
    /// `Core.WorkspaceNaming`.
    /// Usato dalla nomina automatica dei workspace per capire "cosa stai facendo" (es. `brew
    /// update`).
    func foregroundCommandLine() -> [String]?
    /// Working directory corrente della shell del pty, letta dal processo. Fallback per shell che
    /// non emettono OSC 7: serve a creare nuove tab nella cwd reale della tab attiva.
    func currentDirectory() -> String?
    /// `true` se la shell ha processi figli (foreground, background o agente). Segnala che c'è
    /// lavoro vivo: la surface non va sfrattata dalla LRU (perderebbe quel processo). Più largo di
    /// `foregroundProcessName` (che vede solo il foreground).
    func hasRunningChildren() -> Bool
    /// Scrive testo nello stdin del processo (come se digitato). Usato per iniettare il comando di
    /// resume dell'agente al re-focus di una tab ripristinata. No-op se non ancora avviata.
    func sendText(_ text: String)
    /// Pulisce il terminale: svuota lo scrollback e ripulisce lo schermo riportando il prompt in
    /// cima (come Cmd+K). No-op se non avviata.
    func clear()
    /// Cerca `term` nel buffer, seleziona e scorre alla prossima (`forward`) o precedente
    /// occorrenza. Ritorna posizione corrente (1-based, 0 se nessun match) e totale, per un
    /// contatore "3/12". `term` vuoto azzera. Confina i tipi dell'engine: solo `Int` in uscita.
    func search(_ term: String, forward: Bool) -> (current: Int, total: Int)
    /// Termina la ricerca: azzera stato e selezione.
    func endSearch()
}

@MainActor
public protocol TerminalEngine {
    /// Crea una surface. `env` è iniettato nell'ambiente del processo (oltre a quello di default):
    /// usato per legare la sessione al pane via `RELAY_TAB_ID` (ereditato da shell -> agent ->
    /// hook).
    func makeSurface(cwd: String?, shell: String?, env: [String: String]) -> TerminalSurfaceHandle
}
