# Brain decisions

ADRs for `~/.agents` / `github:FirstIntegral/1config`. Project work logs decisions in *that* project's `docs/DECISIONS.md`. This file is the brain's own.

## 2026-09-03 — Omit ask fan-out while `bash_without_prompt` is true

**Decision:** When `bash_without_prompt` is true, `setup.sh` writes empty ask buckets to Claude and Grok, and skips ask patterns in OpenCode `permission.bash`. Deny still fans out. Canonical `permissions.json` still lists the ask rules (restore-gate when the flag flips).

**Why:** OpenCode last-match: `"git push": "ask"` after `"*": "allow"` re-prompted `git push 2>&1 | tail -5; git status; git rev-parse HEAD` (screenshot 2026-09-03, OpenCode 1.10/1.18). Grok always-approve still honors shell `ask` rules (Grok permissions docs). Claude `bypassPermissions` already skipped them. Policy since 2026-08-29 is no generic git-push prompt; live configs did not match.

**Rejected:** Moving `"*": "allow"` after the ask keys (works, but leaves dead ask rules that look like they still prompt). Converting ask → allow (would keep `git push` silent even after a TUI mode flip). Leaving ask in OpenCode as "best-effort" (they are not best-effort — last-match makes them win).

## 2026-08-29 — Full Bash autonomy (`bash_without_prompt: true`)

**Decision:** All three tools run without Bash permission prompts. Claude `bypassPermissions`, Grok `always-approve`, OpenCode `permission.bash["*"] = allow`.

**Why:** Claude's allowlist cannot remove hard-coded safety prompts (`cd`+write, `cd`+git / untrusted hooks, some parse verdicts). The only switch that actually kills them is `bypassPermissions`. The user chose that 2026-08-29.

**Cost:** Claude ask/deny lists become best-effort (bypass skips checks). Generic `git push` no longer prompts. This is **not** a default most people want.

**Flip:** `permissions.json` → `"bash_without_prompt": false`, then `bash ~/.agents/setup.sh`. Documented in `README.md` on purpose so forks see it.

**Rejected:** Leaving Claude on `acceptEdits` and expanding the allowlist. Empirically insufficient.

**Follow-up 2026-09-03:** ask rules were still fanned out; OpenCode last-match re-prompted `git push`. See the omit-ask ADR above.

## 2026-09-02 — Git signs via `gpg-git.sh`, never pinentry GUI

**Decision:** `setup.sh` sets `git config --global gpg.program` to `hooks/gpg-git.sh`. The wrapper calls `gpg --batch --pinentry-mode loopback`, and on cache miss runs `gpg-agent-unlock.sh` then retries. Boot dashboard unlocks GPG **before** tool-update / verify.

**Why:** Keyring unlock already worked, but git still invoked `pinentry-gnome3` when the agent cache was cold (first commit of a session, or a test `git commit` inheriting global `commit.gpgsign`). That is the "enter the GPG password" dialog. Dashboard used to unlock last, after minutes of updater wait.

**Rejected:** `pinentry-mode loopback` in `gpg.conf` (would also strip GUI from encrypt/decrypt). Leaving git on stock gpg and hoping the dashboard races win.

## 2026-08-29 — Dedicated `gpg-signing` keyring collection

**Decision:** Store the GPG passphrase in a gnome-keyring collection labelled `gpg-signing` (empty master, autologin-safe), not in the default collection. Unlock scans bricked on-disk `.keyring` files and restocks.

**Why:** gnome-keyring 50 cannot reload an unencrypted default keyring after any item's `secret=` contains a raw newline (Proton JSON, etc.). Journal: `invalid or unrecognized format`. SearchItems then empty even though the GPG item is still in the file. A one-item collection does not pick up those secrets.

**Rejected:** Sharing the default collection; calling `Service.Unlock` (GUI prompt); encrypting the collection with the login password (autologin has none).

## 2026-08-29 — Omarchy + Ubuntu, inventory is machine-local

**Decision:** The same clone + `setup.sh` must work on Omarchy (Arch) and Ubuntu (Debian), fresh or `git pull` on an existing box. Live grok/claude/opencode versions live in gitignored `inventory.local.md`, not in `SETUP.md`. GPG key id comes from `git config --global user.signingkey` / `$GPG_SIGNING_KEY`, never a hardcoded key from another machine.

**Why:** Pinning versions in `SETUP.md` made Ubuntu fail verify after pulling Omarchy's table (and would dirty git the other way). Hardcoding `95FBA6E0AA245342` made a second machine unlock the wrong key. `setup.sh` prints the distro-correct package line and does not run `apt`/`pacman`.

**Rejected:** Auto-installing packages from setup.sh; keeping the version table in the spec; a default fallback key id.

## 2026-09-01 — Inventory: login PATH, then vendor-dir fallback

**Decision:** `inventory.local.md` resolves each CLI with (1) login shell `command -v`, then (2) executable files in `~/.opencode/bin`, `~/.grok/bin`, `~/.local/bin`. `mise_managed()` in the updater stays (1) only. No `~/.local/bin` symlink, no `.bashrc`/`.profile` edits. A missing command is `unknown`/`missing`; stderr is never a version string.

**Why:** Official OpenCode (and Grok) installers put the binary in a vendor dir and prepend that dir in `.bashrc`. Ubuntu `.bashrc` returns immediately for non-interactive shells (`case $-` interactive-guard), and inventory probes with `env -i bash -lc`, so Ubuntu reported OpenCode missing and stuffed `command not found` into the version cell even though `~/.opencode/bin/opencode` existed and the updater already had that dir on its own PATH. Omarchy may install the same tools via mise; those shims show up in step (1) and must keep winning, or the updater would CDN-upgrade a shadowed leftover vendor binary.

**Rejected:** Unconditional `~/.local/bin/opencode` symlink (shadows mise on Omarchy). Teaching `setup.sh` to edit the user's `.profile` (1config does not own dotfiles; public forks would inherit that). Putting vendor dirs into `mise_managed()` (would treat a leftover vendor copy as "the" tool and skip or fight mise).

## Standing — No AI attribution; never bypass signing

Commits and PRs are the user's. `Co-Authored-By: Claude` and "Generated with …" are forbidden. `--no-gpg-sign` is forbidden. Recorded in `AGENTS.md` as HARD RULEs.

## Standing — `create_project` / `checkpoint_project` never publish

Neither trigger runs `git init`, `git remote add`, or `gh repo create`. A project without a repo or remote is a deliberate state. Checkpointing is note-taking, not a release.

## Standing — Tool-internal memory off

Claude project `memory/` dirs are DISABLED stubs. Grok `[memory] enabled = false`. Durable facts go to markdown. Cron guards wipe residue.

## Standing — Papers are LaTeX, no bibliography

`writepaper_project` assumes `texlive-full` (Ubuntu) or `texlive-meta` (Omarchy). No `\cite`, no `refs.bib`. Author block is this user's unless a fork changes it.
