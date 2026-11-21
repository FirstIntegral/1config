#!/usr/bin/env bash
# preflight.sh — what must be true before setup.sh writes anything.
#
#   bash ~/.agents/hooks/preflight.sh            # exit 0 ready · 1 not ready · 2 usage
#   bash ~/.agents/setup.sh --preflight          # the same check, after the platform probe
#
# setup.sh ends in verify.sh, and verify.sh fails without commit signing, a
# listed origin, and a HEAD this machine can check. Finding that out at the last
# step means the tool configs, the rules links, and the schedule are already
# replaced. This script asks the same questions first and changes nothing.
# Each line it prints names the fix.
#
# It reads this checkout (the directory above hooks/), git config, the gpg
# keyring, ~/.grok/config.toml, and local.json. It writes no file and opens no network connection. gpg creates its
# home directory the first time anything asks it a question, so on a machine
# with no gpg home yet this script does not ask: no keyring means no key.
set -uo pipefail

[ $# -eq 0 ] || { echo "usage: preflight.sh" >&2; exit 2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
n=0
miss() { n=$((n + 1)); echo "  NOT READY  $1"; shift; for l in "$@"; do echo "             $l"; done; }

if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
  miss "python3 3.11 or newer is required (setup.sh reads TOML with tomllib)" \
       "found: $(python3 --version 2>&1 || echo 'no python3')"
fi

fork_hint=0
if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  miss "$ROOT is not a git checkout" \
       "fork the repo on your git host, then: git clone <your fork> $ROOT"
else
  top="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$top" ] && [ "$(cd "$top" && pwd -P)" = "$ROOT" ] \
    || miss "$ROOT sits inside another repository ($top)" "clone it as its own checkout"
  branch="$(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
  [ "$branch" = main ] \
    || miss "this checkout is on '${branch:-a detached HEAD}', and the scripts publish main" \
            "git -C $ROOT switch main"

  # shellcheck disable=SC1091
  . "$ROOT/hooks/brain-remote.sh"
  mapfile -t urls < <({ git -C "$ROOT" remote get-url --all origin 2>/dev/null
                        git -C "$ROOT" remote get-url --push --all origin 2>/dev/null; } | sort -u)
  if [ "${#urls[@]}" -eq 0 ]; then
    miss "this checkout has no origin remote" \
         "fork the repo on your git host, then: git -C $ROOT remote add origin <your fork>"
  elif ! brain_remote_load "$ROOT/BRAIN_REMOTE"; then
    miss "BRAIN_REMOTE lists no URL" "bash $ROOT/bin/1config fork-init"
    fork_hint=1
  else
    for u in "${urls[@]}"; do
      if ! brain_remote_ok "$u"; then
        miss "origin is $u, and BRAIN_REMOTE does not list it" \
             "this looks like a fork that still points at the repo it came from:" \
             "  bash $ROOT/bin/1config fork-init          # shows the four files it would rewrite" \
             "  bash $ROOT/bin/1config fork-init --yes    # writes them and makes one signed commit"
        fork_hint=1
        break
      fi
    done
  fi
fi

[ -n "$(git config --get user.name 2>/dev/null || true)" ] \
  || miss "git has no user.name" 'git config --global user.name "Your Name"'
[ -n "$(git config --get user.email 2>/dev/null || true)" ] \
  || miss "git has no user.email" 'git config --global user.email "you@example.com"'

key="$(bash "$ROOT/hooks/gpg-signing-key.sh" 2>/dev/null || true)"
have_keyring=0
[ -d "${GNUPGHOME:-$HOME/.gnupg}" ] && have_keyring=1
if ! command -v gpg >/dev/null 2>&1; then
  miss "gpg is not installed, and every commit here is signed" "install gnupg"
elif [ -z "$key" ]; then
  miss "git has no signing key" \
       "gpg --full-generate-key                      # only when you have no key yet" \
       "gpg --list-secret-keys --keyid-format=long   # find the key id" \
       "git config --global user.signingkey <KEY-ID>"
elif [ "$have_keyring" = 0 ] || ! gpg --batch --list-secret-keys "$key" >/dev/null 2>&1; then
  miss "the secret key for user.signingkey=$key is not in this machine's keyring" \
       "import it, or point user.signingkey at a key this machine holds"
fi
# git signs and checks signatures through gpg.program when one is set. A setting
# that names a program which is not there breaks both, and the error git prints
# does not say so.
gp="$(git config --get gpg.program 2>/dev/null || true)"
if [ -n "$gp" ] && ! command -v "$gp" >/dev/null 2>&1; then
  miss "git's gpg.program is '$gp', and there is no such program" \
       "git config --global --unset gpg.program    # git then calls gpg itself"
fi
[ "$(git -C "$ROOT" config --bool commit.gpgsign 2>/dev/null || true)" = true ] \
  || miss "commit.gpgsign is not true" "git config --global commit.gpgsign true"

# HEAD is only worth checking once origin is listed: on a fork that has not run
# fork-init, HEAD is the upstream owner's commit and the line above already says what to do.
if [ "$fork_hint" = 0 ] && git -C "$ROOT" rev-parse --verify -q HEAD >/dev/null 2>&1; then
  # git asks gpg for this. With no keyring there is nothing to check against.
  sig=E
  [ "$have_keyring" = 1 ] && sig="$(git -C "$ROOT" show -s --format='%G?' HEAD 2>/dev/null || true)"
  case "$sig" in
    G|U) ;;
    *) miss "the newest commit here has a signature this machine cannot check (sig=${sig:-none})" \
            "your own repo: import the public key that signed it (gpg --import <file>)" \
            "someone else's repo, cloned directly: fork it, clone your fork, then" \
            "  bash $ROOT/bin/1config fork-init" ;;
  esac
fi

# setup.sh edits two files it does not own in a way that can fail: Grok's
# config.toml (three switches, then the permission table) and local.json.
# Both are asked now, so a file setup cannot edit stops it before the first write.
if [ -f "$HOME/.grok/config.toml" ] && [ -f "$ROOT/hooks/grok-config.py" ]; then
  why="$(python3 "$ROOT/hooks/grok-config.py" switches "$HOME/.grok/config.toml" --check 2>&1)" \
    || miss "setup.sh cannot edit ~/.grok/config.toml safely" "${why#grok-config: }"
fi
if [ -f "$ROOT/local.json" ] && [ -f "$ROOT/hooks/local-rules.py" ]; then
  _lr_rc=0
  why="$(python3 "$ROOT/hooks/local-rules.py" check --local-json "$ROOT/local.json" 2>&1 >/dev/null)" || _lr_rc=$?
  [ "$_lr_rc" -ne 2 ] || miss "local.json cannot be read" "${why#local-rules: }"
fi

if [ "$n" -gt 0 ]; then
  echo "  preflight: $n thing(s) to fix. Nothing on this machine was changed."
  exit 1
fi
echo "  ok       preflight (signing, origin, and HEAD are what verify.sh will ask for)"
exit 0
