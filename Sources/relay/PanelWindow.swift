import AppKit
import Core
import SwiftUI

/// Finestra di servizio con dentro una vista SwiftUI (Settings, About, Runtime Stats).
///
/// Due dettagli non negoziabili, entrambi pagati con un crash:
///
/// 1. **`safeAreaRegions = []`** sulla `NSHostingView`. Con la safe area attiva ogni `setFrameSize`
///    della finestra fa invalidare a SwiftUI i suoi safe area insets, che chiede un nuovo "update
///    constraints pass", che ridimensiona la finestra, e così via. Quando i pass superano il numero
///    di view AppKit lancia una `NSGenericException` e l'app abortisce. È lo stesso gotcha della
///    chrome (vedi `ARCHITECTURE`, full-size content view), qui su una finestra separata.
/// 2. **`NSHostingView` + `contentView`**, non `NSHostingController` + `preferredContentSize`:
///    quest'ultimo lascia decidere la dimensione all'engine di layout di SwiftUI, che è proprio la
///    parte che rilancia l'invalidazione.
///
/// La finestra non è ridimensionabile: la dimensione la fissa il chiamante.
@MainActor
func makePanelWindow(
    title: String,
    size: NSSize,
    theme: RelayTheme,
    content: some View
) -> NSWindow {
    let host = NSHostingView(rootView: content)
    host.safeAreaRegions = []

    let panel = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    panel.title = title
    panel.isReleasedWhenClosed = false
    panel.contentView = host
    panel.setContentSize(size)
    panel.center()
    panel.applyRelayChrome(theme)
    return panel
}
