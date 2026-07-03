#!/usr/bin/env bash
# Setup della firma self-signed di Relay (identita stabile tra le build: notifiche che non
# decadono e niente "Apri comunque" ricorrente sugli upgrade). Idempotente.
#
# Crea un keychain DEDICATO in ~/.relay/codesign (non tocca il tuo login keychain) con dentro
# un certificato di code signing self-signed. macOS pero richiede che il certificato sia
# "trusted" per poterci firmare, e impostare il trust vuole la password admin: quello e' l'unico
# passo non automatizzabile (sudo). Lo script lo tenta in non-interactive; se serve, stampa il
# comando esatto da lanciare a mano una volta.
set -euo pipefail

DIR="$HOME/.relay/codesign"
KC="$DIR/relay-codesign.keychain-db"
CERT="$DIR/relay-selfsigned.cer"
PWFILE="$DIR/keychain.pw"
IDENTITY="Relay Self-Signed"
SYSKC="/Library/Keychains/System.keychain"

mkdir -p "$DIR" && chmod 700 "$DIR"

# --- 1. keychain + certificato (headless, idempotente) --------------------
if [ ! -f "$KC" ] || ! security find-certificate -c "$IDENTITY" "$KC" >/dev/null 2>&1; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  cat > "$tmp/cfg" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
  openssl req -x509 -newkey rsa:2048 -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
    -days 3650 -nodes -config "$tmp/cfg" 2>/dev/null
  cp "$tmp/cert.pem" "$CERT"
  p12pass="$(openssl rand -hex 12)"
  openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/cert.p12" \
    -name "$IDENTITY" -passout pass:"$p12pass" 2>/dev/null
  kcpass="$(openssl rand -hex 16)"
  rm -f "$KC"
  security create-keychain -p "$kcpass" "$KC"
  security set-keychain-settings "$KC"                 # niente lock su timeout
  security unlock-keychain -p "$kcpass" "$KC"
  security import "$tmp/cert.p12" -k "$KC" -P "$p12pass" -T /usr/bin/codesign
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$kcpass" "$KC" >/dev/null
  ( umask 077; printf '%s' "$kcpass" > "$PWFILE" )
  chmod 600 "$PWFILE"
  echo "creati keychain e certificato in $DIR"
else
  echo "keychain e certificato gia presenti in $DIR"
  security unlock-keychain -p "$(cat "$PWFILE")" "$KC"
fi

# --- 1b. search list -------------------------------------------------------
# codesign risolve l'identita dalla search list dei keychain (il flag --keychain non basta):
# aggiungo quello dedicato preservando gli esistenti (idempotente).
if ! security list-keychains -d user | grep -q "$KC"; then
  paths="$(security list-keychains -d user | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//')"
  security list-keychains -d user -s $paths "$KC"
  echo "keychain aggiunto alla search list"
fi

# --- 2. trust (richiede sudo, una tantum) ---------------------------------
if security find-identity -v -p codesigning "$KC" | grep -q "$IDENTITY"; then
  echo "OK: '$IDENTITY' e valido per code signing. Firma pronta."
  exit 0
fi

echo "manca il trust del certificato (macOS lo richiede per firmare)."
if sudo -n security add-trusted-cert -d -r trustRoot -p codeSign -k "$SYSKC" "$CERT" 2>/dev/null; then
  echo "trust aggiunto."
else
  cat <<MSG

  Serve UN comando con la tua password admin (una tantum). Lancialo tu:

    sudo security add-trusted-cert -d -r trustRoot -p codeSign -k "$SYSKC" "$CERT"

  Poi rilancia:  bash scripts/setup-signing.sh
  (per rimuovere in futuro: sudo security remove-trusted-cert -d "$CERT")
MSG
  exit 2
fi

if security find-identity -v -p codesigning "$KC" | grep -q "$IDENTITY"; then
  echo "OK: '$IDENTITY' e valido per code signing. Firma pronta."
else
  echo "trust aggiunto ma l'identita non risulta ancora valida; riprova o verifica manualmente." >&2
  exit 3
fi
