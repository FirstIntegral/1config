#!/usr/bin/env bash
# gpg-store-passphrase.sh — one-time: store the GPG signing passphrase into a
# dedicated gnome-keyring collection labelled `gpg-signing` (empty master,
# autologin-safe). Not the default collection — other apps writing multiline
# secrets brick unencrypted default keyrings across reboot.
#
#   bash ~/.agents/hooks/gpg-store-passphrase.sh
#
# Re-run after changing the passphrase. Then verify-unlocks via
# gpg-agent-unlock.sh (all future commits sign silently; agent caches 1 year).
set -u

KEY="${GPG_SIGNING_KEY:-95FBA6E0AA245342}"
PY="${AGENTS_HOME:-$HOME/.agents}/hooks/gpg-keyring.py"

printf 'Enter passphrase for GPG key %s (dedicated gpg-signing collection): ' "$KEY"
IFS= read -rs pass || { echo; exit 1; }
echo

if [ -z "$pass" ]; then
  echo "empty passphrase — abort" >&2
  exit 1
fi

if ! printf '%s' "$pass" | AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}" GPG_SIGNING_KEY="$KEY" python3 "$PY" store; then
  unset pass
  echo "store failed — is gnome-keyring running?" >&2
  exit 1
fi
unset pass
echo "stored in dedicated gpg-signing collection"

# The 1-year TTL only applies to agents started AFTER the conf exists; a
# pre-existing agent keeps its defaults (2h max) and would prompt on expiry.
# Ensure the conf, then reload the agent; the unlock below re-seeds the cache.
CONF="$HOME/.gnupg/gpg-agent.conf"
mkdir -p "$HOME/.gnupg"
for line in "allow-loopback-pinentry" \
            "default-cache-ttl 31536000" "max-cache-ttl 31536000" \
            "default-cache-ttl-ssh 31536000" "max-cache-ttl-ssh 31536000"; do
  grep -qF "$line" "$CONF" 2>/dev/null || echo "$line" >> "$CONF"
done
gpgconf --kill gpg-agent 2>/dev/null || true

if bash "$HOME/.agents/hooks/gpg-agent-unlock.sh"; then
  echo "signing key unlocked — commits will sign silently"
else
  echo "unlock test failed — check keyring / passphrase" >&2
  exit 1
fi
