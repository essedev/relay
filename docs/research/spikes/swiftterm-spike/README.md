# SwiftTerm Spike

Spike di Fase 1: validare SwiftTerm come terminal engine v1, con toolchain standard (no zig, no
binari di terzi). Decisione engine e motivazioni in `../CYCLES.md` (Cycle 5) e
`../ARCHITECTURE.md`.

## Contenuto

- `Sources/swiftterm-spike/` - app AppKit minimale: finestra + `LocalProcessTerminalView` +
  shell locale. Prova che SwiftTerm builda e gira una shell viva.
- `Sources/swiftterm-bench/` - benchmark: throughput del core VT (headless) ed end-to-end nella
  view viva, più memoria.

## Come si esegue

```bash
# app terminale minimale (apre una finestra con la shell)
swift run swiftterm-spike

# benchmark (release, obbligatorio per numeri sensati)
swift build -c release
./.build/release/swiftterm-bench vt      # throughput core VT, headless
./.build/release/swiftterm-bench render  # ingest+render end-to-end nella view viva
```

## Risultati (release, M-series, 2026-07-02)

Core VT (solo parsing, no rendering):

| Payload | Throughput |
| --- | ---: |
| plain text | 82.5 MB/s |
| ANSI color-heavy | 34.6 MB/s |
| scroll / cursor-heavy | 55.8 MB/s |

End-to-end nella view viva: 20.2 MB/s (52 MB in 2.6s).

Memoria: floor idle 90 MB/processo (condiviso); scrollback ~110 MB per 1M righe (col cap a 10k
righe ~1 MB).

## Conclusione

Throughput ampiamente sufficiente per output di agenti (KB/s-MB/s): il timore CoreText lento è
smentito. Restano da misurare in Fase 2, sull'app multi-surface reale: latenza input p99 e costo
memoria incrementale per surface dentro un solo processo.

## Metodo e limiti

- Build release (debug falsa il throughput).
- `bench vt` usa la classe `Terminal` (emulatore UI-agnostic) con delegate no-op: isola il
  parser dal rendering.
- `bench render` lancia una shell reale (`yes | head`) e cronometra fino a `processTerminated`
  (EOF della PTY): proxy stretto di ingest+render, non un render-to-glass frame-perfect; non
  misura latenza input né reattivita durante il burst.
- Memoria via `ps -o rss=`; 1 surface per processo, quindi non misura la scala multi-surface.
