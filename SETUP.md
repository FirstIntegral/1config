# Unified AI Terminal Setup — Full Spec

Complete, unambiguous spec of this machine's AI-tool setup. `setup-infographic.svg` is the visual summary; THIS file is the authoritative version. An AI given this file + the `~/.agents/` folder can recreate everything exactly. If a brain change alters what the figure depicts (components, flows, toolchain), regenerate `setup-infographic.svg` in the same turn.

**TL;DR (Omarchy or Ubuntu):** clone this repo to `~/.agents` → install whatever `[0] platform` prints as missing → `bash ~/.agents/setup.sh` → machine-local GPG + `gh auth` (see `README.md`). Existing box: `git pull && bash ~/.agents/setup.sh`. Manual path: §8.

Human report + opinionated-default table: **`README.md`**. ADRs: **`docs/DECISIONS.md`**. This file remains the machine spec.

## 1. Inventory

Three CLIs: Grok Build (`grok`), Claude Code (`claude`), OpenCode (`opencode`). Config: `~/.grok/config.toml`, `~/.claude/settings.json`, `~/.config/opencode/opencode.jsonc`.

**Live versions are machine-local.** `setup.sh` and the boot updater write `~/.agents/inventory.local.md` (**gitignored**). Do not commit them — Ubuntu and Omarchy will not share patch versions, and pinning them here made `verify.sh` fail after a pull.

Inventory resolution, in order: (1) login shell `env -i bash -lc command -v` — this is what mise shims look like, and it is the **only** probe `update-apps.sh` `mise_managed()` uses to skip a tool; (2) **vendor-dir fallback** if that is empty, the well-known dirs the updater already puts on its own PATH: `~/.opencode/bin`, `~/.grok/bin`, `~/.local/bin`. Official OpenCode/Grok installers drop binaries there and add PATH in `.bashrc`, which a non-interactive login shell never sources (**interactive-guard**). Without (2), Ubuntu inventory reported OpenCode missing and stuffed `command not found` into the version cell. (2) does **not** mutate PATH and does **not** symlink into `~/.local/bin`, so an Omarchy mise shim that *is* on login PATH still wins. A missing command is version `unknown` / path `missing`; stderr is never copied into the table.

Tools whose login-shell PATH resolves under mise are skipped by the updater; mise's own upgrade cadence (`minimum_release_age`) governs them. The updater still refreshes inventory (which may show the mise path from step 1).

**Platform:** Linux. **Supported: Omarchy (Arch) and Ubuntu (Debian).** Requires: `python3`, `flock`, `git`. Wants: `cron` (Ubuntu) / `cronie` (Omarchy/Arch), `gpg`, `gnome-keyring`. Optional: `texlive-full` (Ubuntu) / `texlive-meta` (Omarchy). No root, no package installs from `setup.sh` (except the optional systemd-sleep shim — see that cron-job’s README). `setup.sh` `[0] platform` detects the family and prints the distro-correct install line.

### Opinionated defaults (this repo — many people will not want them)

Canonical file: `permissions.json`. **`bash_without_prompt` is `true`:** Claude `bypassPermissions`, Grok `always-approve`, OpenCode bash `"*" = allow`. Setup **omits ask fan-out** (OpenCode last-match and Grok shell-ask would otherwise still prompt `git push`). Deny still copies. Generic `git push` no longer prompts. Flip to `false` and re-run `setup.sh` to restore the review gate. Full table (signing, caveman, TeX, no AI attribution, no auto-remotes): `README.md`. Why: `docs/DECISIONS.md`.

### Boot dashboard (graphical login)

On any XDG graphical login, a terminal opens with a one-screen summary of boot health (symlinks, guards, `verify.sh`, tool versions, tool-updater log). The desktop entry has no `OnlyShowIn` filter, so both Wayland sessions such as Hyprland and X11 desktops run it. Lives in `~/.agents/boot-dashboard/`. Installed by `setup.sh` → `~/.config/autostart/agents-boot-status.desktop`. Manual: `bash ~/.agents/boot-dashboard/launch.sh`.

## 2. Canonical rules file

`~/.agents/AGENTS.md` — the ONE global rules file. All three tools read it every session via the symlinks in §3. Loaded once per session start. **Keep it LEAN** (cross-project rules only; project facts go in project files) — every extra paragraph costs context on every session of every tool.

Sections, in order:
1. Header — wiring map + migration one-liner
2. Git/GitHub attribution — HARD RULE (no AI attribution in commits/PRs)
3. Git commit signing — HARD RULE (never bypass signing; keyring auto-unlock; manual fallback)
4. Permission policy — canonical `~/.agents/permissions.json`, fanned out to all three tools by `setup.sh` steps 5b/5c/5d (§4); includes the "prompts an allowlist cannot remove" subsection
5. Tri-tool parity — HARD RULE: every feature lands in Claude Code + Grok + OpenCode, installed by `setup.sh`, checked by `verify.sh`
6. Machine toolchains — `texlive-full` + `tectonic` installed; write LaTeX directly, never ask for installs
7. Detached runs / staleness watch — HARD RULE (`hooks/watch-stale.sh`, default 10 min; §4c)
8. Caveman mode — ALWAYS ON (terse style; `/caveman lite|full|ultra`)
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
- **Project AGENTS.md via SessionStart hook** — Claude Code (2.1.219) does NOT read project `AGENTS.md` natively (verified empirically 2026-07-26). `setup.sh` step 5 wires `~/.agents/hooks/load-project-agents.sh` into `~/.claude/settings.json` `hooks.SessionStart`; the script walks up from cwd (stopping before `$HOME`) and injects the nearest `AGENTS.md` into context. Result: identical behavior to Grok/OpenCode. **No project CLAUDE.md files exist — never create one** (stubs retired 2026-07-26).
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

### OpenCode

Reads `AGENTS.md` natively at global and project level — no rules wiring needed.

- **Permission rules** — `setup.sh` step `5d` replaces OpenCode's `permission.bash` map from canonical `Bash(X)` rules, making removals effective. Order: managed catch-all first (`"*": "ask"` normally, `"allow"` under full Bash autonomy), then allow, then ask (**omitted when `bash_without_prompt` is true** — last-match would re-prompt `git push` over `"*": allow`), then deny. OpenCode takes the last match, so deny still wins over the catch-all. Non-`Bash` rules are skipped. Other OpenCode config survives. Valid JSONC comments and trailing commas are accepted; output becomes plain JSON after a backup.

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

Exit codes: `0` remote backup completed (new commit and/or existing commits pushed) · `3` clean tree and `HEAD` has no commit absent from local remote-tracking refs · `10` not a repo · `11` inside another repo · `12` no remote (committed locally) · `13` remote unreachable (committed, not pushed) · `20` refused, session files would be published · `21` commit/push failed · `2` usage.

Invariants, all covered by `verify.sh`:

- **Never** `git init`, `git remote add`, `gh repo create`, `--force`, rebase/reset/amend, or `--no-gpg-sign`. A project without a repo or remote is in a deliberate state.
- Refuses **before staging** if `session_compact.md` / `session_transcript.md` / `claude_memory_import.md` are tracked or unignored — publishing the private transcript is the one failure here that cannot be walked back.
- Requires the given directory to **be** the repo toplevel; `rev-parse --show-toplevel` walks up, so a subdirectory would otherwise commit an unrelated parent repo.
- Reachability uses bare `git ls-remote`, **not** `--exit-code`: that flag returns 2 when no refs match, so an empty freshly created repo would be misread as unreachable and the first push silently refused.
- Cross-checks the URL against the project `AGENTS.md` `## Repo` line and warns on mismatch, but git config always wins — `AGENTS.md` is a file an AI writes and must never authorise a push.
- **A clean tree is not the same as nothing to do.** Commits made earlier and never pushed are exactly the state where "the machine is not the only copy" fails, so a clean tree still takes the push path and only skips the commit. Local unpushed state is counted as `HEAD --not --remotes`; no fetch occurs, so exit `3` does not claim a live remote is reachable or unchanged.
- `verify.sh` runs the refusals and the push path for real against scratch dirs and a bare remote (non-repo → 10 with no `.git` created; unignored transcript → 20; clean tree with one locally unpushed commit → pushed, exit 0; clean with no locally unpushed commit → exit 3).

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

Trigger: user says **`create_project`**. Copy `~/.agents/project-template/` into the project root, fill in names. Five artifacts: `AGENTS.md`, `session_compact.md`, `session_transcript.md`, `docs/DECISIONS.md`, `.gitignore` (no CLAUDE.md — see §4 Claude hook). If the project already has a `.gitignore`, merge the session-file lines instead of overwriting. Verbatim templates:

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
- `.gitignore` — ignores the session files above, `claude_memory_import.md`, and legacy session paths. Sites under `~/projects/sites/` also ignore `AGENTS.md` / `CLAUDE.md`.
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

# Sites repos only (~/projects/sites/*): also ignore agent rules — uncomment or add when creating a site:
# AGENTS.md
# CLAUDE.md
```

(Does **not** ignore `AGENTS.md` by default — only `~/projects/sites/*` do; uncomment those two lines or add them when the project is a site.)

### Rules (enforced via the canonical file, all tools)

1. **Session start:** read `session_compact.md` FIRST if it exists. NEVER open `session_transcript.md` — it is the user's private log (Transcript privacy HARD RULE; read only if the user explicitly asks).
2. **During work:** append to `session_transcript.md` at milestones (writing OK, reading not); ADRs to `docs/DECISIONS.md` in the same turn.
3. **End of session / milestone / before compaction:** rewrite `session_compact.md` — accurate enough for a fresh AI to resume from it alone.
4. Session files live in project root; **never committed unless the user explicitly says otherwise** — template `.gitignore` covers them. `docs/DECISIONS.md` IS committed in repos.
5. **Model tracking:** at `create_project` record active model + effort (read tool config — `opencode.jsonc` / `~/.claude/settings.json` / `~/.grok/config.toml` — or ask user once). The **Models used** list is CUMULATIVE: preserve across rewrites, mark current, add a line on any model/effort change. Every switch ALSO appended to `session_transcript.md` (old → new, reason if known). User says they switched → log immediately.

## 5b. `continue_project <path>`

Trigger: user says **`continue_project <path>`** (example: `continue_project $HOME/projects/some_dummy_project`).

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

- **Scaffold source:** `~/.agents/paper-template/` → copied to `<project>/docs/paper/` on first run (`main.tex`, `build.sh`, `figures/`). Later runs extend the existing paper; they never restart it.
- **Author block is fixed:** `Brusk Kawa Abdalla`, contact `math@brwsk.xyz`.
- **Template contents:** `article` + `amsthm` theorem environments (theorem/lemma/proposition/corollary/conjecture/definition/assumption/example/remark), `mathtools`, `siunitx`, `booktabs`, `pgfplots`/TikZ, `algorithm2e`, `cleveref`, and a red `\TODO{}` macro so every gap is visible instead of guessed.
- **No references, by design.** AI-written papers are self-contained: no bibliography, no `refs.bib`, no `\cite`, no reference list. Prior art is described in prose. `verify.sh` fails if bibliography machinery reappears in the template.
- **Build:** `bash docs/paper/build.sh` → `latexmk -pdf` → `main.pdf`, prints the page count and every open `\TODO`. `clean` argument runs `latexmk -C`. Verified to compile against the installed `texlive-full`.
- **Content hard rules** (in `AGENTS.md`): no invented numbers, no references, no overclaiming — missing measurements become `\TODO{measure: …}` and are reported as Gaps.
- **The paper stays current.** Once `docs/paper/` exists, any scientifically relevant change (method, theorem, assumption, experimental setup, measured number, limitation) updates the paper and rebuilds it in the **same turn** — the trigger does not have to be re-typed. Refactors/tooling changes do not count unless a reported number or stated claim moves.
- `docs/paper/` is **committed** (product, not session state).

## 5e. `global_brain_update`

Trigger: user says **`global_brain_update <what to change>`**. Target is `~/.agents` itself, not the current project. Full spec in canonical `AGENTS.md` — that file wins if they ever diverge.

1. Read the brain first (`AGENTS.md`, `SETUP.md`, plus whatever the request touches — `setup.sh`, `verify.sh`, `permissions.json`, `hooks/`, `updater/`, `project-template/`, `paper-template/`, `boot-dashboard/`).
2. Change the **canonical** home of the thing, never a tool-local copy.
3. Tri-tool parity: all three tools, installed by `setup.sh`, checked by `verify.sh`.
4. `bash ~/.agents/setup.sh` → must end `== PASS ==`, `warnings=0`.
5. `bash ~/.agents/sync.sh -m "<subject>"` → signed commit + push.
6. Report changed files, verify result, pushed commit.

### The brain is a git repo

`~/.agents` is versioned and pushed to **`https://github.com/FirstIntegral/1config.git`** (SSH equivalent also accepted; branch `main`, signed commits, no AI attribution, `backups/` gitignored). **Any** change under `~/.agents/**` — trigger typed or not — ends the same turn with `setup.sh` + `sync.sh`. Local-only edits are unfinished edits.

`sync.sh` is the single scripted path:

```bash
bash ~/.agents/sync.sh -m "Commit subject"    # setup+verify → signed commit → push
bash ~/.agents/sync.sh --no-setup -m "msg"    # skip installation, still run verify.sh
bash ~/.agents/sync.sh --dry-run              # show what would be committed, change nothing
```

It requires repository root + branch `main`, validates every origin fetch and push URL against `FirstIntegral/1config`, and requires `== PASS (warnings=0) ==` before any commit, including with `--no-setup`. Normal sync fetches first; `--dry-run` skips both install and fetch so it changes nothing. New commits use explicit `git commit -S`, and every outgoing commit must have a good signature before push. It is allowlisted because it is the narrow verified push path; canonical `permissions.json` still lists generic `git push` as ask (restore-gate), but live tools omit that ask while `bash_without_prompt` is true. `verify.sh` reports dirty/ahead brain state as `INFO`, because that state is expected before sync.

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

### 6c. Sites exception (`~/projects/sites/*`)

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
13. Verify (+ refresh of gitignored `inventory.local.md`).

`setup.sh` does all of the above: idempotent, backs up anything it replaces to `~/.agents/backups/setup-<ts>/`, self-verifies. `SKIP_CRON=1` skips the crontab step.

**Authority chain:** `SETUP.md` = machine wiring spec. `setup.sh` implements it. `AGENTS.md` = AI runtime rules (session workflow, memory policy). Keep them in sync when changing behavior.

### After any edit under `~/.agents/` (HARD RULE)

`~/.agents/` is the source tree. Installed copies live elsewhere (`~/cron-jobs/*`, tool symlinks, Claude settings). **Any edit under `~/.agents/` must be followed by:**

```bash
bash ~/.agents/setup.sh    # sync installs + local inventory + verify
# check-only later:
bash ~/.agents/verify.sh
```

`verify.sh` fails if: brain root/branch/push URL is wrong; sync can bypass verification; symlinks or XDG autostart drift; guards, updater scripts, or root resume shim differ from source; resume scheduling loses user/home or masks failure; inventory refresh is non-idempotent; inventory resolver fails `--self-test` (login PATH must win, vendor-dir fallback, no stderr versions); live CLI versions leak into SETUP.md; permission policy or modes differ across tools; hooks, cron, templates, checkpoint behavior, or staleness-watch behavior regress; README/DECISIONS omit the Omarchy+Ubuntu or `bash_without_prompt` warnings. It also rejects bibliography machinery in the paper template and untracked project-template files. (The Grok `project-session` skill is a checklist overlay, not installed from this repo — `AGENTS.md` is the source of truth; verify does not police it.)

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
