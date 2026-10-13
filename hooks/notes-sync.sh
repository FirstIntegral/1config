#!/usr/bin/env bash
# notes-sync.sh — copy untracked project notes to the private machine-notes repo.
#
#   bash ~/.agents/hooks/notes-sync.sh push  <project>
#   bash ~/.agents/hooks/notes-sync.sh pull  <project>
#   bash ~/.agents/hooks/notes-sync.sh backfill
#
# The project git never receives these files. This script never runs `git add -A`
# in either repo, never creates a GitHub repo, and never force-pushes.
#
# Stdout ends with one of: notes: skipped | notes: current | notes: pushed | notes: pulled
# Exit 0  those four
# Exit 20 notes.allow is tracked or not ignored
# Exit 23 both sides changed the same file since the last sync; nothing written
# Exit 1  fetch, sign, or push failed. A project commit is not rolled back.
#
# NOTES_SYNC_TEST_ROOT is for verify.sh only. checkpoint.sh unsets it.
# The real clone is $passwd_home/.local/share/machine-notes. A test root that
# points at that clone is refused.
set -uo pipefail

export GIT_TERMINAL_PROMPT=0

die() { echo "notes-sync: $*" >&2; exit 2; }

passwd_home() {
  getent passwd "$(id -un)" | awk -F: '{print $6; exit}'
}

# git@host:owner/repo, ssh://git@host/owner/repo, https://host/owner/repo.
# ssh.github.com folds to github.com. Empty if unparsed.
origin_key() {
  local url="$1" host rest owner repo
  url="${url%.git}"
  url="${url%/}"
  case "$url" in
    git@*:*)
      host="${url#git@}"
      host="${host%%:*}"
      rest="${url#*:}"
      ;;
    ssh://*|https://*|http://*)
      rest="${url#*://}"
      case "$rest" in *@*) rest="${rest#*@}" ;; esac
      host="${rest%%/*}"
      host="${host%%:*}"
      rest="${rest#*/}"
      ;;
    *)
      printf '\n'
      return 0
      ;;
  esac
  [ "$host" = "ssh.github.com" ] && host="github.com"
  owner="${rest%%/*}"
  repo="${rest#*/}"
  repo="${repo%%/*}"
  repo="${repo%%\?*}"
  if [ -z "$host" ] || [ -z "$owner" ] || [ -z "$repo" ] || [ "$owner" = "$rest" ]; then
    printf '\n'
    return 0
  fi
  printf '%s/%s/%s\n' \
    "$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')" \
    "$(printf '%s' "$owner" | tr '[:upper:]' '[:lower:]')" \
    "$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')"
}

trim() {
  local s="$1"
  s="${s%$'\r'}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s\n' "$s"
}

blocked_rel() {
  case "$1" in
    claude_memory_import.md|docs/SESSION.md) return 0 ;;
    docs/session-archive|docs/session-archive/*) return 0 ;;
    docs/session-flushes|docs/session-flushes/*) return 0 ;;
  esac
  return 1
}

denied_base() {
  case "$1" in
    local.properties|keystore.properties) return 0 ;;
    .env|.env.*) return 0 ;;
    *.keystore|*.jks|*.apk|*.pem) return 0 ;;
    credentials*) return 0 ;;
    *service-account*.json|*play-store*.json|google-play*.json|pc-api-*.json) return 0 ;;
  esac
  return 1
}

# Reject globs, absolute paths, ~, and any .. component.
safe_rel() {
  local rel="$1" part
  case "$rel" in
    ''|/*|~*|*'\\'*|*'*)'*|*'?'*|*'['*) return 1 ;;
  esac
  local IFS=/
  # shellcheck disable=SC2086
  set -- $rel
  for part in "$@"; do
    [ -z "$part" ] && return 1
    [ "$part" = "." ] || [ "$part" = ".." ] && return 1
  done
  return 0
}

inside_project() {
  local real="$1"
  case "$real" in
    "$PROJECT"|"$PROJECT"/*) return 0 ;;
  esac
  return 1
}

warn() { echo "notes: warn $*" >&2; }

skip_line() { echo "notes: skipped"; exit 0; }

cmd_backfill() {
  local home g top c rc=0
  unset NOTES_SYNC_TEST_ROOT
  home="$(passwd_home)"
  [ -n "$home" ] || die "no passwd home"
  if [ ! -d "$home/Projects" ]; then
    skip_line
  fi
  if [ ! -e "$home/.local/share/machine-notes/.git" ]; then
    skip_line
  fi
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    top="$(dirname "$g")"
    top="$(cd "$top" && pwd -P)" || continue
    c=0
    env -u NOTES_SYNC_TEST_ROOT bash "$0" push "$top" || c=$?
    if [ "$c" -eq 23 ]; then
      rc=23
    elif [ "$c" -ne 0 ] && [ "$rc" -eq 0 ]; then
      rc=$c
    fi
  done < <(find "$home/Projects" -name .git \( -type d -o -type f \) -print)
  exit "$rc"
}

MODE="${1:-}"
case "$MODE" in
  backfill) cmd_backfill ;;
  push|pull) ;;
  *) die "usage: notes-sync.sh push|pull PROJECT | backfill" ;;
esac
[ $# -eq 2 ] || die "usage: notes-sync.sh $MODE PROJECT"
PROJECT="$2"
[ -d "$PROJECT" ] || die "not a directory: $PROJECT"
PROJECT="$(cd "$PROJECT" && pwd -P)"

HOME_DIR="$(passwd_home)"
[ -n "$HOME_DIR" ] || die "no passwd home"
REAL_NOTES="$HOME_DIR/.local/share/machine-notes"
BRAIN_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"

if [ -n "${NOTES_SYNC_TEST_ROOT:-}" ]; then
  NOTES="$(cd "$NOTES_SYNC_TEST_ROOT" && pwd -P)" || die "bad NOTES_SYNC_TEST_ROOT"
  if [ -d "$REAL_NOTES" ]; then
    realp="$(cd "$REAL_NOTES" && pwd -P)"
    if [ "$NOTES" = "$realp" ]; then
      echo "notes: test root is the real clone" >&2
      exit 1
    fi
    case "$NOTES" in
      "$realp"/*)
        echo "notes: test root is inside the real clone" >&2
        exit 1
        ;;
    esac
  fi
else
  case "$PROJECT" in
    "$HOME_DIR/Projects"/*) ;;
    *) skip_line ;;
  esac
  NOTES="$REAL_NOTES"
fi

if [ "$PROJECT" = "$BRAIN_DIR" ]; then
  skip_line
fi
if [ ! -e "$NOTES/.git" ]; then
  skip_line
fi

if ! git -C "$PROJECT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  skip_line
fi
TOP="$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null || true)"
[ "$TOP" = "$PROJECT" ] || skip_line

# 1config stays on sync.sh. Another project's own BRAIN_REMOTE is not this
# test — grokbot-brain has one, and its untracked transcript still rides.
if [ -f "$BRAIN_DIR/BRAIN_REMOTE" ]; then
  _origin="$(git -C "$PROJECT" config --get remote.origin.pushurl 2>/dev/null || true)"
  [ -n "$_origin" ] || _origin="$(git -C "$PROJECT" config --get remote.origin.url 2>/dev/null || true)"
  if [ -n "$_origin" ]; then
    while IFS= read -r _url || [ -n "$_url" ]; do
      _url="${_url%$'\r'}"
      case "$_url" in ''|'#'*) continue ;; esac
      if [ "$_origin" = "$_url" ]; then
        skip_line
      fi
    done < "$BRAIN_DIR/BRAIN_REMOTE"
  fi
fi

RAW="$(git -C "$PROJECT" config --get remote.origin.pushurl 2>/dev/null || true)"
[ -n "$RAW" ] || RAW="$(git -C "$PROJECT" config --get remote.origin.url 2>/dev/null || true)"
KEY="$(origin_key "$RAW")"
if [ -z "$KEY" ]; then
  skip_line
fi

if [ -e "$PROJECT/notes.allow" ]; then
  if git -C "$PROJECT" ls-files --error-unmatch -- notes.allow >/dev/null 2>&1 \
     || ! git -C "$PROJECT" check-ignore -q -- notes.allow; then
    echo "notes: notes.allow is tracked or not ignored" >&2
    exit 20
  fi
fi

exec 9>"$NOTES/.git/notes-sync.lock"
if ! flock -n 9; then
  echo "notes: locked" >&2
  exit 1
fi

if ! git -C "$NOTES" fetch -q origin; then
  echo "notes: fetch failed" >&2
  exit 1
fi
BRANCH="$(git -C "$NOTES" branch --show-current)"
if [ -z "$BRANCH" ]; then
  echo "notes: notes clone is detached" >&2
  exit 1
fi
if git -C "$NOTES" rev-parse -q --verify "origin/$BRANCH" >/dev/null 2>&1; then
  if ! git -C "$NOTES" merge -q --ff-only "origin/$BRANCH"; then
    echo "notes: fetch is not a fast-forward" >&2
    exit 1
  fi
fi
if [ -n "$(git -C "$NOTES" status --porcelain)" ]; then
  echo "notes: clone is dirty" >&2
  exit 1
fi

BASE="$NOTES/.git/notes-base"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
: > "$WORK/files"
: > "$WORK/conflict"
: > "$WORK/install"
: > "$WORK/stage"
: > "$WORK/same"

is_tracked() {
  git -C "$PROJECT" ls-files --error-unmatch -- "$1" >/dev/null 2>&1
}

base_get() {
  # One notes clone serves every checkout. The base is per checkout, or a
  # second worktree of the same origin looks like a delete and never installs.
  [ -f "$BASE" ] || return 0
  awk -F '\t' -v proj="$PROJECT" -v path="$1" '$1 == proj && $2 == path { print $3; exit }' "$BASE"
}

hash_file() {
  local p="$1" real
  if [ -L "$p" ]; then
    real="$(realpath "$p")" || return 1
    inside_project "$real" || return 1
    git hash-object -- "$real"
  else
    git hash-object -- "$p"
  fi
}

add_file() {
  local rel="$1" quiet="${2:-}" real base
  safe_rel "$rel" || { warn "bad path $rel"; return 0; }
  blocked_rel "$rel" && { warn "blocked $rel"; return 0; }
  base="$(basename "$rel")"
  denied_base "$base" && { warn "denied $rel"; return 0; }
  if [ ! -e "$PROJECT/$rel" ] && [ ! -L "$PROJECT/$rel" ]; then
    # Remote-only file. A missing local path is how a fresh machine installs.
    # A tracked path stays with the project repo.
    if ! git -C "$NOTES" cat-file -e "HEAD:$KEY/$rel" 2>/dev/null; then
      [ -z "$quiet" ] && warn "missing $rel"
      return 0
    fi
    if is_tracked "$rel"; then
      [ -z "$quiet" ] && warn "tracked $rel"
      return 0
    fi
    if grep -Fxq "$rel" "$WORK/files"; then
      return 0
    fi
    printf '%s\n' "$rel" >> "$WORK/files"
    return 0
  fi
  if [ -d "$PROJECT/$rel" ] && [ ! -L "$PROJECT/$rel" ]; then
    warn "not a file $rel"
    return 0
  fi
  real="$(realpath "$PROJECT/$rel")" || { warn "unresolved $rel"; return 0; }
  inside_project "$real" || { warn "escapes $rel"; return 0; }
  if is_tracked "$rel"; then
    [ -z "$quiet" ] && warn "tracked $rel"
    return 0
  fi
  if ! git -C "$PROJECT" check-ignore -q -- "$rel"; then
    [ -z "$quiet" ] && warn "not ignored $rel"
    return 0
  fi
  if grep -Fxq "$rel" "$WORK/files"; then
    return 0
  fi
  printf '%s\n' "$rel" >> "$WORK/files"
}

add_tree() {
  local rel="$1" dir f sub real
  safe_rel "$rel" || { warn "bad path $rel"; return 0; }
  blocked_rel "$rel" && { warn "blocked $rel"; return 0; }
  if [ ! -d "$PROJECT/$rel" ]; then
    add_file "$rel"
    return 0
  fi
  if [ -L "$PROJECT/$rel" ]; then
    real="$(realpath "$PROJECT/$rel")" || { warn "unresolved $rel"; return 0; }
    inside_project "$real" || { warn "escapes $rel"; return 0; }
  fi
  dir="$PROJECT/$rel"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    sub="${f#"$PROJECT"/}"
    add_file "$sub"
  done < <(find -P "$dir" \( -type f -o -type l \) -print)
}

# Defaults. A tracked file stays with the project. A missing local file is
# installed when the notes repo has it and this checkout has no base yet.
for rel in session_compact.md session_transcript.md AGENTS.md docs/DECISIONS.md; do
  add_file "$rel" quiet
done

if [ -f "$PROJECT/notes.allow" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(trim "$line")"
    case "$line" in
      ''|'#'*) continue ;;
    esac
    if ! safe_rel "$line"; then
      warn "rejected $line"
      continue
    fi
    if blocked_rel "$line"; then
      warn "blocked $line"
      continue
    fi
    if [ -d "$PROJECT/$line" ] && [ ! -L "$PROJECT/$line" ]; then
      add_tree "$line"
    else
      add_file "$line"
    fi
  done < "$PROJECT/notes.allow"
  add_file "notes.allow"
fi

# Files already stored for this origin. Covers a machine whose worktree does
# not have them yet. Local notes.allow above is what adds a new path.
if git -C "$NOTES" rev-parse -q --verify HEAD >/dev/null 2>&1; then
  while IFS= read -r full || [ -n "$full" ]; do
    [ -n "$full" ] || continue
    case "$full" in
      "$KEY"/*) add_file "${full#"$KEY"/}" quiet ;;
    esac
  done < <(git -C "$NOTES" ls-tree -r --name-only HEAD -- "$KEY")
fi

while IFS= read -r rel || [ -n "$rel" ]; do
  [ -n "$rel" ] || continue
  notes_rel="$KEY/$rel"
  W=""
  R=""
  B=""
  if [ -e "$PROJECT/$rel" ] || [ -L "$PROJECT/$rel" ]; then
    W="$(hash_file "$PROJECT/$rel")" || { echo "notes: hash failed $rel" >&2; exit 1; }
  fi
  # rev-parse without --verify reprints a missing path on stdout. That string
  # is not a blob, and treating it as one turns the first push into a diverge.
  R="$(git -C "$NOTES" rev-parse -q --verify "HEAD:$notes_rel" 2>/dev/null || true)"
  B="$(base_get "$notes_rel")"
  if [ -z "$W" ] && [ -z "$R" ]; then
    continue
  fi
  if [ -z "$W" ] && [ -n "$R" ]; then
    if [ -z "$B" ]; then
      printf '%s\t%s\t%s\n' "$notes_rel" "$rel" "$R" >> "$WORK/install"
    elif [ "$B" != "$R" ]; then
      # Local copy is gone and the remote copy moved. Do not guess.
      printf '%s\n' "$rel" >> "$WORK/conflict"
    fi
    # B == R: this machine deleted the file. Leave the remote blob. Do not reinstall.
    continue
  fi
  if [ -n "$W" ] && [ -z "$R" ]; then
    if [ -z "$B" ] || [ "$B" = "$W" ]; then
      if [ -z "$B" ]; then
        if [ "$MODE" = "push" ]; then
          printf '%s\t%s\t%s\n' "$notes_rel" "$rel" "$W" >> "$WORK/stage"
        fi
      fi
      # B == W and remote lacks the file: do not resurrect a delete.
      continue
    fi
    printf '%s\n' "$rel" >> "$WORK/conflict"
    continue
  fi
  if [ "$W" = "$R" ]; then
    printf '%s\t%s\t%s\n' "$notes_rel" "$rel" "$W" >> "$WORK/same"
    continue
  fi
  if [ -z "$B" ]; then
    printf '%s\n' "$rel" >> "$WORK/conflict"
    continue
  fi
  if [ "$R" = "$B" ]; then
    if [ "$MODE" = "push" ]; then
      printf '%s\t%s\t%s\n' "$notes_rel" "$rel" "$W" >> "$WORK/stage"
    fi
    continue
  fi
  if [ "$W" = "$B" ]; then
    printf '%s\t%s\t%s\n' "$notes_rel" "$rel" "$R" >> "$WORK/install"
    continue
  fi
  printf '%s\n' "$rel" >> "$WORK/conflict"
done < "$WORK/files"

if [ -s "$WORK/conflict" ]; then
  echo "notes: diverge" >&2
  while IFS= read -r rel; do
    echo "notes: diverge $rel" >&2
  done < "$WORK/conflict"
  exit 23
fi

installed=0
while IFS=$'\t' read -r notes_rel rel oid; do
  [ -n "$rel" ] || continue
  dest="$PROJECT/$rel"
  mkdir -p "$(dirname "$dest")"
  tmp="$(mktemp "$dest.notes.XXXXXX")"
  if ! git -C "$NOTES" cat-file blob "HEAD:$notes_rel" > "$tmp"; then
    rm -f "$tmp"
    echo "notes: blob missing $rel" >&2
    exit 1
  fi
  mv "$tmp" "$dest"
  installed=1
done < "$WORK/install"

staged=0
while IFS=$'\t' read -r notes_rel rel oid; do
  [ -n "$rel" ] || continue
  mkdir -p "$(dirname "$NOTES/$notes_rel")"
  cp -L -- "$PROJECT/$rel" "$NOTES/$notes_rel"
  git -C "$NOTES" add -- "$notes_rel"
  staged=1
done < "$WORK/stage"

# Base tracks the blob both sides now share. Installs and unchanged files are
# recorded before the commit. Staged files are recorded only after it, so a
# sign failure leaves the old base and a clean clone.
update_base() {
  local path="$1" oid="$2" tmp
  [ -n "$path" ] && [ -n "$oid" ] || return 0
  tmp="$(mktemp)"
  if [ -f "$BASE" ]; then
    awk -F '\t' -v proj="$PROJECT" -v p="$path" '!($1 == proj && $2 == p) { print }' "$BASE" > "$tmp"
  fi
  printf '%s\t%s\t%s\n' "$PROJECT" "$path" "$oid" >> "$tmp"
  mv "$tmp" "$BASE"
}

abort_stage() {
  git -C "$NOTES" reset -q
  git -C "$NOTES" checkout -q -- .
  git -C "$NOTES" clean -qfd
}

while IFS=$'\t' read -r notes_rel rel oid; do
  [ -n "$notes_rel" ] || continue
  update_base "$notes_rel" "$oid"
done < "$WORK/same"
while IFS=$'\t' read -r notes_rel rel oid; do
  [ -n "$notes_rel" ] || continue
  update_base "$notes_rel" "$oid"
done < "$WORK/install"

if [ "$staged" -eq 1 ]; then
  body="$(awk -F '\t' 'NF { print $2 }' "$WORK/stage")"
  subject="notes: $KEY"
  commit_ok=0
  if git -C "$NOTES" diff --cached --quiet; then
    commit_ok=1
  elif git -C "$NOTES" commit -q -m "$subject" -m "$body"; then
    commit_ok=1
  else
    bash "$HOME_DIR/.agents/hooks/gpg-agent-unlock.sh" >/dev/null 2>&1 || true
    if git -C "$NOTES" commit -q -m "$subject" -m "$body"; then
      commit_ok=1
    fi
  fi
  if [ "$commit_ok" -ne 1 ]; then
    abort_stage
    echo "notes: sign failed. Run bash ~/.agents/hooks/gpg-agent-unlock.sh" >&2
    exit 1
  fi
  while IFS=$'\t' read -r notes_rel rel oid; do
    [ -n "$notes_rel" ] || continue
    update_base "$notes_rel" "$oid"
  done < "$WORK/stage"
fi

pushed=0
if [ "$MODE" = "push" ]; then
  ahead=0
  if git -C "$NOTES" rev-parse -q --verify "origin/$BRANCH" >/dev/null 2>&1; then
    ahead="$(git -C "$NOTES" rev-list --count "origin/$BRANCH..HEAD")"
  else
    ahead=1
  fi
  if [ "${ahead:-0}" -gt 0 ]; then
    # This git has no push --ff-only. A refspec without '+' already refuses a
    # non-fast-forward. merge-base rejects one before the push when the remote
    # ref exists.
    if git -C "$NOTES" rev-parse -q --verify "origin/$BRANCH" >/dev/null 2>&1; then
      if ! git -C "$NOTES" merge-base --is-ancestor "origin/$BRANCH" HEAD; then
        echo "notes: push is not a fast-forward" >&2
        exit 1
      fi
    fi
    if ! git -C "$NOTES" push -q origin "HEAD:refs/heads/$BRANCH"; then
      echo "notes: push failed" >&2
      exit 1
    fi
    pushed=1
  fi
fi

if [ "$pushed" -eq 1 ]; then
  echo "notes: pushed"
elif [ "$installed" -eq 1 ]; then
  echo "notes: pulled"
else
  echo "notes: current"
fi
exit 0
