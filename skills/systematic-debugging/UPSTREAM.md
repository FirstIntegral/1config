# Upstream

- Source: https://github.com/obra/superpowers/tree/2ce8aa15d05bd57213e6f746f953aafb7ded7a8b/skills/systematic-debugging
- Commit: 2ce8aa15d05bd57213e6f746f953aafb7ded7a8b (committed 2026-10-21T21:00:49Z)
- License: MIT, Copyright (c) 2025 Jesse Vincent. Full text: LICENSE.upstream (keep it).
- Local changes (trims):
  - `Use the \`[plugin-prefixed] test-driven-development\` skill for writing proper failing tests` → `Watch it fail for the right reason before writing the fix` (TDD skill not adopted).
  - `[plugin-prefixed] verification-before-completion` → `verification-before-completion` (local name).
  - "your human partner" → "the user" (heading and one line).
  - Dropped files: `CREATION-LOG.md`, `test-academic.md`, `test-pressure-1/2/3.md` (authoring/test artefacts). Kept: `root-cause-tracing.md`, `defense-in-depth.md`, `condition-based-waiting.md`, `condition-based-waiting-example.ts`, `find-polluter.sh`.
  - Took the upstream secret-safe env probe at this pin: the IDENTITY line no longer expands the value, and `printenv` replaces `env | grep`.
  - Re-checked the rest of the skill at this pin. No other upstream hunk in the files we keep.
- Diff: `diff -u <upstream>/skills/systematic-debugging/SKILL.md SKILL.md`.
