#!/usr/bin/env bash
# gpg-git.sh — git's gpg.program. Never pops pinentry.
#
# Git calls this instead of gpg. We force --pinentry-mode loopback so a cold
# agent cannot open pinentry-gnome3 (that was the "enter the GPG password"
# dialog). On cache miss we restock the agent from the dedicated gpg-signing
# keyring and retry once. stdin is the payload (commit / tag); save it so
# the retry still has bytes.
#
# Installed by setup.sh: git config --global gpg.program ~/.agents/hooks/gpg-git.sh
set -u

AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
UNLOCK="$AGENTS_HOME/hooks/gpg-agent-unlock.sh"

tmp="$(mktemp)" || exit 1
trap 'rm -f "$tmp"' EXIT
cat >"$tmp"

run() {
  gpg --batch --yes --pinentry-mode loopback "$@" <"$tmp"
}

if run "$@"; then
  exit 0
fi

if [ -x "$UNLOCK" ]; then
  bash "$UNLOCK" >/dev/null 2>&1 || true
fi
run "$@"
