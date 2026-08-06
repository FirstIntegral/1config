#!/usr/bin/env bash
# verify.sh — consistency check for the whole ~/.agents ecosystem.
#
# After ANY edit under ~/.agents/, run:
#   bash ~/.agents/setup.sh     # install/sync + verify (preferred)
#   bash ~/.agents/verify.sh    # check-only (this file)
#
# Exit 0 = all green. Exit 1 = at least one FAIL.
set -euo pipefail

AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
CANON="$AGENTS_HOME/AGENTS.md"
SETUP="$AGENTS_HOME/SETUP.md"
HOOKS="$AGENTS_HOME/hooks"
GUARD_DIR="$HOME/cron-jobs/agents-symlink-guard"
MEM_GUARD_DIR="$HOME/cron-jobs/claude-memory-guard"
UPD_DIR="$HOME/cron-jobs/ai-terminal-tools-update-on-boot"
UPD_SRC="$AGENTS_HOME/updater"
TEMPLATE="$AGENTS_HOME/project-template"
fail=0
warns=0

ok()   { echo "  OK    $*"; }
bad()  { echo "  FAIL  $*"; fail=1; }
note() { echo "  WARN  $*"; warns=$((warns + 1)); }
info() { echo "  INFO  $*"; }               # transient state, not a defect — never counts as a warning

echo "== ~/.agents verify — $(date) =="

# --- core files ------------------------------------------------------------
echo "[core]"
[ -f "$CANON" ]  && ok "canonical $CANON" || bad "missing canonical $CANON"
[ -f "$SETUP" ]  && ok "SETUP.md" || bad "missing SETUP.md"
[ -x "$AGENTS_HOME/setup.sh" ] && ok "setup.sh executable" || bad "setup.sh missing or not executable"
[ -x "$AGENTS_HOME/verify.sh" ] && ok "verify.sh executable" || bad "verify.sh missing or not executable"
[ -x "$AGENTS_HOME/sync.sh" ] && ok "sync.sh executable (brain → github)" || bad "sync.sh missing or not executable"
if git -C "$AGENTS_HOME" rev-parse --git-dir >/dev/null 2>&1; then
  brain_remote="$(git -C "$AGENTS_HOME" remote get-url origin 2>/dev/null || true)"
  [ -n "$brain_remote" ] && ok "brain repo origin → $brain_remote" || bad "brain repo has no origin remote"
  # Dirty/ahead is normal mid-edit (verify runs before the commit), so it is INFO, not a warning.
  brain_dirty="$(git -C "$AGENTS_HOME" status --porcelain)"
  brain_ahead="$(git -C "$AGENTS_HOME" log origin/main..main --oneline 2>/dev/null || true)"
  if [ -z "$brain_dirty" ] && [ -z "$brain_ahead" ]; then
    ok "brain repo clean + pushed"
  else
    info "brain repo not yet pushed ($(printf '%s' "$brain_dirty" | grep -c . || true) dirty, $(printf '%s' "$brain_ahead" | grep -c . || true) unpushed) — finish with: bash ~/.agents/sync.sh -m \"…\""
  fi
else
  bad "$AGENTS_HOME is not a git repo (brain must be versioned + pushed)"
fi
[ -d "$TEMPLATE" ] && ok "project-template/" || bad "project-template/ missing"
for f in AGENTS.md session_compact.md session_transcript.md docs/DECISIONS.md .gitignore; do
  [ -e "$TEMPLATE/$f" ] && ok "template $f" || bad "template missing $f"
done
[ -f "$AGENTS_HOME/permissions.json" ] && ok "permissions.json (canonical, all 3 tools)" || bad "permissions.json missing"
PAPER_TPL="$AGENTS_HOME/paper-template"
if [ -d "$PAPER_TPL" ]; then
  for f in main.tex build.sh; do
    [ -e "$PAPER_TPL/$f" ] && ok "paper-template $f" || bad "paper-template missing $f"
  done
  [ -x "$PAPER_TPL/build.sh" ] || note "paper-template/build.sh not executable"
  # No-references rule: the template must never grow a bibliography again.
  if grep -qE '\\(printbibliography|addbibresource|cite\{)|biblatex' "$PAPER_TPL/main.tex" || [ -e "$PAPER_TPL/refs.bib" ]; then
    bad "paper-template has bibliography machinery (papers must be reference-free)"
  else
    ok "paper-template reference-free"
  fi
else
  bad "paper-template/ missing (writepaper_project has no scaffold)"
fi
for f in check-links.sh check-claude-memory.sh load-project-agents.sh gpg-agent-unlock.sh gpg-store-passphrase.sh merge-strays.sh; do
  [ -f "$HOOKS/$f" ] && ok "hooks/$f" || bad "hooks/$f missing"
  [ -x "$HOOKS/$f" ] || note "hooks/$f not executable"
done
BD="$AGENTS_HOME/boot-dashboard"
if [ -d "$BD" ]; then
  [ -x "$BD/dashboard.sh" ] && ok "boot-dashboard/dashboard.sh" || bad "boot-dashboard/dashboard.sh missing/not exec"
  [ -x "$BD/launch.sh" ] && ok "boot-dashboard/launch.sh" || bad "boot-dashboard/launch.sh missing/not exec"
  if [ -f "$HOME/.config/autostart/agents-boot-status.desktop" ]; then
    if grep -q 'boot-dashboard/launch.sh' "$HOME/.config/autostart/agents-boot-status.desktop"; then
      ok "autostart agents-boot-status.desktop"
    else
      bad "autostart desktop present but Exec wrong (run setup.sh)"
    fi
  else
    bad "autostart desktop missing (run setup.sh)"
  fi
else
  note "boot-dashboard/ missing"
fi

# --- symlinks (tool-facing names stay AGENTS.md / CLAUDE.md) ---------------
echo "[symlinks]"
for link in "$HOME/.grok/AGENTS.md" "$HOME/.config/opencode/AGENTS.md" "$HOME/.claude/CLAUDE.md"; do
  if [ -L "$link" ] && [ "$(readlink -f "$link")" = "$CANON" ]; then
    ok "$link → canonical"
  else
    bad "$link not a symlink to $CANON (run setup.sh)"
  fi
done

# --- hooks installed copies must match source byte-for-byte ----------------
echo "[installed guards vs hooks/]"
if [ -f "$HOOKS/check-links.sh" ] && [ -f "$GUARD_DIR/check-links.sh" ]; then
  if cmp -s "$HOOKS/check-links.sh" "$GUARD_DIR/check-links.sh"; then
    ok "symlink guard matches hooks/check-links.sh"
  else
    bad "symlink guard DRIFT — $GUARD_DIR/check-links.sh ≠ hooks/ (run setup.sh)"
  fi
else
  bad "symlink guard install missing (run setup.sh)"
fi
if [ -f "$HOOKS/check-claude-memory.sh" ] && [ -f "$MEM_GUARD_DIR/check-memory.sh" ]; then
  if cmp -s "$HOOKS/check-claude-memory.sh" "$MEM_GUARD_DIR/check-memory.sh"; then
    ok "memory guard matches hooks/check-claude-memory.sh"
  else
    bad "memory guard DRIFT — $MEM_GUARD_DIR/check-memory.sh ≠ hooks/ (run setup.sh)"
  fi
else
  bad "memory guard install missing (run setup.sh)"
fi
if [ -f "$HOOKS/merge-strays.sh" ] && [ -f "$GUARD_DIR/merge-strays.sh" ]; then
  if cmp -s "$HOOKS/merge-strays.sh" "$GUARD_DIR/merge-strays.sh"; then
    ok "stray-merge hook matches hooks/merge-strays.sh"
  else
    bad "stray-merge DRIFT — $GUARD_DIR/merge-strays.sh ≠ hooks/ (run setup.sh)"
  fi
else
  bad "stray-merge install missing (run setup.sh)"
fi

# --- tool updater installed copies must match source byte-for-byte ---------
echo "[updater vs source]"
if [ -d "$UPD_SRC" ]; then
  for s in boot-check.sh update-apps.sh on-resume.sh; do
    if [ -f "$UPD_SRC/$s" ] && [ -f "$UPD_DIR/$s" ]; then
      if cmp -s "$UPD_SRC/$s" "$UPD_DIR/$s"; then
        ok "updater $s matches source"
      else
        bad "updater DRIFT — $UPD_DIR/$s ≠ updater/ (run setup.sh)"
      fi
    else
      bad "updater install missing: $UPD_DIR/$s (run setup.sh)"
    fi
  done
  [ -f "$UPD_SRC/system-sleep-shim.sh" ] && ok "updater system-sleep-shim.sh present" || bad "updater system-sleep-shim.sh missing"
  if [ -f /usr/lib/systemd/system-sleep/ai-terminal-tools-update-resume.sh ]; then
    ok "systemd resume shim installed (root-owned)"
  else
    note "systemd resume shim not installed (needs root once): sudo cp ~/.agents/updater/system-sleep-shim.sh /usr/lib/systemd/system-sleep/"
  fi
else
  bad "updater/ source missing (copy ~/.agents fully)"
fi

# --- gpg unlock hooks --------------------------------------------------------
echo "[gpg hooks]"
if [ -x "$HOOKS/gpg-agent-unlock.sh" ] && [ -x "$HOOKS/gpg-store-passphrase.sh" ]; then
  ok "gpg hooks present + executable"
else
  bad "gpg unlock hooks missing (run setup.sh)"
fi
if [ -d "$AGENTS_HOME/vendor/jeepney" ] && [ -f "$AGENTS_HOME/vendor/jeepney/__init__.py" ]; then
  ok "vendored jeepney present (gpg keyring access)"
else
  bad "vendor/jeepney missing — gpg keyring hooks cannot run"
fi
if [ -d "$BD" ] && grep -q 'gpg-agent-unlock' "$BD/dashboard.sh" 2>/dev/null; then
  ok "boot dashboard runs gpg unlock"
else
  note "boot dashboard does not reference gpg-agent-unlock"
fi

# --- flag names (must not reintroduce bare NEEDS-MERGE as the live flag) ---
echo "[flag names]"
for pair in \
  "$HOOKS/check-links.sh:NEEDS-SYMLINK-MERGE" \
  "$HOOKS/check-claude-memory.sh:NEEDS-MEMORY-MERGE" \
  "$CANON:NEEDS-SYMLINK-MERGE" \
  "$CANON:NEEDS-MEMORY-MERGE" \
  "$SETUP:NEEDS-SYMLINK-MERGE" \
  "$SETUP:NEEDS-MEMORY-MERGE"
do
  file="${pair%%:*}"
  needle="${pair##*:}"
  if grep -qF "$needle" "$file" 2>/dev/null; then
    ok "$needle present in $(basename "$file")"
  else
    bad "$needle missing from $file"
  fi
done
# Live FLAG= assignment must use the new names (legacy migration lines may still say NEEDS-MERGE)
for f in "$HOOKS/check-links.sh" "$HOOKS/check-claude-memory.sh"; do
  if grep -E '^\s*FLAG=' "$f" | grep -q 'NEEDS-SYMLINK-MERGE\|NEEDS-MEMORY-MERGE'; then
    ok "FLAG= uses new name in $(basename "$f")"
  else
    bad "FLAG= still wrong in $f"
  fi
done

# --- SETUP inventory markers -----------------------------------------------
echo "[SETUP inventory]"
if grep -q 'TOOL_INVENTORY_START' "$SETUP" && grep -q 'TOOL_INVENTORY_END' "$SETUP"; then
  ok "TOOL_INVENTORY markers present"
else
  bad "SETUP.md missing TOOL_INVENTORY_START/END markers"
fi

# --- continue_project parity (SETUP must mention residue check) ------------
echo "[doc parity]"
if grep -q 'NEEDS-MEMORY-MERGE' "$SETUP" && grep -q 'continue_project' "$SETUP"; then
  ok "SETUP.md continue_project + memory flag documented"
else
  bad "SETUP.md missing continue_project / NEEDS-MEMORY-MERGE (drift from AGENTS.md)"
fi
for f in "$CANON" "$SETUP"; do
  for needle in checkpoint_project writepaper_project global_brain_update 'Tri-tool parity'; do
    if grep -qF "$needle" "$f"; then
      ok "$needle present in $(basename "$f")"
    else
      bad "$needle missing from $f"
    fi
  done
done
grep -qF 'math@brwsk.xyz' "$CANON" && ok "paper author contact pinned in AGENTS.md" || bad "paper author contact missing from AGENTS.md"
if grep -q 'Residue / conflict check' "$SETUP" || grep -q 'Residue / conflict check' "$CANON"; then
  ok "residue/conflict check wording present"
else
  note "residue/conflict check heading not found (rename?)"
fi

# --- grok config -----------------------------------------------------------
echo "[grok config]"
if command -v python3 >/dev/null; then
  if python3 - <<PY
import tomllib, pathlib, sys
p = pathlib.Path.home() / ".grok" / "config.toml"
if not p.is_file():
    print("missing config.toml"); sys.exit(1)
cfg = tomllib.loads(p.read_text())
mem = cfg.get("memory", {}).get("enabled", True)
cc = cfg.get("compat", {}).get("claude", {})
ok = (mem is False) and (cc.get("agents") is False) and (cc.get("rules") is False)
sys.exit(0 if ok else 2)
PY
  then
    ok "memory.enabled=false, compat.claude agents/rules=false"
  else
    bad "grok config switches wrong (run setup.sh)"
  fi
  [ ! -e "$HOME/.grok/memory" ] && ok "no ~/.grok/memory dir" || bad "~/.grok/memory still exists"
else
  note "python3 missing — skip TOML checks"
fi

# --- permission parity across all three tools -------------------------------
echo "[permission parity]"
PERMS_SRC="$AGENTS_HOME/permissions.json"
if ! command -v python3 >/dev/null; then
  note "python3 missing — skip permission parity check"
elif [ ! -f "$PERMS_SRC" ]; then
  bad "canonical $PERMS_SRC missing"
else
  parity_out="$(PERMS_SRC="$PERMS_SRC" python3 - <<'PY'
import json, os, pathlib, re, tomllib

src = json.loads(pathlib.Path(os.environ["PERMS_SRC"]).read_text()).get("permissions", {})
home = pathlib.Path.home()
want = {b: src.get(b, []) for b in ("allow", "deny")}

def report(tool, missing, total):
    print(f"{'OK' if not missing else 'MISS'}\t{tool}\t{total - len(missing)}/{total}\t{missing[0] if missing else ''}")

# Claude — verbatim rules in permissions.allow / permissions.deny
p = home / ".claude/settings.json"
if p.is_file():
    got = json.loads(p.read_text()).get("permissions", {})
    miss = [r for b in want for r in want[b] if r not in got.get(b, [])]
    report("claude", miss, sum(len(v) for v in want.values()))
else:
    print("SKIP\tclaude\t-\tno settings.json")

# Grok — verbatim rules in [permission] allow / deny
p = home / ".grok/config.toml"
if p.is_file():
    got = tomllib.loads(p.read_text()).get("permission", {})
    miss = [r for b in want for r in want[b] if r not in got.get(b, [])]
    report("grok", miss, sum(len(v) for v in want.values()))
else:
    print("SKIP\tgrok\t-\tno config.toml")

# OpenCode — Bash(X) rules translated into the permission.bash map
p = home / ".config/opencode/opencode.jsonc"
def pats(bucket):
    out = []
    for r in want[bucket]:
        m = re.fullmatch(r"Bash\((.*)\)", r)
        if m and m.group(1) not in ("", "*"):
            out.append(m.group(1))
    return out
if p.is_file():
    text = re.sub(r"^\s*//.*$", "", p.read_text(), flags=re.M)
    got = json.loads(text).get("permission", {}).get("bash", {})
    got = got if isinstance(got, dict) else {}
    miss = [x for x in pats("allow") if got.get(x) != "allow"] + \
           [x for x in pats("deny") if got.get(x) != "deny"]
    report("opencode", miss, len(pats("allow")) + len(pats("deny")))
else:
    print("SKIP\topencode\t-\tno opencode.jsonc")
PY
)" || parity_out=""
  if [ -z "$parity_out" ]; then
    bad "permission parity check failed to run"
  else
    while IFS=$'\t' read -r status tool count detail; do
      case "$status" in
        OK)   ok   "$tool carries all canonical rules ($count)" ;;
        MISS) bad  "$tool missing canonical rules ($count) e.g. $detail — run setup.sh" ;;
        SKIP) note "$tool: $detail" ;;
      esac
    done <<< "$parity_out"
  fi
fi

# --- claude SessionStart hook ----------------------------------------------
echo "[claude hook]"
if command -v python3 >/dev/null && [ -f "$HOME/.claude/settings.json" ]; then
  if python3 - <<'PY'
import json, pathlib, sys
cfg = json.loads(pathlib.Path.home().joinpath(".claude/settings.json").read_text())
starts = cfg.get("hooks", {}).get("SessionStart", [])
cmds = [h.get("command", "") for g in starts for h in g.get("hooks", [])]
sys.exit(0 if any("load-project-agents.sh" in c for c in cmds) else 1)
PY
  then
    ok "SessionStart wires load-project-agents.sh"
  else
    bad "Claude SessionStart missing load-project-agents.sh (run setup.sh)"
  fi
else
  note "no claude settings.json — skip hook check"
fi

# --- crontab ---------------------------------------------------------------
echo "[crontab]"
if command -v crontab >/dev/null; then
  ct="$(crontab -l 2>/dev/null || true)"
  echo "$ct" | grep -q 'agents-symlink-guard/check-links.sh' && ok "crontab symlink guard" || bad "crontab missing symlink guard"
  echo "$ct" | grep -q 'agents-symlink-guard/merge-strays.sh' && ok "crontab stray-merge" || bad "crontab missing stray-merge"
  echo "$ct" | grep -q 'claude-memory-guard/check-memory.sh' && ok "crontab memory guard" || bad "crontab missing memory guard"
  echo "$ct" | grep -q 'ai-terminal-tools-update-on-boot/boot-check.sh' && ok "crontab tool updater" || bad "crontab missing tool updater"
else
  note "crontab not available"
fi

# --- template parity: project-template/ files must equal SETUP.md §5 blocks --
echo "[template parity]"
if command -v python3 >/dev/null; then
  if TEMPLATE="$TEMPLATE" SETUP_MD="$SETUP" python3 - <<'PY'
import os, re, pathlib, sys
setup = pathlib.Path(os.environ["SETUP_MD"]).read_text()
tpl = pathlib.Path(os.environ["TEMPLATE"])
m = re.search(r"## 5\. Per-project standard.*?(?=\n## 5b\.)", setup, re.S)
if not m:
    print("section 5 not found"); sys.exit(1)
blocks = re.findall(r"```[a-z]*\n(.*?)\n```", m.group(0), re.S)
files = ["AGENTS.md", "session_compact.md", "session_transcript.md", "docs/DECISIONS.md", ".gitignore"]
if len(blocks) != len(files):
    print(f"expected {len(files)} template blocks, found {len(blocks)}"); sys.exit(1)
for b, f in zip(blocks, files):
    want = (tpl / f).read_text().rstrip("\n")
    got = b.rstrip("\n")
    if want != got:
        print(f"DRIFT: {f} != SETUP.md section 5 block"); sys.exit(1)
sys.exit(0)
PY
  then
    ok "template files match SETUP.md §5 blocks"
  else
    bad "template DRIFT vs SETUP.md §5 (make project-template/ the source of truth)"
  fi
fi

# --- SETUP inventory vs installed binaries -----------------------------------
echo "[inventory vs installed]"
if command -v python3 >/dev/null; then
  if SETUP_MD="$SETUP" python3 - <<'PY'
import os, re, subprocess, pathlib, sys
text = pathlib.Path(os.environ["SETUP_MD"]).read_text()
m = re.search(r"<!-- TOOL_INVENTORY_START -->(.*?)<!-- TOOL_INVENTORY_END -->", text, re.S)
if not m:
    print("inventory markers missing"); sys.exit(1)
rows = {}
for line in m.group(1).splitlines():
    mm = re.match(r"\|\s*([A-Za-z][A-Za-z ]*?)\s*\|\s*([^\|]+?)\s*\|", line)
    if mm:
        rows[mm.group(1).strip()] = mm.group(2).strip()
def ver(cmd):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=15)
        out = (r.stdout or r.stderr or "").splitlines()
        s = out[0] if out else ""
        mm = re.search(r"(\d+\.\d+\.\d+)", s)
        return mm.group(1) if mm else (s[:40] or "unknown")
    except Exception:
        return "unknown"
expect = {
    "Grok Build": ver("grok --version 2>/dev/null || true"),
    "Claude Code": ver("claude --version 2>/dev/null || true"),
    "OpenCode": ver("opencode --version 2>/dev/null || true"),
}
bad = []
for k, want in expect.items():
    got = rows.get(k, "")
    if "unknown" in (want, got):
        continue
    if want != got:
        bad.append(f"{k}: SETUP.md={got} installed={want}")
if bad:
    print(" | ".join(bad)); sys.exit(1)
sys.exit(0)
PY
  then
    ok "SETUP.md inventory matches installed binaries"
  else
    bad "SETUP.md inventory ≠ installed binaries (run setup.sh)"
  fi
fi

# --- summary ---------------------------------------------------------------
echo
if [ "$fail" -eq 0 ]; then
  echo "== PASS (warnings=$warns) =="
  echo "After future ~/.agents edits:  bash ~/.agents/setup.sh"
  exit 0
else
  echo "== FAIL (fail>=1, warnings=$warns) =="
  echo "Fix issues, then:  bash ~/.agents/setup.sh && bash ~/.agents/verify.sh"
  exit 1
fi
