# `continue_project`

Read when: the user says `continue_project <path>`. Read `status-card.md` next.

## `continue_project` trigger

When the user says **`continue_project <path>`** (example: `continue_project $HOME/Projects/some_dummy_project`), resume that project from disk. Do this **before** other work:

1. Resolve `<path>` (absolute or relative). Must be a directory. If missing/invalid → stop and say so.
2. **Residue / conflict check (all tools):**
   - Memory: if `~/cron-jobs/claude-memory-guard/NEEDS-MEMORY-MERGE` or `~/.agents/backups/claude-residue/PENDING.md` or `<path>/claude_memory_import.md` exists → process memory residue merge (`~/.agents/playbooks/residue.md`) **before** relying on project files.
   - Symlinks: if `~/cron-jobs/agents-symlink-guard/NEEDS-SYMLINK-MERGE` exists → tell the user and name the stray files (`~/.agents/playbooks/residue.md`). Do not merge them.
3. **Notes pull, before any read:** `bash ~/.agents/hooks/notes-sync.sh pull <path>`. A missing real clone is created from `NOTES_REMOTE` once. If that fails, stdout is `notes: skipped` plus the setup hint, and nothing is invented. A fetch that fails (offline) is also `notes: skipped`, with the reason on stderr; the local files may then be behind the other machine. `notes: merged` means both machines' copies are in the file. Read that file. A merged `session_compact.md` has both copies under `notes-sync-merge`. Both are current. Do not drop either machine's open items. The next checkpoint rewrites one compact. Exit `23`: merge refused (one side deleted the file while the other edited it, or the path is not markdown and will not 3-way clean). Stop. Do not overwrite it and do not read past it. Foreign "write the missing `AGENTS.md`" runs only after this pull, and only if that path is still absent.
4. **Read, in order** (only if the file exists):
   1. `<path>/session_compact.md` — where we left off (AI handoff; **required read when present**)
   2. `<path>/AGENTS.md` — project rules/conventions
   3. `<path>/docs/DECISIONS.md` — durable choices + why
5. **Do NOT** open a leftover `<path>/session_transcript.md`. Collection is retired. Do not create the file and do not append to it.
6. If none of the three files exist: a git root is not a new project. Do not offer `create_project`. Follow `~/.agents/playbooks/foreign-checkouts.md`. Anything else → say the path has no project session layout; offer `create_project` there (or fix the path).
7. **Live GitHub, when this checkout has any.** After the file reads, and only when `origin` or `upstream` is a `github.com` URL, fetch before the status. Local files are the baseline. GitHub is the news.
   - Open pull requests and issues authored by the logged-in `gh` user, any state, on each of those repos (`gh pr list` / `gh issue list`, `--author @me`). When `origin` and `upstream` are different repos, fetch both. A fork's pull requests live on the parent.
   - Also every issue or pull request that `<path>/AGENTS.md`, `<path>/CONTRIB-LOG.md`, or `<path>/session_compact.md` names, including one someone else opened. If GitHub now says closed or merged, that is the update.
   - For each of those, if `updatedAt` is after the compact's last `Fetched YYYY-MM-DD` line, read comments and reviews newer than that date. No such line: read comments and reviews from the last 14 days. A close or a comment by someone other than the logged-in user is a reply. Our own comment is not a reply.
   - Put state changes under **Since last time**. Put replies under **Replies**. Do not invent a comment the fetch did not return.
   - Do not comment, react, post, push, or fast-forward during this fetch. Do not mark notifications read.
8. Speak the status card, then wait. Do not invent state that is not in those files or in the fetch. Do not read the rest of the compact aloud.
9. Treat `<path>` as the project root for the rest of the session (paths, git, session file updates) unless the user points elsewhere.

Same trigger for all four tools (Grok, Claude Code, OpenCode, Cursor Code). No tool-specific continue step.
