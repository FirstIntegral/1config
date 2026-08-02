#!/usr/bin/env bash
# Called by /usr/lib/systemd/system-sleep/ai-terminal-tools-update-resume.sh on resume
# from suspend/hibernate. Args: $1 = pre|post  $2 = suspend|hibernate|hybrid-sleep|suspend-then-hibernate
# Only act on "post" (resume). Run the boot-check as the current user, detached
# so systemd doesn't block.
# SOURCE: ~/.agents/updater/ — setup.sh copies to ~/cron-jobs/ai-terminal-tools-update-on-boot/
set -u
[ "${1:-}" = "post" ] || exit 0

user="${USER:-brwsk}"
home="$HOME"
DIR="$home/cron-jobs/ai-terminal-tools-update-on-boot"
script="$DIR/boot-check.sh"

# Drop into user, fully detached, no waiting — update runs in background.
runuser -u "$user" -- env -i HOME="$home" USER="$user" PATH="$home/.opencode/bin:$home/.grok/bin:$home/.local/bin:/usr/local/bin:/usr/bin:/bin" \
  nohup "$script" </dev/null >>"$DIR/update-apps.log" 2>&1 &
exit 0
