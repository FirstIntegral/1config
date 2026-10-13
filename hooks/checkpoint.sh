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
#   brain checkout                  -> do nothing at all                    (exit 22)
#   not a git repo                  -> do nothing at all                    (exit 10)
#   dir is not the repo toplevel    -> do nothing at all                    (exit 11)
#   session files not ignored       -> refuse, change nothing               (exit 20)
#   foreign, private file tracked   -> refuse, change nothing               (exit 15)
#   clean + no locally unpushed work -> do nothing                           (exit  3)
#   no remote configured            -> commit locally, do not push          (exit 12)
#   remote unreachable / missing    -> commit, do not push                  (exit 13)
#   push URL owner is not ours      -> commit if needed, do not push        (exit 14)
#   push fails                      -> commit stays, report                 (exit 21)
#   otherwise                       -> commit if needed + push              (exit  0)
#   notes diverge                   -> notes repo unchanged                 (exit 23)
#
# After the leak check passes, exits 0, 3, 12, 13, 14, and 21 call
# hooks/notes-sync.sh push. Exits 10, 11, 15, 20, and 22 do not. --dry-run
# returns before any notes stat. A missing notes clone keeps the exit above.
#
# NEVER, under any circumstance: create a repo, add a remote, create a GitHub repo,
# force-push, rebase, reset, amend, or bypass commit signing. A project without a repo or
# without a remote is in a deliberate state, and a checkpoint is a note-taking action that
# must not change it. Publishing something the user never chose to publish cannot be undone
# by deleting it afterwards.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
FORK_PARENTS="$ROOT/fork-parents.txt"
BRAIN_URLS="$ROOT/BRAIN_REMOTE"
FOREIGN_BEGIN="# 1config-foreign"
FOREIGN_END="# end 1config-foreign"

# git@host:owner/repo.git or https://host/owner/repo.git. Empty if unparsed.
slug_of() {
  local url="$1" rest owner repo
  case "$url" in
    git@*:*) rest="${url#*:}" ;;
    https://*|http://*)
      rest="${url#*://}"
      rest="${rest#*/}"
      ;;
    *) printf '\n'; return 0 ;;
  esac
  rest="${rest%.git}"
  owner="${rest%%/*}"
  repo="${rest#*/}"
  repo="${repo%%/*}"
  if [ -z "$owner" ] || [ -z "$repo" ] || [ "$owner" = "$rest" ]; then
    printf '\n'
    return 0
  fi
  printf '%s/%s\n' "$(printf '%s' "$owner" | tr '[:upper:]' '[:lower:]')" \
                   "$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')"
}

owner_of() {
  local slug
  slug="$(slug_of "$1")"
  printf '%s\n' "${slug%%/*}"
}

# Owners on URL lines in the brain allowlist. Not the project's own files.
inside_owner() {
  local url slug owner
  [ -f "$BRAIN_URLS" ] || return 1
  while IFS= read -r url || [ -n "$url" ]; do
    url="${url%$'\r'}"
    case "$url" in
      ''|'#'*) continue ;;
    esac
    slug="$(slug_of "$url")"
    [ -n "$slug" ] || continue
    owner="${slug%%/*}"
    [ "$owner" = "$1" ] && return 0
  done < "$BRAIN_URLS"
  return 1
}

# Configured URL, not the insteadOf rewrite. The rewrite is transport.
# The owner check has to see the URL a person set.
raw_remote_url() {
  local remote="$1" url
  url="$(git -C "$PROJECT" config --get "remote.${remote}.pushurl" 2>/dev/null || true)"
  if [ -z "$url" ]; then
    url="$(git -C "$PROJECT" config --get "remote.${remote}.url" 2>/dev/null || true)"
  fi
  printf '%s\n' "$url"
}

# origin matches fork-parents.txt and the parent owner is not ours.
# Sites stay sites. A missing origin is not foreign.
is_foreign_checkout() {
  local origin slug line ours parent parent_owner
  case "$PROJECT" in
    "$HOME/Projects/sites"/*) return 1 ;;
  esac
  origin="$(raw_remote_url origin)"
  slug="$(slug_of "$origin")"
  [ -n "$slug" ] || return 1
  [ -f "$FORK_PARENTS" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      ''|'#'*) continue ;;
    esac
    ours="$(printf '%s' "$line" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
    parent="$(printf '%s' "$line" | awk '{print $2}' | tr '[:upper:]' '[:lower:]')"
    [ "$ours" = "$slug" ] || continue
    parent_owner="${parent%%/*}"
    inside_owner "$parent_owner" && return 1
    return 0
  done < "$FORK_PARENTS"
  return 1
}

# The URL checkpoint would push to. Unparsed is not outside.
push_owner_outside() {
  local url="$1" owner
  owner="$(owner_of "$url")"
  [ -n "$owner" ] || return 1
  inside_owner "$owner" && return 1
  return 0
}

write_foreign_exclude() {
  local ex="$PROJECT/.git/info/exclude" tmp
  mkdir -p "$(dirname "$ex")"
  [ -f "$ex" ] || : > "$ex"
  tmp="$(mktemp)"
  awk -v b="$FOREIGN_BEGIN" -v e="$FOREIGN_END" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip { print }
  ' "$ex" > "$tmp"
  cat >> "$tmp" <<EOF

$FOREIGN_BEGIN
/AGENTS.md
/docs/DECISIONS.md
/session_compact.md
/session_transcript.md
/claude_memory_import.md
/notes.allow
$FOREIGN_END
EOF
  mv "$tmp" "$ex"
}

PROJECT=""
SUBJECT=""
DRY=0

die() { echo "checkpoint: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    -m|--message) [ $# -ge 2 ] || die "$1 needs a value"; SUBJECT="$2"; shift 2 ;;
    --dry-run)    DRY=1; shift ;;
    -h|--help)    sed -n '2,40p' "$0"; exit 0 ;;
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

# The brain is not a day-end project. checkpoint.sh pushes without verify.sh;
# sync.sh is the publisher that refuses a failed verify. Refuse before git.
refuse_brain() {
  echo "  repo     brain checkout — not a project"
  echo "  action   refused — checkpoint does not publish the brain (exit 22). Use sync.sh."
  exit 22
}
BRAIN_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"

# Project commit already happened, or there was nothing to commit. Notes sync
# never rolls that commit back. Dry-run does not stat the notes clone.
finish() {
  local want="$1" nrc=0
  if [ "$DRY" = 1 ]; then
    exit "$want"
  fi
  if [ ! -f "$BRAIN_DIR/hooks/notes-sync.sh" ]; then
    echo "  notes    hooks/notes-sync.sh missing"
    exit 21
  fi
  (
    unset NOTES_SYNC_TEST_ROOT
    bash "$BRAIN_DIR/hooks/notes-sync.sh" push "$PROJECT"
  ) || nrc=$?
  if [ "$nrc" -eq 23 ]; then
    echo "== checkpoint: notes diverge (exit 23). Notes repo unchanged."
    exit 23
  fi
  if [ "$nrc" -eq 20 ]; then
    echo "== checkpoint: notes.allow would be published (exit 20)"
    exit 20
  fi
  if [ "$nrc" -ne 0 ]; then
    echo "== checkpoint: notes sync failed (exit $nrc). Project commit was not rolled back."
    exit 21
  fi
  exit "$want"
}

if [ "$PROJECT" = "$BRAIN_DIR" ]; then
  refuse_brain
fi
if [ -f "$PROJECT/setup.sh" ] && [ -f "$PROJECT/verify.sh" ] && [ -f "$PROJECT/BRAIN_REMOTE" ]; then
  _origin="$(git -C "$PROJECT" remote get-url --push origin 2>/dev/null || true)"
  if [ -n "$_origin" ]; then
    while IFS= read -r _url || [ -n "$_url" ]; do
      _url="${_url%$'\r'}"
      case "$_url" in
        ''|'#'*) continue ;;
      esac
      if [ "$_origin" = "$_url" ]; then
        refuse_brain
      fi
    done < "$PROJECT/BRAIN_REMOTE"
  fi
fi

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

# --- 1b. foreign checkout: keep our notes out of their tree -------------------------
# fork-parents.txt matches origin. A push aimed at an owner who is not on
# BRAIN_REMOTE gets the same exclude, so a later retarget cannot publish notes
# that this commit already captured. Sites are not this case. Dry-run writes nothing.
FOREIGN=0
OUTSIDE_PUSH=0
CHOSEN_URL=""
if is_foreign_checkout; then
  FOREIGN=1
fi
_up="$(git -C "$PROJECT" rev-parse --abbrev-ref "@{upstream}" 2>/dev/null || true)"
if [ -n "$_up" ]; then
  _remote="${_up%%/*}"
  CHOSEN_URL="$(raw_remote_url "$_remote")"
elif git -C "$PROJECT" config --get remote.origin.url >/dev/null 2>&1; then
  CHOSEN_URL="$(raw_remote_url origin)"
fi
if [ -n "$CHOSEN_URL" ] && push_owner_outside "$CHOSEN_URL"; then
  OUTSIDE_PUSH=1
fi
if [ "$FOREIGN" = 1 ] || [ "$OUTSIDE_PUSH" = 1 ]; then
  case "$PROJECT" in
    "$HOME/Projects/sites"/*) ;;
    *)
      if [ "$DRY" = 1 ]; then
        echo "  foreign  would write .git/info/exclude"
      else
        write_foreign_exclude
        echo "  foreign  exclude updated"
      fi
      TRACKED_PRIVATE=()
      for f in AGENTS.md docs/DECISIONS.md; do
        if git -C "$PROJECT" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
          TRACKED_PRIVATE+=("$f")
        fi
      done
      if [ ${#TRACKED_PRIVATE[@]} -gt 0 ]; then
        echo "  action   REFUSED — foreign checkout, already tracked:"
        printf '             %s\n' "${TRACKED_PRIVATE[@]}"
        echo "           exclude cannot untrack those. Nothing committed."
        exit 15
      fi
      ;;
  esac
fi

# --- 2. session files must be ignored before anything is staged ---------------------
# The transcript is the user's private log. A checkpoint that publishes it is the one
# failure here that cannot be walked back, so it is checked before `git add`, not after.
LEAKED=()
for f in session_compact.md session_transcript.md claude_memory_import.md notes.allow; do
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
    finish 3
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
  # An owner who is not on BRAIN_REMOTE is not a reachability problem. Skip
  # ls-remote so a refused push is exit 14, not exit 13. Unparsed URLs are not a veto.
  if [ "$OUTSIDE_PUSH" = 1 ]; then
    echo "  reachable skipped — push URL owner is not ours"
  elif git -C "$PROJECT" ls-remote "$REMOTE" >/dev/null 2>&1; then
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
      finish 21
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
if [ "$OUTSIDE_PUSH" = 1 ]; then
  echo "  push     skipped — push URL owner is not ours"
  echo "== checkpoint: ${HASH:-none} not pushed (exit 14)"
  finish 14
fi
if [ -z "$REMOTE" ]; then
  if [ "$UNREACHABLE" = 1 ]; then
    echo "  push     skipped — remote configured but not reachable"
    echo "           NOT creating it. If the repo should exist, create it yourself and re-run."
    echo "== checkpoint: $HASH not pushed (remote unreachable)"
    finish 13
  fi
  echo "  push     skipped — no remote; local only"
  echo "== checkpoint: $HASH not pushed (no remote)"
  finish 12
fi
if [ "$DRY" = 1 ]; then
  echo "  DRY    git -C $PROJECT push"
  finish 0
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
  finish 21
fi
echo "  push     ok -> $REMOTE/$BRANCH"
if [ "$NOTHING_TO_COMMIT" = 1 ]; then
  echo "== checkpoint: pushed $UNPUSHED existing commit(s), nothing new to commit ($HASH)"
else
  echo "== checkpoint: committed and pushed $HASH"
fi
finish 0
