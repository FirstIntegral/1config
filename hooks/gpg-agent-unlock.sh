#!/usr/bin/env bash
# gpg-agent-unlock.sh — auto-unlock the GPG signing key from the GNOME keyring.
#
# The passphrase lives in a dedicated `gpg-signing` collection (empty master so
# autologin can read it). This script test-signs; if the agent has no cached
# passphrase it fetches via Secret Service (both unlocked and locked items) and
# unlocks with --pinentry-mode loopback. If the live daemon has nothing, it
# scans on-disk *.keyring files (including ones gnome-keyring 50 refuses to
# load after a multiline secret bricked them) and restocks the dedicated
# collection.
#
# Runs at login from the boot dashboard; invoke anytime:
#   bash ~/.agents/hooks/gpg-agent-unlock.sh
#
# One-time setup (prompts once, stores in the dedicated collection):
#   bash ~/.agents/hooks/gpg-store-passphrase.sh
#
# Manual fallback (nothing stored / passphrase changed), real terminal:
#   export GPG_TTY=$(tty); echo x | gpg --pinentry-mode loopback -u 95FBA6E0AA245342 --clearsign -o /dev/null
#
# Exit: 0 cached-or-unlocked · 1 passphrase rejected · 2 dbus error · 3 nothing stored
set -u

KEY="${GPG_SIGNING_KEY:-95FBA6E0AA245342}"
PY="${AGENTS_HOME:-$HOME/.agents}/hooks/gpg-keyring.py"

key_cached() {
  printf 'test' | gpg --batch --yes --pinentry-mode loopback \
    --local-user "$KEY" --sign -o /dev/null 2>/dev/null
}

if key_cached; then
  exit 0
fi

pass="$(AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}" GPG_SIGNING_KEY="$KEY" python3 "$PY" fetch)" || exit $?

if printf '%s' "$pass" \
   | gpg --batch --yes --pinentry-mode loopback \
         --passphrase-fd 0 --local-user "$KEY" --sign -o /dev/null 2>/dev/null; then
  exit 0
fi
exit 1
