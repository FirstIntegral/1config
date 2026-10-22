# Upstream

- Source: https://github.com/obra/superpowers/tree/2ce8aa15d05bd57213e6f746f953aafb7ded7a8b/skills/writing-plans
- Commit: 2ce8aa15d05bd57213e6f746f953aafb7ded7a8b (committed 2026-10-21T21:00:49Z)
- License: MIT, Copyright (c) 2025 Jesse Vincent. Full text: LICENSE.upstream (keep it).
- Local changes (trims):
  - Removed `[plugin-prefixed] using-git-worktrees` context line.
  - Plan header's `REQUIRED SUB-SKILL: Use [plugin-prefixed] subagent-driven-development … or [plugin-prefixed] executing-plans` → "implement this plan task-by-task, in order".
  - "during brainstorming" → "before planning"; `docs/superpowers/plans/` → `docs/plans/`.
  - The two `REQUIRED SUB-SKILL` handoff bullets → execute task-by-task, run `verification-before-completion`, use `requesting-code-review` when subagent-driven, log choices in `docs/DECISIONS.md`, commits signed with no AI co-author lines.
  - Re-checked at this pin. Upstream file matches the previous pin. No new trim.
- Diff: `diff -u <upstream>/skills/writing-plans/SKILL.md SKILL.md`.
