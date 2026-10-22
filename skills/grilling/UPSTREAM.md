# Upstream

- Source: https://github.com/mattpocock/skills/tree/5beb35b040e3de97e54fa9e386d7e42d15c295c2/skills/productivity/grilling
- Commit: 5beb35b040e3de97e54fa9e386d7e42d15c295c2 (committed 2026-10-19T15:51:40Z)
- License: MIT, Copyright (c) 2026 Matt Pocock. Full text: LICENSE.upstream (keep it).
- Local changes (trims):
  - Description fires only when the user says grill, and names the handoff to `writing-plans`. Upstream also loaded when the user "wants to stress-test their thinking" or used any grill-like phrase.
  - Added a load guard: creative work and brainstorming do not start the interview, and this skill does not write the plan.
  - Dropped `agents/openai.yaml` (packaging for another host).
- Diff: `diff -u <upstream>/skills/productivity/grilling/SKILL.md SKILL.md`.
