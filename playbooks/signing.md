# Commit signing: when a signature fails

Read when: a signed commit fails, or the task is the GPG key, its passphrase, or a commit made on github.com.

## The key and the check

- The signing key is `$GPG_SIGNING_KEY`, otherwise `git config --global user.signingkey` (`hooks/gpg-signing-key.sh`). Never another machine's key id.
- git calls `gpg` itself. Nothing in 1config stores a passphrase or types one. Until 2026-11-21 a wrapper and three keyring hooks did; they are gone, and `setup.sh` unsets a `gpg.program` that still points at the old wrapper.
- `bash ~/.agents/hooks/gpg-sign-check.sh` makes one test signature with pinentry turned off. Exit `0`: a commit signs with no prompt. Exit `1`: the key needs a passphrase that gpg-agent does not hold. Exit `3`: no signing key is set, or its secret key is not in this keyring.

## When a signed commit fails

1. Run the check and read its exit code. Do not retry the commit in a loop, and never bypass signing.
2. Exit `1`: stop and tell the user. Only a person can type the passphrase. In a real terminal: `export GPG_TTY=$(tty); echo x | gpg -u "$(git config --global --get user.signingkey)" --clearsign -o /dev/null`. gpg-agent then holds it, and the commit can be made again. A key with no passphrase never reaches this state; the owner's machines use one (`docs/DECISIONS.md`, "Signing: the same key, with no passphrase").
3. Exit `3`: stop and name what is missing. `bash ~/.agents/setup.sh --preflight` prints the fix.
4. Exit `0` and the commit still fails: the cause is not the key. Read git's own error.

## A commit made on github.com

- A commit made on github.com is signed by `GitHub <noreply@github.com>` with key `968479A1AFF927E37D1A566BB5690EEEBB952194`. `setup.sh` imports `hooks/github-web-flow.asc` and does not set ownertrust, so a good signature stays `%G?` = `U`. Leave that commit in place.
