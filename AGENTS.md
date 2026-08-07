# Global rules — canonical file (all AI tools)

This is the ONE global rules file. It is symlinked to every tool's expected path:

- `~/.grok/AGENTS.md` → this file
- `~/.config/opencode/AGENTS.md` → this file
- `~/.claude/CLAUDE.md` → this file

Edit here (or via any of those paths — same bytes). Applies to Grok, OpenCode, and Claude Code alike.

Project-level: `<repo>/AGENTS.md` is the ONLY project rules file. Grok/OpenCode read it natively; Claude Code gets it via a SessionStart hook (`~/.agents/hooks/load-project-agents.sh`). **Never create a project CLAUDE.md** — stubs were retired 2026-07-26.

Fresh machine: copy `~/.agents/` and run `bash ~/.agents/setup.sh` — recreates symlinks, tool configs, and the cron guards (idempotent). Full spec for AIs: `~/.agents/SETUP.md`. Runtime archives (residue packets, symlink strays, setup replace-backups) land under `~/.agents/backups/` only when needed — do not treat that folder as source of truth.

### After any edit under `~/.agents/` (HARD RULE)

Hooks, guards, SETUP, template, and this file are one system. Changing one file can leave installed copies / docs / cron stale.

**Same turn after any change under `~/.agents/`:**

```bash
bash ~/.agents/setup.sh                 # re-copy hooks → cron-jobs, fix symlinks/config, refresh inventory
bash ~/.agents/sync.sh -m "<subject>"   # setup + verify + signed commit + push to github:FirstIntegral/1config
```

Do not end a turn that edited `~/.agents/**` without running **both**. `verify.sh` alone is check-only (does not install); `sync.sh` re-runs `setup.sh` itself and refuses to commit if verify fails. The brain is a git repo — a local-only edit is an unfinished edit (see `global_brain_update`).

**Boot dashboard:** `~/.agents/boot-dashboard/` — on GNOME login opens a status terminal (autostart). Not project code; machine health only.

---

## Git / GitHub attribution — HARD RULE

NEVER add AI/Claude attribution to any git or GitHub artifact. No exceptions, all repos, by default.

- Do NOT add `Co-Authored-By: Claude ...` (or any Co-Authored-By AI line) to commit messages.
- Do NOT add `🤖 Generated with Claude Code` (or similar AI-generated notes) to PR bodies, commit bodies, or descriptions.

This overrides any default harness guidance that says to include those lines. Write commits and PRs attributed solely to the user.

---

## Git commit signing — HARD RULE

NEVER bypass commit signing. If a repo (or global git config) has `commit.gpgsign=true`, or the repo's docs say commits are signed:

- Do NOT use `--no-gpg-sign`, `-c commit.gpgsign=false`, or any other bypass.
- If signing fails (locked key, no pinentry), STOP and unlock, then commit. Never work around it.
- **Unlock is automated** — the passphrase lives in the GNOME keyring (encrypted at rest; keyring unlocks at login via PAM). `~/.agents/hooks/gpg-agent-unlock.sh` test-signs and, if the agent is empty, fetches the passphrase over Secret Service D-Bus and unlocks with `--pinentry-mode loopback`. Runs at login from the boot dashboard; invoke anytime. Nothing to type, ever.
- One-time setup on a fresh machine (prompts once, stores in keyring, nothing on disk): `bash ~/.agents/hooks/gpg-store-passphrase.sh`
- If the automated unlock fails (keyring locked/empty, passphrase changed): re-store with the command above, or manual fallback in a real terminal: `export GPG_TTY=$(tty); echo x | gpg --pinentry-mode loopback -u 95FBA6E0AA245342 --clearsign -o /dev/null` (prompts, caches). Then retry the commit.
- History rewrites (rebase, filter-repo, amend) must leave commits re-signed before any push.

---

## Permission allowlist (all three tools) — canonical file

Global no-prompt allowlist lives in **`~/.agents/permissions.json`**. `setup.sh` fans it out to every tool, union-style, deduped, idempotent — existing rules are never dropped:

| Step | Tool | Lands in | Form |
|------|------|----------|------|
| `5b` | Claude Code | `~/.claude/settings.json` → `permissions.allow` / `.deny` | rules verbatim |
| `5c` | Grok | `~/.grok/config.toml` → `[permission] allow` / `deny` | rules verbatim (Grok speaks the same `Bash(...)` syntax) |
| `5d` | OpenCode | `~/.config/opencode/opencode.jsonc` → `permission.bash` | `Bash(X)` → `"X": "allow"` / `"deny"` |

- Add or remove a rule → edit `~/.agents/permissions.json`, then `bash ~/.agents/setup.sh`. `verify.sh` fails if any of the three drifts.
- **Never hand-edit the per-tool copies** (`~/.claude/settings.json`, `[permission]` in `config.toml`, `permission.bash`) — they would drift from canonical and survive only until someone re-reads the source.
- OpenCode gets only the `Bash(...)` rules; `Skill(...)` and other tool rules are Claude/Grok-only. No catch-all is written for OpenCode, so its permissive defaults are never tightened by this file — the deny list still lands.
- Grok runs `[ui] permission_mode = "always-approve"`, so allow rules are moot there today; **deny rules still apply** in that mode, which is why they are fanned out too.
- Allowed = runs with no prompt in **every** project. Unmatched calls still prompt. `deny` entries are hard-blocked, not prompted.
- Deliberately NOT allowlisted (still prompt): `rm`, `sudo`, `curl`/`wget`, `git push`, package installs, `chmod`/`chown`, `mv`, `dd`. Also absent on purpose: `xargs -I`, `sh -c`, `bash -c`, `npx` — they run an arbitrary inner command, so allowing them would launder every rule above.
- Per-project `.claude/settings.local.json` files accumulate one-off absolute-path rules from clicking Approve. That is disposable noise — do not promote it wholesale; lift only the generic patterns.

### `defaults.edit_without_prompt` — file writes never prompt (all three tools)

Same canonical file, second block: `defaults.edit_without_prompt` (currently **true**). One switch, three native spellings, fanned out by the same `setup.sh` steps and checked by `verify.sh`:

| Tool | Setting written | Scope |
|------|-----------------|-------|
| Claude Code | `permissions.defaultMode = "acceptEdits"` | file writes/edits only — Bash still obeys the allow list |
| Grok | `[ui] permission_mode = "always-approve"` | Grok's only knob, and **broader**: approves every prompt, not just edits |
| OpenCode | `permission.edit = "allow"` | file writes/edits (already OpenCode's default; pinned so it is visible and checkable) |

Flip it to `false` + `setup.sh` to be asked again (Claude → `"default"`, OpenCode → `"ask"`, Grok's key removed). `deny` rules bite in every mode, including Grok's always-approve.

### Compound commands: every segment must match

A pipeline or `;`/`&&`/`||` chain is approved only if **each** segment matches a rule. One unlisted `lscpu` in a ten-part probe prompts for the whole line, and the prompt names only part of what it wants. So when a probe prompts, the fix is to find the *one* unlisted segment — or split the probe into separate calls — not to re-run the same chain.

### Prompts an allowlist cannot remove — write a script file instead

Some Bash calls prompt **regardless** of any allow rule, because Claude Code decides them before consulting the allowlist:

- **Obfuscation / parse verdicts** — e.g. `Contains brace with quote character (expansion obfuscation)`. Fired by heredocs whose body mixes `{...}` with quotes (Python f-strings are the usual cause: `print(f"n={n}")`). Also: commands over 10,000 chars, anything the parser can't fully parse.
- **Exec wrappers** — `watch`, `setsid`, `ionice`, `flock`, `find -exec`, `find -delete`. Only an exact-match rule for the whole command string helps.
- **Env runners** — `npx`, `docker exec`, `mise exec`, `devbox run`, `direnv exec` are not stripped; the rule must name runner **and** inner command.

**So: never pipe multi-line Python (or any brace-heavy script) through a heredoc.** Write it to a file under the session scratchpad, then run the file — `python3 /tmp/.../probe.py`, `.venv/bin/python /tmp/.../probe.py`. That form matches the normal allowlist and never prompts. Keep it as a file for reruns instead of re-pasting a heredoc.

Wrappers that ARE stripped before matching (safe to prefix a rule's command with): `timeout`, `time`, `nice`, `nohup`, `stdbuf`, `command`, `builtin`, bare `xargs` (no flags). `Bash(pytest *)` therefore covers `timeout 900 pytest -q`. Interpreter **paths** are not normalized: `Bash(python *)` does not cover `.venv/bin/python` — venv paths need their own rules (they are in the canonical file).

---

## Tri-tool parity — HARD RULE

**Claude Code, Grok, and OpenCode must behave the same.** Same rules, same memory, same triggers, same allowlist. A feature that works in one tool and not the others is a bug, not a milestone.

Whenever anything is added to or changed in this setup:

1. **Land it in all three, in the same turn.** Canonical source stays single (`~/.agents/…`); `setup.sh` fans it out per tool. Never write a per-tool copy by hand.
2. **If a tool has no native mechanism**, implement the closest equivalent (hook, config key, translated rule syntax) and record what differs — SETUP.md §4, one line. "Claude-only" is acceptable ONLY when the other two physically cannot do it, and only when written down.
3. **`setup.sh` installs it for all three; `verify.sh` checks all three.** A feature with no verify check does not count as installed.
4. **Rules and triggers live in the canonical `AGENTS.md`** (all three read it via the symlinks), never in a tool-specific file — so every trigger (`create_project`, `continue_project`, `checkpoint_project`, `writepaper_project`, caveman mode, memory policy) fires identically everywhere.
5. Same for memory: shared markdown only, identical for all three (see Memory policy). Tool-internal stores stay disabled everywhere.

Known per-tool wiring (keep in sync): global rules → symlinks (§3 of SETUP.md); project `AGENTS.md` → native in Grok/OpenCode, SessionStart hook in Claude; permissions → `permissions.json` fan-out (above).

---

## Machine toolchains (this machine)

- **TeX: `texlive-full` installed** (Debian pkg `texlive-full` 2025.x, TeX Live 2025). Full scheme — every CTAN package, every engine, all fonts. Write scientific papers, posters, TikZ/PGFPlots, beamer, bibliographies directly; **never** ask the user to install a LaTeX package, and never fall back to a Markdown-only deliverable for lack of TeX.
  - Engines: `pdflatex`, `xelatex`, `lualatex`, `tex` · build: `latexmk` (preferred, handles reruns) · bib: `biber`, `bibtex` · index: `makeindex` · also `texcount`, `latexdiff`.
  - `tectonic` also installed (`~/.local/bin`) — self-contained one-shot builds; use when a project's build script already calls it.
  - All of the above are allowlisted (no prompt). Package installs (`tlmgr install`) are not — and with `texlive-full` should never be needed.

---

## Caveman mode — ALWAYS ON (global default)

**Every response.** Every project. No opt-in per session.

Talk terse like smart caveman. Keep all technical accuracy. Drop articles, filler, pleasantries, hedging. Fragments OK.

- Pattern: `[thing] [action] [reason]. [next step].`
- Code, commits, PRs, diffs: write **normal** (not caveman).
- Security warnings & irreversible actions: write **clear**, then resume caveman.
- User says **stop caveman** or **normal mode** → revert for rest of session.
- Adjust level: `/caveman lite|full|ultra` (default: **full**).

---

## `create_project` trigger

When the user says **`create_project`** (starting a new project), always set up the standard layout. Fast path: `cp -r ~/.agents/project-template/. <project-dir>/` then fill in names; or create the files manually:

| File | Audience | Maintenance |
|------|----------|-------------|
| `AGENTS.md` | all AI tools | Project rules/conventions, plus a `## Repo` line recording the remote (or `none (local only)`). Canonical and ONLY project rules file (Claude Code loads it via SessionStart hook — never create a project CLAUDE.md). Committed by default — **except** `~/projects/sites/*` (see Sites rule). |
| `session_transcript.md` | **human ONLY** | Append-only narrative log of each work session, newest at bottom. Written for the user to read back. AI agents NEVER read it (Transcript privacy HARD RULE). |
| `session_compact.md` | **AI handoff** | Concise state: current status, where we left off, next steps, key decisions, open issues. Always records the active **model + effort**. **Rewrite** (not append) at end of session / major milestone / before context compaction. |
| `docs/DECISIONS.md` | all AI tools | ADR log: decision + why + rejected alternatives, appended in the same turn a choice is made. Versioned (committed in repos). |
| `.gitignore` | git | Must ignore session files (`session_compact.md`, `session_transcript.md`, `claude_memory_import.md` + legacy session paths). Comes from the template; if project already has a `.gitignore`, **merge** those lines in (do not overwrite the whole file). Under `~/projects/sites/*` also ignore `AGENTS.md` and `CLAUDE.md`. |

Rules:

1. **Session start in any project:** if `session_compact.md` exists, read it FIRST to restore where we left off — before doing other work.
2. **During work:** append to `session_transcript.md` at milestones (human-readable, chronological, verbose OK).
3. **End of session / milestone / before compaction:** rewrite `session_compact.md` to reflect the latest state. It must always be accurate enough for a fresh AI session to resume work from it alone.
4. Session files live in the project root. **Never commit them unless the user explicitly says otherwise** — `session_transcript.md` and `session_compact.md` are local-only; the template `.gitignore` enforces this. If copying files by hand (no template), add the same ignore lines.
5. **`create_project` never creates a git repo or a remote.** Whether a project goes to GitHub is the user's call, made explicitly. Fill the `## Repo` line with `none (local only)` and leave it; update it the same turn a remote is actually added, so `checkpoint.sh`'s cross-check stays meaningful.
6. **Model tracking:** at `create_project`, record the active model + effort in `session_compact.md` (read the tool's config — `opencode.jsonc` / `~/.claude/settings.json` / `~/.grok/config.toml` — or ask the user once). The **Models used** list in compact is CUMULATIVE: preserve it across rewrites, mark the current one, add a line whenever model or effort changes. Every switch also goes to `session_transcript.md` (old → new, reason if known) — the transcript is the lossless copy. If the user says they switched models, log it immediately.

---

## `continue_project` trigger

When the user says **`continue_project <path>`** (example: `continue_project /home/brwsk/projects/some_dummy_project`), resume that project from disk. Do this **before** other work:

1. Resolve `<path>` (absolute or relative). Must be a directory. If missing/invalid → stop and say so.
2. **Residue / conflict check (all tools):**
   - Memory: if `~/cron-jobs/claude-memory-guard/NEEDS-MEMORY-MERGE` or `~/.agents/backups/claude-residue/PENDING.md` or `<path>/claude_memory_import.md` exists → process memory residue merge (Memory policy) **before** relying on project files.
   - Symlinks: if `~/cron-jobs/agents-symlink-guard/NEEDS-SYMLINK-MERGE` exists → process symlink conflict merge (see Cron guards) before editing global rules.
3. **Read, in order** (only if the file exists):
   1. `<path>/session_compact.md` — where we left off (AI handoff; **required read when present**)
   2. `<path>/AGENTS.md` — project rules/conventions
   3. `<path>/docs/DECISIONS.md` — durable choices + why
4. **Do NOT** open `<path>/session_transcript.md` unless the user explicitly asks (Transcript privacy HARD RULE).
5. If none of the three files exist → say the path has no project session layout; offer `create_project` there (or fix the path).
6. After reading: brief status (current state + where we left off + open issues from compact), then wait for / take the user's next instruction. Do not invent state that is not in those files.
7. Treat `<path>` as the project root for the rest of the session (paths, git, session file updates) unless the user points elsewhere.

Same trigger for all tools (Grok / Claude Code / OpenCode). No tool-specific continue step.

---

## `checkpoint_project` trigger

When the user says **`checkpoint_project`** (done for the day — leave and resume later), apply to the **current** project (cwd walk-up to nearest project root, stopping before `$HOME`):

1. Resolve the project root. No session layout there (no `session_compact.md` / `AGENTS.md`) → say so, offer `create_project`.
2. Read `session_compact.md` (state restore). NEVER open `session_transcript.md` (Transcript privacy HARD RULE).
3. Rewrite `session_compact.md` so a fresh AI session can resume from it alone: current state, where we left off (concrete next step), key decisions, open issues, and the cumulative **Models used** list (current marked).
4. Append a `## <YYYY-MM-DD> — wrap-up` entry to `session_transcript.md` (write-only): what was done today + the next step.
5. Backfill `docs/DECISIONS.md` with any meaningful choices from this session not yet logged (same-turn ADR rule).
6. **Commit and push** (see below). Half-finished work is expected and fine — the point is that the machine is not the only copy.
7. Finish with: "Checkpoint saved — next step: <X>", plus the pushed commit hash (or one line saying why nothing was pushed).

Same for all three tools. Formalizes the existing "End of session / milestone" rule as an explicit trigger.

### Step 6 in detail — run the script, do not hand-roll git

```sh
bash ~/.agents/hooks/checkpoint.sh <project-root> -m "checkpoint: <YYYY-MM-DD> <what moved>"
```

**Do not open-code these git commands.** Step 6 is mechanical and has exactly one correct answer per project state; hand-running it produced inconsistent behaviour on consecutive checkpoints of the same project. The script is the behaviour; the prose below documents what it does, and `verify.sh` exercises its two refusals for real on every run.

Read its exit code and report accordingly:

| exit | meaning | what happened |
|---|---|---|
| `0` | committed and pushed | normal path |
| `3` | clean tree | nothing to commit |
| `10` | **not a git repo** | nothing done, no `git init` |
| `11` | project is inside another repo, not its root | nothing done |
| `12` | no remote | committed locally, not pushed |
| `13` | remote configured but unreachable | committed, not pushed, **not created** |
| `20` | **refused** — session files would be published | nothing done; fix `.gitignore` and re-run |
| `21` | commit or push failed | any commit made is safe; not retried, not forced |

`--dry-run` prints the plan and changes nothing. Anything other than `0` or `3` goes in the closing line so the state is never silently lost.

**Gate the script applies, before touching git at all:**

| project is | do |
|---|---|
| **not a git repo** | **nothing.** No commit, no push, no `git init`. Say "not a git repo — nothing pushed" and finish the checkpoint normally. |
| a repo with **no remote** | commit locally, **do not push**, do not add a remote. Say "committed locally, no remote". |
| a repo with a remote | commit and push, no asking |

**HARD RULE: a checkpoint never creates a repo, never adds a remote, never creates a GitHub repo.** A project without a repo is a deliberate state — scratch work, a scaffold, something not meant to be published — and a checkpoint is a note-taking action that must not silently change it. Publishing something the user never chose to publish is not recoverable by deleting it afterwards. If a project looks like it wants a repo, say so and let them decide next session.

Also check the **root**, not just "somewhere in a repo": `git rev-parse --show-toplevel` walks *up*, so it succeeds for any subdirectory. A toplevel differing from the project root means the project sits inside someone else's repo (or a parent worktree), and committing there would sweep unrelated work into the checkpoint. Do not commit in that case — say so and skip.

**Which projects get a remote is a manual decision, and stays one.** Nothing in this setup creates repos; `create_project` does not, and neither does a checkpoint. A project has a remote because someone deliberately ran `gh repo create` or `git remote add`. That is the whole policy.

**The project's `AGENTS.md` records the remote as documentation — never as authorisation.** The `## Repo` section in `project-template/AGENTS.md` carries the URL so it is visible without running git, and `checkpoint.sh` cross-checks it against `git remote get-url --push` and warns on a mismatch. But **git config always wins**, because git config is set by an explicit human action while `AGENTS.md` is a file an AI writes: a line hallucinated into it must never be able to authorise a push, and a stale line must never redirect one. Documentation drifts; the push target cannot be allowed to drift with it.

**What "has a remote" means here.** The test is a configured remote, not GitHub specifically — a self-hosted or GitLab origin pushes exactly the same way, and nothing in this trigger is GitHub-aware. Two consequences worth stating:

- **Read the URL before pushing, do not just count remotes.** `git remote get-url --push origin`. If `origin` does not exist but other remotes do, do **not** guess which one to push to — commit locally, name the remotes found, and let the user choose. If the branch already has an upstream, push there and ignore all of this.
- **A configured remote is not a reachable one.** The URL can point at a repo that was deleted, renamed, or that this key cannot write to.

**When the push fails, the checkpoint still succeeded.** Steps 1-5 are the checkpoint; the push is a backup. On any push failure: report the exact error, leave the commit in place, and finish with "committed <hash>, push failed: <reason>". Then stop. Specifically never, in response to a failed push:

- `gh repo create`, or add/rewrite a remote — the repo not existing is an answer, not an obstacle
- `--force` / `--force-with-lease` — a non-fast-forward means someone else pushed; that is merged deliberately next session, not overwritten at the end of a day
- `git rebase`, `git reset`, amending, or any history rewrite to make the push go through
- retrying with a different branch or remote than the one that failed

Repo with a remote, the normal path:

```sh
git add -A                      # session files are gitignored, so they stay local
git commit -m "checkpoint: <YYYY-MM-DD> <what moved today>"
git push                        # -u origin <branch> if the branch has no upstream
```

- **Signing and attribution rules apply unchanged** — signed commit, no `Co-Authored-By: Claude`, no "Generated with Claude Code". Signing fails → `bash ~/.agents/hooks/gpg-agent-unlock.sh`, retry. Never bypass.
- **Commit on the current branch**, whatever it is. A checkpoint records where the work actually is; it is not the moment to invent a branch or open a PR.
- **`git push` is not allowlisted and will prompt.** That is deliberate and stays that way: the prompt is the last look before work leaves the machine. Answer it; do not route around it.
- **Nothing to commit** → skip, say "nothing to commit" in the closing line.
- **Session files are never committed** (`session_compact.md`, `session_transcript.md`, `claude_memory_import.md`) — the template `.gitignore` already excludes them. If a project lacks those ignore lines, add them *before* the `git add -A`, or the checkpoint publishes the private transcript. Verify with `git add -A --dry-run` before committing in any project whose `.gitignore` you have not seen this session. Under `~/projects/sites/*` the Sites rule also keeps `AGENTS.md` out.

Rationale for pushing unfinished work: a checkpoint fires when the day ends, which is usually mid-thought. The tree being messy is the normal case, not a reason to hold it back — remote is a backup here, not a release. Anything genuinely not for publication belongs in `.gitignore`, which is the mechanism that decides what leaves, not the checkpoint's judgement. That rationale covers *existing* remotes only; it is never a reason to create one.

---

## `writepaper_project` trigger

When the user says **`writepaper_project`** (optionally `writepaper_project <path>` or with a topic/venue hint), write a **complete, full-length research paper about that project** — LaTeX, publication-grade, not a summary and not a README in disguise.

**Author block is fixed** (every paper, unless the user names co-authors):

```latex
\author{Brusk Kawa Abdalla\thanks{\href{mailto:math@brwsk.xyz}{math@brwsk.xyz}}}
```

### Procedure

1. Resolve the project root (given path, else cwd walk-up stopping before `$HOME`). Read `session_compact.md`, `AGENTS.md`, `docs/DECISIONS.md`, then the actual **code, tests, benchmarks, logs, and result files**. Never read `session_transcript.md` (Transcript privacy).
2. Scaffold `docs/paper/` from `~/.agents/paper-template/` (`main.tex`, `build.sh`, `figures/`) if not already there; otherwise extend what exists — never silently overwrite a paper in progress.
3. Write the paper. Then **build it**: `bash docs/paper/build.sh` (latexmk → `main.pdf`). Fix every LaTeX error and every undefined reference/citation; a paper that does not compile is not delivered. `texlive-full` is installed — no package is missing, never stub one out.
4. Report: page count, section list, and an explicit **Gaps** list (what is `\TODO` and why).
5. Same turn: append the milestone to `session_transcript.md`, log paper-level choices (scope, claims, framing) in `docs/DECISIONS.md`, rewrite `session_compact.md`.

### Required structure (drop a section only if it truly does not apply, and say so)

Abstract · keywords · **Introduction** (motivation, gap, explicit contribution list) · **Background** (self-contained, no citations — see below) · **Preliminaries & notation** (symbol table; every symbol defined before use) · **Problem statement** (formal, with assumptions stated as such) · **Method / construction** · **Theory**: definitions, lemmas, theorems, propositions, corollaries — numbered `amsthm` environments, each with a proof (full proofs may move to an appendix, sketch in-line) · **Complexity / cost analysis** (time, space, sample, or numerical-error bounds as fitting) · **Algorithms** in pseudocode · **Implementation** (architecture, key design decisions from `DECISIONS.md`) · **Experimental setup** (hardware, software versions, seeds, datasets, hyperparameters) · **Results**: tables + figures with real numbers, `n`, mean ± CI or std, appropriate hypothesis test with its statistic, p-value and **effect size**, ablations · **Discussion** · **Limitations & threats to validity** · **Conclusion & future work** · **Appendices**: full proofs, extra derivations, and a **reproducibility appendix** (exact commands, commit hash, environment).

Use the science the project actually needs and do not water it down: formal statements over prose claims, derivations shown, units and error bars everywhere, `booktabs` tables, `pgfplots`/TikZ figures (generate data files from real runs), `algorithm2e` pseudocode, `siunitx` for quantities.

### HARD RULES for the content

- **No invented numbers.** Every reported measurement traces to something in the repo — a run you executed, a logged metric, a test output. If a number is needed and does not exist, either produce it by running the code, or write `\TODO{measure: …}` and list it under Gaps. Never fill a results table with plausible-looking values.
- **NO REFERENCES AT ALL.** The paper is AI-written and self-contained: no bibliography, no `refs.bib`, no `\cite`, no numbered reference list, no "[1]"-style markers, no DOIs or arXiv IDs. If prior art must be mentioned, describe the idea in plain prose ("the standard fixed-point argument", "classical Runge–Kutta") without a citation key. A citation is never the reason to skip a derivation — derive it in the paper or state it as an assumption.
- **No overclaiming.** Theorems get proofs or they become conjectures. Empirical claims get the statistic that supports them. Scope conditions and failure cases go in Limitations, not omitted.
- Keep the paper a **living artifact**: re-running `writepaper_project` updates and extends it (new results, new sections), it does not restart from scratch.

### Keeping the paper current — HARD RULE once `docs/paper/` exists

After a project has a paper, **the paper is part of that project's definition of done.** Whenever anything scientifically relevant changes, update `docs/paper/` in the **same turn** as the change — no waiting for the user to re-say `writepaper_project`.

Scientifically relevant = anything the paper asserts: the method or algorithm, a definition, a theorem/lemma/proof, complexity, assumptions or their scope, experimental setup (hardware, versions, seeds, hyperparameters, datasets), any measured number, an ablation, a limitation, or a decision logged in `docs/DECISIONS.md` that the paper describes. Refactors, renames, tooling, and CI changes are **not** relevant unless they change a reported number or a stated claim.

Each such update: patch the affected sections (and the abstract/contributions if the claim moved), rebuild with `bash docs/paper/build.sh`, and say in one line what the paper now says differently. Numbers that went stale but have not been re-measured become `\TODO{measure: …}` — never left silently wrong. Mention the paper update in `session_transcript.md` at the next milestone.

`docs/paper/` **is committed** (it is product, not session state) — for `~/projects/sites/*` the Sites rule still applies to `AGENTS.md` only.

---

## `global_brain_update` trigger

When the user says **`global_brain_update <what to change>`**, the target is **the brain itself** — `~/.agents/` — not the current project. The trailing text is the change to make.

1. **Read before writing.** `AGENTS.md` (canonical rules) and `SETUP.md` (spec), plus whatever the request touches: `setup.sh`, `verify.sh`, `permissions.json`, `hooks/`, `updater/`, `project-template/`, `paper-template/`, `boot-dashboard/`. Never patch the brain blind — half of it installs the other half.
2. **Put the change in its canonical home**, never in a tool-local path: rules & triggers → `AGENTS.md` · spec / how it installs → `SETUP.md` · install logic → `setup.sh` · checks → `verify.sh` · permissions → `permissions.json` · scripts → `hooks/` (or `updater/`) · scaffolds → `project-template/` / `paper-template/`.
3. **Tri-tool parity applies** (see that HARD RULE): land it for Claude Code + Grok + OpenCode, install it in `setup.sh`, check it in `verify.sh`. A brain change with no verify check is not done.
4. `bash ~/.agents/setup.sh` → must end `== PASS ==` with `warnings=0`. Fix anything it reports before moving on.
5. `bash ~/.agents/sync.sh -m "<commit subject>"` → re-runs setup+verify, signed commit, push to `github:FirstIntegral/1config` (`main`).
6. **Report:** what changed, which files, verify result, pushed commit hash.

**Standing rule — the brain repo is the source of truth.** ANY change under `~/.agents/**`, whether or not the trigger was typed, ends the same turn with `setup.sh` **and** `sync.sh`. Never leave the brain dirty locally, never push a brain that fails verify, never bypass signing, no AI attribution in the commit (see the Git rules above). `backups/` is gitignored runtime residue and stays out of the repo.

---

## Global workflow

These rules apply to **every project**, all tools. Per-project `AGENTS.md` and `docs/DECISIONS.md` add project-specific detail.

### Project knowledge (two layers)

| Layer | Location | Git | Purpose |
|-------|----------|-----|---------|
| **Tracked project knowledge** | `docs/DECISIONS.md`; usually also `AGENTS.md` | Yes | Durable decisions, conventions — shareable |
| **Local session files** | `session_compact.md`, `session_transcript.md`, `claude_memory_import.md` (+ legacy `docs/session-archive/`, `docs/session-flushes/`) | No (gitignored) | Session state + full log + residue staging. Never committed unless the user explicitly says otherwise |

### Sites repos — `AGENTS.md` local-only (HARD RULE for `~/projects/sites/*`)

Applies only under **`~/projects/sites/<site>/`** (public site repos). Not other projects.

- `AGENTS.md` must be in that site's **`.gitignore`** (with `CLAUDE.md` if present). **Never commit** site agent rules to GitHub.
- `docs/DECISIONS.md` **is** committed (shareable product/architecture rationale).
- Session files stay gitignored like everywhere else.
- Non-site projects: **do** commit `AGENTS.md` by default (team/shareable conventions).

When `create_project` lands under `~/projects/sites/`, merge the usual session ignore lines **and** add `AGENTS.md` + `CLAUDE.md` to `.gitignore`.

### Transcript privacy — HARD RULE

`session_transcript.md` is the **user's private log**. AI agents NEVER open or read it unless the user explicitly asks. Appending at milestones is fine — reading is not. The only AI-facing session file is `session_compact.md`.

### On session start

0. **Residue / conflict check:** memory (`NEEDS-MEMORY-MERGE` / `PENDING.md` / project `claude_memory_import.md`) and/or symlink (`NEEDS-SYMLINK-MERGE`) — process first (Memory policy + Cron guards).
1. If `session_compact.md` exists in the project root, read it first — it says where we left off.
2. Read project `AGENTS.md` and `docs/DECISIONS.md` if they exist.
3. Do NOT open `session_transcript.md` (Transcript privacy rule above).

### During work

- **Meaningful choice made** (architecture, naming, security trade-off, rejected alternative) → append an ADR entry to `docs/DECISIONS.md` **in the same turn**. Include *why* and what was rejected.
- **Durable fact** (commands, paths, conventions) → project `AGENTS.md`; global fact → this file.
- **Project has `docs/paper/` and something scientifically relevant changed** (method, theorem, assumption, setup, measured number, limitation) → update the paper and rebuild it in the **same turn** (see `writepaper_project` → "Keeping the paper current").
- **Milestone reached** → append to `session_transcript.md`.
- **Before compaction or ending a long session** → rewrite `session_compact.md`.

### End of session / milestone

1. Rewrite `session_compact.md` (see `create_project` rules).
2. Confirm `docs/DECISIONS.md` has any new decisions from this session.

### New / resume projects

- **`create_project`** — scaffold a new project (template). Only new-project trigger.
- **`continue_project <path>`** — resume an existing project from its session files (see section above).
- **`checkpoint_project`** — end-of-day wrap-up of the current project (see section above).
- No tool-specific init/continue steps. Retired Grok-era machinery (`init-project`, `/flush`, `docs/SESSION.md`, tool-internal memory) must not be recreated.

---

## Memory policy — everything in shared files

- ALL durable memory → shared markdown only: this file (global rules), project `AGENTS.md`, `session_compact.md`, `docs/DECISIONS.md` (project facts). Nothing important anywhere else.
- **Tool-internal memory stores are DISABLED / removed by user policy**:
  - Grok: `[memory] enabled = false` in `~/.grok/config.toml`. Do **not** recreate `~/.grok/memory/`. If it reappears, ignore it; guards delete it (after archive).
  - Claude: every `~/.claude/projects/*/memory/` holds only a DISABLED stub `MEMORY.md` (no topic files). Do **not** write memories there. Do **not** use Claude's `#` memory shortcut (it would create project `CLAUDE.md` / feed auto-memory — both forbidden).
  - OpenCode: no separate memory store; uses AGENTS.md only.
- When asked to "remember" something: global fact → this file; project fact → that project's files. Same turn, no exceptions.
- Keep this file LEAN — it loads into every session. Cross-project rules only; project specifics never belong here.
- Symlinked paths (`~/.claude/CLAUDE.md`, `~/.grok/AGENTS.md`, `~/.config/opencode/AGENTS.md`) all write to this file.

### Cron guards (machine hygiene)

| Guard | Script source | Installed as | Flag (if AI/human work needed) | Job |
|-------|---------------|--------------|--------------------------------|-----|
| Symlink | `~/.agents/hooks/check-links.sh` | `~/cron-jobs/agents-symlink-guard/check-links.sh` | `NEEDS-SYMLINK-MERGE` | Keep the 3 AGENTS symlinks healthy |
| Tool memory | `~/.agents/hooks/check-claude-memory.sh` | `~/cron-jobs/claude-memory-guard/check-memory.sh` | `NEEDS-MEMORY-MERGE` | Detect Claude/Grok memory residue → archive → stage → wipe to stub |

Both installed by `setup.sh` (copy from `hooks/`). Schedule: `@daily` + `@reboot` each. Stray merging is automated by `~/.agents/hooks/merge-strays.sh` (cron `@daily`, see Symlink conflict section below).

**Two different flags — do not mix them up:**

| Flag path | Meaning |
|-----------|---------|
| `~/cron-jobs/claude-memory-guard/NEEDS-MEMORY-MERGE` | Staged Claude/Grok memory residue to merge into markdown |
| `~/cron-jobs/agents-symlink-guard/NEEDS-SYMLINK-MERGE` | Quarantined divergent global-rules file under `backups/strays/` |

### Claude/Grok residue → merge into standard files (AI duty)

Cron **cannot** judge “important facts” (no LLM). It only stages. **You (the AI) merge.**

**When:** session start, `continue_project`, or any time you notice:

- flag `~/cron-jobs/claude-memory-guard/NEEDS-MEMORY-MERGE`, or
- `~/.agents/backups/claude-residue/PENDING.md`, or
- project-root `claude_memory_import.md`

**Do:**

1. Read `PENDING.md` and each listed `PACKET.md` (and any `claude_memory_import.md`).
2. Sort facts:
   - global / cross-project → this file (`~/.agents/AGENTS.md`)
   - project conventions, commands, deploy notes → project `AGENTS.md`
   - current handoff / open work → `session_compact.md`
   - architecture choice + why → `docs/DECISIONS.md`
   - skip junk, duplicates, and “DISABLED” stubs
3. If the project has `session_transcript.md`, append a one-line note that residue was imported (write-only; do not read the rest of the file). Skip if no transcript file exists.
4. Delete processed `claude_memory_import.md`. Remove processed packet lines from `PENDING.md`; if empty, delete `PENDING.md` and the `NEEDS-MEMORY-MERGE` flag.
5. Never re-create tool memory stores. Never leave durable facts only in the archive.

### Symlink conflict → merge into canonical (AUTOMATED)

**`~/.agents/hooks/merge-strays.sh` does this automatically** (cron @daily, after the guard): each quarantined stray is fed to a headless LLM ("extract unique durable rules not already in canonical → one markdown section or SKIP"), output is sanitized and appended to canonical, the stray is deleted, the flag cleared. Nothing to type.

**You (AI/human) intervene only when:** the flag survives two merge runs (LLM failing), or you want to relocate merged content from the file tail into its proper section.

Manual procedure (fallback only):
1. Read each listed file under `~/.agents/backups/strays/`.
2. If it has unique durable rules not already in `~/.agents/AGENTS.md`, merge those into the canonical file (this file).
3. Delete the processed stray file path lines from `NEEDS-SYMLINK-MERGE`; if empty, delete the flag.
4. Symlinks should already point at the canonical file (guard re-linked them).
