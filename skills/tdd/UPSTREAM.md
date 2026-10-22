# Upstream

- Source: https://github.com/mattpocock/skills/tree/5beb35b040e3de97e54fa9e386d7e42d15c295c2/skills/engineering/tdd
- Commit: 5beb35b040e3de97e54fa9e386d7e42d15c295c2 (committed 2026-10-19T15:51:40Z)
- License: MIT, Copyright (c) 2026 Matt Pocock. Full text: LICENSE.upstream (keep it).
- Local changes (trims):
  - Description starts with "Use when". Upstream led with "Test-driven development."
  - Removed the `GLOSSARY.md` read. ADRs stay.
  - Removed the instruction to call the Skill tool with `codebase-design`. The seam question goes to the user. That skill is not adopted.
  - Removed "see the `code-review` skill". Refactoring still waits until the slice is green.
  - Kept `tests.md` and `mocking.md` verbatim. They are short and do not mention those names.
  - Dropped `agents/openai.yaml` (packaging for another host).
- Diff: `diff -u <upstream>/skills/engineering/tdd/SKILL.md SKILL.md`.
