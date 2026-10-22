# Upstream

- Source: https://github.com/Master-cai/Research-Paper-Writing-Skills/tree/77e7c2c1ba06f7d71844873147665437a03aac1b/research-paper-writing
- Commit: 77e7c2c1ba06f7d71844873147665437a03aac1b (committed 2026-06-23T02:28:54Z)
- License: MIT, Copyright (c) 2026 Master-cai. Full text: LICENSE.upstream (keep it).
- Local changes (trims):
  - Description loads only inside `writepaper_project`, `docs/paper/`, or `paper-template/`, and only for prose and claim checks. Digit-refuse keeps the numbers.
  - Added `## 1config`. No bibliography, no invented measurements, and this skill does not replace the `writepaper_project` section list.
  - Each kept section guide starts with that same override. The guide text under the note is upstream.
  - Dropped `references/examples/` (annotated excerpts of published papers, including Neural Body and Instant-NGP, plus a citation-link index).
  - Dropped `references/does-my-writing-flow-source.md` (a PDF extract of someone else's flow handout). The paragraph check in `SKILL.md` stays.
  - Dropped `agents/openai.yaml` (packaging for another host).
  - Claim step and the paper-review close say a missing measurement is `\TODO{measure: ...}`, not a new number.
- Diff: `diff -u <upstream>/research-paper-writing/SKILL.md SKILL.md`.
