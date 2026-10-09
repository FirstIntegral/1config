# Brain decisions

ADRs for `~/.agents`. The origin allowlist is `BRAIN_REMOTE`. Project work logs decisions in *that* project's `docs/DECISIONS.md`. This file is the brain's own.

## 2026-10-09 — 1config ships its own Omarchy usage plugin

**Decision:** `omarchy-plugin/firstintegral.1config/` is part of this repo. `setup.sh` copies it into `~/.config/omarchy/plugins/firstintegral.1config/` when that directory's parent exists, and inserts the widget id into the live `shell.json` right section if it is absent. The collector reads Omarchy's existing usage records (Claude, Codex, Fireworks), Grok's local session ledger and last credits snapshot, and OpenCode's local sqlite database. The refresh timer does not call a provider. Panel key `u` may run `omarchy-agent-usage-update --limits-only`. Ubuntu skips the copy. The widget is not `brwsk.brain`.

**Why:** NixFred's Burn Bar (`github:nixfred/burnbar`) and Infomarchy (`github:nixfred/infomarchy`) are the Omarchy plugins that put this machine's AI usage on the desktop. Burn Bar is a large cockpit (pace advice, local GPU, Jetson ssh) and a separate project. Omarchy's own `omarchy.agents` widget already draws Claude, Codex, and Fireworks, and it does not read Grok or OpenCode ledgers. 1config is the thing that ties those three tools together, so the bar widget belongs in this repo and only adds the reads Omarchy does not do. Copying Burn Bar in would freeze someone else's UI and its network behavior inside the brain.

**Rejected:** `omarchy plugin add` of burnbar or infomarchy as the 1config answer. Vendoring either repo. A provider call on the timer. Putting the widget in omarchy-dots (that pack does not install plugins, and the live `shell.json` is already a local edit because `brwsk.brain` is on the bar). Reusing the `brwsk.brain` id.

## 2026-10-09 — Claude reads project AGENTS.md; the hook is a fallback

**Decision:** Keep `hooks/load-project-agents.sh`, and make it print nothing when Claude Code will load the project `AGENTS.md` itself. That is Claude 2.1.277 or newer, instruction mode unset or `claude-md-or-agents-md`, and no `CLAUDE.md`, `.claude/CLAUDE.md`, or `CLAUDE.local.md` in the working directory or a parent. `~/.claude/CLAUDE.md` is excluded from that check. Mode `claude-md-and-agents-md` also loads the file, so the hook stays quiet. The hook still prints for an older or unknown Claude, for mode `claude-md` or `managed-only` or any unknown mode, and for the default mode when a suppressing file is present. The user symlink stays. No line cap and no context-percent meter on `AGENTS.md`. The Omarchy skill stays out of this file. The rules file stays one file.

**Why:** On 2.1.295 the native reader and the SessionStart hook both delivered the same project file, and the two copies are not deduped. A project `CLAUDE.md` makes the native reader ignore `AGENTS.md`, so deleting the hook would drop project rules there and on Claude before 2.1.277. The file is about 1.4% of a 1,000,000-token window, under the 3% headroom that closed the line-cap debate. The Omarchy skill is already discovered by all three tools. A side file the model might open is not loaded by any of them.

**Rejected:** Deleting the hook. A version check with no suppressor check. Pasting the Omarchy skill into `AGENTS.md`. Splitting the rules file into on-demand markdown. A verify failure at 3% of the window.

## 2026-10-09 — Oracles, policy keys, kill tokens, brain checkpoint refuse

**Decision:** Four mechanical laws. No line cap on `AGENTS.md`.

1. `hooks/rule-oracles.sh` is the executable form of the `create_project` path rule and of the ban on hooks reading `session_transcript.md`. `verify.sh` runs it.
2. A keyed fact in this file is a `**Policy:**` line. One active `key=value`. A replaced value is `key superseded-by <heading>`. `verify.sh` fails on a second active value or a missing heading. Whole headings stay, because one ADR can mix live and dead facts.
3. Retired names live in `hooks/kill-tokens.deny`. `merge-strays.sh` will not append a section that contains one; the stray stays. `verify.sh` fails if a token appears in the prompt or the templates. A gitignore sample may still name a retired path so new projects keep ignoring it.
4. `checkpoint.sh` exits 22 on this checkout, before git. `sync.sh` remains the publisher of the brain.

**Why:** A phrase check does not compute the path rule. Two live ADRs assigned opposite values to the same fact. The stray merger can paste a killed name back into the prompt. `checkpoint.sh` would commit and push this repo without running `verify.sh`.

**Rejected:** A line cap on `AGENTS.md` (still under debate; a share of the context window is the candidate, not a line count). An LLM judge inside `verify.sh`. Marking an entire mixed ADR superseded. A `session_compact.md` for the brain.

## 2026-10-04 — Boot dashboard keeps sync exit codes

**Decision:** `check_brain_sync` and `check_dots_sync` store `$?` from the hook itself. Exit 5 from `omarchy-dots/sync.sh` is shown as that script's own last line (a live file was edited). The README no longer mentions `apply.sh --no-pkg` or an opentabletdriver row.

**Why:** Both checks were `out="$(...)" || true` then `rc=$?`. The dashboard is `set -u` only, so `|| true` is not what keeps it alive. It makes `$?` always 0. A failed dots sync painted a green check and wrote `CLEAN`. The 2026-10-04 false green row was a different bug (the dots script re-execs itself now), but the next real failure would have been hidden the same way. Exit 5's text still said opentabletdriver, which `sync.sh` does not use.

**Rejected:** Parsing the output text to guess success. Re-running `sync.sh` from the dashboard after a fast-forward (the script re-execs; the caller is the wrong place).

## 2026-09-29 — Boot dashboard writes a close slip

**Decision:** On exit, `dashboard.sh` overwrites `~/.agents/boot-dashboard/close-slip.txt`. One line per warn or fail that is not the tool-updates row, words as shown. No such row writes the single word `CLEAN`. The file is gitignored. A missing file means this dashboard has not exited since the slip existed.

**Why:** The window is gone after ENTER. Deleting the file on a clean close looks the same as a dashboard that never ran. Tool updates already live in `update-apps.log`, so that row is omitted.

**Rejected:** Deleting the file when clean. A second terminal or a tail of the updater log. Recording ok and skip rows.

## 2026-09-29 — This tree is 1config

**Decision:** Canonical `AGENTS.md` opens with the name. This checkout is the GitHub repo `FirstIntegral/1config`. On this machine that checkout is `~/.agents/`. "Global brain", "the brain", and `global_brain_update` mean that same repo. `SETUP.md` carries the same paragraph. `verify.sh` fails if either file drops `This tree is **1config**`.

**Why:** The rules file said "this repo" and "the brain" and never said the GitHub name in the text every session loads. `SETUP.md`, `LICENSE`, and the figure already said 1config. An agent then went looking for what 1config was.

**Rejected:** Leaving the name only in `SETUP.md` or the figure. A second identity file. Tool-local copies of the sentence.

## 2026-09-29 — Digit refuse is the default gate on a new paper

**Decision:** After latexmk, a new paper's `build.sh` runs `hooks/digit-refuse.sh`. A measurement token in prose must already appear, character for character, in a tabular or a caption of that paper. `digit-refuse.deny` lists tokens that must not be typeset at all. `\TODO{...}` is not a claim. A bare integer in the deny file, or any fuzzy / near / LLM / repo-wide flag, exits 2 and writes nothing. A clean check is silent. A miss prints `file:line` and fails the build. Scope defaults to the whole paper. Existing papers are not backfilled.

**Why:** On 2026-09-12 a leftover counter billed 2 evals where the method spent 6, rescue took about 45% of the budget instead of the reserved sixth, and the headline `118/135` (and `121/135`) was repeated as the result. The corrected table is `100/135`. The prose and the buggy table had agreed, so a later sentence can still carry the dead token. The gate is the build, not a widget, because that is the minute a digit ships.

**Rejected:** A glass claim board. A fuzzy match that would accept `100/136` because `100/135` is close. Searching the whole repo for the digit. Backfilling every existing `build.sh`. Treating a caption protocol line (n, seeds, budget) as prose that must be repeated inside the grid. Equating `1.20\times 10^{4}` with `12040`.

## 2026-09-27 — Opinionated default is on

**Policy:** bash_without_prompt=true
**Policy:** caveman=full

**Decision:** Clones get this config. `bash_without_prompt` is true in `permissions.json`. Caveman is always on (full) in `AGENTS.md`. This machine has no `local.json`. That file stays a gitignored opt-out (`false` / `off`) for someone who rejects the default. `setup.sh` still merges it when it exists, into the live tools only.

**Why:** The repo is opinionated. Shipping the safe default in git and the real default in a private file made GitHub and this machine disagree. Autonomy and caveman are the direction. Red lines still wait for a yes.

**Rejected:** Leaving the committed Bash flag false. Keeping caveman off unless a private file turns it on.

## 2026-09-27 — Public adoption: license, git author, red lines, local overlay, one remote

**Policy:** bash_without_prompt superseded-by 2026-09-27 — Opinionated default is on
**Policy:** caveman superseded-by 2026-09-27 — Opinionated default is on
**Policy:** paper_author=git-config

Item (4) below, and the claim that this machine keeps autonomy and caveman via `local.json`, are historical. The live bash flag and caveman level are the Opinionated default ADR. License, git author, red lines, and `BRAIN_REMOTE` in this ADR stay live.

**Decision:** Five changes so a stranger can take this repo. (1) MIT license. The copyright notice names Brusk Kawa Abdalla and `github:FirstIntegral/1config`; keeping that notice is the credit, including for commercial use. (2) Paper author and contact come from `git config user.name` and `user.email`. The template no longer carries a personal email. (3) Red lines live in `AGENTS.md`: destructive acts and anything that leaves the machine wait for an explicit yes even when Bash autonomy is on. (4) Committed `bash_without_prompt` is false and caveman is off. Gitignored `local.json` may set either. `setup.sh` merges the Bash key into the live tools only. (5) `sync.sh`, `verify.sh`, and boot sync read allowed origins from `BRAIN_REMOTE`. A fork edits that file.

**Why:** The behavior rules were already the adoptable part. The blockers were a missing license, a personal name baked into every session, safety confirms that lived outside the shared file, taste shipped as the only durable default, and the GitHub URL copied through the scripts. This machine keeps autonomy and caveman via `local.json`, which upstream does not own.

**Rejected:** A custom "say my name in your README" license. Leaving autonomy on in the committed json. Splitting voice into a second file. Hardcoding the remote in each script and telling forks to hunt the copies.

## 2026-09-27 — Three OpenClaw habits in, three layouts out

**Decision:** Steal three habits. (1) A herd post that only agrees is noise; a recant, a kill, or a new measurement is a post. (2) Before a new tool, script, or service, look for a maintained one; build custom only when that one is dead, unsafe, or the user asked for custom. (3) A required file that is absent is said out loud; do not invent its contents. Refuse three layouts: no `SOUL.md` / `USER.md` / `IDENTITY.md`; no agent-readable daily diary; no personal heartbeat. Text lives in `AGENTS.md` (`## Herd boards`, `## Kept out`, During work) and `SETUP.md` §5f plus the during-work rule. `verify.sh` checks the phrases in both files.

**Why:** The useful half of that layout was already here under other names (one rules file, caveman as voice, private transcript, machine heartbeat). Round 11 burned seats repeating a fact already on the wall, and a missing graveyard must not be invented. The preflight was practiced sometimes and unwritten. The three refusals would fight injection, transcript privacy, and the heartbeat this machine already runs.

**Rejected:** Copying the extra Markdown files. An agent-readable `memory/YYYY-MM-DD.md`. A social ping for mail, calendar, or hours of silence. Leaving the refusals unwritten.

## 2026-09-27 — Herd boards are a standing rule

**Decision:** A crowd of talking agents uses one append-only flocked wall, waves so later seats can read earlier posts, public recants, a parseable last line, and one coder only after a mechanical lock. Argument waves do not run the official seeds. Text lives in `AGENTS.md` (`## Herd boards`) and `SETUP.md` §5f. `verify.sh` checks the heading in both.

**Why:** Repeated across projects. Parallel seats cannot see each other, so a single blast is not a conversation. Honesty instructions produced blunt, sourced kills. Unrestricted official-seed runs made the later table a reproduction. The rule stays short because this file loads into every session.

**Rejected:** A per-project-only note. A long sociology section. Raising the live cap so every seat starts together. Personal-abuse as a goal.

## 2026-09-16 — Lean `docs/paper/lean/` is default on new writepaper scaffolds

**Policy:** lean_scaffold=default

**Decision:** First `writepaper_project` copies `paper-template/lean/` with `main.tex` / `build.sh` / `figures/`. New papers get a Lean project by default. Existing `docs/paper/` trees without `lean/` stay grandfathered (not backfilled). Do not overwrite a paper's existing Lean files.

**Why:** User wants Lean present the moment a new paper is scaffolded, not as a later copy step. The kernel-check still only runs because `build.sh` sees `lean/`. Fidelity caveat unchanged: `lake` green is not a proof the LaTeX sentence matches.

**Rejected:** Silent backfill of Darboux / other in-flight papers. Making Mathlib the template default. Treating `template_sanity` as a paper theorem.

## 2026-09-16 — Lean 4 opt-in kernel-check for papers (P0)

**Policy:** lean_scaffold superseded-by 2026-09-16 — Lean `docs/paper/lean/` is default on new writepaper scaffolds

The sentence below that copies `lean/` only when a theorem is being formalized is historical. New papers copy `lean/` by default. The rest of this ADR stays live: no Mathlib in the template, `install-elan.sh` as the install path, `lake build` when `lean/` exists, and `statement-fidelity unmeasured` until a mechanical crosswalk exists.

**Decision:** Add Lean 4 as an opt-in paper kernel-check. Template `paper-template/lean/` is core Lean only (pinned `leanprover/lean4:v4.34.0`, no Mathlib). `writepaper_project` copies `lean/` only when a theorem is being formalized. Existing papers are grandfathered. `setup.sh` probes `elan` non-fatally like TeX and never installs it. Install path is `hooks/install-elan.sh` (official tarball, then run the binary — never `curl | sh`). `build.sh` runs `lake build` when `lean/` exists; missing lake skips; type errors fail. Verified count is `n/m kernel-checked Lean statements`. `lake` green is not fidelity to the LaTeX sentence — Gaps must say `statement-fidelity unmeasured` until a mechanical xwalk exists.

**Why:** Kernel is the right judge of *Lean proofs*. It cannot see LaTeX. Forcing Lean on every `amsthm` paper would tax Vigil/sites/trading papers and freeze Darboux trees as illegal. Mathlib in the template would make `verify.sh` a multi-GB download. The conversion protocol (parts list → pedantic Lean → compiled-signature diff, or Lean-first statements) is the actual anti-wrong-theorem layer and is deferred to P1/P2.

**Rejected:** Landing the full xwalk/lock/probes/dual-formalizer stack in the same turn. Mathlib-on by default in the template. HARD RULE that every `amsthm` paper must have a Lean mirror. `litex` as a Lean-in-LaTeX SSOT (the named tool is a different language). Distro/AUR Lean. `curl | sh` elan-init. Pinning `stable`/`nightly` or stale 4.32. Claiming “paper theorems are kernel-verified.” leanlab (unrelated PyPI tool). Human sign-off as a same-turn writepaper gate.

## 2026-09-05 Deny `rm -rf` is exact `/` `~` `$HOME`, not a glob under them

**Decision:** Drop `Bash(rm -rf /*)`, `Bash(rm -rf ~/*)`, `Bash(rm -rf $HOME/*)` from canonical `permissions.json`. Keep exact `Bash(rm -rf /)`, `Bash(rm -rf ~)`, `Bash(rm -rf $HOME)`.

**Why:** All three matchers treat `*` as a glob. OpenCode last-match then denies `rm -rf ~/.config/protonmail` and `rm -rf /home/brwsk/.config/protonmail` even after Vigil **Y allow once** (screenshot 2026-09-05). The rules were meant to block wiping `/` or `$HOME`, not every recursive delete under them. Vigil's rm-root classifier (0.6.1) owns `rm -rf /*` / `~/*` / `$HOME/*` as exact-root wipes.

**Rejected:** Escaping the star (`/\*`) — Grok/Claude/OpenCode glob syntax is not the same, and a missed escape would re-break every `rm -rf /…`. Leaving the globs and telling the human to use `mv` (that was the workaround, not the fix).

## 2026-09-04 — Boot dashboard self-syncs the brain from 1config

**Decision:** New hook `hooks/brain-sync.sh`, run by the boot dashboard right after the network check. It fetches `origin/main` and, when local `~/.agents` is behind `github:FirstIntegral/1config`, fast-forwards to match the repo. The dashboard surfaces the result as a row (`ok` up-to-date/ff'd, `warn` fetch-failed/ahead/dirty, `fail` divergence).

**Why:** A box that has been off for a while boots with a stale brain and no way to know it; previously `git pull && bash setup.sh` was a manual step that only happened when the user remembered. Local should follow the repo by default.

**Safety constraints (hard):** fast-forward only (`git merge --ff-only`); remote must validate to `FirstIntegral/1config` (never a fork / stale URL); never pulls over uncommitted edits or unpushed commits; ssh `BatchMode=yes` + time-bounded fetch so boot never hangs on a passphrase prompt. Divergence/dirty/behind-with-edits are surfaced, never silently rewritten.

**Rejected:** A `git pull` (non-ff merge could rewrite local commits). `git reset --hard origin/main` (destroys local work). A `@reboot` cron job instead of the dashboard (no human-visible row; dashboard already runs at login). Running it before the network check (would false-warn offline every cold boot).

## 2026-09-03 — Omit ask fan-out while `bash_without_prompt` is true

**Decision:** When `bash_without_prompt` is true, `setup.sh` writes empty ask buckets to Claude and Grok, and skips ask patterns in OpenCode `permission.bash`. Deny still fans out. Canonical `permissions.json` still lists the ask rules (restore-gate when the flag flips).

**Why:** OpenCode last-match: `"git push": "ask"` after `"*": "allow"` re-prompted `git push 2>&1 | tail -5; git status; git rev-parse HEAD` (screenshot 2026-09-03, OpenCode 1.10/1.18). Grok always-approve still honors shell `ask` rules (Grok permissions docs). Claude `bypassPermissions` already skipped them. Policy since 2026-08-29 is no generic git-push prompt; live configs did not match.

**Rejected:** Moving `"*": "allow"` after the ask keys (works, but leaves dead ask rules that look like they still prompt). Converting ask → allow (would keep `git push` silent even after a TUI mode flip). Leaving ask in OpenCode as "best-effort" (they are not best-effort — last-match makes them win).

## 2026-08-29 — Full Bash autonomy (`bash_without_prompt: true`)

**Policy:** bash_without_prompt superseded-by 2026-09-27 — Opinionated default is on

The flag value below still matches the live value. The active Policy line lives on the Opinionated default ADR so the key has one home.

**Decision:** All three tools run without Bash permission prompts. Claude `bypassPermissions`, Grok `always-approve`, OpenCode `permission.bash["*"] = allow`.

**Why:** Claude's allowlist cannot remove hard-coded safety prompts (`cd`+write, `cd`+git / untrusted hooks, some parse verdicts). The only switch that actually kills them is `bypassPermissions`. The user chose that 2026-08-29.

**Cost:** Claude ask/deny lists become best-effort (bypass skips checks). Generic `git push` no longer prompts. This is **not** a default most people want.

**Flip:** `permissions.json` → `"bash_without_prompt": false`, then `bash ~/.agents/setup.sh`. Documented in `README.md` on purpose so forks see it.

**Rejected:** Leaving Claude on `acceptEdits` and expanding the allowlist. Empirically insufficient.

**Follow-up 2026-09-03:** ask rules were still fanned out; OpenCode last-match re-prompted `git push`. See the omit-ask ADR above.

## 2026-09-02 — Git signs via `gpg-git.sh`, never pinentry GUI

**Decision:** `setup.sh` sets `git config --global gpg.program` to `hooks/gpg-git.sh`. The wrapper calls `gpg --batch --pinentry-mode loopback`, and on cache miss runs `gpg-agent-unlock.sh` then retries. Boot dashboard unlocks GPG **before** tool-update / verify.

**Why:** Keyring unlock already worked, but git still invoked `pinentry-gnome3` when the agent cache was cold (first commit of a session, or a test `git commit` inheriting global `commit.gpgsign`). That is the "enter the GPG password" dialog. Dashboard used to unlock last, after minutes of updater wait.

**Rejected:** `pinentry-mode loopback` in `gpg.conf` (would also strip GUI from encrypt/decrypt). Leaving git on stock gpg and hoping the dashboard races win.

## 2026-08-29 — Dedicated `gpg-signing` keyring collection

**Decision:** Store the GPG passphrase in a gnome-keyring collection labelled `gpg-signing` (empty master, autologin-safe), not in the default collection. Unlock scans bricked on-disk `.keyring` files and restocks.

**Why:** gnome-keyring 50 cannot reload an unencrypted default keyring after any item's `secret=` contains a raw newline (Proton JSON, etc.). Journal: `invalid or unrecognized format`. SearchItems then empty even though the GPG item is still in the file. A one-item collection does not pick up those secrets.

**Rejected:** Sharing the default collection; calling `Service.Unlock` (GUI prompt); encrypting the collection with the login password (autologin has none).

## 2026-08-29 — Omarchy + Ubuntu, inventory is machine-local

**Decision:** The same clone + `setup.sh` must work on Omarchy (Arch) and Ubuntu (Debian), fresh or `git pull` on an existing box. Live grok/claude/opencode versions live in gitignored `inventory.local.md`, not in `SETUP.md`. GPG key id comes from `git config --global user.signingkey` / `$GPG_SIGNING_KEY`, never a hardcoded key from another machine.

**Why:** Pinning versions in `SETUP.md` made Ubuntu fail verify after pulling Omarchy's table (and would dirty git the other way). Hardcoding `95FBA6E0AA245342` made a second machine unlock the wrong key. `setup.sh` prints the distro-correct package line and does not run `apt`/`pacman`.

**Rejected:** Auto-installing packages from setup.sh; keeping the version table in the spec; a default fallback key id.

## 2026-09-01 — Inventory: login PATH, then vendor-dir fallback

**Decision:** `inventory.local.md` resolves each CLI with (1) login shell `command -v`, then (2) executable files in `~/.opencode/bin`, `~/.grok/bin`, `~/.local/bin`. `mise_managed()` in the updater stays (1) only. No `~/.local/bin` symlink, no `.bashrc`/`.profile` edits. A missing command is `unknown`/`missing`; stderr is never a version string.

**Why:** Official OpenCode (and Grok) installers put the binary in a vendor dir and prepend that dir in `.bashrc`. Ubuntu `.bashrc` returns immediately for non-interactive shells (`case $-` interactive-guard), and inventory probes with `env -i bash -lc`, so Ubuntu reported OpenCode missing and stuffed `command not found` into the version cell even though `~/.opencode/bin/opencode` existed and the updater already had that dir on its own PATH. Omarchy may install the same tools via mise; those shims show up in step (1) and must keep winning, or the updater would CDN-upgrade a shadowed leftover vendor binary.

**Rejected:** Unconditional `~/.local/bin/opencode` symlink (shadows mise on Omarchy). Teaching `setup.sh` to edit the user's `.profile` (1config does not own dotfiles; public forks would inherit that). Putting vendor dirs into `mise_managed()` (would treat a leftover vendor copy as "the" tool and skip or fight mise).

## Standing — No AI attribution; never bypass signing

Commits and PRs are the user's. `Co-Authored-By: Claude` and "Generated with …" are forbidden. `--no-gpg-sign` is forbidden. Recorded in `AGENTS.md` as HARD RULEs.

## Standing — `create_project` / `checkpoint_project` never publish

Neither trigger runs `git init`, `git remote add`, or `gh repo create`. A project without a repo or remote is a deliberate state. Checkpointing is note-taking, not a release.

## Standing — Tool-internal memory off

Claude project `memory/` dirs are DISABLED stubs. Grok `[memory] enabled = false`. Durable facts go to markdown. Cron guards wipe residue.

## Standing — Papers are LaTeX, no bibliography

`writepaper_project` assumes `texlive-full` (Ubuntu) or `texlive-meta` (Omarchy). No `\cite`, no `refs.bib`. Author block comes from `git config --global user.name` and `user.email`. An empty value means stop and ask.

## 2026-09-09 — Default `create_project` root

Simple `create_project <name>` commands resolve to `~/Projects/<name>`. Explicit paths remain supported. This prevents project placement from depending on whichever directory a tool happened to start in. The previous behavior was ambiguous and placed `infomarchy_design` directly under `$HOME`; that project was moved to `~/Projects/infomarchy_design`. No git repository or remote is created.
