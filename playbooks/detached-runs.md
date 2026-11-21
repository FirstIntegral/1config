# Detached runs and preview servers

Read when: you start a command that outlives the turn: a build, a sweep, a training run, or a preview server.

## Detached runs get a staleness watch — HARD RULE

Any shell work that outlives the turn — a benchmark sweep, a long build, a training run, anything
launched with `nohup`/`setsid`/background — is armed with a periodic staleness check **in the same
turn it is launched**. Default interval **10 minutes**. Never launch a multi-hour job and then
report on it only when asked.

```sh
bash ~/.agents/hooks/watch-stale.sh <pid> <logfile|-> [interval_seconds]   # default 600
```

One line per interval on stdout, so it feeds a monitor directly (each line = one notification);
it ends by itself when the pid is gone. Exit `0` watched process exited · `2` usage · `3` no such pid.

- **Watch the worker pid when you can.** Resolve it against the interpreter and script
  (`pgrep -af 'bin/python -u path/to/script.py args'`). The watch sums CPU over that pid and its
  descendants, so a `bash -c` wrapper no longer reads as a hang. `EXITED` is still about the pid
  it was given.
- **Stale means BOTH signals flat** — no log growth *and* effectively no CPU across a whole
  interval. Either alone is a normal working run: a job grinding through one expensive step is
  silent, and a job blocked on I/O still writes. Alerting on one signal produces false hangs, which
  is how a watch gets ignored.
- **Silence is not success and it is not failure either.** The watch reports what it measured
  (`alive` / `STALE` / `EXITED`) every interval, including when nothing changed. A monitor that
  only speaks on bad news is indistinguishable from a monitor that died.
- **A staleness watch is not a completion watch.** It says whether the job is moving, never whether
  it did the right thing. Pair it with something that fires once on exit and reports the tail of the
  log, and read the actual output before believing the run.
- Applies to detached/long-running **jobs** only (builds, sweeps, training). A foreground command
  that returns in a second cannot go stale, and wrapping one in a watch is noise.

### Preview / dev servers are not jobs

A local `http.server` / `npm start` / similar, launched so a screenshot or the user can hit a URL,
is **idle-by-design**. Do **not** wrap it in `watch-stale.sh` — no log growth + no CPU is the
healthy state, and the watch would cry `STALE` forever.

Grok's TUI keeps `◎ 1 command still running` for as long as that background task lives, **even
after the turn that started it has finished**. That is the TUI working, not a hang. An unexplained
status line after "done" looks like a leak.

Policy:

1. **During the turn** — fine. Name the URL.
2. **End of turn** — kill the preview unless the user still needs it. Closing line says either
   "preview killed" or "still running: `<cmd>` on :<port> — stop with X".
3. Never leave an unnamed background command.
