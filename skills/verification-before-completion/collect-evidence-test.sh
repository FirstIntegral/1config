#!/usr/bin/env bash
# Fixture gate for collect-evidence.sh. Tools are stubs on PATH, so no real
# npm, cargo, or go runs and nothing touches the network.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/collect-evidence.sh"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

fail() {
  echo "collect-evidence-test: $*" >&2
  exit 1
}

# Each stub logs its call and fails when the call contains $STUB_FAIL.
mkdir -p "$ROOT/bin"
for t in npm pnpm yarn bun make cargo go pytest ruff mise just; do
  cat >"$ROOT/bin/$t" <<'STUB'
#!/bin/sh
name="$(basename "$0")"
echo "$name $*" >>"$STUB_LOG"
echo "stub $name $*"
case "$name $*" in *"$STUB_FAIL"*) echo "first noise"; echo "boom: $name $*"; exit 3 ;; esac
exit 0
STUB
  chmod +x "$ROOT/bin/$t"
done
export PATH="$ROOT/bin:$PATH"
export STUB_LOG="$ROOT/calls.log"
export STUB_FAIL="__never__"

run() {
  local dir="$1"
  shift
  : >"$STUB_LOG"
  set +e
  out="$(bash "$SCRIPT" -C "$dir" "$@" 2>&1)"
  rc=$?
  set -e
}

expect_rc() {
  [ "$rc" = "$1" ] || fail "$2: exit $rc want $1 -- $out"
}

expect_out() {
  printf '%s\n' "$out" | grep -qF -- "$1" || fail "$2: missing '$1' -- $out"
}

refuse_out() {
  if printf '%s\n' "$out" | grep -qF -- "$1"; then fail "$2: unexpected '$1' -- $out"; fi
}

fixture() {
  mkdir -p "$ROOT/$1"
  echo "$ROOT/$1"
}

# Nothing detected: exit 2, said out loud, nothing claimed.
d="$(fixture empty)"
run "$d"
expect_rc 2 empty
expect_out "NOTHING DETECTED" empty
expect_out "Nothing was verified" empty

# package.json with no lockfile: npm, fixed order, dry run calls nothing.
d="$(fixture npm)"
cat >"$d/package.json" <<'JSON'
{
  "name": "x",
  "scripts": {
    "test": "vitest run",
    "build": "tsc -p .",
    "lint": "eslint .",
    "start": "node ."
  }
}
JSON
run "$d" --dry-run
expect_rc 0 npm-dry
expect_out " 1  npm run lint" npm-dry
expect_out " 2  npm run build" npm-dry
expect_out " 3  npm run test" npm-dry
refuse_out "run start" npm-dry
[ ! -s "$STUB_LOG" ] || fail "dry run executed: $(cat "$STUB_LOG")"

# Lockfile picks the runner.
for pair in pnpm:pnpm-lock.yaml yarn:yarn.lock bun:bun.lockb bun:bun.lock; do
  pm="${pair%%:*}" lock="${pair#*:}"
  d="$(fixture "lock-$lock")"
  printf '{"scripts":{"typecheck":"tsc --noEmit"}}\n' >"$d/package.json"
  : >"$d/$lock"
  run "$d" -n
  expect_rc 0 "lock $lock"
  expect_out "$pm run typecheck" "lock $lock"
done

# npm init's placeholder test proves nothing and is skipped.
d="$(fixture placeholder)"
printf '{"scripts":{"test":"echo \\"Error: no test specified\\" && exit 1"}}\n' >"$d/package.json"
run "$d" -n
expect_rc 2 placeholder
expect_out "NOTHING DETECTED" placeholder

# Every other ecosystem in one tree.
d="$(fixture poly)"
printf 'check:\n\ttrue\ntest: build\n\ttrue\nbuild:\n\ttrue\n' >"$d/Makefile"
printf '[package]\nname = "x"\n' >"$d/Cargo.toml"
printf 'module x\n' >"$d/go.mod"
printf '[tool.ruff]\nline-length = 100\n[tool.pytest.ini_options]\n' >"$d/pyproject.toml"
printf '[tasks.lint]\nrun = "x"\n[tasks."test"]\nrun = "y"\n' >"$d/mise.toml"
printf 'build:\n    echo b\ntest arg="x":\n    echo t\nfoo := "bar"\n' >"$d/justfile"
run "$d" -n
expect_rc 0 poly
for want in "make check" "make test" "cargo clippy --all-targets -- -D warnings" "cargo test" \
  "go vet ./..." "go test ./..." "ruff check ." "pytest -q" "mise run lint" "mise run test" \
  "just build" "just test"; do
  expect_out "$want" poly
done
refuse_out "make build" poly
refuse_out "just foo" poly

# All pass: table, exit 0, every command really ran.
d="$ROOT/npm"
run "$d"
expect_rc 0 pass
expect_out "status" pass
expect_out "PASS" pass
expect_out "result: 3 passed, 0 failed, 3 run" pass
[ "$(wc -l <"$STUB_LOG" | tr -d ' ')" = 3 ] || fail "pass: want 3 calls, got $(cat "$STUB_LOG")"
refuse_out "last 20 lines" pass

# One failure: exit 1, its real exit code, its tail, and the rest still run.
STUB_FAIL="npm run build"
run "$d" --tail 1
STUB_FAIL="__never__"
expect_rc 1 fail
expect_out "FAIL        3" fail
expect_out "--- #2 npm run build: last 1 lines ---" fail
expect_out "boom: npm run build" fail
refuse_out "first noise" fail
expect_out "result: 2 passed, 1 failed, 3 run" fail
grep -q "npm run test" "$STUB_LOG" || fail "fail: later command skipped"

# .verify beats detection; comments and blanks are skipped.
printf '# local gate\n\nnpm run lint\n  make test  \n' >"$d/.verify"
run "$d" -n
expect_rc 0 dotverify
expect_out "(source: .verify)" dotverify
expect_out " 1  npm run lint" dotverify
expect_out " 2  make test" dotverify
refuse_out "npm run build" dotverify

# --cmd beats .verify.
run "$d" -n --cmd "go test ./pkg/..." --cmd "true"
expect_rc 0 cmd
expect_out "(source: --cmd)" cmd
expect_out " 1  go test ./pkg/..." cmd
refuse_out "make test" cmd

# An empty .verify is nothing to run, not a pass.
d="$(fixture emptyverify)"
printf '# nothing yet\n' >"$d/.verify"
run "$d"
expect_rc 2 emptyverify
expect_out "NOTHING TO RUN" emptyverify

# A tool that is not installed is MISSING and fails the run.
run "$d" --cmd "collect-evidence-no-such-tool --flag"
expect_rc 1 missing
expect_out "MISSING   127" missing

# Usage errors.
run "$d" --bogus
expect_rc 64 usage
run "$d" --tail x
expect_rc 64 usage-tail

echo "collect-evidence-test: ok"
