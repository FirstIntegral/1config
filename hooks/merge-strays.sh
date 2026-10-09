#!/usr/bin/env bash
# merge-strays.sh — automated AI merge of quarantined AGENTS.md strays.
#
# Runs after the symlink guard (cron @daily). When NEEDS-SYMLINK-MERGE exists
# (stray files quarantined by check-links.sh), each stray is fed to a headless
# LLM: "extract unique durable rules not already in canonical, output one
# markdown section or SKIP". Sanitized output is appended to canonical, the
# stray is deleted, the flag line removed. If the LLM fails, the flag survives
# for the next run (manual fallback = the documented AI duty).
# A reply that contains a token from hooks/kill-tokens.deny is not appended.
# The stray and the flag line stay, so a human can separate the retired name
# from anything else in that reply.
#
# Env overrides (sandbox testing):
#   CANON, GUARD_DIR, STRAYS_DIR, AGENTS_HOME,
#   MERGE_LLM_BACKEND (claude|grok|opencode), MERGE_LLM_MODEL,
#   MERGE_MAX_BYTES, MERGE_TIMEOUT, MERGE_SKIP_LLM=1 (report only)
set -u

CANON="${CANON:-$HOME/.agents/AGENTS.md}"
AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
DIR="${GUARD_DIR:-$HOME/cron-jobs/agents-symlink-guard}"
FLAG="$DIR/NEEDS-SYMLINK-MERGE"
STRAYS="${STRAYS_DIR:-$HOME/.agents/backups/strays}"
LOG="$DIR/merge-strays.log"
BACKEND="${MERGE_LLM_BACKEND:-claude}"
MODEL="${MERGE_LLM_MODEL:-}"
MAX_BYTES="${MERGE_MAX_BYTES:-4000}"
TIMEOUT="${MERGE_TIMEOUT:-120}"
SKIP_LLM="${MERGE_SKIP_LLM:-0}"
KILL_DENY="${KILL_DENY:-$AGENTS_HOME/hooks/kill-tokens.deny}"

# kill_token_hit TEXT -> prints the token and returns 0 when TEXT contains one.
# Fixed-string match. Empty deny file means nothing is retired.
kill_token_hit() {
  local text="$1" tok
  [ -f "$KILL_DENY" ] || return 1
  while IFS= read -r tok || [ -n "$tok" ]; do
    tok="${tok%$'\r'}"
    case "$tok" in
      ''|'#'*) continue ;;
    esac
    if printf '%s\n' "$text" | grep -F -q -- "$tok"; then
      printf '%s\n' "$tok"
      return 0
    fi
  done < "$KILL_DENY"
  return 1
}

if [ "${1:-}" = "--check-kill" ]; then
  shift
  if kill_token_hit "$*" >/dev/null; then
    exit 1
  fi
  exit 0
fi

mkdir -p "$DIR"
ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $*" >> "$LOG"; }

exec 9>"$DIR/.merge.lock"
flock 9

[ -f "$FLAG" ] || exit 0

[ -f "$CANON" ] || { log "FATAL canonical missing $CANON"; exit 1; }
[ -d "$STRAYS" ] || { log "FATAL strays dir missing $STRAYS"; exit 1; }

export PATH="$HOME/.opencode/bin:$HOME/.grok/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"

llm_query() {
  # llm_query "PROMPT" -> stdout reply; rc=0 on success. Backend chain.
  local prompt="$1"
  case "$BACKEND" in
    opencode)
      if [ -n "$MODEL" ]; then
        timeout "$TIMEOUT" opencode run --model "$MODEL" "$prompt" 2>/dev/null
      else
        timeout "$TIMEOUT" opencode run "$prompt" 2>/dev/null
      fi
      ;;
    grok)
      if [ -n "$MODEL" ]; then
        timeout "$TIMEOUT" grok -p --model "$MODEL" "$prompt" 2>/dev/null
      else
        timeout "$TIMEOUT" grok -p "$prompt" 2>/dev/null
      fi
      ;;
    *)
      if [ -n "$MODEL" ]; then
        timeout "$TIMEOUT" claude -p --model "$MODEL" "$prompt" --output-format text 2>/dev/null
      else
        timeout "$TIMEOUT" claude -p "$prompt" --output-format text 2>/dev/null
      fi
      ;;
  esac
}

sanitize_output() {
  # strip ANSI/control chars; collapse to safe printable set + \n\t
  tr -d '\000-\010\013\014\016-\037\177' | tr -d '\033'
}

append_merged() {
  # append_merged "BASENAME" "CONTENT" -> appends section to canonical
  {
    printf '\n---\n'
    printf '<!-- merged from %s on %s by merge-strays.sh -->\n' "$1" "$(date '+%Y-%m-%d %H:%M')"
    printf '%s\n' "$2"
  } >> "$CANON"
}

processed=0
failed=0
tmp_out="$(mktemp)"
tmp_flag="$(mktemp)"
# Preserve lines that fail (strays still pending); drop processed ones.
cp "$FLAG" "$tmp_flag"

while IFS= read -r stray; do
  [ -n "$stray" ] || continue
  case "$stray" in
    "$STRAYS"/*) ;;
    *) log "skip non-stray path in flag: $stray"; continue ;;
  esac
  [ -f "$stray" ] || { log "stray gone, drop line: $stray"; sed -i "\|^${stray}$|d" "$tmp_flag"; continue; }

  base="$(basename "$stray")"
  log "MERGE start $base ($(wc -c < "$stray") bytes)"

  if [ "$SKIP_LLM" = "1" ]; then
    log "SKIP_LLM=1 — leaving $base pending for manual merge"
    continue
  fi

  prompt="You maintain the global rules file for AI coding tools (AGENTS.md).

The CANONICAL file below already contains the current rules. A STRAY file replaced the symlink and was quarantined; it may contain newer or unique content worth keeping.

TASK:
- Compare STRAY against CANONICAL.
- Extract ONLY content present in STRAY that is NOT already in CANONICAL and is a durable rule or fact worth keeping (new sections, updated conventions, commands, paths, decisions).
- Skip duplicates, trivia, and junk.

OUTPUT FORMAT (exact):
- If nothing is worth keeping, output exactly: SKIP
- Otherwise output exactly ONE markdown section: a single \"## \" heading followed by short bullet lines (\"- ...\"). No preamble, no code fences, no trailing commentary.

CANONICAL:
$(cat "$CANON")

STRAY:
$(cat "$stray")"

  if ! llm_query "$prompt" > "$tmp_out"; then
    log "MERGE FAIL (llm rc=$?) $base — flag kept for next run"
    failed=$((failed + 1))
    continue
  fi

  out="$(sanitize_output < "$tmp_out" | sed '/^[[:space:]]*$/d' | head -c "$MAX_BYTES")"
  if [ -z "$out" ]; then
    log "MERGE FAIL (empty reply) $base — flag kept"
    failed=$((failed + 1))
    continue
  fi

  if [ "$(printf '%s' "$out" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')" = "SKIP" ]; then
    log "SKIP $base — no unique content (stray dropped, flag cleared)"
    rm -f "$stray"
    sed -i "\|^${stray}$|d" "$tmp_flag"
    processed=$((processed + 1))
    continue
  fi

  _kill="$(kill_token_hit "$out" || true)"
  if [ -n "$_kill" ]; then
    log "KILL $base — output contains retired token ($_kill); stray kept, not appended"
    failed=$((failed + 1))
    continue
  fi

  case "$out" in
    "## "*|"### "*)
      append_merged "$base" "$out"
      log "MERGED $base (${#out} bytes appended to canonical)"
      rm -f "$stray"
      sed -i "\|^${stray}$|d" "$tmp_flag"
      processed=$((processed + 1))
      ;;
    *)
      log "MERGE FAIL (invalid output, not a markdown heading) $base — flag kept"
      failed=$((failed + 1))
      ;;
  esac
done < "$tmp_flag"

rm -f "$tmp_out"

if [ -s "$tmp_flag" ]; then
  mv "$tmp_flag" "$FLAG"
else
  rm -f "$tmp_flag" "$FLAG"
  log "FLAG cleared (all strays processed)"
fi

log "merge run done: processed=$processed failed=$failed"
exit 0
