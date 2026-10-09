# firstintegral.1config

Omarchy bar plugin that ships with [1config](https://github.com/FirstIntegral/1config). The bar face is the ring. The panel is the brain: what the repo is, then the spend.

Left click opens a card under the bar icon. Right click re-reads local files. Spend is the default. `g` opens the map. `s` returns to spend. `h` and `l` cycle the six parts. Click a part in the list under the map.

The bar shows the ring only. The tooltip still names the hottest plan (the self-test fixture produces `Claude 50%`). An accent dot pulses on the bar when a limit is at 80% or more.

The panel keeps the thin accent frame, the small-caps headers, and a slow sweep on the map. The square grid and the scanlines are gone. Colours come from the current Omarchy theme. The sweep runs only while the map is open.

| Card | Where the numbers come from |
|---|---|
| Claude, Codex, Fireworks, any other `~/.local/state/omarchy/agents/usage/*.json` | Omarchy's own usage records. Today tokens, 7-day message counts, limit percent and reset. |
| Grok | `~/.grok/sessions/**/usage.json` turn totals for today and 7 days, plus the latest `creditUsagePercent` Grok already wrote to `~/.grok/logs/unified.jsonl`. |
| OpenCode | `step-finish` rows in `~/.local/share/opencode/opencode.db`. Seven day rows and one row per model, each with tokens and dollars. Same records as `opencode stats`. A database with no `part` table falls back to session token sums. |

The timer does not call a provider. In the panel, `u` runs `omarchy-agent-usage-update --limits-only`, which is Omarchy's collector and does contact the providers you are already signed into. `r` only re-reads disk.

The side pane also reads the checkout, still without printing paths: short commit, branch, dirty bit, how many of the three rules symlinks resolve, whether `claude` / `grok` / `opencode` are on `PATH`, and whether the last boot slip was `CLEAN`. The six parts are Rules, Install, Permissions, Hooks, Scaffolds, and Usage.

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
