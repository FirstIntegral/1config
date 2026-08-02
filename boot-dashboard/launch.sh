#!/usr/bin/env bash
# Open a terminal window running the boot dashboard.
# Used by GNOME autostart (.desktop) and for manual: bash ~/.agents/boot-dashboard/launch.sh
set -u

DASH="${AGENTS_HOME:-$HOME/.agents}/boot-dashboard/dashboard.sh"
TITLE="Agents · boot status"

# Compact dashboard window (cols x rows). User's normal Ptyxis often restores a
# near-fullscreen last size (window-size in dconf) — that makes boot status look
# full-screen. We temporarily set a normal size for this launch only.
COLS="${BOOT_DASHBOARD_COLS:-92}"
ROWS="${BOOT_DASHBOARD_ROWS:-32}"

if [ ! -x "$DASH" ]; then
  chmod +x "$DASH" 2>/dev/null || true
fi

# Small delay so Wayland/GNOME session + network are up (autostart can fire early)
if [ "${BOOT_DASHBOARD_NO_DELAY:-0}" != "1" ]; then
  sleep "${BOOT_DASHBOARD_DELAY:-4}"
fi

# Prefer ptyxis (this machine's default), then xdg-terminal-exec, then fallbacks
run_cmd="bash -lc $(printf '%q' "$DASH")"

# ── Ptyxis: temporary normal size so we don't inherit fullscreen restore ──
# restore-window-size + a huge saved window-size is what made this look fullscreen.
# Set compact size → open window → restore previous prefs so normal terminals
# keep the user's preferred size.
ptyxis_launch() {
  local prev_size prev_restore
  prev_size="$(gsettings get org.gnome.Ptyxis window-size 2>/dev/null || true)"
  prev_restore="$(gsettings get org.gnome.Ptyxis restore-window-size 2>/dev/null || true)"

  gsettings set org.gnome.Ptyxis window-size "(uint32 ${COLS}, uint32 ${ROWS})" 2>/dev/null || true
  gsettings set org.gnome.Ptyxis restore-window-size true 2>/dev/null || true

  # Start window, give it a moment to map + read dconf size, then put prefs back.
  ptyxis --standalone --title="$TITLE" --new-window -x "$run_cmd" &
  local pid=$!
  sleep 1.2
  if [ -n "${prev_size:-}" ]; then
    gsettings set org.gnome.Ptyxis window-size "$prev_size" 2>/dev/null || true
  fi
  if [ -n "${prev_restore:-}" ]; then
    gsettings set org.gnome.Ptyxis restore-window-size "$prev_restore" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
}

if command -v ptyxis >/dev/null 2>&1; then
  ptyxis_launch
  exit 0
fi

if command -v xdg-terminal-exec >/dev/null 2>&1; then
  exec xdg-terminal-exec -- $run_cmd
fi

if command -v gnome-terminal >/dev/null 2>&1; then
  # geometry = COLSxROWS — GNOME places it; not true center but normal size
  exec gnome-terminal --geometry="${COLS}x${ROWS}" --title="$TITLE" -- $run_cmd
fi

if command -v x-terminal-emulator >/dev/null 2>&1; then
  exec x-terminal-emulator -e bash -lc "$DASH"
fi

# Last resort: run in current tty
exec bash "$DASH"
