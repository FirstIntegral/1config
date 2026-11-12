#!/usr/bin/env bash
# install-elan.sh — official elan (Lean 4 version manager), pinned and checksum-verified.
#
#   bash ~/.agents/hooks/install-elan.sh                              # install the pin
#   bash ~/.agents/hooks/install-elan.sh pin-info v4.2.5              # sums for a bump
#   bash ~/.agents/hooks/install-elan.sh --version v4.2.5 --sha256 <hex>
#
# Idempotent. No root. Does not edit .bashrc / .profile.
# Downloads one release tarball by exact version, refuses unless its sha256
# equals the pin below, then runs the installer binary. Never curl | sh, never
# `releases/latest`: the binary that runs is the one that was reviewed.
# setup.sh never calls this (probe only, like TeX).
#
# Bump: run pin-info, check that the local sum and GitHub's digest agree, then
# change PIN_VERSION and both sums in one commit.
#
# Exit: 0 installed-or-already-present · 1 download, checksum, or install failed · 64 usage
set -euo pipefail

PIN_VERSION="v4.2.4"
PIN_SHA256_X86_64="42b94d4244e8353142c456ec0e4ca6528fd898a6c604d4059f494e706e431f63"
PIN_SHA256_AARCH64="05febd124d84ebf994b2e7479922a5650b1e950c17ae3bd1ddd776b65bb72bf9"

REPO="leanprover/elan"
RELEASE_BASE="${ELAN_RELEASE_BASE:-https://github.com/$REPO/releases/download}"
AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
ELAN_HOME="${ELAN_HOME:-$HOME/.elan}"
ELAN_BIN="$ELAN_HOME/bin/elan"
PIN_FILE="$AGENTS_HOME/paper-template/lean/lean-toolchain"

log() { echo "install-elan: $*"; }
die() { echo "install-elan: ERROR: $*" >&2; exit 1; }
usage() { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }

target_triple() {
  case "$(uname -m)" in
    x86_64)        echo x86_64-unknown-linux-gnu ;;
    aarch64|arm64) echo aarch64-unknown-linux-gnu ;;
    *) die "unsupported arch $(uname -m)" ;;
  esac
}

pinned_sha() {
  case "$1" in
    x86_64-unknown-linux-gnu)  echo "$PIN_SHA256_X86_64" ;;
    aarch64-unknown-linux-gnu) echo "$PIN_SHA256_AARCH64" ;;
  esac
}

# pin-info: what a bump needs. The local sum of each tarball, and the digest
# GitHub computed server-side for the same asset. They must agree.
pin_info() {
  local version="$1" triple tmp sum
  command -v curl >/dev/null || die "curl required"
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT
  for triple in x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu; do
    curl -sSfL "$RELEASE_BASE/$version/elan-$triple.tar.gz" -o "$tmp/$triple.tar.gz" \
      || die "download failed for $version $triple"
    sum="$(sha256sum "$tmp/$triple.tar.gz" | awk '{print $1}')"
    echo "$triple  local  $sum"
  done
  curl -sSfL "https://api.github.com/repos/$REPO/releases/tags/$version" 2>/dev/null \
    | python3 -c '
import json, sys
for a in json.load(sys.stdin).get("assets", []):
    if a.get("name", "").endswith("-unknown-linux-gnu.tar.gz"):
        print(a["name"][5:-7], " github", (a.get("digest") or "none").replace("sha256:", ""))
' || echo "(GitHub digest not available — compare against the release page by hand)"
}

version="$PIN_VERSION"
sha_override=""
while [ $# -gt 0 ]; do
  case "$1" in
    pin-info)  [ $# -ge 2 ] || usage; pin_info "$2"; exit 0 ;;
    --version) [ $# -ge 2 ] || usage; version="$2"; shift 2 ;;
    --sha256)  [ $# -ge 2 ] || usage; sha_override="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done
if [ "$version" != "$PIN_VERSION" ] && [ -z "$sha_override" ]; then
  die "--version $version needs --sha256 (only $PIN_VERSION has a pinned sum)"
fi

export PATH="$ELAN_HOME/bin:${PATH:-}"

if [ -x "$ELAN_BIN" ] || command -v elan >/dev/null 2>&1; then
  log "elan already present ($(command -v elan 2>/dev/null || echo "$ELAN_BIN"))"
else
  command -v curl >/dev/null || die "curl required to fetch elan"
  command -v tar >/dev/null || die "tar required to unpack elan"
  command -v sha256sum >/dev/null || die "sha256sum required to check elan"

  triple="$(target_triple)"
  want="${sha_override:-$(pinned_sha "$triple")}"
  [ -n "$want" ] || die "no pinned sha256 for $triple"

  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT
  url="$RELEASE_BASE/$version/elan-$triple.tar.gz"
  log "downloading $url"
  curl -sSfL "$url" -o "$tmp/elan.tar.gz" || die "download failed: $url"
  got="$(sha256sum "$tmp/elan.tar.gz" | awk '{print $1}')"
  if [ "$got" != "$want" ]; then
    die "sha256 mismatch for $version $triple — got $got, pinned $want. Nothing was run."
  fi
  log "sha256 ok ($version $triple)"
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
