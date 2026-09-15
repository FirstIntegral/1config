#!/usr/bin/env bash
# install-elan.sh — official elan (Lean 4 version manager).
#
#   bash ~/.agents/hooks/install-elan.sh
#
# Idempotent. No root. Does not edit .bashrc / .profile.
# Downloads the GitHub release tarball, then runs the installer binary —
# never curl | sh. setup.sh never calls this (probe only, like TeX).
#
# Exit: 0 installed-or-already-present · 1 download/install failed
set -euo pipefail

AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
ELAN_HOME="${ELAN_HOME:-$HOME/.elan}"
ELAN_BIN="$ELAN_HOME/bin/elan"
PIN_FILE="$AGENTS_HOME/paper-template/lean/lean-toolchain"

log() { echo "install-elan: $*"; }
die() { echo "install-elan: ERROR: $*" >&2; exit 1; }

export PATH="$ELAN_HOME/bin:${PATH:-}"

if [ -x "$ELAN_BIN" ] || command -v elan >/dev/null 2>&1; then
  log "elan already present ($(command -v elan 2>/dev/null || echo "$ELAN_BIN"))"
else
  command -v curl >/dev/null || die "curl required to fetch elan"
  command -v tar >/dev/null || die "tar required to unpack elan"

  case "$(uname -m)" in
    x86_64)        arch=x86_64-unknown-linux-gnu ;;
    aarch64|arm64) arch=aarch64-unknown-linux-gnu ;;
    *) die "unsupported arch $(uname -m)" ;;
  esac

  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap 'rm -rf "$tmp"' EXIT
  url="https://github.com/leanprover/elan/releases/latest/download/elan-${arch}.tar.gz"
  log "downloading $url"
  curl -sSfL "$url" -o "$tmp/elan.tar.gz"
  tar -xzf "$tmp/elan.tar.gz" -C "$tmp"
  init=""
  for cand in "$tmp/elan-init" "$tmp/elan"; do
    if [ -f "$cand" ]; then
      init="$cand"
      break
    fi
  done
  [ -n "$init" ] || die "elan-init binary missing from tarball"
  chmod +x "$init"

  # Do not let the installer rewrite shell rc (1config does not own those files).
  export ELAN_NO_MODIFY_PATH=1
  export RUSTUP_NO_MODIFY_PATH=1
  if "$init" --help 2>&1 | grep -q -- '--no-modify-path'; then
    "$init" -y --default-toolchain none --no-modify-path
  else
    "$init" -y --default-toolchain none
  fi
  [ -x "$ELAN_BIN" ] || die "elan missing after install ($ELAN_BIN)"
  log "installed $ELAN_BIN"
fi

if [ ! -x "$ELAN_BIN" ]; then
  if command -v elan >/dev/null 2>&1; then
    ELAN_BIN="$(command -v elan)"
  else
    die "elan missing"
  fi
fi

if [ -f "$PIN_FILE" ]; then
  pin="$(tr -d '[:space:]' < "$PIN_FILE")"
  case "$pin" in
    leanprover/lean4:v[0-9]*.[0-9]*.[0-9]*)
      log "installing toolchain $pin"
      "$ELAN_BIN" toolchain install "$pin"
      ;;
    *)
      die "refusing unpinned toolchain in $PIN_FILE: $pin"
      ;;
  esac
else
  log "no $PIN_FILE — elan installed, no toolchain pin"
fi

log "ok"
