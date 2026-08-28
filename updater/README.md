# Tool updater — source of truth

Boot + resume auto-updater for opencode / grok / claude.

| File | Role |
|------|------|
| `update-apps.sh` | Upgrades the 3 CLIs; refreshes SETUP.md inventory only when version rows change. Holds its own flock. |
| `boot-check.sh` | `@reboot` gate: waits for network (0/1/3/5/10/15 min backoff), then runs `update-apps.sh`. |
| `on-resume.sh` | User helper: runs `boot-check.sh` inside a supervised transient service after resume. |
| `system-sleep-shim.sh` | Root systemd hook: detects logged-in users and schedules delayed helpers outside the sleep-hook cgroup. |
| `refresh-inventory.py` | Shared exact/idempotent SETUP.md inventory refresher used by setup and updater. |

**Install model:** `setup.sh` copies the 4 user scripts (byte-identical) to
`~/cron-jobs/ai-terminal-tools-update-on-boot/`; `verify.sh` checks byte-identity.
Logs (`update-apps.log`) and the lock (`.update.lock`) stay in the installed dir —
never in this source tree. Crontab `@reboot …/boot-check.sh` is managed by setup.sh.

Install or refresh the root hook:

```bash
sudo install -o root -g root -m 0755 ~/.agents/updater/system-sleep-shim.sh \
  /usr/lib/systemd/system-sleep/ai-terminal-tools-update-resume.sh
```

Portable: no username or home path is hardcoded. The root hook uses `loginctl` +
`getent`, then passes explicit `HOME`, `USER`, and `LOGNAME` to `systemd-run --uid`.
Scheduling failures return nonzero and go to the journal instead of being masked.
