# Tool updater — source of truth

Boot + resume auto-updater for opencode / grok / claude.

| File | Role |
|------|------|
| `update-apps.sh` | The updater: upgrades the 3 CLIs, refreshes SETUP.md inventory (`by update-apps`). Holds its own flock. |
| `boot-check.sh` | `@reboot` gate: waits for network (0/1/3/5/10/15 min backoff), then runs `update-apps.sh`. |
| `on-resume.sh` | Resume hook body: runs `boot-check.sh` detached after suspend. |
| `system-sleep-shim.sh` | systemd shim — **install once per machine with root**: `sudo cp system-sleep-shim.sh /usr/lib/systemd/system-sleep/ai-terminal-tools-update-resume.sh` |

**Install model:** `setup.sh` copies the 3 user scripts (byte-identical) to
`~/cron-jobs/ai-terminal-tools-update-on-boot/`; `verify.sh` checks byte-identity.
Logs (`update-apps.log`) and the lock (`.update.lock`) stay in the installed dir —
never in this source tree. Crontab `@reboot …/boot-check.sh` is managed by setup.sh.

Portable: scripts use `$HOME`/`$USER`; no machine-specific paths inside.
