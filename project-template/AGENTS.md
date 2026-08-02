# <Project Name>

## Overview
<what this project is — one paragraph>

## Stack / Conventions
<languages, frameworks, style rules>

## Commands
- Build:
- Test:
- Run:

## Session files
- `session_compact.md` — AI handoff state. Read FIRST at session start; rewrite at end of session / milestone. Local-only (gitignored): never commit unless the user says otherwise.
- `session_transcript.md` — human-ONLY narrative log. Append at milestones; AI NEVER reads it unless the user explicitly asks. Local-only (gitignored): never commit unless the user says otherwise.
- `docs/DECISIONS.md` — ADR log; append decision + why in the same turn it is made. Versioned (committed in repos).
- `.gitignore` — ignores the session files above, `claude_memory_import.md`, and legacy session paths. Sites under `~/projects/sites/` also ignore `AGENTS.md` / `CLAUDE.md`.
