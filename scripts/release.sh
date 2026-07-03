#!/usr/bin/env bash
# Routine di release di Relay: build dmg -> GitHub Release -> aggiorna il cask nel tap brew.
# Source of truth della versione: ./VERSION. Bump quel file, poi `make release`.
#
# Idempotente per versione: se il tag vX esiste gia, si ferma (bumpa VERSION prima).
# Env: SIGN_IDENTITY (default '-' ad-hoc), passato al bundle.
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
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

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

# Tag gia esistente => versione gia rilasciata.
if git rev-parse "$TAG" >/dev/null 2>&1; then
  fail "il tag $TAG esiste gia. Bumpa ./VERSION prima di rilasciare."
fi
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  fail "la release $TAG esiste gia su $REPO. Bumpa ./VERSION."
fi

info "release $TAG (sign=$SIGN_IDENTITY)"

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
gh release create "$TAG" "$DMG" \
  --repo "$REPO" \
  --title "Relay $TAG" \
  --generate-notes

# --- Aggiorna il cask nel tap ---------------------------------------------
info "aggiorno il cask nel tap $TAP_REPO"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone --depth 1 "https://github.com/${TAP_REPO}.git" "$tmp/tap"
cask="$tmp/tap/$CASK_PATH"
[ -f "$cask" ] || fail "cask non trovato nel tap: $CASK_PATH (bootstrap del tap mancante?)"

# version + sha256 sono le uniche righe che cambiano: l'URL le interpola.
sed -i '' -E "s|^  version \".*\"|  version \"${VERSION}\"|" "$cask"
sed -i '' -E "s|^  sha256 \".*\"|  sha256 \"${SHA}\"|" "$cask"

git -C "$tmp/tap" add "$CASK_PATH"
git -C "$tmp/tap" commit -m "relay ${VERSION}" >/dev/null
git -C "$tmp/tap" push >/dev/null
info "tap aggiornato"

printf '\033[32m✓ rilasciata Relay %s\033[0m\n' "$TAG"
echo "  installa:  brew install --cask ${GH_ACCOUNT}/relay/relay"
echo "  aggiorna:  brew update && brew upgrade --cask relay"
