# Permission policy

Read when: a command prompts that should not, a permission rule has to change, or the task is `permissions.json` or an autonomy flag.

## Permission policy — canonical file

Global permission policy lives in **`~/.agents/permissions.json`**. `setup.sh` fans it out to every tool that has a persistent permission config, deduped and idempotent. Canonical permission buckets and modes win so revocations propagate; unrelated non-permission config survives:

| Step | Tool | Lands in | Form |
|------|------|----------|------|
| `5b` | Claude Code | `~/.claude/settings.json` → `permissions.allow` / `.ask` / `.deny` | rules verbatim |
| `5c` | Grok | `~/.grok/config.toml` → `[permission] allow` / `ask` / `deny` | rules verbatim (Grok speaks the same `Bash(...)` syntax) |
| `5d` | OpenCode | `~/.config/opencode/opencode.jsonc` → `permission.bash` + `permission.external_directory` | `Bash(X)` → `"X": "allow"` / `"ask"` / `"deny"`; `external_directory` follows `bash_without_prompt` |

- Add or remove a rule → edit `~/.agents/permissions.json`, then `bash ~/.agents/setup.sh`. `verify.sh` fails if any of the three drifts.
- **Never hand-edit the per-tool copies** (`~/.claude/settings.json`, `[permission]` in `config.toml`, `permission.bash`) — they would drift from canonical and survive only until someone re-reads the source.
- **Cursor Code has no persistent permission file.** Its command autonomy is per-invocation (`cursor-agent --force` / `--yolo` / `--sandbox`), so the policy does not fan out to it. The rules file still applies (Tool parity, in `AGENTS.md`).
- Grok and OpenCode get enforceable `Bash(...)` rules only; `Skill(...)` is Claude-only. OpenCode's managed `"*"` catch-all is `"ask"` when Bash autonomy is off and `"allow"` when on; `permission.external_directory` (any file access outside the project cwd, e.g. `/tmp` scratch work) follows the same switch — OpenCode-only, Claude and Grok cover out-of-tree access with their autonomy modes. Canonical allow, then (if autonomy off) ask, then deny follow it — OpenCode uses **last match**, so a later `"git push": "ask"` beats `"*": "allow"`. **While `bash_without_prompt` is true, setup omits ask fan-out** for all three tools (OpenCode last-match; Grok always-approve still honors shell ask; Claude can still prompt on an explicit ask rule). Deny still fans out after `*` so last-match deny holds.
- **The opinionated default is on.** `permissions.json` ships `bash_without_prompt` true. A fresh clone gets Claude `bypassPermissions`, Grok `always-approve`, OpenCode bash `"*" = allow`, and no ask rules. Generic `git push` does not prompt. Deny still applies. The red lines in `AGENTS.md` still wait for a yes. Gitignored `local.json` may set the key false; `setup.sh` merges that into the live tools only. Missing `local.json` means the committed true.
- `allow` runs without a prompt, `ask` always requests approval, and `deny` blocks. With autonomy off, generic `git push` has explicit `ask` rules; `bash ~/.agents/sync.sh` is the narrow, verified exception.
- Deny `rm -rf` is exact `/`, `~`, `$HOME` only. Never `rm -rf /*` / `~/*` / `$HOME/*`: `*` is a glob in Claude, Grok, and OpenCode, so those rules match every recursive delete under `/` or home. Vigil's rm-root classifier owns wiping `/` or `$HOME` including a trailing `/*`.
- Allowlist still lists common safe commands so that if `bash_without_prompt` is flipped off, day-to-day work stays quiet. Per-project one-offs remain project-local; global generated permission buckets are replaced from canonical on setup.

### `defaults.edit_without_prompt` + `defaults.bash_without_prompt`

Same canonical file, `defaults` block. `edit_without_prompt` is **true**. `bash_without_prompt` is **true**. The opinionated default is on. A gitignored `local.json` may turn either flag off. A value is `true` or `false` without quotes; `setup.sh` stops on anything else. `setup.sh` fans the effective value out in steps 5b/5c/5d; `verify.sh` checks the live tools against that merge. See `README.md`.

| Flag | Claude Code | Grok | OpenCode |
|------|-------------|------|----------|
| `edit_without_prompt` | `defaultMode = "acceptEdits"` (only if Bash flag false) | `[ui] permission_mode = "acceptEdits"` | `permission.edit = "allow"` |
| `bash_without_prompt` | `defaultMode = "bypassPermissions"` (**wins** over acceptEdits) | `[ui] permission_mode = "always-approve"` | `permission.bash["*"] = "allow"` (ask omitted) + `permission.external_directory = "allow"` |

**Why the Bash flag exists:** Claude's allowlist cannot remove some hard-coded safety prompts. `bypassPermissions` kills those prompts, but also kills the generic-push review gate. This repo ships the flag **true**. That is the direction. `local.json` is only an opt-out.

With the effective flag true, setup does **not** copy ask rules into any tool — that is what makes generic `git push` prompt-free (an explicit ask rule can still prompt in Claude, in Grok always-approve, and through OpenCode last-match). Deny still copies. Claude deny rules block in every mode, `bypassPermissions` included. The red lines in `AGENTS.md` still wait for a yes.

### Compound commands (when bash_without_prompt is false)

A pipeline or `;`/`&&`/`||` chain is approved only if **each** segment matches a rule. One unlisted segment prompts the whole line. Fix: allowlist the missing segment, or split the probe.

### Prompts an allowlist cannot remove (Claude)

Even with a full allowlist, Claude still prompts for: obfuscation/parse verdicts (heredoc f-strings — mitigated by PreToolUse `heredoc-rewrite` hook), exec wrappers (`watch`, `setsid`, `find -exec`), env runners (`npx`, `docker exec`), and hard-coded compound safety (cd+write, cd+git). **`bash_without_prompt → bypassPermissions` is the fix for those.** Prefer script files over heredocs regardless — reusable, no parse-verdict class.

Wrappers stripped before matching: `timeout`, `time`, `nice`, `nohup`, `stdbuf`, `command`, `builtin`, bare `xargs`. Interpreter **paths** are not normalized — venv paths need their own rules (in the canonical file).
