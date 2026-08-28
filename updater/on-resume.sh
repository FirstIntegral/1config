#!/usr/bin/env bash
# Called by /usr/lib/systemd/system-sleep/ai-terminal-tools-update-resume.sh on resume
# from suspend/hibernate. Args: $1 = pre|post  $2 = suspend|hibernate|hybrid-sleep|suspend-then-hibernate
# Only act on "post" (resume). The root shim schedules this as a delayed
# transient service under the target user, so this process stays supervised.
# SOURCE: ~/.agents/updater/ — setup.sh copies to ~/cron-jobs/ai-terminal-tools-update-on-boot/
set -euo pipefail
[ "${1:-}" = "post" ] || exit 0

DIR="${UPD_INSTALL_DIR:-$HOME/cron-jobs/ai-terminal-tools-update-on-boot}"
script="$DIR/boot-check.sh"

[ -x "$script" ] || { echo "on-resume: missing executable $script" >&2; exit 1; }
exec "$script"
