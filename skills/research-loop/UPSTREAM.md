# Upstream

- Source: https://github.com/alphaXiv/OpenResearch/tree/a92fd471aba91e9bdd14a88e2322ec42f9dfdbdb (`SKILL.md`, `agent-skills/orx-experiment-tree`, `orx-create`, `orx-results`, `orx-logs`)
- Commit: a92fd471aba91e9bdd14a88e2322ec42f9dfdbdb (committed 2026-10-31T00:56:22Z), release v0.2.23
- License: MIT, Copyright (c) 2026 alphaXiv. Full text: LICENSE.upstream (keep it).
- Local changes (trims):
  - Not vendored. Upstream's `SKILL.md` is a shim that runs `orx skill`. Here, the four cardinal rules and the command shapes are restated in 1config's own words, and the bundled manual stays in the binary (`orx skill`).
  - Added: the pinned install (`orx-install.sh`), the pre-registration gate and ledger (`orx-ledger.sh`), and the Never list. These are local, not upstream. `orx-install-test.sh` is their fixture gate.
  - Dropped: `orx install-skills`, `orx feedback`, managed compute, and Overleaf.
  - Credit footer appended.
- Pin bump: `bash orx-install.sh pin-info <version>`, then update `PIN_VERSION` and the two `PIN_SHA256_*` values in `orx-install.sh`. Re-read `src/telemetry.rs` (env and consent behaviour) and the `local_experiments` and `runs` columns in `src/store.rs`, which `orx-ledger.sh` checks.
