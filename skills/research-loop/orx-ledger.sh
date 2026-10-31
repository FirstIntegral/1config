#!/usr/bin/env bash
# orx-ledger.sh — read-only gates over the OpenResearch experiment DB (orx.db).
#
#   bash ~/.agents/skills/research-loop/orx-ledger.sh prior <projectId|all> [regex]
#   bash ~/.agents/skills/research-loop/orx-ledger.sh prereg-check <expId>
#   (either takes --db <path/to/orx.db>)
#
# prior         Lists experiments whose title or description matches regex
#               (case-insensitive), with run counts, latest run, and commit.
#               Exit 0 nothing matched · 3 matches printed: read them first.
# prereg-check  Passes when the experiment's description has Hypothesis:,
#               Prediction:, and Decision rule: lines and no run is done or in
#               flight. Exit 0 ok to launch · 1 not pre-registered or frozen.
# Both: 2 DB missing or schema changed · 64 usage.
#
# Opens the DB with mode=ro and never runs orx, so it sends nothing anywhere.
# DB: --db, else $ORX_DATA_DIR/orx.db, else settings.json dataDir, else
# ${XDG_DATA_HOME:-~/.local/share}/openresearch/orx.db.
set -euo pipefail

usage() { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }

db=""
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --db) [ $# -ge 2 ] || usage; db="$2"; shift ;;
    -h | --help) usage ;;
    *) args+=("$1") ;;
  esac
  shift
done
[ "${#args[@]}" -ge 2 ] || usage
cmd="${args[0]}"
case "$cmd" in
  prior) [ "${#args[@]}" -le 3 ] || usage ;;
  prereg-check) [ "${#args[@]}" -eq 2 ] || usage ;;
  *) usage ;;
esac

if [ -z "$db" ]; then
  if [ -n "${ORX_DATA_DIR:-}" ]; then
    db="$ORX_DATA_DIR/orx.db"
  else
    settings="${XDG_CONFIG_HOME:-$HOME/.config}/openresearch/settings.json"
    dir=""
    if [ -f "$settings" ] && command -v jq >/dev/null 2>&1; then
      dir="$(jq -r '.dataDir // empty' "$settings" 2>/dev/null || true)"
    fi
    db="${dir:-${XDG_DATA_HOME:-$HOME/.local/share}/openresearch}/orx.db"
  fi
fi
if [ ! -f "$db" ]; then
  echo "orx-ledger: no experiment DB at $db (no orx project yet, or pass --db)" >&2
  exit 2
fi
command -v python3 >/dev/null || { echo "orx-ledger: python3 required" >&2; exit 2; }

exec python3 - "$db" "${args[@]}" <<'PY'
import re, sqlite3, sys, time

db, cmd, target = sys.argv[1], sys.argv[2], sys.argv[3]
NEED = {
    "local_experiments": {"id", "project_id", "parent_experiment_id", "title",
                          "description", "branch_name", "archived"},
    "runs": {"id", "experiment_id", "status", "commit_sha", "created_at", "exit_code"},
}
try:
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    for table, cols in NEED.items():
        have = {r[1] for r in con.execute(f"PRAGMA table_info({table})")}
        missing = cols - have
        if missing:
            sys.exit(print(f"orx-ledger: schema changed: {table} lacks {sorted(missing)}; "
                           "use `orx project view` / `orx runs` instead", file=sys.stderr) or 2)
except sqlite3.Error as e:
    sys.exit(print(f"orx-ledger: cannot read {db}: {e}", file=sys.stderr) or 2)

def runs(exp_id):
    return con.execute(
        "SELECT id, status, exit_code, commit_sha, created_at FROM runs "
        "WHERE experiment_id = ? ORDER BY created_at", (exp_id,)).fetchall()

def stamp(ms):
    t = ms / 1000 if ms and ms > 1e11 else ms
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(t)) if t else "-"

if cmd == "prior":
    pat = re.compile(sys.argv[4] if len(sys.argv) > 4 else "", re.I)
    q = ("SELECT id, project_id, parent_experiment_id, title, description, archived "
         "FROM local_experiments")
    rows = con.execute(q + ("" if target == "all" else " WHERE project_id = ?")
                       + " ORDER BY created_at",
                       () if target == "all" else (target,)).fetchall()
    hits = [r for r in rows if pat.search(f"{r[3] or ''}\n{r[4] or ''}")]
    print("experiment\tproject\tparent\ttitle\truns\tdone\tlatest\tcommit\tat")
    for eid, pid, parent, title, _desc, archived in hits:
        rs = runs(eid)
        last = rs[-1] if rs else None
        print("\t".join([
            eid, pid, parent or "[root]",
            (title or "").replace("\t", " ") + (" [archived]" if archived else ""),
            str(len(rs)), str(sum(1 for r in rs if r[1] == "done")),
            f"{last[1]}({last[2]})" if last else "-",
            (last[3] or "-")[:12] if last else "-",
            stamp(last[4]) if last else "-",
        ]))
    print(f"prior: {len(hits)} matching of {len(rows)} experiments", file=sys.stderr)
    sys.exit(3 if hits else 0)

row = con.execute("SELECT title, description FROM local_experiments WHERE id = ?",
                  (target,)).fetchone()
if row is None:
    sys.exit(print(f"prereg-check: no experiment {target}", file=sys.stderr) or 1)
desc, bad = row[1] or "", []
for field in ("Hypothesis:", "Prediction:", "Decision rule:"):
    if not re.search(rf"^\s*[-*]?\s*\**{re.escape(field[:-1])}\**:", desc, re.I | re.M):
        bad.append(f"description lacks a '{field}' line")
rs = runs(target)
done = [r for r in rs if r[1] == "done"]
live = [r for r in rs if r[1] in ("starting", "running")]
if done:
    bad.append(f"frozen: run {done[-1][0]} is done; branch a child instead")
if live:
    bad.append(f"run {live[-1][0]} is {live[-1][1]}; wait for it")
failed = [r for r in rs if r[1] in ("failed", "lost", "cancelled")]
for msg in bad:
    print(f"  FAIL  {msg}")
if failed and not bad:
    print(f"  NOTE  {len(failed)} earlier run(s) ended failed/lost/cancelled; "
          "if one of them answered the node, it is frozen")
print(f"prereg-check: {target} ({row[0] or 'untitled'}): {'FAIL' if bad else 'ok to launch'}")
sys.exit(1 if bad else 0)
PY
