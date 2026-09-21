# Misure di performance

I numeri dietro ai budget di `ARCHITECTURE.md` (sezione "Budget v1") e la taratura del cap LRU
(Milestone 3), più le misure di consumo sotto carico reale (leak di processi e fd alla chiusura).
Ri-eseguibili con la strumentazione integrata (`RELAY_PERF=1`, vedi sotto). Macchina di misura:
MacBook, build **release** (`swift build -c release`), 2 luglio 2026.

## Come rieseguire

La strumentazione è dev tooling come demo/simulate: spenta a regime (costo zero), si accende con
variabili d'ambiente.

- `RELAY_PERF=1` - avvia il `PerfSampler`: ogni 2s logga (categoria `perf`) RSS del processo,
  numero di surface vive e le statistiche di latenza del monitor di input. All'avvio esegue anche
  un micro-benchmark della latenza input (5000 iterazioni).
- `RELAY_PERF_CYCLE=1` - cicla il focus tra tutte le tab (una ogni 1.5s) per realizzare le surface
  e far salire la memoria fino al cap.
- `RELAY_SURFACE_CAP=N` - override del cap LRU (default 12), per esplorare la pendenza
  memoria/surface oltre il default.

```sh
# Pendenza memoria/surface (cap alzato per vedere tutte le surface vive insieme):
RELAY_PERF=1 RELAY_PERF_CYCLE=1 RELAY_SURFACE_CAP=30 .build/release/relay --demo 5x6
# In un altro terminale, streamma i campioni:
log stream --style compact --level info --predicate \
  'subsystem == "dev.relay.app" AND category == "perf"'
```

## Latenza input aggiunta dallo shell

**Budget**: < 1 frame (16ms) p99. **Misura**: p50 ~0ms, p99 ~0ms, **max 0.0024ms** (2.4µs) su 5000
keystroke sintetici (carattere semplice, il caso comune del digitare).

Interpretazione: Relay non siede sul path di input del terminale. L'unico codice che gira su ogni
keyDown prima che SwiftTerm veda l'evento è il monitor `Cmd/Option` (`handleNavigationKey`): un
check dei modificatori che, per un carattere normale, ritorna subito. Il rendering e l'emulazione VT
- il grosso della latenza percepita keystroke-to-glyph - sono di SwiftTerm, fuori dal nostro
controllo e fuori da questo budget ("latenza *aggiunta dallo shell*"). Margine di ~4 ordini di
grandezza: non è un'area da ottimizzare.

## Memoria vs surface vive (taratura cap LRU)

**Budget correlato**: renderer vivi = pane visibili + qualche recente (LRU); costo di un workspace
mai aperto ~0. **Misura** (demo, cap alzato a 30, focus ciclato per realizzare tutte le surface):

| Surface vive | RSS (steady state) |
| --- | --- |
| 1 | ~90 MB (base app) |
| 13 | ~92 MB |
| 20 | ~94 MB |
| 30 | ~98-99 MB |

Note di lettura:

- I primi ~15s post-lancio mostrano un transiente (~126-132 MB) da cache di avvio e autorelease
  pool, poi reclaimato: lo steady state è ~90-99 MB. I numeri sopra sono steady state.
- Pendenza marginale: **~0.3-0.5 MB per surface idle**. Sorprendentemente bassa perché una surface
  idle è PTY + emulatore quasi senza scrollback.
- **Caveat**: le shell della demo producono pochissimo output, quindi questa è la memoria *di base*
  di una surface, non una con lo scrollback pieno. Il driver di memoria vero è lo scrollback
  (cellule stilizzate), che però è cappato a 10k righe per surface: è quello il tetto per surface,
  non la struttura.

### Conclusione sul cap

Il cap LRU resta **12**. Con la pendenza misurata, 12 surface idle costano pochi MB sopra la base
(~90 MB). Anche nel caso pessimistico di 12 surface con scrollback pieno (poche MB l'una per il cap
a 10k righe), il totale resta nell'ordine delle centinaia di MB: accettabile per un terminale. Il
cap non è quindi un limite di memoria stretto ma una diga contro la crescita illimitata; tenerlo
generoso è coerente col principio "meglio sforare il cap che uccidere un processo" (l'eviction è
distruttiva: perde lo scrollback). Il knob `RELAY_SURFACE_CAP` resta per ri-tarare se in futuro le
misure su sessioni reali (scrollback pieno) lo richiederanno.

## Leak di processi e fd alla chiusura (settembre 2026)

Misure su uso reale, non su demo: la macchina di misura è la stessa su cui Relay gira tutto il
giorno con decine di sessioni Claude Code in parallelo.

### Stato osservato

Relay in esecuzione da 5 giorni, con **51 tab** nel layout:

| grandezza | valore |
| --- | --- |
| shell figlie dirette del processo Relay | 132 (di cui 2 zombie) |
| fd `/dev/ptmx` aperti | 125, su 146 fd numerici totali |
| processi nell'albero sotto Relay | 561 |
| sessioni `claude` vive | 33, per 6,1 GB di RSS |
| discendenti medi per sessione agente | 8,8 (i server MCP) |

Almeno 81 shell erano residui di tab non più esistenti. Il `RLIMIT_NOFILE` ereditato dalle shell è
1.048.576: l'esaurimento degli fd **non** è il muro vicino, il costo è nei processi.

### Riproduzione

Istanza isolata (`RELAY_SOCKET`/`RELAY_LAYOUT` in una dir temporanea), binario rinominato per non
colpire per sbaglio il Relay vero, pilotata via voci di menu (mirate al processo, a differenza dei
keystroke di System Events che vanno al frontmost):

```text
avvio                        tab/ws=1/1   shell=1   ptmx=1
New Tab x5                   tab/ws=6/1   shell=6   ptmx=6
Close Tab x5                 tab/ws=1/1   shell=6   ptmx=6
New Tab x3 + Split + 2 tab   tab/ws=7/1   shell=12  ptmx=12
Close Pane                   tab/ws=4/1   shell=12  ptmx=12
New Workspace + 3 tab        tab/ws=8/2   shell=16  ptmx=16
Close Workspace              tab/ws=4/1   shell=16  ptmx=16
```

Tutte e tre le strade di chiusura leakano, nessuna rilascia niente. Su cicli ripetuti la crescita è
lineare ed esatta: +10 tab aperte-e-chiuse = +10 shell, +10 ptmx, +10 fd, zero rilasciati. Uccidendo
il processo Relay il kernel chiude gli fd, la pty fa hangup e tutto muore in un secondo: per questo
il leak si vede solo con Relay vivo e si accumula per giorni.

### Causa, isolata su pty reale

Harness che replica `LocalProcess.terminate()` di SwiftTerm alla lettera:

| teardown | figlio in foreground | figlio in background | nessun figlio |
| --- | --- | --- | --- |
| `io.close()` + SIGTERM (SwiftTerm) | shell viva, fd aperto | shell viva, fd aperto | shell viva, fd aperto |
| `io.close(flags: .stop)` + SIGTERM | tutto morto, fd chiuso | idem | idem |
| SIGHUP a pgrp fg + pgrp shell, poi terminate | tutto morto, fd chiuso | idem | idem |

La terza colonna è quella che spiega i numeri: **anche una tab con la shell ferma al prompt leaka**,
non serve un agente vivo. `io.close()` senza `.stop` aspetta il completamento della read pendente sul
master, che su una pty non arriva mai: il cleanup handler non gira e il fd non si chiude, quindi non
c'è hangup. Il `SIGTERM` alla sola shell una zsh interattiva lo ignora (misurato).

### Costo in memoria

- RSS di Relay: **+0,15 MB per tab persa** (88 -> 94 MB su 40 cicli apri-chiudi). L'emulatore e la
  view vengono liberati davvero; restano fd e canale DispatchIO. La memoria di Relay non è il
  problema.
- Il costo vero è nei processi superstiti: ~0,5-1,3 MB per shell, ~200 MB per sessione `claude`,
  più il suo albero MCP.
- Stato della macchina al momento della misura (32 GB): 0,07 GB di RAM libera, compressor a 11,16 GB
  residenti per 51,3 GB logici, swap a 16,6 GB su 17,4. `memory_pressure` riportava "54% free", che
  è fuorviante perché conta inactive e purgeable.

### Cosa invece non cresce

Verificato: `recency`/`lastTouchedAt` (puliti in `evict`), `completionFlashTimers` (si
auto-rimuovono), `activationOrder` (potato alla chiusura finestra), gli stati per-workspace di
`NamingController` (`prune`), le connessioni del receiver (effimere), `~/.relay` (152 KB in tutto),
UserDefaults. Gli 8 `withObservationTracking` si ri-armano 1:1.

`enforceLRU` gira a ogni render e fa una `proc_listchildpids` per candidata, e siccome il cap non è
raggiungibile la sweep si ripete all'infinito: **non è un hot spot**. 6,1 µs per chiamata, e in un
`sample` di 3s del processo vero non compare un solo frame di `enforceLRU` o `hasRunningChildren`
(main thread fermo in `mach_msg` nel 90% dei campioni).
