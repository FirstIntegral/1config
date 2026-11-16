#!/usr/bin/env python3
"""claude-brain-access.py — let Claude see the brain directory.

    python3 ~/.agents/hooks/claude-brain-access.py apply --home "$HOME" --brain "$HOME/.agents"
    python3 ~/.agents/hooks/claude-brain-access.py check --home "$HOME" --brain "$HOME/.agents"
    python3 ~/.agents/hooks/claude-brain-access.py self-test

Claude Code reads ~/.claude/CLAUDE.md. Claude Desktop remote chat does not.
Desktop uploads files from folders already granted on that chat. This script
adds the realpath of the brain to two places and nowhere else:

  * ~/.claude/settings.json permissions.additionalDirectories
  * when ~/.config/Claude/claude_desktop_config.json exists:
      preferences.localAgentModeTrustedFolders
      every existing preferences.remoteChatFolderGrants.*.folders
      every existing preferences.remoteSessionFolderGrants value that is a
      list of paths or an object with folders

A missing Desktop file is a skip. The script does not create that file and
does not invent a chat id. Trusted folders do not mount the directory onto a
new chat. A second apply writes nothing.

check exits 0 when the grant is present, 2 when settings.json is missing,
and 1 on drift. apply exits 1 when the brain directory is missing, JSON is
invalid, or a grant that should be a list is some other type.
"""
import argparse
import json
import os
import pathlib
import sys
import tempfile

DESKTOP_REL = pathlib.Path(".config/Claude/claude_desktop_config.json")
SETTINGS_REL = pathlib.Path(".claude/settings.json")


def same(path, brain):
    return os.path.realpath(path) == brain


def has_path(seq, brain):
    return any(isinstance(item, str) and same(item, brain) for item in seq)


def ensure(seq, brain):
    if has_path(seq, brain):
        return False
    seq.append(brain)
    return True


def load_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as err:
        raise SystemExit(f"invalid JSON in {path}: {err}") from err


def dump_json(path, cfg):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def brain_path(raw):
    path = pathlib.Path(raw).expanduser()
    if not path.is_dir():
        raise SystemExit(f"brain directory missing: {path}")
    return os.path.realpath(path)


def mutate_settings(cfg, brain):
    perms = cfg.setdefault("permissions", {})
    current = perms.get("additionalDirectories", [])
    if "additionalDirectories" in perms and not isinstance(current, list):
        raise SystemExit("permissions.additionalDirectories is not a list")
    if not isinstance(current, list):
        current = []
    changed = ensure(current, brain)
    perms["additionalDirectories"] = current
    return changed


def mutate_desktop(cfg, brain):
    """Return (changed, unknown_shapes). Never creates a chat id."""
    prefs = cfg.setdefault("preferences", {})
    changed = False
    unknown = []
    trusted = prefs.get("localAgentModeTrustedFolders", [])
    if "localAgentModeTrustedFolders" in prefs and not isinstance(trusted, list):
        raise SystemExit("preferences.localAgentModeTrustedFolders is not a list")
    if not isinstance(trusted, list):
        trusted = []
    if ensure(trusted, brain):
        changed = True
    prefs["localAgentModeTrustedFolders"] = trusted

    def walk(name, value):
        nonlocal changed
        if not isinstance(value, dict):
            return
        for key, entry in value.items():
            if isinstance(entry, list):
                if ensure(entry, brain):
                    changed = True
            elif isinstance(entry, dict) and isinstance(entry.get("folders"), list):
                if ensure(entry["folders"], brain):
                    changed = True
            else:
                unknown.append(f"{name}.{key}")

    walk("remoteChatFolderGrants", prefs.get("remoteChatFolderGrants"))
    walk("remoteSessionFolderGrants", prefs.get("remoteSessionFolderGrants"))
    return changed, unknown


def desktop_problems(cfg, brain):
    prefs = cfg.get("preferences")
    if not isinstance(prefs, dict):
        return ["desktop config has no preferences object"]
    problems = []
    trusted = prefs.get("localAgentModeTrustedFolders")
    if not isinstance(trusted, list) or not has_path(trusted, brain):
        problems.append("desktop trusted folders omit the brain")

    def walk(name, value):
        if not isinstance(value, dict):
            return
        for key, entry in value.items():
            if isinstance(entry, list):
                seq = entry
            elif isinstance(entry, dict) and isinstance(entry.get("folders"), list):
                seq = entry["folders"]
            else:
                continue
            if not has_path(seq, brain):
                problems.append(f"desktop {name}.{key} omits the brain")

    walk("remoteChatFolderGrants", prefs.get("remoteChatFolderGrants"))
    walk("remoteSessionFolderGrants", prefs.get("remoteSessionFolderGrants"))
    return problems


def apply_home(home, brain):
    home = pathlib.Path(home)
    settings = home / SETTINGS_REL
    cfg = load_json(settings) if settings.is_file() else {}
    if not isinstance(cfg, dict):
        raise SystemExit(f"{settings} is not a JSON object")
    changed = mutate_settings(cfg, brain)
    if changed or not settings.is_file():
        dump_json(settings, cfg)
        print(f"  merged   additionalDirectories += {brain}")
    else:
        print("  ok       additionalDirectories already lists the brain")

    desktop = home / DESKTOP_REL
    if not desktop.is_file():
        print("  skip     no Claude Desktop config")
        return
    raw = load_json(desktop)
    if not isinstance(raw, dict):
        raise SystemExit(f"{desktop} is not a JSON object")
    dchanged, unknown = mutate_desktop(raw, brain)
    for item in unknown:
        print(f"  skip     unknown grant shape {item}")
    if dchanged:
        dump_json(desktop, raw)
        print("  merged   Desktop trusted folders and existing grants")
    else:
        print("  ok       Desktop grants already list the brain")


def check_home(home, brain):
    home = pathlib.Path(home)
    settings = home / SETTINGS_REL
    if not settings.is_file():
        print("missing settings.json")
        return 2
    cfg = load_json(settings)
    if not isinstance(cfg, dict):
        print(f"{settings} is not a JSON object")
        return 1
    dirs = cfg.get("permissions", {}).get("additionalDirectories")
    if not isinstance(dirs, list) or not has_path(dirs, brain):
        print("settings additionalDirectories omits the brain")
        return 1
    desktop = home / DESKTOP_REL
    if not desktop.is_file():
        print("ok settings; desktop config absent")
        return 0
    raw = load_json(desktop)
    if not isinstance(raw, dict):
        print(f"{desktop} is not a JSON object")
        return 1
    problems = desktop_problems(raw, brain)
    if problems:
        print(problems[0])
        return 1
    print("ok settings; desktop grants")
    return 0


def self_test():
    def fail(msg):
        print(f"FAIL: {msg}", file=sys.stderr)
        raise SystemExit(1)

    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        brain = root / "brain"
        brain.mkdir()
        home = root / "home"
        other = "/tmp/claude-brain-access-other"

        settings = {
            "permissions": {
                "allow": ["Bash(ls *)"],
                "defaultMode": "bypassPermissions",
                "additionalDirectories": [other],
            }
        }
        desktop = {
            "coworkUserFilesPath": "/tmp/claude-user-files",
            "preferences": {
                "localAgentModeTrustedFolders": [other],
                "remoteChatFolderGrants": {
                    "chat-1": {"orgUuid": "org", "folders": [other]},
                },
                "remoteSessionFolderGrants": {
                    "session-list": [other],
                    "session-obj": {"folders": [other]},
                    "session-unknown": "leave-me",
                },
            },
        }
        dump_json(home / SETTINGS_REL, settings)
        dump_json(home / DESKTOP_REL, desktop)
        apply_home(home, brain_path(brain))
        written_settings = (home / SETTINGS_REL).read_bytes()
        written_desktop = (home / DESKTOP_REL).read_bytes()
        apply_home(home, brain_path(brain))
        if (home / SETTINGS_REL).read_bytes() != written_settings:
            fail("second apply rewrote settings.json")
        if (home / DESKTOP_REL).read_bytes() != written_desktop:
            fail("second apply rewrote the desktop config")
        if check_home(home, brain_path(brain)) != 0:
            fail("check failed on a fresh grant")
        got = load_json(home / SETTINGS_REL)
        dirs = got["permissions"]["additionalDirectories"]
        if dirs != [other, str(brain.resolve())]:
            fail(f"additionalDirectories changed shape: {dirs}")
        if got["permissions"]["allow"] != ["Bash(ls *)"]:
            fail("allow bucket was rewritten")
        got_d = load_json(home / DESKTOP_REL)
        if got_d["coworkUserFilesPath"] != "/tmp/claude-user-files":
            fail("desktop top-level key dropped")
        prefs = got_d["preferences"]
        if prefs["remoteSessionFolderGrants"]["session-unknown"] != "leave-me":
            fail("unknown grant shape was rewritten")
        for seq in (
            prefs["localAgentModeTrustedFolders"],
            prefs["remoteChatFolderGrants"]["chat-1"]["folders"],
            prefs["remoteSessionFolderGrants"]["session-list"],
            prefs["remoteSessionFolderGrants"]["session-obj"]["folders"],
        ):
            if other not in seq or str(brain.resolve()) not in seq:
                fail(f"grant lost a directory: {seq}")
        prefs["remoteChatFolderGrants"]["chat-1"]["folders"] = [other]
        dump_json(home / DESKTOP_REL, got_d)
        if check_home(home, brain_path(brain)) != 1:
            fail("check passed after a grant lost the brain")

        bare = root / "bare"
        dump_json(bare / SETTINGS_REL, {"permissions": {"defaultMode": "default"}})
        apply_home(bare, brain_path(brain))
        if (bare / DESKTOP_REL).exists():
            fail("apply created a Desktop config")
        if check_home(bare, brain_path(brain)) != 0:
            fail("check failed when Desktop config is absent")

        bad = root / "bad"
        dump_json(bad / SETTINGS_REL, {"permissions": {"additionalDirectories": "nope"}})
        before = (bad / SETTINGS_REL).read_bytes()
        try:
            apply_home(bad, brain_path(brain))
        except SystemExit as err:
            if err.code in (0, None):
                fail("a non-list additionalDirectories was accepted")
        else:
            fail("a non-list additionalDirectories was accepted")
        if (bad / SETTINGS_REL).read_bytes() != before:
            fail("a refused apply still wrote settings.json")

        empty = root / "empty"
        if check_home(empty, brain_path(brain)) != 2:
            fail("missing settings.json was not exit 2")
        apply_home(empty, brain_path(brain))
        created = load_json(empty / SETTINGS_REL)
        if created["permissions"]["additionalDirectories"] != [str(brain.resolve())]:
            fail("apply did not create settings.json")
    print("ok")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("apply", "check", "self-test"))
    parser.add_argument("--home", default=str(pathlib.Path.home()))
    parser.add_argument("--brain", default=str(pathlib.Path.home() / ".agents"))
    args = parser.parse_args()
    if args.command == "self-test":
        self_test()
        return
    brain = brain_path(args.brain)
    if args.command == "apply":
        apply_home(args.home, brain)
        return
    raise SystemExit(check_home(args.home, brain))


if __name__ == "__main__":
    main()
