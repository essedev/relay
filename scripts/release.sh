#!/usr/bin/env bash
# Routine di release di Relay: build dmg -> GitHub Release -> aggiorna il cask nel tap brew.
# Source of truth della versione: ./VERSION. Bump quel file, poi `make release`.
#
# Idempotente per versione: se il tag vX esiste gia, si ferma (bumpa VERSION prima).
# Firma: default self-signed stabile (scripts/setup-signing.sh). Per ad-hoc: SIGN_IDENTITY=- make release.
set -euo pipefail

REPO="essedev/relay"
TAP_REPO="essedev/homebrew-relay"
CASK_PATH="Casks/relay.rb"
GH_ACCOUNT="essedev"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(cat VERSION)"
TAG="v${VERSION}"
DMG=".build/Relay-${VERSION}.dmg"
SIGN_IDENTITY="${SIGN_IDENTITY:-Relay Self-Signed}"

info()  { printf '\033[36m==>\033[0m %s\n' "$1"; }
fail()  { printf '\033[31merrore:\033[0m %s\n' "$1" >&2; exit 1; }

# --- Preconditions ---------------------------------------------------------
command -v gh >/dev/null 2>&1 || fail "gh non trovato (brew install gh)"
[ -n "$VERSION" ] || fail "VERSION vuoto"

# Account GitHub giusto (ho due account; il repo vive su $GH_ACCOUNT).
current_account="$(gh api user --jq .login 2>/dev/null || true)"
if [ "$current_account" != "$GH_ACCOUNT" ]; then
  info "account gh attivo '$current_account' != '$GH_ACCOUNT', switch"
  gh auth switch --user "$GH_ACCOUNT" >/dev/null 2>&1 || fail "impossibile fare switch a $GH_ACCOUNT (gh auth login?)"
fi

# Branch main e working tree pulito: la release fotografa un commit preciso.
branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" = "main" ] || fail "non sei su main (sei su '$branch')"
git diff --quiet && git diff --cached --quiet || fail "working tree sporco: committa o stasha prima di rilasciare"

# Aggiorna version+sha256 del cask nel tap. Estratto in funzione: lo usa sia il flusso normale sia
# il recupero di una release gia pubblicata su GitHub ma con il tap rimasto indietro.
update_tap() {
  info "aggiorno il cask nel tap $TAP_REPO"
  local tmp cask
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  git clone --depth 1 "https://github.com/${TAP_REPO}.git" "$tmp/tap"
  cask="$tmp/tap/$CASK_PATH"
  [ -f "$cask" ] || fail "cask non trovato nel tap: $CASK_PATH (bootstrap del tap mancante?)"

  # version + sha256 sono le uniche righe che cambiano: l'URL le interpola.
  sed -i '' -E "s|^  version \".*\"|  version \"${VERSION}\"|" "$cask"
  sed -i '' -E "s|^  sha256 \".*\"|  sha256 \"${SHA}\"|" "$cask"
  # Verifica che i sed abbiano davvero scritto i valori attesi: un cambio di formato nel tap
  # (indentazione, stile brew) li renderebbe no-op, con un commit vuoto e il tap non aggiornato.
  grep -q "version \"${VERSION}\"" "$cask" && grep -q "sha256 \"${SHA}\"" "$cask" \
    || fail "cask non aggiornato: formato inatteso in $CASK_PATH"

  git -C "$tmp/tap" add "$CASK_PATH"
  git -C "$tmp/tap" commit -m "relay ${VERSION}" >/dev/null
  git -C "$tmp/tap" push >/dev/null
  info "tap aggiornato"
}

# Stato della pubblicazione GitHub per questa versione.
tag_exists=false; release_exists=false
git rev-parse "$TAG" >/dev/null 2>&1 && tag_exists=true
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 && release_exists=true

if $tag_exists && $release_exists; then
  # Gia pubblicata (es. un tap update fallito per rete la volta scorsa): recupero lo sha256
  # dall'asset reale e aggiorno solo il tap, senza ri-taggare ne ri-creare la release.
  info "release $TAG gia su GitHub: recupero lo sha e aggiorno solo il tap"
  dldir="$(mktemp -d)"; trap 'rm -rf "$dldir"' EXIT
  gh release download "$TAG" --repo "$REPO" --pattern '*.dmg' --dir "$dldir" --clobber \
    || fail "download dell'asset dmg della release $TAG fallito"
  SHA="$(shasum -a 256 "$dldir"/*.dmg | awk '{print $1}')"
  update_tap
  printf '\033[32m✓ tap allineato per Relay %s\033[0m\n' "$TAG"
  exit 0
elif $tag_exists || $release_exists; then
  fail "stato incoerente per $TAG (tag=$tag_exists, release=$release_exists): risolvi a mano"
fi

info "release $TAG (sign=$SIGN_IDENTITY)"

# --- Firma -----------------------------------------------------------------
# Firma non-adhoc: setup-signing.sh garantisce cert + keychain in search list + unlock + trust
# (idempotente). Se il trust manca esce non-zero con le istruzioni.
if [ "$SIGN_IDENTITY" != "-" ]; then
  bash "$ROOT/scripts/setup-signing.sh" \
    || fail "firma '$SIGN_IDENTITY' non pronta (vedi sopra), oppure rilascia ad-hoc: SIGN_IDENTITY=- make release"
fi

# --- Build dmg -------------------------------------------------------------
info "build dmg"
make dmg SIGN_IDENTITY="$SIGN_IDENTITY"
[ -f "$DMG" ] || fail "dmg non prodotto: $DMG"

SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
info "sha256 $SHA"

# --- Tag + GitHub Release --------------------------------------------------
# Push del branch prima del tag: la Release deve puntare a un commit gia su origin.
info "push $branch"
git push origin "$branch"
info "tag $TAG e push"
git tag -a "$TAG" -m "Relay $TAG"
git push origin "$TAG"

info "creo la GitHub Release e carico il dmg"
# Note dai conventional commit tra il tag precedente e questo (il repo e trunk-based: niente PR,
# quindi --generate-notes darebbe un body vuoto col solo link di compare).
NOTES="$(mktemp)"; trap 'rm -f "$NOTES"' EXIT
bash "$ROOT/scripts/release-notes.sh" "$TAG" > "$NOTES"
gh release create "$TAG" "$DMG" \
  --repo "$REPO" \
  --title "Relay $TAG" \
  --notes-file "$NOTES"

# --- Aggiorna il cask nel tap ---------------------------------------------
update_tap

printf '\033[32m✓ rilasciata Relay %s\033[0m\n' "$TAG"
echo "  installa:  brew install --cask ${GH_ACCOUNT}/relay/relay"
echo "  aggiorna:  brew update && brew upgrade --cask relay"
