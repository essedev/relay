/// Accumula delta di scroll frazionari (in righe) e restituisce le righe intere da applicare.
/// Il terminale scrolla solo a righe intere: il residuo sub-riga si conserva tra gli eventi,
/// così i gesti lenti del trackpad (delta < 1 riga a evento) si sommano invece di perdersi.
/// Al cambio di direzione il residuo si azzera: l'inversione non deve "ripagare" il residuo
/// accumulato nel verso opposto.
struct PreciseScrollAccumulator {
    private var residual: Double = 0

    /// Aggiunge un delta (positivo = verso l'alto, come `scrollUp`) e restituisce le righe
    /// intere maturate. Delta nulli o non finiti sono ignorati.
    mutating func lines(addingDeltaInRows delta: Double) -> Int {
        guard delta != 0, delta.isFinite else { return 0 }
        if residual != 0, (residual < 0) != (delta < 0) {
            residual = 0
        }
        residual += delta
        let whole = residual.rounded(.towardZero)
        residual -= whole
        return Int(whole)
    }
}
