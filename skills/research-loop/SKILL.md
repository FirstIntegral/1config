---
name: research-loop
description: Use when running, planning, or reporting computational experiments with OpenResearch (`orx`) - an ML or numerical run, a hyperparameter or architecture round, a backtest, or a paper reproduction. Pre-register before launch, check the experiment DB before re-running, keep telemetry off. Not for paper prose (research-paper-writing).
---

# Research Loop (OpenResearch `orx`)

OpenResearch keeps a project as a tree of experiment nodes in a local SQLite DB. Each node is a git branch with one fixed run command, and each run is an immutable archive of one commit. This skill adds three things on top: a pinned install with telemetry off, a pre-registration gate before every launch, and a ledger check before every re-run.

## Install and check (once per machine)

```sh
bash ~/.agents/skills/research-loop/orx-install.sh          # pinned musl tarball, sha256-verified
bash ~/.agents/skills/research-loop/orx-install.sh check    # wrapper + persisted opt-out + status "off"
```

- `orx` is `~/.local/bin/orx`, a wrapper that exports `ORX_TELEMETRY_ENV=off` and turns update checks off. Run `check` before the first `orx` call in a session. If it fails, stop and tell the user.
- Never install `orx` another way: no `curl | sh`, no `openresearch-cli-installer.sh`, no AppImage (it self-updates), no `orx update`.
- To bump the pin: `orx-install.sh pin-info <version>` prints the sidecar sha256 and GitHub's asset digest. If they match, ask the user, then pass `--version <v> --sha256 <hex>`.

## Never, without an explicit yes

- `orx install-skills`. Its Codex target is `~/.agents/skills/orx`, which is inside this repo. This skill is the integration.
- `orx login`, `orx feedback`, `orx telemetry on`, `orx update`.
- `--backend openresearch|hf|modal|tinker` (paid or third-party compute). Default to `--backend local`. Use `ssh`, `slurm`, `k8s`, or `ray` only on hosts the user named.
- `orx exp delete`, archiving nodes, or `orx project edit --run-command` on a project with done runs. These are Red lines.

Literature commands send the query off the machine: `orx discover keyword|embedding` and `orx paper` go to alphaXiv, `openalex` and `biorxiv` go to OpenAlex, and `pubmed` goes to NCBI. Never put unpublished results in a query.

## Before any run: check the ledger

```sh
orx projects                                   # find <projectId>
orx project view <projectId>                   # the tree: ids, titles, branches, [root]
bash ~/.agents/skills/research-loop/orx-ledger.sh prior <projectId> '<regex for the idea>'
```

`prior` is read-only and does not run `orx`. Exit `0` means no node matches. Exit `3` means it printed matching nodes with run counts, the latest status, and the commit. Read those first (`orx runs <projectId> --experiment <expId>`, `orx logs <runId>`). A node with a `done` run already answered its question. Re-running it does not test anything new. Branch a child, or report the existing result.

## Pre-register, then launch

1. Create the node. Its title is the idea. Its parent is the baseline, but only in round 1. After that it is the previous round's winner.
   `orx create-experiment <projectId> --parent <expId> --title "<idea>"`
2. On the node's branch, commit `prereg.md` with these lines:
   - `Hypothesis:` the claim.
   - `Prediction:` the metric, its direction, and its threshold, in numbers.
   - `Decision rule:` keep, kill, or descend, and the exact condition for each.
   - Optional: `Seeds:`, `Data:`, and `Not testing:` lines.
3. Copy the same text into the node: `orx exp desc <expId> --stdin < prereg.md`.
4. Gate: `bash ~/.agents/skills/research-loop/orx-ledger.sh prereg-check <expId>`. Exit `0` means the description has all three lines and no run is done or in flight. Exit `1` means you fix the description, or the node is frozen.
5. Launch: `orx exp run <expId> --backend local`, then `orx exp wait <expId>`.

The run records the commit that contains `prereg.md`, so the git history shows the prediction was written before the result. The DB description can be overwritten, so it is a mirror and not the proof. In a project with its own pre-registration ledger (the trading lab), that ledger stays canonical. Write the entry there first and cite its id in `prereg.md`.

## After the run: log the result

- Read the evidence with `orx logs <runId>` and `rg` on the printed path. Status alone is not a result.
- Append to the description. Never rewrite the pre-registered lines:
  `## Result (run <runId>, commit <sha>)`, then the measured value, the verdict under the `Decision rule:`, and the cited log lines.
- A result that misses the prediction stays a result. Do not repair a node after a run has answered it.
- Report measured numbers through verification-before-completion and Digit-refuse. Paper prose goes through research-paper-writing.

## Upstream rules this keeps (OpenResearch SKILL.md)

1. **Never edit a node once a run has answered it.** A run that died on an error (OOM, missing dependency) answered nothing, so repair the node in place. Stop after two such runs in a row and ask the user.
2. **The run command and env are a fixed contract.** Set them once with `orx project edit <projectId> --run-command '<cmd>'`.
3. **Vary the code, not knobs in the command.** Put the change on the child's branch.
4. **Grow the tree downward, in stacked bushes.** Siblings are the co-equal options of one decision. The next round hangs off that round's winner, never off the root.

For more depth, `orx skill` prints the upstream manual and `orx skill <module>` prints one module (`orx-experiment-tree`, `orx-create`, `orx-results`, `orx-logs`, `orx-lit-review`). Where they conflict, the Never list above wins.

## Files and network

- Config: `~/.config/openresearch/settings.json` (`telemetryDisabled`). `credentials.json` exists only after `orx login`.
- Data: `~/.local/share/openresearch/orx.db` and logs, or `$ORX_DATA_DIR`.
- `orx up` serves the dashboard on `127.0.0.1:4791`. When it spawns OpenCode, it writes `~/.config/opencode/skills/orx/SKILL.md`, which is outside this repo and harmless.

---

Adapted from [alphaXiv/OpenResearch](https://github.com/alphaXiv/OpenResearch) `SKILL.md` and `agent-skills/` at commit `a92fd471aba91e9bdd14a88e2322ec42f9dfdbdb`. MIT License, Copyright (c) 2026 alphaXiv. See UPSTREAM.md.
