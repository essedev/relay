# Decisioni

Le scelte che vincolano il lavoro futuro e che avevano un'alternativa reale, scartata. Numerazione
globale e stabile: si citano come `DECISIONS #N`, anche dopo che una voce esce di qui. Status:
`proposta` (discussa, non ratificata), `attiva`, `superata da #M`, `assorbita in <doc>`. Il
racconto di ogni giro sta in `docs/research/CYCLES.md`; qui resta solo la regola.

Le voci nascono quando un ciclo esce dalla rotazione di CYCLES (o quando un ciclo chiuso prende
una decisione nuova): i cicli ancora in CYCLES portano le loro decisioni nel testo.

## #1 - Strumenti di lint pinnati, non da brew

Status: attiva. Fonte: Cycle 14.
SwiftFormat e SwiftLint si scaricano a versione fissa in `.build/tools` (`make tools`, versioni nel
`Makefile`), e CI e locale girano gli stessi binari. Scartato `brew install` nel workflow: prende
sempre l'ultima, e una regola nuova bocciava codice invariato (CI rossa da 0.7.0 a 0.7.2). Un
upgrade degli strumenti è un commit esplicito che bumpa la versione.

## #2 - Le eccezioni dell'input da tastiera vivono nella policy

Status: attiva. Fonte: Cycle 15.
Se `Option` produce testo stampabile senza `Cmd`/`Ctrl` quel testo vince, salvo `Option`+cifra
1..9 senza Shift, che resta scorciatoia. L'eccezione sta dentro `Core.KeyboardTextInput`, così
monitor, interceptor verso il PTY e recorder delle impostazioni restano coerenti per costruzione.
Scartata la regola universale (rompeva il cambio tab sui layout non US) e l'eccezione nei
chiamanti (dipenderebbe dall'ordine dei local monitor). Costo accettato: i simboli su
`Option`+cifra non si digitano.

## #3 - Il cap LRU delle surface è soft e protegge il contesto

Status: attiva. Fonte: Cycle 9 e 15.
`SurfaceEvictionPolicy` non sfratta mai la tab visibile, il workspace attivo, l'attenzione fresca,
le tab toccate di recente né una tab con lavoro vivo; se i candidati non bastano il cap si sfora.
Scartato il cap rigido: sforare costa memoria, sfrattare costa scrollback e shell all'utente. Il
cap non va esteso alle sessioni agente (vedi `docs/ROADMAP.md`, disattivazione automatica).

## #4 - Runtime Stats campiona solo a pannello aperto

Status: attiva. Fonte: Cycle 15.
`RuntimeStatsSampler` gira finché il pannello è aperto e invalida il timer in `windowWillClose`; resta
separato da `PerfSampler`, che è dev tooling (`RELAY_PERF`). Scartati il polling permanente e la
fusione dei due campionatori: l'osservabilità per l'utente non deve costare nulla a regime.

## #5 - Note di release dai conventional commit

Status: attiva. Fonte: Cycle 15.
Il body di una GitHub Release lo genera `scripts/release-notes.sh` raggruppando per tipo i commit
fra due tag. Scartato `gh release create --generate-notes`: genera dalle PR, e il repo è
trunk-based, quindi produceva un body vuoto. La conseguenza è che il messaggio di commit è il testo
della release.

## #6 - Chiudere un progetto riusa il campo dell'archivio

Status: attiva. Fonte: Cycle 30.
Un progetto chiuso è `Workspace.closed`, che su disco resta la chiave `archived`: nessuna entità
nuova, nessuna migrazione. Chiudere disattiva le sessioni tenendo i `ResumeBinding` e butta le
surface; rimuovere (`Remove Project`) resta il solo gesto distruttivo. Scartate un'entità a parte e
la chiave rinominata: un binario precedente leggerebbe tutti i chiusi come aperti.

## #7 - Un progetto chiuso resta nel suo gruppo

Status: attiva. Fonte: Cycle 30.
Chiudere non tocca `groupID`: la card mostra solo i membri aperti (`members(of:)`) e un gruppo coi
membri tutti chiusi esiste ancora. Sostituisce la regola dell'archivio, che tirava fuori dal gruppo
e rendeva `archived` e `groupID` mutuamente esclusivi. Scartata perché chiudere deve essere un gesto
senza perdita: riaprire rimette il progetto dove stava. Restano esclusivi solo `pinned` con
`closed` e `pinned` con `groupID`.

## #8 - Il triage è una pagina, non un overlay

Status: attiva. Fonte: Cycle 30.
Home e Projects sono pagine del right pane (`RelayWindow.page`) che coprono i terminali senza
smontarli; la dashboard overlay, il kanban e la sua preferenza sono stati tolti. Home conta solo i
progetti aperti. Scartato tenere la dashboard accanto a Home: due viste di triage sugli stessi
dati. L'azione rimappabile resta `toggleDashboard` per non perdere le combinazioni salvate.

## #9 - La sidebar elenca solo il lavoro aperto

Status: attiva. Fonte: Cycle 30.
In sidebar stanno palette, Home, Projects e i progetti aperti; i chiusi si raggiungono dalla
palette (`Cmd+P`) e dal catalogo. Scartata la sezione dei chiusi in fondo, come l'archivio di
prima: riportava nella lista di lavoro quello che hai messo via.

## #10 - La cornice della finestra è nostra, coi colori del tema

Status: attiva. Fonte: Cycle 30.
Sidebar e contenuto sono due card arrotondate su una cornice un gradino più scura del fondo del tema
(`RelayTheme.chromeFrame`, `CardContainerController`). Scartato il materiale della sidebar nativa
di macOS 26 (e `sidebarWithViewController:`): porta il suo materiale e ignora il tema, quindi un
tema chiaro non resterebbe chiaro.
