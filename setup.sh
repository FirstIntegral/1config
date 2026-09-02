#!/usr/bin/env bash
# setup.sh — recreate the unified AI-terminal setup on a fresh machine.
#
# Omarchy (Arch) and Ubuntu (Debian): clone ~/.agents, then:
#   bash ~/.agents/setup.sh
# Existing machine (either distro): git pull && bash ~/.agents/setup.sh
# Idempotent. Backs up anything it replaces to ~/.agents/backups/setup-<timestamp>/.
#
# Env: SKIP_CRON=1  skip crontab install (testing / machine without cron)
set -euo pipefail

AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
CANON="$AGENTS_HOME/AGENTS.md"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$AGENTS_HOME/backups/setup-$TS"
GUARD_DIR="$HOME/cron-jobs/agents-symlink-guard"
MEM_GUARD_DIR="$HOME/cron-jobs/claude-memory-guard"
MEM_GUARD_SRC="$AGENTS_HOME/hooks/check-claude-memory.sh"
UPD_DIR="$HOME/cron-jobs/ai-terminal-tools-update-on-boot"
UPD_SRC="$AGENTS_HOME/updater"
SKIP_CRON="${SKIP_CRON:-0}"

log() { echo "  $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

echo "== unified AI setup — $(date) =="

# --- 0 platform + preflight (Omarchy/Arch and Ubuntu/Debian) ----------------
echo "[0] platform"
FAMILY=unknown
HINT="install python3, flock (util-linux), git, cron, gnupg, gnome-keyring"
if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
fi
if command -v omarchy >/dev/null 2>&1 || [ -d /usr/share/omarchy ]; then
  FAMILY=omarchy
  HINT="omarchy pkg add python util-linux cronie git gnupg gnome-keyring texlive-meta"
elif echo "${ID:-} ${ID_LIKE:-}" | grep -qiE 'ubuntu|debian'; then
  FAMILY=debian
  HINT="sudo apt-get install -y python3 util-linux cron git gnupg gnome-keyring texlive-full"
elif echo "${ID:-} ${ID_LIKE:-}" | grep -qi arch; then
  FAMILY=arch
  HINT="sudo pacman -S --needed python util-linux cronie git gnupg gnome-keyring texlive-meta"
fi
log "family   $FAMILY (${ID:-unknown})"

need_die=0
for cmd in python3 flock git; do
  if command -v "$cmd" >/dev/null; then
    log "ok       $cmd"
  else
    log "MISSING  $cmd"
    need_die=1
  fi
done
if command -v crontab >/dev/null; then
  log "ok       crontab"
else
  log "MISSING  crontab (Ubuntu: apt install cron · Omarchy/Arch: pacman -S cronie)"
fi
if command -v gpg >/dev/null; then
  log "ok       gpg"
else
  log "MISSING  gpg — commit signing will fail until gnupg is installed"
fi
if command -v gnome-keyring-daemon >/dev/null; then
  log "ok       gnome-keyring"
else
  log "MISSING  gnome-keyring — signing unlock needs Secret Service"
fi
if command -v latexmk >/dev/null || command -v pdflatex >/dev/null; then
  log "ok       tex"
else
  log "MISSING  texlive (writepaper_project needs it) — $HINT"
fi
if [ "$need_die" -eq 1 ]; then
  echo "ERROR: required commands missing. Install, then re-run setup.sh:" >&2
  echo "  $HINT" >&2
  exit 1
fi

[ -f "$CANON" ] || die "canonical $CANON not found — copy ~/.agents first"
[ -d "$AGENTS_HOME/project-template" ] || log "WARNING: $AGENTS_HOME/project-template missing — create_project scaffolding will have no source"
if [ "${AGENTS_UPDATE_LOCK_HELD:-0}" != 1 ]; then
  mkdir -p "$UPD_DIR"
  exec 8>"$UPD_DIR/.update.lock"
  flock 8
fi
export AGENTS_UPDATE_LOCK_HELD=1
mkdir -p "$BACKUP_DIR"

# --- 1 symlinks ------------------------------------------------------------
echo "[1] symlinks → $CANON"
link_one() {
  local link="$1"
  mkdir -p "$(dirname "$link")"
  if [ -L "$link" ] && [ "$(readlink -f "$link")" = "$CANON" ]; then
    log "ok       $link (already linked)"
  else
    if [ -e "$link" ] && [ ! -L "$link" ]; then
      cp -p "$link" "$BACKUP_DIR/"
      log "backed up existing $link"
    fi
    ln -sfn "$CANON" "$link"
    log "linked   $link"
  fi
}
link_one "$HOME/.grok/AGENTS.md"
link_one "$HOME/.config/opencode/AGENTS.md"
link_one "$HOME/.claude/CLAUDE.md"

# --- 2 grok config.toml ------------------------------------------------------
echo "[2] grok config.toml switches"
GROK_CFG="$HOME/.grok/config.toml"
if [ -f "$GROK_CFG" ]; then
  cp -p "$GROK_CFG" "$BACKUP_DIR/"
fi
GROK_CFG="$GROK_CFG" python3 - <<'PYEOF'
import os, re, pathlib
p = pathlib.Path(os.environ["GROK_CFG"])
text = p.read_text() if p.exists() else "# grok config — created by ~/.agents/setup.sh\n"

def set_key(text, section, key, value):
    if not re.search(rf"(?m)^\[{re.escape(section)}\]\s*$", text):
        return text.rstrip() + f"\n\n[{section}]\n{key} = {value}\n"
    lines = text.splitlines()
    start = next(i for i, l in enumerate(lines) if l.strip() == f"[{section}]")
    end = next((i for i in range(start + 1, len(lines))
                if lines[i].lstrip().startswith("[")), len(lines))
    for i in range(start + 1, end):
        if re.match(rf"\s*{re.escape(key)}\s*=", lines[i]):
            lines[i] = re.sub(r"=.*$", f"= {value}", lines[i])
            return "\n".join(lines) + "\n"
    lines.insert(start + 1, f"{key} = {value}")
    return "\n".join(lines) + "\n"

for section, key, value in [
    ("compat.claude", "agents", "false"),   # no double-read of CLAUDE.md
    ("compat.claude", "rules", "false"),
    ("memory", "enabled", "false"),         # memory lives in shared markdown
]:
    text = set_key(text, section, key, value)
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(text)
print("  set      [compat.claude] agents/rules=false, [memory] enabled=false")
PYEOF
# Backup dedupe: drop the pre-copy if nothing changed
if [ -f "$BACKUP_DIR/$(basename "$GROK_CFG")" ] && cmp -s "$GROK_CFG" "$BACKUP_DIR/$(basename "$GROK_CFG")"; then
  rm -f "$BACKUP_DIR/$(basename "$GROK_CFG")"
fi

# --- 3 grok memory dir removal -----------------------------------------------
echo "[3] grok memory dir removal"
GROK_MEM="$HOME/.grok/memory"
if [ -e "$GROK_MEM" ]; then
  mkdir -p "$BACKUP_DIR"
  cp -a "$GROK_MEM" "$BACKUP_DIR/grok-memory"
  rm -rf "$GROK_MEM"
  log "removed $GROK_MEM (archived under $BACKUP_DIR/grok-memory)"
else
  log "ok       no $GROK_MEM"
fi

# --- 4 claude auto-memory wipe-to-stub ----------------------------------------
echo "[4] claude auto-memory wipe-to-stub"
DISABLED_STUB='# Memory Index — DISABLED

Disabled by user policy. Do not write memories here.
Durable facts live in `~/.agents/AGENTS.md` (global rules) and the project'\''s
`AGENTS.md` / `session_compact.md` (project facts).
'
found=0
shopt -s nullglob
for d in "$HOME"/.claude/projects/*/memory; do
  [ -d "$d" ] || continue
  f="$d/MEMORY.md"
  # Already a lone DISABLED stub → leave alone
  if [ -f "$f" ] && grep -qi "disabled by user policy" "$f" 2>/dev/null; then
    extras=0
    for x in "$d"/* "$d"/.[!.]* "$d"/..?*; do
      [ -e "$x" ] || continue
      base="$(basename "$x")"
      [ "$base" = "MEMORY.md" ] && continue
      extras=1
      break
    done
    if [ "$extras" = 0 ]; then
      continue
    fi
  fi
  found=1
  proj="$(basename "$(dirname "$d")")"
  mkdir -p "$BACKUP_DIR"
  cp -a "$d" "$BACKUP_DIR/claude-memory-$proj"
  # Wipe everything in the memory dir, then write stub only
  find "$d" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  printf '%s\n' "$DISABLED_STUB" > "$f"
  log "wiped+stub $d (original archived as claude-memory-$proj)"
done
shopt -u nullglob
[ "$found" = 0 ] && log "ok       all claude memory dirs already stub-only (or none exist)"

# --- 5 claude SessionStart hook: project AGENTS.md loader -------------------
echo "[5] claude AGENTS.md SessionStart hook"
HOOK_SCRIPT="$AGENTS_HOME/hooks/load-project-agents.sh"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [ ! -f "$HOOK_SCRIPT" ]; then
  log "WARNING: $HOOK_SCRIPT missing — copy ~/.agents fully; skipping hook wiring"
else
  chmod +x "$HOOK_SCRIPT"
  [ -f "$CLAUDE_SETTINGS" ] && cp -p "$CLAUDE_SETTINGS" "$BACKUP_DIR/claude-settings.json"
  CLAUDE_SETTINGS="$CLAUDE_SETTINGS" python3 - <<'PYEOF'
import json, os, pathlib
p = pathlib.Path(os.environ["CLAUDE_SETTINGS"])
cfg = json.loads(p.read_text()) if p.exists() else {}
cmd = 'bash "$HOME/.agents/hooks/load-project-agents.sh"'
hooks = cfg.setdefault("hooks", {})
starts = hooks.setdefault("SessionStart", [])
existing = [h.get("command", "") for g in starts for h in g.get("hooks", [])]
if any("load-project-agents.sh" in c for c in existing):
    print("  ok       AGENTS.md hook already wired")
else:
    entry = {"type": "command", "command": cmd, "timeout": 5,
             "statusMessage": "Loading project AGENTS.md..."}
    if starts:
        starts[0].setdefault("hooks", []).append(entry)
    else:
        starts.append({"hooks": [entry]})
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(cfg, indent=2) + "\n")
    print("  wired    SessionStart -> load-project-agents.sh")
PYEOF
  # Backup dedupe: drop the pre-copy if nothing changed
  if [ -f "$BACKUP_DIR/claude-settings.json" ] && cmp -s "$CLAUDE_SETTINGS" "$BACKUP_DIR/claude-settings.json"; then
    rm -f "$BACKUP_DIR/claude-settings.json"
  fi
fi

# --- 5b claude global permission policy (source: permissions.json) -----------
echo "[5b] permission rules → claude"
PERMS_SRC="$AGENTS_HOME/permissions.json"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [ ! -f "$PERMS_SRC" ]; then
  log "WARNING: $PERMS_SRC missing — copy ~/.agents fully; skipping permission merge"
else
  [ -f "$CLAUDE_SETTINGS" ] && cp -p "$CLAUDE_SETTINGS" "$BACKUP_DIR/claude-settings-perms.json"
  PERMS_SRC="$PERMS_SRC" CLAUDE_SETTINGS="$CLAUDE_SETTINGS" python3 - <<'PYEOF'
import json, os, pathlib

src = json.loads(pathlib.Path(os.environ["PERMS_SRC"]).read_text())
p = pathlib.Path(os.environ["CLAUDE_SETTINGS"])
cfg = json.loads(p.read_text()) if p.exists() else {}

perms = cfg.setdefault("permissions", {})
changed = []
for bucket in ("allow", "ask", "deny"):
    wanted = list(src.get("permissions", {}).get(bucket, []))
    if perms.get(bucket) != wanted:
        perms[bucket] = wanted
        changed.append(bucket)

# defaults.bash_without_prompt / edit_without_prompt -> permissions.defaultMode.
# bypassPermissions is the ONLY Claude mode that kills hard-coded safety prompts
# (cd+write path-bypass, cd+git untrusted-hooks, some parse verdicts). acceptEdits
# only skips file-write prompts; Bash still goes through the allow list.
defaults = src.get("defaults", {})
if defaults.get("bash_without_prompt"):
    mode = "bypassPermissions"
elif defaults.get("edit_without_prompt"):
    mode = "acceptEdits"
else:
    mode = "default"
mode_changed = perms.get("defaultMode") != mode
perms["defaultMode"] = mode

if changed or mode_changed:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(cfg, indent=2) + "\n")
    msg = "replaced " + ", ".join(changed) if changed else ""
    if mode_changed:
        msg = (msg + ", " if msg else "") + f'defaultMode="{mode}"'
    print("  merged   " + msg)
else:
    print("  ok       permission policy already in sync")
PYEOF
  # Backup dedupe: drop the pre-copy if nothing changed
  if [ -f "$BACKUP_DIR/claude-settings-perms.json" ] && cmp -s "$CLAUDE_SETTINGS" "$BACKUP_DIR/claude-settings-perms.json"; then
    rm -f "$BACKUP_DIR/claude-settings-perms.json"
  fi
fi

# --- 5c grok permission rules (same canonical source, native rule syntax) ----
echo "[5c] permission rules → grok"
GROK_CFG="$HOME/.grok/config.toml"
if [ ! -f "$PERMS_SRC" ]; then
  log "WARNING: $PERMS_SRC missing — skipping grok permission merge"
else
  [ -f "$GROK_CFG" ] && cp -p "$GROK_CFG" "$BACKUP_DIR/grok-config-perms.toml"
  PERMS_SRC="$PERMS_SRC" GROK_CFG="$GROK_CFG" python3 - <<'PYEOF'
import json, os, pathlib, re, tomllib

src = json.loads(pathlib.Path(os.environ["PERMS_SRC"]).read_text())
p = pathlib.Path(os.environ["GROK_CFG"])
text = p.read_text() if p.exists() else "# grok config — created by ~/.agents/setup.sh\n"

# Grok speaks the same Bash(...) rule syntax as Claude, so rules go in verbatim.
cur = tomllib.loads(text).get("permission", {})
extra_keys = set(cur) - {"allow", "ask", "deny"}
if extra_keys:
    raise SystemExit("unsupported existing [permission] keys; move them to permissions.json first: " + ", ".join(sorted(extra_keys)))
merged, changed = {}, []
for bucket in ("allow", "ask", "deny"):
    existing = [r for r in cur.get(bucket, []) if isinstance(r, str)]
    # Grok skips Skill(...) and other unknown prefixes; only install rules it enforces.
    wanted = [r for r in src.get("permissions", {}).get(bucket, []) if re.fullmatch(r"Bash\(.*\)", r)]
    merged[bucket] = wanted
    if existing != wanted:
        changed.append(bucket)

def render(bucket):
    if not merged[bucket]:
        return ""
    body = "".join(f'  {json.dumps(r)},\n' for r in merged[bucket])
    return f"{bucket} = [\n{body}]\n"

section = "[permission]\n" + render("allow") + render("ask") + render("deny")

lines = text.splitlines()
start = next((i for i, l in enumerate(lines) if l.strip() == "[permission]"), None)
if start is None:
    text = text.rstrip() + "\n\n" + section
else:
    end = next((i for i in range(start + 1, len(lines))
                if lines[i].lstrip().startswith("[")), len(lines))
    text = "\n".join(lines[:start] + section.rstrip("\n").splitlines() + lines[end:]) + "\n"

# Match Claude's policy modes: bash autonomy wins, otherwise edits can remain prompt-free.
_d = src.get("defaults", {})
if _d.get("bash_without_prompt"):
    want_mode = "always-approve"
elif _d.get("edit_without_prompt"):
    want_mode = "acceptEdits"
else:
    want_mode = "ask"
MODE_LINE = f'permission_mode = {json.dumps(want_mode)}'
before_ui = text
lines = text.splitlines()
ui = next((i for i, l in enumerate(lines) if l.strip() == "[ui]"), None)
if ui is None:
    lines += ["", "[ui]", MODE_LINE]
else:
    end = next((i for i in range(ui + 1, len(lines))
                if lines[i].lstrip().startswith("[")), len(lines))
    idx = next((i for i in range(ui + 1, end)
                if re.match(r"\s*permission_mode\s*=", lines[i])), None)
    if idx is None:
        lines.insert(ui + 1, MODE_LINE)
    else:
        lines[idx] = MODE_LINE
text = "\n".join(lines) + "\n"
mode_changed = text != before_ui

tomllib.loads(text)                          # validate before replacing the live config
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(text)
bits = changed
if bits:
    print("  replaced " + ", ".join(bits) + " → [permission]")
if mode_changed:
    print(f'  merged   [ui] permission_mode="{want_mode}"')
elif not bits:
    print("  ok       grok [permission] already in sync")
PYEOF
  if [ -f "$BACKUP_DIR/grok-config-perms.toml" ] && cmp -s "$GROK_CFG" "$BACKUP_DIR/grok-config-perms.toml"; then
    rm -f "$BACKUP_DIR/grok-config-perms.toml"
  fi
fi

# --- 5d opencode permission rules (Bash(X) → permission.bash "X") ------------
echo "[5d] permission rules → opencode"
OC_CFG="$HOME/.config/opencode/opencode.jsonc"
if [ ! -f "$PERMS_SRC" ]; then
  log "WARNING: $PERMS_SRC missing — skipping opencode permission merge"
else
  [ -f "$OC_CFG" ] && cp -p "$OC_CFG" "$BACKUP_DIR/opencode-perms.jsonc"
  PERMS_SRC="$PERMS_SRC" OC_CFG="$OC_CFG" python3 - <<'PYEOF'
import json, os, pathlib, re

src = json.loads(pathlib.Path(os.environ["PERMS_SRC"]).read_text())
p = pathlib.Path(os.environ["OC_CFG"])

def strip_jsonc(s):
    out, i, n, in_string, escaped = [], 0, len(s), False, False
    while i < n:
        c = s[i]
        if in_string:
            out.append(c)
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
            out.append(c)
            i += 1
        elif s.startswith("//", i):
            i = s.find("\n", i)
            if i == -1:
                break
        elif s.startswith("/*", i):
            i = s.find("*/", i)
            i = n if i == -1 else i + 2
        else:
            out.append(c); i += 1
    return "".join(out)

def strip_trailing_commas(s):
    out, i, n, in_string, escaped = [], 0, len(s), False, False
    while i < n:
        c = s[i]
        if in_string:
            out.append(c)
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
            out.append(c)
            i += 1
            continue
        if c == ',':
            j = i + 1
            while j < n and s[j].isspace():
                j += 1
            if j < n and s[j] in '}]':
                i += 1
                continue
        out.append(c)
        i += 1
    return "".join(out)

raw = p.read_text() if p.exists() else '{\n  "$schema": "https://opencode.ai/config.json"\n}\n'
stripped = strip_trailing_commas(strip_jsonc(raw))
had_comments = stripped != raw        # "//" inside the $schema URL is not a comment
cfg = json.loads(stripped)

# Only Bash(...) rules translate; OpenCode's bash map keys are the command patterns themselves.
def bash_patterns(bucket):
    pats = []
    for rule in src.get("permissions", {}).get(bucket, []):
        m = re.fullmatch(r"Bash\((.*)\)", rule)
        if m and m.group(1) not in ("", "*"):
            pats.append(m.group(1))
    return pats

perm = cfg.setdefault("permission", {})
bash = perm.get("bash")
if isinstance(bash, str):
    bash = {"*": bash}                                  # a bare "allow"/"ask" becomes the catch-all
elif not isinstance(bash, dict):
    bash = {}
before = json.dumps(bash)

# Order matters: OpenCode takes the LAST matching rule. Start with the managed catch-all,
# then write canonical allow/ask/deny actions; the whole bash map is brain-managed.
defaults = src.get("defaults", {})
bash = {"*": "allow" if defaults.get("bash_without_prompt") else "ask"}
for pat in bash_patterns("allow"):
    bash.pop(pat, None)
    bash[pat] = "allow"
for pat in bash_patterns("ask"):
    bash.pop(pat, None)
    bash[pat] = "ask"
for pat in bash_patterns("deny"):
    bash.pop(pat, None)
    bash[pat] = "deny"
perm["bash"] = bash

# defaults.edit_without_prompt -> permission.edit. Written explicitly even though OpenCode
# already defaults to "allow", so the setting is visible and verify.sh can check all three.
edit_before = perm.get("edit")
perm["edit"] = "allow" if defaults.get("edit_without_prompt") else "ask"
edit_changed = perm["edit"] != edit_before

if json.dumps(bash) != before or edit_changed:
    p.parent.mkdir(parents=True, exist_ok=True)
    if had_comments:
        print("  note     comments in opencode.jsonc dropped by rewrite (pre-copy is in the backup dir)")
    p.write_text(json.dumps(cfg, indent=2) + "\n")
    print(f'  merged   permission.bash now pins {len(bash)} rule(s), edit="{perm["edit"]}"')
else:
    print("  ok       opencode permission.bash already in sync")
PYEOF
  if [ -f "$BACKUP_DIR/opencode-perms.jsonc" ] && cmp -s "$OC_CFG" "$BACKUP_DIR/opencode-perms.jsonc"; then
    rm -f "$BACKUP_DIR/opencode-perms.jsonc"
  fi
fi

# --- 5e claude PreToolUse hook: quoted-heredoc -> scratchpad rewrite --------
echo "[5e] claude PreToolUse heredoc-rewrite hook"
HR_SH="$AGENTS_HOME/hooks/heredoc-rewrite.sh"
HR_PY="$AGENTS_HOME/hooks/heredoc-rewrite.py"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [ ! -f "$HR_SH" ] || [ ! -f "$HR_PY" ]; then
  log "WARNING: hooks/heredoc-rewrite.{sh,py} missing — copy ~/.agents fully; skipping PreToolUse wiring"
else
  chmod +x "$HR_SH" "$HR_PY"
  [ -f "$CLAUDE_SETTINGS" ] && cp -p "$CLAUDE_SETTINGS" "$BACKUP_DIR/claude-settings-heredoc.json"
  CLAUDE_SETTINGS="$CLAUDE_SETTINGS" python3 - <<'PYEOF'
import json, os, pathlib
p = pathlib.Path(os.environ["CLAUDE_SETTINGS"])
cfg = json.loads(p.read_text()) if p.exists() else {}
cmd = 'bash "$HOME/.agents/hooks/heredoc-rewrite.sh"'
hooks = cfg.setdefault("hooks", {})
pre = hooks.setdefault("PreToolUse", [])
existing = [h.get("command", "") for g in pre for h in g.get("hooks", [])]
if any("heredoc-rewrite" in c for c in existing):
    print("  ok       PreToolUse heredoc-rewrite already wired")
else:
    entry = {"type": "command", "command": cmd, "timeout": 5,
             "statusMessage": "heredoc -> scratchpad rewrite"}
    pre.append({"matcher": "Bash", "hooks": [entry]})
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(cfg, indent=2) + "\n")
    print("  wired    PreToolUse -> heredoc-rewrite.sh")
PYEOF
  if [ -f "$BACKUP_DIR/claude-settings-heredoc.json" ] && cmp -s "$CLAUDE_SETTINGS" "$BACKUP_DIR/claude-settings-heredoc.json"; then
    rm -f "$BACKUP_DIR/claude-settings-heredoc.json"
  fi
fi

# --- 6 symlink guard (source: hooks/check-links.sh) -------------------------
echo "[6] symlink guard script (refresh from hooks/)"
LINK_GUARD_SRC="$AGENTS_HOME/hooks/check-links.sh"
mkdir -p "$GUARD_DIR"
if [ -f "$GUARD_DIR/check-links.sh" ] && ! cmp -s "$LINK_GUARD_SRC" "$GUARD_DIR/check-links.sh"; then
  cp -p "$GUARD_DIR/check-links.sh" "$BACKUP_DIR/check-links.sh" 2>/dev/null || true
fi
if [ ! -f "$LINK_GUARD_SRC" ]; then
  log "WARNING: $LINK_GUARD_SRC missing — copy ~/.agents fully; skipping symlink guard"
else
  cp -p "$LINK_GUARD_SRC" "$GUARD_DIR/check-links.sh"
  chmod +x "$GUARD_DIR/check-links.sh" "$LINK_GUARD_SRC"
  log "refreshed $GUARD_DIR/check-links.sh (from hooks/)"
fi

# --- 7 claude/grok memory residue guard ------------------------------------
echo "[7] claude-memory-guard (residue catcher)"
if [ ! -f "$MEM_GUARD_SRC" ]; then
  log "WARNING: $MEM_GUARD_SRC missing — copy ~/.agents fully; skipping memory guard"
else
  mkdir -p "$MEM_GUARD_DIR"
  if [ -f "$MEM_GUARD_DIR/check-memory.sh" ] && ! cmp -s "$MEM_GUARD_SRC" "$MEM_GUARD_DIR/check-memory.sh"; then
    cp -p "$MEM_GUARD_DIR/check-memory.sh" "$BACKUP_DIR/check-memory.sh" 2>/dev/null || true
  fi
  cp -p "$MEM_GUARD_SRC" "$MEM_GUARD_DIR/check-memory.sh"
  chmod +x "$MEM_GUARD_DIR/check-memory.sh" "$MEM_GUARD_SRC"
  log "refreshed $MEM_GUARD_DIR/check-memory.sh (from hooks/)"
fi

# --- 7b tool updater (source: updater/) --------------------------------------
echo "[7b] tool updater (refresh from updater/)"
if [ -d "$UPD_SRC" ]; then
  mkdir -p "$UPD_DIR"
  for s in boot-check.sh update-apps.sh on-resume.sh refresh-inventory.py; do
    if [ -f "$UPD_SRC/$s" ]; then
      if [ -f "$UPD_DIR/$s" ] && ! cmp -s "$UPD_SRC/$s" "$UPD_DIR/$s"; then
        cp -p "$UPD_DIR/$s" "$BACKUP_DIR/updater-$s" 2>/dev/null || true
      fi
      cp -p "$UPD_SRC/$s" "$UPD_DIR/$s"
      chmod +x "$UPD_DIR/$s" "$UPD_SRC/$s"
      log "refreshed $UPD_DIR/$s (from updater/)"
    else
      log "WARNING: updater/$s missing"
    fi
  done
  # Root-installed systemd shim needs an explicit privileged install. verify.sh
  # checks byte identity so source changes cannot leave a stale hook silently.
  if [ -f "$UPD_SRC/system-sleep-shim.sh" ]; then
    chmod +x "$UPD_SRC/system-sleep-shim.sh"
  fi
else
  log "WARNING: updater/ missing — copy ~/.agents fully; skipping updater install"
fi

# --- 7c stray-merge (AI) hook: source hooks/merge-strays.sh ------------------
echo "[7c] stray-merge hook (AI merge of quarantined strays)"
MERGE_SRC="$AGENTS_HOME/hooks/merge-strays.sh"
if [ -f "$MERGE_SRC" ]; then
  if [ -f "$GUARD_DIR/merge-strays.sh" ] && ! cmp -s "$MERGE_SRC" "$GUARD_DIR/merge-strays.sh"; then
    cp -p "$GUARD_DIR/merge-strays.sh" "$BACKUP_DIR/merge-strays.sh" 2>/dev/null || true
  fi
  cp -p "$MERGE_SRC" "$GUARD_DIR/merge-strays.sh"
  chmod +x "$GUARD_DIR/merge-strays.sh" "$MERGE_SRC"
  log "refreshed $GUARD_DIR/merge-strays.sh (from hooks/)"
else
  log "WARNING: hooks/merge-strays.sh missing — skip"
fi

# --- 8 crontab ---------------------------------------------------------------
echo "[8] crontab entries"
if [ "$SKIP_CRON" = 1 ]; then
  log "skipped (SKIP_CRON=1)"
elif ! command -v crontab >/dev/null; then
  log "WARNING: crontab not found — add manually:"
  log "  @daily  $GUARD_DIR/check-links.sh"
  log "  @reboot $GUARD_DIR/check-links.sh"
  log "  @daily  $MEM_GUARD_DIR/check-memory.sh"
  log "  @reboot $MEM_GUARD_DIR/check-memory.sh"
  log "  @reboot $UPD_DIR/boot-check.sh"
else
  # CRITICAL: never feed `crontab -` an empty stdin (installs an empty crontab).
  # All greps carry `|| true` so set -e/pipefail cannot abort before crontab -.
  CT_OLD="$(crontab -l 2>/dev/null || true)"
  CT_OLD="$(printf '%s\n' "$CT_OLD" | grep -v -E 'agents-symlink-guard|claude-memory-guard|ai-terminal-tools-update-on-boot' || true)"
  { printf '%s\n' "$CT_OLD"
    printf '@daily %s\n@reboot %s\n@daily %s\n@daily %s\n@reboot %s\n@reboot %s\n' \
      "$GUARD_DIR/check-links.sh" "$GUARD_DIR/check-links.sh" \
      "$GUARD_DIR/merge-strays.sh" \
      "$MEM_GUARD_DIR/check-memory.sh" "$MEM_GUARD_DIR/check-memory.sh" \
      "$UPD_DIR/boot-check.sh"
  } | grep -v '^$' | crontab -
  log "installed symlink-guard (@daily + @reboot) + stray-merge (@daily) + memory-guard (@daily + @reboot) + tool updater (@reboot)"
fi

# --- gpg hooks (direct-reference from ~/.agents, like the claude hook) -------
echo "[gpg] unlock hooks (dedicated gpg-signing collection, nothing installed elsewhere)"
for h in gpg-agent-unlock.sh gpg-store-passphrase.sh gpg-keyring.py gpg-signing-key.sh gpg-git.sh; do
  if [ -f "$AGENTS_HOME/hooks/$h" ]; then
    chmod +x "$AGENTS_HOME/hooks/$h"
    log "ready   hooks/$h"
  else
    log "WARNING: hooks/$h missing"
  fi
done
if command -v git >/dev/null && [ -x "$AGENTS_HOME/hooks/gpg-git.sh" ]; then
  git config --global gpg.program "$AGENTS_HOME/hooks/gpg-git.sh"
  log "git     gpg.program → hooks/gpg-git.sh (loopback, no pinentry GUI)"
fi

# --- checkpoint script (direct-reference, called by the checkpoint_project trigger) --
echo "[checkpoint] checkpoint.sh (git half of checkpoint_project)"
CP_SRC="$AGENTS_HOME/hooks/checkpoint.sh"
if [ -f "$CP_SRC" ]; then
  chmod +x "$CP_SRC"
  if bash -n "$CP_SRC" 2>/dev/null; then
    log "ready   hooks/checkpoint.sh"
  else
    log "WARNING: hooks/checkpoint.sh has a syntax error"
  fi
else
  log "WARNING: hooks/checkpoint.sh missing"
fi

# --- staleness watch (direct-reference, armed beside every detached run) ------
echo "[watch-stale] watch-stale.sh (staleness watch for detached runs)"
WS_SRC="$AGENTS_HOME/hooks/watch-stale.sh"
if [ -f "$WS_SRC" ]; then
  chmod +x "$WS_SRC"
  if bash -n "$WS_SRC" 2>/dev/null; then
    log "ready   hooks/watch-stale.sh"
  else
    log "WARNING: hooks/watch-stale.sh has a syntax error"
  fi
else
  log "WARNING: hooks/watch-stale.sh missing"
fi

# --- boot dashboard autostart -----------------------------------------------
echo "[boot-dashboard] install XDG autostart (Wayland + X11)"
BD="$AGENTS_HOME/boot-dashboard"
if [ -d "$BD" ]; then
  chmod +x "$BD/dashboard.sh" "$BD/launch.sh" 2>/dev/null || true
  mkdir -p "$HOME/.config/autostart"
  DESK_SRC="$BD/agents-boot-status.desktop"
  DESK_DST="$HOME/.config/autostart/agents-boot-status.desktop"
  if [ -f "$DESK_SRC" ]; then
    # Rewrite Exec= to this machine's home (portable if user name differs)
    sed "s|^Exec=.*|Exec=$BD/launch.sh|" "$DESK_SRC" > "$DESK_DST"
    chmod 644 "$DESK_DST"
    log "autostart $DESK_DST"
    if command -v systemctl >/dev/null 2>&1; then
      if systemctl --user daemon-reload >/dev/null 2>&1; then
        log "reloaded user systemd generators"
      else
        log "note     no active user systemd manager; autostart applies next login"
      fi
    fi
  else
    log "WARNING: $DESK_SRC missing"
  fi
else
  log "WARNING: boot-dashboard/ missing — skip autostart"
fi

# --- inventory refresh (machine-local, gitignored) --------------------------
echo "[inventory] refresh inventory.local.md (not committed — versions differ per machine)"
INV_REFRESH="$UPD_SRC/refresh-inventory.py"
[ -f "$INV_REFRESH" ] || die "$INV_REFRESH missing"
AGENTS_HOME="$AGENTS_HOME" INVENTORY_MD="$AGENTS_HOME/inventory.local.md" \
  INVENTORY_SOURCE=setup python3 "$INV_REFRESH" \
  || die "inventory.local.md refresh failed"

# --- verify (full ecosystem check) ------------------------------------------
echo "[verify] running guards smoke + verify.sh"
"$GUARD_DIR/check-links.sh" || true
if [ -x "$MEM_GUARD_DIR/check-memory.sh" ]; then
  "$MEM_GUARD_DIR/check-memory.sh" || true
fi
python3 -c "import tomllib, os; tomllib.load(open(os.path.expanduser('$HOME/.grok/config.toml'), 'rb')); print('  config.toml: valid TOML')"

VERIFY="$AGENTS_HOME/verify.sh"
if [ -x "$VERIFY" ]; then
  if ! bash "$VERIFY"; then
    die "verify.sh reported FAIL"
  fi
else
  die "$VERIFY missing — ecosystem cannot be verified"
fi

echo "== done. backups (if anything was replaced): $BACKUP_DIR =="
echo "Rule: after ANY edit under $AGENTS_HOME → re-run this setup.sh (syncs installs + verify)."
