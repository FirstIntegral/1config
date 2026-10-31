#!/usr/bin/env bash
# orx-install.sh — pinned, checksum-verified OpenResearch CLI (orx), telemetry off.
#
#   bash ~/.agents/skills/research-loop/orx-install.sh            # install the pin
#   bash ~/.agents/skills/research-loop/orx-install.sh check      # verify only
#   bash ~/.agents/skills/research-loop/orx-install.sh pin-info v0.2.24
#   bash ~/.agents/skills/research-loop/orx-install.sh --version v0.2.24 --sha256 <hex>
#
# Never curl | sh, no AppImage, no root, no shell-rc edits. setup.sh never calls
# this. It fetches the static musl CLI tarball from the GitHub release, refuses
# unless its sha256 equals the pin below, and installs:
#   $PREFIX/lib/openresearch-cli/<version>/orx   the real binary (no install
#                                                receipt, so it never self-updates)
#   $PREFIX/bin/orx                              a wrapper that exports
#                                                ORX_TELEMETRY_ENV=off and the
#                                                no-update-check variables
# It then persists `telemetry off` with ORX_TELEMETRY_ENV=off set, so the opt-out
# sends no consent event, and runs `check`.
#
# Exit: 0 ok · 1 download, checksum, or check failed · 64 usage
set -euo pipefail

PIN_VERSION="v0.2.23"
PIN_SHA256_X86_64="790e8bcbd531a1019e67d3299af572fa2af813fe9f255b859888e84c994a6000"
PIN_SHA256_AARCH64="1bae8a36f434097f9291475eb843c4a9be04feaaf4168e0e1fcfbb60fef36e08"

REPO="alphaXiv/OpenResearch"
RELEASE_BASE="${ORX_RELEASE_BASE:-https://github.com/$REPO/releases/download}"
PREFIX="${ORX_PREFIX:-$HOME/.local}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/openresearch"
MARK="# managed by 1config skills/research-loop/orx-install.sh"

log() { echo "orx-install: $*"; }
die() { echo "orx-install: ERROR: $*" >&2; exit 1; }
usage() { sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }

target_triple() {
  case "$(uname -m)" in
    x86_64) echo x86_64-unknown-linux-musl ;;
    aarch64 | arm64) echo aarch64-unknown-linux-musl ;;
    *) die "unsupported arch $(uname -m)" ;;
  esac
}

pinned_sha() {
  case "$1" in
    x86_64-unknown-linux-musl) echo "$PIN_SHA256_X86_64" ;;
    aarch64-unknown-linux-musl) echo "$PIN_SHA256_AARCH64" ;;
  esac
}

# check: wrapper present, wrapper forces telemetry and update checks off, and
# the opt-out is persisted in settings.json. Reads files only; the one binary
# call goes through the wrapper, so it runs with telemetry disabled by env.
check() {
  local wrapper="$PREFIX/bin/orx" bad=0 real status
  if [ ! -f "$wrapper" ]; then
    echo "  FAIL  no $wrapper"
    return 1
  fi
  if ! grep -qF "$MARK" "$wrapper"; then
    echo "  FAIL  $wrapper is not the 1config wrapper (curl installer or AppImage?)"
    return 1
  fi
  for line in "export ORX_TELEMETRY_ENV=off" "export ORX_NO_UPDATE_CHECK=1" \
    "export OPENRESEARCH_CLI_DISABLE_UPDATE=1" "export NO_UPDATE_NOTIFIER=1"; do
    if grep -qxF "$line" "$wrapper"; then echo "  ok    wrapper: $line"; else
      echo "  FAIL  wrapper missing: $line"; bad=1; fi
  done
  real="$(sed -n 's/^exec "\(.*\)" "\$@"$/\1/p' "$wrapper")"
  if [ -n "$real" ] && [ -x "$real" ]; then echo "  ok    binary $real"; else
    echo "  FAIL  wrapper points at a missing binary: ${real:-?}"; bad=1; fi
  if [ -f "$CONFIG_DIR/settings.json" ] &&
    tr -d ' \n\t' <"$CONFIG_DIR/settings.json" | grep -q '"telemetryDisabled":true'; then
    echo "  ok    $CONFIG_DIR/settings.json telemetryDisabled=true"
  else
    echo "  FAIL  telemetry opt-out not persisted in $CONFIG_DIR/settings.json"; bad=1
  fi
  if [ "$bad" = 0 ]; then
    status="$("$wrapper" telemetry status 2>&1 | head -1 || true)"
    case "$status" in
      *"analytics: off"*) echo "  ok    orx telemetry status: $status" ;;
      *) echo "  FAIL  orx telemetry status: ${status:-no output}"; bad=1 ;;
    esac
  fi
  command -v orx >/dev/null 2>&1 && [ "$(command -v orx)" != "$wrapper" ] &&
    echo "  WARN  first orx on PATH is $(command -v orx), not $wrapper"
  [ "$bad" = 0 ]
}

# pin-info: print a release's sha256 from the .sha256 sidecar and from
# GitHub's server-side asset digest. Use both, matching, to bump the pin.
pin_info() {
  local version="$1" triple asset side api
  triple="$(target_triple)"
  asset="openresearch-cli-$triple.tar.xz"
  side="$(curl -fsSL "$RELEASE_BASE/$version/$asset.sha256" | awk '{print $1}')"
  command -v jq >/dev/null || die "jq required for pin-info"
  api="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/tags/$version" |
    jq -r --arg n "$asset" '.assets[] | select(.name == $n) | .digest' | sed 's/^sha256://')"
  echo "sidecar  $side"
  echo "github   $api"
  [ -n "$side" ] && [ "$side" = "$api" ] || die "sidecar and GitHub digest disagree"
  echo "pin: --version $version --sha256 $side"
}

version="$PIN_VERSION" sha="" mode=install
while [ $# -gt 0 ]; do
  case "$1" in
    check) mode=check ;;
    pin-info) mode=pin-info; [ $# -ge 2 ] || usage; version="$2"; shift ;;
    --version) [ $# -ge 2 ] || usage; version="$2"; shift ;;
    --sha256) [ $# -ge 2 ] || usage; sha="$2"; shift ;;
    --prefix) [ $# -ge 2 ] || usage; PREFIX="$2"; shift ;;
    -h | --help) usage ;;
    *) echo "orx-install: unknown argument $1" >&2; usage ;;
  esac
  shift
done

case "$mode" in
  check) log "check $PREFIX/bin/orx"; check && { log ok; exit 0; }; die "check failed" ;;
  pin-info) pin_info "$version"; exit 0 ;;
esac

case "$version" in v[0-9]*.[0-9]*.[0-9]*) ;; *) die "bad version $version" ;; esac
triple="$(target_triple)"
if [ -z "$sha" ]; then
  [ "$version" = "$PIN_VERSION" ] || die "refusing unpinned $version: pass --sha256 (see pin-info)"
  sha="$(pinned_sha "$triple")"
fi
[[ "$sha" =~ ^[0-9a-f]{64}$ ]] || die "bad sha256 $sha"
command -v curl >/dev/null || die "curl required"
command -v tar >/dev/null || die "tar required"
command -v sha256sum >/dev/null || die "sha256sum required"

asset="openresearch-cli-$triple.tar.xz"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
log "downloading $RELEASE_BASE/$version/$asset"
curl -fsSL "$RELEASE_BASE/$version/$asset" -o "$tmp/$asset"
got="$(sha256sum "$tmp/$asset" | awk '{print $1}')"
[ "$got" = "$sha" ] || die "sha256 mismatch for $asset: got $got want $sha (nothing installed)"
log "sha256 ok $got"

tar -xJf "$tmp/$asset" -C "$tmp"
bin="$tmp/openresearch-cli-$triple/orx"
[ -f "$bin" ] || die "orx missing from tarball"

wrapper="$PREFIX/bin/orx"
if [ -e "$wrapper" ] && ! grep -qF "$MARK" "$wrapper" 2>/dev/null; then
  die "$wrapper exists and is not the 1config wrapper; move it aside first"
fi
libdir="$PREFIX/lib/openresearch-cli/$version"
mkdir -p "$libdir" "$PREFIX/bin"
install -m 0755 "$bin" "$libdir/orx"
cp "$tmp/openresearch-cli-$triple/LICENSE" "$libdir/LICENSE" 2>/dev/null || true
echo "$sha  $asset" >"$libdir/SHA256"
cat >"$wrapper.tmp" <<WRAP
#!/bin/sh
$MARK
# OpenResearch $version, tarball sha256 $sha
export ORX_TELEMETRY_ENV=off
export ORX_NO_UPDATE_CHECK=1
export OPENRESEARCH_CLI_DISABLE_UPDATE=1
export NO_UPDATE_NOTIFIER=1
exec "$libdir/orx" "\$@"
WRAP
chmod 0755 "$wrapper.tmp"
mv -f "$wrapper.tmp" "$wrapper"
log "installed $libdir/orx and wrapper $wrapper"

# Persist the opt-out. ORX_TELEMETRY_ENV=off (from the wrapper) stops the
# consent event that `orx telemetry off` otherwise sends.
"$wrapper" --no-telemetry telemetry off >/dev/null
check || die "check failed after install"
case ":$PATH:" in *":$PREFIX/bin:"*) ;; *) log "note: $PREFIX/bin is not on PATH" ;; esac
log ok
