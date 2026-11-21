# Changing 1config itself

Read when: the user says `global_brain_update`, or you are about to edit any file under `~/.agents/`.

### After any edit under `~/.agents/` (HARD RULE)

Hooks, guards, SETUP, template, and this file are one system. Changing one file can leave installed copies / docs / cron stale.

**Same turn after any change under `~/.agents/`:**

```bash
bash ~/.agents/setup.sh                 # re-copy hooks → cron-jobs, fix symlinks/config, refresh inventory
bash ~/.agents/sync.sh -m "<subject>"   # setup + verify + signed commit + push to the origin in BRAIN_REMOTE
```

Do not end a turn that edited `~/.agents/**` without running **both**. `verify.sh` alone is check-only (does not install); `sync.sh` re-runs `setup.sh` itself and refuses to commit if verify fails. It fetches first: a brain that is behind is fast-forwarded over signed commits only, and a diverged one stops before anything is installed. It also refuses to commit a token-shaped string (`hooks/secret-scan.sh`; a fixture line carries `gitleaks:allow`). The brain is a git repo — a local-only edit is an unfinished edit (see `global_brain_update`, below).

CI (`.github/workflows/ci.yml`) runs `verify.sh --repo`, ShellCheck at error severity, and the skill fixtures on every pull request and every push to `main`. `--repo` is what a clone carries. A new check that reads this machine's state goes behind `machine` in `verify.sh`. A fixture does not touch the network or this machine's git config.

Same-turn also means **the figure**: if the edit alters what `setup-infographic.svg` depicts (components, flows, toolchain, repo list), regenerate `setup-infographic.svg` in the same turn, before `sync.sh`. The figure is part of the spec surface; a brain change that leaves it stale is unfinished. (This repeats `global_brain_update` step 2b on purpose — it applies to every brain edit, trigger typed or not.)

Same-turn also means **the welcome walkthrough (`hooks/welcome.js`)**: when a brain change adds, retires, or changes a user-facing trigger, rule, hook, or workflow, the AI must decide in the same turn whether it belongs in the 8-page walkthrough (`hooks/welcome.js`) and update the relevant page and snippet box if so (internal refactors, minor bugfixes, or test-only tweaks stay out so the 8 pages remain high-signal).

## `global_brain_update` trigger

When the user says **`global_brain_update <what to change>`**, the target is **the brain itself** — `~/.agents/` — not the current project. The trailing text is the change to make.

1. **Read before writing.** `AGENTS.md` (canonical rules) and `SETUP.md` (spec), plus whatever the request touches: `setup.sh`, `verify.sh`, `permissions.json`, `hooks/`, `updater/`, `project-template/`, `paper-template/`, `boot-dashboard/`. Never patch the brain blind — half of it installs the other half.
2. **Put the change in its canonical home**, never in a tool-local path: hard rules, and one row per trigger → `AGENTS.md` · a trigger's body, and the description of a script or a screen → `playbooks/<name>.md` (line 1 `# Title`, then `Read when: <condition>`, and a row in the table in `AGENTS.md`) · spec / how it installs → `SETUP.md` · install logic → `setup.sh` · checks → `verify.sh` · permissions → `permissions.json` · scripts → `hooks/` (or `updater/`) · scaffolds → `project-template/` / `paper-template/` · on-demand process skills → `skills/<name>/` + one `!skills/<name>/` line in `.gitignore`; adopted ones keep `UPSTREAM.md` (pinned SHA, trims) and `LICENSE.upstream`.
2b. **If the change alters what `setup-infographic.svg` depicts** (components, flows, toolchain), regenerate the figure in the same turn — it is part of the spec surface (verify checks it exists and stays referenced).
2c. **Evaluate `hooks/welcome.js` (AI judgment):** when new features, triggers, hooks, or policies arrive (or old ones change), decide in the same turn whether they belong in the 8-page welcome walkthrough (`hooks/welcome.js`). Update its pages/snippets when a user-facing capability or architectural rule changes; skip minor internal plumbing so the walkthrough stays concise and fits strictly inside its box borders (`node ~/.agents/hooks/welcome.js --self-test`).
3. **Tool parity applies** (see that HARD RULE): land it for Claude Code + Grok + OpenCode + Cursor Code, install it in `setup.sh`, check it in `verify.sh`. A brain change with no verify check is not done.
4. `bash ~/.agents/setup.sh` → must end `== PASS (warnings=0) ==`. Fix anything it reports before moving on.
5. `bash ~/.agents/sync.sh -m "<commit subject>"` → re-runs setup+verify, signed commit, push to the origin listed in `BRAIN_REMOTE` (`main`).
6. **Report:** what changed, which files, verify result, pushed commit hash.

**Standing rule — the brain repo is the source of truth.** ANY change under `~/.agents/**`, whether or not the trigger was typed, ends the same turn with `setup.sh` **and** `sync.sh`. Never leave the brain dirty locally, never push a brain that fails verify, never bypass signing, no AI attribution in the commit (see the Git rules in `AGENTS.md`). `backups/` is gitignored runtime residue and stays out of the repo.

## Per-tool wiring

Known per-tool wiring (keep in sync): global rules → symlinks (§3 of SETUP.md); project `AGENTS.md` → native in Grok, OpenCode, Claude Code 2.1.277+, and Cursor Code (project root and subdirectories); permissions → `permissions.json` fan-out (`~/.agents/playbooks/permissions.md`); skills → `~/.agents/skills` (Grok, OpenCode native; Claude per-skill symlink, setup `1b`). Cursor Code's global mechanism is the generated user rule `~/.cursor/rules/1config.mdc` (alwaysApply) plus the `~/.cursor/AGENTS.md` link; its command autonomy is per-invocation flags (`--force` / `--yolo` / `--sandbox`), so permissions.json does not fan out to it, and tracked skills are not linked into Cursor — both recorded in SETUP.md §4.

## Install and pull

Fresh machine (Omarchy or Ubuntu): clone your fork to `~/.agents/`, set commit signing, and run `bash ~/.agents/setup.sh` — recreates symlinks, tool configs, and the cron guards (idempotent). It stops before any write when signing, origin, or HEAD is not ready; `--preflight` runs only that check. A new fork runs `bash ~/.agents/bin/1config fork-init --yes` once, before setup. Existing box: `bash ~/.agents/hooks/brain-sync.sh && bash ~/.agents/setup.sh`. A bare `git pull` skips the signature gate. `bash ~/.agents/setup.sh --dry-run` prints the config diffs and changes nothing. `bash ~/.agents/uninstall.sh` prints a removal plan; `--yes` removes, and that is a red line. Human report + opinionated defaults: `README.md`. Full spec: `SETUP.md`. Threat model: `SECURITY.md`. Runtime archives land under `~/.agents/backups/` only when needed — do not treat that folder as source of truth.
