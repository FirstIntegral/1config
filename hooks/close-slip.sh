#!/usr/bin/env bash
# close-slip.sh — update rows on the boot close slip after the dashboard has exited.
#
# The dashboard still rewrites the whole file on exit. A later verify or setup
# only replaces the rows it actually re-checked, so the 1config panel (120s
# re-read) does not keep a boot failure that has already been fixed.
#
#   close-slip.sh clear LABEL [LABEL...]
#   close-slip.sh set warn|fail LABEL DETAIL...
#   close-slip.sh --selftest
#
# clear on a missing file does nothing (no dashboard exit yet — do not invent
# CLEAN). set creates the file. No rows left after clear writes CLEAN.
# BOOT_DASHBOARD_SLIP overrides the path. A label is the text between the
# two-space gaps: "fail  ecosystem  verify FAIL (7) — ...".
set -u

AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
dest="${BOOT_DASHBOARD_SLIP:-$AGENTS_HOME/boot-dashboard/close-slip.txt}"

label_of() {
  local rest="${1#*  }"
  printf '%s\n' "${rest%%  *}"
}

write_lines() {
  local tmp
  mkdir -p "$(dirname "$dest")" || return 1
  tmp="$(mktemp "${TMPDIR:-/tmp}/close-slip.XXXXXX")" || return 1
  if [ "$#" -eq 0 ]; then
    printf 'CLEAN\n' >"$tmp"
  else
    printf '%s\n' "$@" >"$tmp"
  fi
  mv -f "$tmp" "$dest"
}

# Print kept lines, one per record, dropping CLEAN and any label in the args.
# A missing file prints nothing and returns 2.
collect_kept() {
  local line lab drop want
  [ -f "$dest" ] || return 2
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    [ "$line" = "CLEAN" ] && continue
    lab="$(label_of "$line")"
    drop=0
    for want in "$@"; do
      [ "$lab" = "$want" ] && drop=1
    done
    [ "$drop" -eq 0 ] && printf '%s\n' "$line"
  done <"$dest"
  return 0
}

cmd="${1:-}"
if [ "$cmd" = "--selftest" ]; then
  dir="$(mktemp -d "${TMPDIR:-/tmp}/close-slip-test.XXXXXX")"
  trap 'rm -rf "$dir"' EXIT
  export BOOT_DASHBOARD_SLIP="$dir/close-slip.txt"
  fail=0
  bash "$0" clear ecosystem || fail=1
  [ ! -e "$BOOT_DASHBOARD_SLIP" ] || fail=1
  printf '%s\n' \
    'fail  ecosystem  verify FAIL (7) — bash ~/.agents/verify.sh' \
    'warn  omarchy dots  1 edited: hypr/bindings.lua — not applied' \
    >"$BOOT_DASHBOARD_SLIP"
  bash "$0" clear ecosystem || fail=1
  printf '%s\n' 'warn  omarchy dots  1 edited: hypr/bindings.lua — not applied' >"$dir/want"
  cmp -s "$dir/want" "$BOOT_DASHBOARD_SLIP" || fail=1
  bash "$0" clear 'omarchy dots' || fail=1
  printf 'CLEAN\n' >"$dir/want"
  cmp -s "$dir/want" "$BOOT_DASHBOARD_SLIP" || fail=1
  bash "$0" set fail ecosystem 'verify FAIL (2) — bash ~/.agents/verify.sh' || fail=1
  printf '%s\n' 'fail  ecosystem  verify FAIL (2) — bash ~/.agents/verify.sh' >"$dir/want"
  cmp -s "$dir/want" "$BOOT_DASHBOARD_SLIP" || fail=1
  bash "$0" set fail ecosystem 'verify FAIL (1) — bash ~/.agents/verify.sh' || fail=1
  printf '%s\n' 'fail  ecosystem  verify FAIL (1) — bash ~/.agents/verify.sh' >"$dir/want"
  cmp -s "$dir/want" "$BOOT_DASHBOARD_SLIP" || fail=1
  printf '%s\n' 'warn  brain sync  local ahead — unpushed commits' >>"$BOOT_DASHBOARD_SLIP"
  bash "$0" clear sync || fail=1
  grep -q 'brain sync' "$BOOT_DASHBOARD_SLIP" || fail=1
  if [ "$fail" -ne 0 ]; then
    echo "close-slip selftest failed" >&2
    exit 1
  fi
  exit 0
fi

case "$cmd" in
  clear)
    [ "$#" -ge 2 ] || { echo "usage: close-slip.sh clear LABEL..." >&2; exit 2; }
    shift
    # A missing slip means the dashboard has not exited. Do not invent CLEAN.
    [ -f "$dest" ] || exit 0
    kept=()
    mapfile -t kept < <(collect_kept "$@")
    if [ "${#kept[@]}" -eq 0 ]; then
      write_lines
    else
      write_lines "${kept[@]}"
    fi
    ;;
  set)
    [ "$#" -ge 4 ] || { echo "usage: close-slip.sh set warn|fail LABEL DETAIL..." >&2; exit 2; }
    status="$2"
    label="$3"
    shift 3
    detail="$*"
    case "$status" in
      warn|fail) ;;
      *) echo "close-slip.sh: status must be warn or fail" >&2; exit 2 ;;
    esac
    detail="${detail//$'\n'/ }"
    detail="${detail//$'\r'/ }"
    kept=()
    if [ -f "$dest" ]; then
      mapfile -t kept < <(collect_kept "$label")
    fi
    kept+=("$status  $label  $detail")
    write_lines "${kept[@]}"
    ;;
  *)
    echo "usage: close-slip.sh clear LABEL... | set warn|fail LABEL DETAIL... | --selftest" >&2
    exit 2
    ;;
esac
