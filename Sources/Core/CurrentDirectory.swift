/// Precedenza fra le fonti della working directory di una tab. Pura: l'ordine è testato qui invece
/// di vivere sparso nelle cascate `??` dei chiamanti (dove si era già invertito una volta).
///
/// Ordine: **shell viva -> ultimo OSC 7 noto -> root del workspace**.
///
/// La shell viva vince perché l'OSC 7 spesso non arriva affatto: `/etc/zshrc` carica l'integrazione
/// da `/etc/zshrc_$TERM_PROGRAM`, e Relay non setta `TERM_PROGRAM` di proposito (maschererebbe il
/// segnale del kitty keyboard protocol), quindi zsh qui non lo emette. Anche quando arriva è fermo
/// all'ultimo prompt: un `cd` seguito da un comando lungo lo lascia indietro.
///
/// L'ultimo valore noto resta la fonte giusta per le tab **non realizzate** (surface mai aperta, o
/// sfrattata dal cap LRU): lì la shell non esiste e `live` è `nil`.
public enum CurrentDirectory {
    /// La cwd migliore nota, o `nil` se nessuna fonte la conosce (la surface partirà dalla home).
    public static func resolve(
        live: String?,
        lastKnown: String?,
        workspaceRoot: String?
    ) -> String? {
        live ?? lastKnown ?? workspaceRoot
    }
}
