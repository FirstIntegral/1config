# Security

1config installs rules, permission settings, and scripts for four AI coding tools, and it updates itself from GitHub at login. Two things are worth an attacker's time: the repository, because what it holds runs on every machine that follows it, and the agents, because by default they run shell commands without asking.

This file says which guards exist, what they do not cover, and how to report a hole. The decisions behind each choice are in [`docs/DECISIONS.md`](docs/DECISIONS.md).

## Report a vulnerability

Do not put the details in a public issue. Use **Security → Report a vulnerability** on the GitHub repository when GitHub offers that button. When it does not, open an issue that says only that you have a security report, and wait for a private channel.

Say what you ran, on which commit, and what happened. A proof against a scratch `HOME` is enough. Do not test against a machine or an account that is not yours.

This is one person's configuration repository. There is no bounty and no promised response time. The supported version is `main`.

## What runs, and when

| When | What runs |
|---|---|
| `bash ~/.agents/setup.sh` | Writes the four rules symlinks, the permission lists and modes in three tool configs, two Claude hooks, the guard and updater schedule, a login autostart entry, and `git config --global gpg.program`. `setup.sh --dry-run` prints the whole list. |
| Every graphical login | The boot dashboard: `hooks/brain-sync.sh` fetches and fast-forwards this checkout, `setup.sh` runs when that pull moved it, then `verify.sh`. |
| Daily, and two minutes after login | The guards: symlink check, stray merge (one headless model call with no tools), memory-residue check. |
| Login and resume | The updater, for the CLIs that mise does not manage. |
| Inside an agent session | The rules in `AGENTS.md`, and the scripts those rules name: `sync.sh`, `hooks/checkpoint.sh`, `hooks/notes-sync.sh`. |

All of it runs as the user. `setup.sh` never calls `sudo`. The one root-owned file is the optional resume shim, installed by hand with `sudo install`; it starts the updater as the logged-in user and does not run a user-owned script as root.

## Threat model

### Guards

| Threat | Guard | Limit |
|---|---|---|
| A push credential alone (a stolen `gh` token, a hijacked browser session) puts a commit on `main`, and every machine runs it at the next login. | `hooks/verify-incoming.sh`. The login pull and `sync.sh` take a fast-forward only when each first-parent commit is signed by a fingerprint in `BRAIN_SIGNERS` or by this machine's own signing key. The fetch URL must be on `BRAIN_REMOTE`. A commit made on github.com carries GitHub's web-flow signature: it is a warn and is not installed. An unsigned or unlisted commit is a fail. | Whoever holds a listed signing key ships code to every machine. A side branch is vouched for by the signed merge that brought it in. |
| A pull request that changes a script is merged after a skim. | CI (`.github/workflows/ci.yml`) runs `verify.sh --repo`, ShellCheck, and the fixtures on every pull request, with a read-only token and no secret. A merge made on github.com is web-flow signed, so no machine installs it until someone pulls it by hand. | CI shows that the fixtures pass. It does not judge intent. |
| A credential is committed to this public repository, or to a project by a checkpoint. | `hooks/secret-scan.sh` runs before every brain commit and every checkpoint. Token shapes and private-key blocks stop the commit, and `gitleaks` joins in when it is installed. A checkpoint also refuses an untracked file whose name says secret (`.env`, `*.pem`, a keystore), an untracked file over 50 MB, and the session files. | The patterns know a fixed list of shapes. Only added lines are scanned. History is not, and a secret that is already tracked is not flagged again. |
| A checkpoint pushes private notes to a repository that is not the owner's. | The push URL's host and owner must be on a `BRAIN_REMOTE` line, after ssh aliases and `insteadOf` are resolved. Otherwise the commit stays local and the script exits 14. On a foreign checkout the private files go into `.git/info/exclude`. | A URL the parser cannot read is not vetoed. |
| A stray rules file carries text aimed at the model that merges it. | The merge model runs with no tools, so text in the stray cannot make it run a command. The reply is capped in size, and a reply that contains a retired name from `hooks/kill-tokens.deny` is not appended. | The merge is automatic. What the model returns is appended to `AGENTS.md` before a person reads it, and every later session loads that file. The append leaves the work tree dirty; the 1config panel and `1config status` show that. Nothing publishes it until the next `sync.sh`, and that diff is the place to read it. |
| A downloaded installer is swapped. | `hooks/install-elan.sh` and `skills/research-loop/orx-install.sh` pin a version and its sha256 and run nothing on a mismatch. `vendor/jeepney` is a pinned copy with its licence. Each adopted skill records the upstream commit it came from. | The tool updater takes what each vendor's update channel serves. A checksum it compares comes from that same channel. |
| A tool config is edited so that a rule disappears. | `setup.sh` rewrites the permission lists from `permissions.json`, `verify.sh` fails on drift, and the symlink guard re-links the rules file. | The drift is found at the next setup, verify, login, or guard run, not at the moment it happens. |

### Not defended, on purpose

1. **Agents run shell commands without a prompt.** `bash_without_prompt` ships `true`: Claude Code `bypassPermissions`, Grok `always-approve`, OpenCode `"*": "allow"`. Text an agent reads can steer it: a web page, a dependency's README, an issue, a file in a cloned repository. The command it then runs has the user's rights, which include the files, the ssh keys, the tokens, and the signing key. The deny list is short (`rm -rf /`, `rm -rf ~`, `rm -rf $HOME`, `sudo rm *`, `mkfs*`, `dd if=* of=/dev/*`). It stops a slip, not an adversary. The red lines in `AGENTS.md` are instructions to a model, not enforcement. To opt out, set `"bash_without_prompt": false` in `local.json`, or run the tools inside a sandbox, a container, or a VM. Vigil, a separate repository, puts a human approval in front of some commands on the machines that run it; 1config neither installs it nor depends on it.
2. **A signature means "made on one of the owner's machines". It does not mean "a person approved this".** The GPG passphrase is kept in a gnome-keyring collection with an empty master password so that an unattended login can sign, and gpg-agent caches it for a year. Any process that runs as the user can sign, an agent included. The signature gate therefore stops an attacker who holds only a push credential. It does not stop one who runs code on a machine that signs. Disk encryption protects the key at rest.
3. **Each machine trusts every machine that holds a listed key.** One compromised machine can push a signed commit, and the others install it at their next login.
4. **GitHub settings are not managed from here.** Branch protection, required signatures, secret scanning, and push protection are repository settings. No guard above assumes that any of them is on.
5. **Machine notes are private, not encrypted.** `hooks/notes-sync.sh` copies untracked notes to the private repository named in `NOTES_REMOTE`: `session_compact.md`, a local `AGENTS.md`, `docs/DECISIONS.md`, and the paths in `notes.allow`. It refuses secret-looking names. It does not scan content. Whoever can read that repository can read the notes.
6. **The fix button is a prompt.** The lines in the boot slip become the prompt of a `grok` session when the owner presses Fix with Grok in the panel. The dashboard's own checks write those lines. A line can carry a file name, or the last line a sync script printed.
7. **A model's judgement.** The rules about red lines, force-push, and drafts before replies are followed by a language model. They fail the way a model fails.

### Out of scope

- An attacker who already runs code as the user or as root. That attacker can read the keyring, edit the tool configs, and sign.
- Physical access to an unlocked session.
- The AI vendors' services, CLIs, and update servers.
- A fork, and the changes its owner made.

## Look before you install

- `bash ~/.agents/setup.sh --dry-run` prints the diff of every tool config it would write and lists the other steps. It changes nothing.
- `bash ~/.agents/uninstall.sh` prints what it would remove. `--yes` removes it. `--restore-configs` puts back the oldest tool configs that `setup.sh` saved.
- `local.json` turns Bash autonomy off for one machine. See `local.json.example`.
- A fork replaces `BRAIN_REMOTE`, `BRAIN_SIGNERS`, `NOTES_REMOTE`, and `fork-parents.txt`. Take out of `BRAIN_SIGNERS` every fingerprint you do not control: a listed key can ship code to your machines. With an empty list, a login pull takes only commits signed by that machine's own key.
