# Upstream

- Source: https://github.com/obra/superpowers/tree/8ca22dba9a94f28898bbce59f2537ff4d87c747d/skills/systematic-debugging
- Commit: 8ca22dba9a94f28898bbce59f2537ff4d87c747d (committed 2026-09-25T11:06:27-07:00)
- License: MIT, Copyright (c) 2025 Jesse Vincent. Full text: LICENSE.upstream (keep it).
- Local changes (trims):
  - `Use the \`[plugin-prefixed] test-driven-development\` skill for writing proper failing tests` → `Watch it fail for the right reason before writing the fix` (TDD skill not adopted).
  - `[plugin-prefixed] verification-before-completion` → `verification-before-completion` (local name).
  - "your human partner" → "the user" (heading and one line).
  - Dropped files: `CREATION-LOG.md`, `test-academic.md`, `test-pressure-1/2/3.md` (authoring/test artefacts). Kept: `root-cause-tracing.md`, `defense-in-depth.md`, `condition-based-waiting.md`, `condition-based-waiting-example.ts`, `find-polluter.sh`.
- Diff: `diff -u <upstream>/skills/systematic-debugging/SKILL.md SKILL.md`.
