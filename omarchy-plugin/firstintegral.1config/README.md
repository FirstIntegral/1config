# firstintegral.1config

Omarchy bar plugin that ships with [1config](https://github.com/FirstIntegral/1config). The bar face is the ring. The panel is spend, and vitals for whether this checkout is actually correct.

Left click opens a card under the bar icon, on vitals. Right click refreshes everything (local files, OpenCode Go, and provider limits). `s` opens spend. `v` (`g` as alias) returns to vitals. A tile marked `›` carries detail: Boot slip opens the warn/fail lines the boot dashboard wrote at its last exit, and a dirty Work tree opens the uncommitted files. A fail line makes that tile a fault. `esc` (or a click on the detail) goes back. The detail has a Fix with Grok button, and `f` does the same from the vitals page: it opens a terminal running `grok` in `~/.agents` with the open lines, or every non-ok vital when no detail is open.

The bar shows the ring only, at the bar's own icon size. The tooltip still names the hottest plan (the self-test fixture produces `Claude 50%`) and starts with the brain verdict. An accent dot pulses on the bar when a limit is at 80% or more, and when a vital is a fault.

The panel keeps the thin accent frame. On vitals the ring is a small mark at the left of the verdict, with short rays clipped to that strip. Each check is one line, two columns. That page does not show the limit, the model rows, or the quiet toggle. Spend uses the proportional face for words and monospace for numbers, with no small-caps. Colours come from the current Omarchy theme. A fault uses the urgent colour. A warn stays on the accent.

The spend list is seven tools, in this order, with anything actually used pulled to the front: Claude, Grok, Grok Bot, OpenAI, OpenCode, Codex, Cursor. Each used tool is its own light box. Inside it, each limit and each model is its own lighter box. There is no today total and no box per weekday. The boxes use the same colours as a vitals tile: foreground wash and accent edge. Spend does not draw the accent pip. A limit at 80% uses the stronger edge. An error uses urgent. "By model" sits next to the quiet toggle and starts off. `m` is the same switch. A tool with no tokens, no plan window, and no model rows stays off that list. The button under the title (`q`, `a` as alias) shows those quiet tools at the end, one short box each. No install says "Not on this machine". An install with no ledger says "No usage record on this machine". An empty ledger says "No usage this week". Records that are not in that seven, including the Omarchy fireworks file, are not shown.

| Card | Where the numbers come from |
|---|---|
| Claude, Codex | Omarchy's own usage records. Today tokens, 7-day message counts, limit percent and reset, and `modelUsage` when that file has it. |
| Grok | `~/.grok/sessions/**/usage.json` turn totals for today and 7 days, plus the latest `creditUsagePercent` Grok already wrote to `~/.grok/logs/unified.jsonl`. That field is already a percent on 0–100 (`1` is 1% used). Up to six models. |
| Grok Bot | Newest `weekly-usage.cache` slice in `~/.config/Grok Bot/sand-client-persistence`. `percentUsed` is already a percent on 0–100. One Weekly row, plus On demand when that cache has a cent cap. A cache past `expiresAtMs` is dropped, and so is a reading whose `nextResetMs` is already in the past (the week it measures ended — an old 100% from before a reset must not stick). Other blobs in that directory are not read. |
| OpenAI | Not installed here. The quiet toggle says "Not on this machine" and does not invent a number. |
| Cursor | `cursor-agent` can be on `PATH`. There is no usage ledger for it yet, so the quiet toggle says "No usage record on this machine". |
| OpenCode Go | `GET https://opencode.ai/zen/go/v1/usage` with the active `opencode-go` key in `opencode.db` (`auth.json` only when that row is absent). Three windows: rolling, weekly, monthly. Cached ten minutes. A failed live read keeps the cached windows and says so. A rolling window at 0% reads "Starts on first use". |
| OpenCode on this machine | `step-finish` rows in `~/.local/share/opencode/opencode.db`. The Go windows are the card. Model boxes, when shown, carry tokens and dollars. Same records as `opencode stats`. A database with no `part` table falls back to session token sums. |

The Go read is the one network call, and only when that cache is older than ten minutes. The prepaid dollar balance on the console is a separate wallet and is not on this route. Each footer shortcut uses its first letter as its hotkey (`r` re-read, `f` fix, `s` spend, `v` vitals, `l` limits, `q` quiet, `m` models; legacy `g`, `u`, and `a` still work). In the panel, `r` refreshes everything (re-reads disk with `--refresh-go` immediately and runs `omarchy-agent-usage-update --limits-only` followed by another fresh read), while `l` runs `omarchy-agent-usage-update --limits-only` and forces the Go read again.

Vitals is the checkout, not a diagram of it. Each tile is one check and one short result. Tile text itself prints no paths, remotes, or keys. The groups are Checkout, Rules, Guards, and Machine.

| Tile | Clear when |
|---|---|
| Checkout | `setup.sh`, `verify.sh`, `sync.sh`, and `AGENTS.md` are all in the checkout |
| Work tree | `git status` is clean. A dirty tree is a warn; click it for the uncommitted files |
| Remote | `origin` is one of the lines in `BRAIN_REMOTE` |
| Matches origin | local `HEAD` equals local `origin/main`. Ahead or behind is a warn. Diverged is a fault. No fetch |
| Rules links | all three rules symlinks resolve to this `AGENTS.md` |
| Permissions | `permissions.json` parses, including `bash_without_prompt`. `local.json` may override that flag |
| Hooks | the nine install and guard scripts are in `hooks/` |
| Scaffolds | project template, paper template, its build script, and the Lean lakefile are present |
| Boot slip | the last boot dashboard exit wrote `CLEAN`, except an `ecosystem` or `setup` row that a later `verify.sh` or finished `setup.sh` has already replaced. Other rows stay until the next exit. A missing slip is a warn, not a fault. A line that starts with `fail` is a fault. Click for the lines. Fix with Grok (`f`) opens those lines in a grok terminal. The card re-reads the file about every 120s |
| Memory guard | the installed cron script is present and the residue flag is absent |
| Symlink guard | the installed cron script is present and the stray flag is absent |
| Boot dashboard | the installed autostart `Exec` line points at this checkout's `launch.sh` |
| Three tools | `claude`, `grok`, and `opencode` are on `PATH` |
| TeX | `latexmk` or `pdflatex` is on `PATH` |
| Lean | `lean` is on `PATH`, or `~/.elan/bin/lean` exists |
| Commit signing | global git config has signing on, `gpg.program` ends in `gpg-git.sh`, and a signing key is set |
| Plugin copy | the installed plugin matches this directory. No Omarchy plugins directory reads "no shell", which is clear |

The header still shows the short commit, the branch, the dirty bit, the link count, and the tool count. The bar dot pulses on a usage limit at 80% or on a vital fault. A warn does not pulse the bar. Hover starts with `brain clear`, `brain warn`, or `brain fault`.

No prompt text or credentials leave the collector. Detail lines (slip text, `git status` paths relative to this checkout) are local-file names only, and an `@` never passes. Output is one JSON object on stdout.

## Install

`bash ~/.agents/setup.sh` copies this folder to `~/.config/omarchy/plugins/firstintegral.1config/` when that plugins directory exists, and adds `{ "id": "firstintegral.1config" }` to `bar.layout.right` in `~/.config/omarchy/shell.json` if it is missing. It does not reorder other widgets. Omarchy forbids symlinks inside a plugin, so this is a copy, not a link. The next `setup.sh` overwrites the copy.

Check the collector without the bar:

```bash
python3 bin/usage.py
python3 bin/usage.py --self-test
omarchy plugin validate .
```

IPC: `omarchy-shell firstintegral.1config toggle` · `refresh` · `refreshLimits` · `isOpen`.
