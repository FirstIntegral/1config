#!/usr/bin/env python3
"""Secret-Service helper for the GPG signing passphrase.

The passphrase is stored in a dedicated gnome-keyring collection labelled
`gpg-signing`, not in the default collection. Unencrypted default keyrings
are bricked across reboot when any item's secret contains a raw newline
(Proton JSON, etc.) — gnome-keyring then logs "invalid or unrecognized
format" and Secret Service has no items. A one-item collection stays
loadable. Empty master password so autologin (no PAM password) can read it.

CLI:
  fetch      — write the passphrase to stdout (live Secret Service, else
               scan ~/.local/share/keyrings/*.keyring and restock)
  store      — read passphrase from stdin, write to the dedicated collection
  self-test  — file-scanner + SearchItems-tuple tests (no D-Bus, no secrets)

Exit: 0 ok · 1 bad passphrase/store · 2 dbus/keyring error · 3 nothing stored
"""
from __future__ import annotations

import os
import re
import sys
import tempfile
from pathlib import Path

AGENTS_HOME = os.environ.get("AGENTS_HOME", os.path.expanduser("~/.agents"))
KEY = os.environ.get("GPG_SIGNING_KEY", "95FBA6E0AA245342")
ATTRIB_APP = "gpg-signing"
COLLECTION_LABEL = "gpg-signing"
KEYRING_DIR = Path(os.environ.get("GPG_KEYRING_DIR", os.path.expanduser("~/.local/share/keyrings")))
ITEM_LABEL = f"GPG signing key {KEY}"

_ITEM_RE = re.compile(r"^\[(\d+)\]\s*$")
_ATTR_RE = re.compile(r"^\[(\d+):attribute\d+\]\s*$")
_KV_RE = re.compile(r"^([A-Za-z0-9:_-]+)=(.*)$")


def _log(msg: str) -> None:
    print(msg, file=sys.stderr)


def _ay_to_bytes(val) -> bytes:
    if isinstance(val, (bytes, bytearray)):
        return bytes(val)
    if isinstance(val, str):
        return val.encode()
    return bytes(val)


def scan_keyring_files(directory: Path, key_id: str = KEY) -> bytes | None:
    """Best-effort parse of gnome2 textual .keyring files, including bricked ones.

    GLib KeyFile cannot load a file whose secret= value contains a raw newline.
    We scan line-oriented instead and only return the gpg-signing item.
    """
    if not directory.is_dir():
        return None
    found: list[tuple[float, bytes]] = []
    for path in sorted(directory.glob("*.keyring")):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
            mtime = path.stat().st_mtime
        except OSError:
            continue
        pw = _scan_keyring_text(text, key_id)
        if pw:
            found.append((mtime, pw))
    if not found:
        return None
    found.sort(key=lambda t: t[0])
    return found[-1][1]


def _scan_keyring_text(text: str, key_id: str) -> bytes | None:
    secret: str | None = None
    attrs: dict[str, str] = {}
    attr_name: str | None = None
    in_item = False
    matches: list[bytes] = []

    def finish() -> None:
        if attrs.get("app") == ATTRIB_APP and attrs.get("key-id", key_id) == key_id:
            if secret:
                matches.append(secret.encode())

    for raw in text.splitlines():
        if _ITEM_RE.match(raw):
            if in_item:
                finish()
            in_item = True
            secret = None
            attrs = {}
            attr_name = None
            continue
        if _ATTR_RE.match(raw):
            attr_name = None
            continue
        if not in_item:
            continue
        m = _KV_RE.match(raw)
        if not m:
            continue
        k, v = m.group(1), m.group(2)
        if k == "secret" and secret is None:
            secret = _unescape_keyfile(v)
        elif k == "name":
            attr_name = v
        elif k == "value" and attr_name:
            attrs[attr_name] = v
            attr_name = None
    if in_item:
        finish()
    return matches[-1] if matches else None


def _unescape_keyfile(value: str) -> str:
    # GLib KeyFile escapes; bricked files have raw newlines so this is a no-op
    # for those, and still correct for a properly escaped one-line secret.
    out = []
    i = 0
    while i < len(value):
        if value[i] == "\\" and i + 1 < len(value):
            nxt = value[i + 1]
            out.append({"n": "\n", "t": "\t", "s": " ", "\\": "\\"}.get(nxt, nxt))
            i += 2
        else:
            out.append(value[i])
            i += 1
    return "".join(out)


def _pick_item(unlocked, locked):
    if unlocked:
        return unlocked[0], False
    if locked:
        return locked[0], True
    return None, False


def _dbus():
    vendor = os.path.join(AGENTS_HOME, "vendor")
    if vendor not in sys.path:
        sys.path.insert(0, vendor)
    from jeepney import DBusAddress, new_method_call
    from jeepney.io.blocking import open_dbus_connection
    return DBusAddress, new_method_call, open_dbus_connection


def _secret_tuple(handle, data: bytes):
    return (handle, [], list(data), "text/plain")


def fetch_live() -> bytes | None:
    DBusAddress, new_method_call, open_dbus_connection = _dbus()
    conn = open_dbus_connection(bus="SESSION")
    svc = DBusAddress(
        "/org/freedesktop/secrets",
        bus_name="org.freedesktop.secrets",
        interface="org.freedesktop.Secret.Service",
    )
    r = conn.send_and_get_reply(new_method_call(svc, "OpenSession", "sv", ("plain", ("s", ""))))
    handle = r.body[1]
    r = conn.send_and_get_reply(
        new_method_call(svc, "SearchItems", "a{ss}", ({"app": ATTRIB_APP, "key-id": KEY},))
    )
    # SearchItems → (unlocked, locked). Older code only looked at body[0].
    unlocked, locked = (r.body + ([], []))[:2]
    path, is_locked = _pick_item(unlocked, locked)
    if path is None:
        return None
    if is_locked:
        _unlock_empty(conn, DBusAddress, new_method_call, path, handle)
    item = DBusAddress(path, bus_name="org.freedesktop.secrets", interface="org.freedesktop.Secret.Item")
    r = conn.send_and_get_reply(new_method_call(item, "GetSecret", "o", (handle,)))
    return _ay_to_bytes(r.body[0][2])


def _unlock_empty(conn, DBusAddress, new_method_call, object_path, handle) -> None:
    """Headless unlock of an empty-master collection. Never Service.Unlock (that prompts)."""
    internal = DBusAddress(
        "/org/freedesktop/secrets",
        bus_name="org.freedesktop.secrets",
        interface="org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface",
    )
    # Prefer unlocking the collection the item lives in.
    col = object_path.rsplit("/", 1)[0] if object_path.count("/") >= 5 else object_path
    conn.send_and_get_reply(
        new_method_call(internal, "UnlockWithMasterPassword", "o(oayays)", (col, _secret_tuple(handle, b"")))
    )


def _collections(conn, DBusAddress, new_method_call):
    props = DBusAddress(
        "/org/freedesktop/secrets",
        bus_name="org.freedesktop.secrets",
        interface="org.freedesktop.DBus.Properties",
    )
    r = conn.send_and_get_reply(
        new_method_call(props, "Get", "ss", ("org.freedesktop.Secret.Service", "Collections"))
    )
    return list(r.body[0][1])


def _collection_label(conn, DBusAddress, new_method_call, path: str) -> str:
    props = DBusAddress(path, bus_name="org.freedesktop.secrets", interface="org.freedesktop.DBus.Properties")
    r = conn.send_and_get_reply(new_method_call(props, "Get", "ss", ("org.freedesktop.Secret.Collection", "Label")))
    return r.body[0][1]


def _collection_locked(conn, DBusAddress, new_method_call, path: str) -> bool:
    props = DBusAddress(path, bus_name="org.freedesktop.secrets", interface="org.freedesktop.DBus.Properties")
    r = conn.send_and_get_reply(new_method_call(props, "Get", "ss", ("org.freedesktop.Secret.Collection", "Locked")))
    return bool(r.body[0][1])


def ensure_collection(conn, DBusAddress, new_method_call, handle) -> str:
    for path in _collections(conn, DBusAddress, new_method_call):
        try:
            if _collection_label(conn, DBusAddress, new_method_call, path) == COLLECTION_LABEL:
                if _collection_locked(conn, DBusAddress, new_method_call, path):
                    _unlock_empty(conn, DBusAddress, new_method_call, path, handle)
                return path
        except Exception:
            continue
    internal = DBusAddress(
        "/org/freedesktop/secrets",
        bus_name="org.freedesktop.secrets",
        interface="org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface",
    )
    r = conn.send_and_get_reply(
        new_method_call(
            internal,
            "CreateWithMasterPassword",
            "a{sv}(oayays)",
            (
                {"org.freedesktop.Secret.Collection.Label": ("s", COLLECTION_LABEL)},
                _secret_tuple(handle, b""),
            ),
        )
    )
    return r.body[0]


def store(passphrase: bytes) -> None:
    if not passphrase:
        raise SystemExit(1)
    DBusAddress, new_method_call, open_dbus_connection = _dbus()
    conn = open_dbus_connection(bus="SESSION")
    svc = DBusAddress(
        "/org/freedesktop/secrets",
        bus_name="org.freedesktop.secrets",
        interface="org.freedesktop.Secret.Service",
    )
    r = conn.send_and_get_reply(new_method_call(svc, "OpenSession", "sv", ("plain", ("s", ""))))
    handle = r.body[1]
    col_path = ensure_collection(conn, DBusAddress, new_method_call, handle)
    col = DBusAddress(col_path, bus_name="org.freedesktop.secrets", interface="org.freedesktop.Secret.Collection")
    props = {
        "org.freedesktop.Secret.Item.Label": ("s", ITEM_LABEL),
        "org.freedesktop.Secret.Item.Attributes": ("a{ss}", {"app": ATTRIB_APP, "key-id": KEY}),
    }
    conn.send_and_get_reply(
        new_method_call(
            col,
            "CreateItem",
            "a{sv}(oayays)b",
            (props, _secret_tuple(handle, passphrase), True),
        )
    )


def fetch() -> bytes:
    dbus_err: Exception | None = None
    try:
        pw = fetch_live()
        if pw:
            return pw
    except Exception as e:
        dbus_err = e
        _log(f"secret service: {e}")
    pw = scan_keyring_files(KEYRING_DIR)
    if pw:
        if dbus_err is None:
            try:
                store(pw)
                _log("migrated gpg-signing item into dedicated collection")
            except Exception as e:
                _log(f"migrate skipped: {e}")
        return pw
    raise SystemExit(2 if dbus_err else 3)


def self_test() -> None:
    path, locked = _pick_item([], ["/locked/1"])
    assert path == "/locked/1" and locked is True
    path, locked = _pick_item(["/u"], ["/l"])
    assert path == "/u" and locked is False
    path, locked = _pick_item([], [])
    assert path is None and locked is False

    bricked = """[keyring]
display-name=Default
ctime=1
mtime=0
lock-on-idle=false
lock-after=false

[1]
item-type=0
display-name=Password for proton
secret={"foo":
"bar-with-newline"}
mtime=1
ctime=1

[1:attribute0]
name=application
type=string
value=Python keyring library

[2]
item-type=0
display-name=GPG signing key 95FBA6E0AA245342
secret=test-passphrase-not-real
mtime=2
ctime=2

[2:attribute0]
name=app
type=string
value=gpg-signing

[2:attribute1]
name=key-id
type=string
value=95FBA6E0AA245342
"""
    assert _scan_keyring_text(bricked, KEY) == b"test-passphrase-not-real"
    assert _scan_keyring_text(bricked, "DEADBEEF") is None
    assert _scan_keyring_text("[keyring]\n", KEY) is None

    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        (d / "Default.keyring").write_text(bricked)
        (d / "empty.keyring").write_text("[keyring]\ndisplay-name=x\n")
        assert scan_keyring_files(d, KEY) == b"test-passphrase-not-real"
        assert scan_keyring_files(d, "nope") is None
    _log("self-test ok")


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    cmd = argv[1]
    if cmd == "fetch":
        sys.stdout.buffer.write(fetch())
        return 0
    if cmd == "store":
        store(sys.stdin.buffer.read())
        return 0
    if cmd == "self-test":
        self_test()
        return 0
    _log(f"unknown command: {cmd}")
    return 2


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except BrokenPipeError:
        raise SystemExit(0)
