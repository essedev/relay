#!/usr/bin/env bash
# Rigenera gli screenshot del README da una demo isolata, in modo ripetibile.
#
# Perché isolata: la demo gira con socket e layout **suoi** (RELAY_SOCKET/RELAY_LAYOUT in una
# cartella temporanea), quindi non tocca ~/.relay e non entra in conflitto con un Relay già aperto
# (il guard single-instance dev è sul socket, vedi App.swift). Il tema arriva da NSArgumentDomain,
# che ha precedenza sulle preferenze salvate ma non le scrive: le tue impostazioni restano quelle.
#
# Uso: scripts/screenshots.sh [tema]
#   tema: nome esatto dal catalogo (default "Tokyo Night").
#
# Richiede il permesso Screen Recording per il terminale da cui lo lanci. Occupa lo schermo per
# circa un minuto: ogni scatto è un avvio pulito della demo, così le tre immagini hanno la stessa
# finestra e lo stesso contenuto invece di essere tre momenti diversi di una sessione che cambia.
set -euo pipefail

cd "$(dirname "$0")/.."

THEME="${1:-Tokyo Night}"
OUT="docs/images"
RUNTIME="$(mktemp -d)"
mkdir -p "$OUT"

RELAY_PID=""
cleanup() {
  [[ -n "$RELAY_PID" ]] && kill "$RELAY_PID" 2>/dev/null || true
  rm -rf "$RUNTIME"
}
trap cleanup EXIT

echo "build…"
swift build

# shot <file> [--show overlay] — avvia la demo, aspetta che le sessioni si differenzino, cattura
# la sola finestra di Relay, chiude.
shot() {
  local name="$1"
  shift
  RELAY_SOCKET="$RUNTIME/relay.sock" RELAY_LAYOUT="$RUNTIME/layout.json" \
    ./.build/debug/relay --demo 5x3 -relay.theme.name "$THEME" "$@" &
  RELAY_PID=$!
  # Le sessioni simulate partono sfalsate (0.3-4s) e ciclano: dopo una decina di secondi la
  # sidebar mostra stati diversi, che è il punto degli screenshot.
  sleep 12
  local bounds
  bounds="$(swift scripts/window-bounds.swift relay)"
  /usr/sbin/screencapture -x -R "$bounds" "$OUT/$name.png"
  kill "$RELAY_PID" 2>/dev/null || true
  wait "$RELAY_PID" 2>/dev/null || true
  RELAY_PID=""
  echo "  $OUT/$name.png  ($bounds)"
  sleep 1
}

echo "scatti (tema: $THEME, runtime isolato in $RUNTIME)"
shot hero
shot dashboard --show dashboard
shot guide --show guide

echo "fatto. Rivedi le immagini prima di committarle."
