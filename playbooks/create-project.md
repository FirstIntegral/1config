# `create_project`

Read when: the user says `create_project`.

## `create_project` trigger

When the user says **`create_project`** (starting a new project), always set up the standard layout. Resolve the target before editing: `create_project <name>` with a simple name means `~/Projects/<name>`; an explicit absolute or relative path containing `/` is used after resolution; a missing name requires a question. Never use the current working directory as the default for a simple name. `verify.sh` runs `hooks/rule-oracles.sh`: `foo` → `~/Projects/foo`, a name containing `/` is not moved under `~/Projects`, an empty name exits 30 (ask). That fixture also fails if a hook reads `session_transcript.md`. Fast path: `cp -r ~/.agents/project-template/. <project-dir>/` then fill in names; or create the files manually:

| File | Audience | Maintenance |
|------|----------|-------------|
| `AGENTS.md` | all AI tools | Project rules/conventions, plus a `## Repo` line recording the remote (or `none (local only)`). Canonical and ONLY project rules file (Claude Code 2.1.277+ reads it natively — never create a project CLAUDE.md). Committed by default — **except** `~/Projects/sites/*` (see the Sites rule in `AGENTS.md`). |
| `session_compact.md` | **AI handoff** | Top is the status card (`## How things are`, `## Left to do`). Below that: model + effort, decisions, pointers. **Rewrite** (not append) at end of session / major milestone / before context compaction. Every rewrite keeps the card at the top. |
| `docs/DECISIONS.md` | all AI tools | ADR log: decision + why + rejected alternatives, appended in the same turn a choice is made. Versioned (committed in repos). |
| `.gitignore` | git | Must ignore session files (`session_compact.md`, `claude_memory_import.md`, a leftover `session_transcript.md`, + legacy session paths) and `explain/`. Comes from the template; if project already has a `.gitignore`, **merge** those lines in (do not overwrite the whole file). Under `~/Projects/sites/*` also ignore `AGENTS.md` and `CLAUDE.md`. |

Rules:

1. **Session start in any project:** if `session_compact.md` exists, read it FIRST to restore where we left off — before doing other work.
2. **During work:** do not write `session_transcript.md`. ADRs go to `docs/DECISIONS.md` in the same turn.
3. **End of session / milestone / before compaction:** rewrite `session_compact.md` to reflect the latest state. It must always be accurate enough for a fresh AI session to resume work from it alone.
4. `session_compact.md` lives in the project root. **Never commit it unless the user explicitly says otherwise.** The template `.gitignore` enforces this, and it still names a leftover `session_transcript.md`. If copying files by hand (no template), add the same ignore lines. Do not create `session_transcript.md`.
5. **`create_project` never creates a git repo or a remote.** Whether a project goes to GitHub is the user's call, made explicitly. Fill the `## Repo` line with `none (local only)` and leave it; update it the same turn a remote is actually added, so `checkpoint.sh`'s cross-check stays meaningful. It does not create `machine-notes` and does not invent a notes key. No origin means a later notes sync skips.
6. **Model tracking:** at `create_project`, record the active model + effort in `session_compact.md` (read the tool's config — `opencode.jsonc` / `~/.claude/settings.json` / `~/.grok/config.toml` — or ask the user once). The **Models used** list in compact is CUMULATIVE: preserve it across rewrites, mark the current one, add a line whenever model or effort changes. If the user says they switched models, log it in that list immediately.
7. **Handoff shape:** point at specs, ADRs, and commits by path. Do not copy them into `session_compact.md`. List the skills the next agent should load. Redact secrets. Do not drop these three lines on a rewrite.
