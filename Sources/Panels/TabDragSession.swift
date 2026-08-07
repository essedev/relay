import SwiftUI
import WorkspaceModel

/// Il drag di una tab **fuori dalla sua strip**, verso un altro workspace nella sidebar.
///
/// Serve un intermediario perché strip e sidebar vivono in due `NSHostingView` sorelle: un
/// coordinate space SwiftUI non le attraversa, e la riga sollevata verrebbe clippata al bordo della
/// strip proprio mentre esci. La lingua comune sono le **coordinate finestra con origine in alto a
/// sinistra**: la strip ci pubblica il puntatore, la sidebar ci registra le righe come bersagli, il
/// composition root ci osserva per disegnare il fantasma sopra tutta la finestra.
///
/// Una per finestra: le finestre partizionano i workspace, e due sidebar che scrivessero gli stessi
/// bersagli si sovrapporrebbero in coordinate.
///
/// Il riordino orizzontale dentro la strip non passa di qui: finché il puntatore resta nella strip
/// (`isOutside == false`) vale la meccanica di `Reorderable`, invariata.
@MainActor
@Observable
public final class TabDragSession {
    /// La tab in volo. `sourceWorkspaceID` serve a escludere la riga di partenza dai bersagli:
    /// rilasciarla a casa sua non è uno spostamento.
    public struct Payload: Equatable, Sendable {
        public let tabID: UUID
        public let sourceWorkspaceID: UUID
        public let title: String

        public init(tabID: UUID, sourceWorkspaceID: UUID, title: String) {
            self.tabID = tabID
            self.sourceWorkspaceID = sourceWorkspaceID
            self.title = title
        }
    }

    public private(set) var payload: Payload?
    /// Puntatore in coordinate finestra (origine in alto a sinistra). Cambia a ogni evento del
    /// mouse, quindi **nessuno oltre al fantasma deve osservarla**: il fantasma esiste solo fuori
    /// dalla strip, così un riordino orizzontale non invalida niente (vedi `target`).
    public private(set) var location: CGPoint = .zero
    /// Il gesto ha lasciato la strip di partenza: da qui il fantasma è visibile e il rilascio può
    /// cambiare workspace.
    public private(set) var isOutside = false

    /// Righe candidate al drop, **nello spazio della sidebar** (workspace -> frame). Il passaggio a
    /// coordinate finestra lo fa `target` con `sidebarRect`: così la sidebar riscrive i frame solo
    /// quando cambia il layout, non a ogni pixel di trascinamento.
    public private(set) var targets: [UUID: CGRect] = [:]
    /// La sidebar in coordinate finestra. Fa anche da guardia: fuori di qui non c'è drop, e una
    /// sidebar collassata (larghezza ~0) non può accogliere niente, anche se i frame delle sue
    /// righe sono ancora quelli dell'ultimo layout.
    public private(set) var sidebarRect: CGRect = .zero

    /// Il composition root monta e smonta il fantasma qui: true quando il drag esce dalla strip.
    public var onGhostVisibilityChange: ((Bool) -> Void)?

    public init() {}

    /// Il workspace sotto il puntatore, o `nil` se il drop non sposterebbe niente (dentro la strip,
    /// fuori dalla sidebar, fuori da ogni riga, o sulla riga di partenza).
    ///
    /// **Stored, non computed**: la sidebar lo legge nel proprio body per evidenziare la riga, e da
    /// computed dipenderebbe da `location`, cioè si ridisegnerebbe a ogni pixel di trascinamento -
    /// anche durante un riordino orizzontale che non la riguarda, rubando main thread al gesto.
    /// Così si invalida solo quando il bersaglio cambia davvero.
    public private(set) var target: UUID?

    /// Il bersaglio per la posizione corrente. Legge proprietà osservate, ma sempre fuori da un
    /// body SwiftUI (da `move`), quindi non crea dipendenze.
    private func resolveTarget() -> UUID? {
        guard isOutside, let payload, sidebarRect.contains(location) else { return nil }
        return TabDropTargets.hit(
            CGPoint(x: location.x - sidebarRect.minX, y: location.y - sidebarRect.minY),
            in: targets,
            excluding: payload.sourceWorkspaceID
        )
    }

    // MARK: - Registro dei bersagli (scritto dalla sidebar durante il layout)

    /// Tutte le scritture di geometria deduplicano: la sidebar le fa durante il layout e legge
    /// `target` nel body, quindi riassegnare lo stesso valore accenderebbe un giro di
    /// invalidazione per ogni misura.
    public func setSidebarRect(_ rect: CGRect) {
        guard sidebarRect != rect else { return }
        sidebarRect = rect
    }

    public func setTarget(_ id: UUID, frame: CGRect) {
        guard targets[id] != frame else { return }
        targets[id] = frame
    }

    /// Toglie una riga dai bersagli: scrollata fuori dal suo contenitore, o non più a schermo.
    public func clearTarget(_ id: UUID) {
        guard targets[id] != nil else { return }
        targets[id] = nil
    }

    /// Scarta i bersagli di righe che non esistono più (workspace chiuso, card richiusa): il loro
    /// frame resterebbe a coprire un'area dove ora c'è altro.
    public func pruneTargets(keeping ids: Set<UUID>) {
        guard !targets.keys.allSatisfy(ids.contains) else { return }
        targets = targets.filter { ids.contains($0.key) }
    }

    public func begin(_ payload: Payload) {
        self.payload = payload
        isOutside = false
        target = nil
    }

    /// Aggiorna il puntatore. `outside` lo decide la strip, che conosce i propri bounds.
    public func move(to point: CGPoint, outside: Bool) {
        location = point
        if isOutside != outside {
            isOutside = outside
            onGhostVisibilityChange?(outside)
        }
        let hit = resolveTarget()
        guard target != hit else { return }
        target = hit
    }

    /// Chiude il gesto e restituisce il bersaglio su cui è stato rilasciato (`nil` = nessuno, il
    /// chiamante ricade sul riordino nella strip).
    @discardableResult
    public func end() -> UUID? {
        let hit = target
        payload = nil
        target = nil
        if isOutside {
            isOutside = false
            onGhostVisibilityChange?(false)
        }
        return hit
    }
}

/// Hit test dei bersagli del drop: puro e testato, perché è la sola regola che decide dove finisce
/// una sessione viva. Se più righe contengono il punto (non dovrebbe accadere: le righe non si
/// sovrappongono) vince quella col centro più vicino, così il risultato non dipende dall'ordine di
/// iterazione di un dizionario.
public enum TabDropTargets {
    public static func hit(
        _ point: CGPoint,
        in targets: [UUID: CGRect],
        excluding excluded: UUID?
    ) -> UUID? {
        targets
            .filter { $0.key != excluded && $0.value.contains(point) }
            .min { lhs, rhs in distance(point, to: lhs.value) < distance(point, to: rhs.value) }?
            .key
    }

    private static func distance(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = point.x - rect.midX
        let dy = point.y - rect.midY
        return dx * dx + dy * dy
    }
}

/// Il fantasma della tab in volo: una pill col titolo che segue il puntatore, montata dal
/// composition root in un overlay a livello finestra (le due hosting view di strip e sidebar sono
/// sorelle, nessuna delle due può disegnare sopra l'altra).
public struct TabDragGhost: View {
    let session: TabDragSession
    let settings: AppSettings

    public init(session: TabDragSession, settings: AppSettings) {
        self.session = session
        self.settings = settings
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        return Group {
            if let payload = session.payload, session.isOutside {
                Text(payload.title)
                    .font(Theme.Typography.tab)
                    .foregroundStyle(colors.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: Theme.Metrics.maxTabWidth, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(colors.selection)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .stroke(colors.accent, lineWidth: 1)
                    )
                    .shadow(radius: 6, y: 2)
                    .opacity(0.9)
                    // Scostato dal puntatore: sotto la freccia nasconderebbe la riga bersaglio.
                    .offset(x: session.location.x + 10, y: session.location.y - 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// Riporta il rettangolo della view che avvolge, in **coordinate finestra con origine in alto a
/// sinistra**: la lingua comune di `TabDragSession`. `NSViewRepresentable` e non un
/// `GeometryReader`, perché `.global` in SwiftUI è relativo alla propria hosting view e qui il
/// punto è proprio uscirne.
struct WindowRectReader: NSViewRepresentable {
    let onChange: (CGRect) -> Void

    func makeNSView(context _: Context) -> ReporterView {
        let view = ReporterView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ReporterView, context _: Context) {
        nsView.onChange = onChange
    }

    final class ReporterView: NSView {
        var onChange: ((CGRect) -> Void)?
        /// Ultimo valore riportato: `report()` scatta a ogni layout, e la strip si rilayouta a ogni
        /// evento del gesto. Senza questo confronto ogni passata riscriverebbe lo stesso rettangolo
        /// nello `@State` del chiamante, invalidandone il body per niente.
        private var reported: CGRect?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }

        override func setFrameOrigin(_ newOrigin: NSPoint) {
            super.setFrameOrigin(newOrigin)
            report()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            report()
        }

        override func layout() {
            super.layout()
            report()
        }

        /// Le coordinate finestra di AppKit hanno origine in basso a sinistra; qui si ribalta una
        /// volta sola, sull'altezza della content view, che è anche il riquadro in cui il
        /// composition root disegna il fantasma.
        private func report() {
            guard let window, let content = window.contentView else { return }
            let rect = convert(bounds, to: nil)
            let flipped = CGRect(
                x: rect.minX,
                y: content.bounds.height - rect.maxY,
                width: rect.width,
                height: rect.height
            )
            guard reported != flipped else { return }
            reported = flipped
            onChange?(flipped)
        }
    }
}

extension View {
    /// Osserva il rettangolo di questa view in coordinate finestra (vedi `WindowRectReader`).
    func windowRect(_ onChange: @escaping (CGRect) -> Void) -> some View {
        background(WindowRectReader(onChange: onChange))
    }
}

/// Le misure che servono **solo durante un gesto**: dove sta l'area delle tab e dove la strip, in
/// coordinate finestra.
///
/// Deliberatamente una classe tenuta in uno `@State`, non due `@State` di valore: lo scroll
/// orizzontale della strip sposta il contenuto e quindi ne cambia il rettangolo in finestra a ogni
/// frame, e scriverlo in uno `@State` invaliderebbe la strip per tutta la durata dello scroll.
/// Qui la scrittura non invalida niente, e il gesto legge il valore corrente quando gli serve.
@MainActor
final class DragGeometryBox {
    var tabs: CGRect = .zero
    var strip: CGRect = .zero

    init() {}
}
