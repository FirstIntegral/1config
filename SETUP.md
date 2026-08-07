# Unified AI Terminal Setup — Full Spec

Complete, unambiguous spec of this machine's AI-tool setup. `setup-infographic.svg` is the visual summary; THIS file is the authoritative version. An AI given this file + the `~/.agents/` folder can recreate everything exactly.

**TL;DR migration:** copy `~/.agents/` to the new machine → `bash ~/.agents/setup.sh` → done. Manual path: §8.

## 1. Inventory

**Versions are auto-maintained** by `~/cron-jobs/ai-terminal-tools-update-on-boot/update-apps.sh` (boot + resume). That script upgrades binaries, then rewrites the table below. Do not hand-edit versions.

<!-- TOOL_INVENTORY_START -->
| Tool | Version | Binary | Config |
|------|---------|--------|--------|
| Grok Build | 1.0.0 | `~/.grok/bin/grok` | `~/.grok/config.toml` |
| Claude Code | 2.1.224 | `~/.local/bin/claude` | `~/.claude/settings.json` |
| OpenCode | 1.18.15 | `~/.opencode/bin/opencode` | `~/.config/opencode/opencode.jsonc` |
<!-- last refreshed: 2026-08-07 18:12 by update-apps -->
<!-- TOOL_INVENTORY_END -->

Platform: linux. Requires: `python3`, `cron`. No root, no package installs (except optional systemd-sleep shim for resume updates — see that cron-job’s README).

### Boot dashboard (login)

On GNOME login, a terminal opens with a one-screen summary of boot health (symlinks, guards, `verify.sh`, tool versions, tool-updater log). Lives in `~/.agents/boot-dashboard/`. Autostart desktop installed by `setup.sh` → `~/.config/autostart/agents-boot-status.desktop`. Manual: `bash ~/.agents/boot-dashboard/launch.sh`.

## 2. Canonical rules file

`~/.agents/AGENTS.md` — the ONE global rules file. All three tools read it every session via the symlinks in §3. Loaded once per session start. **Keep it LEAN** (cross-project rules only; project facts go in project files) — every extra paragraph costs context on every session of every tool.

Sections, in order:
1. Header — wiring map + migration one-liner
2. Git/GitHub attribution — HARD RULE (no AI attribution in commits/PRs)
3. Git commit signing — HARD RULE (never bypass signing; keyring auto-unlock; manual fallback)
4. Permission allowlist — canonical `~/.agents/permissions.json`, fanned out to all three tools by `setup.sh` steps 5b/5c/5d (§4); includes the "prompts an allowlist cannot remove" subsection
5. Tri-tool parity — HARD RULE: every feature lands in Claude Code + Grok + OpenCode, installed by `setup.sh`, checked by `verify.sh`
6. Machine toolchains — `texlive-full` + `tectonic` installed; write LaTeX directly, never ask for installs
7. Caveman mode — ALWAYS ON (terse style; `/caveman lite|full|ultra`)
8. `create_project` trigger (§5)
9. `continue_project <path>` trigger (§5b)
10. `checkpoint_project` trigger (§5c)
11. `writepaper_project` trigger (§5d)
12. `global_brain_update` trigger (§5e) — changes to `~/.agents` itself, ending in `setup.sh` + `sync.sh`
13. Global workflow (session start / during / end)
14. Memory policy (§6)

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

Append/merge these keys; **preserve all existing content**:

```toml
[compat.claude]
agents = false   # don't double-inject CLAUDE.md files (same content as AGENTS.md)
rules = false

[memory]
enabled = false  # memory lives in shared markdown, not grok's store
```

(`skills`/`mcps`/`hooks` compat intentionally left enabled.)

- **Grok memory dir removed.** If `~/.grok/memory/` exists, `setup.sh` archives it under `~/.agents/backups/setup-<ts>/grok-memory/` then deletes it. Do not recreate.
- **Permission rules** — `setup.sh` step `5c` writes `[permission] allow = [...] / deny = [...]` from `~/.agents/permissions.json`, union-merged with whatever is already there, and re-parses the TOML afterwards so a broken config can never ship. Grok uses the **same `Bash(...)` rule syntax as Claude**, so rules go in verbatim. `[ui] permission_mode = "always-approve"` is on, which auto-approves allow-side prompts anyway — **deny rules still apply in that mode**, which is why they are written too.
- **`permission_mode` is now brain-managed** (added 2026-08-07) — step `5c` writes/updates the `[ui] permission_mode` line from `defaults.edit_without_prompt`. **Per-tool difference, recorded per the parity rule:** Grok has no edit-only autonomy mode, so `always-approve` is the nearest equivalent and is *broader* than Claude's `acceptEdits` / OpenCode's `permission.edit` — it approves every prompt, not just file writes. With the flag `false` the key is **deleted** rather than set to a guessed off-value (grok's enum for that field is not documented in the binary), so grok falls back to its own default.

### Claude Code

- Global file `~/.claude/CLAUDE.md` → symlink (§3).
- **Project AGENTS.md via SessionStart hook** — Claude Code (2.1.219) does NOT read project `AGENTS.md` natively (verified empirically 2026-07-26). `setup.sh` step 3b wires `~/.agents/hooks/load-project-agents.sh` into `~/.claude/settings.json` `hooks.SessionStart`; the script walks up from cwd (stopping before `$HOME`) and injects the nearest `AGENTS.md` into context. Result: identical behavior to Grok/OpenCode. **No project CLAUDE.md files exist — never create one** (stubs retired 2026-07-26).
- **Auto-memory wiped to a stub only.** For every `~/.claude/projects/*/memory/` dir (including empty ones): archive anything that is not already a lone DISABLED stub, delete all other files in that dir, write exactly:

```markdown
# Memory Index — DISABLED

Disabled by user policy. Do not write memories here.
Durable facts live in `~/.agents/AGENTS.md` (global rules) and the project's
`AGENTS.md` / `session_compact.md` (project facts).
```

- Claude `#` memory shortcut is NOT used (creates project CLAUDE.md / feeds auto-memory — both forbidden).
- **Global permission allowlist** — canonical source `~/.agents/permissions.json` (renamed from `claude-permissions.json` on 2026-08-06 when it stopped being Claude-only). `setup.sh` step `5b` merges its `permissions.allow` / `permissions.deny` into `~/.claude/settings.json` as a **union** (never drops rules added by hand or by clicking Approve), deduped and idempotent. Matched tool calls run without a prompt in every project; anything unmatched still prompts. Edit the canonical file, then re-run `setup.sh` — never hand-edit `permissions` in `~/.claude/settings.json`, the next merge would leave it orphaned from source. Adopted 2026-08-06 by promoting the per-project allowlist from `philosophy_human_communication_framework_vs_llm/.claude/settings.json`. The same file also drives Grok (§Grok) and OpenCode (§OpenCode); `verify.sh` section `[permission parity]` fails if any of the three drifts.
- **`permissions.defaultMode = "acceptEdits"`** (added 2026-08-07) — written by step `5b` from `defaults.edit_without_prompt` in the canonical file; this is Claude's nearest equivalent to grok's always-approve. It removes the *"Do you want to create X?"* write prompts only; **Bash still goes through the allow list**, so no command runs that no rule matches. `false` → step `5b` writes `"default"` instead.
- **Compound-command matching** — Claude approves a pipeline / `;` / `&&` chain only when **every** segment matches a rule, and the prompt text names only some of the offenders. A hardware probe (`lscpu | grep …; free -g | head -2; uname -srm; lsb_release -d`) therefore prompted despite `grep`/`head` being allowed. Fixed 2026-08-07 by allowlisting the read-only sysinfo set (`uname`, `lscpu`, `lsb_release`, `free`, `df`, `nproc`, `lsblk`, `lspci`, `vmstat`, `getconf`, `hostnamectl`, `uptime`, `id`, `whoami`, `pwd`, `date`, `ps`, `pgrep`, `file`, `readlink`, `tree`, `sha256sum`, `md5sum`, `crontab -l`), the read-only git verbs (`rev-parse`, `remote get-url`, `ls-files`, `config --get`, `describe`, `blame`), and `sed`/`awk` — in **both** bare and `<cmd> *` forms, since a bare `lscpu` does not match `Bash(lscpu *)`.
- **Prompts the allowlist can't remove** — obfuscation/parse verdicts (e.g. `Contains brace with quote character (expansion obfuscation)`, thrown by heredocs whose body mixes braces with quotes, i.e. Python f-strings), exec wrappers (`watch`, `setsid`, `flock`, `find -exec`), and env runners (`npx`, `docker exec`). Decided before rule matching. Workaround is behavioural, not config: write the script to a scratchpad file and run the file. Documented in `AGENTS.md` §Permission allowlist.
- **TeX** — `texlive-full` (TeX Live 2025) is installed machine-wide, plus `tectonic` in `~/.local/bin`. All engines/build tools are allowlisted; `tlmgr install` is not, and is unnecessary under the full scheme.

### OpenCode

Reads `AGENTS.md` natively at global and project level — no rules wiring needed.

- **Permission rules** — `setup.sh` step `5d` translates the `Bash(X)` rules from `~/.agents/permissions.json` into the `permission.bash` map in `~/.config/opencode/opencode.jsonc`: `Bash(python3 *)` → `"python3 *": "allow"`, deny rules → `"deny"`. Deny entries are written **last** because OpenCode takes the last matching rule. Non-`Bash` rules (`Skill(...)`) have no OpenCode equivalent and are skipped. **No catch-all `"*"` is invented** — OpenCode's defaults are permissive (`bash`/`edit` default to `allow`), and this merge only pins the canonical rules rather than tightening everything else. Step `5d` also writes `permission.edit` from `defaults.edit_without_prompt` (`allow` / `ask`) — same value OpenCode would default to, written explicitly so the switch is visible in the file and `verify.sh` can compare all three tools. The file is rewritten as plain JSON; if it ever gains `//` comments they are dropped on merge and the pre-copy lands in the setup backup dir.

### GPG signing unlock (GNOME keyring)

- Passphrase lives in the GNOME keyring (Secret Service), **not on disk**. Keyring unlocks at login via PAM → silent unlock forever after a one-time store.
- `hooks/gpg-agent-unlock.sh` — test-sign; if the agent has no cached passphrase, fetch from keyring + unlock with `--pinentry-mode loopback`. Runs at login via the boot dashboard; standalone anytime.
- `hooks/gpg-store-passphrase.sh` — one-time store (prompts once; nothing on disk). Re-run after a passphrase change.
- **gnome-keyring 50.x API quirk (verified 2026-08):** `CreateItem` lives on the **Collection** interface (not Service), `GetSecret` on the **Item** interface, and the Secret struct signature is `(oayays)` with a single `ay` parameters field. The plain-session handle marshals correctly only via the **vendored `jeepney`** (`~/.agents/vendor/jeepney`, MIT, pure python — dbus-python/GLib validate object paths and fail). No system packages needed.
- `~/.gnupg/gpg-agent.conf` already: `allow-loopback-pinentry`, `default-cache-ttl 31536000`, `max-cache-ttl 31536000` (1-year cache after first unlock).
- Fallback (keyring locked/empty): manual unlock in a real terminal (see canonical `AGENTS.md`).

### §4b `hooks/checkpoint.sh` — the git half of `checkpoint_project`

Steps 1-5 of that trigger need judgement (what happened today, which decisions to log) and stay with the AI. Step 6 is mechanical, has one correct answer per project state, and was being re-derived by hand inconsistently — so it is a script. All three tools call the same one, via the trigger in canonical `AGENTS.md`; nothing tool-specific.

```sh
bash ~/.agents/hooks/checkpoint.sh <project-root> [-m SUBJECT] [--dry-run]
```

Exit codes: `0` committed+pushed · `3` clean tree · `10` not a repo · `11` inside another repo · `12` no remote (committed locally) · `13` remote unreachable (committed, not pushed) · `20` refused, session files would be published · `21` commit/push failed · `2` usage.

Invariants, all covered by `verify.sh`:

- **Never** `git init`, `git remote add`, `gh repo create`, `--force`, rebase/reset/amend, or `--no-gpg-sign`. A project without a repo or remote is in a deliberate state.
- Refuses **before staging** if `session_compact.md` / `session_transcript.md` / `claude_memory_import.md` are tracked or unignored — publishing the private transcript is the one failure here that cannot be walked back.
- Requires the given directory to **be** the repo toplevel; `rev-parse --show-toplevel` walks up, so a subdirectory would otherwise commit an unrelated parent repo.
- Reachability uses bare `git ls-remote`, **not** `--exit-code`: that flag returns 2 when no refs match, so an empty freshly created repo would be misread as unreachable and the first push silently refused.
- Cross-checks the URL against the project `AGENTS.md` `## Repo` line and warns on mismatch, but git config always wins — `AGENTS.md` is a file an AI writes and must never authorise a push.
- `verify.sh` runs the two refusals for real against a scratch dir (non-repo → 10 with no `.git` created; unignored transcript → 20).

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

Trigger: user says **`continue_project <path>`** (example: `continue_project /home/brwsk/projects/some_dummy_project`).

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
6. Finish with: "Checkpoint saved — next step: <X>".

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

`~/.agents` is versioned and pushed to **`git@github.com:FirstIntegral/1config.git`** (branch `main`, signed commits, no AI attribution, `backups/` gitignored). **Any** change under `~/.agents/**` — trigger typed or not — ends the same turn with `setup.sh` + `sync.sh`. Local-only edits are unfinished edits.

`sync.sh` is the single scripted path:

```bash
bash ~/.agents/sync.sh -m "Commit subject"    # setup+verify → signed commit → push
bash ~/.agents/sync.sh --no-setup -m "msg"    # skip setup.sh (already ran this turn)
bash ~/.agents/sync.sh --dry-run              # show what would be committed, change nothing
```

It refuses to commit when `setup.sh`/`verify.sh` fail, unlocks the GPG agent through the keyring hook, and **never** bypasses signing (a locked key is an error to fix). It is allowlisted for all three tools precisely because it can only ever push this one repo — generic `git push` still prompts everywhere, including here. `verify.sh` reports the brain's remote and warns when the working tree is dirty.

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
@daily  /home/brwsk/cron-jobs/claude-memory-guard/check-memory.sh
@reboot /home/brwsk/cron-jobs/claude-memory-guard/check-memory.sh
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

- **Source:** `~/.agents/updater/` (`boot-check.sh`, `update-apps.sh`, `on-resume.sh`, `system-sleep-shim.sh`).
- **Installed by** `setup.sh` → `~/cron-jobs/ai-terminal-tools-update-on-boot/` (user scripts only, byte-identical; `update-apps.log` + `.update.lock` stay in the installed dir). `verify.sh` byte-compares.
- **Crontab:** `@reboot .../boot-check.sh` (managed by setup.sh). **Resume:** root-installed systemd hook `/usr/lib/systemd/system-sleep/ai-terminal-tools-update-resume.sh` — install once per machine: `sudo cp ~/.agents/updater/system-sleep-shim.sh /usr/lib/systemd/system-sleep/ai-terminal-tools-update-resume.sh`.
- `update-apps.sh` refreshes the SETUP.md inventory table (`by update-apps` — same marker as setup.sh).
- Both guards **and** the updater hold `flock`s; setup.sh runs serialized.

## 8. Manual recreation (or just `bash ~/.agents/setup.sh`)

1. Copy/write `~/.agents/` (canonical `AGENTS.md` + `project-template/` + `hooks/` + `updater/`).
2. Symlinks (§3).
3. Grok config keys (§4) + delete `~/.grok/memory/` if present (after archive).
4. Claude memory wipe-to-stub for every `~/.claude/projects/*/memory/` (§4).
5. Claude AGENTS.md SessionStart hook (§4) — merged into `~/.claude/settings.json`, preserving existing hooks.
6. Install/refresh symlink guard + stray-merge hook (§7a) — copied from `hooks/check-links.sh` + `hooks/merge-strays.sh`.
7. Install/refresh claude-memory-guard (§6b/§7b) — copied from `hooks/check-claude-memory.sh`.
8. Install/refresh tool updater (§7c) — copied from `updater/` (systemd resume shim needs root once).
9. Crontab entries for guards + updater (§7) — preserves other crontab lines.
10. GPG keyring unlock hooks — `chmod +x hooks/gpg-agent-unlock.sh hooks/gpg-store-passphrase.sh`; run the store script once (see §4 GPG).
11. `checkpoint.sh` — `chmod +x hooks/checkpoint.sh` + `bash -n` syntax gate (§4b).
12. Verify (+ optional inventory refresh of §1 version table).

`setup.sh` does all of the above: idempotent, backs up anything it replaces to `~/.agents/backups/setup-<ts>/`, self-verifies. `SKIP_CRON=1` skips the crontab step.

**Authority chain:** `SETUP.md` = machine wiring spec. `setup.sh` implements it. `AGENTS.md` = AI runtime rules (session workflow, memory policy). Keep them in sync when changing behavior.

### After any edit under `~/.agents/` (HARD RULE)

`~/.agents/` is the source tree. Installed copies live elsewhere (`~/cron-jobs/*`, tool symlinks, Claude settings). **Any edit under `~/.agents/` must be followed by:**

```bash
bash ~/.agents/setup.sh    # sync installs + inventory + verify
# check-only later:
bash ~/.agents/verify.sh
```

`verify.sh` fails if: symlinks wrong, hooks≠installed guards, flag names missing, inventory markers gone, grok memory switches wrong, Claude SessionStart hook missing, crontab guards missing, or project-session skill regressed to retired workflow.

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
