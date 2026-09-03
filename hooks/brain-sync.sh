#!/usr/bin/env bash
# brain-sync.sh — pull ~/.agents forward to match origin/main (github:FirstIntegral/1config).
#
# Runs at login from the boot dashboard; safe to run anytime:
#   bash ~/.agents/hooks/brain-sync.sh
#
# Guarantees:
#   * only ever talks to the canonical 1config remote (never a fork / stale URL)
#   * fast-forward only — never rewrites local commits, never clobbers local edits
#   * never prompts (ssh BatchMode) and never hangs (fetch is time-bounded)
#
# Exit codes:
#   0   up to date, or fast-forwarded to origin/main
#   1   fetch failed (offline / auth / remote unreachable)
#   2   local is ahead (unpushed commits) — nothing pulled
#   3   local is behind but the tree has uncommitted edits — nothing pulled
#   4   divergence / not a repo / wrong branch / non-1config remote — human needed
set -euo pipefail

AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
REMOTE_HTTPS="https://github.com/FirstIntegral/1config.git"
REMOTE_SSH="git@github.com:FirstIntegral/1config.git"
BRANCH="main"
FETCH_TIMEOUT="${BRAIN_SYNC_FETCH_TIMEOUT:-45}"

git -C "$AGENTS_HOME" rev-parse --git-dir >/dev/null 2>&1 \
  || { echo "brain-sync: $AGENTS_HOME is not a git repo" >&2; exit 4; }
[ "$(realpath "$(git -C "$AGENTS_HOME" rev-parse --show-toplevel)")" = "$(realpath "$AGENTS_HOME")" ] \
  || { echo "brain-sync: $AGENTS_HOME is not the repo root" >&2; exit 4; }
[ "$(git -C "$AGENTS_HOME" branch --show-current)" = "$BRANCH" ] \
  || { echo "brain-sync: not on branch $BRANCH" >&2; exit 4; }

mapfile -t fetch_urls < <(git -C "$AGENTS_HOME" remote get-url --all origin 2>/dev/null || true)
[ "${#fetch_urls[@]}" -gt 0 ] || { echo "brain-sync: no origin fetch URL" >&2; exit 4; }
for url in "${fetch_urls[@]}"; do
  case "$url" in
    "$REMOTE_HTTPS"|"$REMOTE_SSH") ;;
    *) echo "brain-sync: refusing non-1config origin: $url" >&2; exit 4 ;;
  esac
done

# BatchMode: never prompt for a passphrase at boot (ssh-agent must already hold the key).
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=10}"

if ! timeout "$FETCH_TIMEOUT" git -C "$AGENTS_HOME" fetch -q origin \
     "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"; then
  echo "brain-sync: fetch failed (offline or key not available)" >&2
  exit 1
fi

local_sha="$(git -C "$AGENTS_HOME" rev-parse "$BRANCH")"
remote_sha="$(git -C "$AGENTS_HOME" rev-parse "refs/remotes/origin/$BRANCH")"

behind="$(git -C "$AGENTS_HOME" rev-list --count "$local_sha..$remote_sha")"
ahead="$(git -C "$AGENTS_HOME" rev-list --count "$remote_sha..$local_sha")"

if [ "$behind" -eq 0 ] && [ "$ahead" -eq 0 ]; then
  echo "up to date"
  exit 0
fi

if [ "$behind" -eq 0 ]; then
  echo "$ahead local commit(s) ahead — not pulling"
  exit 2
fi

if [ "$ahead" -gt 0 ]; then
  echo "diverged from origin/$BRANCH ($behind behind, $ahead ahead) — needs a manual merge" >&2
  exit 4
fi

# behind only. Never pull over uncommitted local edits.
if [ -n "$(git -C "$AGENTS_HOME" status --porcelain)" ]; then
  echo "$behind commit(s) behind but tree dirty — not pulling"
  exit 3
fi

if ! git -C "$AGENTS_HOME" merge --ff-only "refs/remotes/origin/$BRANCH" >/dev/null; then
  echo "brain-sync: non-fast-forward divergence — needs a manual merge" >&2
  exit 4
fi

echo "fast-forwarded $behind commit(s) → matches origin/$BRANCH"
exit 0
