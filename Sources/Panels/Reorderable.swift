import SwiftUI

/// Riordino via drag & drop **in-app**, fluido, condiviso da sidebar (verticale) e tab bar
/// (orizzontale). Niente `onDrag`/`onDrop` di sistema (che generano una preview con snap-back al
/// rilascio): trasciniamo la riga *vera* con un `DragGesture` + `.offset` (sollevata,
/// semitrasparente) e mostriamo una linea di inserimento live. Al rilascio lo scambio parte in
/// `withAnimation` mentre l'offset torna a zero, così la riga si posa senza salti.
///
/// Meccanica: ogni elemento misura il proprio frame di layout in un coordinate space nominato.
/// La misura vive dentro `reorderableRow`, **fuori** (dopo) l'`.offset` del drag: un GeometryReader
/// dentro l'offset ne assorbe la traslazione (l'offset è un GeometryEffect, si propaga alla
/// geometria dei discendenti anche nello space nominato), il frame della riga in volo si muoveva
/// col gesto e il centro proiettato diventava frame + 2x la traslazione - la linea di inserimento
/// derivava proporzionalmente alla distanza. Misurato fuori, il frame resta il layout stabile.
/// Dal centro proiettato della riga in volo (frame originale + traslazione, non il puntatore
/// grezzo) ricaviamo l'indice di inserimento (`reorderInsertionIndex`), così la linea segue il
/// corpo della riga a prescindere dal punto di presa; la semantica del drop la decide il caller
/// (`perform`). Lo stato del gesto vive in un
/// `@GestureState` del caller: un solo elemento per
/// lista si muove, niente pasteboard condivisa, e SwiftUI lo azzera da solo anche a gesto
/// annullato (menu contestuale, perdita focus), così nessuna riga resta sollevata e nessun drag
/// successivo parte rotto.
enum ReorderAxis {
    case vertical
    case horizontal
}

/// Stato effimero del gesto di riordino: elemento in volo, traslazione lungo l'asse e slot di
/// inserimento corrente. In un `@GestureState` con `resetTransaction` animata: il reset (fine o
/// annullamento del gesto) riposa la riga con la stessa curva dello scambio.
struct ReorderDragState: Equatable {
    var id: UUID?
    var translation: CGFloat = 0
    var insertion: Int?
}

/// Raccoglie i frame degli elementi riordinabili: indice visivo -> rettangolo nel coordinate space.
struct ReorderFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] {
        [:]
    }

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Indice di inserimento (0...count) data una posizione lungo l'asse: quante righe hanno il centro
/// prima di essa. `count` = posizione finale (dopo l'ultimo elemento).
func reorderInsertionIndex(
    location: CGPoint,
    frames: [Int: CGRect],
    axis: ReorderAxis,
    count: Int
) -> Int {
    let pos = axis == .vertical ? location.y : location.x
    let mids = (0 ..< count)
        .compactMap { i -> (Int, CGFloat)? in
            guard let f = frames[i] else { return nil }
            return (i, axis == .vertical ? f.midY : f.midX)
        }
        .sorted { $0.1 < $1.1 }
    var index = 0
    for (i, mid) in mids {
        if pos > mid { index = i + 1 } else { break }
    }
    return index
}

/// Indice di inserimento guidato dal **centro proiettato** della riga trascinata (frame originale +
/// traslazione), non dal puntatore grezzo. Così la linea segue il *corpo* della riga sollevata ed è
/// **indipendente dal punto di presa** lungo la riga: afferrarla in cima o in fondo dà lo stesso
/// risultato (col puntatore grezzo la decisione sfasava di quanto eri lontano dal centro). Se manca
/// il frame della riga, ricade sulla sola traslazione (caso improbabile, frame non ancora
/// misurato).
func reorderInsertionIndex(
    draggedIndex: Int,
    translation: CGFloat,
    frames: [Int: CGRect],
    axis: ReorderAxis,
    count: Int
) -> Int {
    let base = frames[draggedIndex].map { axis == .vertical ? $0.midY : $0.midX } ?? 0
    let center = base + translation
    let point = axis == .vertical ? CGPoint(x: 0, y: center) : CGPoint(x: center, y: 0)
    return reorderInsertionIndex(location: point, frames: frames, axis: axis, count: count)
}

/// La linea di inserimento, posizionata al bordo dell'elemento `insertion` (o in coda dopo
/// l'ultimo). Vive in un overlay ancorato al contenitore, nello stesso coordinate space dei frame.
struct ReorderInsertionLine: View {
    let insertion: Int?
    let frames: [Int: CGRect]
    let axis: ReorderAxis
    let count: Int
    let color: Color
    var thickness: CGFloat = 2

    var body: some View {
        // `offset(for:)` ritorna nil se count == 0 o il frame manca: nessun guard extra sul count.
        if let insertion, let offset = offset(for: insertion) {
            line
                .offset(
                    x: axis == .horizontal ? offset - thickness / 2 : 0,
                    y: axis == .vertical ? offset - thickness / 2 : 0
                )
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var line: some View {
        if axis == .vertical {
            Rectangle().fill(color).frame(height: thickness).frame(maxWidth: .infinity)
        } else {
            Rectangle().fill(color).frame(width: thickness).frame(maxHeight: .infinity)
        }
    }

    /// Bordo iniziale dell'elemento bersaglio; per l'ultima posizione, bordo finale dell'ultimo.
    private func offset(for insertion: Int) -> CGFloat? {
        if insertion < count {
            guard let f = frames[insertion] else { return nil }
            return axis == .vertical ? f.minY : f.minX
        }
        guard let f = frames[count - 1] else { return nil }
        return axis == .vertical ? f.maxY : f.maxX
    }
}

/// Parametri di una riga riordinabile. Struct (init sintetizzato) per tenere snella la firma.
struct ReorderRowConfig {
    let id: UUID
    /// Indice visivo della riga (stesso passato a `reorderFrame`): serve a proiettarne il centro
    /// durante il drag, così l'inserimento segue il corpo della riga e non il punto di presa.
    let index: Int
    let axis: ReorderAxis
    let space: String
    let count: Int
    let frames: [Int: CGRect]
    /// Il wrapper `@GestureState` del caller (per `.updating`) e il suo valore corrente (per il
    /// rendering): SwiftUI azzera il wrapper da solo a fine/annullamento gesto.
    let drag: GestureState<ReorderDragState>
    let state: ReorderDragState
    let perform: (Int) -> Void

    /// Indice di inserimento per la traslazione corrente, dal centro proiettato della riga.
    func insertionIndex(for translation: CGSize) -> Int {
        reorderInsertionIndex(
            draggedIndex: index,
            translation: shift(of: translation),
            frames: frames,
            axis: axis,
            count: count
        )
    }

    /// Componente della traslazione lungo l'asse della lista.
    func shift(of translation: CGSize) -> CGFloat {
        axis == .vertical ? translation.height : translation.width
    }
}

/// Gesto di trascinamento di una riga: aggiorna traslazione e linea di inserimento durante il
/// movimento, esegue lo scambio animato al rilascio. Free function (non modifier) per leggibilità.
/// `@MainActor`: costruisce un `Gesture` SwiftUI (isolato al main actor).
@MainActor
private func reorderDragGesture(_ config: ReorderRowConfig) -> some Gesture {
    DragGesture(minimumDistance: 6, coordinateSpace: .named(config.space))
        .updating(config.drag) { value, state, _ in
            if state.id == nil { state.id = config.id }
            guard state.id == config.id else { return }
            state.translation = config.shift(of: value.translation)
            state.insertion = config.insertionIndex(for: value.translation)
        }
        .onEnded { value in
            // Il gesto vive sulla riga dove il drag è partito: niente guard sull'id. Lo scambio
            // parte qui; il reset (animato) dello stato lo fa la resetTransaction del caller.
            let index = config.insertionIndex(for: value.translation)
            withAnimation(.easeInOut(duration: 0.2)) {
                config.perform(index)
            }
        }
}

/// Parametri del contenitore: coordinate space, raccolta frame e disegno della linea.
struct ReorderContainerConfig {
    let space: String
    let axis: ReorderAxis
    let count: Int
    let frames: Binding<[Int: CGRect]>
    let insertion: Int?
    let lineColor: Color
}

extension View {
    /// Rende la riga trascinabile: la solleva (offset + semitrasparenza + zIndex) seguendo il dito,
    /// misura il suo frame di layout, aggiorna la linea di inserimento durante il gesto ed esegue
    /// lo scambio animato al rilascio. La misura sta **dopo** l'offset, mai prima: un
    /// GeometryReader dentro l'offset ne assorbirebbe la traslazione (frame in volo = layout +
    /// gesto, centro
    /// proiettato raddoppiato, linea che deriva con la distanza); fuori, misura il frame di layout,
    /// stabile per tutto il gesto.
    func reorderableRow(_ config: ReorderRowConfig) -> some View {
        let isDragging = config.state.id == config.id
        let shift = isDragging ? config.state.translation : 0
        return offset(
            x: config.axis == .horizontal ? shift : 0,
            y: config.axis == .vertical ? shift : 0
        )
        .opacity(isDragging ? 0.6 : 1)
        .zIndex(isDragging ? 1 : 0)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ReorderFramesKey.self,
                    value: [config.index: proxy.frame(in: .named(config.space))]
                )
            }
        )
        .gesture(reorderDragGesture(config))
    }

    /// Rende il contenitore (VStack/HStack) bersaglio del riordino: definisce il coordinate space,
    /// raccoglie i frame e disegna la linea di inserimento in overlay.
    func reorderableContainer(_ config: ReorderContainerConfig) -> some View {
        coordinateSpace(.named(config.space))
            .overlay(alignment: .topLeading) {
                ReorderInsertionLine(
                    insertion: config.insertion,
                    frames: config.frames.wrappedValue,
                    axis: config.axis,
                    count: config.count,
                    color: config.lineColor
                )
            }
            .onPreferenceChange(ReorderFramesKey.self) { config.frames.wrappedValue = $0 }
    }
}
