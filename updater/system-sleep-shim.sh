#!/bin/sh
# Systemd suspend/resume hook. INSTALL ONCE PER MACHINE (needs root):
#   sudo cp ~/.agents/updater/system-sleep-shim.sh /usr/lib/systemd/system-sleep/ai-terminal-tools-update-resume.sh
# Systemd calls every script here with: $1 = pre|post  $2 = suspend|hibernate|hybrid-sleep|suspend-then-hibernate
# We delegate to the user's on-resume trigger (installed copy in ~/cron-jobs/ai-terminal-tools-update-on-boot/).
# NOTE: this shim is root-owned and NOT re-installed by setup.sh; keep the
# path below pointing at the INSTALLED copy (unchanged across machines).
/home/brwsk/cron-jobs/ai-terminal-tools-update-on-boot/on-resume.sh "$@"
exit 0
