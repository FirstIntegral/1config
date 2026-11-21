#!/usr/bin/env bash
# checkpoint-test.sh — fixtures for hooks/checkpoint.sh.
#
#   bash hooks/checkpoint-test.sh
#
# Each case runs the real script on a scratch repository and judges it by its
# exit code, its output, and what reached the scratch remotes. One line per case:
# `ok <what>` or `FAIL <what>`. Exit 1 when any case fails. verify.sh replays
# the lines. Nothing here reads this machine's git config or touches a network.
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")" && pwd -P)"
CP="$HOOKS/checkpoint.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

printf '%s\n' '[user]' '	name = verify' '	email = verify@local' \
  '[init]' '	defaultBranch = main' '[commit]' '	gpgsign = false' \
  '[tag]' '	gpgSign = false' > "$T/gitconfig"
printf '%s\n' 'https://github.com/fixture-owner/brain.git' \
  'git@github.com:fixture-owner/brain.git' > "$T/brain-remote"
printf '%s\n' 'fixture-owner/omalauncher fixture-parent/omalauncher' > "$T/fork-parents"
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1 GIT_URL_SSH_CONFIG=/dev/null
export BRAIN_REMOTE_FILE="$T/brain-remote" FORK_PARENTS_FILE="$T/fork-parents"
unset GIT_DIR GIT_WORK_TREE

OURS='git@github.com:fixture-owner/app.git'
THEIRS='https://github.com/fixture-parent/app.git'

fails=0
pass() { echo "ok $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

# A work tree with one commit on main, and a .gitignore for the session files.
new_work() {
  local w
  w="$(mktemp -d -p "$T")"
  git init -q "$w"
  printf 'session_compact.md\n' > "$w/.gitignore"
  echo one > "$w/a.txt"
  git -C "$w" add -A && git -C "$w" commit -qm one
  printf '%s\n' "$w"
}

# A bare repository that stands in for the URL in $2, for the work tree in $1.
new_bare() {
  local w="$1" url="$2" b
  b="$(mktemp -d -p "$T")/remote.git"
  git init -q --bare "$b"
  git -C "$w" config "url.$b.insteadOf" "$url"
  printf '%s\n' "$b"
}

commits() { git -C "$1" rev-list --count --all 2>/dev/null || echo 0; }

# Run checkpoint.sh on $1. Leaves the exit code in RC and the output in OUT.
run_cp() {
  local w="$1"; shift
  RC=0
  OUT="$(bash "$CP" "$w" "$@" 2>&1)" || RC=$?
}

# --- the push goes where the owner check looked ---------------------------------
# git's own choice of push remote (remote.pushDefault, branch.<name>.pushRemote)
# is not the remote the owner check read. The push names its remote.
w="$(new_work)"
ours="$(new_bare "$w" "$OURS")"
theirs="$(new_bare "$w" "$THEIRS")"
git -C "$w" remote add origin "$OURS"
git -C "$w" remote add other "$THEIRS"
git -C "$w" push -qu origin main 2>/dev/null
git -C "$w" config remote.pushDefault other
echo two > "$w/b.txt"
run_cp "$w" -m two
if [ "$RC" -eq 0 ] && [ "$(commits "$ours")" -eq 2 ] && [ "$(commits "$theirs")" -eq 0 ]; then
  pass "remote.pushDefault does not move the push to another owner's repo"
else
  fail "remote.pushDefault moved the push (exit $RC, ours $(commits "$ours"), theirs $(commits "$theirs"))"
fi

w="$(new_work)"
ours="$(new_bare "$w" "$OURS")"
theirs="$(new_bare "$w" "$THEIRS")"
git -C "$w" remote add origin "$OURS"
git -C "$w" remote add other "$THEIRS"
git -C "$w" push -qu origin main 2>/dev/null
git -C "$w" config branch.main.pushRemote other
echo two > "$w/b.txt"
run_cp "$w" -m two
if [ "$RC" -eq 0 ] && [ "$(commits "$ours")" -eq 2 ] && [ "$(commits "$theirs")" -eq 0 ]; then
  pass "branch.<name>.pushRemote does not move the push to another owner's repo"
else
  fail "branch.<name>.pushRemote moved the push (exit $RC, ours $(commits "$ours"), theirs $(commits "$theirs"))"
fi

# A remote can carry several push URLs, and a push goes to every one of them.
w="$(new_work)"
ours="$(new_bare "$w" "$OURS")"
theirs="$(new_bare "$w" "$THEIRS")"
git -C "$w" remote add origin "$OURS"
git -C "$w" remote set-url --add --push origin "$THEIRS"
git -C "$w" remote set-url --add --push origin "$OURS"
echo two > "$w/b.txt"
run_cp "$w" -m two
if [ "$RC" -eq 14 ] && [ "$(commits "$ours")" -eq 0 ] && [ "$(commits "$theirs")" -eq 0 ]; then
  pass "a second push URL of another owner is vetoed (exit 14)"
else
  fail "a second push URL of another owner was pushed to (exit $RC, ours $(commits "$ours"), theirs $(commits "$theirs"))"
fi

# An upstream branch with another name still receives the push.
w="$(new_work)"
ours="$(new_bare "$w" "$OURS")"
git -C "$w" remote add origin "$OURS"
git -C "$w" push -q origin main:trunk 2>/dev/null
git -C "$w" fetch -q origin
git -C "$w" branch -q --set-upstream-to=origin/trunk main
echo two > "$w/b.txt"
run_cp "$w" -m two
if [ "$RC" -eq 0 ] && [ "$(git -C "$ours" rev-list --count trunk 2>/dev/null)" = 2 ] \
   && ! git -C "$ours" rev-parse -q --verify refs/heads/main >/dev/null; then
  pass "the push goes to the upstream branch, also when its name differs"
else
  fail "a differently named upstream branch did not get the push (exit $RC)"
fi

[ "$fails" -eq 0 ]
