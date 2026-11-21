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
# Before the walk, a BRAIN_SIGNERS.asc in <tip> is imported when every key in it
# is already a listed signer (see import_tip_keys below).
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
# "This machine's own key" is a key it holds the secret half of. The lookup goes
# through the secret keyring: user.signingkey may be an email or a short id, and
# any public key that was ever imported can carry the same email.
own_key="$(bash "$ROOT/hooks/gpg-signing-key.sh" 2>/dev/null || true)"
if [ -n "$own_key" ]; then
  while IFS= read -r own_fpr; do
    [ -n "$own_fpr" ] && allowed+=("$(upper "$own_fpr")")
  done < <(gpg --batch --list-secret-keys --with-colons "$own_key" 2>/dev/null \
    | awk -F: '$1 == "sec" { p = 1; next } p && $1 == "fpr" { print $10; p = 0 }')
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

# The signers' public keys travel in the repository as BRAIN_SIGNERS.asc. A
# machine has to hold a signer's new subkey before it can check a commit that
# subkey signed, and the commit that ships the file may be signed by that very
# subkey. So the file is read from the commit being checked, before the check.
# It is imported only when every key in it is already on the list above.
# An import gives no trust: the list decides who may sign, and gpg takes a
# subkey only with a binding that the listed primary key signed.
import_tip_keys() {
  local tmp f
  git -C "$REPO" cat-file -e "$TIP:BRAIN_SIGNERS.asc" 2>/dev/null || return 0
  [ "$(git -C "$REPO" cat-file -s "$TIP:BRAIN_SIGNERS.asc" 2>/dev/null || echo 0)" -le 262144 ] || return 0
  tmp="$(mktemp)" || return 0
  if git -C "$REPO" show "$TIP:BRAIN_SIGNERS.asc" > "$tmp" 2>/dev/null; then
    local -a found=()
    while IFS= read -r f; do
      [ -n "$f" ] && found+=("$(upper "$f")")
    done < <(gpg --batch --show-keys --with-colons "$tmp" 2>/dev/null \
      | awk -F: '$1 == "pub" { p = 1; next } p && $1 == "fpr" { print $10; p = 0 }')
    local ok=0
    [ "${#found[@]}" -gt 0 ] && ok=1
    for f in ${found[@]+"${found[@]}"}; do
      in_list "$f" ${allowed[@]+"${allowed[@]}"} || ok=0
    done
    [ "$ok" = 1 ] && gpg --batch --import "$tmp" >/dev/null 2>&1
  fi
  rm -f "$tmp"
  return 0
}
import_tip_keys

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
