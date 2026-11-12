#!/usr/bin/env bash
# tool-path.sh — sourced. PATH for a script that starts from cron, a timer, or
# autostart, where the login shell's PATH is not inherited.
#
#   agents_tool_path   -> prints the PATH to export
#
# Order follows the inventory rule (ADR 2026-09-01): the login shell's own PATH
# first, because that is where mise shims and wrappers live and they must win,
# then the vendor dirs the official installers use, then the system dirs.
# The updater does not use this: it keeps a PATH without mise on purpose.

agents_tool_path() {
  local login="" line
  # A profile may print a banner. Only the marked line is the PATH.
  while IFS= read -r line; do
    case "$line" in
      __AGENTS_PATH__=*) login="${line#__AGENTS_PATH__=}" ;;
    esac
  done < <(timeout 10 env -i HOME="$HOME" USER="${USER:-$(id -un)}" TERM=dumb \
             bash -lc 'printf "\n__AGENTS_PATH__=%s\n" "$PATH"' 2>/dev/null || true)
  printf '%s\n' "${login:+$login:}$HOME/.opencode/bin:$HOME/.grok/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
}
