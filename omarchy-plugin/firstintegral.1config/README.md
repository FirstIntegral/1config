# firstintegral.1config

Omarchy bar plugin that ships with [1config](https://github.com/FirstIntegral/1config). The bar face is the ring. The panel is spend, and vitals for whether this checkout is actually correct.

Left click opens a card under the bar icon, on vitals. Right click re-reads local files. `s` opens spend. `v` and `g` return to vitals.

The bar shows the ring only, at the bar's own icon size. The tooltip still names the hottest plan (the self-test fixture produces `Claude 50%`) and starts with the brain verdict. An accent dot pulses on the bar when a limit is at 80% or more, and when a vital is a fault.

The panel keeps the thin accent frame. On vitals the ring is a small mark at the left of the verdict, with short rays clipped to that strip. Each check is one line, two columns. That page does not show the limit, the model rows, or the quiet toggle. Spend uses the proportional face for words and monospace for numbers, with no small-caps. Colours come from the current Omarchy theme. A fault uses the urgent colour. A warn stays on the accent.

The spend list is six tools, in this order, with anything actually used pulled to the front: Claude, Grok, OpenAI, OpenCode, Codex, Cursor. Each used tool is its own light box. Inside it, today and the 7-day total are one line, and each limit and each model is its own lighter box. There is no box per weekday. The boxes use the same colours as a vitals tile: foreground wash, accent edge, accent pip. A limit at 80% uses the stronger edge. An error uses urgent. "By model" sits next to the quiet toggle and starts off. `m` is the same switch. A tool with no tokens, no plan window, and no model rows stays off that list. The button under the title (`a`) shows those quiet tools at the end, one short box each. No install says "Not on this machine". An install with no ledger says "No usage record on this machine". An empty ledger says "No usage this week". Records that are not in that six, including the Omarchy fireworks file, are not shown.

| Card | Where the numbers come from |
|---|---|
| Claude, Codex | Omarchy's own usage records. Today tokens, 7-day message counts, limit percent and reset, and `modelUsage` when that file has it. |
| Grok | `~/.grok/sessions/**/usage.json` turn totals for today and 7 days, plus the latest `creditUsagePercent` Grok already wrote to `~/.grok/logs/unified.jsonl`. Up to six models. |
| OpenAI | Not installed here. The quiet toggle says "Not on this machine" and does not invent a number. |
| Cursor | `cursor-agent` can be on `PATH`. There is no usage ledger for it yet, so the quiet toggle says "No usage record on this machine". |
| OpenCode Go | `GET https://opencode.ai/zen/go/v1/usage` with the `opencode-go` key already in `auth.json`. Three windows: rolling, weekly, monthly. Cached ten minutes. A rolling window at 0% reads "Starts on first use". |
| OpenCode on this machine | `step-finish` rows in `~/.local/share/opencode/opencode.db`. One line for today and the 7-day total, and one box per model, each with tokens and dollars. Same records as `opencode stats`. A database with no `part` table falls back to session token sums. |

The Go read is the one network call, and only when that cache is older than ten minutes. The prepaid dollar balance on the console is a separate wallet and is not on this route. In the panel, `u` runs `omarchy-agent-usage-update --limits-only` and forces the Go read again. `r` re-reads disk and uses the Go cache if it is still fresh.

Vitals is the checkout, not a diagram of it. Each tile is one check and one short result. No paths, remotes, or keys are printed. The groups are Checkout, Rules, Guards, and Machine.

| Tile | Clear when |
|---|---|
| Checkout | `setup.sh`, `verify.sh`, `sync.sh`, and `AGENTS.md` are all in the checkout |
| Work tree | `git status` is clean. A dirty tree is a warn |
| Remote | `origin` is one of the lines in `BRAIN_REMOTE` |
| Matches origin | local `HEAD` equals local `origin/main`. Ahead or behind is a warn. Diverged is a fault. No fetch |
| Rules links | all three rules symlinks resolve to this `AGENTS.md` |
| Permissions | `permissions.json` parses, including `bash_without_prompt`. `local.json` may override that flag |
| Hooks | the nine install and guard scripts are in `hooks/` |
| Scaffolds | project template, paper template, its build script, and the Lean lakefile are present |
| Boot slip | the last boot dashboard exit wrote `CLEAN`. A missing slip is a warn, not a fault |
| Memory guard | the installed cron script is present and the residue flag is absent |
| Symlink guard | the installed cron script is present and the stray flag is absent |
| Boot dashboard | the installed autostart `Exec` line points at this checkout's `launch.sh` |
| Three tools | `claude`, `grok`, and `opencode` are on `PATH` |
| TeX | `latexmk` or `pdflatex` is on `PATH` |
| Lean | `lean` is on `PATH`, or `~/.elan/bin/lean` exists |
| Commit signing | global git config has signing on, `gpg.program` ends in `gpg-git.sh`, and a signing key is set |
| Plugin copy | the installed plugin matches this directory. No Omarchy plugins directory reads "no shell", which is clear |

The header still shows the short commit, the branch, the dirty bit, the link count, and the tool count. The bar dot pulses on a usage limit at 80% or on a vital fault. A warn does not pulse the bar. Hover starts with `brain clear`, `brain warn`, or `brain fault`.

No prompt text, paths, or credentials leave the collector. Output is one JSON object on stdout.

`brwsk.brain` is a different plugin (the grokbot-brain tracker). This one is 1config itself.

## Install

`bash ~/.agents/setup.sh` copies this folder to `~/.config/omarchy/plugins/firstintegral.1config/` when that plugins directory exists, and adds `{ "id": "firstintegral.1config" }` to `bar.layout.right` in `~/.config/omarchy/shell.json` if it is missing. It does not reorder other widgets. Omarchy forbids symlinks inside a plugin, so this is a copy, not a link. The next `setup.sh` overwrites the copy.

Check the collector without the bar:

```bash
python3 bin/usage.py
python3 bin/usage.py --self-test
omarchy plugin validate .
```

IPC: `omarchy-shell firstintegral.1config toggle` · `refresh` · `refreshLimits` · `isOpen`.
