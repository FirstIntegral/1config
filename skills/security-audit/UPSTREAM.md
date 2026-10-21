# Upstream

- Source: https://github.com/cloudflare/security-audit-skill/tree/c1c8a8c1471069fb0e188eeaff69b8e8db6564a8/skills/security-audit
- Commit: c1c8a8c1471069fb0e188eeaff69b8e8db6564a8 (committed 2026-09-14T19:28:54Z)
- License: MIT, Copyright (c) 2025-2026 Cloudflare, Inc. Full text: LICENSE.upstream (keep it).
- Local changes (trims):
  - Description fires only on an explicit security audit, pen-test, or vulnerability hunt. Ordinary security questions stay on the other review skills.
  - Added `## 1config constraints`. That section owns the profile and the budget: full audit waits for a named agent budget, the proposal is profile `quick` with a cap of 40, and `standard` or `deep` waits for a yes that names the profile. A null budget does not start hunters.
  - Parent maps to this tool's subagents. A tool with no subagents stops the full audit.
  - Output stays `~/security-audit-skill/<repo-name>/run-<N>`. Auditing `~/.agents` waits for a separate yes.
  - Target-controlled execution stays off. Vigil is not the OS sandbox this skill requires, so those leads stay `needs_validation`.
  - `run-metadata.json` budget field points at 1config constraints. The profile paragraph no longer defaults to `standard`. The cost-budget sentence no longer lets the parent invent a budget.
  - MIT credit footer added so `verify.sh` can read the copyright from this file.
- Diff: `diff -u <upstream>/skills/security-audit/SKILL.md SKILL.md`.
