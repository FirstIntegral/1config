# Upstream

- Source: https://github.com/JuliusBrussee/caveman/tree/bad48a0e1df55e05e3f52249afa35ecc1909ee76/skills/migration
- Commit: bad48a0e1df55e05e3f52249afa35ecc1909ee76 (committed 2026-10-17T21:08:52Z)
- License: Apache-2.0, Copyright 2026 Julius Brussee. Full text: LICENSE.upstream (keep it).
- Local changes (trims):
  - Description starts with "Use when" and names the reversible sequence, including never contract unless the user asks. Upstream said "Use for schema..." and did not lead with "Use when".
  - Last line states the stop rule in those words. Upstream said "do not perform later destructive contraction implicitly."
  - `NOTICE` is the upstream NOTICE, copied verbatim. Only the Caveman copyright line pertains to this skill. The other notices name engine, font, browse, and CLI components this directory does not contain.
  - Dropped `agents/openai.yaml` (packaging for another host).
- Diff: `diff -u <upstream>/skills/migration/SKILL.md SKILL.md`.
