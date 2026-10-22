# Upstream

- Source: https://github.com/obra/superpowers/tree/2ce8aa15d05bd57213e6f746f953aafb7ded7a8b/skills/requesting-code-review
- Commit: 2ce8aa15d05bd57213e6f746f953aafb7ded7a8b (committed 2026-10-21T21:00:49Z)
- License: MIT, Copyright (c) 2025 Jesse Vincent. Full text: LICENSE.upstream (keep it).
- Local changes (trims):
  - Removed "After each task in subagent-driven development" (skill not adopted).
  - `Dispatch a \`general-purpose\` subagent` (Claude agent-type name) → tool-neutral wording plus a self-review fallback for tools without subagents.
  - Example path `docs/superpowers/plans/…` → `docs/plans/…`.
  - "your human partner" → "the user". `code-reviewer.md` kept verbatim.
  - Example `BASE_SHA` line uses `cut -d' ' -f1` instead of `awk '{print $1}'`, matching upstream at this pin.
  - Re-checked the rest of the skill at this pin. `code-reviewer.md` had no upstream diff.
- Diff: `diff -u <upstream>/skills/requesting-code-review/SKILL.md SKILL.md`.
