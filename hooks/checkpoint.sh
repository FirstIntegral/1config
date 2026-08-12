#!/usr/bin/env bash
# checkpoint.sh — the git half of the `checkpoint_project` trigger, as a real script.
#
# Steps 1-5 of that trigger (rewrite session_compact.md, append the transcript wrap-up,
# backfill DECISIONS) need judgement about what happened today and stay with the AI.
# Step 6 is mechanical, has exactly one correct answer per project state, and was being
# re-derived by hand every time -- inconsistently. It lives here instead.
#
#   bash ~/.agents/hooks/checkpoint.sh [PROJECT_DIR] [-m SUBJECT] [--dry-run]
#
# Decides, in order, and stops at the first thing that applies:
#
#   not a git repo                  -> do nothing at all                    (exit 10)
#   dir is not the repo toplevel    -> do nothing at all                    (exit 11)
#   session files not ignored       -> refuse, change nothing               (exit 20)
#   nothing to commit               -> do nothing                           (exit  3)
#   no remote configured            -> commit locally, do not push          (exit 12)
#   remote unreachable / missing    -> commit, do not push                  (exit 13)
#   push fails                      -> commit stays, report                 (exit 21)
#   otherwise                       -> commit + push                        (exit  0)
#
# NEVER, under any circumstance: create a repo, add a remote, create a GitHub repo,
# force-push, rebase, reset, amend, or bypass commit signing. A project without a repo or
# without a remote is in a deliberate state, and a checkpoint is a note-taking action that
# must not change it. Publishing something the user never chose to publish cannot be undone
# by deleting it afterwards.
set -uo pipefail

PROJECT=""
SUBJECT=""
DRY=0

die() { echo "checkpoint: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    -m|--message) [ $# -ge 2 ] || die "$1 needs a value"; SUBJECT="$2"; shift 2 ;;
    --dry-run)    DRY=1; shift ;;
    -h|--help)    sed -n '2,30p' "$0"; exit 0 ;;
    -*)           die "unknown flag: $1" ;;
    *)            [ -z "$PROJECT" ] || die "more than one project path given"; PROJECT="$1"; shift ;;
  esac
done

PROJECT="${PROJECT:-$PWD}"
[ -d "$PROJECT" ] || die "not a directory: $PROJECT"
PROJECT="$(cd "$PROJECT" && pwd -P)"
echo "== checkpoint: $PROJECT"

run() {  # echo and execute, or just echo under --dry-run
  if [ "$DRY" = 1 ]; then echo "  DRY    $*"; return 0; fi
  "$@"
}

# --- 1. is it a repo, and is this directory its root? -------------------------------
TOP="$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$TOP" ]; then
  echo "  repo     none — not a git repository"
  echo "  action   nothing committed, nothing pushed (a checkpoint never runs 'git init')"
  exit 10
fi
if [ "$TOP" != "$PROJECT" ]; then
  # rev-parse walks UP, so it succeeds from any subdirectory. Committing here would sweep
  # an unrelated parent repo's work into this project's checkpoint.
  echo "  repo     $TOP"
  echo "  action   refused — project is INSIDE another repo, not its root; nothing done"
  exit 11
fi
# `branch --show-current` and not `rev-parse --abbrev-ref HEAD`: on a repo with no commits
# yet, rev-parse prints "HEAD" AND exits nonzero, so a `|| echo HEAD` fallback yields the
# two-line value "HEAD\nHEAD".
BRANCH="$(git -C "$PROJECT" branch --show-current 2>/dev/null || true)"
[ -n "$BRANCH" ] || BRANCH="HEAD (detached)"
echo "  repo     $TOP  (branch $BRANCH)"

# --- 2. session files must be ignored before anything is staged ---------------------
# The transcript is the user's private log. A checkpoint that publishes it is the one
# failure here that cannot be walked back, so it is checked before `git add`, not after.
LEAKED=()
for f in session_compact.md session_transcript.md claude_memory_import.md; do
  [ -e "$PROJECT/$f" ] || continue
  if git -C "$PROJECT" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    LEAKED+=("$f (already tracked)")
  elif ! git -C "$PROJECT" check-ignore -q "$f"; then
    LEAKED+=("$f (not gitignored)")
  fi
done
if [ ${#LEAKED[@]} -gt 0 ]; then
  echo "  action   REFUSED — session files would be committed:"
  printf '             %s\n' "${LEAKED[@]}"
  echo "           add them to .gitignore (and 'git rm --cached' if tracked), then re-run."
  exit 20
fi
echo "  session  compact/transcript correctly excluded"

# --- 3. anything to do? -------------------------------------------------------------
# A clean tree is not the same as nothing to do. Commits made earlier in the session and
# never pushed are exactly the state where "the machine is not the only copy" fails, so a
# clean tree still goes through the push path -- it just skips the commit.
#
# `HEAD --not --remotes` counts commits absent from EVERY remote, which answers the
# question for a branch with no upstream as well as for one that has drifted ahead of it.
NOTHING_TO_COMMIT=0
if [ -z "$(git -C "$PROJECT" status --porcelain)" ]; then
  UNPUSHED="$(git -C "$PROJECT" rev-list --count HEAD --not --remotes 2>/dev/null || echo 0)"
  if [ "${UNPUSHED:-0}" -eq 0 ]; then
    echo "  tree     clean — nothing to commit, nothing unpushed"
    exit 3
  fi
  echo "  tree     clean — nothing to commit, but $UNPUSHED commit(s) not on any remote"
  NOTHING_TO_COMMIT=1
else
  echo "  staging  $(git -C "$PROJECT" add -A --dry-run | wc -l) path(s)"
fi

# --- 4. remote: configured? and does it actually exist? -----------------------------
# `git remote get-url --push` is the authority for WHERE to push. An AGENTS.md line is
# documentation and is cross-checked below, never used to authorise a push: git config is
# set by an explicit human action, whereas AGENTS.md is a file an AI writes.
UPSTREAM="$(git -C "$PROJECT" rev-parse --abbrev-ref "@{upstream}" 2>/dev/null || true)"
REMOTE=""
if [ -n "$UPSTREAM" ]; then
  REMOTE="${UPSTREAM%%/*}"
elif git -C "$PROJECT" remote get-url origin >/dev/null 2>&1; then
  REMOTE="origin"
fi

ALL_REMOTES="$(git -C "$PROJECT" remote | tr '\n' ' ')"
if [ -z "$REMOTE" ]; then
  if [ -n "${ALL_REMOTES// /}" ]; then
    # Remotes exist but none is named origin and the branch has no upstream. Guessing which
    # one the user meant is exactly the kind of decision a checkpoint must not make.
    echo "  remote   none usable — no upstream, no 'origin'; found: $ALL_REMOTES"
  else
    echo "  remote   none configured"
  fi
else
  URL="$(git -C "$PROJECT" remote get-url --push "$REMOTE" 2>/dev/null || true)"
  echo "  remote   $REMOTE  $URL"

  # Cross-check against the project's AGENTS.md, if it records one. A mismatch is a warning,
  # never a veto -- git config wins, because it is what push actually uses.
  if [ -f "$PROJECT/AGENTS.md" ]; then
    DOC="$(grep -oE '(git@[A-Za-z0-9._-]+:[A-Za-z0-9._/-]+\.git|https://[A-Za-z0-9._-]+/[A-Za-z0-9._/-]+\.git)' \
           "$PROJECT/AGENTS.md" | head -1 || true)"
    if [ -n "$DOC" ] && [ "$DOC" != "$URL" ]; then
      echo "  WARNING  AGENTS.md records a different remote: $DOC"
      echo "           git config wins. Fix the AGENTS.md line if it is stale."
    elif [ -n "$DOC" ]; then
      echo "  agents   AGENTS.md remote matches"
    fi
  fi

  # Does it exist on the host, and can this key reach it? One call covers both, and works
  # for GitHub, GitLab and self-hosted alike -- nothing here is GitHub-specific.
  #
  # NOT `--exit-code`: that flag reports 2 when no refs MATCH, and a freshly created empty
  # repo has no refs at all. It would call every brand-new GitHub repo unreachable and
  # silently refuse the first push, which is the case this check most needs to get right.
  # Bare `ls-remote` is 0 on contact (even when empty) and 128 when it cannot reach or auth.
  if git -C "$PROJECT" ls-remote "$REMOTE" >/dev/null 2>&1; then
    echo "  reachable yes"
  else
    echo "  reachable NO — remote is configured but missing, renamed, or not writable by this key"
    REMOTE=""
    UNREACHABLE=1
  fi
fi
UNREACHABLE="${UNREACHABLE:-0}"

# --- 5. commit (signed; never bypassed) ---------------------------------------------
SUBJECT="${SUBJECT:-checkpoint: $(date +%F)}"
if [ "$NOTHING_TO_COMMIT" = 1 ]; then
  # Nothing new to record; the work is already committed and only the backup is missing.
  HASH="$(git -C "$PROJECT" rev-parse --short HEAD)"
  echo "  commit   skipped — nothing to commit; pushing $UNPUSHED existing commit(s)"
else
run git -C "$PROJECT" add -A
if [ "$DRY" != 1 ]; then
  if ! git -C "$PROJECT" commit -q -m "$SUBJECT"; then
    # Most likely a locked gpg key. Unlock and retry once -- never --no-gpg-sign.
    echo "  commit   failed; attempting gpg unlock then one retry"
    bash "$HOME/.agents/hooks/gpg-agent-unlock.sh" >/dev/null 2>&1 || true
    git -C "$PROJECT" commit -q -m "$SUBJECT" || {
      echo "  commit   FAILED — not bypassing signing. Unlock the key and re-run."
      exit 21
    }
  fi
  HASH="$(git -C "$PROJECT" rev-parse --short HEAD)"
  SIG="$(git -C "$PROJECT" log -1 --format='%G?')"
  echo "  commit   $HASH  sig=$SIG  $SUBJECT"
  [ "$SIG" = "G" ] || [ "$SIG" = "U" ] || echo "  WARNING  commit is not signed (sig=$SIG)"
else
  run git -C "$PROJECT" commit -m "$SUBJECT"
  HASH="(dry-run)"
fi
fi

# --- 6. push ------------------------------------------------------------------------
if [ -z "$REMOTE" ]; then
  if [ "$UNREACHABLE" = 1 ]; then
    echo "  push     skipped — remote configured but not reachable"
    echo "           NOT creating it. If the repo should exist, create it yourself and re-run."
    echo "== checkpoint: $HASH not pushed (remote unreachable)"
    exit 13
  fi
  echo "  push     skipped — no remote; local only"
  echo "== checkpoint: $HASH not pushed (no remote)"
  exit 12
fi
if [ "$DRY" = 1 ]; then
  echo "  DRY    git -C $PROJECT push"
  exit 0
fi
if [ -n "$UPSTREAM" ]; then
  PUSH_OUT="$(git -C "$PROJECT" push 2>&1)"; RC=$?
else
  PUSH_OUT="$(git -C "$PROJECT" push -u "$REMOTE" "$BRANCH" 2>&1)"; RC=$?
fi
if [ $RC -ne 0 ]; then
  # A non-fast-forward means someone else pushed. That is merged deliberately next
  # session, never force-resolved at the end of a day.
  echo "$PUSH_OUT" | sed 's/^/           /'
  echo "  push     FAILED — commit $HASH is safe locally. Not retrying, not forcing."
  exit 21
fi
echo "  push     ok -> $REMOTE/$BRANCH"
if [ "$NOTHING_TO_COMMIT" = 1 ]; then
  echo "== checkpoint: pushed $UNPUSHED existing commit(s), nothing new to commit ($HASH)"
else
  echo "== checkpoint: committed and pushed $HASH"
fi
exit 0
