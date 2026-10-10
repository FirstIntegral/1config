# Upstream

- Source: https://github.com/obra/superpowers/tree/8ca22dba9a94f28898bbce59f2537ff4d87c747d/skills/requesting-code-review
- Commit: 8ca22dba9a94f28898bbce59f2537ff4d87c747d (committed 2026-09-25T11:06:27-07:00)
- License: MIT, Copyright (c) 2025 Jesse Vincent. Full text: LICENSE.upstream (keep it).
- Local changes (trims):
  - Removed "After each task in subagent-driven development" (skill not adopted).
  - `Dispatch a \`general-purpose\` subagent` (Claude agent-type name) → tool-neutral wording plus a self-review fallback for tools without subagents.
  - Example path `docs/superpowers/plans/…` → `docs/plans/…`.
  - "your human partner" → "the user". `code-reviewer.md` kept verbatim.
- Diff: `diff -u <upstream>/skills/requesting-code-review/SKILL.md SKILL.md`.
