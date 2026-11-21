# Guards, flags, and residue

Read when: a `NEEDS-MEMORY-MERGE` or `NEEDS-SYMLINK-MERGE` flag, `PENDING.md`, or a `claude_memory_import.md` exists, or the task is one of the two guards.

### Cron guards (machine hygiene)

| Guard | Script source | Installed as | Flag (if AI/human work needed) | Job |
|-------|---------------|--------------|--------------------------------|-----|
| Symlink | `~/.agents/hooks/check-links.sh` | `~/cron-jobs/agents-symlink-guard/check-links.sh` | `NEEDS-SYMLINK-MERGE` | Keep the 4 AGENTS symlinks healthy |
| Tool memory | `~/.agents/hooks/check-claude-memory.sh` | `~/cron-jobs/claude-memory-guard/check-memory.sh` | `NEEDS-MEMORY-MERGE` | Detect Claude/Grok memory residue → archive → stage → wipe to stub |

Both installed by `setup.sh` (copy from `hooks/`). Schedule: `1config-guards.timer`, a systemd user timer. It runs daily, catches up a missed day, and runs two minutes after login. One run is the symlink guard, then the memory guard. No script merges a stray rules file (see the Symlink conflict section below, in this file). A machine with no systemd user manager gets the same chain in cron. `hooks/scheduler.sh` picks, and leaves exactly one of the two installed.

**Two different flags — do not mix them up:**

| Flag path | Meaning |
|-----------|---------|
| `~/cron-jobs/claude-memory-guard/NEEDS-MEMORY-MERGE` | Staged Claude/Grok memory residue to merge into markdown |
| `~/cron-jobs/agents-symlink-guard/NEEDS-SYMLINK-MERGE` | A divergent global-rules file kept under `backups/strays/`, waiting for the user |

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
3. Delete processed `claude_memory_import.md`. Remove processed packet lines from `PENDING.md`; if empty, delete `PENDING.md` and the `NEEDS-MEMORY-MERGE` flag.
4. Never re-create tool memory stores. Never leave durable facts only in the archive. Do not write `session_transcript.md`.

### Symlink conflict → the stray waits for the user

`hooks/check-links.sh` copies a diverged rules file to `~/.agents/backups/strays/`, restores the link, and lists the copy in `NEEDS-SYMLINK-MERGE`. No script and no model merges it into this file: every tool obeys this file, so what enters it is the user's decision.

When the flag exists:

1. Tell the user, and name each stray file the flag lists. Do not merge it.
2. Merge only the lines the user asks for, as a normal brain edit (`setup.sh`, then `sync.sh`).
3. Delete a stray file only when the user says it is done. The guard then drops its line, and the flag with the last line.
