# Commit signing: how the key is unlocked

Read when: a signed commit fails, or the task is the GPG key, its passphrase, or a commit made on github.com.

## Unlock

- **Unlock is attempted automatically** — passphrase lives in a dedicated gnome-keyring collection labelled `gpg-signing` (empty master so autologin can read it; **not** the default collection). Default unencrypted keyrings get bricked across reboot when another app stores a multiline secret (gnome-keyring then logs `invalid or unrecognized format` and Secret Service is empty). `~/.agents/hooks/gpg-agent-unlock.sh` test-signs; if the agent is empty it fetches over D-Bus (unlocked **and** locked items), and if the live daemon has nothing it scans on-disk `*.keyring` files and restocks the dedicated collection. Then `--pinentry-mode loopback`. Boot dashboard runs this **first** at graphical login (before slow tool-update waits).
- **Git never pops pinentry.** `setup.sh` sets `git config --global gpg.program` to `~/.agents/hooks/gpg-git.sh`. That wrapper signs with `--pinentry-mode loopback`; on cache miss it runs the unlock hook and retries. A cold agent must fail closed and restock, not open `pinentry-gnome3`.
- One-time setup on a fresh machine (prompts once): `bash ~/.agents/hooks/gpg-store-passphrase.sh`
- If automated unlock still fails (nothing stored, passphrase changed): re-run the store script, or manual fallback in a real terminal: `export GPG_TTY=$(tty); echo x | gpg --pinentry-mode loopback -u "$(git config --global --get user.signingkey)" --clearsign -o /dev/null` (prompts, caches). Then retry the commit. Signing key is `$GPG_SIGNING_KEY` or `git config --global user.signingkey` — never another machine's key id.
- A commit made on github.com is signed by `GitHub <noreply@github.com>` with key `968479A1AFF927E37D1A566BB5690EEEBB952194`. `setup.sh` imports `hooks/github-web-flow.asc` and does not set ownertrust, so a good signature stays `%G?` = `U`. Leave that commit in place.
