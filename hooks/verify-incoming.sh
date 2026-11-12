#!/usr/bin/env bash
# verify-incoming.sh — signature gate for commits a login or a sync is about to take.
#
#   bash ~/.agents/hooks/verify-incoming.sh <repo> <base> <tip>
#
# Walks the first-parent chain base..tip. A side branch is vouched for by the
# signed merge that brought it in. Each commit on that chain needs a good
# signature (%G? is G or U) whose primary-key fingerprint (%GP) is this
# machine's own signing key or a line in BRAIN_SIGNERS.
#
# Why a list and not "any good signature": the remote can be written by
# anything that holds a push credential. The signing key is a separate secret.
# GitHub's web-flow key signs every commit made on github.com, including one
# made through the API with a stolen token, so it is not accepted unless the
# owner lists it. A web commit is named and left for a manual pull.
#
# Exit 0  every mainline commit is signed by a listed key (prints nothing)
#      5  every refused commit is signed by GitHub web-flow
#      6  a refused commit is unsigned, unverifiable, or signed by an unlisted key
#      2  usage
# The reason is one line on stderr.
# BRAIN_SIGNERS_FILE and GITHUB_WEB_FLOW_FILE are for verify.sh only.
set -uo pipefail

[ $# -eq 3 ] || { echo "usage: verify-incoming.sh <repo> <base> <tip>" >&2; exit 2; }
REPO="$1"
BASE="$2"
TIP="$3"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SIGNERS="${BRAIN_SIGNERS_FILE:-$ROOT/BRAIN_SIGNERS}"
WEB_FLOW="${GITHUB_WEB_FLOW_FILE:-$ROOT/hooks/github-web-flow.asc}"

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

# Fingerprints this machine accepts. The file first, then the local signing key.
allowed=()
if [ -f "$SIGNERS" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [ -n "$line" ] && allowed+=("$(upper "$line")")
  done < "$SIGNERS"
fi
own_key="$(bash "$ROOT/hooks/gpg-signing-key.sh" 2>/dev/null || true)"
if [ -n "$own_key" ]; then
  own_fpr="$(gpg --batch --list-keys --with-colons "$own_key" 2>/dev/null \
    | awk -F: '$1 == "pub" { p = 1; next } p && $1 == "fpr" { print $10; exit }')"
  [ -n "$own_fpr" ] && allowed+=("$(upper "$own_fpr")")
fi

web=()
if [ -f "$WEB_FLOW" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && web+=("$(upper "$line")")
  done < <(gpg --batch --show-keys --with-colons "$WEB_FLOW" 2>/dev/null \
    | awk -F: '$1 == "pub" { p = 1; next } p && $1 == "fpr" { print $10; p = 0 }')
fi

in_list() {
  local want="$1" x
  shift
  for x in "$@"; do
    [ "$x" = "$want" ] && return 0
  done
  return 1
}

rows="$(git -C "$REPO" log --first-parent --format='%H%x09%G?%x09%GP' "$BASE..$TIP" 2>/dev/null)" || {
  echo "cannot read $BASE..$TIP in $REPO" >&2
  exit 6
}
[ -n "$rows" ] || exit 0

refused_web=0
refused_other=0
first_web=""
first_other=""
other() {
  refused_other=$((refused_other + 1))
  [ -n "$first_other" ] || first_other="$1"
}
while IFS=$'\t' read -r sha sig fpr; do
  [ -n "$sha" ] || continue
  fpr="$(upper "${fpr:-}")"
  short="${sha:0:7}"
  case "$sig" in
    G|U)
      if [ -n "$fpr" ] && in_list "$fpr" ${allowed[@]+"${allowed[@]}"}; then
        continue
      fi
      if [ -n "$fpr" ] && in_list "$fpr" ${web[@]+"${web[@]}"}; then
        refused_web=$((refused_web + 1))
        [ -n "$first_web" ] || first_web="$short was made on github.com (web-flow signature)"
      else
        other "$short is signed by a key that is not in BRAIN_SIGNERS (${fpr:-no fingerprint})"
      fi
      ;;
    N) other "$short is unsigned" ;;
    B) other "$short has a BAD signature" ;;
    E) other "$short has a signature this keyring cannot check" ;;
    *) other "$short has an expired or revoked signature (sig=$sig)" ;;
  esac
done <<<"$rows"

total=$((refused_web + refused_other))
[ "$total" -gt 0 ] || exit 0
if [ "${#allowed[@]}" -eq 0 ]; then
  echo "no signer is listed: BRAIN_SIGNERS is empty and this machine has no signing key" >&2
  exit 6
fi
more=""
[ "$total" -gt 1 ] && more=" (+$((total - 1)) more)"
if [ "$refused_other" -gt 0 ]; then
  echo "$first_other$more" >&2
  exit 6
fi
echo "$first_web$more" >&2
exit 5
