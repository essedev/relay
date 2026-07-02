# Misure di performance (Milestone 3)

I numeri dietro ai budget di `ARCHITECTURE.md` (sezione "Budget v1") e la taratura del cap LRU.
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
