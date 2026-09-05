# 1config

Canonical AI-terminal brain for **Claude Code**, **Grok**, and **OpenCode**. One rules file, one permission policy, one setup script. Lives at `~/.agents/` and is the git repo `github:FirstIntegral/1config`.

This file is the human report. The machine spec is [`SETUP.md`](SETUP.md). Runtime rules the three tools load every session are [`AGENTS.md`](AGENTS.md). Opinionated choices and *why* are [`docs/DECISIONS.md`](docs/DECISIONS.md).

## Supported systems

| Distro | Status | Package line (setup.sh prints this if something is missing) |
|--------|--------|---------------------------------------------------------------|
| **Omarchy** (Arch) | Supported | `omarchy pkg add python util-linux cronie git gnupg gnome-keyring texlive-meta` |
| **Ubuntu** (Debian) | Supported | `sudo apt-get install -y python3 util-linux cron git gnupg gnome-keyring texlive-full` |
| Other systemd Linux | Best-effort | python3, flock, git, cron, gnupg, gnome-keyring |

Same `setup.sh` on both. No Omarchy-only step in the install path. The Omarchy desktop skill is **gitignored** (`skills/`) and never required for the brain to run.

## Fresh machine

```bash
# 1. GitHub auth, then clone into ~/.agents  (HTTPS or SSH)
git clone https://github.com/FirstIntegral/1config.git ~/.agents
# git clone git@github.com:FirstIntegral/1config.git ~/.agents

# 2. Distro packages if the preflight complains
#    Ubuntu:  sudo apt-get install -y python3 util-linux cron git gnupg gnome-keyring texlive-full
#    Omarchy: omarchy pkg add python util-linux cronie git gnupg gnome-keyring texlive-meta
#    then:    sudo systemctl enable --now cron     # Ubuntu
#             sudo systemctl enable --now cronie   # Omarchy/Arch

# 3. Wire the brain (idempotent)
bash ~/.agents/setup.sh

# 4. Machine-local, once
git config --global user.name  "…"
git config --global user.email "…"
git config --global user.signingkey <YOUR-KEY-ID>   # this machine's key, not another box's
git config --global commit.gpgsign true
bash ~/.agents/hooks/gpg-store-passphrase.sh        # dedicated gnome-keyring collection
gh auth login                                       # so sync.sh can fetch/push

# 5. Optional: resume-from-suspend updater (needs root once)
sudo install -o root -g root -m 0755 ~/.agents/updater/system-sleep-shim.sh \
  /usr/lib/systemd/system-sleep/ai-terminal-tools-update-resume.sh
```

Install the three CLIs (grok, claude, opencode) however you usually do. `setup.sh` does **not** download them; the boot updater only upgrades bins that already exist.

`verify.sh` ending `== PASS (warnings=0) ==` means the brain is installed. A signing warn on the boot dashboard is normal until step 4.

### Omarchy machines: also clone the desktop config pack

The **desktop** config (Hyprland bindings, shell layout, theme, Vigil plugin, OpenTabletDriver/Huion) is a separate public repo: `github:FirstIntegral/omarchy-dots`. On an Omarchy box, after this brain is installed:

```bash
gh repo clone FirstIntegral/omarchy-dots ~/Projects/omarchy-dots
cd ~/Projects/omarchy-dots && ./apply.sh --dry-run && ./apply.sh
```

From then on the boot dashboard keeps it in sync automatically: `~/Projects/omarchy-dots/sync.sh` runs at every login (fetch → ff-only pull → drift-check `~/.config` vs pack → auto-apply). Non-Omarchy boxes show a gray `–` skip row and never touch it. Playbook: that repo's `README.md`.

## Existing machine — pull latest

Works on Omarchy **and** Ubuntu. Same commands:

```bash
cd ~/.agents
git pull origin main
bash ~/.agents/setup.sh
```

`setup.sh` is idempotent: re-copies hooks, refreshes cron jobs, re-fans permissions, rewrites the autostart `Exec=` to *this* `$HOME`. Live CLI versions go to **gitignored** `inventory.local.md`, so an Ubuntu box pulling Omarchy-era versions (or the reverse) no longer fails verify and no longer dirties git with a version-table fight. That table uses login `command -v` first, then the vendor dirs the updater already knows (`~/.opencode/bin`, `~/.grok/bin`, `~/.local/bin`) — Ubuntu's official OpenCode installer is visible even though its PATH line lives behind `.bashrc`'s interactive-guard; an Omarchy mise shim on login PATH still wins. 1config does not edit your `.profile` and does not symlink into `~/.local/bin`.

## Opinionated defaults — read before you fork

These are **this repo's** choices. Other people often want the opposite. They are all reversible; none are hidden.

| Default | Value here | Why | Flip |
|---------|------------|-----|------|
| **`bash_without_prompt`** | **`true`** | Claude's allowlist cannot kill some hard-coded prompts (`cd`+write, `cd`+git). Full autonomy sets Claude `bypassPermissions`, Grok `always-approve`, OpenCode `permission.bash["*"]="allow"`, **and omits ask fan-out** (OpenCode last-match and Grok shell-ask would otherwise still prompt `git push`). Deny still fans out. Generic `git push` no longer prompts. | `permissions.json` → `"bash_without_prompt": false` then `bash ~/.agents/setup.sh`. Restores the Bash review gate. |
| **`edit_without_prompt`** | `true` | File writes should not stop a session. | Same file, `"edit_without_prompt": false`. |
| GPG commit signing | Required, never `--no-gpg-sign` | Attribution is cryptographic. | Don't. If you must unsigned history, this is the wrong brain. |
| No AI co-author lines | Hard rule | Commits/PRs attributed to the user only. | Don't. |
| Caveman mode | Always on | Terse AI prose. `/caveman lite\|full\|ultra` or `stop caveman`. | Say `normal mode` in that session. |
| Tool memory stores | Disabled | Facts live in markdown (`AGENTS.md`, `session_compact.md`, `docs/DECISIONS.md`). | Don't recreate `~/.grok/memory/` or Claude topic files. |
| `create_project` / `checkpoint_project` | Never `git init`, never add a remote | Publishing is a human decision. | Ask explicitly. |
| TeX | Assumed installed | Papers are LaTeX, never a Markdown fallback. | Install `texlive-full` (Ubuntu) or `texlive-meta` (Omarchy). |
| Paper author block | Brusk Kawa Abdalla | This user's papers. | Edit `AGENTS.md` `writepaper_project` if you fork. |
| Remote check | `FirstIntegral/1config` only | `sync.sh` / `verify.sh` refuse a different origin. | Forks: change the two URL constants. |

Canonical permission file: [`permissions.json`](permissions.json). Comments in that file are part of the spec.

## What `setup.sh` does *not* do

- No `apt` / `pacman` / `omarchy pkg` (prints the line, you run it).
- No CLI download for grok/claude/opencode.
- No GPG key generation and no passphrase prompt (that's `gpg-store-passphrase.sh`).
- No `gh auth login`.
- No rewrite of *your* git `user.signingkey`.
- **Does** set `git config --global gpg.program` to `hooks/gpg-git.sh` (loopback, no pinentry GUI).

## Layout

| Path | Role |
|------|------|
| `AGENTS.md` | Rules every tool loads (via symlinks). Keep lean. |
| `SETUP.md` | Full install spec. Authoritative for AIs recreating the machine. |
| `permissions.json` | One policy, fanned out to all three tools. |
| `setup.sh` / `verify.sh` / `sync.sh` | Install, check, signed push. |
| `hooks/` | GPG unlock, checkpoint, guards, heredoc rewrite. |
| `boot-dashboard/` | Login status terminal (XDG autostart, Wayland or X11). |
| `docs/DECISIONS.md` | ADRs for this repo. |
| `inventory.local.md` | Live CLI versions. Gitignored. Login PATH first (mise), then `~/.opencode/bin` / `~/.grok/bin` / `~/.local/bin` so Ubuntu's official installer is visible without shadowing Omarchy mise. |
| `skills/` | Machine-local (Omarchy skill lives here). Gitignored. |
