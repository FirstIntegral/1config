#!/usr/bin/env bash
# boot-dashboard — slick one-screen summary of boot checks / tool status.
# Source lives under ~/.agents; opened on login via autostart + launch.sh.
set -u

export PATH="$HOME/.opencode/bin:$HOME/.grok/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"

AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
GUARD_DIR="$HOME/cron-jobs/agents-symlink-guard"
MEM_DIR="$HOME/cron-jobs/claude-memory-guard"
UPD_DIR="$HOME/cron-jobs/ai-terminal-tools-update-on-boot"
UPD_LOG="$UPD_DIR/update-apps.log"
UPD_LOCK="$UPD_DIR/.update.lock"

# ── colors (plain if not a tty) ────────────────────────────────────────────
if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then
  R=$'\033[0m'
  DIM=$'\033[2m'
  BOLD=$'\033[1m'
  GREEN=$'\033[32m'
  RED=$'\033[31m'
  YELLOW=$'\033[33m'
  CYAN=$'\033[36m'
  BLUE=$'\033[34m'
  GRAY=$'\033[90m'
else
  R=; DIM=; BOLD=; GREEN=; RED=; YELLOW=; CYAN=; BLUE=; GRAY=
fi

pass=0
fail=0
warn=0

# ── layout helpers ─────────────────────────────────────────────────────────
clear_screen() { printf '\033[2J\033[H'; }

line() {
  printf "  ${GRAY}%s${R}\n" "────────────────────────────────────────────────"
}

header() {
  local host now
  host="$(hostname 2>/dev/null || echo host)"
  now="$(date '+%Y-%m-%d  %H:%M')"
  printf "\n"
  printf "  ${BOLD}${CYAN}agents${R}  ${DIM}boot status${R}\n"
  printf "  ${GRAY}%s · %s${R}\n" "$host" "$now"
  line
}

row() {
  # row STATUS LABEL DETAIL
  local st="$1" label="$2" detail="$3"
  local icon color
  case "$st" in
    ok)   icon="✓"; color="$GREEN";  pass=$((pass + 1)) ;;
    fail) icon="✗"; color="$RED";    fail=$((fail + 1)) ;;
    warn) icon="!"; color="$YELLOW"; warn=$((warn + 1)) ;;
    run)  icon="…"; color="$BLUE" ;;
    skip) icon="–"; color="$GRAY" ;;
    *)    icon="·"; color="$GRAY" ;;
  esac
  printf "  ${color}%s${R}  ${BOLD}%-18s${R}  ${DIM}%s${R}\n" "$icon" "$label" "$detail"
}

spinner_wait() {
  # spinner_wait SECONDS message — brief visual wait
  local total="$1" msg="$2" i=0
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local end=$((SECONDS + total))
  while [ "$SECONDS" -lt "$end" ]; do
    printf "\r  ${BLUE}%s${R}  ${DIM}%s${R}   " "${frames[$((i % ${#frames[@]}))]}" "$msg"
    sleep 0.1
    i=$((i + 1))
  done
  printf "\r\033[K"
}

# ── checks ─────────────────────────────────────────────────────────────────
# Light probe: HEAD + small endpoint. Full github.com HTML is huge and often
# trips short curl timeouts even when the net is fine (boot race + slow path).
net_probe() {
  curl -fsS --max-time 8 -o /dev/null -I https://github.com 2>/dev/null \
    || curl -fsS --max-time 8 -o /dev/null https://api.github.com 2>/dev/null
}

check_network() {
  # Boot often fires before DHCP/WiFi is ready — retry briefly instead of
  # false "github slow" on first miss.
  local attempts="${BOOT_DASHBOARD_NET_ATTEMPTS:-6}"
  local gap="${BOOT_DASHBOARD_NET_GAP:-3}"
  local i=1
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local fi=0

  while [ "$i" -le "$attempts" ]; do
    if net_probe; then
      printf "\r\033[K"
      if [ "$i" -eq 1 ]; then
        row ok "network" "github reachable"
      else
        row ok "network" "github reachable (attempt $i/${attempts})"
      fi
      return 0
    fi
    if [ "$i" -lt "$attempts" ]; then
      printf "\r  ${BLUE}%s${R}  ${BOLD}%-18s${R}  ${DIM}waiting for net (%s/%s)…${R}   " \
        "${frames[$((fi % ${#frames[@]}))]}" "network" "$i" "$attempts"
      sleep "$gap"
      fi=$((fi + 1))
    fi
    i=$((i + 1))
  done
  printf "\r\033[K"

  if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 \
    || ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; then
    row warn "network" "online, github slow/unreachable"
    return 1
  fi
  row fail "network" "offline"
  return 1
}

check_symlinks() {
  local okc=0 f
  for f in "$HOME/.grok/AGENTS.md" "$HOME/.config/opencode/AGENTS.md" "$HOME/.claude/CLAUDE.md"; do
    if [ -L "$f" ] && [ "$(readlink -f "$f" 2>/dev/null)" = "$AGENTS_HOME/AGENTS.md" ]; then
      okc=$((okc + 1))
    fi
  done
  if [ "$okc" -eq 3 ]; then
    row ok "symlinks" "3/3 → ~/.agents/AGENTS.md"
    return 0
  fi
  row fail "symlinks" "$okc/3 ok — run setup.sh"
  return 1
}

check_link_guard() {
  if [ ! -x "$GUARD_DIR/check-links.sh" ]; then
    row fail "link guard" "missing"
    return 1
  fi
  if "$GUARD_DIR/check-links.sh" >/dev/null 2>&1; then
    row ok "link guard" "healthy"
    return 0
  fi
  local rc=$?
  if [ -f "$GUARD_DIR/NEEDS-SYMLINK-MERGE" ]; then
    row warn "link guard" "NEEDS-SYMLINK-MERGE set"
    return 1
  fi
  row warn "link guard" "exit $rc (see check-links.log)"
  return 1
}

check_mem_guard() {
  if [ ! -x "$MEM_DIR/check-memory.sh" ]; then
    row fail "memory guard" "missing"
    return 1
  fi
  if "$MEM_DIR/check-memory.sh" >/dev/null 2>&1; then
    row ok "memory guard" "clean"
    return 0
  fi
  if [ -f "$MEM_DIR/NEEDS-MEMORY-MERGE" ]; then
    row warn "memory guard" "NEEDS-MEMORY-MERGE — residue to merge"
    return 1
  fi
  row warn "memory guard" "exit non-zero (see check-memory.log)"
  return 1
}

check_verify() {
  if [ ! -x "$AGENTS_HOME/verify.sh" ]; then
    row fail "verify" "verify.sh missing"
    return 1
  fi
  local out rc
  out="$(bash "$AGENTS_HOME/verify.sh" 2>&1)" || true
  if echo "$out" | grep -q '== PASS'; then
    row ok "ecosystem" "verify PASS"
    return 0
  fi
  local nfail
  nfail="$(echo "$out" | grep -c 'FAIL' || true)"
  row fail "ecosystem" "verify FAIL ($nfail) — bash ~/.agents/verify.sh"
  return 1
}

check_versions() {
  local g c o
  g="$(grok --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo '?')"
  c="$(claude --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo '?')"
  o="$(opencode --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo '?')"
  if [ "$g" != "?" ] || [ "$c" != "?" ] || [ "$o" != "?" ]; then
    row ok "tool versions" "grok $g · claude $c · opencode $o"
  else
    row warn "tool versions" "CLIs not on PATH yet"
  fi
}

check_gpg_sign() {
  # Auto-unlocks the signing key from the GNOME keyring (no prompts).
  if [ ! -x "$AGENTS_HOME/hooks/gpg-agent-unlock.sh" ]; then
    row warn "signing" "unlock hook missing"
    return 1
  fi
  if "$AGENTS_HOME/hooks/gpg-agent-unlock.sh" >/dev/null 2>&1; then
    row ok "signing" "gpg key unlocked (commits silent)"
    return 0
  fi
  row warn "signing" "not unlocked — run gpg-store-passphrase.sh once"
  return 1
}

updater_running() {
  # lock held OR boot-check/update process alive
  if pgrep -f 'ai-terminal-tools-update-on-boot/(boot-check|update-apps)\.sh' >/dev/null 2>&1; then
    return 0
  fi
  if [ -f "$UPD_LOCK" ] && command -v fuser >/dev/null 2>&1; then
    fuser "$UPD_LOCK" >/dev/null 2>&1 && return 0
  fi
  return 1
}

check_tool_updates() {
  # Observe boot updater; wait a bit if still running (does not start a new upgrade).
  # One in-place status line only (no permanent "run" row that doubles with final).
  local max_wait="${BOOT_DASHBOARD_UPD_WAIT:-180}"  # 3 min default; UI must not hang forever
  local waited=0
  if updater_running; then
    while updater_running && [ "$waited" -lt "$max_wait" ]; do
      printf "\r  ${BLUE}…${R}  ${BOLD}%-18s${R}  ${DIM}still updating (%ss / ${max_wait}s)${R}   " \
        "tool updates" "$waited"
      sleep 2
      waited=$((waited + 2))
    done
    printf "\r\033[K"
  fi

  if updater_running; then
    # Background cron still working (each tool has 300s timeout). Fine to close UI.
    row warn "tool updates" "still running after ${max_wait}s — background OK · $UPD_LOG"
    return 1
  fi

  if [ ! -f "$UPD_LOG" ]; then
    row warn "tool updates" "no log yet (first boot?)"
    return 1
  fi

  local last endline
  last="$(tail -40 "$UPD_LOG" 2>/dev/null || true)"
  endline="$(echo "$last" | grep 'update-apps run END' | tail -1 || true)"
  if echo "$last" | grep -q 'no net after all retries'; then
    row warn "tool updates" "skipped — no network at boot"
    return 1
  fi
  if echo "$endline" | grep -q 'fail=0'; then
    local when
    when="$(echo "$endline" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]+' | head -1 || echo recent)"
    row ok "tool updates" "ok · $when"
    return 0
  fi
  if echo "$endline" | grep -q 'fail=1'; then
    # One tool timed out / failed; others may still be OK — warn not hard fail
    local hint
    hint="$(echo "$last" | grep -E 'TIMED OUT|FAILED' | tail -1 | sed 's/.*] //' || true)"
    if [ -n "$hint" ]; then
      row warn "tool updates" "$hint · see log"
    else
      row warn "tool updates" "partial fail — see $UPD_LOG"
    fi
    return 1
  fi
  # No END yet but not running — mid-log or stale
  if echo "$last" | grep -q 'update-apps run START'; then
    row warn "tool updates" "log incomplete (interrupted?)"
    return 1
  fi
  row warn "tool updates" "no completed run in log"
  return 1
}

# ── main ───────────────────────────────────────────────────────────────────
main() {
  # Prefer compact size if the terminal honors CSI 8 (rows;cols). launch.sh
  # also forces Ptyxis window-size for this one window.
  if [ -t 1 ]; then
    printf '\033[8;32;92t' 2>/dev/null || true
  fi

  clear_screen
  header
  printf "  ${DIM}running checks…${R}\n\n"

  check_network
  check_symlinks
  check_link_guard
  check_mem_guard
  check_verify
  check_versions
  check_gpg_sign
  check_tool_updates

  line
  printf "\n"
  if [ "$fail" -eq 0 ] && [ "$warn" -eq 0 ]; then
    printf "  ${GREEN}${BOLD}●  READY${R}  ${DIM}all clear — go work${R}\n"
  elif [ "$fail" -eq 0 ]; then
    printf "  ${YELLOW}${BOLD}●  READY-ish${R}  ${DIM}%s warn · fine to work, glance above${R}\n" "$warn"
  else
    printf "  ${RED}${BOLD}●  NOT READY${R}  ${DIM}%s fail · %s warn — fix, then: bash ~/.agents/setup.sh${R}\n" "$fail" "$warn"
  fi
  printf "\n"
  printf "  ${GRAY}%s ok · %s warn · %s fail${R}\n" "$pass" "$warn" "$fail"
  printf "\n"
  printf "  ${DIM}enter to close${R}\n"
  # non-interactive (tests): skip wait
  if [ -t 0 ]; then
    read -r _ || true
  fi
}

main "$@"
