#!/usr/bin/env bash
# Genera le note di una release dai conventional commit tra due ref.
# Uso: release-notes.sh <to-ref> [from-ref]
#
# from-ref opzionale: se assente usa il tag precedente (git describe). Se non esiste tag
# precedente (prima release) elenca tutta la storia fino a <to-ref> e omette il link di compare.
# Output su stdout in markdown. Raggruppa per tipo (Features/Fixes/Performance/Other), scarta i
# commit di release (chore(release)). Parsing in bash puro (no gawk: BSD awk su macOS non ha
# match(...,array)).
set -euo pipefail

REPO="${RELEASE_NOTES_REPO:-essedev/relay}"

TO="${1:?uso: release-notes.sh <to-ref> [from-ref]}"
FROM="${2:-}"

if [ -z "$FROM" ]; then
  FROM="$(git describe --tags --abbrev=0 "${TO}^" 2>/dev/null || true)"
fi

if [ -n "$FROM" ]; then
  RANGE="${FROM}..${TO}"
else
  RANGE="$TO"
fi

feat=(); fixes=(); perf=(); other=()

while IFS= read -r subject; do
  [ -n "$subject" ] || continue
  if [[ "$subject" =~ ^([a-z]+)(\(([^\)]*)\))?(!)?:[[:space:]]+(.*)$ ]]; then
    type="${BASH_REMATCH[1]}"
    scope="${BASH_REMATCH[3]}"
    bang="${BASH_REMATCH[4]}"
    desc="${BASH_REMATCH[5]}"
    # I commit di release sono rumore in un changelog utente.
    { [ "$type" = "chore" ] && [ "$scope" = "release" ]; } && continue
    if [ -n "$scope" ]; then line="- **$scope**: "; else line="- "; fi
    [ "$bang" = "!" ] && line="${line}**Breaking:** "
    line="${line}${desc}"
    case "$type" in
      feat) feat+=("$line") ;;
      fix)  fixes+=("$line") ;;
      perf) perf+=("$line") ;;
      *)    other+=("$line") ;;
    esac
  else
    # Subject non conventional: lo tengo grezzo in Other, non lo perdo.
    other+=("- $subject")
  fi
done < <(git log --no-merges --format='%s' "$RANGE")

out=""
emit_section() {
  local title="$1"; shift
  [ "$#" -eq 0 ] && return
  [ -n "$out" ] && out+=$'\n'
  out+="### $title"$'\n'
  local it
  for it in "$@"; do out+="$it"$'\n'; done
}

# `${arr[@]+"${arr[@]}"}` = espansione safe di array possibilmente vuoto sotto `set -u`.
emit_section "Features"    ${feat[@]+"${feat[@]}"}
emit_section "Fixes"       ${fixes[@]+"${fixes[@]}"}
emit_section "Performance" ${perf[@]+"${perf[@]}"}
emit_section "Other"       ${other[@]+"${other[@]}"}

if [ -n "$FROM" ]; then
  [ -n "$out" ] && out+=$'\n'
  out+="**Full Changelog**: https://github.com/${REPO}/compare/${FROM}...${TO}"$'\n'
fi

[ -n "$out" ] || out="_Initial release._"$'\n'

printf '%s' "$out"
