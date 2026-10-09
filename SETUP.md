# Unified AI Terminal Setup — Full Spec

Complete, unambiguous spec of this machine's AI-tool setup. `setup-infographic.svg` is the visual summary; THIS file is the authoritative version. An AI given this file + the `~/.agents/` folder can recreate everything exactly. If a brain change alters what the figure depicts (components, flows, toolchain), regenerate `setup-infographic.svg` in the same turn.

**TL;DR (Omarchy or Ubuntu):** clone this repo to `~/.agents` → install whatever `[0] platform` prints as missing → `bash ~/.agents/setup.sh` → machine-local GPG + `gh auth` (see `README.md`). Existing box: `git pull && bash ~/.agents/setup.sh`. Manual path: §8.

Human report + opinionated-default table: **`README.md`**. ADRs: **`docs/DECISIONS.md`**. This file remains the machine spec.

## 1. Inventory

Three CLIs: Grok Build (`grok`), Claude Code (`claude`), OpenCode (`opencode`). Config: `~/.grok/config.toml`, `~/.claude/settings.json`, `~/.config/opencode/opencode.jsonc`.

**Live versions are machine-local.** `setup.sh` and the boot updater write `~/.agents/inventory.local.md` (**gitignored**). Do not commit them — Ubuntu and Omarchy will not share patch versions, and pinning them here made `verify.sh` fail after a pull.

Inventory resolution, in order: (1) login shell `env -i bash -lc command -v` — this is what mise shims look like, and it is the **only** probe `update-apps.sh` `mise_managed()` uses to skip a tool; (2) **vendor-dir fallback** if that is empty, the well-known dirs the updater already puts on its own PATH: `~/.opencode/bin`, `~/.grok/bin`, `~/.local/bin`. Official OpenCode/Grok installers drop binaries there and add PATH in `.bashrc`, which a non-interactive login shell never sources (**interactive-guard**). Without (2), Ubuntu inventory reported OpenCode missing and stuffed `command not found` into the version cell. (2) does **not** mutate PATH and does **not** symlink into `~/.local/bin`, so an Omarchy mise shim that *is* on login PATH still wins. A missing command is version `unknown` / path `missing`; stderr is never copied into the table.

Tools whose login-shell PATH resolves under mise are skipped by the updater; mise's own upgrade cadence (`minimum_release_age`) governs them. The updater still refreshes inventory (which may show the mise path from step 1).

**Platform:** Linux. **Supported: Omarchy (Arch) and Ubuntu (Debian).** Requires: `python3`, `flock`, `git`. Wants: `cron` (Ubuntu) / `cronie` (Omarchy/Arch), `gpg`, `gnome-keyring`. Optional: `texlive-full` (Ubuntu) / `texlive-meta` (Omarchy); Lean 4 via user-space `elan` (`bash ~/.agents/hooks/install-elan.sh` — not a distro package, not `setup.sh`). No root, no package installs from `setup.sh` (except the optional systemd-sleep shim — see that cron-job’s README). `setup.sh` `[0] platform` detects the family and prints the distro-correct install line.

### Opinionated defaults (this repo — many people will not want them)

Canonical file: `permissions.json`. The opinionated default is on: `bash_without_prompt` true. A fresh clone gets Claude `bypassPermissions`, Grok `always-approve`, OpenCode bash `"*" = allow`, and setup omits ask fan-out. Deny still copies. Generic `git push` does not prompt. Gitignored `local.json` may set the key false; `setup.sh` merges that into the live tools only. Full table: `README.md`. Why: `docs/DECISIONS.md`.

### Local overlay

`local.json` is gitignored and optional. Missing file means the opinionated default is on: Bash autonomy and caveman full. Copy `local.json.example` to `local.json` only to opt out (`bash_without_prompt` false, `caveman` off). `BRAIN_REMOTE` is the origin allowlist for `sync.sh`, `verify.sh`, and boot sync. A fork edits that file, not the scripts.

### Red lines

Red lines are in canonical `AGENTS.md`. Destructive or hard-to-undo acts, and anything under Leaves the machine, wait for an explicit yes even when Bash autonomy is on. A quoted message is a draft.

### Boot dashboard (graphical login)

On any XDG graphical login, a terminal opens with a one-screen summary of boot health (symlinks, guards, `verify.sh`, tool versions, tool-updater log). The desktop entry has no `OnlyShowIn` filter, so both Wayland sessions such as Hyprland and X11 desktops run it. Lives in `~/.agents/boot-dashboard/`. Installed by `setup.sh` → `~/.config/autostart/agents-boot-status.desktop`. Manual: `bash ~/.agents/boot-dashboard/launch.sh`.

The dashboard also runs **brain self-sync** (`hooks/brain-sync.sh`) right after the network check: it fetches `origin/main` and, when the local `~/.agents` checkout is **behind** the remote listed in `BRAIN_REMOTE`, fast-forwards to match it. Fast-forward only, against those URLs only, never over uncommitted local edits or unpushed commits, and never prompting (ssh `BatchMode`, time-bounded fetch). Exit codes: `0` up-to-date/ff'd · `1` fetch failed · `2` local ahead · `3` behind + dirty tree · `4` divergence / not-a-repo / URL not in `BRAIN_REMOTE`. A stale, diverged, or dirty brain is a warn (or fail for `4`) on screen, never silently rewritten.

On exit, `dashboard.sh` overwrites `~/.agents/boot-dashboard/close-slip.txt`. One line per warn or fail that is not the tool-updates row (that row already lives in `~/cron-jobs/ai-terminal-tools-update-on-boot/update-apps.log`), using the status, label, and detail the row showed. Newlines in the detail become spaces. No such row writes the single word `CLEAN`. The file is gitignored. A missing file means the dashboard has not exited since the slip existed. `BOOT_DASHBOARD_SLIP` overrides the path for tests. Ok and skip rows are not written.

## 2. Canonical rules file

`~/.agents/AGENTS.md` — the ONE global rules file. All three tools read it every session via the symlinks in §3. Loaded once per session start. **Keep it LEAN** (cross-project rules only; project facts go in project files) — every extra paragraph costs context on every session of every tool.

Sections, in order:
1. Header — wiring map + migration one-liner
2. Git/GitHub attribution — HARD RULE (no AI attribution in commits/PRs)
3. Git commit signing — HARD RULE (never bypass signing; keyring auto-unlock; manual fallback)
4. Permission policy — canonical `~/.agents/permissions.json`, fanned out to all three tools by `setup.sh` steps 5b/5c/5d (§4); includes the "prompts an allowlist cannot remove" subsection
5. Tri-tool parity — HARD RULE: every feature lands in Claude Code + Grok + OpenCode, installed by `setup.sh`, checked by `verify.sh`
6. Machine toolchains — `texlive-full` + `tectonic` installed; Lean 4 via `elan` (user-space hook, not a distro pkg); write LaTeX directly, never ask for TeX/Lean installs
7. Detached runs / staleness watch — HARD RULE (`hooks/watch-stale.sh`, default 10 min; §4c)
8. Caveman mode — ALWAYS ON (full). `local.json` key `caveman` is the durable opt-out (`off`, `lite`, `ultra`)
   Red lines sit with the hard rules: destructive acts and anything that leaves the machine wait for a yes, even when Bash autonomy is on.
   Herd boards sit after caveman and before the triggers (§5f): one wall, a post that only agrees is noise, a missing file said aloud. Kept out: `SOUL.md`, daily diary, personal heartbeat.
9. `create_project` trigger (§5)
10. `continue_project <path>` trigger (§5b)
11. `checkpoint_project` trigger (§5c)
12. `writepaper_project` trigger (§5d)
13. `global_brain_update` trigger (§5e) — changes to `~/.agents` itself, ending in `setup.sh` + `sync.sh`
14. Global workflow (session start / during / end)
15. Memory policy (§6)

## 3. Symlinks

```bash
ln -s ~/.agents/AGENTS.md ~/.grok/AGENTS.md
ln -s ~/.agents/AGENTS.md ~/.config/opencode/AGENTS.md
ln -s ~/.agents/AGENTS.md ~/.claude/CLAUDE.md
```

- Back up any pre-existing regular file before replacing it.
- Reads AND writes through any of these paths land in the canonical file.
- Each tool only ever opens its own expected path; the OS resolves the link.

## 4. Tool-specific config

### Grok — `~/.grok/config.toml`

Append/merge these switches while preserving other config. The brain-managed permission buckets are the explicit replacement exception described below:

```toml
[compat.claude]
agents = false   # don't double-inject CLAUDE.md files (same content as AGENTS.md)
rules = false

[memory]
enabled = false  # memory lives in shared markdown, not grok's store
```

(`skills`/`mcps`/`hooks` compat intentionally left enabled.)

- **Grok memory dir removed.** If `~/.grok/memory/` exists, `setup.sh` archives it under `~/.agents/backups/setup-<ts>/grok-memory/` then deletes it. Do not recreate.
- **Permission rules** — `setup.sh` step `5c` replaces `[permission] allow / ask / deny` from `~/.agents/permissions.json`, filtering out unsupported non-`Bash` rules. Replacement makes revocations effective. **While `bash_without_prompt` is true, the ask bucket is written empty:** Grok always-approve still honors shell `ask` rules, so leaving `Bash(git push)` in ask would re-prompt. Unknown existing keys such as structured `rules` cause setup to stop before writing instead of silently deleting them; move desired policy into canonical first. The transformed TOML is parsed before replacing the live file.
- **`permission_mode` is brain-managed** — step `5c` maps Bash autonomy to `always-approve`, edit-only autonomy to `acceptEdits`, and both flags off to `ask`. **Current `permissions.json`: `bash_without_prompt` true → Grok `always-approve`.** Many people will not want that; flip the flag.

### Claude Code

- Global file `~/.claude/CLAUDE.md` → symlink (§3).
- **Project AGENTS.md** — Claude Code 2.1.277 and later reads a project `AGENTS.md` when no `CLAUDE.md`, `.claude/CLAUDE.md`, or `CLAUDE.local.md` sits in the working directory or a parent. The user file `~/.claude/CLAUDE.md` does not suppress that read, and Claude does not read `~/.claude/AGENTS.md` as user instructions, so the global symlink stays. Default instruction mode is `claude-md-or-agents-md`. `claude-md-and-agents-md` also loads `AGENTS.md`. `claude-md` and `managed-only` do not. `setup.sh` step 5 still wires `hooks/load-project-agents.sh` into `hooks.SessionStart`. The hook prints the nearest project `AGENTS.md` (walk stops before `$HOME`, cap `AGENTS_CAP` bytes) only when the native read will not happen: Claude older than 2.1.277 or version unknown, mode `claude-md` or `managed-only` or unknown, or the default mode with one of those three suppressing files present. A current Claude on the default mode with no project `CLAUDE.md` gets one copy, from Claude itself. **Never create a project CLAUDE.md** — it hides `AGENTS.md` from the native reader. A disabled built-in `AGENTS.md` plugin is not detected; the hook then stays quiet on 2.1.277+ and the project file is missed until the plugin is on.
- **Auto-memory wiped to a stub only.** For every `~/.claude/projects/*/memory/` dir (including empty ones): archive anything that is not already a lone DISABLED stub, delete all other files in that dir, write exactly:

```markdown
# Memory Index — DISABLED

Disabled by user policy. Do not write memories here.
Durable facts live in `~/.agents/AGENTS.md` (global rules) and the project's
`AGENTS.md` / `session_compact.md` (project facts).
```

- Claude `#` memory shortcut is NOT used (creates project CLAUDE.md / feeds auto-memory — both forbidden).
- **Global permission policy** — canonical source `~/.agents/permissions.json`. `setup.sh` step `5b` replaces `permissions.allow / ask / deny` so removing a canonical rule removes it from the live policy. Other Claude settings survive. Matched allow calls run silently; explicit ask calls prompt; denies block. **While `bash_without_prompt` is true, the ask bucket is written empty** (parity with Grok/OpenCode; Claude bypass already skips ask). Never hand-edit generated global permission buckets. The same file drives Grok and OpenCode; `verify.sh` checks exact content, including stale grants.
- **`permissions.defaultMode`** (added 2026-08-07 as `acceptEdits`; extended 2026-08-07 for full bash auto-approve) — written by step `5b` from the canonical defaults:
  - `bash_without_prompt: true` → `"bypassPermissions"` (**wins**; only mode that kills hard-coded Claude safety prompts such as *cd with write operation* and *cd before git / untrusted hooks*)
  - else `edit_without_prompt: true` → `"acceptEdits"` (file writes only; Bash still uses allow list)
  - else → `"default"`
  **Current `permissions.json`: `bash_without_prompt` true → Claude `bypassPermissions`.** Flip the flag to restore the generic-push review gate.
- **Compound-command matching** (relevant only when not in `bypassPermissions`) — Claude approves a pipeline / `;` / `&&` chain only when **every** segment matches a rule. Allowlist still carries the read-only sysinfo set, read-only git verbs, `sed`/`awk`, etc., so flipping `bash_without_prompt` off does not immediately re-prompt day-to-day probes.
- **Prompts the allowlist can't remove** — obfuscation/parse verdicts, exec wrappers, env runners, and hard-coded compound safety (`cd`+write path-bypass, `cd`+git untrusted-hooks). Full Bash autonomy removes them **and** the generic-push review gate. This repo currently has autonomy **on**; set `bash_without_prompt` false to restore the gate. Heredoc f-strings are separately rewritten by the PreToolUse hook below.
- **Quoted-heredoc parse-verdict class — auto-rewritten via PreToolUse hook** (added 2026-08-07, prompted by 21 heredoc prompts in one Claude session). `setup.sh` step `5e` wires `~/.agents/hooks/heredoc-rewrite.sh` (bash wrapper → `heredoc-rewrite.py`) into `~/.claude/settings.json` `hooks.PreToolUse` with `matcher: Bash`. The hook rewrites quoted-delimiter `python3 -` / `python -` / `cat >> file` / `cat > file` heredocs to scratchpad files under `~/.cache/agents-heredoc/` (7-day sweep) and answers `decision: allow` for the rewritten form, which is allowlist-shaped (`python3 <file>`). Unquoted heredocs and heredocs under `bash`/`sh`/`sudo`/anything else produce **no decision** and still prompt. **Claude-only, recorded per the parity rule:** Grok and OpenCode do not have Claude's parse-verdict prompt class or a matching PreToolUse rewrite mechanism; the behavioral rule in `AGENTS.md` (prefer script files over heredocs) applies everywhere. Verified by `verify.sh` `[claude heredoc-rewrite hook]` section, including five smoke tests.
- **TeX** — `texlive-full` (TeX Live 2025) is installed machine-wide, plus `tectonic` in `~/.local/bin`. All engines/build tools are allowlisted; `tlmgr install` is not, and is unnecessary under the full scheme.
- **Lean 4** — `elan` → `lean` + `lake`, user-space under `~/.elan`. Not a distro package. `setup.sh` probes non-fatally (`ok elan` / `MISSING` + the hook command), same shape as TeX, and **never downloads**. Install path is `bash ~/.agents/hooks/install-elan.sh` (official GitHub tarball, then run the binary — never `curl | sh`; `--default-toolchain none`; does not edit `.bashrc`/`.profile`). Paper `build.sh` prepends `~/.elan/bin`. Allowlisted: `elan`/`lean`/`lake` + the hook. Not allowlisted: `curl`, AUR `elan-lean`, distro `lean4`. Pin lives in `paper-template/lean/lean-toolchain` as exact `leanprover/lean4:vX.Y.Z`. Mathlib is opt-in per paper, never in the template. `leanlab` (PyPI) is unrelated.

### OpenCode

Reads `AGENTS.md` natively at global and project level — no rules wiring needed.

- **Permission rules** — `setup.sh` step `5d` replaces OpenCode's `permission.bash` map from canonical `Bash(X)` rules, making removals effective. Order: managed catch-all first (`"*": "ask"` normally, `"allow"` under full Bash autonomy), then allow, then ask (**omitted when `bash_without_prompt` is true** — last-match would re-prompt `git push` over `"*": allow`), then deny. OpenCode takes the last match, so deny still wins over the catch-all. Non-`Bash` rules are skipped. Other OpenCode config survives. Valid JSONC comments and trailing commas are accepted; output becomes plain JSON after a backup. Deny `rm -rf` rules are exact `/` `~` `$HOME` only — a trailing `/*` is a glob and would deny every `rm -rf /…` (glass 2026-09-05). Literal `rm -rf /*` is Vigil rm-root, not a harness glob.
- **`external_directory`** — OpenCode-only gate that prompts on any file access outside the project cwd (e.g. `/tmp` scratch scripts, screenshots) regardless of the bash catch-all. Step `5d` sets `permission.external_directory` = `allow` while `bash_without_prompt` is true, else `ask`. Claude (`bypassPermissions`) and Grok (`always-approve`) cover out-of-tree access natively — recorded per the parity rule. Checked by `verify.sh` `[permission parity]` as `opencode-external_directory` (added 2026-09-05 after repeated `/tmp` prompts with autonomy on).

### GPG signing unlock (Secret Service keyring)

- Passphrase lives in a **dedicated** gnome-keyring collection labelled `gpg-signing`, empty master (autologin has no PAM password, so a login-locked collection would never open). Isolated from the default collection on purpose.
- **Why dedicated (verified 2026-08-29, this machine):** gnome-keyring 50 cannot reload an unencrypted `.keyring` file after any item's `secret=` contains a raw newline (Proton JSON via Python keyring, etc.) — journal: `keyring was in an invalid or unrecognized format`. SearchItems then returns empty even though the GPG item is still in the file. A one-item collection does not pick up those secrets, so it survives reboot. Unlock scans bricked files and restocks the dedicated collection when the live daemon has nothing.
- `hooks/gpg-keyring.py` — jeepney helper: SearchItems uses **both** `(unlocked, locked)` arrays; never `Service.Unlock` (that GUI-prompts); empty-master via `CreateWithMasterPassword` / `UnlockWithMasterPassword`. `fetch` / `store` / `self-test`.
- `hooks/gpg-agent-unlock.sh` — test-sign; on miss, `gpg-keyring.py fetch` + `--pinentry-mode loopback`. Boot dashboard runs this **first** at graphical login (before tool-update / verify). Exit `0` cached-or-unlocked · `1` passphrase rejected · `2` dbus · `3` nothing stored.
- `hooks/gpg-git.sh` — git's `gpg.program`. Loopback only; on cache miss runs unlock and retries. `setup.sh` points `git config --global gpg.program` here so commits never open `pinentry-gnome3`.
- `hooks/gpg-store-passphrase.sh` — one-time store into the dedicated collection (prompts once). Re-run after a passphrase change.
- **gnome-keyring 50.x API quirk (verified 2026-08):** `CreateItem` lives on the **Collection** interface (not Service), `GetSecret` on the **Item** interface, and the Secret struct signature is `(oayays)` with a single `ay` parameters field. The plain-session handle marshals correctly only via the **vendored `jeepney`** (`~/.agents/vendor/jeepney`, MIT, pure python — dbus-python/GLib validate object paths and fail). No system packages needed.
- `~/.gnupg/gpg-agent.conf` already: `allow-loopback-pinentry`, `default-cache-ttl 31536000`, `max-cache-ttl 31536000` (1-year cache after first unlock).
- Signing key id: `$GPG_SIGNING_KEY` or `git config --global user.signingkey`. Never a hardcoded key from another machine.
- Fallback: re-run the store script, or manual unlock in a real terminal (see canonical `AGENTS.md`).

### §4b `hooks/checkpoint.sh` — the git half of `checkpoint_project`

Steps 1-5 of that trigger need judgement (what happened today, which decisions to log) and stay with the AI. Step 6 is mechanical, has one correct answer per project state, and was being re-derived by hand inconsistently — so it is a script. All three tools call the same one, via the trigger in canonical `AGENTS.md`; nothing tool-specific.

```sh
bash ~/.agents/hooks/checkpoint.sh <project-root> [-m SUBJECT] [--dry-run]
```

Exit codes: `0` remote backup completed (new commit and/or existing commits pushed) · `3` clean tree and `HEAD` has no commit absent from local remote-tracking refs · `10` not a repo · `11` inside another repo · `12` no remote (committed locally) · `13` remote unreachable (committed, not pushed) · `20` refused, session files would be published · `21` commit/push failed · `22` brain checkout, nothing done · `2` usage.

Invariants, all covered by `verify.sh`:

- **Never** `git init`, `git remote add`, `gh repo create`, `--force`, rebase/reset/amend, or `--no-gpg-sign`. A project without a repo or remote is in a deliberate state.
- Refuses **before staging** if `session_compact.md` / `session_transcript.md` / `claude_memory_import.md` are tracked or unignored — publishing the private transcript is the one failure here that cannot be walked back.
- Requires the given directory to **be** the repo toplevel; `rev-parse --show-toplevel` walks up, so a subdirectory would otherwise commit an unrelated parent repo.
- Reachability uses bare `git ls-remote`, **not** `--exit-code`: that flag returns 2 when no refs match, so an empty freshly created repo would be misread as unreachable and the first push silently refused.
- Cross-checks the URL against the project `AGENTS.md` `## Repo` line and warns on mismatch, but git config always wins — `AGENTS.md` is a file an AI writes and must never authorise a push.
- **A clean tree is not the same as nothing to do.** Commits made earlier and never pushed are exactly the state where "the machine is not the only copy" fails, so a clean tree still takes the push path and only skips the commit. Local unpushed state is counted as `HEAD --not --remotes`; no fetch occurs, so exit `3` does not claim a live remote is reachable or unchanged.
- `verify.sh` runs the refusals and the push path for real against scratch dirs and a bare remote (non-repo → 10 with no `.git` created; unignored transcript → 20; brain checkout → exit 22 with no git command; clean tree with one locally unpushed commit → pushed, exit 0; clean with no locally unpushed commit → exit 3).
- The brain checkout exits 22 before any git command. That is the directory `checkpoint.sh` lives in, and a worktree whose `origin` is listed in its `BRAIN_REMOTE` and which contains `setup.sh` and `verify.sh`. `sync.sh` is the publisher. `checkpoint.sh` does not run `verify.sh`, so it must not be a second door onto this repo.

### Rule oracles, policy keys, retired names

`hooks/rule-oracles.sh` is the `create_project` path rule as a shell fixture. `verify.sh` runs it. Simple name `foo` resolves to `~/Projects/foo`. A name containing `/` is resolved as given and is not moved under `~/Projects`. An empty name exits 30 (ask). The same run fails if a script under `hooks/`, `updater/`, or `boot-dashboard/` reads `session_transcript.md`. Naming the file in a gitignore check or an append instruction is allowed.

Keyed facts in `docs/DECISIONS.md` use a `**Policy:**` line. One active value per key. A replaced value keeps a `superseded-by` line whose text is the heading that holds the live value. `verify.sh` fails on a second active value or a target heading that is not in the file. Whole headings stay when one ADR mixes a live fact and a dead one.

Retired names live in `hooks/kill-tokens.deny` (one literal token per line; an empty file is legal). `merge-strays.sh` does not append a section that contains one; the stray stays. `verify.sh` fails if a token appears in `AGENTS.md`, `README.md`, the project-template markdown, or `SETUP.md` outside a fenced `gitignore` sample. `project-template/.gitignore` may still name a retired path so new projects keep ignoring it.

### §4c `hooks/watch-stale.sh` — staleness watch for detached runs

Every long-running **job** launched detached is armed with one, in the same turn, per the canonical
`AGENTS.md` rule. Tool-agnostic bash: Claude drives it through its Monitor/background-task
mechanism, Grok and OpenCode by backgrounding it and reading its stdout — the script is identical
and lives in one place.

**Not for preview/dev servers** (`http.server`, `npm start`, …). Those are idle-by-design; a
staleness watch would false-alarm. Kill them at end of turn unless the user still needs the URL
(`AGENTS.md` — "Preview / dev servers are not jobs"). Grok's TUI `◎ 1 command still running` line
stays up until that background task dies — that is the TUI, not a hang.

```sh
bash ~/.agents/hooks/watch-stale.sh <pid> <logfile|-> [interval_seconds]   # default 600
```

One stdout line per interval (`alive` / `STALE`), one final `EXITED` line, then it ends on its own.
Exit codes: `0` watched process exited · `2` usage · `3` no such pid.

Invariants, covered by `verify.sh`:

- **Stale requires BOTH** flat log growth and under 1s of CPU across the interval. Either signal
  alone is a working run — a job inside one expensive step writes nothing, a job blocked on I/O
  still writes — and single-signal alerting yields false hangs until the watch is ignored.
- **CPU is read from `/proc/<pid>/stat` fields 14+15** (utime+stime), parsed *after* stripping
  through the last `)`: the comm field can contain spaces and parens, so positional `awk` on the
  raw line misreads any process whose name is not a single bare word.
- Reports every interval including quiet ones — a watch that speaks only on bad news cannot be
  told apart from a watch that died.
- Watches the pid it is given and never guesses; the caller resolves the *worker* pid
  (`pgrep -af '<interpreter> -u <script> <args>'`), because a shell wrapper burns no CPU and would
  read as hung forever.
- `verify.sh` exercises it for real against a scratch process: an idle pid with a flat log must
  report `STALE`, and the same watch must end with `EXITED` once that pid is gone.

## 5. Per-project standard — `create_project`

Trigger: user says **`create_project`**. Resolve the target before copying: a simple `create_project <name>` means `~/Projects/<name>`; an explicit absolute or relative path containing `/` is used after resolution; a missing name requires a question. Never default a simple name to the current working directory. Copy `~/.agents/project-template/` into the project root, fill in names. Five artifacts: `AGENTS.md`, `session_compact.md`, `session_transcript.md`, `docs/DECISIONS.md`, `.gitignore` (no CLAUDE.md — see §4 Claude hook). If the project already has a `.gitignore`, merge the session-file lines instead of overwriting. Verbatim templates:

### `AGENTS.md`

```markdown
# <Project Name>

## Overview
<what this project is — one paragraph>

## Stack / Conventions
<languages, frameworks, style rules>

## Commands
- Build:
- Test:
- Run:

## Repo
- Remote: `<git@github.com:owner/name.git>`  — or `none (local only)`

Documentation, not authorisation: `checkpoint.sh` cross-checks this against `git remote get-url --push` and warns on a mismatch, but git config is what actually decides where a push goes. Keep this line current when the remote changes; never treat it as permission to push. A project with `none (local only)` is in a deliberate state — nothing may create a repo or remote for it without the user asking.

## Session files
- `session_compact.md` — AI handoff state. Read FIRST at session start; rewrite at end of session / milestone. Local-only (gitignored): never commit unless the user says otherwise.
- `session_transcript.md` — human-ONLY narrative log. Append at milestones; AI NEVER reads it unless the user explicitly asks. Local-only (gitignored): never commit unless the user says otherwise.
- `docs/DECISIONS.md` — ADR log; append decision + why in the same turn it is made. Versioned (committed in repos).
- `.gitignore` — ignores the session files above, `claude_memory_import.md`, and legacy session paths. Sites under `~/Projects/sites/` also ignore `AGENTS.md` / `CLAUDE.md`.
```

### `session_compact.md`

```markdown
# Session Compact — <Project Name>

AI handoff file. Read FIRST at session start. Rewrite (do not append) at end of session / milestone / before compaction.

## Models used
CUMULATIVE — preserve this list across rewrites; add a line whenever model or effort changes.
- <model> · effort: <level> · since <YYYY-MM-DD>  ← current

(mirror every switch in session_transcript.md too — transcript is the lossless copy)

## Current state
<where things stand right now>

## Where we left off
<last completed step + immediate next step>

## Key decisions
- <decision + why>

## Open issues / blockers
- none yet
```

### `session_transcript.md`

```markdown
# Session Transcript — <Project Name>

Human-readable narrative log of work sessions. Append-only, newest at the bottom.
(This file is for the user ONLY — AI agents never read it unless the user explicitly asks.)

---

## <YYYY-MM-DD> — Session 1
<what was discussed, decided, built>
```

### `docs/DECISIONS.md`

```markdown
# Decisions & Rationale (ADRs)

Append an entry (date + decision + why + rejected alternatives) in the same turn a meaningful choice is made.

## <YYYY-MM-DD> <first decision title>
- <decision + why + what was rejected>
```

### `.gitignore`

```gitignore
# Local AI session files — never commit unless the user says otherwise
session_compact.md
session_transcript.md
claude_memory_import.md

# Legacy session paths (retired 2026-07; keep ignored if present)
docs/SESSION.md
docs/session-archive/
docs/session-flushes/

# Sites repos only (~/Projects/sites/*): also ignore agent rules — uncomment or add when creating a site:
# AGENTS.md
# CLAUDE.md

# Lean paper artifacts (opt-in docs/paper/lean/)
docs/paper/lean/.lake/
```

(Does **not** ignore `AGENTS.md` by default — only `~/Projects/sites/*` do; uncomment those two lines or add them when the project is a site.)

### Rules (enforced via the canonical file, all tools)

1. **Session start:** read `session_compact.md` FIRST if it exists. NEVER open `session_transcript.md` — it is the user's private log (Transcript privacy HARD RULE; read only if the user explicitly asks).
2. **During work:** append to `session_transcript.md` at milestones (writing OK, reading not); ADRs to `docs/DECISIONS.md` in the same turn. Before a new tool, script, or service, look for a maintained one; build custom only when that one is dead, unsafe, or the user asked for custom. A required file that is absent is said out loud — name the path; do not invent its contents.
3. **End of session / milestone / before compaction:** rewrite `session_compact.md` — accurate enough for a fresh AI to resume from it alone.
4. Session files live in project root; **never committed unless the user explicitly says otherwise** — template `.gitignore` covers them. `docs/DECISIONS.md` IS committed in repos.
5. **Model tracking:** at `create_project` record active model + effort (read tool config — `opencode.jsonc` / `~/.claude/settings.json` / `~/.grok/config.toml` — or ask user once). The **Models used** list is CUMULATIVE: preserve across rewrites, mark current, add a line on any model/effort change. Every switch ALSO appended to `session_transcript.md` (old → new, reason if known). User says they switched → log immediately.

## 5b. `continue_project <path>`

Trigger: user says **`continue_project <path>`** (example: `continue_project $HOME/Projects/some_dummy_project`).

Before other work, the AI must (must match canonical `AGENTS.md` — that file wins if they ever diverge):

1. Resolve `<path>` (absolute or relative). Must be a directory. If missing/invalid → stop and say so.
2. **Residue / conflict check (all tools):**
   - Memory: if `~/cron-jobs/claude-memory-guard/NEEDS-MEMORY-MERGE` or `~/.agents/backups/claude-residue/PENDING.md` or `<path>/claude_memory_import.md` exists → process memory residue merge **before** relying on project files.
   - Symlinks: if `~/cron-jobs/agents-symlink-guard/NEEDS-SYMLINK-MERGE` exists → process symlink conflict merge before editing global rules.
3. **Read, in order** (only if the file exists):
   1. `<path>/session_compact.md` — where we left off (required read when present)
   2. `<path>/AGENTS.md` — project rules/conventions
   3. `<path>/docs/DECISIONS.md` — durable choices + why
4. **Do NOT** open `<path>/session_transcript.md` unless the user explicitly asks (Transcript privacy HARD RULE).
5. If none of the three files in step 3 exist → say the path has no project session layout; offer `create_project` there (or fix the path).
6. After reading: brief status (current state + where we left off + open issues from compact), then wait for / take the user’s next instruction. Do not invent state that is not in those files.
7. Treat `<path>` as the project root for the rest of the session unless the user points elsewhere.

Same for all three tools.

## 5c. `checkpoint_project`

Trigger: user says **`checkpoint_project`** (done for the day — leave and resume later). Applies to the **current** project (cwd walk-up to nearest project root, stopping before `$HOME`). Must match canonical `AGENTS.md` — that file wins if they ever diverge.

1. Resolve the project root. No session layout there (no `session_compact.md` / `AGENTS.md`) → say so, offer `create_project`.
2. Read `session_compact.md` (state restore). NEVER open `session_transcript.md` (Transcript privacy HARD RULE).
3. Rewrite `session_compact.md` so a fresh AI session can resume from it alone: current state, where we left off (concrete next step), key decisions, open issues, cumulative **Models used** list (current marked).
4. Append a `## <YYYY-MM-DD> — wrap-up` entry to `session_transcript.md` (write-only): what was done today + the next step.
5. Backfill `docs/DECISIONS.md` with any meaningful choices from this session not yet logged (same-turn ADR rule).
6. Run `bash ~/.agents/hooks/checkpoint.sh <project-root> -m "checkpoint: <YYYY-MM-DD> <what moved>"` to commit and push according to §4b. Half-finished work is expected and should still be backed up.
7. Finish with: "Checkpoint saved — next step: <X>", plus the pushed commit hash or the script's exact non-push reason.

Same for all three tools. Formalizes the "End of session / milestone" rule as an explicit trigger.

## 5d. `writepaper_project`

Trigger: user says **`writepaper_project`** (optionally with a path or topic/venue hint). Writes a complete, publication-grade LaTeX research paper about the project. Full spec lives in canonical `AGENTS.md` — that file wins if they ever diverge.

- **Scaffold source:** `~/.agents/paper-template/` → copied to `<project>/docs/paper/` on first run (`main.tex`, `build.sh`, `figures/`, `lean/`, `digit-refuse.cfg`, `digit-refuse.deny`). Later runs extend the existing paper; they never restart it. `lean/` is **default on that first scaffold**. Existing `docs/paper/` without `lean/` is not backfilled. Existing `build.sh` copies are not rewritten to add digit-refuse; the next time that build script is edited for a build, add the same call. Never overwrite a paper's existing Lean files.
- **Author block comes from git:** `git config --global user.name` and `user.email`. Empty either one and stop. The template ships `AUTHOR` / `EMAIL` placeholders, not a personal name.
- **Template contents:** `article` + `amsthm` theorem environments (theorem/lemma/proposition/corollary/conjecture/definition/assumption/example/remark), `mathtools`, `siunitx`, `booktabs`, `pgfplots`/TikZ, `algorithm2e`, `cleveref`, and a red `\TODO{}` macro so every gap is visible instead of guessed. Default `lean/` stub on first scaffold: pinned `lean-toolchain`, core-only `lakefile.toml` (no Mathlib), `Paper.lean` with a real tiny proof (`template_sanity` — delete once real theorems exist), `.lake/` gitignored.
- **No references, by design.** AI-written papers are self-contained: no bibliography, no `refs.bib`, no `\cite`, no reference list. Prior art is described in prose. `verify.sh` fails if bibliography machinery reappears in the template.
- **Build:** `bash docs/paper/build.sh` → `latexmk -pdf` → `main.pdf`, then `~/.agents/hooks/digit-refuse.sh main.tex main.pdf`, then the page count and every open `\TODO`. If `lean/` exists and `lake` is on PATH (build.sh prepends `~/.elan/bin`), also `lake build` and a sorry count. Type errors fail the script. A digit-refuse miss fails the script. Missing `lake` prints `LEAN SKIPPED` and the PDF still ships. `clean` runs `latexmk -C` and `lake clean` when present. Never `lake exe cache get` from `build.sh`. No tool has a Lean plugin, and no tool has its own digit checker — all three run `lake` and digit-refuse via `build.sh`.
- **Digit refuse.** A measurement token in prose must occur as that same token inside a `tabular`, `tabularx`, `tabular*`, `longtable`, `longtabu`, or `tblr`, or inside a `\caption`, in the paper. Tokens are fractions (`100/135`), decimals (`0.212`), percents (`45%`), scientific (`1.2e3`), dash-pairs (`13--2`, `7--3--5`), and integers of three or more digits (`8000`). `\frac{100}{135}` is the token `100/135`. A calendar year `19xx` or `20xx` is not a token. A single-hyphen digit group (`02-23-20174`) is an identifier, not a measurement. An en-dash pair (`13--2`) still is. `\TODO{...}` is not a claim; a cemetery token inside a `\TODO` still fails because it is typeset. Comments are not typeset. Text before `\begin{document}` is not a claim. `digit-refuse.deny` beside `main.tex` is one exact token per line. A bare integer in that file exits 2 and the check does not run. Flags `--fuzzy`, `--near`, `--llm`, `--repo`, `--anywhere`, `--close`, `--substr`, and any other `--` flag exit 2 and write nothing. Scope lives in `digit-refuse.cfg` (`scope=paper|chapter|section`, default `paper`). Chapter and section scope let text before the first marker use every table; a later chapter cannot borrow an earlier table. `skip-cmd=Name` masks one command the way `\TODO` is masked (author slots). The legal tokens are only those reached by `\input` / `\include` on the tex input path, never a repo-wide search. A clean check prints nothing. A miss prints `file:line` and the token. `verify.sh` builds the fixture PDFs.
- **Content hard rules** (in `AGENTS.md`): no invented numbers, no references, no overclaiming — missing measurements become `\TODO{measure: …}` and are reported as Gaps. Kernel-checked = `lake build` green **and** that declaration has no `sorryAx`. Report `n/m kernel-checked Lean statements`. `lake` green is **not** a proof that the Lean statement matches the LaTeX theorem.
- **Lean conversion (fidelity).** The kernel checks the declared Lean type, not the paper sentence. When formalizing: (1) write the statement in Lean first and quote the pretty-printed type in LaTeX, **or** (2) decompose the LaTeX theorem into a committed parts list (objects, hypotheses, conclusion, quantifier order, boundary flags) bound to `\label{thm:…}` not line numbers, emit pedantic Lean from those rows, and script-diff the compiled signature against the rows. Do not freely restate then `lake build`. Until a mechanical xwalk hook exists, Gaps must include `statement-fidelity unmeasured` for every formalized theorem. Dual-formalizer / mutation probes / `xwalk.lock` / litex are **not** installed (P2). `leanlab` is unrelated.
- **Mathlib** is opt-in in that paper's `lakefile.toml` when statements need ℝ / polynomials / ODEs. Template stays core Lean so `verify.sh` never downloads a cache.
- **The paper stays current.** Once `docs/paper/` exists, any scientifically relevant change (method, theorem, assumption, experimental setup, measured number, limitation) updates the paper and rebuilds it in the **same turn** — the trigger does not have to be re-typed. Refactors/tooling changes do not count unless a reported number or stated claim moves. Theory-statement changes update the Lean mirror **if** `lean/` already exists; non-theory edits do not start a proof hunt.
- `docs/paper/` is **committed** (product, not session state). `.lake/` is gitignored.

## 5e. `global_brain_update`

Trigger: user says **`global_brain_update <what to change>`**. Target is `~/.agents` itself, not the current project. Full spec in canonical `AGENTS.md` — that file wins if they ever diverge.

1. Read the brain first (`AGENTS.md`, `SETUP.md`, plus whatever the request touches — `setup.sh`, `verify.sh`, `permissions.json`, `hooks/`, `updater/`, `project-template/`, `paper-template/`, `boot-dashboard/`).
2. Change the **canonical** home of the thing, never a tool-local copy.
2b. If the change alters what `setup-infographic.svg` depicts (components, flows, toolchain), regenerate the figure in this turn, **before** setup/sync.
3. Tri-tool parity: all three tools, installed by `setup.sh`, checked by `verify.sh`.
4. `bash ~/.agents/setup.sh` → must end `== PASS ==`, `warnings=0`.
5. `bash ~/.agents/sync.sh -m "<subject>"` → signed commit + push.
6. Report changed files, verify result, pushed commit.

### The brain is a git repo

This tree is **1config**. The GitHub repo is `FirstIntegral/1config` (`git@github.com:FirstIntegral/1config.git`, `https://github.com/FirstIntegral/1config.git`). On this machine the checkout is `~/.agents/`. "Global brain", "the brain", and the trigger `global_brain_update` all mean this same repo. Edit `~/.agents/`, not a tool-local copy. Branch `main`, signed commits, no AI attribution, `backups/` gitignored. **Any** change under `~/.agents/**` — trigger typed or not — ends the same turn with `setup.sh` + `sync.sh`. Local-only edits are unfinished edits.

`sync.sh` is the single scripted path:

```bash
bash ~/.agents/sync.sh -m "Commit subject"    # setup+verify → signed commit → push
bash ~/.agents/sync.sh --no-setup -m "msg"    # skip installation, still run verify.sh
bash ~/.agents/sync.sh --dry-run              # show what would be committed, change nothing
```

It requires repository root + branch `main`, validates every origin fetch and push URL against `BRAIN_REMOTE`, and requires `== PASS (warnings=0) ==` before any commit, including with `--no-setup`. Normal sync fetches first; `--dry-run` skips both install and fetch so it changes nothing. New commits use explicit `git commit -S`, and every outgoing commit must have a good signature before push. It is allowlisted because it is the narrow verified push path; canonical `permissions.json` still lists generic `git push` as ask (restore-gate), but live tools omit that ask while `bash_without_prompt` is true. `verify.sh` reports dirty/ahead brain state as `INFO`, because that state is expected before sync.

## 5f. Herd boards

Standing rule, not a typed trigger. Full text in canonical `AGENTS.md` (`## Herd boards`) — that file wins if they diverge. All three tools read it through the symlinks. No per-tool copy. No installer step.

When the user asks for tens or hundreds of agents that should talk: one append-only flocked wall, waves so later seats can read earlier posts, honesty with public recants, a parseable last-line token, argument seats do not edit source, one hands seat codes only after a mechanical lock, and argument waves do not run the official measurement seeds. An empty lock is legal. A parallel blast on an empty wall is not a conversation.

A post that only agrees is noise. If a required file is missing, the post says that file is missing; do not invent its contents.

Before a new tool, script, or service, look for a maintained one. Build custom only when that one is dead, unsafe, or the user asked for custom. A required file that is absent is said out loud on any task, not only on a herd wall.

Kept out, on purpose: no `SOUL.md`, `USER.md`, or `IDENTITY.md` (this file is what the tools load; caveman is the voice); no agent-readable daily diary (the transcript stays private); no personal heartbeat (mail, calendar, or a ping after hours of silence). Machine health and job staleness stay the heartbeat.

## 6. Memory policy

- ALL durable memory → shared markdown only: `~/.agents/AGENTS.md` (global rules), project `AGENTS.md`, `session_compact.md`, `docs/DECISIONS.md` (project facts/decisions).
- Tool-internal stores **removed/disabled**: Claude `memory/` dirs = DISABLED stub only (no topic files); Grok `~/.grok/memory/` deleted (config `enabled = false`); OpenCode has none.
- "Remember X": global fact → global file; project fact → project files. Same turn, no exceptions.
- Claude's `#` shortcut is NOT used (user policy). If ever triggered inside a project it would CREATE a project `CLAUDE.md` (retired) or feed auto-memory — never do that; durable facts go to `AGENTS.md` / `session_compact.md` instead.

### 6b. Claude/Grok residue guard (cron)

Claude can re-create topic files under `~/.claude/projects/*/memory/` despite the stub. Cron catches that.

- **Source:** `~/.agents/hooks/check-claude-memory.sh`
- **Installed as:** `~/cron-jobs/claude-memory-guard/check-memory.sh` (copied by `setup.sh` each run)
- **Schedule:**

```
@daily  $HOME/cron-jobs/claude-memory-guard/check-memory.sh
@reboot $HOME/cron-jobs/claude-memory-guard/check-memory.sh
```

- **Behavior:**
  1. Scan every Claude `memory/` dir. Clean = only `MEMORY.md` with "Disabled by user policy".
  2. If residue (topic files, non-stub MEMORY, empty→uncontrolled dir, etc.): archive under `~/.agents/backups/claude-residue/<ts>/`, append to `PENDING.md`, write project `claude_memory_import.md` when path can be resolved, set **`NEEDS-MEMORY-MERGE`** flag, wipe dir back to DISABLED stub only.
  3. If `~/.grok/memory/` exists: archive under the same packet dir, delete it, flag pending.
- **AI merge duty** (cron has no LLM): on session start / `continue_project`, if `NEEDS-MEMORY-MERGE` or `PENDING.md` or `claude_memory_import.md` exists → merge durable facts into standard files; if the project has `session_transcript.md`, append a one-line import note (write-only); then clear flag/pending/import. Full procedure in canonical `AGENTS.md`.
- Log: `~/cron-jobs/claude-memory-guard/check-memory.log`.

### 6c. Sites exception (`~/Projects/sites/*`)

Public site repos: gitignore `AGENTS.md` (+ `CLAUDE.md`). Commit `docs/DECISIONS.md`. Non-site projects commit `AGENTS.md`. Enforced via global `AGENTS.md` (HARD RULE for that path prefix).

## 7. Cron guards

### 7a. Symlink guard

- **Source:** `~/.agents/hooks/check-links.sh`
- **Installed as:** `~/cron-jobs/agents-symlink-guard/check-links.sh` (copied by `setup.sh` each run)
- Schedule: `@daily` + `@reboot`

| State found | Action | Log word |
|---|---|---|
| symlink resolves to canonical | nothing | `OK` |
| symlink points elsewhere | re-point to canonical | `REPOINT` |
| path missing | create symlink | `CREATE` |
| regular file, identical to canonical | re-link, no content change | `FIXED` |
| regular file, diverged (any difference) | quarantine to `~/.agents/backups/strays/`, re-link, append to **`NEEDS-SYMLINK-MERGE`** | `CONFLICT` |

(No auto-append of stray bytes — see suggestion 2026-08; quarantined strays are AI-merged.)

- Log: `~/cron-jobs/agents-symlink-guard/check-links.log`.
- Flag: **`NEEDS-SYMLINK-MERGE`** in same folder (exists only after a CONFLICT).
- **AI merge is automated:** `hooks/merge-strays.sh` (installed to the guard dir, byte-verified; cron `@daily`) feeds each stray to a headless LLM (`claude -p` default, `grok -p` / `opencode run` fallback — `MERGE_LLM_BACKEND` selects), sanitizes the markdown output, appends to canonical with a provenance comment, deletes the stray, clears the flag. If the LLM fails, the flag survives for the next run; manual fallback procedure lives in canonical `AGENTS.md`. Sandbox knobs: `CANON`, `GUARD_DIR`, `STRAYS_DIR`, `MERGE_LLM_MODEL`, `MERGE_MAX_BYTES` (4000), `MERGE_TIMEOUT` (120), `MERGE_SKIP_LLM=1` (report only).

### 7b. Tool-memory residue guard

See §6b. Flag: **`NEEDS-MEMORY-MERGE`** under `~/cron-jobs/claude-memory-guard/` (different name on purpose — never confuse with symlink flag).

### 7c. Tool updater (boot / resume)

- **Source:** `~/.agents/updater/` (`boot-check.sh`, `update-apps.sh`, `on-resume.sh`, `refresh-inventory.py`, `system-sleep-shim.sh`).
- **Installed by** `setup.sh` → `~/cron-jobs/ai-terminal-tools-update-on-boot/` (user scripts only, byte-identical; `update-apps.log` + `.update.lock` stay in the installed dir). `verify.sh` byte-compares.
- **Crontab:** `@reboot .../boot-check.sh` (managed by setup.sh). **Resume:** root-installed systemd hook `/usr/lib/systemd/system-sleep/ai-terminal-tools-update-resume.sh`; install or refresh with `sudo install -o root -g root -m 0755 ~/.agents/updater/system-sleep-shim.sh /usr/lib/systemd/system-sleep/ai-terminal-tools-update-resume.sh`.
- The root hook discovers logged-in users through `loginctl`/`getent`, then asks the system manager to start a delayed transient service with explicit `--uid`, `HOME`, `USER`, and `LOGNAME`. It never executes a user-owned script as root, never relies on root's `$HOME`, and does not detach a child into the sleep hook's cgroup.
- `update-apps.sh` and `setup.sh` refresh **gitignored** `inventory.local.md` only when version rows change. They must not write live versions into this spec. Inventory uses login PATH then vendor-dir fallback (§1); `mise_managed()` stays login-PATH-only.
- mise-managed tools are skipped by `update-apps.sh`: the login-resolved (`env -i bash -lc`) binary is under `~/.local/share/mise/` or is a wrapper delegating to `mise x` (those wrappers set `MISE_MINIMUM_RELEASE_AGE=0`, so mise cadence = every invocation). Direct CDN/`update` calls for them only hit shadowed bins or interactive "managed by a package manager" prompts. The updater still refreshes the inventory.
- Updater, standalone setup, and normal sync share `.update.lock`; sync holds it through verification, commit, and push so inventory cannot change after the gate.

### 7d. Omarchy plugin `firstintegral.1config`

Source: `omarchy-plugin/firstintegral.1config/` (`manifest.json`, `Service.qml`, `BarWidget.qml`, `Panel.qml`, `BrainMap.qml`, `bin/usage.py`). Id `firstintegral.1config`. Kinds `service` and `bar-widget`.

On a machine with `~/.config/omarchy/plugins/`, `setup.sh` deletes and recopies that directory (Omarchy's validator rejects symlinks inside a plugin), runs `omarchy-plugin-validate` when the command exists, and inserts `{ "id": "firstintegral.1config" }` into `bar.layout.right` of `~/.config/omarchy/shell.json` when the id is absent. Insertion keeps the rest of the file's bytes. It prefers the slot after `brwsk.brain`, else after `brwsk.vigil`, else the start of `right`. It does not remove other widgets. A missing plugins directory (Ubuntu, or Omarchy before the shell exists) skips the copy. `verify.sh` runs `usage.py --self-test` everywhere, validates the source when `omarchy-plugin-validate` exists, and on an Omarchy shell checks the installed copy matches and the bar id is present.

The timer runs `bin/usage.py`. It reads local files: Omarchy's `~/.local/state/omarchy/agents/usage/*.json`, Grok `usage.json` turn totals plus the last credits line in `~/.grok/logs/unified.jsonl`, OpenCode `step-finish` rows (token total and dollar cost per day and per model, the same records `opencode stats` prints; a database with no `part` table falls back to session token sums), and a path-free snapshot of this checkout (short commit, branch, dirty bit, three rules symlinks, `claude`/`grok`/`opencode` on `PATH`, boot slip `CLEAN` or not). The JSON also carries the six static parts of the repo. OpenCode Go windows are the extra read: `GET https://opencode.ai/zen/go/v1/usage` with the `opencode-go` key from `auth.json`, cached ten minutes at `~/.local/state/1config/opencode-go.json`. The cache stores percents and reset times only. Cloudflare rejects Python's default client, so the request uses a curl user agent. The console's prepaid credit balance is not on that route. Panel key `u` runs `omarchy-agent-usage-update --limits-only` and passes `--refresh-go`.

Open drops a card about 760 by 820 under the bar icon (`centerOnBar` stays off). The bar face is the ring mark alone, at `Style.bar.iconCanvas`. The tooltip still carries the hottest plan (`Grok 42%`). The default view is spend. Words on that view use the proportional face at the shell's title and heading sizes. Numbers stay monospace. There are no small-caps on the spend boxes. The roster is Claude, Grok, OpenAI, OpenCode, Codex, Cursor. Each used tool is one bordered box. Each limit, each day, and each model is its own box inside that. Tools with no tokens, no limits, and no model rows are omitted until panel key `a` (the same control as the button) appends them. OpenAI and Cursor are in the roster. No install says "Not on this machine". An install with no ledger says "No usage record on this machine". An Omarchy usage file whose id is not in the roster is ignored. OpenCode Go is three boxes — rolling, weekly, monthly — each a label, a percent, a bar, and the reset (rolling at 0% says "Starts on first use"). Under that, the local week is still one box per day and one box per model. `g` opens the map (`BrainMap.qml` above a short list): what 1config is, not only the spend. The square grid and scanlines are not painted. The frame and the sweep stay. The 30 fps sweep runs only while that map is open. `verify.sh` requires `BrainMap.qml` to be referenced from `Panel.qml`, requires `mode: "usage"` with no centred card, requires the bar face to stay the ring only, requires the quiet toggle, requires the Go usage URL, and `usage.py --self-test` requires the six part ids, the six-tool roster with unused tools last, a dropped non-roster usage file, a 7-day OpenCode series, and the three Go windows from a cache fixture.

The bar id is also packed in omarchy-dots `omarchy/shell.json` so login sync does not treat that line as a local edit. omarchy-dots still does not install plugin files. This copy is the install.

This is the Omarchy surface of 1config. Claude, Grok, and OpenCode do not each get a plugin. `brwsk.brain` stays the grokbot-brain tracker and is not this widget. NixFred's Burn Bar and Infomarchy are the prior art; they are not vendored.

## 8. Manual recreation (or just `bash ~/.agents/setup.sh`)

0. Distro packages if missing (setup.sh `[0]` prints the line). Ubuntu: `sudo apt-get install -y python3 util-linux cron git gnupg gnome-keyring texlive-full`. Omarchy: `omarchy pkg add python util-linux cronie git gnupg gnome-keyring texlive-meta`. Enable the cron daemon (`cron` on Ubuntu, `cronie` on Omarchy/Arch).
1. Clone or copy `~/.agents/` (this repo). Same tree on Omarchy and Ubuntu.
2. Symlinks (§3).
3. Grok config keys (§4) + delete `~/.grok/memory/` if present (after archive).
4. Claude memory wipe-to-stub for every `~/.claude/projects/*/memory/` (§4).
5. Claude AGENTS.md SessionStart hook (§4) — merged into `~/.claude/settings.json`, preserving existing hooks.
6. Install/refresh symlink guard + stray-merge hook (§7a) — copied from `hooks/check-links.sh` + `hooks/merge-strays.sh`.
7. Install/refresh claude-memory-guard (§6b/§7b) — copied from `hooks/check-claude-memory.sh`.
8. Install/refresh tool updater (§7c) — user scripts copied from `updater/`; install the root resume shim with the `sudo install` command above and repeat after shim changes.
9. Crontab entries for guards + updater (§7) — preserves other crontab lines.
10. GPG keyring unlock hooks — `chmod +x hooks/gpg-agent-unlock.sh hooks/gpg-store-passphrase.sh hooks/gpg-keyring.py hooks/gpg-signing-key.sh hooks/gpg-git.sh`. Point `git config --global gpg.program` at `hooks/gpg-git.sh`. Set `git config --global user.signingkey` to **this** machine's key, then run the store script once (see §4 GPG). Dedicated `gpg-signing` collection, not default.
11. `checkpoint.sh` — `chmod +x hooks/checkpoint.sh` + `bash -n` syntax gate (§4b).
12. `watch-stale.sh` — `chmod +x hooks/watch-stale.sh` + `bash -n` syntax gate (§4c).
13. Optional Lean: `bash ~/.agents/hooks/install-elan.sh` if the setup probe said `MISSING elan`. Not in the distro pkg line. `setup.sh` never downloads it.
14. Verify (+ refresh of gitignored `inventory.local.md`).

`setup.sh` does the above except the optional elan install (step 13 is the hook; setup only probes). Idempotent, backs up anything it replaces to `~/.agents/backups/setup-<ts>/`, self-verifies. `SKIP_CRON=1` skips the crontab step.

**Authority chain:** `SETUP.md` = machine wiring spec. `setup.sh` implements it. `AGENTS.md` = AI runtime rules (session workflow, memory policy). Keep them in sync when changing behavior.

### After any edit under `~/.agents/` (HARD RULE)

`~/.agents/` is the source tree. Installed copies live elsewhere (`~/cron-jobs/*`, tool symlinks, Claude settings). **Any edit under `~/.agents/` must be followed by:**

```bash
bash ~/.agents/setup.sh    # sync installs + local inventory + verify
# check-only later:
bash ~/.agents/verify.sh
```

`verify.sh` fails if: brain root/branch/push URL is wrong; sync can bypass verification; symlinks or XDG autostart drift; guards, updater scripts, or root resume shim differ from source; resume scheduling loses user/home or masks failure; inventory refresh is non-idempotent; inventory resolver fails `--self-test` (login PATH must win, vendor-dir fallback, no stderr versions); live CLI versions leak into SETUP.md; permission policy or modes differ across tools; hooks, cron, templates, checkpoint behavior, or staleness-watch behavior regress; README/DECISIONS omit the Omarchy+Ubuntu or `bash_without_prompt` warnings. It also rejects bibliography machinery in the paper template, Mathlib in the template lakefile, unpinned `lean-toolchain`, `sorry` in template `Paper.lean`, missing `install-elan.sh`, and untracked project-template / paper-template Lean files. Missing `elan`/`lake` on PATH is INFO, not FAIL. (The Grok `project-session` skill is a checklist overlay, not installed from this repo — `AGENTS.md` is the source of truth; verify does not police it.)

## 9. Verification

Preferred (full ecosystem):

```bash
bash ~/.agents/setup.sh    # sync + verify
bash ~/.agents/verify.sh   # check-only; exit 0 = green
```

Manual smoke (subset of what `verify.sh` does):

```bash
for f in ~/.grok/AGENTS.md ~/.config/opencode/AGENTS.md ~/.claude/CLAUDE.md; do
  [ -L "$f" ] && [ "$(readlink -f "$f")" = "$HOME/.agents/AGENTS.md" ] && echo "OK   $f" || echo "FAIL $f"
done
python3 -c "import tomllib,os; tomllib.load(open(os.path.expanduser('~/.grok/config.toml'),'rb'))" && echo TOML-OK
crontab -l | grep -E 'agents-symlink-guard|claude-memory-guard|ai-terminal-tools-update'
cmp -s ~/.agents/hooks/check-links.sh ~/cron-jobs/agents-symlink-guard/check-links.sh && echo LINKS-SYNC-OK
cmp -s ~/.agents/hooks/merge-strays.sh ~/cron-jobs/agents-symlink-guard/merge-strays.sh && echo MERGE-SYNC-OK
cmp -s ~/.agents/hooks/check-claude-memory.sh ~/cron-jobs/claude-memory-guard/check-memory.sh && echo MEM-SYNC-OK
cmp -s ~/.agents/updater/update-apps.sh ~/cron-jobs/ai-terminal-tools-update-on-boot/update-apps.sh && echo UPD-SYNC-OK
bash ~/.agents/hooks/gpg-agent-unlock.sh && echo GPG-CACHED-OK || echo GPG-UNLOCK-NEEDED
```

Expected: `verify.sh` exit 0; 3× OK symlinks; guards + updater byte-identical to sources.
