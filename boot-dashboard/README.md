# Boot dashboard

On login: opens a **normal-size** terminal (not fullscreen), runs health checks, shows ready / not ready.

| File | Role |
|------|------|
| `dashboard.sh` | UI + checks |
| `launch.sh` | opens Ptyxis (or fallback terminal) with the dashboard |
| `agents-boot-status.desktop` | Cross-desktop XDG autostart template (Wayland or X11) |

**Installed by** `~/.agents/setup.sh` → `~/.config/autostart/agents-boot-status.desktop`

**Manual:** `bash ~/.agents/boot-dashboard/launch.sh`

## What it checks

| Row | Meaning |
|-----|---------|
| **network** | GitHub reachable (HEAD / api). Retries ~6×3s so early-boot DHCP/WiFi catch up. Warn = online but GitHub slow; fail = offline. |
| **symlinks** | 3 AGENTS paths → `~/.agents/AGENTS.md` |
| **link guard** | `agents-symlink-guard` healthy |
| **memory guard** | Claude/Grok residue clean |
| **tool updates** | Watches boot updater (`~/cron-jobs/ai-terminal-tools-update-on-boot/`). Does **not** start upgrades. Runs **before** ecosystem so inventory refresh finishes first. |
| **ecosystem** | `verify.sh` PASS (after tool updates — avoids false inventory mismatch at boot) |
| **tool versions** | grok / claude / opencode on PATH |
| **signing** | Attempts GPG signing-key unlock from the dedicated `gpg-signing` collection (and migrates out of bricked default `.keyring` files). Warn: nothing stored / dbus down / passphrase rejected — not a generic "locked". |

## Window size

Ptyxis restores last window size from dconf. If that size is huge (near-fullscreen), the boot status window used to open full screen.

`launch.sh` temporarily sets `org.gnome.Ptyxis window-size` to **92×32** (cols×rows), opens the dashboard, then restores the previous value so normal terminals keep your preferred size. Override:

```bash
BOOT_DASHBOARD_COLS=100 BOOT_DASHBOARD_ROWS=36 bash ~/.agents/boot-dashboard/launch.sh
```

## Env knobs

| Var | Default | Effect |
|-----|---------|--------|
| `BOOT_DASHBOARD_DELAY` | `4` | Seconds before open (session settle) |
| `BOOT_DASHBOARD_NO_DELAY` | `0` | Set `1` to skip delay |
| `BOOT_DASHBOARD_NET_ATTEMPTS` | `6` | Network probe retries |
| `BOOT_DASHBOARD_NET_GAP` | `3` | Seconds between net retries |
| `BOOT_DASHBOARD_UPD_WAIT` | `180` | Max seconds to watch tool updater |
| `BOOT_DASHBOARD_COLS` / `ROWS` | `92` / `32` | Ptyxis size for this window |

## Reading the common warns

1. **network — online, github slow/unreachable**  
   Ping works; light GitHub probe failed after retries. Often: WiFi just up, DNS slow, or GitHub congested. Fine to work. Re-run later: `bash ~/.agents/boot-dashboard/launch.sh` with `BOOT_DASHBOARD_NO_DELAY=1`.

2. **tool updates — still running after 180s**  
   `@reboot` `boot-check.sh` → `update-apps.sh` still upgrading (each tool has a 300s timeout). Background is OK — close the window. Log: `~/cron-jobs/ai-terminal-tools-update-on-boot/update-apps.log`.

Partial fail (e.g. `claude update TIMED OUT`) is a **warn**, not a hard fail — other tools may have updated fine.

3. **signing — no stored passphrase / dbus failed / passphrase rejected**  
   Dedicated `gpg-signing` collection missing, gnome-keyring down, or the passphrase changed. One-time: `bash ~/.agents/hooks/gpg-store-passphrase.sh`. Unlock also migrates the item out of bricked default `.keyring` files (multiline secrets make gnome-keyring refuse the whole file).
