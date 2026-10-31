#!/usr/bin/env bash
# Fixture gate for orx-install.sh and orx-ledger.sh. The release is a local
# tarball holding a stub orx, HOME is a temp dir, and nothing touches the
# network or the real OpenResearch binary.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

fail() {
  echo "orx-install-test: $*" >&2
  exit 1
}

run() {
  set +e
  out="$("$@" 2>&1)"
  rc=$?
  set -e
}
expect_rc() { [ "$rc" = "$1" ] || fail "$2: exit $rc want $1 -- $out"; }
expect_out() { printf '%s\n' "$out" | grep -qF -- "$1" || fail "$2: missing '$1' -- $out"; }

case "$(uname -m)" in
  x86_64) triple=x86_64-unknown-linux-musl ;;
  aarch64 | arm64) triple=aarch64-unknown-linux-musl ;;
  *) fail "unsupported arch" ;;
esac

# Stub orx: logs argv and the telemetry env, implements `telemetry off|status`.
pkg="$ROOT/pkg/openresearch-cli-$triple"
mkdir -p "$pkg" "$ROOT/rel/v9.9.9"
cat >"$pkg/orx" <<'STUB'
#!/bin/sh
cfg="${XDG_CONFIG_HOME:-$HOME/.config}/openresearch"
echo "argv=$* env=${ORX_TELEMETRY_ENV:-unset} upd=${ORX_NO_UPDATE_CHECK:-unset}" >>"$HOME/orx-calls.log"
case "$*" in
  *"telemetry off") mkdir -p "$cfg"; printf '{\n  "telemetryDisabled": true\n}\n' >"$cfg/settings.json" ;;
  "telemetry status") echo "Anonymous usage analytics: off (disabled by ORX_TELEMETRY_ENV)" ;;
esac
STUB
chmod +x "$pkg/orx"
echo "MIT License" >"$pkg/LICENSE"
tar -cJf "$ROOT/rel/v9.9.9/openresearch-cli-$triple.tar.xz" -C "$ROOT/pkg" "openresearch-cli-$triple"
good="$(sha256sum "$ROOT/rel/v9.9.9/openresearch-cli-$triple.tar.xz" | awk '{print $1}')"
bad="$(printf '0%.0s' $(seq 64))"

export HOME="$ROOT/home" XDG_CONFIG_HOME="$ROOT/home/.config" ORX_PREFIX="$ROOT/home/.local"
export ORX_RELEASE_BASE="file://$ROOT/rel"
mkdir -p "$HOME"
INSTALL=(bash "$HERE/orx-install.sh")

# Unpinned version without --sha256 is refused before any download.
run "${INSTALL[@]}" --version v9.9.9
expect_rc 1 unpinned
expect_out "refusing unpinned v9.9.9" unpinned
[ ! -e "$ORX_PREFIX/bin/orx" ] || fail "unpinned: installed something"

# Checksum mismatch: refused, nothing installed.
run "${INSTALL[@]}" --version v9.9.9 --sha256 "$bad"
expect_rc 1 mismatch
expect_out "sha256 mismatch" mismatch
[ ! -e "$ORX_PREFIX/bin/orx" ] || fail "mismatch: installed something"

# check before install fails.
run "${INSTALL[@]}" check
expect_rc 1 "check-before-install"

# Good install: wrapper, binary, opt-out persisted with env off, check passes.
run "${INSTALL[@]}" --version v9.9.9 --sha256 "$good"
expect_rc 0 install
expect_out "sha256 ok $good" install
expect_out "telemetryDisabled=true" install
expect_out "analytics: off" install
grep -qxF "export ORX_TELEMETRY_ENV=off" "$ORX_PREFIX/bin/orx" || fail "wrapper lacks telemetry env"
[ -x "$ORX_PREFIX/lib/openresearch-cli/v9.9.9/orx" ] || fail "binary not installed"
grep -qF "argv=--no-telemetry telemetry off env=off upd=1" "$HOME/orx-calls.log" ||
  fail "opt-out did not run with ORX_TELEMETRY_ENV=off: $(cat "$HOME/orx-calls.log")"

# Idempotent re-run.
run "${INSTALL[@]}" --version v9.9.9 --sha256 "$good"
expect_rc 0 reinstall

# check fails when the opt-out is gone, and when the wrapper is foreign.
printf '{"telemetryDisabled": false}\n' >"$XDG_CONFIG_HOME/openresearch/settings.json"
run "${INSTALL[@]}" check
expect_rc 1 "check-telemetry-on"
expect_out "telemetry opt-out not persisted" "check-telemetry-on"
printf '#!/bin/sh\nexec /opt/orx "$@"\n' >"$ORX_PREFIX/bin/orx"
run "${INSTALL[@]}" check
expect_rc 1 "check-foreign"
expect_out "not the 1config wrapper" "check-foreign"
run "${INSTALL[@]}" --version v9.9.9 --sha256 "$good"
expect_rc 1 "install-over-foreign"
expect_out "move it aside" "install-over-foreign"

# ---- orx-ledger.sh against a fixture DB with orx's column names.
command -v python3 >/dev/null || fail "python3 required"
LEDGER=(bash "$HERE/orx-ledger.sh")
data="$ROOT/data"
mkdir -p "$data"
python3 - "$data/orx.db" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.executescript("""
CREATE TABLE local_experiments (id TEXT PRIMARY KEY, project_id TEXT, parent_experiment_id TEXT,
  slug TEXT, branch_name TEXT, title TEXT, description TEXT, run_command TEXT,
  created_at INTEGER, archived INTEGER DEFAULT 0);
CREATE TABLE runs (id TEXT PRIMARY KEY, experiment_id TEXT, project_id TEXT, status TEXT,
  exit_code INTEGER, commit_sha TEXT, created_at INTEGER);
INSERT INTO local_experiments VALUES
 ('e1','p1',NULL,'base','orx/base','Baseline','Hypothesis: x\nPrediction: y\nDecision rule: z','make',1,0),
 ('e2','p1','e1','lr','orx/lr','LR 3e-5','**Hypothesis:** lower LR converges\n**Prediction:** loss<0.1\n**Decision rule:** keep if loss<0.1','make',2,0),
 ('e3','p1','e1','mom','orx/mom','Momentum 0.9','try momentum','make',3,0),
 ('e4','p2',NULL,'other','orx/o','Other project','Hypothesis: a\nPrediction: b\nDecision rule: c','make',4,0);
INSERT INTO runs VALUES
 ('r1','e1','p1','done',0,'abcdef1234567890',1761900000000),
 ('r2','e2','p1','failed',1,'1111111111111111',1761900001000);
""")
c.commit()
PY
export ORX_DATA_DIR="$data"

run "${LEDGER[@]}" prior p1 'learning rate|lr '
expect_rc 3 prior-hit
expect_out "LR 3e-5" prior-hit
expect_out "prior: 1 matching of 3" prior-hit
run "${LEDGER[@]}" prior p1 'transformer'
expect_rc 0 prior-miss
run "${LEDGER[@]}" prior all
expect_rc 3 prior-all
expect_out "Other project" prior-all
run "${LEDGER[@]}" prereg-check e1
expect_rc 1 frozen
expect_out "frozen: run r1 is done" frozen
run "${LEDGER[@]}" prereg-check e2
expect_rc 0 prereg-ok
expect_out "earlier run(s) ended failed" prereg-ok
run "${LEDGER[@]}" prereg-check e3
expect_rc 1 prereg-missing
expect_out "lacks a 'Hypothesis:' line" prereg-missing
run "${LEDGER[@]}" prereg-check nope
expect_rc 1 unknown-exp
run "${LEDGER[@]}" --db "$ROOT/none.db" prior all
expect_rc 2 no-db
run "${LEDGER[@]}" prior
expect_rc 64 usage
python3 -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute('ALTER TABLE runs RENAME COLUMN commit_sha TO sha'); c.commit()" "$data/orx.db"
run "${LEDGER[@]}" prior all
expect_rc 2 schema-changed
expect_out "schema changed" schema-changed

echo "orx-install-test: ok"
