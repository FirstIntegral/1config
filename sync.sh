#!/usr/bin/env bash
# sync.sh — install + verify + commit + push the brain (~/.agents → github:FirstIntegral/1config).
#
#   bash ~/.agents/sync.sh -m "Commit subject"     # normal use
#   bash ~/.agents/sync.sh --no-setup -m "msg"     # skip setup.sh (already ran it this turn)
#   bash ~/.agents/sync.sh --dry-run               # show what would be committed, change nothing
#
# Scope is deliberately narrow: this script only ever touches ~/.agents, which is why it can be
# allowlisted while a generic `git push` still prompts everywhere else.
# Signing is NEVER bypassed — a locked key is an error to fix, not to work around.
set -euo pipefail

AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
REMOTE_EXPECT="git@github.com:FirstIntegral/1config.git"
BRANCH="main"
run_setup=1
dry_run=0
msg=""

while [ $# -gt 0 ]; do
  case "$1" in
    -m|--message) msg="${2:-}"; shift 2 ;;
    --no-setup)   run_setup=0; shift ;;
    --dry-run)    dry_run=1; shift ;;
    -h|--help)    sed -n '2,10p' "$0"; exit 0 ;;
    *)            echo "sync.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

cd "$AGENTS_HOME"
git rev-parse --git-dir >/dev/null 2>&1 || { echo "sync.sh: $AGENTS_HOME is not a git repo" >&2; exit 1; }

remote="$(git remote get-url origin 2>/dev/null || true)"
[ -n "$remote" ] || { echo "sync.sh: no 'origin' remote" >&2; exit 1; }
[ "$remote" = "$REMOTE_EXPECT" ] && echo "  repo     $remote" \
  || echo "  repo     $remote  (expected $REMOTE_EXPECT — continuing)"

# 1. install + verify: never push a brain that fails its own checks
if [ "$run_setup" = 1 ]; then
  echo "[sync 1/4] setup.sh (installs + runs verify.sh)"
  bash "$AGENTS_HOME/setup.sh" >/tmp/agents-sync-setup.$$ 2>&1 || {
    echo "sync.sh: setup.sh FAILED — not committing. Output:" >&2
    tail -40 /tmp/agents-sync-setup.$$ >&2
    rm -f /tmp/agents-sync-setup.$$
    exit 1
  }
  grep -E '^== (PASS|FAIL)' /tmp/agents-sync-setup.$$ || true
  rm -f /tmp/agents-sync-setup.$$
else
  echo "[sync 1/4] setup.sh skipped (--no-setup)"
fi

# 2. anything to commit?
echo "[sync 2/4] working tree"
if [ -z "$(git status --porcelain)" ]; then
  echo "  clean    nothing to commit"
  if [ -n "$(git log "origin/$BRANCH..$BRANCH" --oneline 2>/dev/null)" ]; then
    echo "  ahead    local commits not yet pushed — pushing"
  else
    echo "  synced   already in sync with origin/$BRANCH"
    exit 0
  fi
else
  git status --short | sed 's/^/  /'
fi

if [ "$dry_run" = 1 ]; then
  echo "[sync] --dry-run: stopping before commit"
  exit 0
fi

# 3. commit (signed; gpg agent is unlocked from the keyring, never bypassed)
echo "[sync 3/4] commit"
if [ -n "$(git status --porcelain)" ]; then
  [ -n "$msg" ] || msg="Update brain: $(git status --porcelain | awk '{print $NF}' | xargs -n99 echo | cut -c1-60)"
  [ -x "$AGENTS_HOME/hooks/gpg-agent-unlock.sh" ] && bash "$AGENTS_HOME/hooks/gpg-agent-unlock.sh" >/dev/null 2>&1 || true
  git add -A
  if ! git commit -q -m "$msg"; then
    echo "sync.sh: commit failed (signing key locked?). Fix it — do NOT disable signing." >&2
    echo "  try: bash $AGENTS_HOME/hooks/gpg-agent-unlock.sh" >&2
    exit 1
  fi
  git log -1 --format='  committed %h %s'
fi

# 4. push
echo "[sync 4/4] push origin $BRANCH"
git push -q origin "$BRANCH"
git log -1 --format='  pushed   %h %s'
echo "  brain in sync with github"
