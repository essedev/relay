#!/usr/bin/env bash
# Riscrive il body di TUTTE le GitHub Release esistenti con le note generate dai conventional
# commit (stesso template di release.sh via release-notes.sh). Non tocca tag, asset (.dmg) ne il
# cask brew: solo `gh release edit --notes`, reversibile.
#
# Uso: backfill-release-notes.sh [--dry-run]
#   --dry-run: stampa le note che scriverebbe, non edita nulla.
set -euo pipefail

REPO="essedev/relay"
GH_ACCOUNT="essedev"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

command -v gh >/dev/null 2>&1 || { echo "gh non trovato" >&2; exit 1; }

current_account="$(gh api user --jq .login 2>/dev/null || true)"
if [ "$current_account" != "$GH_ACCOUNT" ]; then
  echo "==> switch account gh a $GH_ACCOUNT" >&2
  gh auth switch --user "$GH_ACCOUNT" >/dev/null 2>&1 || { echo "switch a $GH_ACCOUNT fallito" >&2; exit 1; }
fi

# Tag v* in ordine di versione crescente: cosi ogni tag ha il precedente gia noto a git describe.
tags="$(git tag --list 'v*' --sort=version:refname)"
[ -n "$tags" ] || { echo "nessun tag v* trovato" >&2; exit 1; }

while IFS= read -r tag; do
  [ -n "$tag" ] || continue
  # Solo i tag che hanno una release pubblicata.
  if ! gh release view "$tag" --repo "$REPO" >/dev/null 2>&1; then
    echo "-- $tag: nessuna release, salto" >&2
    continue
  fi
  notes="$(bash "$ROOT/scripts/release-notes.sh" "$tag")"
  if $DRY_RUN; then
    printf '\n===== %s =====\n%s\n' "$tag" "$notes"
  else
    printf '%s' "$notes" | gh release edit "$tag" --repo "$REPO" --notes-file - \
      && echo "✓ $tag aggiornata" >&2
  fi
done <<< "$tags"

$DRY_RUN && echo "(dry-run: niente scritto)" >&2 || true
