# Global rules — canonical file (all AI tools)

This is the ONE global rules file. It is symlinked to every tool's expected path:

- `~/.grok/AGENTS.md` → this file
- `~/.config/opencode/AGENTS.md` → this file
- `~/.claude/CLAUDE.md` → this file

Edit here (or via any of those paths — same bytes). Applies to Grok, OpenCode, and Claude Code alike.

Project-level: `<repo>/AGENTS.md` is the ONLY project rules file. Grok/OpenCode read it natively; Claude Code gets it via a SessionStart hook (`~/.agents/hooks/load-project-agents.sh`). **Never create a project CLAUDE.md** — stubs were retired 2026-07-26.

Fresh machine: copy `~/.agents/` and run `bash ~/.agents/setup.sh` — recreates symlinks, tool configs, and the cron guards (idempotent). Full spec for AIs: `~/.agents/SETUP.md`. Runtime archives (residue packets, symlink strays, setup replace-backups) land under `~/.agents/backups/` only when needed — do not treat that folder as source of truth.

### After any edit under `~/.agents/` (HARD RULE)

Hooks, guards, SETUP, template, and this file are one system. Changing one file can leave installed copies / docs / cron stale.

**Same turn after any change under `~/.agents/`:**

```bash
bash ~/.agents/setup.sh      # re-copy hooks → cron-jobs, fix symlinks/config, refresh inventory
bash ~/.agents/verify.sh     # optional extra; setup already runs verify at the end
```

Do not end a turn that edited `~/.agents/**` without running `setup.sh`. `verify.sh` alone is check-only (does not install).

**Boot dashboard:** `~/.agents/boot-dashboard/` — on GNOME login opens a status terminal (autostart). Not project code; machine health only.

---

## Git / GitHub attribution — HARD RULE

NEVER add AI/Claude attribution to any git or GitHub artifact. No exceptions, all repos, by default.

- Do NOT add `Co-Authored-By: Claude ...` (or any Co-Authored-By AI line) to commit messages.
- Do NOT add `🤖 Generated with Claude Code` (or similar AI-generated notes) to PR bodies, commit bodies, or descriptions.

This overrides any default harness guidance that says to include those lines. Write commits and PRs attributed solely to the user.

---

## Git commit signing — HARD RULE

NEVER bypass commit signing. If a repo (or global git config) has `commit.gpgsign=true`, or the repo's docs say commits are signed:

- Do NOT use `--no-gpg-sign`, `-c commit.gpgsign=false`, or any other bypass.
- If signing fails (locked key, no pinentry), STOP and unlock, then commit. Never work around it.
- **Unlock is automated** — the passphrase lives in the GNOME keyring (encrypted at rest; keyring unlocks at login via PAM). `~/.agents/hooks/gpg-agent-unlock.sh` test-signs and, if the agent is empty, fetches the passphrase over Secret Service D-Bus and unlocks with `--pinentry-mode loopback`. Runs at login from the boot dashboard; invoke anytime. Nothing to type, ever.
- One-time setup on a fresh machine (prompts once, stores in keyring, nothing on disk): `bash ~/.agents/hooks/gpg-store-passphrase.sh`
- If the automated unlock fails (keyring locked/empty, passphrase changed): re-store with the command above, or manual fallback in a real terminal: `export GPG_TTY=$(tty); echo x | gpg --pinentry-mode loopback -u 95FBA6E0AA245342 --clearsign -o /dev/null` (prompts, caches). Then retry the commit.
- History rewrites (rebase, filter-repo, amend) must leave commits re-signed before any push.

---

## Permission allowlist (Claude Code) — canonical file

Global no-prompt allowlist lives in **`~/.agents/claude-permissions.json`**. `setup.sh` step `5b` merges it into `~/.claude/settings.json` (union, deduped, idempotent — existing rules are never dropped).

- Add or remove a rule → edit `~/.agents/claude-permissions.json`, then `bash ~/.agents/setup.sh`.
- **Never hand-edit `permissions` in `~/.claude/settings.json`** — it would drift from canonical and survive only until someone re-reads the source.
- Allowed = runs with no prompt in **every** project. Unmatched calls still prompt. `deny` entries are hard-blocked, not prompted.
- Deliberately NOT allowlisted (still prompt): `rm`, `sudo`, `curl`/`wget`, `git push`, package installs, `chmod`/`chown`, `mv`, `dd`.
- Per-project `.claude/settings.local.json` files accumulate one-off absolute-path rules from clicking Approve. That is disposable noise — do not promote it wholesale; lift only the generic patterns.

---

## Caveman mode — ALWAYS ON (global default)

**Every response.** Every project. No opt-in per session.

Talk terse like smart caveman. Keep all technical accuracy. Drop articles, filler, pleasantries, hedging. Fragments OK.

- Pattern: `[thing] [action] [reason]. [next step].`
- Code, commits, PRs, diffs: write **normal** (not caveman).
- Security warnings & irreversible actions: write **clear**, then resume caveman.
- User says **stop caveman** or **normal mode** → revert for rest of session.
- Adjust level: `/caveman lite|full|ultra` (default: **full**).

---

## `create_project` trigger

When the user says **`create_project`** (starting a new project), always set up the standard layout. Fast path: `cp -r ~/.agents/project-template/. <project-dir>/` then fill in names; or create the files manually:

| File | Audience | Maintenance |
|------|----------|-------------|
| `AGENTS.md` | all AI tools | Project rules/conventions. Canonical and ONLY project rules file (Claude Code loads it via SessionStart hook — never create a project CLAUDE.md). Committed by default — **except** `~/projects/sites/*` (see Sites rule). |
| `session_transcript.md` | **human ONLY** | Append-only narrative log of each work session, newest at bottom. Written for the user to read back. AI agents NEVER read it (Transcript privacy HARD RULE). |
| `session_compact.md` | **AI handoff** | Concise state: current status, where we left off, next steps, key decisions, open issues. Always records the active **model + effort**. **Rewrite** (not append) at end of session / major milestone / before context compaction. |
| `docs/DECISIONS.md` | all AI tools | ADR log: decision + why + rejected alternatives, appended in the same turn a choice is made. Versioned (committed in repos). |
| `.gitignore` | git | Must ignore session files (`session_compact.md`, `session_transcript.md`, `claude_memory_import.md` + legacy session paths). Comes from the template; if project already has a `.gitignore`, **merge** those lines in (do not overwrite the whole file). Under `~/projects/sites/*` also ignore `AGENTS.md` and `CLAUDE.md`. |

Rules:

1. **Session start in any project:** if `session_compact.md` exists, read it FIRST to restore where we left off — before doing other work.
2. **During work:** append to `session_transcript.md` at milestones (human-readable, chronological, verbose OK).
3. **End of session / milestone / before compaction:** rewrite `session_compact.md` to reflect the latest state. It must always be accurate enough for a fresh AI session to resume work from it alone.
4. Session files live in the project root. **Never commit them unless the user explicitly says otherwise** — `session_transcript.md` and `session_compact.md` are local-only; the template `.gitignore` enforces this. If copying files by hand (no template), add the same ignore lines.
5. **Model tracking:** at `create_project`, record the active model + effort in `session_compact.md` (read the tool's config — `opencode.jsonc` / `~/.claude/settings.json` / `~/.grok/config.toml` — or ask the user once). The **Models used** list in compact is CUMULATIVE: preserve it across rewrites, mark the current one, add a line whenever model or effort changes. Every switch also goes to `session_transcript.md` (old → new, reason if known) — the transcript is the lossless copy. If the user says they switched models, log it immediately.

---

## `continue_project` trigger

When the user says **`continue_project <path>`** (example: `continue_project /home/brwsk/projects/some_dummy_project`), resume that project from disk. Do this **before** other work:

1. Resolve `<path>` (absolute or relative). Must be a directory. If missing/invalid → stop and say so.
2. **Residue / conflict check (all tools):**
   - Memory: if `~/cron-jobs/claude-memory-guard/NEEDS-MEMORY-MERGE` or `~/.agents/backups/claude-residue/PENDING.md` or `<path>/claude_memory_import.md` exists → process memory residue merge (Memory policy) **before** relying on project files.
   - Symlinks: if `~/cron-jobs/agents-symlink-guard/NEEDS-SYMLINK-MERGE` exists → process symlink conflict merge (see Cron guards) before editing global rules.
3. **Read, in order** (only if the file exists):
   1. `<path>/session_compact.md` — where we left off (AI handoff; **required read when present**)
   2. `<path>/AGENTS.md` — project rules/conventions
   3. `<path>/docs/DECISIONS.md` — durable choices + why
4. **Do NOT** open `<path>/session_transcript.md` unless the user explicitly asks (Transcript privacy HARD RULE).
5. If none of the three files exist → say the path has no project session layout; offer `create_project` there (or fix the path).
6. After reading: brief status (current state + where we left off + open issues from compact), then wait for / take the user's next instruction. Do not invent state that is not in those files.
7. Treat `<path>` as the project root for the rest of the session (paths, git, session file updates) unless the user points elsewhere.

Same trigger for all tools (Grok / Claude Code / OpenCode). No tool-specific continue step.

---

## `checkpoint_project` trigger

When the user says **`checkpoint_project`** (done for the day — leave and resume later), apply to the **current** project (cwd walk-up to nearest project root, stopping before `$HOME`):

1. Resolve the project root. No session layout there (no `session_compact.md` / `AGENTS.md`) → say so, offer `create_project`.
2. Read `session_compact.md` (state restore). NEVER open `session_transcript.md` (Transcript privacy HARD RULE).
3. Rewrite `session_compact.md` so a fresh AI session can resume from it alone: current state, where we left off (concrete next step), key decisions, open issues, and the cumulative **Models used** list (current marked).
4. Append a `## <YYYY-MM-DD> — wrap-up` entry to `session_transcript.md` (write-only): what was done today + the next step.
5. Backfill `docs/DECISIONS.md` with any meaningful choices from this session not yet logged (same-turn ADR rule).
6. Finish with: "Checkpoint saved — next step: <X>".

Same for all three tools. Formalizes the existing "End of session / milestone" rule as an explicit trigger.

---

## Global workflow

These rules apply to **every project**, all tools. Per-project `AGENTS.md` and `docs/DECISIONS.md` add project-specific detail.

### Project knowledge (two layers)

| Layer | Location | Git | Purpose |
|-------|----------|-----|---------|
| **Tracked project knowledge** | `docs/DECISIONS.md`; usually also `AGENTS.md` | Yes | Durable decisions, conventions — shareable |
| **Local session files** | `session_compact.md`, `session_transcript.md`, `claude_memory_import.md` (+ legacy `docs/session-archive/`, `docs/session-flushes/`) | No (gitignored) | Session state + full log + residue staging. Never committed unless the user explicitly says otherwise |

### Sites repos — `AGENTS.md` local-only (HARD RULE for `~/projects/sites/*`)

Applies only under **`~/projects/sites/<site>/`** (public site repos). Not other projects.

- `AGENTS.md` must be in that site's **`.gitignore`** (with `CLAUDE.md` if present). **Never commit** site agent rules to GitHub.
- `docs/DECISIONS.md` **is** committed (shareable product/architecture rationale).
- Session files stay gitignored like everywhere else.
- Non-site projects: **do** commit `AGENTS.md` by default (team/shareable conventions).

When `create_project` lands under `~/projects/sites/`, merge the usual session ignore lines **and** add `AGENTS.md` + `CLAUDE.md` to `.gitignore`.

### Transcript privacy — HARD RULE

`session_transcript.md` is the **user's private log**. AI agents NEVER open or read it unless the user explicitly asks. Appending at milestones is fine — reading is not. The only AI-facing session file is `session_compact.md`.

### On session start

0. **Residue / conflict check:** memory (`NEEDS-MEMORY-MERGE` / `PENDING.md` / project `claude_memory_import.md`) and/or symlink (`NEEDS-SYMLINK-MERGE`) — process first (Memory policy + Cron guards).
1. If `session_compact.md` exists in the project root, read it first — it says where we left off.
2. Read project `AGENTS.md` and `docs/DECISIONS.md` if they exist.
3. Do NOT open `session_transcript.md` (Transcript privacy rule above).

### During work

- **Meaningful choice made** (architecture, naming, security trade-off, rejected alternative) → append an ADR entry to `docs/DECISIONS.md` **in the same turn**. Include *why* and what was rejected.
- **Durable fact** (commands, paths, conventions) → project `AGENTS.md`; global fact → this file.
- **Milestone reached** → append to `session_transcript.md`.
- **Before compaction or ending a long session** → rewrite `session_compact.md`.

### End of session / milestone

1. Rewrite `session_compact.md` (see `create_project` rules).
2. Confirm `docs/DECISIONS.md` has any new decisions from this session.

### New / resume projects

- **`create_project`** — scaffold a new project (template). Only new-project trigger.
- **`continue_project <path>`** — resume an existing project from its session files (see section above).
- **`checkpoint_project`** — end-of-day wrap-up of the current project (see section above).
- No tool-specific init/continue steps. Retired Grok-era machinery (`init-project`, `/flush`, `docs/SESSION.md`, tool-internal memory) must not be recreated.

---

## Memory policy — everything in shared files

- ALL durable memory → shared markdown only: this file (global rules), project `AGENTS.md`, `session_compact.md`, `docs/DECISIONS.md` (project facts). Nothing important anywhere else.
- **Tool-internal memory stores are DISABLED / removed by user policy**:
  - Grok: `[memory] enabled = false` in `~/.grok/config.toml`. Do **not** recreate `~/.grok/memory/`. If it reappears, ignore it; guards delete it (after archive).
  - Claude: every `~/.claude/projects/*/memory/` holds only a DISABLED stub `MEMORY.md` (no topic files). Do **not** write memories there. Do **not** use Claude's `#` memory shortcut (it would create project `CLAUDE.md` / feed auto-memory — both forbidden).
  - OpenCode: no separate memory store; uses AGENTS.md only.
- When asked to "remember" something: global fact → this file; project fact → that project's files. Same turn, no exceptions.
- Keep this file LEAN — it loads into every session. Cross-project rules only; project specifics never belong here.
- Symlinked paths (`~/.claude/CLAUDE.md`, `~/.grok/AGENTS.md`, `~/.config/opencode/AGENTS.md`) all write to this file.

### Cron guards (machine hygiene)

| Guard | Script source | Installed as | Flag (if AI/human work needed) | Job |
|-------|---------------|--------------|--------------------------------|-----|
| Symlink | `~/.agents/hooks/check-links.sh` | `~/cron-jobs/agents-symlink-guard/check-links.sh` | `NEEDS-SYMLINK-MERGE` | Keep the 3 AGENTS symlinks healthy |
| Tool memory | `~/.agents/hooks/check-claude-memory.sh` | `~/cron-jobs/claude-memory-guard/check-memory.sh` | `NEEDS-MEMORY-MERGE` | Detect Claude/Grok memory residue → archive → stage → wipe to stub |

Both installed by `setup.sh` (copy from `hooks/`). Schedule: `@daily` + `@reboot` each. Stray merging is automated by `~/.agents/hooks/merge-strays.sh` (cron `@daily`, see Symlink conflict section below).

**Two different flags — do not mix them up:**

| Flag path | Meaning |
|-----------|---------|
| `~/cron-jobs/claude-memory-guard/NEEDS-MEMORY-MERGE` | Staged Claude/Grok memory residue to merge into markdown |
| `~/cron-jobs/agents-symlink-guard/NEEDS-SYMLINK-MERGE` | Quarantined divergent global-rules file under `backups/strays/` |

### Claude/Grok residue → merge into standard files (AI duty)

Cron **cannot** judge “important facts” (no LLM). It only stages. **You (the AI) merge.**

**When:** session start, `continue_project`, or any time you notice:

- flag `~/cron-jobs/claude-memory-guard/NEEDS-MEMORY-MERGE`, or
- `~/.agents/backups/claude-residue/PENDING.md`, or
- project-root `claude_memory_import.md`

**Do:**

1. Read `PENDING.md` and each listed `PACKET.md` (and any `claude_memory_import.md`).
2. Sort facts:
   - global / cross-project → this file (`~/.agents/AGENTS.md`)
   - project conventions, commands, deploy notes → project `AGENTS.md`
   - current handoff / open work → `session_compact.md`
   - architecture choice + why → `docs/DECISIONS.md`
   - skip junk, duplicates, and “DISABLED” stubs
3. If the project has `session_transcript.md`, append a one-line note that residue was imported (write-only; do not read the rest of the file). Skip if no transcript file exists.
4. Delete processed `claude_memory_import.md`. Remove processed packet lines from `PENDING.md`; if empty, delete `PENDING.md` and the `NEEDS-MEMORY-MERGE` flag.
5. Never re-create tool memory stores. Never leave durable facts only in the archive.

### Symlink conflict → merge into canonical (AUTOMATED)

**`~/.agents/hooks/merge-strays.sh` does this automatically** (cron @daily, after the guard): each quarantined stray is fed to a headless LLM ("extract unique durable rules not already in canonical → one markdown section or SKIP"), output is sanitized and appended to canonical, the stray is deleted, the flag cleared. Nothing to type.

**You (AI/human) intervene only when:** the flag survives two merge runs (LLM failing), or you want to relocate merged content from the file tail into its proper section.

Manual procedure (fallback only):
1. Read each listed file under `~/.agents/backups/strays/`.
2. If it has unique durable rules not already in `~/.agents/AGENTS.md`, merge those into the canonical file (this file).
3. Delete the processed stray file path lines from `NEEDS-SYMLINK-MERGE`; if empty, delete the flag.
4. Symlinks should already point at the canonical file (guard re-linked them).
