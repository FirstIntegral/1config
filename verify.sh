#!/usr/bin/env bash
# verify.sh — consistency check for the whole ~/.agents ecosystem.
#
# After ANY edit under ~/.agents/, run:
#   bash ~/.agents/setup.sh     # install/sync + verify (preferred)
#   bash ~/.agents/verify.sh    # check-only (this file)
#
# Exit 0 = all green. Exit 1 = at least one FAIL.
set -euo pipefail

AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
CANON="$AGENTS_HOME/AGENTS.md"
SETUP="$AGENTS_HOME/SETUP.md"
HOOKS="$AGENTS_HOME/hooks"
GUARD_DIR="$HOME/cron-jobs/agents-symlink-guard"
MEM_GUARD_DIR="$HOME/cron-jobs/claude-memory-guard"
UPD_DIR="$HOME/cron-jobs/ai-terminal-tools-update-on-boot"
UPD_SRC="$AGENTS_HOME/updater"
TEMPLATE="$AGENTS_HOME/project-template"
fail=0
warns=0

ok()   { echo "  OK    $*"; }
bad()  { echo "  FAIL  $*"; fail=1; }
note() { echo "  WARN  $*"; warns=$((warns + 1)); }
info() { echo "  INFO  $*"; }               # transient state, not a defect — never counts as a warning

echo "== ~/.agents verify — $(date) =="

# --- core files ------------------------------------------------------------
echo "[core]"
[ -f "$CANON" ]  && ok "canonical $CANON" || bad "missing canonical $CANON"
[ -f "$SETUP" ]  && ok "SETUP.md" || bad "missing SETUP.md"
[ -x "$AGENTS_HOME/setup.sh" ] && ok "setup.sh executable" || bad "setup.sh missing or not executable"
[ -x "$AGENTS_HOME/verify.sh" ] && ok "verify.sh executable" || bad "verify.sh missing or not executable"
[ -x "$AGENTS_HOME/sync.sh" ] && ok "sync.sh executable (brain → github)" || bad "sync.sh missing or not executable"
if git -C "$AGENTS_HOME" rev-parse --git-dir >/dev/null 2>&1; then
  brain_root="$(realpath "$(git -C "$AGENTS_HOME" rev-parse --show-toplevel)")"
  [ "$brain_root" = "$(realpath "$AGENTS_HOME")" ] \
    && ok "brain path is repository root" || bad "brain is nested inside repo $brain_root"
  brain_branch="$(git -C "$AGENTS_HOME" branch --show-current)"
  [ "$brain_branch" = main ] && ok "brain branch is main" || bad "brain branch is ${brain_branch:-detached}, expected main"
  # shellcheck disable=SC1091
  source "$AGENTS_HOME/hooks/brain-remote.sh"
  if brain_remote_load "$AGENTS_HOME/BRAIN_REMOTE"; then
    ok "BRAIN_REMOTE lists ${#BRAIN_REMOTE_URLS[@]} origin URL(s)"
  else
    bad "BRAIN_REMOTE missing or empty"
  fi
  mapfile -t brain_fetch_urls < <(git -C "$AGENTS_HOME" remote get-url --all origin 2>/dev/null || true)
  mapfile -t brain_push_urls < <(git -C "$AGENTS_HOME" remote get-url --push --all origin 2>/dev/null || true)
  if [ "${#brain_fetch_urls[@]}" -eq 0 ]; then
    bad "brain repo has no origin fetch URL"
  else
    for brain_remote in "${brain_fetch_urls[@]}"; do
      if brain_remote_ok "$brain_remote"; then
        ok "brain repo fetch URL → $brain_remote"
      else
        bad "brain fetch URL is not in BRAIN_REMOTE → $brain_remote"
      fi
    done
  fi
  if [ "${#brain_push_urls[@]}" -eq 0 ]; then
    bad "brain repo has no origin push URL"
  else
    for brain_remote in "${brain_push_urls[@]}"; do
      if brain_remote_ok "$brain_remote"; then
        ok "brain repo push URL → $brain_remote"
      else
        bad "brain push URL is not in BRAIN_REMOTE → $brain_remote"
      fi
    done
  fi
  [ "$(git -C "$AGENTS_HOME" config --bool commit.gpgsign 2>/dev/null || true)" = true ] \
    && ok "brain commit.gpgsign=true" || bad "brain commit.gpgsign is not true"
  brain_head_sig="$(git -C "$AGENTS_HOME" show -s --format='%G?' HEAD 2>/dev/null || true)"
  case "$brain_head_sig" in
    G|U) ok "brain HEAD has a good signature (sig=$brain_head_sig)" ;;
    *) bad "brain HEAD signature is not good (sig=${brain_head_sig:-none})" ;;
  esac
  brain_unsigned=""
  while IFS= read -r brain_commit; do
    [ -n "$brain_commit" ] || continue
    brain_sig="$(git -C "$AGENTS_HOME" show -s --format='%G?' "$brain_commit")"
    case "$brain_sig" in G|U) ;; *) brain_unsigned="$brain_commit:$brain_sig"; break ;; esac
  done < <(git -C "$AGENTS_HOME" rev-list origin/main..main 2>/dev/null || true)
  [ -z "$brain_unsigned" ] && ok "all outgoing brain commits are signed" \
    || bad "unsigned/unverifiable outgoing brain commit $brain_unsigned"
  # Dirty/ahead is normal mid-edit (verify runs before the commit), so it is INFO, not a warning.
  brain_dirty="$(git -C "$AGENTS_HOME" status --porcelain)"
  brain_ahead="$(git -C "$AGENTS_HOME" log origin/main..main --oneline 2>/dev/null || true)"
  if [ -z "$brain_dirty" ] && [ -z "$brain_ahead" ]; then
    ok "brain repo clean + pushed"
  else
    info "brain repo not yet pushed ($(printf '%s' "$brain_dirty" | grep -c . || true) dirty, $(printf '%s' "$brain_ahead" | grep -c . || true) unpushed) — finish with: bash ~/.agents/sync.sh -m \"…\""
  fi
else
  bad "$AGENTS_HOME is not a git repo (brain must be versioned + pushed)"
fi
[ -d "$TEMPLATE" ] && ok "project-template/" || bad "project-template/ missing"
for f in AGENTS.md session_compact.md session_transcript.md docs/DECISIONS.md .gitignore; do
  [ -e "$TEMPLATE/$f" ] && ok "template $f" || bad "template missing $f"
done
# Presence on disk is not enough: project-template/.gitignore self-shadows its own
# session files (they ARE its ignore patterns), so an untracked template silently
# breaks every fresh clone — happened on the first migration to a new machine.
if git -C "$AGENTS_HOME" rev-parse --git-dir >/dev/null 2>&1; then
  for f in AGENTS.md session_compact.md session_transcript.md docs/DECISIONS.md .gitignore; do
    if git -C "$AGENTS_HOME" ls-files --error-unmatch "project-template/$f" >/dev/null 2>&1; then
      ok "template $f tracked in git"
    else
      bad "template $f NOT tracked (gitignored by its own .gitignore — git add -f project-template/$f)"
    fi
  done
fi
[ -f "$AGENTS_HOME/permissions.json" ] && ok "permissions.json (canonical, all 3 tools)" || bad "permissions.json missing"
PAPER_TPL="$AGENTS_HOME/paper-template"
if [ -d "$PAPER_TPL" ]; then
  for f in main.tex build.sh lean/lakefile.toml lean/lean-toolchain lean/Paper.lean lean/.gitignore; do
    [ -e "$PAPER_TPL/$f" ] && ok "paper-template $f" || bad "paper-template missing $f"
  done
  [ -x "$PAPER_TPL/build.sh" ] || note "paper-template/build.sh not executable"
  # No-references rule: the template must never grow a bibliography again.
  if grep -qE '\\(printbibliography|addbibresource|cite\{)|biblatex' "$PAPER_TPL/main.tex" || [ -e "$PAPER_TPL/refs.bib" ]; then
    bad "paper-template has bibliography machinery (papers must be reference-free)"
  else
    ok "paper-template reference-free"
  fi
  if grep -qE '^[[:space:]]*\[\[require\]\]' "$PAPER_TPL/lean/lakefile.toml" 2>/dev/null \
     || grep -qiE '^[[:space:]]*name[[:space:]]*=[[:space:]]*"mathlib"' "$PAPER_TPL/lean/lakefile.toml" 2>/dev/null; then
    bad "paper-template lakefile has a require / mathlib (template is core-Lean only)"
  else
    ok "paper-template lakefile has no mathlib"
  fi
  if grep -qE '^leanprover/lean4:v[0-9]+\.[0-9]+\.[0-9]+$' "$PAPER_TPL/lean/lean-toolchain" 2>/dev/null; then
    ok "lean-toolchain pinned to vX.Y.Z"
  else
    bad "lean-toolchain must be exact leanprover/lean4:vX.Y.Z (not stable/nightly)"
  fi
  if grep -qE '^[[:space:]]*(sorry|admit)\b' "$PAPER_TPL/lean/Paper.lean" 2>/dev/null; then
    bad "paper-template Paper.lean contains sorry (template must actually prove)"
  else
    ok "paper-template Paper.lean has no sorry"
  fi
  if grep -q 'lake build' "$PAPER_TPL/build.sh" && grep -q 'lean/' "$PAPER_TPL/build.sh"; then
    ok "paper-template build.sh gates lake on lean/"
  else
    bad "paper-template build.sh missing lake gate"
  fi
  if grep -q 'digit-refuse.sh' "$PAPER_TPL/build.sh" \
    && [ -f "$PAPER_TPL/digit-refuse.cfg" ] \
    && [ -f "$PAPER_TPL/digit-refuse.deny" ]; then
    ok "paper-template build.sh runs digit-refuse"
  else
    bad "paper-template missing digit-refuse hook, cfg, or deny file"
  fi
  if grep -q 'scope=paper' "$PAPER_TPL/digit-refuse.cfg" \
    && ! grep -qE '^[^#]*[0-9]' "$PAPER_TPL/digit-refuse.deny"; then
    ok "paper-template digit-refuse defaults are paper scope and an empty cemetery"
  else
    bad "paper-template digit-refuse.cfg/deny drifted"
  fi
  if git -C "$AGENTS_HOME" rev-parse --git-dir >/dev/null 2>&1; then
    for f in lean/lakefile.toml lean/lean-toolchain lean/Paper.lean lean/.gitignore; do
      if git -C "$AGENTS_HOME" ls-files --error-unmatch "paper-template/$f" >/dev/null 2>&1; then
        ok "paper-template $f tracked in git"
      else
        bad "paper-template $f NOT tracked"
      fi
    done
  fi
else
  bad "paper-template/ missing (writepaper_project has no scaffold)"
fi
[ -f "$AGENTS_HOME/README.md" ] && ok "README.md (fresh-machine + opinionated defaults)" || bad "README.md missing"
[ -f "$AGENTS_HOME/docs/DECISIONS.md" ] && ok "docs/DECISIONS.md (brain ADRs)" || bad "docs/DECISIONS.md missing"
for f in check-links.sh check-claude-memory.sh load-project-agents.sh gpg-agent-unlock.sh gpg-store-passphrase.sh gpg-signing-key.sh gpg-git.sh merge-strays.sh checkpoint.sh rule-oracles.sh watch-stale.sh heredoc-rewrite.sh brain-sync.sh brain-remote.sh install-elan.sh digit-refuse.sh digit-refuse-test.sh; do
  [ -f "$HOOKS/$f" ] && ok "hooks/$f" || bad "hooks/$f missing"
  [ -x "$HOOKS/$f" ] || note "hooks/$f not executable"
  # A hook that does not parse is worse than a missing one: it fails halfway through.
  [ -f "$HOOKS/$f" ] && { bash -n "$HOOKS/$f" 2>/dev/null && ok "hooks/$f parses" || bad "hooks/$f SYNTAX ERROR"; }
done

echo "[digit-refuse]"
if grep -q 'Digit refuse' "$AGENTS_HOME/AGENTS.md" && grep -q 'Digit refuse' "$SETUP"; then
  ok "digit-refuse documented in AGENTS.md and SETUP.md"
else
  bad "digit-refuse missing from AGENTS.md or SETUP.md"
fi
if [ -x "$HOOKS/digit-refuse-test.sh" ] && bash "$HOOKS/digit-refuse-test.sh" >/tmp/digit-refuse-test.out 2>&1; then
  ok "digit-refuse fixtures"
else
  bad "digit-refuse fixtures failed — see /tmp/digit-refuse-test.out"
fi

# Every sync path must require a clean verification result. Scratch scripts let
# this test the gate without installing anything or contacting a remote.
echo "[sync.sh behaviour]"
if [ -x "$AGENTS_HOME/sync.sh" ]; then
  _syncsrc="$AGENTS_HOME/sync.sh"
  _synctmp="$(mktemp -d)"
  git -C "$_synctmp" init -q -b main
  git -C "$_synctmp" remote add origin https://github.com/FirstIntegral/1config.git
  printf '%s\n' 'https://github.com/FirstIntegral/1config.git' 'git@github.com:FirstIntegral/1config.git' > "$_synctmp/BRAIN_REMOTE"

  printf '#!/bin/sh\necho "== FAIL (fail>=1, warnings=0) =="\nexit 1\n' > "$_synctmp/verify.sh"
  chmod +x "$_synctmp/verify.sh"
  _rc=0; AGENTS_HOME="$_synctmp" bash "$_syncsrc" --no-setup >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -ne 0 ] && ok "--no-setup still refuses failed verify.sh" \
                    || bad "sync.sh --no-setup bypassed failed verification"

  printf '#!/bin/sh\necho "== PASS (warnings=1) =="\nexit 0\n' > "$_synctmp/setup.sh"
  chmod +x "$_synctmp/setup.sh"
  _rc=0; AGENTS_HOME="$_synctmp" bash "$_syncsrc" >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -ne 0 ] && ok "refuses PASS with warnings even when setup exits zero" \
                    || bad "sync.sh accepted PASS with warnings"

  printf '#!/bin/sh\necho "== PASS (warnings=0) =="\n' > "$_synctmp/verify.sh"
  printf '#!/bin/sh\ntouch "$AGENTS_HOME/setup-was-run"\n' > "$_synctmp/setup.sh"
  chmod +x "$_synctmp/verify.sh" "$_synctmp/setup.sh"
  printf 'dirty\n' > "$_synctmp/work.txt"
  _rc=0; AGENTS_HOME="$_synctmp" bash "$_syncsrc" --dry-run >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 0 ] && [ ! -e "$_synctmp/setup-was-run" ] \
    && ok "--dry-run is check-only and does not run setup.sh" \
    || bad "sync.sh --dry-run changed installation state (exit $_rc)"

  git -C "$_synctmp" config remote.origin.pushurl https://example.invalid/not-1config.git
  _rc=0; AGENTS_HOME="$_synctmp" bash "$_syncsrc" --no-setup >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -ne 0 ] && ok "refuses an unexpected origin pushurl" \
                    || bad "sync.sh accepted an unexpected origin pushurl"
  git -C "$_synctmp" config --unset-all remote.origin.pushurl

  git -C "$_synctmp" remote set-url origin https://example.invalid/not-1config.git
  _rc=0; AGENTS_HOME="$_synctmp" bash "$_syncsrc" --no-setup >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -ne 0 ] && ok "refuses an unexpected origin fetch URL" \
                    || bad "sync.sh accepted an unexpected origin fetch URL"
  git -C "$_synctmp" remote set-url origin https://github.com/FirstIntegral/1config.git

  git -C "$_synctmp" symbolic-ref HEAD refs/heads/not-main
  _rc=0; AGENTS_HOME="$_synctmp" bash "$_syncsrc" --no-setup >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -ne 0 ] && ok "refuses to sync from a branch other than main" \
                    || bad "sync.sh accepted a non-main branch"
  git -C "$_synctmp" symbolic-ref HEAD refs/heads/main

  mkdir "$_synctmp/nested"
  _rc=0; AGENTS_HOME="$_synctmp/nested" bash "$_syncsrc" --no-setup >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -ne 0 ] && ok "refuses an AGENTS_HOME nested inside another repo" \
                    || bad "sync.sh accepted a nested repo path"
  rm -rf "$_synctmp"
else
  bad "sync.sh unavailable for behaviour checks"
fi
if grep -q 'SETUP_STRICT' "$AGENTS_HOME/setup.sh"; then
  bad "setup.sh still has a lenient SETUP_STRICT path"
else
  ok "setup.sh has no lenient verification path"
fi
if grep -q 'git commit -S' "$AGENTS_HOME/sync.sh" && grep -q "format='%G?'" "$AGENTS_HOME/sync.sh" \
    && grep -q 'refs/heads/\$BRANCH:refs/remotes/origin/\$BRANCH' "$AGENTS_HOME/sync.sh"; then
  ok "sync.sh explicitly signs and verifies outgoing commits after a fresh fetch"
else
  bad "sync.sh signed-outgoing enforcement is incomplete"
fi

# checkpoint.sh behaviour, not just presence. The failure that matters is the one that
# publishes something, so the two refusals are exercised for real against a scratch dir.
echo "[checkpoint.sh behaviour]"
if [ -x "$HOOKS/checkpoint.sh" ]; then
  _cptmp="$(mktemp -d)"
  # This file runs under `set -e`, and checkpoint.sh exits nonzero BY DESIGN on every
  # refusal. Capture the code with `|| rc=$?` -- a bare call aborts verify.sh mid-section.
  _rc=0; bash "$HOOKS/checkpoint.sh" "$_cptmp" >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 10 ] && ok "refuses a non-repo (exit 10, no git init)" \
                    || bad "checkpoint.sh did not refuse a non-repo (exit $_rc, wanted 10)"
  _rc=0; bash "$HOOKS/checkpoint.sh" "$AGENTS_HOME" >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 22 ] && ok "refuses the brain checkout (exit 22)" \
                    || bad "checkpoint.sh did not refuse the brain checkout (exit $_rc, wanted 22)"
  _brainfake="$(mktemp -d)"
  git init -q "$_brainfake"
  printf 'https://example.test/brain.git\n' > "$_brainfake/BRAIN_REMOTE"
  : > "$_brainfake/setup.sh"
  : > "$_brainfake/verify.sh"
  git -C "$_brainfake" remote add origin 'https://example.test/brain.git'
  _rc=0; bash "$HOOKS/checkpoint.sh" "$_brainfake" >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 22 ] && ok "refuses a worktree whose origin is listed in BRAIN_REMOTE (exit 22)" \
                    || bad "checkpoint.sh did not refuse a brain-marked worktree (exit $_rc, wanted 22)"
  rm -rf "$_brainfake"
  [ -d "$_cptmp/.git" ] && bad "checkpoint.sh CREATED a repo — must never do that" \
                        || ok "left the non-repo alone"
  git -C "$_cptmp" init -q 2>/dev/null || true
  printf 'secret\n' > "$_cptmp/session_transcript.md"
  _rc=0; bash "$HOOKS/checkpoint.sh" "$_cptmp" >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 20 ] && ok "refuses to commit an unignored session_transcript.md (exit 20)" \
                    || bad "checkpoint.sh would have published the transcript (exit $_rc, wanted 20)"
  rm -rf "$_cptmp"

  # A clean tree with commits that never left the machine is the state where the
  # backup is most needed, and the early "nothing to commit" exit used to skip the
  # push entirely. Exercised against a real bare remote, not mocked.
  _cpwork="$(mktemp -d)"; _cpremote="$(mktemp -d)"
  git init -q --bare "$_cpremote/remote.git"
  git init -q "$_cpwork"
  git -C "$_cpwork" config user.email verify@local
  git -C "$_cpwork" config user.name verify
  git -C "$_cpwork" config commit.gpgsign false
  printf 'session_compact.md\nsession_transcript.md\n' > "$_cpwork/.gitignore"
  echo one > "$_cpwork/a.txt"
  git -C "$_cpwork" add -A && git -C "$_cpwork" commit -qm one
  git -C "$_cpwork" remote add origin "$_cpremote/remote.git"
  _br="$(git -C "$_cpwork" rev-parse --abbrev-ref HEAD)"
  git -C "$_cpwork" push -qu origin "$_br" 2>/dev/null
  echo two > "$_cpwork/b.txt"
  git -C "$_cpwork" add -A && git -C "$_cpwork" commit -qm two
  _rc=0; bash "$HOOKS/checkpoint.sh" "$_cpwork" >/dev/null 2>&1 || _rc=$?
  _remote_count="$(git -C "$_cpremote/remote.git" rev-list --count HEAD 2>/dev/null || echo 0)"
  [ "$_rc" -eq 0 ] && [ "$_remote_count" -eq 2 ] \
    && ok "pushes commits that a clean tree would otherwise strand (exit 0)" \
    || bad "checkpoint.sh left unpushed commits on a clean tree (exit $_rc, remote has $_remote_count)"
  # and with nothing unpushed either, it must still be a no-op
  _rc=0; bash "$HOOKS/checkpoint.sh" "$_cpwork" >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 3 ] && ok "clean with no locally unpushed commit is a no-op (exit 3)" \
                   || bad "checkpoint.sh did not no-op with no locally unpushed commit (exit $_rc)"
  rm -rf "$_cpwork" "$_cpremote"
else
  bad "hooks/checkpoint.sh not executable — checkpoint_project has no git half"
fi

echo "[rule oracles]"
if [ -x "$HOOKS/rule-oracles.sh" ]; then
  if bash "$HOOKS/rule-oracles.sh"; then
    ok "rule-oracles.sh fixtures"
  else
    bad "rule-oracles.sh fixtures failed"
  fi
else
  bad "hooks/rule-oracles.sh not executable"
fi
if grep -q 'rule-oracles.sh' "$CANON" && grep -q 'rule-oracles.sh' "$SETUP"; then
  ok "rule-oracles documented in AGENTS.md and SETUP.md"
else
  bad "rule-oracles missing from AGENTS.md or SETUP.md"
fi
if grep -q 'exits 22' "$CANON" && grep -q 'exits 22' "$SETUP"; then
  ok "brain checkpoint exit 22 documented in AGENTS.md and SETUP.md"
else
  bad "exit 22 missing from AGENTS.md or SETUP.md"
fi
if grep -q 'kill-tokens.deny' "$CANON" && grep -q 'kill-tokens.deny' "$SETUP"; then
  ok "kill-tokens.deny documented in AGENTS.md and SETUP.md"
else
  bad "kill-tokens.deny missing from AGENTS.md or SETUP.md"
fi
if grep -qF '**Policy:**' "$CANON" && grep -qF '**Policy:**' "$SETUP"; then
  ok "policy-key rule documented in AGENTS.md and SETUP.md"
else
  bad "policy-key rule missing from AGENTS.md or SETUP.md"
fi

echo "[policy keys]"
if [ -f "$AGENTS_HOME/docs/DECISIONS.md" ]; then
  declare -A _pol_val _pol_n
  _pol_line=0
  while IFS= read -r _pol_row || [ -n "$_pol_row" ]; do
    _pol_line=$((_pol_line + 1))
    case "$_pol_row" in
      '**Policy:** '*) ;;
      *) continue ;;
    esac
    _pol_rest="${_pol_row#\*\*Policy:\*\* }"
    if [[ "$_pol_rest" =~ ^([a-z][a-z0-9_]*)=([A-Za-z0-9._-]+)$ ]]; then
      _pk="${BASH_REMATCH[1]}"
      _pv="${BASH_REMATCH[2]}"
      if [ -n "${_pol_val[$_pk]+x}" ]; then
        bad "policy key $_pk assigned twice (${_pol_val[$_pk]} and $_pv)"
      else
        _pol_val[$_pk]="$_pv"
      fi
      _pol_n[$_pk]=$((${_pol_n[$_pk]:-0} + 1))
    elif [[ "$_pol_rest" =~ ^([a-z][a-z0-9_]*)\ superseded-by\ (.+)$ ]]; then
      _ptarget="${BASH_REMATCH[2]}"
      if grep -qxF "## $_ptarget" "$AGENTS_HOME/docs/DECISIONS.md"; then
        :
      else
        bad "policy superseded-by target missing: $_ptarget"
      fi
    else
      bad "malformed policy line $_pol_line: $_pol_rest"
    fi
  done < "$AGENTS_HOME/docs/DECISIONS.md"
  for _pk in bash_without_prompt caveman paper_author lean_scaffold; do
    if [ -n "${_pol_val[$_pk]+x}" ]; then
      ok "policy $_pk=${_pol_val[$_pk]}"
    else
      bad "policy key $_pk has no active value"
    fi
  done
  unset _pol_val _pol_n _pol_row _pol_rest _pk _pv _ptarget _pol_line
else
  bad "docs/DECISIONS.md missing — no policy keys"
fi

echo "[kill tokens]"
_killdeny="$HOOKS/kill-tokens.deny"
if [ -f "$_killdeny" ] && grep -q 'kill-tokens.deny' "$HOOKS/merge-strays.sh"; then
  ok "kill-tokens.deny present and merge-strays.sh consults it"
else
  bad "kill-tokens.deny missing or merge-strays.sh does not consult it"
fi
if [ -f "$_killdeny" ]; then
  _rc=0; bash "$HOOKS/merge-strays.sh" --check-kill "plain sentence with no retired name" >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 0 ] && ok "kill check allows text with no retired name" \
                   || bad "kill check rejected clean text (exit $_rc)"
  _tok="$(grep -vE '^[[:space:]]*(#|$)' "$_killdeny" | head -n 1 || true)"
  if [ -n "$_tok" ]; then
    _rc=0; bash "$HOOKS/merge-strays.sh" --check-kill "please revive ${_tok} now" >/dev/null 2>&1 || _rc=$?
    [ "$_rc" -eq 1 ] && ok "kill check refuses a retired name" \
                     || bad "kill check did not refuse a retired name (exit $_rc)"
    _setup_body="$(awk '
      /^```gitignore$/ { s = 1; next }
      /^```$/ && s { s = 0; next }
      !s { print }
    ' "$SETUP")"
    _kill_hit=0
    while IFS= read -r _tok || [ -n "$_tok" ]; do
      case "$_tok" in
        ''|'#'*) continue ;;
      esac
      _tok="${_tok%$'\r'}"
      for _kf in "$CANON" "$AGENTS_HOME/README.md" \
                 "$TEMPLATE/AGENTS.md" "$TEMPLATE/session_compact.md" \
                 "$TEMPLATE/session_transcript.md" "$TEMPLATE/docs/DECISIONS.md"; do
        [ -f "$_kf" ] || continue
        if grep -F -q -- "$_tok" "$_kf"; then
          bad "retired name in ${_kf#"$AGENTS_HOME"/}"
          _kill_hit=1
        fi
      done
      if printf '%s\n' "$_setup_body" | grep -F -q -- "$_tok"; then
        bad "retired name in SETUP.md outside the gitignore sample"
        _kill_hit=1
      fi
    done < "$_killdeny"
    [ "$_kill_hit" -eq 0 ] && ok "retired names absent from the prompt and templates"
  else
    ok "kill-tokens.deny is empty (legal)"
  fi
fi

# watch-stale.sh behaviour. A watch that never fires is worse than none, so the
# stale verdict and the exit line are both exercised against a real scratch process.
echo "[watch-stale.sh behaviour]"
if [ -x "$HOOKS/watch-stale.sh" ]; then
  _rc=0; bash "$HOOKS/watch-stale.sh" >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 2 ] && ok "rejects missing arguments (exit 2)" \
                   || bad "watch-stale.sh accepted missing arguments (exit $_rc, wanted 2)"
  # A pid above pid_max cannot exist, so this is the no-such-process path, not a race.
  _rc=0; bash "$HOOKS/watch-stale.sh" 4194305 - 1 >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 3 ] && ok "rejects a pid that does not exist (exit 3)" \
                   || bad "watch-stale.sh accepted a dead pid (exit $_rc, wanted 3)"
  _wstmp="$(mktemp -d)"
  : > "$_wstmp/run.log"
  sleep 3 &
  _wspid=$!
  _wsout="$(bash "$HOOKS/watch-stale.sh" "$_wspid" "$_wstmp/run.log" 1 2>&1 || true)"
  wait "$_wspid" 2>/dev/null || true
  case "$_wsout" in
    *STALE*) ok "flags an idle pid with a flat log as STALE" ;;
    *)       bad "watch-stale.sh missed a stale run: ${_wsout:-<no output>}" ;;
  esac
  case "$_wsout" in
    *EXITED*) ok "ends with EXITED once the pid is gone" ;;
    *)        bad "watch-stale.sh did not report EXITED: ${_wsout:-<no output>}" ;;
  esac
  rm -rf "$_wstmp"
else
  bad "hooks/watch-stale.sh not executable — detached runs have no staleness watch"
fi

BD="$AGENTS_HOME/boot-dashboard"
if [ -d "$BD" ]; then
  [ -x "$BD/dashboard.sh" ] && ok "boot-dashboard/dashboard.sh" || bad "boot-dashboard/dashboard.sh missing/not exec"
  [ -x "$BD/launch.sh" ] && ok "boot-dashboard/launch.sh" || bad "boot-dashboard/launch.sh missing/not exec"
  DESK_SRC="$BD/agents-boot-status.desktop"
  DESK_DST="$HOME/.config/autostart/agents-boot-status.desktop"
  if [ ! -f "$DESK_SRC" ]; then
    bad "boot-dashboard desktop source missing"
  elif grep -qE '^(OnlyShowIn|NotShowIn)=' "$DESK_SRC"; then
    bad "boot-dashboard desktop file is filtered to selected desktops"
  else
    ok "boot-dashboard XDG autostart is cross-desktop (Wayland + X11)"
  fi
  if [ -f "$DESK_DST" ]; then
    if [ -f "$DESK_SRC" ] && cmp -s <(sed "s|^Exec=.*|Exec=$BD/launch.sh|" "$DESK_SRC") "$DESK_DST"; then
      ok "installed boot-dashboard autostart matches source"
    else
      bad "installed boot-dashboard autostart differs from source (run setup.sh)"
    fi
    if grep -qE '^(OnlyShowIn|NotShowIn)=' "$DESK_DST"; then
      bad "installed boot-dashboard autostart excludes some desktops (run setup.sh)"
    else
      ok "installed boot-dashboard autostart has no desktop filter"
    fi
  else
    bad "autostart desktop missing (run setup.sh)"
  fi
else
  note "boot-dashboard/ missing"
fi

# --- symlinks (tool-facing names stay AGENTS.md / CLAUDE.md) ---------------
echo "[symlinks]"
for link in "$HOME/.grok/AGENTS.md" "$HOME/.config/opencode/AGENTS.md" "$HOME/.claude/CLAUDE.md"; do
  if [ -L "$link" ] && [ "$(readlink -f "$link")" = "$CANON" ]; then
    ok "$link → canonical"
  else
    bad "$link not a symlink to $CANON (run setup.sh)"
  fi
done

# --- hooks installed copies must match source byte-for-byte ----------------
echo "[installed guards vs hooks/]"
if [ -f "$HOOKS/check-links.sh" ] && [ -f "$GUARD_DIR/check-links.sh" ]; then
  if cmp -s "$HOOKS/check-links.sh" "$GUARD_DIR/check-links.sh"; then
    ok "symlink guard matches hooks/check-links.sh"
  else
    bad "symlink guard DRIFT — $GUARD_DIR/check-links.sh ≠ hooks/ (run setup.sh)"
  fi
else
  bad "symlink guard install missing (run setup.sh)"
fi
if [ -f "$HOOKS/check-claude-memory.sh" ] && [ -f "$MEM_GUARD_DIR/check-memory.sh" ]; then
  if cmp -s "$HOOKS/check-claude-memory.sh" "$MEM_GUARD_DIR/check-memory.sh"; then
    ok "memory guard matches hooks/check-claude-memory.sh"
  else
    bad "memory guard DRIFT — $MEM_GUARD_DIR/check-memory.sh ≠ hooks/ (run setup.sh)"
  fi
else
  bad "memory guard install missing (run setup.sh)"
fi
if [ -f "$HOOKS/merge-strays.sh" ] && [ -f "$GUARD_DIR/merge-strays.sh" ]; then
  if cmp -s "$HOOKS/merge-strays.sh" "$GUARD_DIR/merge-strays.sh"; then
    ok "stray-merge hook matches hooks/merge-strays.sh"
  else
    bad "stray-merge DRIFT — $GUARD_DIR/merge-strays.sh ≠ hooks/ (run setup.sh)"
  fi
else
  bad "stray-merge install missing (run setup.sh)"
fi

# --- tool updater installed copies must match source byte-for-byte ---------
echo "[updater vs source]"
if [ -d "$UPD_SRC" ]; then
  for s in boot-check.sh update-apps.sh on-resume.sh refresh-inventory.py; do
    if [ -f "$UPD_SRC/$s" ] && [ -f "$UPD_DIR/$s" ]; then
      if cmp -s "$UPD_SRC/$s" "$UPD_DIR/$s"; then
        ok "updater $s matches source"
      else
        bad "updater DRIFT — $UPD_DIR/$s ≠ updater/ (run setup.sh)"
      fi
    else
      bad "updater install missing: $UPD_DIR/$s (run setup.sh)"
    fi
  done
  SHIM_SRC="$UPD_SRC/system-sleep-shim.sh"
  SHIM_DST="/usr/lib/systemd/system-sleep/ai-terminal-tools-update-resume.sh"
  [ -x "$SHIM_SRC" ] && ok "updater system-sleep-shim.sh present + executable" || bad "updater system-sleep-shim.sh missing/not executable"
  if [ -f "$SHIM_DST" ]; then
    [ -x "$SHIM_DST" ] && ok "systemd resume shim executable" || bad "systemd resume shim is not executable"
    [ "$(stat -c '%U:%G' "$SHIM_DST" 2>/dev/null)" = "root:root" ] \
      && ok "systemd resume shim root-owned" || bad "systemd resume shim is not root:root"
    cmp -s "$SHIM_SRC" "$SHIM_DST" \
      && ok "systemd resume shim matches source" \
      || bad "systemd resume shim DRIFT — refresh with sudo install (see SETUP.md §7c)"
  else
    info "systemd resume shim not installed (optional): sudo install -o root -g root -m 0755 ~/.agents/updater/system-sleep-shim.sh /usr/lib/systemd/system-sleep/ai-terminal-tools-update-resume.sh"
  fi

  # Exercise user/home discovery and systemd-run arguments without scheduling a unit.
  _rstmp="$(mktemp -d)"
  _rslog="$_rstmp/systemd-run.args"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$SYSTEMD_RUN_LOG"\n' > "$_rstmp/systemd-run"
  printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$(id -u) $(id -un) no active" > "$_rstmp/loginctl"
  printf '#!/bin/sh\nprintf "%%s\\n" "%s:x:%s:%s::%s:/bin/sh"\n' \
    "$(id -un)" "$(id -u)" "$(id -g)" "$HOME" > "$_rstmp/getent"
  chmod +x "$_rstmp/systemd-run" "$_rstmp/loginctl" "$_rstmp/getent"
  _rc=0
  AI_UPDATE_DELAY=1s SYSTEMD_RUN="$_rstmp/systemd-run" LOGINCTL="$_rstmp/loginctl" \
    GETENT="$_rstmp/getent" SYSTEMD_RUN_LOG="$_rslog" \
    sh "$SHIM_SRC" post suspend >/dev/null 2>&1 || _rc=$?
  if [ "$_rc" -eq 0 ] \
      && grep -q -- "--uid=$(id -un)" "$_rslog" \
      && grep -q -- "--setenv=HOME=$HOME" "$_rslog" \
      && grep -q -- "$UPD_DIR/on-resume.sh" "$_rslog"; then
    ok "resume shim schedules updater with explicit user + home"
  else
    bad "resume shim user/home scheduling smoke failed (exit $_rc)"
  fi
  printf '#!/bin/sh\nexit 7\n' > "$_rstmp/systemd-run"
  _rc=0
  AI_UPDATE_DELAY=1s SYSTEMD_RUN="$_rstmp/systemd-run" LOGINCTL="$_rstmp/loginctl" \
    GETENT="$_rstmp/getent" sh "$SHIM_SRC" post suspend >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 1 ] && ok "resume shim propagates scheduling failure" \
                    || bad "resume shim masked scheduling failure (exit $_rc)"
  rm -rf "$_rstmp"
else
  bad "updater/ source missing (copy ~/.agents fully)"
fi

# --- gpg unlock hooks --------------------------------------------------------
echo "[gpg hooks]"
if [ -x "$HOOKS/gpg-agent-unlock.sh" ] && [ -x "$HOOKS/gpg-store-passphrase.sh" ] && [ -x "$HOOKS/gpg-signing-key.sh" ]; then
  ok "gpg hooks present + executable"
else
  bad "gpg unlock hooks missing (run setup.sh)"
fi
if [ -f "$HOOKS/gpg-keyring.py" ]; then
  ok "hooks/gpg-keyring.py present"
  if python3 -m py_compile "$HOOKS/gpg-keyring.py" 2>/dev/null; then
    ok "hooks/gpg-keyring.py compiles"
  else
    bad "hooks/gpg-keyring.py SYNTAX ERROR"
  fi
  if python3 "$HOOKS/gpg-keyring.py" self-test >/dev/null; then
    ok "gpg-keyring.py self-test (bricked-file scan + SearchItems tuple)"
  else
    bad "gpg-keyring.py self-test failed"
  fi
else
  bad "hooks/gpg-keyring.py missing"
fi
if grep -q 'SearchItems' "$HOOKS/gpg-keyring.py" && grep -q '_pick_item' "$HOOKS/gpg-keyring.py"; then
  ok "gpg-keyring.py uses SearchItems (unlocked, locked) tuple"
else
  bad "gpg-keyring.py does not handle SearchItems locked items"
fi
if grep -q 'COLLECTION_LABEL = "gpg-signing"' "$HOOKS/gpg-keyring.py" \
   && grep -q 'CreateWithMasterPassword' "$HOOKS/gpg-keyring.py"; then
  ok "gpg passphrase stored in dedicated gpg-signing collection"
else
  bad "gpg-keyring.py does not isolate a dedicated collection"
fi
if grep -q 'gpg-keyring.py' "$HOOKS/gpg-agent-unlock.sh" \
   && grep -q 'gpg-keyring.py' "$HOOKS/gpg-store-passphrase.sh"; then
  ok "unlock + store scripts call gpg-keyring.py"
else
  bad "unlock/store scripts do not call gpg-keyring.py"
fi
if [ -d "$AGENTS_HOME/vendor/jeepney" ] && [ -f "$AGENTS_HOME/vendor/jeepney/__init__.py" ]; then
  ok "vendored jeepney present (gpg keyring access)"
else
  bad "vendor/jeepney missing — gpg keyring hooks cannot run"
fi
if [ -d "$BD" ] && grep -q 'gpg-agent-unlock' "$BD/dashboard.sh" 2>/dev/null; then
  ok "boot dashboard runs gpg unlock"
else
  note "boot dashboard does not reference gpg-agent-unlock"
fi
if [ -d "$BD" ] && grep -q 'no stored passphrase' "$BD/dashboard.sh" 2>/dev/null; then
  ok "boot dashboard distinguishes unlock exit 3 (nothing stored)"
else
  bad "boot dashboard still lumps all gpg failures as keyring locked/empty"
fi
if [ -x "$HOOKS/gpg-git.sh" ] \
   && grep -q 'pinentry-mode loopback' "$HOOKS/gpg-git.sh" \
   && grep -q 'gpg-agent-unlock.sh' "$HOOKS/gpg-git.sh"; then
  ok "hooks/gpg-git.sh loopback + unlock-retry (no pinentry GUI)"
else
  bad "hooks/gpg-git.sh missing loopback unlock wrapper"
fi
_gp="$(git config --global --get gpg.program 2>/dev/null || true)"
if [ "$_gp" = "$HOOKS/gpg-git.sh" ]; then
  ok "git gpg.program → hooks/gpg-git.sh"
else
  bad "git gpg.program is '${_gp:-unset}' (run setup.sh)"
fi
if [ -d "$BD" ]; then
  _gpg_call="$(awk '/^main\(\)/{m=1} m && /check_gpg_sign/{print NR; exit}' "$BD/dashboard.sh")"
  _upd_call="$(awk '/^main\(\)/{m=1} m && /check_tool_updates/{print NR; exit}' "$BD/dashboard.sh")"
  if [ -n "$_gpg_call" ] && [ -n "$_upd_call" ] && [ "$_gpg_call" -lt "$_upd_call" ]; then
    ok "boot dashboard unlocks gpg before slow tool-update wait"
  else
    bad "boot dashboard still runs gpg unlock after tool updates (pinentry race)"
  fi
fi

# --- brain self-sync (boot dashboard pulls ~/.agents to match 1config) ------
echo "[brain sync]"
if [ -x "$HOOKS/brain-sync.sh" ]; then
  grep -q -- '--ff-only' "$HOOKS/brain-sync.sh" \
    && ok "brain-sync pulls fast-forward only" \
    || bad "brain-sync lacks --ff-only guard (must never rewrite local commits)"
  grep -q 'brain-remote.sh' "$HOOKS/brain-sync.sh" \
    && grep -q 'BRAIN_REMOTE' "$HOOKS/brain-sync.sh" \
    && ok "brain-sync validates origin against BRAIN_REMOTE" \
    || bad "brain-sync does not validate origin against BRAIN_REMOTE"
  grep -q 'BatchMode=yes' "$HOOKS/brain-sync.sh" \
    && ok "brain-sync never prompts (ssh BatchMode)" \
    || bad "brain-sync can hang on an ssh passphrase prompt at boot"
else
  bad "hooks/brain-sync.sh missing"
fi
if [ -d "$BD" ] && [ -f "$BD/dashboard.sh" ]; then
  grep -q 'check_brain_sync' "$BD/dashboard.sh" \
    && ok "boot dashboard checks brain sync" \
    || bad "boot dashboard does not check brain sync (local can drift behind 1config)"
  _bs_call="$(awk '/^main\(\)/{m=1} m && /check_brain_sync/{print NR; exit}' "$BD/dashboard.sh")"
  _vr_call="$(awk '/^main\(\)/{m=1} m && /check_verify/{print NR; exit}' "$BD/dashboard.sh")"
  if [ -n "$_bs_call" ] && [ -n "$_vr_call" ] && [ "$_bs_call" -lt "$_vr_call" ]; then
    ok "boot dashboard syncs brain before verify"
  else
    bad "boot dashboard does not sync brain before verify"
  fi
  if bash "$BD/dashboard.sh" --slip-selftest; then
    ok "boot dashboard close slip records warn/fail and writes CLEAN"
  else
    bad "boot dashboard close-slip selftest failed"
  fi
  # `out=$(cmd) || true` then `rc=$?` is always 0. A failed sync must stay a warn.
  if awk '
    /^check_brain_sync\(\)|^check_dots_sync\(\)/ { inside=1 }
    inside && /^}/ { inside=0 }
    inside && /out=/ && /\|\| true/ { bad=1 }
    END { exit bad ? 1 : 0 }
  ' "$BD/dashboard.sh"; then
    ok "boot dashboard keeps brain and dots sync exit codes"
  else
    bad "boot dashboard swallows a sync exit code with || true"
  fi
  if grep -q 'opentabletdriver' "$BD/dashboard.sh" "$BD/README.md"; then
    bad "boot dashboard still describes omarchy-dots exit 5 as opentabletdriver"
  else
    ok "boot dashboard omarchy-dots exit 5 is the sync.sh line"
  fi
  if grep -q 'close-slip.txt' "$CANON" && grep -q 'close-slip.txt' "$SETUP"; then
    ok "close slip documented in AGENTS.md and SETUP.md"
  else
    bad "close slip missing from AGENTS.md or SETUP.md"
  fi
fi

# --- flag names (must not reintroduce bare NEEDS-MERGE as the live flag) ---
echo "[flag names]"
for pair in \
  "$HOOKS/check-links.sh:NEEDS-SYMLINK-MERGE" \
  "$HOOKS/check-claude-memory.sh:NEEDS-MEMORY-MERGE" \
  "$CANON:NEEDS-SYMLINK-MERGE" \
  "$CANON:NEEDS-MEMORY-MERGE" \
  "$SETUP:NEEDS-SYMLINK-MERGE" \
  "$SETUP:NEEDS-MEMORY-MERGE"
do
  file="${pair%%:*}"
  needle="${pair##*:}"
  if grep -qF "$needle" "$file" 2>/dev/null; then
    ok "$needle present in $(basename "$file")"
  else
    bad "$needle missing from $file"
  fi
done
# Live FLAG= assignment must use the new names (legacy migration lines may still say NEEDS-MERGE)
for f in "$HOOKS/check-links.sh" "$HOOKS/check-claude-memory.sh"; do
  if grep -E '^\s*FLAG=' "$f" | grep -q 'NEEDS-SYMLINK-MERGE\|NEEDS-MEMORY-MERGE'; then
    ok "FLAG= uses new name in $(basename "$f")"
  else
    bad "FLAG= still wrong in $f"
  fi
done

# --- machine-local inventory (must not live in SETUP.md) -------------------
echo "[SETUP inventory]"
if grep -q 'TOOL_INVENTORY_START' "$SETUP"; then
  bad "SETUP.md still pins live CLI versions (belongs in gitignored inventory.local.md)"
else
  ok "SETUP.md does not pin live CLI versions"
fi
if grep -q '^inventory.local.md$' "$AGENTS_HOME/.gitignore"; then
  ok "inventory.local.md is gitignored"
else
  bad "inventory.local.md missing from .gitignore"
fi
if grep -q '^boot-dashboard/close-slip.txt$' "$AGENTS_HOME/.gitignore"; then
  ok "boot-dashboard/close-slip.txt is gitignored"
else
  bad "boot-dashboard/close-slip.txt missing from .gitignore"
fi
INV_REFRESH="$UPD_SRC/refresh-inventory.py"
if [ -f "$INV_REFRESH" ] && INV_REFRESH="$INV_REFRESH" python3 -c 'import os; p=os.environ["INV_REFRESH"]; compile(open(p, encoding="utf-8").read(), p, "exec")' 2>/dev/null; then
  if python3 "$INV_REFRESH" --self-test >/dev/null; then
    ok "inventory resolver: login PATH wins, vendor-dir fallback, no stderr versions"
  else
    bad "refresh-inventory.py --self-test failed"
  fi
  _invtmp="$(mktemp)"
  _inv_rc=0
  INVENTORY_MD="$_invtmp" INVENTORY_SOURCE=verify python3 "$INV_REFRESH" >/dev/null 2>&1 || _inv_rc=$?
  if [ "$_inv_rc" -eq 0 ]; then
    _inv_before="$(sha256sum "$_invtmp" | cut -d' ' -f1)"
    INVENTORY_MD="$_invtmp" INVENTORY_SOURCE=verify python3 "$INV_REFRESH" >/dev/null 2>&1 || _inv_rc=$?
    _inv_after="$(sha256sum "$_invtmp" | cut -d' ' -f1)"
    [ "$_inv_rc" -eq 0 ] && [ "$_inv_before" = "$_inv_after" ] \
      && ok "inventory refresh is byte-idempotent when versions are unchanged" \
      || bad "inventory refresh failed or dirtied inventory.local.md on a no-op run"
    INV_FILE="$_invtmp" python3 -c 'import os, pathlib; p=pathlib.Path(os.environ["INV_FILE"]); s=p.read_text(); p.write_text(s.replace("<!-- last refreshed:", "| Bogus Tool | 0.0.0 | x | x |\n<!-- last refreshed:", 1))'
    INVENTORY_MD="$_invtmp" INVENTORY_SOURCE=verify python3 "$INV_REFRESH" >/dev/null 2>&1 || _inv_rc=$?
    if [ "$_inv_rc" -eq 0 ] && ! grep -q 'Bogus Tool' "$_invtmp"; then
      ok "inventory refresh replaces stale or extra rows exactly"
    else
      bad "inventory refresh left stale or extra rows"
    fi
  else
    bad "inventory refresh smoke failed (exit $_inv_rc)"
  fi
  rm -f "$_invtmp"
else
  bad "updater/refresh-inventory.py missing or invalid"
fi
if grep -q 'vendor-dir fallback' "$SETUP" \
   && grep -q '\.opencode/bin' "$SETUP" \
   && grep -q 'interactive-guard' "$SETUP"; then
  ok "SETUP.md documents login PATH then vendor-dir fallback"
else
  bad "SETUP.md missing inventory vendor-dir fallback (Ubuntu .bashrc PATH vs Omarchy mise)"
fi
if grep -q 'vendor-dir fallback' "$AGENTS_HOME/docs/DECISIONS.md" \
   && grep -q 'interactive-guard' "$AGENTS_HOME/docs/DECISIONS.md"; then
  ok "docs/DECISIONS.md records inventory vendor-dir fallback ADR"
else
  bad "docs/DECISIONS.md missing inventory vendor-dir fallback ADR"
fi
if grep -q '\.update\.lock' "$AGENTS_HOME/setup.sh" && grep -q 'flock 8' "$AGENTS_HOME/setup.sh" \
    && grep -q '\.update\.lock' "$AGENTS_HOME/sync.sh" && grep -q 'AGENTS_UPDATE_LOCK_HELD=1' "$AGENTS_HOME/sync.sh" \
    && grep -q '\.update\.lock' "$UPD_SRC/update-apps.sh" && grep -q 'flock -n 9' "$UPD_SRC/update-apps.sh"; then
  ok "sync, setup, and updater share serialization lock"
else
  bad "sync/setup/updater serialization lock missing or divergent"
fi

# --- continue_project parity (SETUP must mention residue check) ------------
echo "[doc parity]"
if grep -q 'NEEDS-MEMORY-MERGE' "$SETUP" && grep -q 'continue_project' "$SETUP"; then
  ok "SETUP.md continue_project + memory flag documented"
else
  bad "SETUP.md missing continue_project / NEEDS-MEMORY-MERGE (drift from AGENTS.md)"
fi
if grep -q 'only agrees is noise' "$AGENTS_HOME/docs/DECISIONS.md" \
   && grep -q 'SOUL.md' "$AGENTS_HOME/docs/DECISIONS.md" \
   && grep -q 'personal heartbeat' "$AGENTS_HOME/docs/DECISIONS.md"; then
  ok "docs/DECISIONS.md records the OpenClaw habit ADR"
else
  bad "docs/DECISIONS.md missing the OpenClaw habit ADR"
fi
for f in "$CANON" "$SETUP"; do
  for needle in checkpoint_project writepaper_project global_brain_update create_project '~/Projects/<name>' 'Tri-tool parity' watch-stale.sh 'Preview / dev servers are not jobs' 'lake build' 'install-elan.sh' 'Herd boards' 'only agrees is noise' 'look for a maintained one' 'do not invent its contents' 'SOUL.md' 'daily diary' 'personal heartbeat' 'Red lines' 'Leaves the machine' 'opinionated default is on' 'BRAIN_REMOTE' 'local.json' 'This tree is **1config**'; do
    if grep -qF "$needle" "$f"; then
      ok "$needle present in $(basename "$f")"
    else
      bad "$needle missing from $f"
    fi
  done
done
if SETUP_MD="$SETUP" python3 - <<'PY'
import os, pathlib, re, sys
text = pathlib.Path(os.environ["SETUP_MD"]).read_text()
m = re.search(r"## 5c\. `checkpoint_project`(.*?)(?=\n## 5d\.)", text, re.S)
sys.exit(0 if m and "hooks/checkpoint.sh" in m.group(1) and "commit and push" in m.group(1) else 1)
PY
then
  ok "SETUP.md checkpoint_project includes checkpoint.sh commit/push step"
else
  bad "SETUP.md checkpoint_project omits its git half"
fi
if grep -qE '\[[0-9]+[a-z]?/[0-9]+\]' "$AGENTS_HOME/setup.sh"; then
  bad "setup.sh has stale fixed-total step banners"
else
  ok "setup.sh stage banners make no stale total-count claim"
fi
if grep -q 'user.name' "$CANON" && grep -q 'user.email' "$CANON" \
   && ! grep -qF 'math@brwsk.xyz' "$CANON" \
   && ! grep -qF 'math@brwsk.xyz' "$AGENTS_HOME/paper-template/main.tex"; then
  ok "paper author comes from git config, not a pinned personal email"
else
  bad "paper author still pinned to a personal email, or git-config rule missing"
fi
if [ -f "$AGENTS_HOME/LICENSE" ] && grep -q 'MIT License' "$AGENTS_HOME/LICENSE" \
   && grep -q 'Brusk Kawa Abdalla' "$AGENTS_HOME/LICENSE" \
   && grep -q 'FirstIntegral/1config' "$AGENTS_HOME/LICENSE"; then
  ok "MIT LICENSE credits the author and the repo"
else
  bad "LICENSE missing MIT notice, author, or repo credit"
fi
if grep -q '^local.json$' "$AGENTS_HOME/.gitignore" \
   && [ -f "$AGENTS_HOME/local.json.example" ] \
   && git -C "$AGENTS_HOME" check-ignore -q local.json \
   && ! git -C "$AGENTS_HOME" check-ignore -q local.json.example; then
  ok "local.json is gitignored; local.json.example is not"
else
  bad "local overlay is not gitignored, or local.json.example is missing"
fi
if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d["defaults"]["bash_without_prompt"] is True else 1)' "$AGENTS_HOME/permissions.json"; then
  ok "committed bash_without_prompt default is true"
else
  bad "permissions.json bash_without_prompt is not the opinionated true default"
fi
if grep -q 'Residue / conflict check' "$SETUP" || grep -q 'Residue / conflict check' "$CANON"; then
  ok "residue/conflict check wording present"
else
  note "residue/conflict check heading not found (rename?)"
fi

# --- grok config -----------------------------------------------------------
echo "[grok config]"
if command -v python3 >/dev/null; then
  if python3 - <<PY
import tomllib, pathlib, sys
p = pathlib.Path.home() / ".grok" / "config.toml"
if not p.is_file():
    print("missing config.toml"); sys.exit(1)
cfg = tomllib.loads(p.read_text())
mem = cfg.get("memory", {}).get("enabled", True)
cc = cfg.get("compat", {}).get("claude", {})
ok = (mem is False) and (cc.get("agents") is False) and (cc.get("rules") is False)
sys.exit(0 if ok else 2)
PY
  then
    ok "memory.enabled=false, compat.claude agents/rules=false"
  else
    bad "grok config switches wrong (run setup.sh)"
  fi
  [ ! -e "$HOME/.grok/memory" ] && ok "no ~/.grok/memory dir" || bad "~/.grok/memory still exists"
else
  note "python3 missing — skip TOML checks"
fi

# --- permission parity across all three tools -------------------------------
echo "[permission parity]"
PERMS_SRC="$AGENTS_HOME/permissions.json"
if ! command -v python3 >/dev/null; then
  note "python3 missing — skip permission parity check"
elif [ ! -f "$PERMS_SRC" ]; then
  bad "canonical $PERMS_SRC missing"
else
  parity_out="$(PERMS_SRC="$PERMS_SRC" python3 - <<'PY'
import json, os, pathlib, re, tomllib

def load_jsonc(path):
    raw = path.read_text()
    out, i, n, in_string, escaped = [], 0, len(raw), False, False
    while i < n:
        c = raw[i]
        if in_string:
            out.append(c)
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
            out.append(c)
            i += 1
        elif raw.startswith("//", i):
            i = raw.find("\n", i)
            if i == -1:
                break
        elif raw.startswith("/*", i):
            i = raw.find("*/", i)
            i = n if i == -1 else i + 2
        else:
            out.append(c); i += 1
    text = "".join(out)
    out, i, n, in_string, escaped = [], 0, len(text), False, False
    while i < n:
        c = text[i]
        if in_string:
            out.append(c)
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
        elif c == ',':
            j = i + 1
            while j < n and text[j].isspace():
                j += 1
            if j < n and text[j] in '}]':
                i += 1
                continue
        out.append(c); i += 1
    return json.loads("".join(out))

canon = json.loads(pathlib.Path(os.environ["PERMS_SRC"]).read_text())
_local = pathlib.Path(os.environ["PERMS_SRC"]).with_name("local.json")
if _local.is_file():
    _over = json.loads(_local.read_text())
    if "bash_without_prompt" in _over:
        canon.setdefault("defaults", {})["bash_without_prompt"] = bool(_over["bash_without_prompt"])
src = canon.get("permissions", {})
defaults = canon.get("defaults", {})
edit_on = bool(defaults.get("edit_without_prompt"))
bash_on = bool(defaults.get("bash_without_prompt"))
home = pathlib.Path.home()
want = {b: list(src.get(b, [])) for b in ("allow", "ask", "deny")}
# Live ask buckets are empty while autonomy is on (OpenCode last-match /
# Grok shell-ask would otherwise still prompt git push). Canonical json
# still lists the restore-gate rules.
if bash_on:
    want["ask"] = []
grok_want = {b: [r for r in want[b] if re.fullmatch(r"Bash\(.*\)", r)] for b in want}

def report(tool, problems, total):
    print(f"{'OK' if not problems else 'MISS'}\t{tool}\t{total if not problems else 0}/{total}\t{problems[0] if problems else ''}")

# Claude — verbatim rules in permissions.allow / permissions.ask / permissions.deny
p = home / ".claude/settings.json"
if p.is_file():
    got = json.loads(p.read_text()).get("permissions", {})
    problems = [b for b in want if got.get(b, []) != want[b]]
    report("claude", problems, sum(len(v) for v in want.values()))
else:
    print("SKIP\tclaude\t-\tno settings.json")

# Grok — verbatim rules in [permission] allow / ask / deny
p = home / ".grok/config.toml"
if p.is_file():
    got = tomllib.loads(p.read_text()).get("permission", {})
    problems = [b for b in grok_want if got.get(b, []) != grok_want[b]]
    problems += [k for k in got if k not in grok_want]
    report("grok", problems, sum(len(v) for v in grok_want.values()))
else:
    print("SKIP\tgrok\t-\tno config.toml")

# OpenCode — Bash(X) rules translated into the permission.bash map
p = home / ".config/opencode/opencode.jsonc"
def pats(bucket):
    out = []
    for r in want[bucket]:
        m = re.fullmatch(r"Bash\((.*)\)", r)
        if m and m.group(1) not in ("", "*"):
            out.append(m.group(1))
    return out
if p.is_file():
    oc_cfg = load_jsonc(p)
    got = oc_cfg.get("permission", {}).get("bash", {})
    got = got if isinstance(got, dict) else {}
    expected = {"*": "allow" if bash_on else "ask"}
    for bucket, action in (("allow", "allow"), ("ask", "ask"), ("deny", "deny")):
        if bucket == "ask" and bash_on:
            continue
        for pattern in pats(bucket):
            expected.pop(pattern, None)
            expected[pattern] = action
    problems = [] if list(got.items()) == list(expected.items()) else ["permission.bash content/order"]
    if bash_on and any(v == "ask" for v in got.values()):
        problems = problems or ["ask rules present under bash_without_prompt (last-match re-prompts git push)"]
    report("opencode", problems, len(expected))
else:
    print("SKIP\topencode\t-\tno opencode.jsonc")

# defaults.edit_without_prompt / bash_without_prompt — canonical switches, native spellings
def mode(tool, path, got, expect):
    if not path.is_file():
        print(f"SKIP\t{tool}\t-\tno {path.name}")
    elif got == expect:
        print(f"MODEOK\t{tool}\t{got or 'unset'}\t")
    else:
        print(f"MODEMISS\t{tool}\t{got or 'unset'}\t{expect or 'unset'}")

# Claude: bash_without_prompt wins → bypassPermissions; else edit → acceptEdits; else default
if bash_on:
    claude_expect = "bypassPermissions"
elif edit_on:
    claude_expect = "acceptEdits"
else:
    claude_expect = "default"
p = home / ".claude/settings.json"
mode("claude", p,
     json.loads(p.read_text()).get("permissions", {}).get("defaultMode") if p.is_file() else None,
     claude_expect)

p = home / ".grok/config.toml"
if bash_on:
    grok_expect = "always-approve"
elif edit_on:
    grok_expect = "acceptEdits"
else:
    grok_expect = "ask"
mode("grok", p,
     tomllib.loads(p.read_text()).get("ui", {}).get("permission_mode") if p.is_file() else None,
     grok_expect)

p = home / ".config/opencode/opencode.jsonc"
if p.is_file():
    oc = oc_cfg.get("permission", {})
    got_edit = oc.get("edit")
    got_bash = oc.get("bash") if isinstance(oc.get("bash"), dict) else {}
else:
    got_edit = None
    got_bash = {}
mode("opencode", p, got_edit, "allow" if edit_on else "ask")
got_ext = oc.get("external_directory") if p.is_file() else None
mode("opencode-external_directory", p, got_ext, "allow" if bash_on else "ask")
oc_bash_expect = "allow" if bash_on else "ask"
if not p.is_file():
    print(f"SKIP\topencode-bash\t-\tno opencode.jsonc")
elif got_bash.get("*") == oc_bash_expect:
    print(f"MODEOK\topencode-bash\t*={oc_bash_expect}\t")
else:
    print(f"MODEMISS\topencode-bash\t{got_bash.get('*') or 'unset'}\t{oc_bash_expect}")
PY
)" || parity_out=""
  if [ -z "$parity_out" ]; then
    bad "permission parity check failed to run"
  else
    while IFS=$'\t' read -r status tool count detail; do
      case "$status" in
        OK)       ok   "$tool permission policy exactly matches canonical ($count)" ;;
        MISS)     bad  "$tool permission policy drift ($count) at $detail — run setup.sh" ;;
        MODEOK)   ok   "$tool permission mode = $count" ;;
        MODEMISS) bad  "$tool permission mode = $count, canonical wants $detail — run setup.sh" ;;
        SKIP)     note "$tool: $detail" ;;
      esac
    done <<< "$parity_out"
  fi
fi

# --- claude SessionStart hook ----------------------------------------------
echo "[claude hook]"
if command -v python3 >/dev/null && [ -f "$HOME/.claude/settings.json" ]; then
  if python3 - <<'PY'
import json, pathlib, sys
cfg = json.loads(pathlib.Path.home().joinpath(".claude/settings.json").read_text())
starts = cfg.get("hooks", {}).get("SessionStart", [])
cmds = [h.get("command", "") for g in starts for h in g.get("hooks", [])]
sys.exit(0 if any("load-project-agents.sh" in c for c in cmds) else 1)
PY
  then
    ok "SessionStart wires load-project-agents.sh"
  else
    bad "Claude SessionStart missing load-project-agents.sh (run setup.sh)"
  fi
else
  note "no claude settings.json — skip hook check"
fi
if grep -q '2.1.277' "$CANON" && grep -q '2.1.277' "$SETUP" \
   && grep -q 'load-project-agents.sh' "$CANON" && grep -q 'load-project-agents.sh' "$SETUP" \
   && grep -q 'native AGENTS.md · hook fallback' "$AGENTS_HOME/setup-infographic.svg"; then
  ok "Claude native AGENTS.md documented; hook is the fallback"
else
  bad "Claude native AGENTS.md docs or figure caption drifted"
fi
if grep -q '2.1.219' "$CANON" "$SETUP"; then
  bad "stale Claude 2.1.219 claim still in AGENTS.md or SETUP.md"
else
  ok "stale Claude 2.1.219 claim is gone"
fi
LOADER="$HOOKS/load-project-agents.sh"
hook_case() {
  local label="$1" cwd="$2" expect="$3"
  shift 3
  local out
  out="$(cd "$cwd" && env "$@" bash "$LOADER" 2>/dev/null || true)"
  if [ "$expect" = quiet ]; then
    if [ -z "$out" ]; then ok "$label"; else bad "$label printed output"; fi
  elif printf '%s' "$out" | grep -q -- "$expect"; then
    ok "$label"
  else
    bad "$label missing [$expect]"
  fi
}
hook_base="$(mktemp -d)"
printf 'HOOK_MARKER_PLAIN\n' > "$hook_base/AGENTS.md"
hook_case "2.1.295 default mode is quiet" "$hook_base" quiet \
  AGENTS_CLAUDE_VERSION=2.1.295 AGENTS_INSTRUCTION_MODE=
hook_case "2.1.277 boundary is quiet" "$hook_base" quiet \
  AGENTS_CLAUDE_VERSION=2.1.277 AGENTS_INSTRUCTION_MODE=
hook_case "2.1.276 still injects" "$hook_base" HOOK_MARKER_PLAIN \
  AGENTS_CLAUDE_VERSION=2.1.276 AGENTS_INSTRUCTION_MODE=
hook_case "unknown version still injects" "$hook_base" HOOK_MARKER_PLAIN \
  AGENTS_CLAUDE_VERSION= AGENTS_INSTRUCTION_MODE=
hook_case "claude-md mode injects" "$hook_base" HOOK_MARKER_PLAIN \
  AGENTS_CLAUDE_VERSION=2.1.295 AGENTS_INSTRUCTION_MODE=claude-md
hook_case "managed-only mode injects" "$hook_base" HOOK_MARKER_PLAIN \
  AGENTS_CLAUDE_VERSION=2.1.295 AGENTS_INSTRUCTION_MODE=managed-only
hook_case "unknown mode injects" "$hook_base" HOOK_MARKER_PLAIN \
  AGENTS_CLAUDE_VERSION=2.1.295 AGENTS_INSTRUCTION_MODE=nope
printf 'suppress\n' > "$hook_base/CLAUDE.md"
hook_case "project CLAUDE.md makes the hook inject" "$hook_base" HOOK_MARKER_PLAIN \
  AGENTS_CLAUDE_VERSION=2.1.295 AGENTS_INSTRUCTION_MODE=
hook_case "and-mode stays quiet beside CLAUDE.md" "$hook_base" quiet \
  AGENTS_CLAUDE_VERSION=2.1.295 AGENTS_INSTRUCTION_MODE=claude-md-and-agents-md
rm -f "$hook_base/CLAUDE.md"
mkdir -p "$hook_base/.claude"
printf 'suppress\n' > "$hook_base/.claude/CLAUDE.md"
hook_case ".claude/CLAUDE.md makes the hook inject" "$hook_base" HOOK_MARKER_PLAIN \
  AGENTS_CLAUDE_VERSION=2.1.295 AGENTS_INSTRUCTION_MODE=
rm -rf "$hook_base/.claude"
printf 'suppress\n' > "$hook_base/CLAUDE.local.md"
hook_case "CLAUDE.local.md makes the hook inject" "$hook_base" HOOK_MARKER_PLAIN \
  AGENTS_CLAUDE_VERSION=2.1.295 AGENTS_INSTRUCTION_MODE=
rm -f "$hook_base/CLAUDE.local.md"
mkdir -p "$hook_base/parent/child"
printf 'HOOK_MARKER_CHILD\n' > "$hook_base/parent/child/AGENTS.md"
printf 'suppress\n' > "$hook_base/parent/CLAUDE.md"
hook_case "parent CLAUDE.md makes the hook inject" "$hook_base/parent/child" HOOK_MARKER_CHILD \
  AGENTS_CLAUDE_VERSION=2.1.295 AGENTS_INSTRUCTION_MODE=
if [ -d "$HOME/.cache" ]; then
  hook_home="$(mktemp -d "$HOME/.cache/agents-hook.XXXXXX")"
else
  hook_home="$(mktemp -d)"
fi
printf 'HOOK_MARKER_HOME\n' > "$hook_home/AGENTS.md"
hook_case "user ~/.claude/CLAUDE.md does not suppress" "$hook_home" quiet \
  AGENTS_CLAUDE_VERSION=2.1.295 AGENTS_INSTRUCTION_MODE=
hook_case "real settings, pinned 2.1.295, is quiet" "$hook_base" quiet \
  AGENTS_CLAUDE_VERSION=2.1.295
empty="$(mktemp -d)"
hook_case "no AGENTS.md stays quiet on old Claude" "$empty" quiet \
  AGENTS_CLAUDE_VERSION=2.1.200 AGENTS_INSTRUCTION_MODE=
rm -rf "$hook_base" "$hook_home" "$empty"

# --- claude PreToolUse heredoc-rewrite hook --------------------------------
echo "[claude heredoc-rewrite hook]"
HR_SH="$HOOKS/heredoc-rewrite.sh"
HR_PY="$HOOKS/heredoc-rewrite.py"
if [ -f "$HR_SH" ] && [ -f "$HR_PY" ]; then
  [ -x "$HR_SH" ] || note "hooks/heredoc-rewrite.sh not executable"
  python3 -m py_compile "$HR_PY" 2>/dev/null && ok "heredoc-rewrite.py parses" || bad "heredoc-rewrite.py SYNTAX ERROR"
  if command -v python3 >/dev/null && [ -f "$HOME/.claude/settings.json" ]; then
    if python3 - <<'PY'
import json, pathlib, sys
cfg = json.loads(pathlib.Path.home().joinpath(".claude/settings.json").read_text())
pre = cfg.get("hooks", {}).get("PreToolUse", [])
cmds = [h.get("command", "") for g in pre for h in g.get("hooks", [])]
sys.exit(0 if any("heredoc-rewrite" in c for c in cmds) else 1)
PY
    then
      ok "PreToolUse wires heredoc-rewrite.sh"
    else
      bad "PreToolUse missing heredoc-rewrite.sh (run setup.sh)"
    fi
  else
    note "no claude settings.json — skip wiring check"
  fi
  # Smoke: python3 heredoc -> rewritten + allowed; cat-append heredoc -> rewritten;
  # plain command and non-rewrite-class heredoc -> no decision (normal prompt flow).
  out="$(python3 - <<'SMOKE1' | python3 "$HR_PY"
import json
print(json.dumps({"tool_name":"Bash","tool_input":{"command":"cd '/tmp' && python3 - <<'PY'\nP = 1\nprint(f\"n={P}\")\nPY\n"}}))
SMOKE1
)"
  if printf '%s' "$out" | grep -q '"decision": *"allow"' && printf '%s' "$out" | grep -q 'python3 /'; then
    ok "smoke: python3 heredoc rewritten + allowed"
  else
    bad "smoke: python3 heredoc not rewritten (got: $(printf '%s' "$out" | head -c 120))"
  fi
  out="$(python3 - <<'SMOKE2' | python3 "$HR_PY"
import json
print(json.dumps({"tool_name":"Bash","tool_input":{"command":"cat >> docs/x.md <<'EOF'\n## 2026-08-07 entry\n(ADR-001) with 'quotes'\nEOF\n"}}))
SMOKE2
)"
  if printf '%s' "$out" | grep -q '"decision": *"allow"' && printf '%s' "$out" | grep -q 'io.py' && printf '%s' "$out" | grep -q ' a'; then
    ok "smoke: cat-append heredoc rewritten + allowed"
  else
    bad "smoke: cat-append heredoc not rewritten (got: $(printf '%s' "$out" | head -c 120))"
  fi
  out="$(python3 - <<'SMOKE3' | python3 "$HR_PY"
import json
print(json.dumps({"tool_name":"Bash","tool_input":{"command":"ls /tmp"}}))
SMOKE3
)"
  [ -z "$out" ] && ok "smoke: plain command untouched (no decision)" || bad "smoke: plain command got a decision"
  out="$(python3 - <<'SMOKE4' | python3 "$HR_PY"
import json
print(json.dumps({"tool_name":"Bash","tool_input":{"command":"sudo rm -rf / <<'EOF'\nx\nEOF\n"}}))
SMOKE4
)"
  [ -z "$out" ] && ok "smoke: sudo heredoc falls through (still prompts)" || bad "smoke: sudo heredoc got a decision"
  out="$(python3 - <<'SMOKE5' | python3 "$HR_PY"
import json
print(json.dumps({"tool_name":"Bash","tool_input":{"command":"python3 - <<EOF\nprint('x')\nEOF\n"}}))
SMOKE5
)"
  [ -z "$out" ] && ok "smoke: unquoted heredoc falls through (still prompts)" || bad "smoke: unquoted heredoc got a decision"
else
  bad "heredoc-rewrite hook files missing (run setup.sh)"
fi

# --- crontab ---------------------------------------------------------------
echo "[crontab]"
if command -v crontab >/dev/null; then
  ct="$(crontab -l 2>/dev/null || true)"
  echo "$ct" | grep -q 'agents-symlink-guard/check-links.sh' && ok "crontab symlink guard" || bad "crontab missing symlink guard"
  echo "$ct" | grep -q 'agents-symlink-guard/merge-strays.sh' && ok "crontab stray-merge" || bad "crontab missing stray-merge"
  echo "$ct" | grep -q 'claude-memory-guard/check-memory.sh' && ok "crontab memory guard" || bad "crontab missing memory guard"
  echo "$ct" | grep -q 'ai-terminal-tools-update-on-boot/boot-check.sh' && ok "crontab tool updater" || bad "crontab missing tool updater"
else
  note "crontab not available"
fi

# --- template parity: project-template/ files must equal SETUP.md §5 blocks --
echo "[template parity]"
if command -v python3 >/dev/null; then
  if TEMPLATE="$TEMPLATE" SETUP_MD="$SETUP" python3 - <<'PY'
import os, re, pathlib, sys
setup = pathlib.Path(os.environ["SETUP_MD"]).read_text()
tpl = pathlib.Path(os.environ["TEMPLATE"])
m = re.search(r"## 5\. Per-project standard.*?(?=\n## 5b\.)", setup, re.S)
if not m:
    print("section 5 not found"); sys.exit(1)
blocks = re.findall(r"```[a-z]*\n(.*?)\n```", m.group(0), re.S)
files = ["AGENTS.md", "session_compact.md", "session_transcript.md", "docs/DECISIONS.md", ".gitignore"]
if len(blocks) != len(files):
    print(f"expected {len(files)} template blocks, found {len(blocks)}"); sys.exit(1)
for b, f in zip(blocks, files):
    want = (tpl / f).read_text().rstrip("\n")
    got = b.rstrip("\n")
    if want != got:
        print(f"DRIFT: {f} != SETUP.md section 5 block"); sys.exit(1)
sys.exit(0)
PY
  then
    ok "template files match SETUP.md §5 blocks"
  else
    bad "template DRIFT vs SETUP.md §5 (make project-template/ the source of truth)"
  fi
fi

# --- local inventory vs installed binaries (INFO if a CLI is not installed) --
echo "[inventory vs installed]"
if command -v python3 >/dev/null; then
  if INV_MD="$AGENTS_HOME/inventory.local.md" INV_REFRESH="$INV_REFRESH" python3 - <<'PY'
import importlib.util, os, pathlib, re, sys
p = pathlib.Path(os.environ["INV_MD"])
if not p.is_file():
    print("inventory.local.md missing (run setup.sh)"); sys.exit(1)
spec = importlib.util.spec_from_file_location("refresh_inventory", os.environ["INV_REFRESH"])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
text = p.read_text()
rows = {}
for line in text.splitlines():
    mm = re.match(r"\|\s*([A-Za-z][A-Za-z ]*?)\s*\|\s*([^\|]+?)\s*\|", line)
    if mm:
        rows[mm.group(1).strip()] = mm.group(2).strip()
if "command not" in text.lower():
    print("inventory.local.md contains shell stderr"); sys.exit(1)
bad = []
missing = []
for label, binary, _config in mod.TOOLS:
    path = mod.resolve(binary)
    want = mod.version(binary, path)
    got = rows.get(label, "")
    if not path or want == "unknown" or got in ("unknown", "missing", ""):
        missing.append(label)
        continue
    if want != got:
        bad.append(f"{label}: inventory.local.md={got} installed={want}")
if bad:
    print(" | ".join(bad)); sys.exit(1)
if missing:
    print("not-installed: " + ", ".join(missing)); sys.exit(2)
sys.exit(0)
PY
  then
    ok "inventory.local.md matches installed binaries"
  else
    _inv_rc=$?
    if [ "$_inv_rc" -eq 2 ]; then
      info "one or more CLIs not installed yet (fresh machine is fine — inventory.local.md records missing)"
    else
      bad "inventory.local.md ≠ installed binaries (run setup.sh)"
    fi
  fi
fi

echo "[portability]"
if grep -q 'FAMILY=omarchy' "$AGENTS_HOME/setup.sh" \
   && grep -q 'ubuntu|debian' "$AGENTS_HOME/setup.sh" \
   && grep -q 'texlive-full' "$AGENTS_HOME/setup.sh" \
   && grep -q 'cronie' "$AGENTS_HOME/setup.sh"; then
  ok "setup.sh detects Omarchy/Arch vs Ubuntu/Debian and prints the install line"
else
  bad "setup.sh missing distro detection (Omarchy + Ubuntu)"
fi
if grep -q 'user.signingkey' "$HOOKS/gpg-signing-key.sh" \
   && grep -q 'signing_key' "$HOOKS/gpg-keyring.py" \
   && ! grep -qE 'GPG_SIGNING_KEY:-95FBA6E0' "$HOOKS/gpg-agent-unlock.sh"; then
  ok "GPG signing key comes from git config / env, not a hardcoded key id"
else
  bad "GPG hooks still hardcode a machine-specific key id"
fi
if grep -qi 'omarchy' "$AGENTS_HOME/README.md" \
   && grep -qi 'ubuntu' "$AGENTS_HOME/README.md" \
   && grep -q 'bash_without_prompt' "$AGENTS_HOME/README.md"; then
  ok "README.md covers Omarchy, Ubuntu, and bash_without_prompt"
else
  bad "README.md missing distro or permission-default warning"
fi
if grep -q 'bash_without_prompt' "$AGENTS_HOME/docs/DECISIONS.md" \
   && grep -qi 'omarchy' "$AGENTS_HOME/docs/DECISIONS.md"; then
  ok "docs/DECISIONS.md records autonomy + distro decisions"
else
  bad "docs/DECISIONS.md missing autonomy or distro ADR"
fi
if grep -q 'opinionated default is on' "$CANON" && grep -q 'ALWAYS ON' "$CANON"; then
  ok "AGENTS.md ships autonomy and caveman on"
else
  bad "AGENTS.md missing the opinionated autonomy or caveman default"
fi
if grep -q 'git push is not allowlisted and will prompt' "$CANON"; then
  bad "AGENTS.md still claims git push always prompts (OpenCode last-match / autonomy omit-ask)"
else
  ok "AGENTS.md does not claim git push always prompts"
fi
if grep -q 'if not bash_on:' "$AGENTS_HOME/setup.sh" \
   && grep -q 'bash_patterns("ask")' "$AGENTS_HOME/setup.sh" \
   && grep -q 'bucket == "ask" and defaults.get("bash_without_prompt")' "$AGENTS_HOME/setup.sh" \
   && grep -q 'bucket == "ask" and src.get("defaults"' "$AGENTS_HOME/setup.sh"; then
  ok "setup.sh omits ask fan-out under autonomy (Claude + Grok + OpenCode last-match)"
else
  bad "setup.sh missing omit-ask under bash_without_prompt (OpenCode last-match re-prompts git push)"
fi
if grep -qi 'omarchy' "$SETUP" && grep -qi 'ubuntu' "$SETUP"; then
  ok "SETUP.md documents Omarchy + Ubuntu"
else
  bad "SETUP.md missing distro portability section"
fi

echo "[omarchy plugin]"
PLUGIN="$AGENTS_HOME/omarchy-plugin/firstintegral.1config"
if python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); assert m["id"]=="firstintegral.1config" and m["schemaVersion"]==1 and "bar-widget" in m["kinds"] and "service" in m["kinds"]' "$PLUGIN/manifest.json"; then
  ok "firstintegral.1config manifest"
else
  bad "firstintegral.1config manifest invalid"
fi
if PYTHONDONTWRITEBYTECODE=1 python3 "$PLUGIN/bin/usage.py" --self-test >/dev/null; then
  ok "usage.py self-test"
else
  bad "usage.py self-test failed"
fi
if [ ! -f "$PLUGIN/BrainMap.qml" ] \
   && [ -f "$PLUGIN/Vitals.qml" ] \
   && grep -q 'Vitals.qml' "$PLUGIN/Panel.qml" \
   && grep -q 'brainFault' "$PLUGIN/BarWidget.qml" \
   && grep -q 'verdict' "$PLUGIN/bin/usage.py" \
   && ! grep -q 'BrainMap' "$PLUGIN/Panel.qml"; then
  ok "1config panel shows vitals instead of the map"
else
  bad "1config panel still has the map, or vitals are missing"
fi
if grep -q 'property string mode: "vitals"' "$PLUGIN/Panel.qml" \
   && grep -q 'showModels: false' "$PLUGIN/Panel.qml" \
   && grep -q 'onOpenedChanged: if (root.opened) root.mode = "vitals"' "$PLUGIN/Panel.qml" \
   && grep -q 'panel.mode = "vitals"' "$PLUGIN/BarWidget.qml" \
   && ! grep -q 'centerOnBar: true' "$PLUGIN/Panel.qml"; then
  ok "1config panel opens on vitals under the icon, models off"
else
  bad "1config panel still centred, still opens on spend, or models start on"
fi
if [ -f "$AGENTS_HOME/logo.svg" ] && grep -q 'logo.svg' "$AGENTS_HOME/README.md" \
   && grep -q 'RingMark' "$PLUGIN/BarWidget.qml" && [ -f "$PLUGIN/RingMark.qml" ]; then
  ok "1config ring mark is on the bar and the README"
else
  bad "1config ring mark missing from the bar or the README"
fi
if ! grep -q 'text: root.label' "$PLUGIN/BarWidget.qml" \
   && grep -q 'Style.bar.iconSlot' "$PLUGIN/BarWidget.qml" \
   && grep -q 'Style.bar.iconCanvas' "$PLUGIN/BarWidget.qml" \
   && ! grep -q 'var step = 18' "$PLUGIN/Panel.qml" \
   && ! grep -q '7 days' "$PLUGIN/Panel.qml" \
   && ! grep -q 'text: "Today"' "$PLUGIN/Panel.qml" \
   && ! grep -q 'TilePip' "$PLUGIN/Panel.qml" \
   && ! grep -q 'This week' "$PLUGIN/Panel.qml" \
   && ! grep -q 'dayRows' "$PLUGIN/Panel.qml" \
   && grep -q 'showQuiet' "$PLUGIN/Panel.qml" \
   && grep -q 'showModels' "$PLUGIN/Panel.qml" \
   && grep -q 'By model' "$PLUGIN/Panel.qml" \
   && grep -q 'zen/go/v1/usage' "$PLUGIN/bin/usage.py" \
   && grep -q 'Starts on first use' "$PLUGIN/bin/usage.py" \
   && grep -q 'Not on this machine' "$PLUGIN/bin/usage.py" \
   && ! grep -q 'Fireworks' "$PLUGIN/bin/usage.py" \
   && ! grep -q 'Fireworks' "$PLUGIN/Panel.qml"; then
  ok "1config bar is the ring only, spend has no today line or weekday rows, and Go windows are read"
else
  bad "1config bar still has a label, or the grid, or a today line, or weekday rows, or no Go usage URL, or no quiet toggle"
fi
if grep -q 'function tileFill' "$PLUGIN/Panel.qml" \
   && grep -q 'function tileEdge' "$PLUGIN/Panel.qml" \
   && grep -q '0.045' "$PLUGIN/Panel.qml" \
   && grep -q '0.28' "$PLUGIN/Panel.qml" \
   && grep -q '0.045' "$PLUGIN/Vitals.qml" \
   && grep -q '0.28' "$PLUGIN/Vitals.qml" \
   && ! grep -q 'root.tint(0.022)' "$PLUGIN/Panel.qml" \
   && ! grep -q 'root.tint(0.028)' "$PLUGIN/Panel.qml"; then
  ok "1config spend boxes use the vitals tile colours"
else
  bad "1config spend boxes still use a gray fill"
fi
if ! grep -q 'firstintegral.1config' "$AGENTS_HOME/setup.sh" \
   || ! grep -q 'omarchy-plugin-validate' "$AGENTS_HOME/setup.sh"; then
  bad "setup.sh does not install firstintegral.1config"
else
  ok "setup.sh installs firstintegral.1config"
fi
if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  if omarchy-plugin-validate "$PLUGIN" >/dev/null; then
    ok "omarchy-plugin-validate firstintegral.1config"
  else
    bad "omarchy-plugin-validate firstintegral.1config"
  fi
else
  info "omarchy-plugin-validate not on this machine — skipped"
fi
if [ -d "$HOME/.config/omarchy/plugins" ]; then
  if diff -rq "$PLUGIN" "$HOME/.config/omarchy/plugins/firstintegral.1config" >/dev/null; then
    ok "installed 1config plugin matches the brain copy"
  else
    bad "installed 1config plugin missing or drifted (run setup.sh)"
  fi
  if [ -f "$HOME/.config/omarchy/shell.json" ]; then
    if grep -q '"id": "firstintegral.1config"' "$HOME/.config/omarchy/shell.json"; then
      ok "shell.json bar lists firstintegral.1config"
    else
      bad "shell.json bar missing firstintegral.1config"
    fi
  else
    info "no shell.json — bar placement skipped"
  fi
else
  info "no Omarchy plugins dir — install copy not required here"
fi
if ! grep -q 'firstintegral.1config' "$AGENTS_HOME/setup-infographic.svg"; then
  bad "infographic missing firstintegral.1config"
else
  ok "infographic shows firstintegral.1config"
fi

echo "[infographic]"
if [ -f "$AGENTS_HOME/setup-infographic.svg" ] && grep -q 'setup-infographic.svg' "$SETUP"; then
  ok "setup-infographic.svg present and referenced by SETUP.md"
else
  bad "setup-infographic.svg missing or unreferenced"
fi
if grep -q 'bash_without_prompt = true' "$AGENTS_HOME/setup-infographic.svg" \
   && grep -q 'caveman always on' "$AGENTS_HOME/setup-infographic.svg" \
   && grep -q 'BRAIN_REMOTE' "$AGENTS_HOME/setup-infographic.svg" \
   && grep -qi 'Ubuntu' "$AGENTS_HOME/setup-infographic.svg"; then
  ok "infographic shows opinionated Bash autonomy, caveman, BRAIN_REMOTE, Ubuntu+Omarchy"
else
  bad "infographic still shows the safe default or omits Ubuntu / caveman / BRAIN_REMOTE"
fi
if grep -q 'vendor dirs' "$AGENTS_HOME/setup-infographic.svg" \
   && grep -q 'inventory.local.md' "$AGENTS_HOME/setup-infographic.svg"; then
  ok "infographic shows inventory vendor-dir fallback (not SETUP.md versions)"
else
  bad "infographic still pins versions in SETUP.md or omits vendor-dir fallback"
fi
if grep -q 'lean/' "$AGENTS_HOME/setup-infographic.svg" \
   && grep -q 'lake' "$AGENTS_HOME/setup-infographic.svg" \
   && grep -q 'digit-refuse' "$AGENTS_HOME/setup-infographic.svg"; then
  ok "infographic shows lean/, lake, and digit-refuse"
else
  bad "infographic missing Lean paper toolchain or digit-refuse"
fi

echo "[lean toolchain]"
if grep -q 'figures/`, `lean/`' "$CANON" && grep -q 'figures/`, `lean/`' "$SETUP"; then
  ok "writepaper first scaffold copies lean/ by default"
else
  bad "AGENTS.md/SETUP.md first scaffold list missing lean/"
fi
if grep -q 'ok       elan' "$AGENTS_HOME/setup.sh" \
   && grep -q 'MISSING  elan' "$AGENTS_HOME/setup.sh"; then
  ok "setup.sh probes elan non-fatally"
else
  bad "setup.sh missing non-fatal elan probe"
fi
if grep -qF 'Bash(elan *)' "$AGENTS_HOME/permissions.json" \
   && grep -qF 'Bash(lean *)' "$AGENTS_HOME/permissions.json" \
   && grep -qF 'Bash(lake *)' "$AGENTS_HOME/permissions.json" \
   && grep -qF 'Bash(bash ~/.agents/hooks/install-elan.sh)' "$AGENTS_HOME/permissions.json"; then
  ok "permissions.json allowlists elan/lean/lake + install hook"
else
  bad "permissions.json missing Lean allow rules"
fi
if grep -q 'docs/paper/lean/.lake/' "$TEMPLATE/.gitignore"; then
  ok "project-template gitignores docs/paper/lean/.lake/"
else
  bad "project-template .gitignore missing Lean .lake/"
fi
# lake build of the scaffold is INFO if lake is missing (fresh clone / this box before elan).
_lake=""
if command -v lake >/dev/null 2>&1; then
  _lake="$(command -v lake)"
elif [ -x "${HOME}/.elan/bin/lake" ]; then
  _lake="${HOME}/.elan/bin/lake"
fi
if [ -n "$_lake" ]; then
  _leantmp="$(mktemp -d)"
  cp -a "$PAPER_TPL/lean/." "$_leantmp/"
  if (cd "$_leantmp" && PATH="${HOME}/.elan/bin:${PATH}" "$_lake" build >/dev/null 2>&1); then
    ok "lake build of paper-template/lean/ (scratch)"
  else
    bad "lake build of paper-template/lean/ failed"
  fi
  rm -rf "$_leantmp"
else
  info "lake not on PATH — skip paper-template lake build (run hooks/install-elan.sh)"
fi

# --- summary ---------------------------------------------------------------
echo
if [ "$fail" -eq 0 ]; then
  echo "== PASS (warnings=$warns) =="
  echo "After future ~/.agents edits:  bash ~/.agents/setup.sh"
  exit 0
else
  echo "== FAIL (fail>=1, warnings=$warns) =="
  echo "Fix issues, then:  bash ~/.agents/setup.sh && bash ~/.agents/verify.sh"
  exit 1
fi
