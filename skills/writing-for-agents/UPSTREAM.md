# Upstream

- Source: https://github.com/mattpocock/skills/tree/5beb35b040e3de97e54fa9e386d7e42d15c295c2/skills/productivity/writing-for-agents
- Commit: 5beb35b040e3de97e54fa9e386d7e42d15c295c2 (committed 2026-10-19T15:51:40Z)
- License: MIT, Copyright (c) 2026 Matt Pocock. Full text: LICENSE.upstream (keep it).
- Local changes (trims):
  - Description starts with "Use when" and names AGENTS.md, CLAUDE.md, skill edits, and `global_brain_update`. Upstream led with "Writing documents for agents."
  - Added `## 1config`. Frontmatter stays `name` and `description` only. Do not create a project `CLAUDE.md`.
  - `SKILL-MECHANICS.md` kept, plus a 1config note: no `disable-model-invocation` (Grok and OpenCode share this file).
  - Dropped `agents/openai.yaml` (packaging for another host).
- Diff: `diff -u <upstream>/skills/productivity/writing-for-agents/SKILL.md SKILL.md`.
