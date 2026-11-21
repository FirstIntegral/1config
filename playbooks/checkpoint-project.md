# `checkpoint_project`

Read when: the user says `checkpoint_project`. Read `status-card.md` next, and `machine-notes.md` when the script prints a `notes:` line you do not know.

## `checkpoint_project` trigger

When the user says **`checkpoint_project`** (done for the day — leave and resume later), apply to the **current** project (cwd walk-up to nearest project root, stopping before `$HOME`):

1. Resolve the project root. No session layout there (no `session_compact.md` / `AGENTS.md`) → say so. A git root is not a `create_project`. Follow `~/.agents/playbooks/foreign-checkouts.md`. Anything else → offer `create_project`.
2. Read `session_compact.md` (state restore). Do not open a leftover `session_transcript.md`.
3. Rewrite `session_compact.md` so a fresh AI session can resume from it alone. The top is the status card. Below it: key decisions and the cumulative **Models used** list (current marked). Keep the handoff lines: pointers instead of copies, skills for the next agent, secrets redacted.
4. Do not append to `session_transcript.md`. Collection is retired.
5. Backfill `docs/DECISIONS.md` with any meaningful choices from this session not yet logged (same-turn ADR rule).
6. **Commit and push** (see below). Half-finished work is expected and fine — the point is that the machine is not the only copy.
7. Speak the status card. Then one line: `Checkpoint saved — next step: <item 1>`, plus the pushed commit hash (or one line saying why nothing was pushed).

Same for all four tools. Formalizes the existing "End of session / milestone" rule as an explicit trigger.

### Step 6 in detail — run the script, do not hand-roll git

```sh
bash ~/.agents/hooks/checkpoint.sh <project-root> -m "checkpoint: <YYYY-MM-DD> <what moved>"
```

**Do not open-code these git commands.** Step 6 is mechanical and has exactly one correct answer per project state; hand-running it produced inconsistent behaviour on consecutive checkpoints of the same project. The script is the behaviour; the prose below documents what it does, and `verify.sh` exercises the refusals for real on every run.

Read its exit code and report accordingly:

| exit | meaning | what happened |
|---|---|---|
| `0` | remote backup completed | fetched; took commits this checkout lacked; committed and/or pushed. A fast-forward with nothing local to push is also `0` |
| `3` | clean tree after a successful fetch, already current | no project commit to push. Notes sync still runs. `--dry-run` does not fetch |
| `23` | **notes diverge** — merge refused (delete versus edit, or not a clean text merge) | notes repo unchanged. Project commit is not rolled back |
| `10` | **not a git repo** | nothing done, no `git init` |
| `11` | project is inside another repo, not its root | nothing done |
| `12` | no remote | committed locally, not pushed |
| `13` | remote configured but unreachable | fetch failed. Committed if there was local work. Not pushed, **not created** |
| `14` | push URL owner is not ours | committed if needed, not pushed, not retargeted |
| `16` | **refused** — detached HEAD, or a merge, rebase, cherry-pick, or revert in progress | nothing committed, nothing pushed; finish or abort it, then re-run |
| `15` | **refused** — a fork listed in `fork-parents.txt`, `AGENTS.md` or `docs/DECISIONS.md` already tracked | nothing committed |
| `20` | **refused** — session files, `explain/`, a site's `AGENTS.md` or `CLAUDE.md`, an untracked secret-named or oversized file, or a token-shaped string would be published. Also when the secret scan did not run, or the foreign exclude block could not be written | nothing committed; fix `.gitignore` or that line and re-run |
| `21` | commit or push failed | any commit made is safe; not retried, not forced |
| `22` | **refused** — this checkout is the brain | nothing done; publish with `sync.sh` |
| `24` | **merge conflict** | the merge is aborted. Local commits stay. Nothing is pushed |
| `2` | usage: an unknown flag, a missing value, or a path that is not a directory | nothing done |

`--dry-run` prints the plan and changes nothing. It returns before any notes stat. Anything other than `0` or `3` goes in the closing line so the state is never silently lost.

Exits `0`, `3`, `12`, `13`, `14`, `16`, `21`, and `24` run `hooks/notes-sync.sh push` after the project half. Exits `2`, `10`, `11`, `15`, `20`, and `22` do not. A missing real notes clone is created from `NOTES_REMOTE` once. If that fails, stdout is `notes: skipped`, stderr keeps the setup hint, and the checkpoint exit stays. A markdown file both machines changed is merged (`notes: merged`) and pushed. Exit `23` is the notes half: the merge was refused, nothing in the notes repo was written. A notes failure does not roll back a project commit. A notes sync that fails for another reason turns a `0` or a `3` into `21`. Any other exit stays, so an unreachable remote is still `13`.

Exit `3` happens only after `git fetch --prune` of the push remote succeeds and that branch has no commit this checkout lacks. A clean tree with commits absent from the push remote still pushes, also when another remote has them, and also when the server no longer has the branch. `--dry-run` does not fetch, so its exit `3` is local refs only. Exit `14` does not fetch: the owner veto stays in front of the network.

The brain checkout exits 22 before any git command. That is the directory `checkpoint.sh` lives in, and a worktree whose `origin` is listed in its `BRAIN_REMOTE` and which contains `setup.sh` and `verify.sh`. `checkpoint_project` stops there. `sync.sh` is the publisher.

**Gate the script applies, before touching git at all:**

| project is | do |
|---|---|
| **the brain checkout** | **nothing.** Exit 22. Say `sync.sh` is the publisher. |
| **not a git repo** | **nothing.** No commit, no push, no `git init`. Say "not a git repo — nothing pushed" and finish the checkpoint normally. |
| a repo with **no remote** | commit locally, **do not push**, do not add a remote. Say "committed locally, no remote". |
| a repo with a remote | fetch, take commits this checkout lacks, commit, and push. No asking |

**HARD RULE: a checkpoint never creates a repo, never adds a remote, never creates a GitHub repo.** A project without a repo is a deliberate state — scratch work, a scaffold, something not meant to be published — and a checkpoint is a note-taking action that must not silently change it. Publishing something the user never chose to publish is not recoverable by deleting it afterwards. If a project looks like it wants a repo, say so and let them decide next session.

Also check the **root**, not just "somewhere in a repo": `git rev-parse --show-toplevel` walks *up*, so it succeeds for any subdirectory. A toplevel differing from the project root means the project sits inside someone else's repo (or a parent worktree), and committing there would sweep unrelated work into the checkpoint. Do not commit in that case — say so and skip.

**Which projects get a remote is a manual decision, and stays one.** Nothing in this setup creates repos; `create_project` does not, and neither does a checkpoint. A project has a remote because someone deliberately ran `gh repo create` or `git remote add`. That is the whole policy.

**The project's `AGENTS.md` records the remote as documentation — never as authorisation.** The `## Repo` section in `project-template/AGENTS.md` carries the URL so it is visible without running git, and `checkpoint.sh` cross-checks it against `git remote get-url --push` and warns on a mismatch. But **git config always wins**, because git config is set by an explicit human action while `AGENTS.md` is a file an AI writes: a line hallucinated into it must never be able to authorise a push, and a stale line must never redirect one. Documentation drifts; the push target cannot be allowed to drift with it.

**What "has a remote" means here.** The test is a configured remote, not GitHub specifically — a self-hosted or GitLab origin pushes exactly the same way, and nothing in this trigger is GitHub-aware. Two consequences worth stating:

- **Read the URL before pushing, do not just count remotes.** `git remote get-url --push origin`. If `origin` does not exist but other remotes do, do **not** guess which one to push to — commit locally, name the remotes found, and let the user choose. If the branch already has an upstream, push there and ignore all of this.
- **A configured remote is not a reachable one.** The URL can point at a repo that was deleted, renamed, or that this key cannot write to.

**When the push fails, the checkpoint still succeeded.** Steps 1-5 are the checkpoint; the push is a backup. On any push failure: report the exact error, leave the commit in place, and finish with "committed <hash>, push failed: <reason>". Then stop. Specifically never, in response to a failed push:

- `gh repo create`, or add/rewrite a remote — the repo not existing is an answer, not an obstacle
- `--force` / `--force-with-lease` — the script already merged what it could. A push that still fails is left in place
- `git rebase`, `git reset`, amending, or any history rewrite to make the push go through. A conflicted merge is aborted (exit `24`), not finished by hand inside the script
- retrying with a different branch or remote than the one that failed

Repo with a remote, the normal path is the script. It fetches the push remote first. Commits that this checkout lacks are taken with `git merge` (fast-forward when that is the whole story). Local edits that block a fast-forward are committed, then merged. A conflict aborts that merge and exits `24`. Then:

```sh
git add -A                      # session files are gitignored, so they stay local
git commit -m "checkpoint: <YYYY-MM-DD> <what moved today>"
git push                        # -u origin <branch> if the branch has no upstream
```

- **Signing and attribution rules apply unchanged** — signed commit, no `Co-Authored-By: Claude`, no "Generated with Claude Code". Signing fails → read `~/.agents/playbooks/signing.md`. Never bypass.
- **Commit on the current branch**, whatever it is. A checkpoint records where the work actually is; it is not the moment to invent a branch or open a PR.
- **`git push` prompts only when the effective `bash_without_prompt` is off.** Canonical `permissions.json` still lists the ask rules (the restore-gate). While the effective flag is true, setup omits them from live configs so OpenCode last-match and Grok shell-ask cannot re-prompt. Do not `--force` or invent a workaround if a prompt appears — that means fan-out drifted.
- **Clean, fetch succeeded, already current** → exit `3`. Clean with commits the remote lacks → skip the commit but still push. Clean and strictly behind → fast-forward, exit `0`.
- **Session files are never committed** (`session_compact.md`, a leftover `session_transcript.md`, `claude_memory_import.md`) — the template `.gitignore` already excludes them. If a project lacks those ignore lines, add them *before* the `git add -A`, or the checkpoint publishes a private file. Verify with `git add -A --dry-run` before committing in any project whose `.gitignore` you have not seen this session. Under `~/Projects/sites/*` the Sites rule in `~/.agents/AGENTS.md` also keeps `AGENTS.md` out. On a foreign checkout those private files go in `.git/info/exclude`, not in their `.gitignore`. A dirty hunk in a file they already track is yours to handle: `checkpoint.sh` does not do it. Copy the hunk aside, run the checkpoint, and copy it back. Do not set skip-worktree.

Rationale for pushing unfinished work: a checkpoint fires when the day ends, which is usually mid-thought. The tree being messy is the normal case, not a reason to hold it back — remote is a backup here, not a release. Anything genuinely not for publication belongs in `.gitignore`, which is the mechanism that decides what leaves, not the checkpoint's judgement. That rationale covers *existing* remotes only; it is never a reason to create one.
