#!/usr/bin/env bash
# gpg-sign-check.sh — can this machine sign a commit right now, with nobody at the keyboard?
#
#   bash ~/.agents/hooks/gpg-sign-check.sh
#
# It makes one test signature with the key git would use (hooks/gpg-signing-key.sh)
# and with pinentry turned off, so it never asks for a passphrase and never
# stores one. The boot dashboard and verify.sh call it.
#
# Exit 0  a signature is made with no prompt: the key has no passphrase, or
#         gpg-agent already holds it
#      1  the key needs a passphrase that the agent does not hold. git will sign
#         only after gpg has asked for it once in a terminal or a pinentry window
#      3  no signing key is set, gpg is missing, or the secret key is not in this keyring
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
command -v gpg >/dev/null 2>&1 || exit 3
KEY="$(bash "$ROOT/hooks/gpg-signing-key.sh" 2>/dev/null)" || exit 3
[ -n "$KEY" ] || exit 3
gpg --batch --list-secret-keys "$KEY" >/dev/null 2>&1 || exit 3
if printf 'test' | gpg --batch --yes --pinentry-mode error --local-user "$KEY" --sign -o /dev/null 2>/dev/null; then
  exit 0
fi
exit 1
