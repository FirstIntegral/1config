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

# --- a foreign checkout keeps our notes out, also in a linked worktree ---------
# In a linked worktree .git is a file. The exclude file is in the main
# repository's git directory, and that is where the block has to land.
FORK='git@github.com:fixture-owner/omalauncher.git'
main="$(new_work)"
forkbare="$(new_bare "$main" "$FORK")"
git -C "$main" remote add origin "$FORK"
wt="$(mktemp -d -p "$T")/wt"
git -C "$main" worktree add -q -b feat "$wt"
echo more >> "$wt/a.txt"
echo notes > "$wt/AGENTS.md"
mkdir -p "$wt/docs" && echo adr > "$wt/docs/DECISIONS.md"
run_cp "$wt" -m wt
names="$(git -C "$wt" show --name-only --format= HEAD 2>/dev/null)"
if [ "$RC" -eq 0 ] && printf '%s\n' "$names" | grep -qx a.txt \
   && ! printf '%s\n' "$names" | grep -qx AGENTS.md \
   && ! printf '%s\n' "$names" | grep -qx docs/DECISIONS.md \
   && grep -qx '/AGENTS.md' "$main/.git/info/exclude" 2>/dev/null \
   && [ -z "$(git -C "$forkbare" log --all --format=%H -- AGENTS.md docs/DECISIONS.md)" ]; then
  pass "a linked worktree of a foreign fork keeps our notes out of the push"
else
  fail "a linked worktree of a foreign fork published our notes (exit $RC)"
fi

# The block could not be written. Saying "exclude updated" and going on would
# publish the files the block was meant to hide.
w="$(new_work)"
forkbare="$(new_bare "$w" "$FORK")"
git -C "$w" remote add origin "$FORK"
rm -rf "$w/.git/info" && : > "$w/.git/info"
echo more >> "$w/a.txt"
echo notes > "$w/AGENTS.md"
before="$(git -C "$w" rev-parse HEAD)"
run_cp "$w" -m blocked
if [ "$RC" -eq 20 ] && [ "$(git -C "$w" rev-parse HEAD)" = "$before" ] && [ "$(commits "$forkbare")" -eq 0 ]; then
  pass "an exclude block that cannot be written stops the checkpoint (exit 20)"
else
  fail "checkpoint went on without its exclude block (exit $RC)"
fi

# Exit 15 is the listed fork with our file already tracked. A push URL of
# another owner is exit 14: the commit is made and nothing is pushed.
w="$(new_work)"
theirs="$(new_bare "$w" "$THEIRS")"
echo theirs > "$w/AGENTS.md"
git -C "$w" add AGENTS.md && git -C "$w" commit -qm "their rules"
git -C "$w" remote add origin "$THEIRS"
echo more >> "$w/a.txt"
run_cp "$w" -m local
if [ "$RC" -eq 14 ] && [ "$(git -C "$w" rev-list --count HEAD)" -eq 3 ] && [ "$(commits "$theirs")" -eq 0 ]; then
  pass "a tracked AGENTS.md in another owner's repo is exit 14, committed and not pushed"
else
  fail "a tracked AGENTS.md in another owner's repo (exit $RC, wanted 14)"
fi

# --- the Sites rule is enforced, not only written down --------------------------
site_case() {
  local label="$1" want="$2" file="$3" ignore="$4" home site bare
  home="$(mktemp -d -p "$T")"
  site="$home/Projects/sites/demo"
  mkdir -p "$site"
  git init -q "$site"
  printf 'session_compact.md\n%s\n' "$ignore" > "$site/.gitignore"
  echo page > "$site/index.html"
  git -C "$site" add -A && git -C "$site" commit -qm page
  bare="$(new_bare "$site" "$OURS")"
  git -C "$site" remote add origin "$OURS"
  echo rules > "$site/$file"
  echo more >> "$site/index.html"
  RC=0
  OUT="$(HOME="$home" bash "$CP" "$site" -m site 2>&1)" || RC=$?
  if [ "$RC" -eq "$want" ] && [ -z "$(git -C "$bare" log --all --format=%H -- "$file" 2>/dev/null)" ]; then
    pass "$label (exit $want)"
  else
    fail "$label (exit $RC, wanted $want)"
  fi
}
site_case "a site with an unignored AGENTS.md is refused" 20 AGENTS.md ''
site_case "a site with an unignored CLAUDE.md is refused" 20 CLAUDE.md ''
site_case "a site that ignores AGENTS.md is pushed without it" 0 AGENTS.md 'AGENTS.md'

# --- a secret scan that did not run is not a clean scan -------------------------
w="$(new_work)"
ours="$(new_bare "$w" "$OURS")"
git -C "$w" remote add origin "$OURS"
echo two > "$w/b.txt"
stub="$(mktemp -d -p "$T")"
printf '#!/bin/sh\nexit 3\n' > "$stub/python3"
chmod +x "$stub/python3"
before="$(git -C "$w" rev-parse HEAD)"
RC=0
OUT="$(PATH="$stub:$PATH" bash "$CP" "$w" -m unscanned 2>&1)" || RC=$?
if [ "$RC" -eq 20 ] && [ "$(git -C "$w" rev-parse HEAD)" = "$before" ] && [ "$(commits "$ours")" -eq 0 ]; then
  pass "a secret scan that did not run stops the checkpoint (exit 20)"
else
  fail "checkpoint committed without a secret scan (exit $RC)"
fi

# --- a git state that is not ready for a commit --------------------------------
OURS2='git@github.com:fixture-owner/app2.git'

# Mid-merge: `git add -A` would commit the conflict markers.
w="$(new_work)"
ours="$(new_bare "$w" "$OURS")"
git -C "$w" remote add origin "$OURS"
git -C "$w" push -qu origin main 2>/dev/null
git -C "$w" checkout -q -b side
echo side > "$w/a.txt" && git -C "$w" commit -qam side
git -C "$w" checkout -q main
echo main > "$w/a.txt" && git -C "$w" commit -qam main
git -C "$w" merge -q side >/dev/null 2>&1
before="$(git -C "$w" rev-parse HEAD)"
run_cp "$w" -m midmerge
if [ "$RC" -eq 16 ] && [ "$(git -C "$w" rev-parse HEAD)" = "$before" ] \
   && [ -f "$w/.git/MERGE_HEAD" ] && [ "$(commits "$ours")" -eq 1 ]; then
  pass "a merge in progress stops the checkpoint and is left as it was (exit 16)"
else
  fail "checkpoint committed in the middle of a merge (exit $RC)"
fi

# Mid-rebase.
w="$(new_work)"
git -C "$w" checkout -q -b side
echo side > "$w/a.txt" && git -C "$w" commit -qam side
git -C "$w" checkout -q main
echo main > "$w/a.txt" && git -C "$w" commit -qam main
git -C "$w" checkout -q side
git -C "$w" rebase main >/dev/null 2>&1
before="$(git -C "$w" rev-parse HEAD)"
run_cp "$w" -m midrebase
if [ "$RC" -eq 16 ] && [ "$(git -C "$w" rev-parse HEAD)" = "$before" ] \
   && [ -d "$w/.git/rebase-merge" ] && grep -q '<<<<<<<' "$w/a.txt"; then
  pass "a rebase in progress stops the checkpoint and is left as it was (exit 16)"
else
  fail "checkpoint committed in the middle of a rebase (exit $RC)"
fi

# Detached HEAD: a commit there is on no branch, and the push has no name for it.
w="$(new_work)"
ours="$(new_bare "$w" "$OURS")"
git -C "$w" remote add origin "$OURS"
git -C "$w" push -qu origin main 2>/dev/null
git -C "$w" checkout -q --detach
echo two > "$w/b.txt"
before="$(git -C "$w" rev-parse HEAD)"
run_cp "$w" -m detached
if [ "$RC" -eq 16 ] && [ "$(git -C "$w" rev-parse HEAD)" = "$before" ] && [ -f "$w/b.txt" ] \
   && [ -z "$(git -C "$w" ls-files b.txt)" ]; then
  pass "a detached HEAD stops the checkpoint and commits nothing (exit 16)"
else
  fail "checkpoint committed on a detached HEAD (exit $RC)"
fi

# --- "already current" is about the push remote, as the server has it now -------
# A commit that only another remote has is not backed up on the push remote.
w="$(new_work)"
ours="$(new_bare "$w" "$OURS")"
other="$(new_bare "$w" "$OURS2")"
git -C "$w" remote add origin "$OURS"
git -C "$w" remote add backup "$OURS2"
git -C "$w" push -qu origin main 2>/dev/null
echo two > "$w/b.txt" && git -C "$w" add -A && git -C "$w" commit -qm two
git -C "$w" push -q backup main 2>/dev/null
run_cp "$w"
if [ "$RC" -eq 0 ] && [ "$(commits "$ours")" -eq 2 ]; then
  pass "a commit that only another remote has is still pushed to the push remote"
else
  fail "a commit on another remote counted as pushed (exit $RC, push remote has $(commits "$ours"))"
fi

# The branch is gone on the server. The local tracking ref still names it.
w="$(new_work)"
ours="$(new_bare "$w" "$OURS")"
git -C "$w" remote add origin "$OURS"
git -C "$w" push -q origin main 2>/dev/null
git -C "$w" checkout -q -b feat
echo feat > "$w/f.txt" && git -C "$w" add -A && git -C "$w" commit -qm feat
git -C "$w" push -qu origin feat 2>/dev/null
git -C "$ours" update-ref -d refs/heads/feat
run_cp "$w"
if [ "$RC" -eq 0 ] && git -C "$ours" rev-parse -q --verify refs/heads/feat >/dev/null; then
  pass "a branch the server no longer has is pushed again, not called current"
else
  fail "a stale tracking ref made the checkpoint say current (exit $RC)"
fi

# --- a notes failure does not replace the project's own exit --------------------
# A scratch copy of the hooks with a notes script that always fails.
fake="$(mktemp -d -p "$T")"
mkdir -p "$fake/hooks"
cp "$HOOKS/checkpoint.sh" "$HOOKS/git-url.sh" "$HOOKS/brain-remote.sh" "$HOOKS/secret-scan.sh" "$fake/hooks/"
printf '#!/bin/sh\necho "notes: failed" >&2\nexit 7\n' > "$fake/hooks/notes-sync.sh"
w="$(new_work)"
git -C "$w" remote add origin "$T/no-such-remote.git"
echo two > "$w/b.txt"
RC=0
OUT="$(bash "$fake/hooks/checkpoint.sh" "$w" -m offline 2>&1)" || RC=$?
if [ "$RC" -eq 13 ] && printf '%s\n' "$OUT" | grep -q 'notes sync failed (exit 7)'; then
  pass "an unreachable remote stays exit 13 when the notes sync also fails"
else
  fail "a notes failure replaced the project's exit (exit $RC, wanted 13)"
fi
w="$(new_work)"
ours="$(new_bare "$w" "$OURS")"
git -C "$w" remote add origin "$OURS"
echo two > "$w/b.txt"
RC=0
OUT="$(bash "$fake/hooks/checkpoint.sh" "$w" -m pushed 2>&1)" || RC=$?
if [ "$RC" -eq 21 ] && [ "$(commits "$ours")" -eq 2 ]; then
  pass "a notes failure after a good push is exit 21, and the push stays"
else
  fail "a notes failure after a good push (exit $RC, wanted 21)"
fi

[ "$fails" -eq 0 ]
