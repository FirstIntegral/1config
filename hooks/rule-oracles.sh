#!/usr/bin/env bash
# rule-oracles.sh — executable spec for a few decisions that prose used to carry alone.
#
#   bash ~/.agents/hooks/rule-oracles.sh            # run fixtures (verify.sh does this)
#   bash ~/.agents/hooks/rule-oracles.sh resolve --cwd DIR -- NAME
#
# create_project resolution, matching AGENTS.md:
#   empty / whitespace name     -> exit 30 (ask; do not invent a directory)
#   simple name (no '/')        -> $HOME/Projects/<name>
#   name containing '/'         -> that path, resolved, never prefixed with ~/Projects
#   ~/...                       -> $HOME/...
#
# Also fails if a hook, updater, or boot-dashboard script reads session_transcript.md.
# Mentioning the filename (gitignore check, "append, do not read") is allowed.
# Exit 0 fixtures passed. Exit 1 a fixture failed. Exit 2 usage.
# Exit 30 is only the resolve subcommand, for an empty name.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"

resolve_create_project() {
  local cwd="$1" name="$2"
  name="${name#"${name%%[![:space:]]*}"}"
  name="${name%"${name##*[![:space:]]}"}"
  if [ -z "$name" ]; then
    return 30
  fi
  case "$name" in
    /*)
      printf '%s\n' "$name"
      ;;
    *)
      if [ "${name#\~/}" != "$name" ]; then
        printf '%s\n' "$HOME/${name#\~/}"
      elif [ "${name#*/}" != "$name" ]; then
        realpath -m -- "$cwd/$name"
      else
        printf '%s\n' "$HOME/Projects/$name"
      fi
      ;;
  esac
}

# A line is a read when the transcript filename shares the line with a reader.
# Echoing the name, or listing it for git check-ignore, does not match.
transcript_read_re='(^|[[:space:];|&`(])(cat|head|tail|less|more|bat|source)[[:space:]]+[^[:cntrl:]]*session_transcript|<[[:space:]]*[^[:space:];|&]*session_transcript|\$\([[:space:]]*<[[:space:]]*[^)]*session_transcript|open\([^)]*session_transcript'

scan_transcript_reads() {
  local dir="$1" f hit=0
  [ -d "$dir" ] || return 0
  while IFS= read -r f; do
    case "$f" in
      */rule-oracles.sh) continue ;;
    esac
    if grep -qE "$transcript_read_re" "$f"; then
      echo "FAIL transcript read: $f"
      hit=1
    fi
  done < <(find "$dir" -type f \( -name '*.sh' -o -name '*.py' \))
  return "$hit"
}

run_fixtures() {
  local fail=0
  expect() {
    local cwd="$1" name="$2" want_rc="$3" want_out="$4"
    local out="" rc=0
    out="$(resolve_create_project "$cwd" "$name")" || rc=$?
    if [ "$rc" -ne "$want_rc" ] || [ "$out" != "$want_out" ]; then
      printf 'FAIL name=%q rc=%s out=%q want_rc=%s want=%q\n' \
        "$name" "$rc" "$out" "$want_rc" "$want_out"
      fail=1
    fi
  }

  expect /tmp foo 0 "$HOME/Projects/foo"
  expect /tmp foo/bar 0 /tmp/foo/bar
  expect /tmp /var/x 0 /var/x
  expect /tmp "" 30 ""
  expect /tmp "   " 30 ""
  expect /tmp '~/zzz' 0 "$HOME/zzz"

  local planted
  planted="$(mktemp -d)"
  printf 'cat session_transcript.md\n' > "$planted/bad.sh"
  if scan_transcript_reads "$planted" >/dev/null; then
    echo "FAIL detector missed a planted transcript read"
    fail=1
  fi
  rm -rf "$planted"

  local d
  for d in "$ROOT/hooks" "$ROOT/updater" "$ROOT/boot-dashboard"; do
    scan_transcript_reads "$d" || fail=1
  done

  if [ "$fail" -eq 0 ]; then
    echo "ok create_project paths and transcript-read scan"
  fi
  return "$fail"
}

case "${1:-}" in
  ""|check)
    run_fixtures
    ;;
  resolve)
    shift
    cwd="$PWD"
    while [ $# -gt 0 ]; do
      case "$1" in
        --cwd)
          [ $# -ge 2 ] || { echo "resolve: --cwd needs a directory" >&2; exit 2; }
          cwd="$2"
          shift 2
          ;;
        --)
          shift
          break
          ;;
        *)
          break
          ;;
      esac
    done
    [ $# -eq 1 ] || { echo "usage: rule-oracles.sh resolve --cwd DIR -- NAME" >&2; exit 2; }
    resolve_create_project "$cwd" "$1"
    ;;
  *)
    echo "usage: rule-oracles.sh [check|resolve --cwd DIR -- NAME]" >&2
    exit 2
    ;;
esac
