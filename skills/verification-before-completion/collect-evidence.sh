#!/usr/bin/env bash
# Run a project's verification commands and print an evidence table.
# Usage: collect-evidence.sh [-C dir] [-n|--dry-run] [--tail N] [--cmd CMD]...
#
# Commands come from the first source that has any:
#   1. --cmd CMD (repeatable)
#   2. <dir>/.verify, one shell command per line, # comments
#   3. detection: package.json scripts (test lint typecheck build, runner picked
#      by lockfile), Makefile test/check, cargo test/clippy, go vet/test,
#      ruff/pytest, mise tasks, just recipes
#
# Exit: 0 all passed (or dry-run listed something), 1 a command failed,
#       2 nothing to run, 64 usage. No network, no installs.
# Bash 3.2 safe (macOS): no associative arrays, no mapfile.

set -u

DIR="."
DRY=0
TAIL=20
CMDS=()
ARGS_CMDS=()
SOURCE=""

usage() {
  sed -n '2,13s/^# \{0,1\}//p' "$0"
}

while [ $# -gt 0 ]; do
  case "$1" in
    -C) [ $# -ge 2 ] || { usage >&2; exit 64; }; DIR="$2"; shift 2 ;;
    -n|--dry-run) DRY=1; shift ;;
    --tail) [ $# -ge 2 ] || { usage >&2; exit 64; }; TAIL="$2"; shift 2 ;;
    --cmd) [ $# -ge 2 ] || { usage >&2; exit 64; }; ARGS_CMDS+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "collect-evidence: unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

case "$TAIL" in ''|*[!0-9]*) echo "collect-evidence: --tail wants a number" >&2; exit 64 ;; esac
[ -d "$DIR" ] || { echo "collect-evidence: not a directory: $DIR" >&2; exit 64; }
DIR="$(cd "$DIR" && pwd)"

add() { CMDS+=("$1"); }
has() { command -v "$1" >/dev/null 2>&1; }

# Body of the "scripts" object in package.json, flattened to one line.
# shortcut: text scan, not a JSON parser; a "}" inside a script value ends the block early.
pkg_scripts() {
  tr '\n' ' ' <"$DIR/package.json" | sed -n 's/.*"scripts"[[:space:]]*:[[:space:]]*{\([^}]*\)}.*/\1/p'
}

detect_node() {
  [ -f "$DIR/package.json" ] || return 0
  local pm=npm body s
  if [ -f "$DIR/bun.lockb" ] || [ -f "$DIR/bun.lock" ]; then pm=bun
  elif [ -f "$DIR/pnpm-lock.yaml" ]; then pm=pnpm
  elif [ -f "$DIR/yarn.lock" ]; then pm=yarn
  fi
  body="$(pkg_scripts)"
  for s in lint typecheck build test; do
    printf '%s' "$body" | grep -Eq "\"$s\"[[:space:]]*:" || continue
    # npm init's placeholder test always fails; it proves nothing.
    if [ "$s" = test ] && printf '%s' "$body" | grep -q 'Error: no test specified'; then continue; fi
    add "$pm run $s"
  done
}

detect_make() {
  local f t
  for f in GNUmakefile makefile Makefile; do
    [ -f "$DIR/$f" ] || continue
    for t in check test; do
      grep -Eq "^${t}[[:space:]]*:" "$DIR/$f" && add "make $t"
    done
    return 0
  done
}

detect_rust() {
  [ -f "$DIR/Cargo.toml" ] || return 0
  # clippy is an optional component; only claim it when it is installed.
  if has cargo && cargo clippy --version >/dev/null 2>&1; then add "cargo clippy --all-targets -- -D warnings"; fi
  add "cargo test"
}

detect_go() {
  [ -f "$DIR/go.mod" ] || return 0
  add "go vet ./..."
  add "go test ./..."
}

detect_python() {
  local py=0 f
  for f in pyproject.toml setup.py setup.cfg requirements.txt; do [ -f "$DIR/$f" ] && py=1; done
  if [ -f "$DIR/ruff.toml" ] || [ -f "$DIR/.ruff.toml" ] ||
     { [ -f "$DIR/pyproject.toml" ] && grep -q '^\[tool\.ruff' "$DIR/pyproject.toml"; }; then
    add "ruff check ."
  fi
  if [ -f "$DIR/pytest.ini" ] || [ -f "$DIR/conftest.py" ] ||
     { [ -f "$DIR/pyproject.toml" ] && grep -q '^\[tool\.pytest' "$DIR/pyproject.toml"; } ||
     { [ -f "$DIR/setup.cfg" ] && grep -q '^\[tool:pytest\]' "$DIR/setup.cfg"; } ||
     { [ -f "$DIR/tox.ini" ] && grep -q '^\[pytest\]' "$DIR/tox.ini"; } ||
     { [ "$py" = 1 ] && [ -d "$DIR/tests" ]; }; then
    add "pytest -q"
  fi
}

detect_mise() {
  local f t
  for f in mise.toml .mise.toml; do
    [ -f "$DIR/$f" ] || continue
    for t in lint typecheck build check test; do
      grep -Eq "^\[tasks\.\"?$t\"?\]" "$DIR/$f" && add "mise run $t"
    done
    return 0
  done
}

detect_just() {
  local f t
  for f in justfile Justfile .justfile; do
    [ -f "$DIR/$f" ] || continue
    for t in lint typecheck build check test; do
      grep -Eq "^@?$t([[:space:]]+[^:]*)?:([^=]|$)" "$DIR/$f" && add "just $t"
    done
    return 0
  done
}

if [ ${#ARGS_CMDS[@]} -gt 0 ]; then
  SOURCE="--cmd"
  CMDS=("${ARGS_CMDS[@]}")
elif [ -f "$DIR/.verify" ]; then
  SOURCE=".verify"
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    case "$line" in ''|'#'*) continue ;; esac
    add "$line"
  done <"$DIR/.verify"
else
  SOURCE="detected"
  detect_node; detect_make; detect_rust; detect_go; detect_python; detect_mise; detect_just
fi

echo "verification evidence: $DIR (source: $SOURCE)"

if [ ${#CMDS[@]} -eq 0 ]; then
  if [ "$SOURCE" = ".verify" ]; then
    echo "NOTHING TO RUN: .verify has no commands."
  else
    echo "NOTHING DETECTED: no package.json script (test lint typecheck build), Makefile test/check,"
    echo "Cargo.toml, go.mod, ruff/pytest config, mise task, or just recipe."
  fi
  echo "Pass --cmd CMD or write one command per line in $DIR/.verify. Nothing was verified."
  exit 2
fi

if [ "$DRY" = 1 ]; then
  i=0
  for c in "${CMDS[@]}"; do i=$((i + 1)); printf '%2d  %s\n' "$i" "$c"; done
  echo "dry run: ${#CMDS[@]} command(s) listed, none run. Nothing was verified."
  exit 0
fi

now_ms() {
  local t
  t="$(date +%s%N 2>/dev/null)"
  case "$t" in *N|'') echo $(( $(date +%s) * 1000 )) ;; *) echo $(( t / 1000000 )) ;; esac
}

LOGS="$(mktemp -d "${TMPDIR:-/tmp}/collect-evidence.XXXXXX")"
trap 'rm -rf "$LOGS"' EXIT

ROWS=()
STATUS=()
pass=0 fail=0 i=0
for c in "${CMDS[@]}"; do
  i=$((i + 1))
  t0="$(now_ms)"
  # CI=1 keeps watch-mode runners (vitest, jest) from waiting on a terminal.
  ( cd "$DIR" && CI="${CI:-1}" bash -c "$c" ) </dev/null >"$LOGS/$i.log" 2>&1
  rc=$?
  t1="$(now_ms)"
  ms=$((t1 - t0))
  secs="$((ms / 1000)).$(printf '%01d' $(((ms % 1000) / 100)))s"
  if [ "$rc" -eq 0 ]; then st=PASS; pass=$((pass + 1)); else st=FAIL; fail=$((fail + 1)); fi
  [ "$rc" -eq 127 ] && st=MISSING
  STATUS+=("$st")
  ROWS+=("$(printf '%2d  %-7s  %4s  %7s  %s' "$i" "$st" "$rc" "$secs" "$c")")
done

printf '%2s  %-7s  %4s  %7s  %s\n' "#" "status" "exit" "time" "command"
for r in "${ROWS[@]}"; do printf '%s\n' "$r"; done

i=0
for c in "${CMDS[@]}"; do
  i=$((i + 1))
  [ "${STATUS[$((i - 1))]}" = PASS ] && continue
  echo "--- #$i $c: last $TAIL lines ---"
  tail -n "$TAIL" "$LOGS/$i.log"
done

echo "result: $pass passed, $fail failed, ${#CMDS[@]} run"
[ "$fail" -eq 0 ]
