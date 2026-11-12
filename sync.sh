#!/usr/bin/env bash
# sync.sh — install + verify + commit + push the brain (~/.agents → the origin in BRAIN_REMOTE).
#
#   bash ~/.agents/sync.sh -m "Commit subject"     # normal use
#   bash ~/.agents/sync.sh --no-setup -m "msg"     # skip install, still run verify.sh
#   bash ~/.agents/sync.sh --dry-run               # show what would be committed, change nothing
#
# Scope is deliberately narrow: this script only ever touches ~/.agents, which is why it can be
# allowlisted as the verified push path. Canonical permissions.json still lists generic
# `git push` as ask (restore-gate); live tools omit that ask while bash_without_prompt is true.
# Signing is NEVER bypassed — a locked key is an error to fix, not to work around.
#
# Order: fetch, take what origin has (fast-forward only, signed by a listed key), install and
# verify that tree, scan for secrets, commit, check outgoing signatures, push. A diverged
# brain stops before anything is installed. Nothing here merges, rebases, or forces.
set -euo pipefail

AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
BRANCH="main"
run_setup=1
dry_run=0
msg=""
orig_args=("$@")

while [ $# -gt 0 ]; do
  case "$1" in
    -m|--message) msg="${2:-}"; shift 2 ;;
    --no-setup)   run_setup=0; shift ;;
    --dry-run)    dry_run=1; shift ;;
    -h|--help)    sed -n '2,14p' "$0"; exit 0 ;;
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

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC1091
source "$_script_dir/hooks/brain-remote.sh"
brain_remote_load "$AGENTS_HOME/BRAIN_REMOTE" || {
  echo "sync.sh: $AGENTS_HOME/BRAIN_REMOTE missing or empty" >&2
  exit 1
}

valid_remote_url() { brain_remote_ok "$1"; }

mapfile -t fetch_urls < <(git remote get-url --all origin 2>/dev/null || true)
mapfile -t push_urls < <(git remote get-url --push --all origin 2>/dev/null || true)
[ "${#fetch_urls[@]}" -gt 0 ] || { echo "sync.sh: no 'origin' fetch URL" >&2; exit 1; }
[ "${#push_urls[@]}" -gt 0 ] || { echo "sync.sh: no 'origin' push URL" >&2; exit 1; }
for remote in "${fetch_urls[@]}"; do
  if ! valid_remote_url "$remote"; then
    echo "sync.sh: refusing unexpected origin fetch URL: $remote" >&2
    echo "  expected one of: ${BRAIN_REMOTE_URLS[*]}" >&2
    exit 1
  fi
done
for remote in "${push_urls[@]}"; do
  if valid_remote_url "$remote"; then
    echo "  repo     $remote"
  else
    echo "sync.sh: refusing unexpected origin push URL: $remote" >&2
    echo "  expected one of: ${BRAIN_REMOTE_URLS[*]}" >&2
    exit 1
  fi
done

if [ "$dry_run" != 1 ] && [ "${AGENTS_UPDATE_LOCK_HELD:-0}" != 1 ]; then
  command -v flock >/dev/null || { echo "sync.sh: flock required" >&2; exit 1; }
  update_dir="$HOME/cron-jobs/ai-terminal-tools-update-on-boot"
  mkdir -p "$update_dir"
  exec 8>"$update_dir/.update.lock"
  flock 8
  export AGENTS_UPDATE_LOCK_HELD=1
fi

# 1. origin first. Verifying, then finding out origin moved, means a commit on a
# stale base and a rejected push. Take what origin has before anything is installed.
echo "[sync 1/5] origin"
if [ "$dry_run" = 1 ]; then
  echo "  fetch    skipped under --dry-run (local refs only)"
elif ! git fetch -q origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"; then
  echo "sync.sh: fetch failed — not committing against stale remote state" >&2
  exit 1
elif git rev-parse -q --verify "refs/remotes/origin/$BRANCH" >/dev/null 2>&1; then
  behind="$(git rev-list --count "$BRANCH..origin/$BRANCH")"
  ahead="$(git rev-list --count "origin/$BRANCH..$BRANCH")"
  if [ "$behind" -gt 0 ] && [ "$ahead" -gt 0 ]; then
    echo "sync.sh: diverged from origin/$BRANCH ($behind behind, $ahead ahead) — not committing." >&2
    echo "  merge by hand, then re-run: git -C $AGENTS_HOME merge origin/$BRANCH" >&2
    exit 1
  fi
  if [ "$behind" -gt 0 ]; then
    gate_rc=0
    gate_out="$(bash "$_script_dir/hooks/verify-incoming.sh" "$AGENTS_HOME" "$BRANCH" "origin/$BRANCH" 2>&1)" || gate_rc=$?
    if [ "$gate_rc" -ne 0 ]; then
      echo "sync.sh: origin/$BRANCH is $behind commit(s) ahead and not signed by a listed key — not taken." >&2
      echo "  $gate_out" >&2
      echo "  review, then: git -C $AGENTS_HOME merge --ff-only origin/$BRANCH" >&2
      exit 1
    fi
    # A fast-forward leaves edits to other files in place and refuses an overlap.
    if ! ff_out="$(git merge --ff-only "origin/$BRANCH" 2>&1)"; then
      echo "sync.sh: origin/$BRANCH is $behind commit(s) ahead and overlaps local edits — not committing." >&2
      printf '%s\n' "$ff_out" | sed 's/^/  /' >&2
      echo "  set the edits aside or resolve by hand, then re-run." >&2
      exit 1
    fi
    echo "  took     $behind commit(s) from origin/$BRANCH"
    # The pull may have replaced this file, and bash reads a script as it runs.
    # Start over on the script that is now on disk. It fetches, finds nothing new,
    # and installs the tree that was just pulled.
    export AGENTS_HOME
    exec bash "$_script_dir/sync.sh" ${orig_args[@]+"${orig_args[@]}"}
  fi
  echo "  current  nothing new on origin/$BRANCH"
fi

# 2. install + verify: never push a brain that fails its own checks
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
  echo "[sync 2/5] verify.sh (--dry-run; install skipped)"
  run_check "verify.sh" bash "$AGENTS_HOME/verify.sh"
elif [ "$run_setup" = 1 ]; then
  echo "[sync 2/5] setup.sh (installs + runs verify.sh)"
  run_check "setup.sh" env AGENTS_UPDATE_LOCK_HELD=1 bash "$AGENTS_HOME/setup.sh"
else
  echo "[sync 2/5] verify.sh (--no-setup skips install only)"
  run_check "verify.sh" bash "$AGENTS_HOME/verify.sh"
fi

# 3. anything to commit?
echo "[sync 3/5] working tree"
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

# This repo is public. A token in a hook or a doc must stop here, not on GitHub.
# The scan covers the edits about to be committed and any commit not yet pushed.
scan_base="origin/$BRANCH"
git rev-parse -q --verify "$scan_base" >/dev/null 2>&1 || scan_base=""
if ! bash "$_script_dir/hooks/secret-scan.sh" "$AGENTS_HOME" ${scan_base:+"$scan_base"}; then
  echo "sync.sh: a secret-shaped string is about to be published — not committing." >&2
  echo "  remove it. A fixture that needs a fake token carries gitleaks:allow on that line." >&2
  exit 1
fi
echo "  scan     no secret-shaped strings"

if [ "$dry_run" = 1 ]; then
  echo "[sync] --dry-run: stopping before commit"
  exit 0
fi

# 4. commit (signed; gpg agent is unlocked from the keyring, never bypassed)
echo "[sync 4/5] commit"
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

# 5. push
echo "[sync 5/5] push origin $BRANCH"
git push -q origin "$BRANCH"
git log -1 --format='  pushed   %h %s'
echo "  brain in sync with github"
