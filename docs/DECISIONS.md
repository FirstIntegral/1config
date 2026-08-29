# Brain decisions

ADRs for `~/.agents` / `github:FirstIntegral/1config`. Project work logs decisions in *that* project's `docs/DECISIONS.md`. This file is the brain's own.

## 2026-08-29 — Full Bash autonomy (`bash_without_prompt: true`)

**Decision:** All three tools run without Bash permission prompts. Claude `bypassPermissions`, Grok `always-approve`, OpenCode `permission.bash["*"] = allow`.

**Why:** Claude's allowlist cannot remove hard-coded safety prompts (`cd`+write, `cd`+git / untrusted hooks, some parse verdicts). The only switch that actually kills them is `bypassPermissions`. The user chose that 2026-08-29.

**Cost:** Claude ask/deny lists become best-effort (bypass skips checks). Generic `git push` no longer prompts. This is **not** a default most people want.

**Flip:** `permissions.json` → `"bash_without_prompt": false`, then `bash ~/.agents/setup.sh`. Documented in `README.md` on purpose so forks see it.

**Rejected:** Leaving Claude on `acceptEdits` and expanding the allowlist. Empirically insufficient.

## 2026-08-29 — Dedicated `gpg-signing` keyring collection

**Decision:** Store the GPG passphrase in a gnome-keyring collection labelled `gpg-signing` (empty master, autologin-safe), not in the default collection. Unlock scans bricked on-disk `.keyring` files and restocks.

**Why:** gnome-keyring 50 cannot reload an unencrypted default keyring after any item's `secret=` contains a raw newline (Proton JSON, etc.). Journal: `invalid or unrecognized format`. SearchItems then empty even though the GPG item is still in the file. A one-item collection does not pick up those secrets.

**Rejected:** Sharing the default collection; calling `Service.Unlock` (GUI prompt); encrypting the collection with the login password (autologin has none).

## 2026-08-29 — Omarchy + Ubuntu, inventory is machine-local

**Decision:** The same clone + `setup.sh` must work on Omarchy (Arch) and Ubuntu (Debian), fresh or `git pull` on an existing box. Live grok/claude/opencode versions live in gitignored `inventory.local.md`, not in `SETUP.md`. GPG key id comes from `git config --global user.signingkey` / `$GPG_SIGNING_KEY`, never a hardcoded key from another machine.

**Why:** Pinning versions in `SETUP.md` made Ubuntu fail verify after pulling Omarchy's table (and would dirty git the other way). Hardcoding `95FBA6E0AA245342` made a second machine unlock the wrong key. `setup.sh` prints the distro-correct package line and does not run `apt`/`pacman`.

**Rejected:** Auto-installing packages from setup.sh; keeping the version table in the spec; a default fallback key id.

## Standing — No AI attribution; never bypass signing

Commits and PRs are the user's. `Co-Authored-By: Claude` and "Generated with …" are forbidden. `--no-gpg-sign` is forbidden. Recorded in `AGENTS.md` as HARD RULEs.

## Standing — `create_project` / `checkpoint_project` never publish

Neither trigger runs `git init`, `git remote add`, or `gh repo create`. A project without a repo or remote is a deliberate state. Checkpointing is note-taking, not a release.

## Standing — Tool-internal memory off

Claude project `memory/` dirs are DISABLED stubs. Grok `[memory] enabled = false`. Durable facts go to markdown. Cron guards wipe residue.

## Standing — Papers are LaTeX, no bibliography

`writepaper_project` assumes `texlive-full` (Ubuntu) or `texlive-meta` (Omarchy). No `\cite`, no `refs.bib`. Author block is this user's unless a fork changes it.
