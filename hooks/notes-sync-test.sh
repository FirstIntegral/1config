#!/usr/bin/env bash
# notes-sync-test.sh — fixtures for hooks/notes-sync.sh.
#
#   bash hooks/notes-sync-test.sh
#
# Two scratch "machines" share one bare notes repository. Each case runs the
# real script and judges it by its exit code, its last stdout line, and the
# bytes that reached the project or the notes repository. One line per case:
# `ok <what>` or `FAIL <what>`. Exit 1 when any case fails. verify.sh replays
# the lines. Nothing here touches the real notes clone or a network.
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")" && pwd -P)"
NS="$HOOKS/notes-sync.sh"
T="$(mktemp -d)"
cleanup() {
  [ -d "$T/gnupg" ] && gpgconf --homedir "$T/gnupg" --kill all >/dev/null 2>&1
  rm -rf "$T"
}
trap cleanup EXIT

printf '%s\n' '[user]' '	name = verify' '	email = verify@local' \
  '[init]' '	defaultBranch = main' '[commit]' '	gpgsign = false' \
  '[tag]' '	gpgSign = false' > "$T/gitconfig"
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1 GIT_URL_SSH_CONFIG=/dev/null
unset GIT_DIR GIT_WORK_TREE NOTES_SYNC_HOME NOTES_REMOTE_FILE NOTES_SYNC_TEST_GATE

# has PATTERN... — "does the piped text match", for use after a pipe. It reads
# all of its input before it searches. grep -q stops at the first match, the
# writer then dies of SIGPIPE, and under pipefail the pipeline is false although
# the text was found (and `! writer | grep -q X` is then true although X is
# there). Some greps stop early with output to /dev/null as well, so the input
# is taken whole first and grep reads it from a here-string.
has() {
  local _has_text
  _has_text="$(cat)"
  grep -q "$@" <<<"$_has_text"
}
fails=0
pass() { echo "ok $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

ORIGIN='git@github.com:fixture-owner/notes-case.git'
KEYDIR='github.com/fixture-owner/notes-case'

# A bare notes repository with one commit, and a clone of it per machine.
new_notes_bare() {
  local b seed
  b="$(mktemp -d -p "$T")/n.git"
  git init -q --bare "$b"
  seed="$(mktemp -d -p "$T")"
  git init -q "$seed"
  echo readme > "$seed/README.md"
  git -C "$seed" add README.md && git -C "$seed" commit -qm readme
  git -C "$seed" push -q "$b" HEAD:main
  git -C "$b" symbolic-ref HEAD refs/heads/main
  printf '%s\n' "$b"
}
new_notes_clone() {
  local c
  c="$(mktemp -d -p "$T")/notes"
  git clone -q "$1" "$c"
  printf '%s\n' "$c"
}
# A project checkout with the origin URL in $1 (default ORIGIN).
new_project() {
  local p
  p="$(mktemp -d -p "$T")/proj"
  mkdir -p "$p"
  git init -q "$p"
  echo code > "$p/a.txt"
  printf '%s\n' 'session_compact.md' 'notes.allow' '.env' 'private/' 'id_rsa' '.netrc' '*.p12' \
    'sub/session_transcript.md' 'sub/explain/' > "$p/.gitignore"
  git -C "$p" add a.txt .gitignore && git -C "$p" commit -qm code
  git -C "$p" remote add origin "${1:-$ORIGIN}"
  printf '%s\n' "$p"
}
# run MODE NOTES_CLONE PROJECT [VAR=VALUE ...] — exit code in RC, last stdout line in OUT.
run() {
  local mode="$1" notes="$2" proj="$3"
  shift 3
  RC=0
  OUT="$(env NOTES_SYNC_TEST_ROOT="$notes" "$@" bash "$NS" "$mode" "$proj" 2>"$T/err")" || RC=$?
  OUT="$(printf '%s\n' "$OUT" | tail -n 1)"
}

# --- a new clone at an old path is a new checkout -------------------------------
bare="$(new_notes_bare)"
n1="$(new_notes_clone "$bare")"
p1="$(new_project)"
echo compact-one > "$p1/session_compact.md"
run push "$n1" "$p1"
rm -rf "$p1"
mkdir -p "$p1"
git init -q "$p1"
echo code > "$p1/a.txt"
printf 'session_compact.md\n' > "$p1/.gitignore"
git -C "$p1" add -A && git -C "$p1" commit -qm code
git -C "$p1" remote add origin "$ORIGIN"
run pull "$n1" "$p1"
if [ "$RC" -eq 0 ] && [ "$OUT" = "notes: pulled" ] \
   && [ "$(cat "$p1/session_compact.md" 2>/dev/null)" = "compact-one" ]; then
  pass "a project cloned again at the same path gets its notes back"
else
  fail "a project cloned again at the same path stayed empty (exit $RC, out $OUT)"
fi

# A file this checkout deleted on purpose is still not put back.
rm -f "$p1/session_compact.md"
run pull "$n1" "$p1"
if [ "$RC" -eq 0 ] && [ ! -e "$p1/session_compact.md" ]; then
  pass "a file deleted in a checkout that keeps its git directory is not put back"
else
  fail "a local delete was put back (exit $RC, out $OUT)"
fi

# --- a notes commit that never left this machine --------------------------------
# Machine 1 commits and cannot push. Machine 2 pushes. Machine 1 must recover
# by itself, and both machines' text must be in the result.
bare="$(new_notes_bare)"
n1="$(new_notes_clone "$bare")"
n2="$(new_notes_clone "$bare")"
p1="$(new_project)"
p2="$(new_project)"
printf 'shared\n' > "$p1/session_compact.md"
run push "$n1" "$p1"
run pull "$n2" "$p2"
printf 'shared\nfrom-one\n' > "$p1/session_compact.md"
git -C "$n1" remote set-url --push origin "$T/no-such.git"
run push "$n1" "$p1"
first_rc=$RC
git -C "$n1" remote set-url --push origin "$bare"
printf 'from-two\nshared\n' > "$p2/session_compact.md"
run push "$n2" "$p2"
run push "$n1" "$p1"
if [ "$first_rc" -eq 1 ] && [ "$RC" -eq 0 ] \
   && grep -q 'from-one' "$p1/session_compact.md" && grep -q 'from-two' "$p1/session_compact.md" \
   && git -C "$bare" show "main:$KEYDIR/session_compact.md" | has 'from-one' \
   && git -C "$bare" show "main:$KEYDIR/session_compact.md" | has 'from-two'; then
  pass "an unpushed notes commit and a push from the other machine are merged, not stuck"
else
  fail "an unpushed notes commit left the notes clone stuck (exit $RC, out $OUT: $(tail -n 1 "$T/err"))"
fi
run push "$n1" "$p1"
if [ "$RC" -eq 0 ] && [ "$OUT" = "notes: current" ] \
   && [ -n "$(git -C "$n1" for-each-ref refs/notes-sync/parked)" ]; then
  pass "the commit that was set aside is kept under refs/notes-sync/parked"
else
  fail "the set-aside commit is gone, or the next run is not current (exit $RC, out $OUT)"
fi

# --- a copy that shrank is not replaced by the longer one -----------------------
bare="$(new_notes_bare)"
n1="$(new_notes_clone "$bare")"
n2="$(new_notes_clone "$bare")"
p1="$(new_project)"
p2="$(new_project)"
printf 'done-item\nopen-one\nopen-two\ndone-too\n' > "$p1/session_compact.md"
run push "$n1" "$p1"
run pull "$n2" "$p2"
printf 'open-one\nopen-two\n' > "$p2/session_compact.md"
run push "$n2" "$p2"
printf 'open-one\nopen-two\ndone-too\n' > "$p1/session_compact.md"
run push "$n1" "$p1"
if [ "$RC" -eq 0 ] && [ "$(cat "$p1/session_compact.md")" = "$(printf 'open-one\nopen-two')" ]; then
  pass "an item both machines saw removed does not come back"
else
  fail "a removed item came back (exit $RC, out $OUT): $(tr '\n' '|' < "$p1/session_compact.md")"
fi

# Both machines only added lines, and one copy holds the other: the longer one is right.
bare="$(new_notes_bare)"
n1="$(new_notes_clone "$bare")"
n2="$(new_notes_clone "$bare")"
p1="$(new_project)"
p2="$(new_project)"
printf 'top\n' > "$p1/session_compact.md"
run push "$n1" "$p1"
run pull "$n2" "$p2"
printf 'top\nline-a\n' > "$p2/session_compact.md"
run push "$n2" "$p2"
printf 'top\nline-a\nline-b\n' > "$p1/session_compact.md"
run push "$n1" "$p1"
if [ "$RC" -eq 0 ] && [ "$(cat "$p1/session_compact.md")" = "$(printf 'top\nline-a\nline-b')" ]; then
  pass "when both machines only added lines, the copy that holds the other wins"
else
  fail "two additive copies were not folded into the longer one (exit $RC, out $OUT)"
fi

# --- a key that would leave the notes clone -------------------------------------
bare="$(new_notes_bare)"
n1="$(new_notes_clone "$bare")"
before="$(git -C "$n1" rev-parse HEAD)"
for url in 'https://github.com/../../escape.git' 'https://../../escape.git' 'git@github.com:../escape.git' \
           'https://github.com/owner/..' 'https://github.com/.git/hooks.git'; do
  p1="$(new_project "$url")"
  echo leak > "$p1/session_compact.md"
  run push "$n1" "$p1"
  if [ "$RC" -ne 0 ] || [ "$OUT" != "notes: skipped" ] || [ "$(git -C "$n1" rev-parse HEAD)" != "$before" ] \
     || [ -n "$(git -C "$n1" status --porcelain)" ] \
     || [ -n "$(find "$(dirname "$n1")" "$(dirname "$(dirname "$n1")")" -maxdepth 2 -name session_compact.md -not -path "$p1/*" 2>/dev/null)" ]; then
    fail "an origin of $url wrote notes (exit $RC, out $OUT)"
    url=""
    break
  fi
done
[ -n "$url" ] && pass "an origin whose key has a .. or a dot name is skipped and writes nothing"

# --- names that never ride, at any depth, and through a symlink -----------------
bare="$(new_notes_bare)"
n1="$(new_notes_clone "$bare")"
p1="$(new_project)"
mkdir -p "$p1/sub/explain" "$p1/private"
echo transcript > "$p1/sub/session_transcript.md"
echo explainer > "$p1/sub/explain/brief.md"
echo KEY > "$p1/id_rsa"
echo machine > "$p1/.netrc"
echo cert > "$p1/store.p12"
echo SECRET=1 > "$p1/.env"
ln -s ../.env "$p1/private/settings.md"
echo fine > "$p1/private/ok.md"
printf '%s\n' 'sub/session_transcript.md' 'sub/explain' 'id_rsa' '.netrc' 'store.p12' \
  'private/settings.md' 'private/ok.md' > "$p1/notes.allow"
run push "$n1" "$p1"
rode="$(git -C "$n1" ls-files -- "$KEYDIR" | sed "s|^$KEYDIR/||" | sort | tr '\n' ' ')"
if [ "$RC" -eq 0 ] && [ "$rode" = "notes.allow private/ok.md " ] \
   && ! git -C "$n1" grep -q 'SECRET=1' HEAD 2>/dev/null; then
  pass "a nested transcript, a nested explain/, a key file, and a link to .env do not ride"
else
  fail "a blocked name rode to the notes repository (exit $RC): $rode"
fi

# --- the signature gate on what the pull takes ----------------------------------
if command -v gpg >/dev/null 2>&1; then
  mkdir -m 700 "$T/gnupg"
  for u in one two; do
    GNUPGHOME="$T/gnupg" gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
      --quick-generate-key "fixture-$u <$u@fixture.invalid>" ed25519 sign never >/dev/null 2>&1 || true
  done
  k1="$(GNUPGHOME="$T/gnupg" gpg --batch --list-keys --with-colons one@fixture.invalid 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')"
  k2="$(GNUPGHOME="$T/gnupg" gpg --batch --list-keys --with-colons two@fixture.invalid 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')"
  printf '%s\n' "$k1" > "$T/signers"
  gate=(NOTES_SYNC_TEST_GATE=1 GNUPGHOME="$T/gnupg" BRAIN_SIGNERS_FILE="$T/signers" GPG_SIGNING_KEY="$k1")
  # other_machine_commit NOTES_CLONE KEY|- TEXT — a notes commit from "the other machine".
  other_machine_commit() {
    local notes="$1" key="$2" text="$3"
    mkdir -p "$notes/$KEYDIR"
    printf '%s\n' "$text" > "$notes/$KEYDIR/session_compact.md"
    git -C "$notes" add -- "$KEYDIR/session_compact.md"
    if [ "$key" = "-" ]; then
      git -C "$notes" commit -q -m "notes: $KEYDIR"
    else
      GNUPGHOME="$T/gnupg" git -C "$notes" -c user.signingkey="$key" commit -q -S -m "notes: $KEYDIR"
    fi
    git -C "$notes" push -q origin HEAD:main
  }
  if [ -n "$k1" ] && [ -n "$k2" ]; then
    for case in "-:unsigned" "$k2:signed by a key that is not listed"; do
      bare="$(new_notes_bare)"
      n1="$(new_notes_clone "$bare")"
      n2="$(new_notes_clone "$bare")"
      p1="$(new_project)"
      other_machine_commit "$n2" "${case%%:*}" planted
      before="$(git -C "$n1" rev-parse HEAD)"
      run pull "$n1" "$p1" "${gate[@]}"
      if [ "$RC" -eq 1 ] && [ ! -e "$p1/session_compact.md" ] \
         && [ "$(git -C "$n1" rev-parse HEAD)" = "$before" ] && grep -q 'refused' "$T/err"; then
        pass "a notes commit that is ${case#*:} is not taken (exit 1)"
      else
        fail "a notes commit that is ${case#*:} was installed (exit $RC, out $OUT)"
      fi
    done
    bare="$(new_notes_bare)"
    n1="$(new_notes_clone "$bare")"
    n2="$(new_notes_clone "$bare")"
    p1="$(new_project)"
    other_machine_commit "$n2" "$k1" trusted
    run pull "$n1" "$p1" "${gate[@]}"
    if [ "$RC" -eq 0 ] && [ "$OUT" = "notes: pulled" ] && [ "$(cat "$p1/session_compact.md" 2>/dev/null)" = "trusted" ]; then
      pass "a notes commit signed by a listed key is taken"
    else
      fail "a notes commit signed by a listed key was refused (exit $RC, out $OUT: $(tail -n 1 "$T/err"))"
    fi
  else
    fail "the notes signature fixtures could not make their keys"
  fi
else
  fail "the notes signature fixtures need gpg"
fi

[ "$fails" -eq 0 ]
