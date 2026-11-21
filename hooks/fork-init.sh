#!/usr/bin/env bash
# fork-init.sh — point a fork of this repo at its new owner.
#
#   bash ~/.agents/bin/1config fork-init                     # the plan: four diffs, nothing changes
#   bash ~/.agents/bin/1config fork-init --yes               # write them, one signed commit
#   bash ~/.agents/bin/1config fork-init --yes --notes URL   # also name your private notes repo
#
# Four tracked files say who owns a checkout. A fresh fork still carries the
# upstream owner's four, and AGENTS.md still names the upstream repo:
#   BRAIN_REMOTE      the origin URLs sync.sh, verify.sh, and login sync accept, and
#                     the host and owner checkpoint.sh treats as "ours"
#   BRAIN_SIGNERS     the key fingerprints whose commits a login pull installs
#   NOTES_REMOTE      the private machine-notes repo; no URL means notes are off
#   fork-parents.txt  the upstream owner's own forks
#   AGENTS.md         one sentence: "The GitHub repo is `owner/repo` (...)". The
#                     agents take it as the name of this repo, so it is rewritten too.
# Left alone, your projects never push (checkpoint exit 14), every login tries
# to clone a private repo you cannot read, and the upstream owner's key stays
# able to ship code to your machine. This script rewrites the four from what
# this checkout already knows: its origin URL and git's signing key.
#
# It makes one commit that holds only those files and does not push.
# setup.sh comes next; sync.sh publishes.
#
# Exit 0 done, plan printed, or nothing to do · 1 cannot run (reason named) · 2 usage.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DO=0
NOTES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) DO=1 ;;
    --notes) [ $# -ge 2 ] || { echo "fork-init: --notes needs a URL" >&2; exit 2; }; NOTES="$2"; shift ;;
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
    *) echo "fork-init: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done
die() { echo "fork-init: $*" >&2; exit 1; }

# shellcheck disable=SC1091
. "$ROOT/hooks/git-url.sh"
# shellcheck disable=SC1091
. "$ROOT/hooks/brain-remote.sh"

git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "$ROOT is not a git checkout"
mapfile -t ORIGINS < <({ git -C "$ROOT" remote get-url --all origin 2>/dev/null
                         git -C "$ROOT" remote get-url --push --all origin 2>/dev/null; } | awk '!seen[$0]++')
[ "${#ORIGINS[@]}" -gt 0 ] || die "this checkout has no origin remote; add your fork's URL first"

read -r HOST OWNER REPO <<< "$(git_url_parse "${ORIGINS[0]}")"
[ -n "${HOST:-}" ] && [ -n "${OWNER:-}" ] && [ -n "${REPO:-}" ] \
  || die "origin ${ORIGINS[0]} is not a host/owner/repo URL (https://host/owner/repo.git or git@host:owner/repo.git)"

KEY="$(bash "$ROOT/hooks/gpg-signing-key.sh" 2>/dev/null)" \
  || die "git has no signing key; set git config --global user.signingkey first (bash $ROOT/setup.sh --preflight lists what is missing)"
gpg --batch --list-secret-keys "$KEY" >/dev/null 2>&1 \
  || die "the secret key for user.signingkey=$KEY is not in this machine's keyring"
# The primary-key fingerprint, as `git log --format=%GP` prints it.
FPR="$(gpg --batch --with-colons --list-keys "$KEY" 2>/dev/null | awk -F: '$1 == "pub" { want = 1 } want && $1 == "fpr" { print $10; exit }')"
[ -n "$FPR" ] || die "could not read the fingerprint of key $KEY"

# The path part of a remote URL with its case kept: git hosts fold case, exact
# string matching in BRAIN_REMOTE does not.
url_path() {
  local u="${1%/}"
  u="${u%.git}"
  case "$u" in
    *://*) u="${u#*://}"; printf '%s\n' "${u#*/}" ;;
    *:*)   printf '%s\n' "${u#*:}" ;;
  esac
}
PATHPART="$(url_path "${ORIGINS[0]}")"

# Already this owner's: every origin URL is listed and this key is a signer.
already=1
if brain_remote_load "$ROOT/BRAIN_REMOTE"; then
  for u in "${ORIGINS[@]}"; do brain_remote_ok "$u" || already=0; done
else
  already=0
fi
grep -qx "$FPR" "$ROOT/BRAIN_SIGNERS" 2>/dev/null || already=0
name_ok=1
if [ -f "$ROOT/AGENTS.md" ] && grep -q 'The GitHub repo is `' "$ROOT/AGENTS.md" \
   && ! grep -qF "The GitHub repo is \`$PATHPART\` " "$ROOT/AGENTS.md"; then
  name_ok=0
fi
if [ "$already" = 1 ] && [ "$name_ok" = 1 ] && [ -z "$NOTES" ]; then
  echo "fork-init: origin and this machine's key are already listed. Nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The comment lines at the top of a file say what the file is. They stay.
header() { [ -f "$1" ] && sed -n '/^#/!q;p' "$1"; }

{
  header "$ROOT/BRAIN_REMOTE"
  {
    printf '%s\n' "${ORIGINS[@]}"
    printf 'https://%s/%s.git\n' "$HOST" "$PATHPART"
    printf 'git@%s:%s.git\n' "$HOST" "$PATHPART"
  } | awk '!seen[$0]++'
} > "$TMP/BRAIN_REMOTE"

{
  header "$ROOT/BRAIN_SIGNERS"
  printf '%s\n' "$FPR"
} > "$TMP/BRAIN_SIGNERS"

{
  if [ -n "$(header "$ROOT/NOTES_REMOTE")" ]; then
    header "$ROOT/NOTES_REMOTE"
  else
    printf '%s\n' \
      '# The private repo that carries untracked project notes between your machines.' \
      '# One URL on the first line that is not a comment. hooks/notes-sync.sh reads it.' \
      '# No URL here means notes are off: nothing is cloned and nothing is pushed.' \
      '# The repo must be private and must already exist. Nothing here creates it.'
  fi
  if [ -n "$NOTES" ]; then
    printf '%s\n' "$NOTES"
  elif [ "$already" = 1 ]; then
    # A second run that only adds --notes must not drop a URL that is already there.
    sed -n '/^#/d;/^$/d;p' "$ROOT/NOTES_REMOTE" 2>/dev/null | head -n 1
  fi
} > "$TMP/NOTES_REMOTE"

if [ "$already" = 1 ]; then
  cp "$ROOT/fork-parents.txt" "$TMP/fork-parents.txt" 2>/dev/null || : > "$TMP/fork-parents.txt"
else
  header "$ROOT/fork-parents.txt" > "$TMP/fork-parents.txt"
fi

# The rules file names the repo in one sentence. An agent reads that sentence as
# "this is the repo I edit and push", so a fork must not keep the upstream name.
# Only that sentence changes. A file without it is left as it is.
if [ -f "$ROOT/AGENTS.md" ]; then
  NAME_LINE="The GitHub repo is \`$PATHPART\` (\`git@$HOST:$PATHPART.git\`, \`https://$HOST/$PATHPART.git\`)."
  NAME_LINE="$NAME_LINE" python3 - "$ROOT/AGENTS.md" "$TMP/AGENTS.md" <<'PYNAME'
import os
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
want = os.environ["NAME_LINE"]
new = re.sub(r"The GitHub repo is `[^`\n]+` \(`[^`\n]+`, `[^`\n]+`\)\.", lambda _m: want, text, count=1)
open(dst, "w", encoding="utf-8").write(new)
PYNAME
fi

FILES=(BRAIN_REMOTE BRAIN_SIGNERS NOTES_REMOTE fork-parents.txt)
[ -f "$TMP/AGENTS.md" ] && FILES+=(AGENTS.md)
changed=()
for f in "${FILES[@]}"; do
  cmp -s "$TMP/$f" "$ROOT/$f" || changed+=("$f")
done
if [ "${#changed[@]}" -eq 0 ]; then
  echo "fork-init: the owner files already say $HOST/$OWNER/$REPO and key $FPR. Nothing to do."
  exit 0
fi

echo "== 1config fork-init — $([ "$DO" = 1 ] && echo "writing" || echo "plan only, nothing changes (add --yes)") =="
echo "  origin   ${ORIGINS[0]}"
echo "  owner    $HOST/$OWNER  (projects under this owner are yours for checkpoint_project)"
echo "  signer   $FPR  (git user.signingkey=$KEY)"
if [ -n "$NOTES" ]; then echo "  notes    $NOTES"; else echo "  notes    $(sed -n '/^#/d;/^$/d;p' "$TMP/NOTES_REMOTE" | head -n 1 | grep . || echo 'off (pass --notes URL to name a private notes repo)')"; fi
for f in "${changed[@]}"; do
  echo "--- $f"
  diff -u "$ROOT/$f" "$TMP/$f" | sed '1,2d' || true
done

if [ "$DO" != 1 ]; then
  echo "== plan only. Run again with --yes to write ${#changed[@]} file(s) and make one signed commit. =="
  exit 0
fi

# Anything already staged would ride along in the commit below.
git -C "$ROOT" diff --cached --quiet 2>/dev/null \
  || die "this checkout has staged changes; commit or unstage them first"
[ "$(git -C "$ROOT" config --bool commit.gpgsign 2>/dev/null || true)" = true ] \
  || die "commit.gpgsign is not true; run: git config --global commit.gpgsign true"

for f in "${changed[@]}"; do
  cp "$TMP/$f" "$ROOT/$f"
done
if git -C "$ROOT" commit -q -m "Point this fork at $HOST/$OWNER/$REPO" -- "${changed[@]}"; then
  echo "== done. Committed $(git -C "$ROOT" log -1 --format=%h) (signed, not pushed). =="
  echo "Next:  bash $ROOT/setup.sh"
  echo "Then:  bash $ROOT/sync.sh -m \"<subject>\"     # publishes to ${ORIGINS[0]}"
else
  echo "fork-init: the commit failed (signing?). The files are written and not committed." >&2
  echo "fork-init: fix signing, then: git -C $ROOT commit -m \"Point this fork at $HOST/$OWNER/$REPO\" -- ${changed[*]}" >&2
  exit 1
fi
