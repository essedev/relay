import SwiftUI

/// Riordino via drag & drop **in-app**, fluido, condiviso da sidebar (verticale) e tab bar
/// (orizzontale). Niente `onDrag`/`onDrop` di sistema (che generano una preview con snap-back al
/// rilascio): trasciniamo la riga *vera* con un `DragGesture` + `.offset` (sollevata,
/// semitrasparente) e mostriamo una linea di inserimento live. Al rilascio lo scambio parte in
/// `withAnimation` mentre l'offset torna a zero, così la riga si posa senza salti.
///
/// Meccanica: ogni elemento misura il proprio frame di layout in un coordinate space nominato
/// (`reorderFrame`) - l'`.offset` è un trasform di rendering, non tocca il frame di layout, quindi
/// i frame restano stabili durante il trascinamento. Dalla posizione del puntatore ricaviamo
/// l'indice di inserimento (`reorderInsertionIndex`), vincolato dal caller via `clamp` (es. al
/// segmento di float dei workspace). L'identità del trascinato vive in `@State` del caller: un solo
/// elemento per lista si muove, niente pasteboard condivisa, niente drop incrociati.
enum ReorderAxis {
    case vertical
    case horizontal
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

/// Indice di inserimento (0...count) dato il puntatore: quante righe hanno il centro prima di esso
/// lungo l'asse. `count` = posizione finale (dopo l'ultimo elemento).
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
    let axis: ReorderAxis
    let space: String
    let count: Int
    let frames: [Int: CGRect]
    let dragging: Binding<UUID?>
    let translation: Binding<CGFloat>
    let insertion: Binding<Int?>
    let clamp: (Int) -> Int
    let perform: (Int) -> Void

    /// Indice di inserimento per il puntatore, già vincolato dal `clamp` del caller.
    func insertionIndex(at location: CGPoint) -> Int {
        clamp(reorderInsertionIndex(location: location, frames: frames, axis: axis, count: count))
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
        .onChanged { value in
            if config.dragging.wrappedValue == nil {
                config.dragging.wrappedValue = config.id
            }
            guard config.dragging.wrappedValue == config.id else { return }
            config.translation.wrappedValue = config.shift(of: value.translation)
            config.insertion.wrappedValue = config.insertionIndex(at: value.location)
        }
        .onEnded { value in
            guard config.dragging.wrappedValue == config.id else { return }
            let index = config.insertionIndex(at: value.location)
            withAnimation(.easeInOut(duration: 0.22)) {
                config.perform(index) // legge `dragging` prima del reset qui sotto
                config.dragging.wrappedValue = nil
                config.translation.wrappedValue = 0
                config.insertion.wrappedValue = nil
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
    /// Misura il frame di questo elemento (indice visivo) nel coordinate space `space`. L'`.offset`
    /// del drag non lo altera (è un trasform di rendering), quindi resta stabile durante il gesto.
    func reorderFrame(_ index: Int, in space: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ReorderFramesKey.self,
                    value: [index: proxy.frame(in: .named(space))]
                )
            }
        )
    }

    /// Rende la riga trascinabile: la solleva (offset + semitrasparenza + zIndex) seguendo il dito,
    /// aggiorna la linea di inserimento durante il gesto ed esegue lo scambio animato al rilascio.
    func reorderableRow(_ config: ReorderRowConfig) -> some View {
        let isDragging = config.dragging.wrappedValue == config.id
        let shift = isDragging ? config.translation.wrappedValue : 0
        return offset(
            x: config.axis == .horizontal ? shift : 0,
            y: config.axis == .vertical ? shift : 0
        )
        .opacity(isDragging ? 0.6 : 1)
        .zIndex(isDragging ? 1 : 0)
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
