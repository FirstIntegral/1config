#!/usr/bin/env bash
# trust-test.sh — fixtures for the signature gate around a pull.
#
#   bash hooks/trust-test.sh
#
# hooks/brain-sync.sh, sync.sh (its first step only), hooks/verify-incoming.sh,
# hooks/gpg-git.sh, and the dots gate of boot-dashboard/dashboard.sh, against
# scratch repositories whose commits are signed for real by throwaway keys.
# One line per case: `ok <what>` or `FAIL <what>`. Exit 1 when any case fails.
# verify.sh replays the lines. No network, and no key of this machine is used.
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")" && pwd -P)"
ROOT="$(cd "$HOOKS/.." && pwd -P)"
T="$(mktemp -d)"
cleanup() {
  for d in "$T"/gnupg*; do
    [ -d "$d" ] && gpgconf --homedir "$d" --kill all >/dev/null 2>&1
  done
  rm -rf "$T"
}
trap cleanup EXIT

fails=0
pass() { echo "ok $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

command -v gpg >/dev/null 2>&1 || { echo "FAIL the trust fixtures need gpg"; exit 1; }

printf '%s\n' '[user]' '	name = verify' '	email = verify@local' \
  '[init]' '	defaultBranch = main' '[commit]' '	gpgsign = false' \
  '[tag]' '	gpgSign = false' > "$T/gitconfig"
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GPG_SIGNING_KEY

# K1 is a listed signer. K2 is not.
GH="$T/gnupg"
mkdir -m 700 "$GH"
newkey() {  # newkey HOME UID -> fingerprint
  GNUPGHOME="$1" gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
    --quick-generate-key "$2" ed25519 sign never >/dev/null 2>&1 || true
  GNUPGHOME="$1" gpg --batch --list-secret-keys --with-colons "$2" 2>/dev/null \
    | awk -F: '$1 == "fpr" { print $10; exit }'
}
K1="$(newkey "$GH" 'fixture-one <one@fixture.invalid>')"
K2="$(newkey "$GH" 'fixture-two <two@fixture.invalid>')"
[ -n "$K1" ] && [ -n "$K2" ] || { echo "FAIL the trust fixtures could not make their keys"; exit 1; }
printf '%s\n' "$K1" > "$T/signers"

# commit REPO KEY|- MESSAGE [GNUPGHOME]
commit() {
  local repo="$1" key="$2" msg="$3" home="${4:-$GH}"
  printf '%s\n' "$msg" >> "$repo/f-$RANDOM.txt"
  git -C "$repo" add -A
  if [ "$key" = "-" ]; then
    git -C "$repo" commit -q -m "$msg"
  else
    GNUPGHOME="$home" git -C "$repo" -c user.signingkey="$key" commit -q -S -m "$msg"
  fi
}

# A scratch brain: an origin, a seed clone that pushes to it, and the checkout under test.
new_brain() {
  local r
  r="$(mktemp -d -p "$T")"
  git init -q --bare -b main "$r/origin.git"
  git init -q -b main "$r/seed"
  git -C "$r/seed" remote add origin "$r/origin.git"
  commit "$r/seed" "$K1" seed
  git -C "$r/seed" push -q origin main
  git clone -q "$r/origin.git" "$r/brain"
  printf '%s\n' "$r/origin.git" > "$r/brain/BRAIN_REMOTE"
  printf '%s\n' BRAIN_REMOTE > "$r/brain/.git/info/exclude"
  printf '%s\n' "$r"
}
head_of() { git -C "$1/brain" rev-parse refs/heads/main; }
# bsync ROOT — brain-sync.sh on the scratch brain. Exit code in RC, output in OUT.
bsync() {
  RC=0
  OUT="$(env AGENTS_HOME="$1/brain" GNUPGHOME="$GH" BRAIN_SIGNERS_FILE="$T/signers" \
    bash "$HOOKS/brain-sync.sh" 2>&1)" || RC=$?
}
# sync1 ROOT — sync.sh up to the end of its first step (it stops there in every case below).
sync1() {
  RC=0
  OUT="$(env AGENTS_HOME="$1/brain" GNUPGHOME="$GH" BRAIN_SIGNERS_FILE="$T/signers" \
    AGENTS_UPDATE_LOCK_HELD=1 bash "$ROOT/sync.sh" --no-setup -m fixture 2>&1)" || RC=$?
}

# --- a tag named like the branch must not stand in for it -----------------------
# The remote carries a tag `main` on an unsigned commit that is also the branch tip.
r="$(new_brain)"
commit "$r/seed" - "unsigned push"
git -C "$r/seed" tag main
git -C "$r/seed" push -q origin refs/heads/main refs/tags/main 2>/dev/null
before="$(head_of "$r")"
bsync "$r"
if [ "$RC" -eq 6 ] && [ "$(head_of "$r")" = "$before" ] && ! git -C "$r/brain" rev-parse -q --verify refs/tags/main >/dev/null; then
  pass "login pull: a remote tag named main does not hide an unsigned commit (exit 6, no tag taken)"
else
  fail "login pull: a remote tag named main hid an unsigned commit (exit $RC: $OUT)"
fi
sync1 "$r"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q 'not signed by a listed key' && [ "$(head_of "$r")" = "$before" ]; then
  pass "sync.sh: a remote tag named main does not hide an unsigned commit"
else
  fail "sync.sh: a remote tag named main hid an unsigned commit (exit $RC)"
fi

# A local tag `main` on an old commit. The branch must still follow a signed push.
r="$(new_brain)"
git -C "$r/brain" tag main
commit "$r/seed" "$K1" "signed update"
git -C "$r/seed" push -q origin main
bsync "$r"
if [ "$RC" -eq 0 ] && [ "$(head_of "$r")" = "$(git -C "$r/origin.git" rev-parse refs/heads/main)" ]; then
  pass "login pull: a local tag named main does not stop the branch from following a signed push"
else
  fail "login pull: a local tag named main was read in place of the branch (exit $RC: $OUT)"
fi

# --- diverged: the script must not hand out a merge command for unchecked commits
r="$(new_brain)"
commit "$r/brain" "$K1" "local work"
commit "$r/seed" - "unsigned push"
git -C "$r/seed" push -q origin main
before="$(head_of "$r")"
bsync "$r"
if [ "$RC" -eq 6 ] && [ "$(head_of "$r")" = "$before" ] && printf '%s\n' "$OUT" | grep -q 'unsigned'; then
  pass "login pull: diverged with an unsigned commit on origin is a refusal (exit 6), not 'merge by hand'"
else
  fail "login pull: diverged with an unsigned commit on origin was not refused (exit $RC: $OUT)"
fi
sync1 "$r"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q 'not signed by a listed key' \
   && ! printf '%s\n' "$OUT" | grep -q 'merge by hand, then re-run'; then
  pass "sync.sh: diverged with an unsigned commit on origin prints no merge command"
else
  fail "sync.sh: diverged with an unsigned commit on origin still says merge by hand (exit $RC)"
fi
r="$(new_brain)"
commit "$r/brain" "$K1" "local work"
commit "$r/seed" "$K1" "signed push"
git -C "$r/seed" push -q origin main
bsync "$r"
if [ "$RC" -eq 4 ]; then
  pass "login pull: diverged with signed commits on origin stays exit 4"
else
  fail "login pull: diverged with signed commits on origin (exit $RC, wanted 4)"
fi

# --- this machine's own key is a key it holds the secret half of ----------------
# A public key with the same email, imported first, must not count as "ours".
GH2="$T/gnupg-other"
GH3="$T/gnupg-mine"
mkdir -m 700 "$GH2" "$GH3"
LOOK="$(newkey "$GH2" 'look-alike <me@fixture.invalid>')"
GNUPGHOME="$GH2" gpg --batch --armor --export "$LOOK" > "$T/look.asc" 2>/dev/null
GNUPGHOME="$GH3" gpg --batch --import "$T/look.asc" >/dev/null 2>&1
MINE="$(newkey "$GH3" 'really-me <me@fixture.invalid>')"
g="$(mktemp -d -p "$T")"
git init -q -b main "$g"
commit "$g" "$MINE" base "$GH3"
base="$(git -C "$g" rev-parse HEAD)"
commit "$g" "$LOOK" "signed by the look-alike" "$GH2"
tip="$(git -C "$g" rev-parse HEAD)"
: > "$T/no-signers"
RC=0
OUT="$(env GNUPGHOME="$GH3" BRAIN_SIGNERS_FILE="$T/no-signers" GPG_SIGNING_KEY='me@fixture.invalid' \
  bash "$HOOKS/verify-incoming.sh" "$g" "$base" "$tip" 2>&1)" || RC=$?
if [ "$RC" -eq 6 ]; then
  pass "the gate: a public key that shares the signing key's email is not this machine's own key"
else
  fail "the gate: a look-alike public key was accepted as this machine's own key (exit $RC)"
fi
commit "$g" "$MINE" "signed by me" "$GH3"
RC=0
env GNUPGHOME="$GH3" BRAIN_SIGNERS_FILE="$T/no-signers" GPG_SIGNING_KEY='me@fixture.invalid' \
  bash "$HOOKS/verify-incoming.sh" "$g" "$tip" "$(git -C "$g" rev-parse HEAD)" >/dev/null 2>&1 || RC=$?
if [ "$RC" -eq 0 ]; then
  pass "the gate: a commit signed by the key this machine holds is accepted"
else
  fail "the gate: this machine's own signature was refused (exit $RC)"
fi

# --- gpg-git.sh hands back gpg's own exit code ----------------------------------
stub="$(mktemp -d -p "$T")"
printf '#!/bin/sh\nexit 1\n' > "$stub/gpg"
chmod +x "$stub/gpg"
RC=0
printf 'x' | env PATH="$stub:$PATH" AGENTS_HOME="$T/no-brain" bash "$HOOKS/gpg-git.sh" --verify sig - >/dev/null 2>&1 || RC=$?
if [ "$RC" -eq 1 ]; then
  pass "gpg-git.sh: a failed --verify comes back as a failure"
else
  fail "gpg-git.sh: a failed --verify came back as exit $RC"
fi

# --- the dots gate does not open when its fetch fails ---------------------------
d="$(mktemp -d -p "$T")"
git init -q --bare -b main "$d/origin.git"
git init -q -b main "$d/seed"
git -C "$d/seed" remote add origin "$d/origin.git"
commit "$d/seed" "$K1" seed
git -C "$d/seed" push -q origin main
git clone -q "$d/origin.git" "$d/dots"
dgate() {
  RC=0
  OUT="$(env AGENTS_HOME="$ROOT" GNUPGHOME="$GH" BRAIN_SIGNERS_FILE="$T/signers" \
    bash "$ROOT/boot-dashboard/dashboard.sh" --dots-gate "$d/dots" 2>&1)" || RC=$?
}
commit "$d/seed" - "unsigned pack change"
git -C "$d/seed" push -q origin main
dgate
if [ "$RC" -eq 6 ]; then
  pass "dots gate: an unsigned commit on the pack's origin is refused (exit 6)"
else
  fail "dots gate: an unsigned commit was let through (exit $RC: $OUT)"
fi
git -C "$d/dots" remote set-url origin "$d/gone.git"
dgate
if [ "$RC" -eq 1 ]; then
  pass "dots gate: a fetch that fails stops the sync (exit 1), so the pack's own fetch cannot run unchecked"
else
  fail "dots gate: a failed fetch let the sync go on (exit $RC: $OUT)"
fi
git -C "$d/dots" remote set-url origin "$d/origin.git"
git -C "$d/seed" reset -q --hard HEAD~1
commit "$d/seed" "$K1" "signed pack change"
git -C "$d/seed" push -q -f origin main
dgate
if [ "$RC" -eq 0 ]; then
  pass "dots gate: a signed commit passes (exit 0)"
else
  fail "dots gate: a signed commit was refused (exit $RC: $OUT)"
fi

# --- the login pull talks only to a URL on BRAIN_REMOTE -------------------------
r="$(new_brain)"
commit "$r/seed" "$K1" "signed update"
git -C "$r/seed" push -q origin main
printf '%s\n' 'https://example.invalid/someone/else.git' > "$r/brain/BRAIN_REMOTE"
before="$(head_of "$r")"
bsync "$r"
if [ "$RC" -eq 4 ] && [ "$(head_of "$r")" = "$before" ] && printf '%s\n' "$OUT" | grep -q 'not in BRAIN_REMOTE'; then
  pass "login pull: an origin that BRAIN_REMOTE does not list is refused before any fetch (exit 4)"
else
  fail "login pull: pulled from an origin that BRAIN_REMOTE does not list (exit $RC: $OUT)"
fi

# --- gpg-git.sh: loopback always, and one unlock then one retry for a signature -
gg="$(mktemp -d -p "$T")"
mkdir -p "$gg/bin" "$gg/brain/hooks"
cat > "$gg/bin/gpg" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/gpg.calls"
cat >/dev/null
if [ -e "$STUB_DIR/unlocked" ]; then exit 0; fi
exit 2
STUB
printf '#!/bin/sh\n: > "%s/unlocked"\n' "$gg" > "$gg/brain/hooks/gpg-agent-unlock.sh"
chmod +x "$gg/bin/gpg" "$gg/brain/hooks/gpg-agent-unlock.sh"
RC=0
printf 'payload' | env PATH="$gg/bin:$PATH" STUB_DIR="$gg" AGENTS_HOME="$gg/brain" \
  bash "$HOOKS/gpg-git.sh" -bsau KEY >/dev/null 2>&1 || RC=$?
if [ "$RC" -eq 0 ] && [ "$(wc -l < "$gg/gpg.calls")" -eq 2 ] && [ -e "$gg/unlocked" ] \
   && ! grep -qv -- '--pinentry-mode loopback' "$gg/gpg.calls"; then
  pass "gpg-git.sh: a signature that fails runs the unlock once and retries, always in loopback mode"
else
  fail "gpg-git.sh: no unlock and retry, or a call without loopback (exit $RC, $(wc -l < "$gg/gpg.calls" 2>/dev/null) call(s))"
fi
rm -f "$gg/gpg.calls" "$gg/unlocked"
RC=0
printf 'payload' | env PATH="$gg/bin:$PATH" STUB_DIR="$gg" AGENTS_HOME="$gg/brain" \
  bash "$HOOKS/gpg-git.sh" --verify sig - >/dev/null 2>&1 || RC=$?
if [ "$RC" -ne 0 ] && [ "$(wc -l < "$gg/gpg.calls")" -eq 1 ] && [ ! -e "$gg/unlocked" ]; then
  pass "gpg-git.sh: a failed --verify is an answer: no unlock, no retry"
else
  fail "gpg-git.sh: a failed --verify ran the unlock or was retried (exit $RC)"
fi

# --- the signing key is the one this machine is told about, never a built-in id -
sk="$(mktemp -d -p "$T")"
: > "$sk/gitconfig"
got="$(env GPG_SIGNING_KEY=0xAAAA1111 GIT_CONFIG_GLOBAL="$sk/gitconfig" bash "$HOOKS/gpg-signing-key.sh" 2>/dev/null)"
git config --file "$sk/gitconfig" user.signingkey BBBB2222
got2="$(env -u GPG_SIGNING_KEY GIT_CONFIG_GLOBAL="$sk/gitconfig" bash "$HOOKS/gpg-signing-key.sh" 2>/dev/null)"
: > "$sk/empty"
RC=0
got3="$(env -u GPG_SIGNING_KEY GIT_CONFIG_GLOBAL="$sk/empty" bash "$HOOKS/gpg-signing-key.sh" 2>/dev/null)" || RC=$?
if [ "$got" = "AAAA1111" ] && [ "$got2" = "BBBB2222" ] && [ -z "$got3" ] && [ "$RC" -eq 3 ]; then
  pass "gpg-signing-key.sh: the key is GPG_SIGNING_KEY, else user.signingkey, else none (exit 3)"
else
  fail "gpg-signing-key.sh: wrong key source (env '$got', config '$got2', none '$got3' exit $RC)"
fi

[ "$fails" -eq 0 ]
