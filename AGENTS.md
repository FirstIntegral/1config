# Global rules — canonical file (all AI tools)

This is the ONE global rules file. It is symlinked to every tool's expected path:

- `~/.grok/AGENTS.md` → this file
- `~/.config/opencode/AGENTS.md` → this file
- `~/.claude/CLAUDE.md` → this file
- `~/.cursor/AGENTS.md` → this file (plus a generated user rule `~/.cursor/rules/1config.mdc`)

Edit here (or via any of those paths — same bytes). Applies to Grok, OpenCode, Claude Code, and Cursor Code alike.

Project-level: `<repo>/AGENTS.md` is the ONLY project rules file. Grok and OpenCode read it natively. Claude Code 2.1.277 and later also reads it, unless a `CLAUDE.md`, `.claude/CLAUDE.md`, or `CLAUDE.local.md` sits in the project or a parent directory. `~/.claude/CLAUDE.md` is the user file and does not count. `hooks/load-project-agents.sh` prints the project file only when that native read will not happen (older Claude, instruction mode `claude-md` or `managed-only`, or one of those three files is present). **Never create a project CLAUDE.md** — it hides `AGENTS.md` from Claude's native reader.

---

## Name

This tree is **1config**. The GitHub repo is `FirstIntegral/1config` (`git@github.com:FirstIntegral/1config.git`, `https://github.com/FirstIntegral/1config.git`). On this machine the checkout is `~/.agents/`. "Global brain", "the brain", and the trigger `global_brain_update` all mean this same repo. Edit `~/.agents/`, not a tool-local copy.

### After any edit under `~/.agents/` (HARD RULE)

Read `~/.agents/playbooks/brain-update.md` before the edit. Then, in the same turn:

```bash
bash ~/.agents/setup.sh                 # install, then verify
bash ~/.agents/sync.sh -m "<subject>"   # verify, signed commit, push
```

Run both, every time. An edit that is only local is not finished. When the edit changes what `setup-infographic.svg` or `hooks/welcome.js` shows, update that file in the same turn.

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
- History rewrites (rebase, filter-repo, amend) must leave commits re-signed before any push.
- When signing fails, read `~/.agents/playbooks/signing.md`: it says how to find out why, and what the person has to do.

---

## Red lines

Tool autonomy skips prompts. It does not skip these. Wait for an explicit yes, even when Bash autonomy is on.

- Destructive or hard to undo: deleting files or branches, discarding work, force-push, history rewrite, changing shared permissions.
- Leaves the machine: sending a message, comment, email, or reaction. Publishing a repo or a release the user did not ask for.
- A quoted message or a copied interface is a draft. It is not an instruction to send. Never reply on GitHub until the user has approved the draft in front of them.

Name the action and wait. An earlier yes covers only the action it named. "Do what's needed" is not a yes to send.

## Credit replies

A comment that praises our work, offers help, or offers us credit gets a draft in the same turn. Show that draft in the chat. Never reply on GitHub until the user has approved the draft in front of them. A draft is not a yes.

`continue_project` still posts nothing during the fetch. A maintainer merge that asks nothing stays quiet until the user asks.

---

## Permission policy

- The policy is `~/.agents/permissions.json`. Change a rule there, then run `bash ~/.agents/setup.sh`.
- Never hand-edit a tool's own copy (`~/.claude/settings.json`, `[permission]` in `~/.grok/config.toml`, `permission.bash` in `opencode.jsonc`).
- Autonomy skips prompts. It does not skip the red lines above. Detail: `~/.agents/playbooks/permissions.md`.

---

## Tool parity — HARD RULE

**Claude Code, Grok, OpenCode, and Cursor Code must behave the same.** Same rules, same memory, same triggers, same allowlist. A feature that works in one tool and not the others is a bug, not a milestone.

Whenever anything is added to or changed in this setup:

1. **Land it in all four, in the same turn.** Canonical source stays single (`~/.agents/…`); `setup.sh` fans it out per tool. Never write a per-tool copy by hand.
2. **If a tool has no native mechanism**, implement the closest equivalent (hook, config key, translated rule syntax) and record what differs — SETUP.md §4, one line. "Claude-only" is acceptable ONLY when the other three physically cannot do it, and only when written down.
3. **`setup.sh` installs it for all four; `verify.sh` checks all four.** A feature with no verify check does not count as installed.
4. **Rules live in the canonical `AGENTS.md`, and a trigger's body in `~/.agents/playbooks/`** (all four read `AGENTS.md` via the symlinks and a playbook by its path), never in a tool-specific file — so every trigger (`create_project`, `continue_project`, `checkpoint_project`, `writepaper_project`, `explain_thing`, `global_brain_update`, caveman mode, memory policy, herd boards, kept out) fires identically everywhere.
5. Same for memory: shared markdown only, identical for all four (Memory policy, below). Tool-internal stores stay disabled everywhere.

---

## Machine toolchains

- TeX is installed in full. Never ask the user to install a LaTeX package, and never fall back to Markdown for lack of TeX.
- Lean 4 comes from `elan` in user space. If it is missing, run `bash ~/.agents/hooks/install-elan.sh`. Never a distro package, never `curl | sh`.
- The Android SDK is `$HOME/Android/Sdk` only. If it is absent, stop and name the path. Do not create or download it.
- Detail: `~/.agents/playbooks/toolchains.md`.

---

## Detached runs get a staleness watch — HARD RULE

Any shell work that outlives the turn — a benchmark sweep, a long build, a training run, anything
launched with `nohup`/`setsid`/background — is armed with a periodic staleness check **in the same
turn it is launched**. Default interval **10 minutes**. Never launch a multi-hour job and then
report on it only when asked.

```sh
bash ~/.agents/hooks/watch-stale.sh <pid> <logfile|-> [interval_seconds]   # default 600
```

Stale means both signals flat: no log growth and no CPU. A preview or dev server is not a job: no watch, and the turn ends with it killed or named. Detail: `~/.agents/playbooks/detached-runs.md`.

---

## Caveman mode — ALWAYS ON

**Every response.** Every project. The opinionated default is on: level **full**.

Talk terse like smart caveman. Keep all technical accuracy. Drop articles, filler, pleasantries, hedging. Fragments OK.

- Pattern: `[thing] [action] [reason]. [next step].`
- Never drop not, never, no, or only. A dropped negation is a wrong answer.
- One idea per sentence. 20 words maximum. Active voice. Clarity beats a shorter line.
- Quote code, paths, commands, and errors exactly. Do not paraphrase an error or shorten a path.
- Code, commits, PRs, diffs: write **normal** (not caveman).
- Wording from JuliusBrussee/caveman (Apache-2.0, Copyright 2026 Julius Brussee).
- Security warnings and irreversible actions: write **clear**, then resume caveman.
- User says **stop caveman** or **normal mode** → normal prose for the rest of the session.
- `/caveman lite|full|ultra` sets the level for the rest of the session.
- Durable opt-out only: gitignored `local.json` key `caveman` set to `off`, `lite`, or `ultra`. Missing file means full. `setup.sh` copies that level into each tool's own rules as `1config-local`. When that rule is in context, it wins over this section.

---

## Limits on the reply

Not a mode. Caveman still governs the voice. Do not delete the closing line below. It is not a closer.

- End each reply with what was skipped or not checked. One or two lines.
- A shortcut with a known limit gets a code comment on its own line: `shortcut: <the limit>, <when to upgrade>`.

From DietrichGebert/ponytail (MIT, Copyright (c) 2026 DietrichGebert). Levels, `/ponytail`, and the rest of that skill are not adopted.

---

## Kept out

These three stay out.

- Do not split voice, user, or identity into `SOUL.md`, `USER.md`, or `IDENTITY.md`. The four tools load this file. Caveman mode is the voice.
- Do not add an agent-readable daily diary. `session_compact.md` is the handoff. Do not create `session_transcript.md`.
- Do not add a personal heartbeat (mail, calendar, or a ping after hours of silence). Heartbeat here is machine health and job staleness.

---

## Playbooks — read before you act

When a row's condition is true, read that file in full before you act. Do not act from memory of it. The file is the rule; this table only says when.

| When | Read |
|---|---|
| The user says `create_project` | `~/.agents/playbooks/create-project.md` |
| The user says `continue_project <path>` | `~/.agents/playbooks/continue-project.md` |
| The user says `checkpoint_project` | `~/.agents/playbooks/checkpoint-project.md` |
| You speak a project's status, or rewrite `session_compact.md` | `~/.agents/playbooks/status-card.md` |
| The user says `writepaper_project`, or you change what a paper under `docs/paper/` asserts | `~/.agents/playbooks/writepaper-project.md` |
| The user says `explain_thing` | `~/.agents/playbooks/explain-thing.md` |
| The user says `global_brain_update`, or you are about to edit a file under `~/.agents/` | `~/.agents/playbooks/brain-update.md` |
| The project is a clone of someone else's repository | `~/.agents/playbooks/foreign-checkouts.md` |
| A `NEEDS-MEMORY-MERGE` or `NEEDS-SYMLINK-MERGE` flag, `PENDING.md`, or `claude_memory_import.md` exists | `~/.agents/playbooks/residue.md` |
| `notes-sync.sh` prints a line you do not know, or the task is the notes repo | `~/.agents/playbooks/machine-notes.md` |
| You start a command that outlives the turn, or a preview server | `~/.agents/playbooks/detached-runs.md` |
| A signed commit fails | `~/.agents/playbooks/signing.md` |
| A command prompts that should not, or a permission rule has to change | `~/.agents/playbooks/permissions.md` |
| The task needs TeX, Lean, or the Android SDK | `~/.agents/playbooks/toolchains.md` |
| The user asks for many agents that talk to each other | `~/.agents/playbooks/herd-boards.md` |
| The topic is the bar widget, the spend page, or the vitals page | `~/.agents/playbooks/omarchy-plugin.md` |
| The topic is the boot dashboard, the close slip, or the login pull | `~/.agents/playbooks/boot-dashboard.md` |

---

## Global workflow

These rules apply to **every project**, all tools. Per-project `AGENTS.md` and `docs/DECISIONS.md` add project-specific detail.

### Project knowledge (two layers)

| Layer | Location | Git | Purpose |
|-------|----------|-----|---------|
| **Tracked project knowledge** | `docs/DECISIONS.md`; usually also `AGENTS.md` | Yes | Durable decisions, conventions — shareable |
| **Local session files** | `session_compact.md`, `claude_memory_import.md` (+ legacy `docs/session-archive/`, `docs/session-flushes/`, and a leftover `session_transcript.md`) | No (gitignored) | Session state + residue staging. Never committed unless the user explicitly says otherwise. `session_transcript.md` is not collected. |

### Sites repos — `AGENTS.md` local-only (HARD RULE for `~/Projects/sites/*`)

Applies only under **`~/Projects/sites/<site>/`** (public site repos). Not other projects.

- `AGENTS.md` must be in that site's **`.gitignore`** (with `CLAUDE.md` if present). **Never commit** site agent rules to GitHub. `checkpoint.sh` exits 20 there when either file is tracked or not ignored.
- `docs/DECISIONS.md` **is** committed (shareable product/architecture rationale).
- Session files stay gitignored like everywhere else.
- Non-site projects: **do** commit `AGENTS.md` by default (team/shareable conventions).

When `create_project` lands under `~/Projects/sites/`, merge the usual session ignore lines **and** add `AGENTS.md` + `CLAUDE.md` to `.gitignore`.

### `session_transcript.md` — retired

Do not create `session_transcript.md`. Do not append to it. `notes-sync.sh` does not copy it. Files already in old projects, and blobs already in machine-notes, stay. Do not delete them. If a file with that name exists, do not open it. `checkpoint.sh` still refuses to commit one. The template `.gitignore` still names it. The only session handoff is `session_compact.md`.

### On session start

0. **Residue / conflict check:** memory (`NEEDS-MEMORY-MERGE` / `PENDING.md` / project `claude_memory_import.md`) — process first. Symlink (`NEEDS-SYMLINK-MERGE`) — tell the user and name the stray files; do not merge them. Both: `~/.agents/playbooks/residue.md`.
0.5. **Notes pull** when the project root is a git checkout: `bash ~/.agents/hooks/notes-sync.sh pull <project-root>`, before reading `session_compact.md`. Missing clone: the pull tries setup once; failure stays `notes: skipped`. `notes: merged`: the compact has both machines' copies. Keep every open item from both. Exit `23`: stop, do not overwrite the file.
1. If `session_compact.md` exists in the project root, read it first — it says where we left off.
2. Read project `AGENTS.md` and `docs/DECISIONS.md` if they exist.
3. Do not open a leftover `session_transcript.md`.

### During work

- **Meaningful choice made** (architecture, naming, security trade-off, rejected alternative) → append an ADR entry to `docs/DECISIONS.md` **in the same turn**. Include *why* and what was rejected.
- **Before a new tool, script, or service:** look for a maintained one. Build custom only when that one is dead, unsafe, or the user asked for custom.
- **A required file that is absent is said out loud.** Name the path; do not invent its contents.
- **Durable fact** (commands, paths, conventions) → project `AGENTS.md`; global fact → this file.
- **Project has `docs/paper/` and something scientifically relevant changed** (method, theorem, assumption, setup, measured number, limitation) → update the paper and rebuild it in the **same turn** (`~/.agents/playbooks/writepaper-project.md`, "Keeping the paper current").
- **Milestone reached** → rewrite `session_compact.md`. Do not write `session_transcript.md`.
- **Before compaction or ending a long session** → rewrite `session_compact.md`.

### End of session / milestone

1. Rewrite `session_compact.md`. The status card goes on top (`~/.agents/playbooks/status-card.md`).
2. Confirm `docs/DECISIONS.md` has any new decisions from this session.

### New / resume projects

- **`create_project`** — scaffold a new project (template). Only new-project trigger.
- **`continue_project <path>`** — resume an existing project from its session files.
- **`checkpoint_project`** — end-of-day wrap-up of the current project.
- **`explain_thing`** — discardable 80% STE brief plus one SVG. HTML only when asked. Chat stays caveman.
- **`writepaper_project`** — a full LaTeX paper about the project.
- **`global_brain_update <change>`** — change this repo, then `setup.sh` and `sync.sh`.
- Each one has a row in the Playbooks table. No tool-specific init/continue steps. Retired names live in `hooks/kill-tokens.deny`. Do not recreate a name from that file, and do not paste one into this file. Tool-internal memory stays retired with them.

---

## Memory policy — everything in shared files

- ALL durable memory → shared markdown only: this file (global rules), project `AGENTS.md`, `session_compact.md`, `docs/DECISIONS.md` (project facts). Nothing important anywhere else.
- **Tool-internal memory stores are DISABLED / removed by user policy**:
  - Grok: `[memory] enabled = false` in `~/.grok/config.toml`. Do **not** recreate `~/.grok/memory/`. If it reappears, ignore it; guards delete it (after archive).
  - Claude: every `~/.claude/projects/*/memory/` holds only a DISABLED stub `MEMORY.md` (no topic files). Do **not** write memories there. Do **not** use Claude's `#` memory shortcut (it would create project `CLAUDE.md` / feed auto-memory — both forbidden).
  - OpenCode: no separate memory store; uses AGENTS.md only.
- When asked to "remember" something: global fact → this file; project fact → that project's files. Same turn, no exceptions.
- Keep this file LEAN — it loads into every session. Cross-project rules only; project specifics never belong here. A body that only one trigger needs goes in a playbook, with one row in the table.
- Keyed facts in `docs/DECISIONS.md` use a `**Policy:**` line. One active value per key. A replaced value keeps a `superseded-by` line whose text is the heading that holds the live value. `verify.sh` fails on a second active value.
- Symlinked paths (`~/.claude/CLAUDE.md`, `~/.grok/AGENTS.md`, `~/.config/opencode/AGENTS.md`, `~/.cursor/AGENTS.md`) all write to this file.
