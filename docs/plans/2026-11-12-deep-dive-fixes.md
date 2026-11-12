# Deep-dive fixes Implementation Plan

> **For agentic workers:** implement this plan task-by-task, in order. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the security, bug, and improvement items from the 2026-11-12 review of 1config, except the ones an ADR already decided the other way.

**Architecture:** Shell and Python only, same layout as today. New shared pieces are sourced libraries under `hooks/` (`git-url.sh`, `tool-path.sh`, `verify-incoming.sh`, `secret-scan.sh`). `verify.sh` keeps every check and gains a `--repo` scope that skips machine state, so CI and a login run the same file.

**Tech Stack:** bash, python3 (stdlib), git, gpg, systemd user units, GitHub Actions.

**Spec:** the review report in the 2026-11-12 session (8 security, 16 bug, 9 improvement items). Item numbers below are that report's.

## Global Constraints

- Every brain edit ends with `bash ~/.agents/setup.sh` then `bash ~/.agents/sync.sh -m "<subject>"`. Verify must print `== PASS (warnings=0) ==`.
- Signed commits. No AI attribution. No force-push.
- Tool parity: Claude Code, Grok, OpenCode, Cursor Code. A change with no verify check is not done.
- A fixture never touches the network, the real machine-notes clone, or this machine's git config.
- `AGENTS.md` loads into every session. Add a line there only when an agent must act on it.
- Red lines wait for a yes: GitHub repo settings, deleting keyring files.

## Not done, on purpose

| Item | Why |
|---|---|
| S5 GPG passphrase store | ADR 2026-08-29 "Dedicated `gpg-signing` keyring collection" chose it. Deleting `Default*.bricked-*` files is a red line. |
| I1 shrink `AGENTS.md` | ADR 2026-10-09 rejected "Splitting the rules file into on-demand markdown" and a size cap. |
| I7 revisit bypass | ADR 2026-09-27 "Opinionated default is on": autonomy is the direction. |
| I8 flight recorder | ADR 2026-10-21 rejected "A new diary under another name"; `## Kept out` bans a daily diary. |
| S7 review step before append | `AGENTS.md` says the stray merge is automated and needs nothing typed. Only the tool access, argv, and PATH faults are fixed. |
| B7 `brwsk.vigil` anchor | ADR 2026-10-15 chose it, with a fallback to the start of the list. |
| S1/S2 GitHub settings | Branch protection, secret scanning, push protection: named in the report, waiting for a yes. |

## Review Focus

1. A second machine whose keyring holds the author's public key without ownertrust: its login pull must still work. `BRAIN_SIGNERS` lists the fingerprint; fixture covers `U` plus listed.
2. An ssh host alias (`git@gh-work:Owner/repo`) or an `insteadOf` alias: the owner veto must resolve it, not refuse it. Fixture covers both.
3. `crontab -l` failing for a reason other than "no crontab": setup must not install a crontab that drops the user's lines. Fixture with a stub `crontab`.
4. A checkpoint on a repo that already tracks `.env.example` or a staged key file: only an untracked secret-named file refuses. Fixture covers tracked and untracked.
5. A machine with no systemd user manager (container, ssh-only box): setup must fall back to cron and verify must pass. Fixture with a stub `systemctl`.

---

### Task 1: verify.sh scope and hermetic fixtures (I3, I2 split, B7)

**Files:** Modify `verify.sh`, `hooks/checkpoint.sh`. Create `hooks/git-url.sh`.

- [x] `verify.sh --repo` skips machine state (`machine()` predicate). Default scope is unchanged.
- [x] One `VTMP="$(mktemp -d)"` with an EXIT trap. Every fixture temp path and every fixed `/tmp/*.out` name moves under it.
- [x] Fixture sections export `GIT_CONFIG_GLOBAL="$VTMP/gitconfig"` and `GIT_CONFIG_NOSYSTEM=1`, and unset them after.
- [x] `checkpoint.sh` reads `BRAIN_REMOTE_FILE` and `FORK_PARENTS_FILE` when set (verify only). Fixtures use owner `fixture-owner`, parent `fixture-parent`.
- [x] The `fork-parents.txt` check accepts any well-formed file, not the omalauncher line.
- [x] Regression check: the sorted `OK` lines of a default run before and after differ only by the renamed fixtures.

### Task 2: one URL parser, host plus owner veto (S3)

**Files:** Create `hooks/git-url.sh`. Modify `hooks/checkpoint.sh`, `hooks/notes-sync.sh`, `BRAIN_REMOTE`.

**Interfaces:** `git_url_parse URL` prints `host owner repo` (lowercase) or nothing. `git_url_host_effective HOST` resolves an ssh alias with `ssh -G`. Notes keys keep the literal host.

- [x] Parses `user@host:o/r`, `ssh://[user@]host[:port]/o/r`, `git://`, `https://[user@]host[:port]/o/r`. `ssh.github.com` folds to `github.com`.
- [x] Veto is "parsed, and the host/owner pair is not on a `BRAIN_REMOTE` line". Unparsed stays not a veto.
- [x] An ssh host goes through `ssh -G`. A URL that is not ours is tried once more after `insteadOf`.
- [x] Fixtures: `ssh://` outside owner exits 14, same owner on another host exits 14, ssh alias to our owner pushes, existing notes keys are byte-identical.

### Task 3: signed incoming commits (S1, B6, B16a)

**Files:** Create `hooks/verify-incoming.sh`, `BRAIN_SIGNERS`. Modify `hooks/brain-sync.sh`, `sync.sh`, `hooks/gpg-git.sh`, `boot-dashboard/dashboard.sh`.

**Interfaces:** `verify-incoming.sh REPO BASE TIP` exits 0 trusted, 5 web-flow tip, 6 unsigned or unknown signer. Accepted: `%G?` is `G` or `U`, and `%GP` is this machine's signing key or a `BRAIN_SIGNERS` line. First-parent chain only.

- [x] `brain-sync.sh` exits 5 or 6 before the fast-forward. Dashboard: 5 is a warn with the pull command, 6 is a fail.
- [x] The dashboard runs the same gate on `~/Projects/omarchy-dots` before it calls that repo's `sync.sh` with `DOTS_SYNC_SKIP_FETCH=1`.
- [x] `sync.sh` fetches first. Behind and clean fast-forwards through the gate. Behind with an overlap, or diverged, stops before setup.
- [x] `gpg-git.sh` runs the unlock hook only when git asked for a signature.
- [x] Fixtures use two throwaway keys in a temp `GNUPGHOME`.

### Task 4: nothing secret or oversized leaves (S2, S4)

**Files:** Create `hooks/secret-scan.sh`. Modify `sync.sh`, `hooks/checkpoint.sh`, `project-template/.gitignore`, `SETUP.md` §5 block.

- [x] `secret-scan.sh REPO [BASE]` scans added lines of what `git add -A` would commit, through a temp index. Built-in token patterns; `gitleaks` too when it is on PATH. `gitleaks:allow` on a line skips it.
- [x] `checkpoint.sh` exit 20 also covers an untracked secret-named file, an untracked file over 50 MB (`CHECKPOINT_MAX_FILE_MB`), and a scan hit.
- [x] `sync.sh` refuses to commit on a scan hit.
- [x] Template `.gitignore` ignores `.env`, `.env.*` (not `.env.example`), `*.pem`, `*.keystore`, `*.jks`, `keystore.properties`, `local.properties`.

### Task 5: supply chain (S6, S8)

- [x] `hooks/install-elan.sh` pins elan `v4.2.4` and its sha256 per arch, with `--version` and `--sha256` for a bump. Fixture: wrong sum runs nothing.
- [x] `vendor/jeepney/LICENSE` plus `vendor/jeepney/UPSTREAM.md`. Verify checks both.

### Task 6: stray merge without tools (S7 part, B1, B2, B13)

**Files:** Create `hooks/tool-path.sh`. Modify `hooks/merge-strays.sh`, `boot-dashboard/dashboard.sh`.

- [x] Prompt goes in through a file or stdin. Claude runs with `--tools ""`, Grok with `--tools list_dir` (its allowlist cannot be empty) and no subagents or web, OpenCode with a deny-all permission env. Backends are tried in order.
- [x] `agents_tool_path` is the login-shell PATH, then the vendor dirs. Dashboard and merge-strays use it.
- [ ] The guard run is one ordered chain: links, stray merge, memory.

### Task 7: bugs

- [ ] B3 `heredoc-rewrite.py`: `hookSpecificOutput.updatedInput`, no permission decision, `io.py` opens with a mode, body keeps its last newline. Verify runs the rewritten command.
- [ ] B4 `local.json` `caveman`: setup writes one generated rule per tool; verify checks all four.
- [x] B5 `safe_rel` rejects `*`, `?`, `[`, and a backslash.
- [ ] B8 `opencode-skill-list.sh`: an empty standalone list retries against the running service.
- [ ] B9 Claude deny rules hold under `bypassPermissions`: `AGENTS.md`, `SETUP.md`, `README.md`, one ADR.
- [x] B10 `notes-sync.sh` stashes a leftover from an interrupted run; fetch and push are time-bounded. I9c: an offline pull prints `notes: skipped`.
- [ ] B11 `setup.sh` removes its backup dir when empty and prunes empty `setup-*` dirs.
- [x] B12 `boot-check.sh` skips the network wait when no tool needs a direct update.
- [ ] B14 `paper-template/build.sh` skips `.lake/` and prints an axiom audit.
- [ ] B15 `setup.sh`: `shell.json` is validated before it is replaced; a failed `crontab -l` leaves the crontab alone.
- [ ] B16 dashboard checks four links and never prints a blank version; README facts; checkpoint push is time-bounded; guard logs are capped.

### Task 8: timers (I4)

- [ ] `setup.sh` installs `1config-guards.timer` (daily, `Persistent=true`, plus at login) and `1config-updater.service` when a user manager answers, then drops its own crontab lines. No user manager: cron as before. `AGENTS_SCHEDULER=cron` forces cron.
- [ ] Verify accepts either scheduler and fails on both or neither.

### Task 9: adoption kit and entrypoint (I5, I6, I9)

- [ ] `bin/1config <cmd>` dispatches to the existing scripts; setup links it into `~/.local/bin`.
- [ ] `setup.sh --dry-run` runs against a copy of the files it edits and prints the diff.
- [ ] `uninstall.sh` removes links, units, cron lines, and generated rules; it restores nothing it did not back up.
- [ ] `SECURITY.md` with the threat model.
- [ ] Updater reads `gh auth token` before a token file. `watch-stale.sh` sums CPU over the process tree.

### Task 10: CI (I2)

- [ ] `.github/workflows/ci.yml`: `verify.sh --repo`, shellcheck at error severity, `py_compile`, on pull requests and pushes to `main`.

### Task 11: docs

- [ ] `AGENTS.md`, `SETUP.md`, `README.md`, `docs/DECISIONS.md`, `hooks/welcome.js`, `setup-infographic.svg` for each task above, in the same commit as the code.
