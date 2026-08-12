#!/usr/bin/env bash
# watch-stale.sh — staleness watch for a long-running detached run.
#
#   bash ~/.agents/hooks/watch-stale.sh <pid> <logfile|-> [interval_seconds]
#
# Prints ONE line per interval on stdout, so it can be fed straight to a
# monitor: every line becomes a notification. Ends when the pid is gone.
#
# Why this exists: "it has been quiet for a while" is not evidence of a hang,
# and neither is "CPU looks low" when the pid being watched is a bash wrapper
# that burns nothing while its child does the work. Stale is BOTH signals flat
# over a full interval — no log growth AND effectively no CPU. A run that is
# silently grinding through one expensive step trips neither.
#
# Exit codes: 0 = watched process exited · 2 = bad usage · 3 = no such pid.
set -uo pipefail

usage() {
    cat >&2 <<'EOF'
usage: watch-stale.sh <pid> <logfile|-> [interval_seconds]

  pid       PID of the REAL worker process, not a shell wrapper around it.
            Find it with: pgrep -af '<interpreter> -u <script> <args>'
  logfile   file the run appends to; "-" to watch CPU only
  interval  seconds between checks (default 600)
EOF
}

[ $# -ge 2 ] || { usage; exit 2; }
case "$1" in -h|--help) usage; exit 0 ;; esac

PID="$1"
LOG="$2"
INTERVAL="${3:-600}"

case "$PID" in ''|*[!0-9]*) echo "watch-stale: pid must be a number: $PID" >&2; exit 2 ;; esac
case "$INTERVAL" in ''|*[!0-9]*) echo "watch-stale: interval must be a number: $INTERVAL" >&2; exit 2 ;; esac
[ "$INTERVAL" -gt 0 ] || { echo "watch-stale: interval must be > 0" >&2; exit 2; }
[ -d "/proc/$PID" ] || { echo "watch-stale: no such pid: $PID" >&2; exit 3; }

TICKS_PER_SEC="$(getconf CLK_TCK 2>/dev/null || echo 100)"
MIN_TICKS="$TICKS_PER_SEC"        # under 1s of CPU in a whole interval counts as flat

log_size() {
    [ "$LOG" = "-" ] && { echo 0; return; }
    stat -c %s "$LOG" 2>/dev/null || echo 0
}

# /proc/<pid>/stat fields 14 (utime) + 15 (stime), in clock ticks. The comm field
# can contain spaces and parens, so cut everything through the last ')' first.
cpu_ticks() {
    local raw rest
    raw="$(cat "/proc/$1/stat" 2>/dev/null)" || return 1
    rest="${raw#*) }"
    awk '{print $12 + $13}' <<<"$rest" 2>/dev/null || return 1
}

last_stage() {
    [ "$LOG" = "-" ] && return 0
    grep -aE '^(==|\[|Traceback|Error|FAILED)' "$LOG" 2>/dev/null | tail -1
}

prev_size="$(log_size)"
prev_cpu="$(cpu_ticks "$PID" || echo 0)"
elapsed=0

while true; do
    sleep "$INTERVAL"
    elapsed=$(( elapsed + INTERVAL ))
    mins=$(( elapsed / 60 ))

    if [ ! -d "/proc/$PID" ]; then
        tail_line=""
        [ "$LOG" = "-" ] || tail_line="$(tail -1 "$LOG" 2>/dev/null)"
        echo "[+${mins}m] EXITED — pid $PID gone.${tail_line:+ Last log line: $tail_line}"
        exit 0
    fi

    size="$(log_size)"
    cpu="$(cpu_ticks "$PID")" || cpu="$prev_cpu"

    d_size=$(( size - prev_size ))
    d_cpu=$(( cpu - prev_cpu ))
    cpu_sec=$(( d_cpu / TICKS_PER_SEC ))
    stage="$(last_stage)"

    if [ "$d_size" -eq 0 ] && [ "$d_cpu" -lt "$MIN_TICKS" ]; then
        echo "[+${mins}m] STALE — no log growth and ${cpu_sec}s CPU over ${INTERVAL}s.${stage:+ Last: $stage}"
    else
        echo "[+${mins}m] alive — +${d_size}B log, ${cpu_sec}s CPU.${stage:+ Last: $stage}"
    fi

    prev_size="$size"
    prev_cpu="$cpu"
done
