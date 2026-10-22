---
name: migration
description: Use when a schema, data shape, API, protocol, config, or dependency change must stay reversible. Keep a forward path and a rollback path. Expand, migrate, verify, then contract. Never contract unless the user asks.
---

# Migration

Map current readers, writers, data shape, compatibility window, and ownership before editing.

- Define forward path and rollback path.
- Preserve existing data; make destructive steps explicit and separately authorized.
- Keep mixed-version operation safe where rollout can overlap.
- Sequence expand, migrate, verify, then contract when applicable.
- Make retries idempotent and partial failure observable.
- Verify old and new paths at required transition stages.

Stop after the requested stage passes. Never contract unless the user asks. Do not perform a later destructive contraction implicitly.

---

Adapted from [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) `skills/migration` at commit `bad48a0e1df55e05e3f52249afa35ecc1909ee76`. Apache License 2.0, Copyright 2026 Julius Brussee. See UPSTREAM.md and NOTICE.
