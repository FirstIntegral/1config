# Upstream

- Source: https://github.com/obra/superpowers/tree/8ca22dba9a94f28898bbce59f2537ff4d87c747d/skills/writing-plans
- Commit: 8ca22dba9a94f28898bbce59f2537ff4d87c747d (committed 2026-09-25T11:06:27-07:00)
- License: MIT, Copyright (c) 2025 Jesse Vincent. Full text: LICENSE.upstream (keep it).
- Local changes (trims):
  - Removed `[plugin-prefixed] using-git-worktrees` context line.
  - Plan header's `REQUIRED SUB-SKILL: Use [plugin-prefixed] subagent-driven-development … or [plugin-prefixed] executing-plans` → "implement this plan task-by-task, in order".
  - "during brainstorming" → "before planning"; `docs/superpowers/plans/` → `docs/plans/`.
  - The two `REQUIRED SUB-SKILL` handoff bullets → execute task-by-task, run `verification-before-completion`, use `requesting-code-review` when subagent-driven, log choices in `docs/DECISIONS.md`, commits signed with no AI co-author lines.
- Diff: `diff -u <upstream>/skills/writing-plans/SKILL.md SKILL.md`.
