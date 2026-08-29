#!/usr/bin/env bash
# gpg-store-passphrase.sh — one-time: store the GPG signing passphrase into the
# GNOME keyring (Secret Service). Nothing is written to disk.
#
#   bash ~/.agents/hooks/gpg-store-passphrase.sh
#
# Re-run after changing the passphrase. Then verify-unlocks via
# gpg-agent-unlock.sh (all future commits sign silently; agent caches 1 year).
#
# Implementation notes: this gnome-keyring (50.x) exposes CreateItem on the
# COLLECTION interface (not on Service). dbus-python/GLib cannot marshal the
# session handle; vendored `jeepney` (MIT, pure python) serializes it.
set -u

KEY="${GPG_SIGNING_KEY:-95FBA6E0AA245342}"
ATTRIB_APP="gpg-signing"
LABEL="GPG signing key $KEY"

printf 'Enter passphrase for GPG key %s (stored in keyring; nothing on disk): ' "$KEY"
IFS= read -rs pass || { echo; exit 1; }
echo

if [ -z "$pass" ]; then
  echo "empty passphrase — abort" >&2
  exit 1
fi

KEY="$KEY" ATTRIB_APP="$ATTRIB_APP" LABEL="$LABEL" PASS="$pass" AGENTS_HOME="$HOME/.agents" python3 - <<'PY'
import os, sys
sys.path.insert(0, os.path.join(os.environ["AGENTS_HOME"], "vendor"))
from jeepney import DBusAddress, new_method_call
from jeepney.io.blocking import open_dbus_connection

key = os.environ["KEY"]
app = os.environ["ATTRIB_APP"]
label = os.environ["LABEL"]
passwd = os.environ["PASS"]
conn = open_dbus_connection(bus="SESSION")
svc = DBusAddress("/org/freedesktop/secrets", bus_name="org.freedesktop.secrets",
                  interface="org.freedesktop.Secret.Service")
r = conn.send_and_get_reply(new_method_call(svc, "OpenSession", "sv", ("plain", ("s", ""))))
handle = r.body[1]
r = conn.send_and_get_reply(new_method_call(svc, "ReadAlias", "s", ("default",)))
col_path = r.body[0]
col = DBusAddress(col_path, bus_name="org.freedesktop.secrets",
                  interface="org.freedesktop.Secret.Collection")
props = {
    "org.freedesktop.Secret.Item.Label": ("s", label),
    "org.freedesktop.Secret.Item.Attributes": ("a{ss}", {"app": app, "key-id": key}),
}
secret = (handle, [], list(passwd.encode()), "text/plain")
conn.send_and_get_reply(new_method_call(col, "CreateItem", "a{sv}(oayays)b",
                                        (props, secret, True)))
print("stored in keyring")
PY
rc=$?
unset pass
if [ "$rc" -ne 0 ]; then
  echo "store failed (rc=$rc) — is gnome-keyring running and unlocked?" >&2
  exit 1
fi

# The 1-year TTL only applies to agents started AFTER the conf exists; a
# pre-existing agent keeps its defaults (2h max) and would prompt on expiry.
# Ensure the conf, then reload the agent; the unlock below re-seeds the cache
# from the keyring headlessly.
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
