#!/usr/bin/env bash
# sync.sh — install + verify + commit + push the brain (~/.agents → github:FirstIntegral/1config).
#
#   bash ~/.agents/sync.sh -m "Commit subject"     # normal use
#   bash ~/.agents/sync.sh --no-setup -m "msg"     # skip install, still run verify.sh
#   bash ~/.agents/sync.sh --dry-run               # show what would be committed, change nothing
#
# Scope is deliberately narrow: this script only ever touches ~/.agents, which is why it can be
# allowlisted while a generic `git push` still prompts everywhere else.
# Signing is NEVER bypassed — a locked key is an error to fix, not to work around.
set -euo pipefail

AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
REMOTE_HTTPS="https://github.com/FirstIntegral/1config.git"
REMOTE_SSH="git@github.com:FirstIntegral/1config.git"
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
AGENTS_HOME="$(pwd -P)"
git rev-parse --git-dir >/dev/null 2>&1 || { echo "sync.sh: $AGENTS_HOME is not a git repo" >&2; exit 1; }
repo_root="$(realpath "$(git rev-parse --show-toplevel)")"
[ "$repo_root" = "$AGENTS_HOME" ] || {
  echo "sync.sh: refusing nested repo path: $AGENTS_HOME (toplevel is $repo_root)" >&2
  exit 1
}
current_branch="$(git branch --show-current)"
[ "$current_branch" = "$BRANCH" ] || {
  echo "sync.sh: refusing branch '${current_branch:-detached}'; brain sync requires $BRANCH" >&2
  exit 1
}

valid_remote_url() {
  case "$1" in
    "$REMOTE_HTTPS"|"$REMOTE_SSH") return 0 ;;
    *) return 1 ;;
  esac
}

mapfile -t fetch_urls < <(git remote get-url --all origin 2>/dev/null || true)
mapfile -t push_urls < <(git remote get-url --push --all origin 2>/dev/null || true)
[ "${#fetch_urls[@]}" -gt 0 ] || { echo "sync.sh: no 'origin' fetch URL" >&2; exit 1; }
[ "${#push_urls[@]}" -gt 0 ] || { echo "sync.sh: no 'origin' push URL" >&2; exit 1; }
for remote in "${fetch_urls[@]}"; do
  if ! valid_remote_url "$remote"; then
    echo "sync.sh: refusing unexpected origin fetch URL: $remote" >&2
    echo "  expected $REMOTE_HTTPS (or SSH equivalent)" >&2
    exit 1
  fi
done
for remote in "${push_urls[@]}"; do
  case "$remote" in
    "$REMOTE_HTTPS"|"$REMOTE_SSH") echo "  repo     $remote" ;;
    *)
      echo "sync.sh: refusing unexpected origin push URL: $remote" >&2
      echo "  expected $REMOTE_HTTPS (or SSH equivalent)" >&2
      exit 1
      ;;
  esac
done

# 1. install + verify: never push a brain that fails its own checks
if [ "$dry_run" != 1 ] && [ "${AGENTS_UPDATE_LOCK_HELD:-0}" != 1 ]; then
  command -v flock >/dev/null || { echo "sync.sh: flock required" >&2; exit 1; }
  update_dir="$HOME/cron-jobs/ai-terminal-tools-update-on-boot"
  mkdir -p "$update_dir"
  exec 8>"$update_dir/.update.lock"
  flock 8
  export AGENTS_UPDATE_LOCK_HELD=1
fi
check_log="$(mktemp /tmp/agents-sync-check.XXXXXX)"
trap 'rm -f "$check_log"' EXIT
run_check() {
  local label="$1"
  shift
  if ! "$@" >"$check_log" 2>&1; then
    echo "sync.sh: $label FAILED — not committing. Output:" >&2
    tail -40 "$check_log" >&2
    exit 1
  fi
  if ! grep -q '^== PASS (warnings=0) ==$' "$check_log"; then
    echo "sync.sh: $label did not report PASS with warnings=0 — not committing. Output:" >&2
    tail -40 "$check_log" >&2
    exit 1
  fi
  grep '^== PASS (warnings=0) ==$' "$check_log"
}

if [ "$dry_run" = 1 ]; then
  echo "[sync 1/4] verify.sh (--dry-run; install skipped)"
  run_check "verify.sh" bash "$AGENTS_HOME/verify.sh"
elif [ "$run_setup" = 1 ]; then
  echo "[sync 1/4] setup.sh (installs + runs verify.sh)"
  run_check "setup.sh" env AGENTS_UPDATE_LOCK_HELD=1 bash "$AGENTS_HOME/setup.sh"
else
  echo "[sync 1/4] verify.sh (--no-setup skips install only)"
  run_check "verify.sh" bash "$AGENTS_HOME/verify.sh"
fi

# 2. anything to commit?
echo "[sync 2/4] working tree"
if [ "$dry_run" = 1 ]; then
  echo "  fetch    skipped under --dry-run (local refs only)"
elif ! git fetch -q origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"; then
  echo "sync.sh: fetch failed — not committing against stale remote state" >&2
  exit 1
fi
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
  if ! git commit -S -q -m "$msg"; then
    echo "sync.sh: commit failed (signing key locked?). Fix it — do NOT disable signing." >&2
    echo "  try: bash $AGENTS_HOME/hooks/gpg-agent-unlock.sh" >&2
    exit 1
  fi
  git log -1 --format='  committed %h %s'
fi

# Reject any unsigned commit that would leave the machine, including commits
# created before this invocation. G/U both mean cryptographically good.
outgoing="$(git rev-list "origin/$BRANCH..$BRANCH")"
[ -n "$outgoing" ] || { echo "sync.sh: no outgoing commit after working-tree check" >&2; exit 1; }
while IFS= read -r commit; do
  sig="$(git show -s --format='%G?' "$commit")"
  case "$sig" in
    G|U) ;;
    *)
      echo "sync.sh: refusing unsigned/unverifiable outgoing commit $commit (sig=$sig)" >&2
      exit 1
      ;;
  esac
done <<< "$outgoing"

# 4. push
echo "[sync 4/4] push origin $BRANCH"
git push -q origin "$BRANCH"
git log -1 --format='  pushed   %h %s'
echo "  brain in sync with github"
