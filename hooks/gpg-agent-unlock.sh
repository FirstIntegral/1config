#!/usr/bin/env bash
# gpg-agent-unlock.sh — auto-unlock the GPG signing key from the GNOME keyring.
#
# The passphrase lives in the keyring, encrypted at rest. This script test-signs;
# if the agent has no cached passphrase it fetches it through Secret Service and
# unlocks with --pinentry-mode loopback. Password logins usually unlock the
# keyring through PAM; autologin sessions may leave it locked and need fallback.
#
# Runs at login from the boot dashboard; invoke anytime:
#   bash ~/.agents/hooks/gpg-agent-unlock.sh
#
# One-time setup (prompts once, stores in keyring, nothing on disk):
#   bash ~/.agents/hooks/gpg-store-passphrase.sh
#
# Manual fallback (keyring empty/locked), real terminal:
#   export GPG_TTY=$(tty); echo x | gpg --pinentry-mode loopback -u 95FBA6E0AA245342 --clearsign -o /dev/null
#
# Implementation notes: this gnome-keyring (50.x) exposes CreateItem on the
# COLLECTION interface and GetSecret on the ITEM interface (not on Service).
# dbus-python/GLib cannot marshal the session handle (it validates object
# paths); the vendored pure-python `jeepney` serializes it correctly.
# Vendor: ~/.agents/vendor/jeepney (jeepney 0.9.0, MIT).
set -u

KEY="${GPG_SIGNING_KEY:-95FBA6E0AA245342}"
ATTRIB_APP="gpg-signing"

key_cached() {
  printf 'test' | gpg --batch --yes --pinentry-mode loopback \
    --local-user "$KEY" --sign -o /dev/null 2>/dev/null
}

fetch_passphrase() {
  KEY="$KEY" ATTRIB_APP="$ATTRIB_APP" AGENTS_HOME="$HOME/.agents" python3 - <<'PY'
import os, sys
sys.path.insert(0, os.path.join(os.environ["AGENTS_HOME"], "vendor"))
from jeepney import DBusAddress, new_method_call
from jeepney.io.blocking import open_dbus_connection

key = os.environ["KEY"]
app = os.environ["ATTRIB_APP"]
try:
    conn = open_dbus_connection(bus="SESSION")
    svc = DBusAddress("/org/freedesktop/secrets", bus_name="org.freedesktop.secrets",
                      interface="org.freedesktop.Secret.Service")
    r = conn.send_and_get_reply(new_method_call(svc, "OpenSession", "sv", ("plain", ("s", ""))))
    handle = r.body[1]
    r = conn.send_and_get_reply(new_method_call(svc, "SearchItems", "a{ss}",
                                                ({"app": app, "key-id": key},)))
    items = r.body[0]
    if not items:
        sys.exit(3)  # nothing stored yet
    item = DBusAddress(items[0], bus_name="org.freedesktop.secrets",
                       interface="org.freedesktop.Secret.Item")
    r = conn.send_and_get_reply(new_method_call(item, "GetSecret", "o", (handle,)))
    sys.stdout.buffer.write(bytes(r.body[0][2]))
except SystemExit:
    raise
except Exception:
    sys.exit(2)  # keyring unreachable / locked / dbus error
PY
}

if key_cached; then
  exit 0
fi

pass="$(fetch_passphrase)" || exit $?

if printf '%s' "$pass" \
   | gpg --batch --yes --pinentry-mode loopback \
         --passphrase-fd 0 --local-user "$KEY" --sign -o /dev/null 2>/dev/null; then
  exit 0
fi
exit 1
