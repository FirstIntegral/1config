#!/usr/bin/env bash
# Resolve the GPG signing key id for this machine.
# Order: $GPG_SIGNING_KEY → git config --global user.signingkey
# Never default to another machine's key id.
# Usage: KEY="$(bash ~/.agents/hooks/gpg-signing-key.sh)" || exit $?
set -u
if [ -n "${GPG_SIGNING_KEY:-}" ]; then
  k="$GPG_SIGNING_KEY"
else
  k="$(git config --global --get user.signingkey 2>/dev/null || true)"
fi
k="${k#0x}"
k="${k#0X}"
k="${k##*/}"
if [ -z "$k" ]; then
  echo "no GPG signing key — set git config --global user.signingkey, or GPG_SIGNING_KEY" >&2
  exit 3
fi
printf '%s\n' "$k"
