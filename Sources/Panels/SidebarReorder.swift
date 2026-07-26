import SwiftUI

/// Meccanica di drag & drop **della sidebar**, dove il gesto attraversa contenitori diversi (lista,
/// card dei gruppi, sezione Archive) e due `ScrollView` distinte. `Reorderable` resta com'è per la
/// strip dei pane, che è un contenitore solo: qui servono due cose che lì sarebbero peso morto.
///
/// 1. **Un coordinate space solo, a livello sidebar**, e i frame raccolti con `onGeometryChange`,
///    non con un `PreferenceKey`: su macOS le preference non attraversano il confine di una
///    `ScrollView` (bridge `NSScrollView`), quindi le righe dell'archivio non arriverebbero mai al
///    registro comune (è la stessa trappola che teneva la sezione Archive alta 1px).
/// 2. **La riga in volo disegnata fuori dalle ScrollView**, in overlay sulla sidebar, invece di
///    essere la riga vera spostata con `.offset`: dentro la sua ScrollView verrebbe clippata al
///    bordo e la vedresti sparire a metà gesto, proprio mentre esci dal contenitore. La riga
///    originale resta al suo posto, sbiadita.
struct SidebarDragState {
    var dragged: SidebarDrop.Dragged?
    /// Indice della riga di partenza nel piano: serve a proiettarne il centro durante il gesto.
    var index: Int = 0
    var translation: CGFloat = 0
    /// Slot di inserimento **già normalizzato** per ciò che si trascina, così la linea non promette
    /// un rilascio che il drop poi non farebbe.
    var insertion: Int?
}

/// Parametri di una riga trascinabile della sidebar.
struct SidebarRowConfig {
    let dragged: SidebarDrop.Dragged
    let index: Int
    let space: String
    let frames: [Int: CGRect]
    let plan: SidebarLayout.Plan
    /// Il wrapper `@GestureState` del caller (per `.updating`) e il suo valore corrente (per il
    /// rendering): SwiftUI lo azzera da solo a fine o annullamento del gesto, così nessuna riga
    /// resta sollevata e il drag successivo parte pulito.
    let drag: GestureState<SidebarDragState>
    let state: SidebarDragState
    let onFrame: (Int, CGRect) -> Void
    let perform: (Int) -> Void

    var isDragging: Bool {
        state.dragged == dragged
    }

    /// Slot di inserimento per la traslazione corrente, dal **centro proiettato** della riga in
    /// volo (frame di layout + traslazione), non dal puntatore grezzo: la linea segue il corpo
    /// della riga ed è indipendente dal punto di presa.
    func insertion(for translation: CGSize) -> Int {
        let raw = reorderInsertionIndex(
            draggedIndex: index,
            translation: translation.height,
            frames: frames,
            axis: .vertical,
            count: plan.count
        )
        return SidebarDrop.normalized(insertion: raw, plan: plan, dragged: dragged)
    }
}

@MainActor
private func sidebarDragGesture(_ config: SidebarRowConfig) -> some Gesture {
    DragGesture(minimumDistance: 6, coordinateSpace: .named(config.space))
        .updating(config.drag) { value, state, _ in
            if state.dragged == nil {
                state.dragged = config.dragged
                state.index = config.index
            }
            guard state.dragged == config.dragged else { return }
            state.translation = value.translation.height
            state.insertion = config.insertion(for: value.translation)
        }
        .onEnded { value in
            let slot = config.insertion(for: value.translation)
            withAnimation(.easeInOut(duration: 0.2)) {
                config.perform(slot)
            }
        }
}

extension View {
    /// Rende la riga trascinabile: misura il suo frame nel coordinate space della sidebar, la
    /// sbiadisce mentre è in volo (la copia che segue il puntatore la disegna la sidebar in
    /// overlay) e al rilascio esegue il drop.
    func sidebarReorderRow(_ config: SidebarRowConfig) -> some View {
        opacity(config.isDragging ? 0.25 : 1)
            .background(
                GeometryReader { _ in
                    // `onGeometryChange`, non un PreferenceKey: vedi la nota in testa al file.
                    Color.clear.onGeometryChange(
                        for: CGRect.self,
                        of: { $0.frame(in: .named(config.space)) },
                        action: { config.onFrame(config.index, $0) }
                    )
                }
            )
            .gesture(sidebarDragGesture(config))
    }

    /// Misura una riga **non** trascinabile (coda di una card, header dell'archivio): non ha gesto,
    /// ma il suo frame serve al calcolo degli slot.
    func sidebarReorderSlot(
        index: Int, space: String, onFrame: @escaping (Int, CGRect) -> Void
    ) -> some View {
        background(
            GeometryReader { _ in
                Color.clear.onGeometryChange(
                    for: CGRect.self,
                    of: { $0.frame(in: .named(space)) },
                    action: { onFrame(index, $0) }
                )
            }
        )
    }
}

/// Linea di inserimento della sidebar: vive in overlay sulla **sidebar intera**, non dentro una
/// ScrollView, così può indicare uno slot dell'archivio mentre trascini dalla lista.
struct SidebarInsertionLine: View {
    let insertion: Int?
    let frames: [Int: CGRect]
    let count: Int
    let color: Color
    /// Rientro della linea quando lo slot è dentro una card: allinea l'indicatore ai membri.
    let indent: CGFloat
    var thickness: CGFloat = 2

    var body: some View {
        if let insertion, let y = edge(for: insertion) {
            Rectangle()
                .fill(color)
                .frame(height: thickness)
                .padding(.leading, indent)
                .offset(y: y - thickness / 2)
                .allowsHitTesting(false)
        }
    }

    /// Bordo superiore della riga bersaglio; per l'ultimo slot, bordo inferiore dell'ultima riga.
    private func edge(for insertion: Int) -> CGFloat? {
        if insertion < count, let frame = frames[insertion] { return frame.minY }
        return frames[count - 1]?.maxY
    }
}
