#!/usr/bin/env bash
# config-test.sh — fixtures for the scripts that edit a tool's config file.
#
#   bash hooks/config-test.sh
#
# hooks/grok-config.py and hooks/local-rules.py run on scratch files, and each
# result is read back through a parser. Until 2026-11-21 step 2 of setup.sh
# edited config.toml inline and wrote invalid TOML for the header, dotted-key,
# and inline-table cases below. One line per case: `ok <what>` or
# `FAIL <what>`. Exit 1 when any case fails. verify.sh replays the lines.
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")" && pwd -P)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# has PATTERN... — "does the piped text match", for use after a pipe. It reads
# all of its input before it searches. grep -q stops at the first match, the
# writer then dies of SIGPIPE, and under pipefail the pipeline is false although
# the text was found (and `! writer | grep -q X` is then true although X is
# there). Some greps stop early with output to /dev/null as well, so the input
# is taken whole first and grep reads it from a here-string.
has() {
  local _has_text
  _has_text="$(cat)"
  grep -q "$@" <<<"$_has_text"
}
fails=0
pass() { echo "ok $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

parses() { python3 -c 'import sys, tomllib; tomllib.loads(open(sys.argv[1]).read())' "$1" 2>/dev/null; }
# switches_set FILE — the three values, read back through a TOML parser.
switches_set() {
  python3 - "$1" <<'PY' 2>/dev/null
import sys, tomllib
d = tomllib.loads(open(sys.argv[1]).read())
ok = d["compat"]["claude"]["agents"] is False and d["compat"]["claude"]["rules"] is False \
     and d["memory"]["enabled"] is False
sys.exit(0 if ok else 1)
PY
}

# --- grok-config.py switches ----------------------------------------------------
n=0
grok_case() {
  local label="$1" body="$2" keep="$3" f rc=0
  n=$((n + 1))
  f="$T/grok-$n.toml"
  printf '%s' "$body" > "$f"
  python3 "$HOOKS/grok-config.py" switches "$f" >/dev/null 2>"$T/err" || rc=$?
  if [ "$rc" -eq 0 ] && parses "$f" && switches_set "$f" && grep -qF -- "$keep" "$f"; then
    pass "$label"
  else
    fail "$label (exit $rc: $(head -c 200 "$T/err"))"
  fi
}
grok_case "grok config: no file yet gets the three switches" '' ''
grok_case "grok config: a header with a comment after it is edited in place" \
  $'[memory] # my note\nenabled = true\nmodel = "x"\n' 'model = "x"'
grok_case "grok config: an indented header is edited in place" \
  $'  [memory]\n  enabled = true\n' '[memory]'
grok_case "grok config: a dotted key at the top of the file is edited in place" \
  $'memory.enabled = true\ntheme = "dark"\n\n[ui]\nfont = 12\n' 'theme = "dark"'
grok_case "grok config: a dotted key under a parent table is edited in place" \
  $'[compat]\nclaude.agents = true\nclaude.rules = true\nother = 1\n' 'other = 1'
grok_case "grok config: a value keeps the comment after it" \
  $'[memory]\nenabled = true # was on\n' '# was on'
grok_case "grok config: the other tables and keys are kept" \
  $'[ui]\npermission_mode = "ask"\n\n[permission]\nallow = [\n  "Bash(ls)",\n]\n' '"Bash(ls)",'

# A form the line editor cannot reach must stop, and leave the file as it was.
f="$T/inline.toml"
printf 'memory = { enabled = true }\n' > "$f"
cp "$f" "$T/inline.before"
rc=0; python3 "$HOOKS/grok-config.py" switches "$f" >/dev/null 2>"$T/err" || rc=$?
if [ "$rc" -eq 1 ] && cmp -s "$f" "$T/inline.before" && grep -q 'by hand' "$T/err"; then
  pass "grok config: an inline table stops the edit, names the key, and the file is unchanged"
else
  fail "grok config: an inline table was edited into a broken file (exit $rc)"
fi
f="$T/broken.toml"
printf '[memory\nenabled = true\n' > "$f"
cp "$f" "$T/broken.before"
rc=0; python3 "$HOOKS/grok-config.py" switches "$f" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 1 ] && cmp -s "$f" "$T/broken.before"; then
  pass "grok config: a file that does not parse is left alone (exit 1)"
else
  fail "grok config: a file that does not parse was rewritten (exit $rc)"
fi

# --check is the preflight: it writes nothing, and it names a [permission] key setup would drop.
f="$T/check.toml"
printf '[memory]\nenabled = true\n' > "$f"
cp "$f" "$T/check.before"
rc=0; python3 "$HOOKS/grok-config.py" switches "$f" --check >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ] && cmp -s "$f" "$T/check.before"; then
  pass "grok config: --check passes a file it can edit and writes nothing"
else
  fail "grok config: --check wrote the file or refused a good one (exit $rc)"
fi
printf '[permission]\nallow = []\nmy_own_key = true\n' > "$f"
rc=0; python3 "$HOOKS/grok-config.py" switches "$f" --check >/dev/null 2>"$T/err" || rc=$?
if [ "$rc" -eq 1 ] && grep -q 'my_own_key' "$T/err"; then
  pass "grok config: --check names a [permission] key that setup would stop on"
else
  fail "grok config: --check passed a [permission] key that stops setup midway (exit $rc)"
fi

# --- local-rules.py -------------------------------------------------------------
lr_home() {
  local h
  h="$(mktemp -d -p "$T")"
  mkdir -p "$h/.agents" "$h/.config/opencode" "$h/backup"
  printf '%s\n' "$h"
}
h="$(lr_home)"
printf '{ "caveman": "off" \n' > "$h/.agents/local.json"
rc=0; python3 "$HOOKS/local-rules.py" apply --home "$h" >/dev/null 2>"$T/err" || rc=$?
if [ "$rc" -eq 2 ] && grep -q 'local.json' "$T/err" && [ ! -e "$h/.claude/rules/1config-local.md" ]; then
  pass "local.json that is not valid JSON stops with exit 2, and no rule is written"
else
  fail "a broken local.json was read as 'no override' (exit $rc)"
fi
h="$(lr_home)"
printf '{ "caveman": "of" }\n' > "$h/.agents/local.json"
rc=0; python3 "$HOOKS/local-rules.py" apply --home "$h" >/dev/null 2>"$T/err" || rc=$?
if [ "$rc" -eq 2 ] && grep -q 'caveman' "$T/err"; then
  pass "a caveman level that is not off, lite, full, or ultra stops with exit 2"
else
  fail "a misspelled caveman level was read as 'full' (exit $rc)"
fi
h="$(lr_home)"
printf '{ "caveman": "full" }\n' > "$h/.agents/local.json"
rc=0; python3 "$HOOKS/local-rules.py" apply --home "$h" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && pass "caveman full, the default, is accepted" || fail "caveman full was refused (exit $rc)"

# The rewrite of opencode.jsonc drops comments. The file as it was goes to the backup first.
h="$(lr_home)"
printf '{ "caveman": "lite" }\n' > "$h/.agents/local.json"
printf '{\n  // my own comment\n  "model": "x"\n}\n' > "$h/.config/opencode/opencode.jsonc"
rc=0; python3 "$HOOKS/local-rules.py" apply --home "$h" --backup-dir "$h/backup" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ] && grep -q '1config-local.md' "$h/.config/opencode/opencode.jsonc" \
   && grep -q 'my own comment' "$h/backup/opencode-local-rules.jsonc" 2>/dev/null; then
  pass "opencode.jsonc is saved to the backup before local-rules rewrites it"
else
  fail "opencode.jsonc was rewritten with no saved copy (exit $rc)"
fi

# --- the preflight asks before setup writes -------------------------------------
h="$(mktemp -d -p "$T")"
mkdir -p "$h/.grok"
printf '[permission]\nallow = []\nmy_own_key = true\n' > "$h/.grok/config.toml"
cp "$h/.grok/config.toml" "$T/pf.before"
rc=0; HOME="$h" bash "$HOOKS/preflight.sh" >"$T/pf.out" 2>&1 || rc=$?
if [ "$rc" -eq 1 ] && grep -q 'cannot edit ~/.grok/config.toml' "$T/pf.out" && grep -q 'my_own_key' "$T/pf.out" \
   && cmp -s "$h/.grok/config.toml" "$T/pf.before"; then
  pass "preflight stops on a Grok config that setup would stop on midway, and writes nothing"
else
  fail "preflight did not name a Grok config that stops setup midway (exit $rc)"
fi

# --- platform.sh: the package family, and the install line that goes with it ----
# shellcheck disable=SC1091
. "$HOOKS/platform.sh"
plat_case() {
  local label="$1" body="$2" has_omarchy="$3" want_family="$4" want_hint="$5" f="$T/os-release"
  printf '%s' "$body" > "$f"
  platform_detect "$f" "$has_omarchy"
  if [ "$FAMILY" = "$want_family" ] && printf '%s\n' "$HINT" | has -F -- "$want_hint"; then
    pass "$label"
  else
    fail "$label (family $FAMILY, hint: $HINT)"
  fi
}
plat_case "platform: Ubuntu is the debian family and gets the apt line" \
  $'NAME="Ubuntu"\nID=ubuntu\nID_LIKE=debian\n' 0 debian 'apt-get install'
plat_case "platform: a Debian derivative is found through ID_LIKE" \
  $'ID=pop\nID_LIKE="ubuntu debian"\n' 0 debian 'texlive-full'
plat_case "platform: Arch gets the pacman line" $'ID=arch\n' 0 arch 'pacman -S'
plat_case "platform: Omarchy wins over the os-release file" $'ID=arch\n' 1 omarchy 'omarchy pkg add'
plat_case "platform: an unknown system gets the plain list, not another system's command" \
  $'ID=fedora\n' 0 unknown 'install python3'

[ "$fails" -eq 0 ]
