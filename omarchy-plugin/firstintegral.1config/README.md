# firstintegral.1config

Omarchy bar plugin that ships with [1config](https://github.com/FirstIntegral/1config). One widget for this machine's AI usage.

The bar shows the hottest plan percentage on disk (the self-test fixture produces `C 50%`), or today's token total when no plan figure exists. Left click opens the panel. Right click re-reads local files.

| Card | Where the numbers come from |
|---|---|
| Claude, Codex, Fireworks, any other `~/.local/state/omarchy/agents/usage/*.json` | Omarchy's own usage records. Today tokens, 7-day message counts, limit percent and reset. |
| Grok | `~/.grok/sessions/**/usage.json` turn totals for today and 7 days, plus the latest `creditUsagePercent` Grok already wrote to `~/.grok/logs/unified.jsonl`. |
| OpenCode | Read-only sum of token columns in `~/.local/share/opencode/opencode.db` for today and 7 days. |

The timer does not call a provider. In the panel, `u` runs `omarchy-agent-usage-update --limits-only`, which is Omarchy's collector and does contact the providers you are already signed into. `r` only re-reads disk.

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
