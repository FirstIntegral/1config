#!/usr/bin/env python3
"""Local AI-usage snapshot for the 1config Omarchy plugin.

Reads ledgers already on this machine. Does not call a provider, and does not
emit paths, prompts, credentials, or message text.

  usage.py            one JSON object on stdout
  usage.py --self-test
"""

from __future__ import annotations

import json
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path


FACE = {
    "claude": "Claude",
    "grok": "Grok",
    "opencode": "OpenCode",
    "codex": "Codex",
    "fireworks": "Fireworks",
}

CORE_IDS = ("claude", "grok", "opencode")


def parse_time(value: object) -> datetime | None:
    text = str(value or "").strip()
    if not text:
        return None
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def as_local(moment: datetime, now: datetime) -> datetime:
    return moment.astimezone(now.tzinfo)


def clean_status(value: object) -> str:
    text = " ".join(str(value or "").split())[:160]
    lowered = text.lower()
    if "@" in text or "bearer" in lowered or "sk-" in lowered:
        return ""
    if "token" in lowered and len(text) > 80:
        return ""
    return text


def as_percent(value: object, *, fraction_if_unit: bool) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    if number < 0:
        return None
    if fraction_if_unit and number <= 1:
        number *= 100
    return round(number, 1)


def format_cost(amount: float | None) -> str:
    if amount is None:
        return "—"
    number = float(amount)
    sign = "-" if number < 0 else ""
    number = abs(number)
    if number == 0:
        return "$0"
    if number < 0.01:
        text = f"{number:.4f}".rstrip("0").rstrip(".")
        return sign + "$" + text
    return sign + f"${number:.2f}"


def as_float(value: object) -> float:
    if isinstance(value, bool) or value is None:
        return 0.0
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def clean_model(value: object) -> str:
    text = str(value or "").strip()
    if not text or "@" in text or any(ord(ch) < 32 for ch in text):
        return ""
    return "".join(ch for ch in text if ch.isalnum() or ch in "-_.")[:48]


def format_tokens(count: int | None) -> str:
    if count is None:
        return "—"
    number = int(count)
    sign = "-" if number < 0 else ""
    number = abs(number)
    if number < 1000:
        return sign + str(number)
    if number < 1_000_000:
        text = f"{number / 1000:.1f}".rstrip("0").rstrip(".")
        return sign + text + "k"
    text = f"{number / 1_000_000:.1f}".rstrip("0").rstrip(".")
    return sign + text + "M"


def int_or_zero(value: object) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return 0
    return int(value)


def omarchy_agent(path: Path) -> dict | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(data, dict):
        return None
    limits = []
    for entry in data.get("limits") or []:
        if not isinstance(entry, dict):
            continue
        used = as_percent(entry.get("percent"), fraction_if_unit=True)
        if used is None:
            continue
        limits.append(
            {
                "label": str(entry.get("label") or "Limit")[:80],
                "usedPct": used,
                "resetsAt": str(entry.get("resetsAt") or "")[:40],
            }
        )
    messages = 0
    for day in data.get("recentDays") or []:
        if isinstance(day, dict):
            messages += int_or_zero(day.get("messageCount"))
    today = int_or_zero(data.get("todayTotalTokens"))
    return {
        "id": str(data.get("id") or path.stem)[:40],
        "name": str(data.get("name") or path.stem)[:40],
        "source": "omarchy",
        "sourceLabel": "Omarchy usage record",
        "ready": bool(data.get("ready")),
        "status": clean_status(data.get("usageStatusText")),
        "todayTokens": today,
        "todayLabel": format_tokens(today),
        "weekTokens": None,
        "weekLabel": f"{messages} msgs" if messages else "—",
        "todayPrompts": int_or_zero(data.get("todayPrompts")),
        "todaySessions": int_or_zero(data.get("todaySessions")),
        "updatedAt": str(data.get("updatedAt") or "")[:40],
        "limits": limits,
        "models": [],
    }


def grok_agent(home: Path, now: datetime) -> dict:
    week_start = now - timedelta(days=7)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    slack = (week_start - timedelta(days=1)).timestamp()
    today_tokens = 0
    week_tokens = 0
    week_turns = 0
    models: dict[str, int] = defaultdict(int)
    root = home / ".grok" / "sessions"
    if root.is_dir():
        for path in root.rglob("usage.json"):
            try:
                if path.stat().st_mtime < slack:
                    continue
                payload = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            if not isinstance(payload, dict):
                continue
            for turn in payload.get("turns") or []:
                if not isinstance(turn, dict):
                    continue
                ended = parse_time(turn.get("endedAt"))
                if ended is None:
                    continue
                ended = as_local(ended, now)
                if ended < week_start:
                    continue
                tokens = int_or_zero(turn.get("totalTokens"))
                week_tokens += tokens
                week_turns += 1
                if ended >= today_start:
                    today_tokens += tokens
                model = str(turn.get("primaryModelId") or "")[:64]
                if model and "\n" not in model and "@" not in model:
                    models[model] += tokens
    limits = []
    measured = ""
    billing = last_billing(home / ".grok" / "logs" / "unified.jsonl")
    if billing is not None:
        ctx = billing.get("ctx") if isinstance(billing.get("ctx"), dict) else {}
        config = ctx.get("config") if isinstance(ctx.get("config"), dict) else {}
        used = as_percent(config.get("creditUsagePercent"), fraction_if_unit=False)
        # A 0–1 reading is a fraction some snapshots use. Above 1 is already a percent.
        if used is not None and 0 < used <= 1:
            used = round(used * 100, 1)
        period = config.get("currentPeriod") if isinstance(config.get("currentPeriod"), dict) else {}
        resets = str(period.get("end") or config.get("billingPeriodEnd") or "")[:40]
        if used is not None:
            limits.append({"label": "Credits", "usedPct": used, "resetsAt": resets})
        measured = str(billing.get("ts") or "")[:40]
    top = sorted(models.items(), key=lambda item: item[1], reverse=True)[:3]
    status = ""
    if not root.is_dir() and not limits:
        status = "No Grok session ledger on this machine"
    return {
        "id": "grok",
        "name": "Grok",
        "source": "grok-sessions",
        "sourceLabel": "Grok session ledger + last credits snapshot",
        "ready": week_turns > 0 or bool(limits),
        "status": status,
        "todayTokens": today_tokens,
        "todayLabel": format_tokens(today_tokens),
        "weekTokens": week_tokens,
        "weekLabel": format_tokens(week_tokens),
        "todayPrompts": 0,
        "todaySessions": 0,
        "weekTurns": week_turns,
        "updatedAt": measured,
        "limits": limits,
        "models": [{"id": name, "tokens": tokens, "label": format_tokens(tokens)} for name, tokens in top],
    }


def last_billing(path: Path) -> dict | None:
    if not path.is_file():
        return None
    try:
        size = path.stat().st_size
        with path.open("rb") as handle:
            handle.seek(max(0, size - 1_500_000))
            blob = handle.read().decode("utf-8", "replace")
    except OSError:
        return None
    found = None
    for line in blob.splitlines():
        if "billing: fetched credits config" not in line:
            continue
        try:
            parsed = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict):
            found = parsed
    return found


def epoch_ms(moment: datetime) -> int:
    return int(moment.timestamp() * 1000)


def _opencode_empty() -> dict:
    return {
        "id": "opencode",
        "name": "OpenCode",
        "source": "opencode-steps",
        "sourceLabel": "OpenCode step records",
        "ready": False,
        "status": "No OpenCode database on this machine",
        "todayTokens": 0,
        "todayLabel": "0",
        "weekTokens": 0,
        "weekLabel": "0",
        "todayCost": None,
        "weekCost": None,
        "costLabel": "",
        "todayPrompts": 0,
        "todaySessions": 0,
        "weekTurns": 0,
        "updatedAt": "",
        "limits": [],
        "models": [],
    }


def _opencode_card(today_tokens: int, week_tokens: int, today_cost: float | None, week_cost: float | None, turns: int, models: list[dict]) -> dict:
    card = _opencode_empty()
    card["ready"] = True
    card["status"] = ""
    card["todayTokens"] = today_tokens
    card["todayLabel"] = format_tokens(today_tokens)
    card["weekTokens"] = week_tokens
    card["weekLabel"] = format_tokens(week_tokens)
    card["todayCost"] = None if today_cost is None else round(today_cost, 4)
    card["weekCost"] = None if week_cost is None else round(week_cost, 4)
    if today_cost is not None or week_cost is not None:
        card["costLabel"] = f"today {format_cost(today_cost)} · 7d {format_cost(week_cost)}"
    card["weekTurns"] = turns
    card["models"] = models
    return card


def _opencode_from_steps(connection: sqlite3.Connection, now: datetime) -> dict | None:
    tables = {row[0] for row in connection.execute("select name from sqlite_master where type='table'")}
    if "part" not in tables:
        return None
    week_start = epoch_ms(now - timedelta(days=7))
    today_start = epoch_ms(now.replace(hour=0, minute=0, second=0, microsecond=0))
    join = "left join message m on m.id = p.message_id" if "message" in tables else ""
    model_sql = (
        "coalesce(json_extract(m.data, '$.model.modelID'), json_extract(m.data, '$.modelID'))"
        if "message" in tables
        else "null"
    )
    query = f"""
        select
          p.time_created,
          json_extract(p.data, '$.cost'),
          json_extract(p.data, '$.tokens.total'),
          json_extract(p.data, '$.tokens.input'),
          json_extract(p.data, '$.tokens.output'),
          json_extract(p.data, '$.tokens.reasoning'),
          json_extract(p.data, '$.tokens.cache.read'),
          json_extract(p.data, '$.tokens.cache.write'),
          {model_sql}
        from part p
        {join}
        where p.time_created >= ?
          and json_extract(p.data, '$.type') = 'step-finish'
    """
    rows = connection.execute(query, (week_start,)).fetchall()
    today_tokens = 0
    week_tokens = 0
    today_cost = 0.0
    week_cost = 0.0
    models: dict[str, int] = defaultdict(int)
    for created, cost, total, inp, out, reasoning, cache_read, cache_write, model in rows:
        tokens = int(as_float(total) or (as_float(inp) + as_float(out) + as_float(reasoning) + as_float(cache_read) + as_float(cache_write)))
        price = as_float(cost)
        week_tokens += tokens
        week_cost += price
        if int(created or 0) >= today_start:
            today_tokens += tokens
            today_cost += price
        name = clean_model(model)
        if name:
            models[name] += tokens
    top = sorted(models.items(), key=lambda item: item[1], reverse=True)[:3]
    return _opencode_card(
        today_tokens,
        week_tokens,
        today_cost,
        week_cost,
        len(rows),
        [{"id": name, "tokens": tokens, "label": format_tokens(tokens)} for name, tokens in top],
    )


def _opencode_from_sessions(connection: sqlite3.Connection, now: datetime) -> dict:
    week_start = epoch_ms(now - timedelta(days=7))
    today_start = epoch_ms(now.replace(hour=0, minute=0, second=0, microsecond=0))
    query = """
        select
          coalesce(sum(tokens_input), 0),
          coalesce(sum(tokens_output), 0),
          coalesce(sum(tokens_reasoning), 0),
          coalesce(sum(tokens_cache_read), 0),
          coalesce(sum(tokens_cache_write), 0),
          count(*)
        from session
        where time_updated >= ?
    """
    week = connection.execute(query, (week_start,)).fetchone()
    today = connection.execute(query, (today_start,)).fetchone()

    def total(row: tuple) -> int:
        return sum(int(part or 0) for part in row[:5])

    return _opencode_card(total(today), total(week), None, None, int(week[5] or 0), [])


def opencode_agent(home: Path, now: datetime) -> dict:
    db_path = home / ".local" / "share" / "opencode" / "opencode.db"
    empty = _opencode_empty()
    if not db_path.is_file():
        return empty
    try:
        connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        try:
            from_steps = _opencode_from_steps(connection, now)
            if from_steps is not None:
                return from_steps
            return _opencode_from_sessions(connection, now)
        finally:
            connection.close()
    except sqlite3.Error:
        empty["status"] = "OpenCode database could not be read"
        return empty


def bar_summary(agents: list[dict]) -> dict:
    hottest: tuple[float, str] | None = None
    alarm = False
    today = 0
    lines = []
    for agent in agents:
        today += int_or_zero(agent.get("todayTokens"))
        limit_bits = []
        for limit in agent.get("limits") or []:
            used = limit.get("usedPct")
            if not isinstance(used, (int, float)):
                continue
            if used >= 80:
                alarm = True
            limit_bits.append(f"{limit.get('label') or 'limit'} {used:g}%")
            if hottest is None or used > hottest[0]:
                hottest = (float(used), str(agent.get("id") or ""))
        line = f"{agent.get('name')}: today {agent.get('todayLabel')}"
        if agent.get("weekTokens") is not None:
            line += f" · 7d {agent.get('weekLabel')}"
        elif agent.get("weekLabel") not in (None, "—"):
            line += f" · 7d {agent.get('weekLabel')}"
        if limit_bits:
            line += " · " + ", ".join(limit_bits)
        if agent.get("status"):
            line += " · " + str(agent["status"])
        lines.append(line)
    if hottest is not None:
        name = FACE.get(hottest[1], str(hottest[1] or "AI"))
        label = f"{name} {round(hottest[0])}%"
    else:
        label = "today " + format_tokens(today)
    return {"label": label, "alarm": alarm, "todayTokens": today, "lines": lines}


PILLARS = (
    {
        "id": "rules",
        "name": "Rules",
        "blurb": "One AGENTS.md. Claude, Grok, and OpenCode load the same file through symlinks.",
        "points": [
            "create_project",
            "continue_project",
            "checkpoint_project",
            "writepaper_project",
            "global_brain_update",
        ],
    },
    {
        "id": "install",
        "name": "Install",
        "blurb": "setup.sh wires the machine. verify.sh checks it. sync.sh signs the commit and pushes.",
        "points": ["setup.sh", "verify.sh", "sync.sh"],
    },
    {
        "id": "permissions",
        "name": "Permissions",
        "blurb": "permissions.json is the only policy. setup.sh fans it out to the three tools.",
        "points": ["allow", "ask", "deny", "bash_without_prompt"],
    },
    {
        "id": "hooks",
        "name": "Hooks",
        "blurb": "GPG unlock without a pinentry window, cron guards, staleness watch, boot dashboard.",
        "points": ["gpg-git.sh", "check-links.sh", "watch-stale.sh", "boot-dashboard"],
    },
    {
        "id": "scaffolds",
        "name": "Scaffolds",
        "blurb": "project-template starts a project. paper-template starts a LaTeX paper with a Lean mirror.",
        "points": ["project-template", "paper-template", "digit-refuse"],
    },
    {
        "id": "usage",
        "name": "Usage",
        "blurb": "This machine's AI spend. The timer reads local files. It does not call a provider.",
        "points": ["Claude", "Grok", "OpenCode", "Codex", "Fireworks"],
    },
)

ABOUT = (
    "1config is the global brain on this machine.",
    "Claude Code, Grok, and OpenCode load one rules file.",
    "setup.sh installs it. verify.sh checks it. sync.sh signs a commit and pushes it.",
    "Projects, papers, permissions, and this bar all come from that same checkout.",
    "Usage is one part of the map, not the whole plugin.",
)

LINK_RELS = (
    Path(".claude/CLAUDE.md"),
    Path(".grok/AGENTS.md"),
    Path(".config/opencode/AGENTS.md"),
)


def _token(value: str, limit: int) -> str:
    line = value.strip().splitlines()[:1]
    text = line[0] if line else ""
    if "@" in text or any(ord(ch) < 32 for ch in text):
        return ""
    return "".join(ch for ch in text if ch.isalnum() or ch in "-_./")[:limit]


def _git(root: Path, args: list[str]) -> str:
    try:
        proc = subprocess.run(
            ["git", "-C", str(root), *args],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    if proc.returncode != 0:
        return ""
    return proc.stdout.strip()


def brain_status(home: Path) -> dict:
    root = home / ".agents"
    present = (root / "setup.sh").is_file() and (root / "AGENTS.md").is_file()
    commit = ""
    branch = ""
    dirty = False
    links = 0
    slip = "unknown"
    if present:
        commit = _token(_git(root, ["rev-parse", "--short", "HEAD"]), 12)
        branch = _token(_git(root, ["rev-parse", "--abbrev-ref", "HEAD"]), 40)
        dirty = bool(_git(root, ["status", "--porcelain", "--untracked-files=no"]))
        target = (root / "AGENTS.md").resolve()
        for rel in LINK_RELS:
            path = home / rel
            try:
                if path.is_symlink() and path.resolve() == target:
                    links += 1
            except OSError:
                continue
        slip_path = root / "boot-dashboard" / "close-slip.txt"
        try:
            if slip_path.is_file():
                first = slip_path.read_text(encoding="utf-8", errors="replace").splitlines()[:1]
                slip = "clean" if first and first[0].strip() == "CLEAN" else "warn"
        except OSError:
            slip = "unknown"
    tools = [{"id": name, "present": shutil.which(name) is not None} for name in ("claude", "grok", "opencode")]
    return {
        "name": "1config",
        "oneLine": "One rules file for Claude, Grok, and OpenCode. This checkout is the global brain.",
        "remoteLabel": "FirstIntegral/1config",
        "about": list(ABOUT),
        "present": present,
        "commit": commit,
        "branch": branch,
        "dirty": dirty,
        "links": links,
        "linksExpected": 3,
        "tools": tools,
        "slip": slip,
        "pillars": [dict(item) for item in PILLARS],
    }


def collect(home: Path, now: datetime | None = None) -> dict:
    now = now or datetime.now().astimezone()
    by_id: dict[str, dict] = {}
    usage_dir = home / ".local" / "state" / "omarchy" / "agents" / "usage"
    if usage_dir.is_dir():
        for path in sorted(usage_dir.glob("*.json")):
            agent = omarchy_agent(path)
            if agent is not None:
                by_id[agent["id"]] = agent
    if "claude" not in by_id:
        by_id["claude"] = {
            "id": "claude",
            "name": "Claude",
            "source": "omarchy",
            "sourceLabel": "Omarchy usage record",
            "ready": False,
            "status": "No Claude usage record yet",
            "todayTokens": 0,
            "todayLabel": "0",
            "weekTokens": None,
            "weekLabel": "—",
            "todayPrompts": 0,
            "todaySessions": 0,
            "updatedAt": "",
            "limits": [],
            "models": [],
        }
    by_id["grok"] = grok_agent(home, now)
    by_id["opencode"] = opencode_agent(home, now)
    ordered = [by_id[key] for key in CORE_IDS]
    extras = [by_id[key] for key in sorted(by_id) if key not in CORE_IDS]
    agents = ordered + extras
    summary = bar_summary(agents)
    return {
        "schemaVersion": 1,
        "generatedAt": now.isoformat(timespec="seconds"),
        "hostname": _hostname(),
        "bar": {"label": summary["label"], "alarm": summary["alarm"], "todayTokens": summary["todayTokens"]},
        "tooltip": summary["lines"],
        "agents": agents,
        "brain": brain_status(home),
        "note": "Open the panel for what 1config is. The timer reads this machine only. u asks Omarchy to refresh provider limits.",
    }


def _hostname() -> str:
    import socket
    name = socket.gethostname().split(".")[0]
    return "".join(ch for ch in name if ch.isalnum() or ch in "-_")[:40] or "machine"


def self_test() -> None:
    now = datetime(2026, 10, 9, 15, 0, tzinfo=timezone.utc)
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp)
        usage = home / ".local" / "state" / "omarchy" / "agents" / "usage"
        usage.mkdir(parents=True)
        (usage / "claude.json").write_text(
            json.dumps(
                {
                    "id": "claude",
                    "name": "Claude Code",
                    "ready": True,
                    "todayTotalTokens": 100,
                    "todayPrompts": 2,
                    "todaySessions": 1,
                    "usageStatusText": "",
                    "updatedAt": "2026-10-09T14:00:00Z",
                    "limits": [{"label": "Weekly (7-day)", "percent": 0.5, "resetsAt": "2026-10-16T00:00:00Z"}],
                    "recentDays": [{"date": "2026-10-09", "messageCount": 4}],
                }
            ),
            encoding="utf-8",
        )
        session = home / ".grok" / "sessions" / "demo"
        session.mkdir(parents=True)
        (session / "usage.json").write_text(
            json.dumps(
                {
                    "turns": [
                        {
                            "endedAt": "2026-10-09T14:30:00Z",
                            "totalTokens": 7,
                            "primaryModelId": "grok-test",
                        },
                        {
                            "endedAt": "2026-10-01T14:30:00Z",
                            "totalTokens": 99,
                            "primaryModelId": "old",
                        },
                    ]
                }
            ),
            encoding="utf-8",
        )
        log_dir = home / ".grok" / "logs"
        log_dir.mkdir(parents=True)
        (log_dir / "unified.jsonl").write_text(
            json.dumps(
                {
                    "ts": "2026-10-09T14:00:00Z",
                    "msg": "billing: fetched credits config",
                    "ctx": {
                        "config": {
                            "creditUsagePercent": 25,
                            "currentPeriod": {"end": "2026-10-16T00:00:00Z"},
                        }
                    },
                }
            )
            + "\n",
            encoding="utf-8",
        )
        db_dir = home / ".local" / "share" / "opencode"
        db_dir.mkdir(parents=True)
        connection = sqlite3.connect(db_dir / "opencode.db")
        connection.execute(
            """
            create table session (
              tokens_input integer,
              tokens_output integer,
              tokens_reasoning integer,
              tokens_cache_read integer,
              tokens_cache_write integer,
              time_updated integer
            )
            """
        )
        connection.execute(
            "insert into session values (10, 4, 0, 1, 0, ?)",
            (epoch_ms(now - timedelta(hours=1)),),
        )
        connection.execute("create table message (id text, data text)")
        connection.execute("create table part (time_created integer, message_id text, data text)")
        connection.execute(
            "insert into message values ('m1', ?)",
            (json.dumps({"model": {"modelID": "demo", "providerID": "opencode"}}),),
        )
        step = {
            "type": "step-finish",
            "cost": 1.25,
            "tokens": {"total": 21, "input": 10, "output": 5, "reasoning": 1, "cache": {"read": 4, "write": 1}},
        }
        old = {"type": "step-finish", "cost": 9, "tokens": {"total": 99}}
        connection.execute(
            "insert into part values (?, 'm1', ?)",
            (epoch_ms(now - timedelta(hours=1)), json.dumps(step)),
        )
        connection.execute(
            "insert into part values (?, 'm1', ?)",
            (epoch_ms(now - timedelta(days=8)), json.dumps(old)),
        )
        connection.commit()
        connection.close()
        payload = collect(home, now)
    claude = payload["agents"][0]
    grok = payload["agents"][1]
    opencode = payload["agents"][2]
    assert claude["todayTokens"] == 100, claude
    assert claude["limits"][0]["usedPct"] == 50.0, claude
    assert grok["todayTokens"] == 7, grok
    assert grok["weekTokens"] == 7, grok
    assert grok["limits"][0]["usedPct"] == 25, grok
    assert opencode["todayTokens"] == 21, opencode
    assert opencode["weekTokens"] == 21, opencode
    assert opencode["weekCost"] == 1.25, opencode
    assert opencode["models"][0]["id"] == "demo", opencode
    assert payload["bar"]["label"] == "Claude 50%", payload["bar"]
    brain = payload["brain"]
    assert brain["present"] is False, brain
    assert brain["links"] == 0, brain
    assert [item["id"] for item in brain["pillars"]] == [
        "rules",
        "install",
        "permissions",
        "hooks",
        "scaffolds",
        "usage",
    ], brain
    assert "global brain" in brain["about"][0], brain
    blob = json.dumps(payload)
    for banned in ("/tmp", "Bearer", "sk-", "usage.json", "@"):
        assert banned not in blob, banned
    print("self-test ok")


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        self_test()
        return 0
    json.dump(collect(Path.home()), sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except Exception as exc:  # one line, no traceback into the bar journal
        print(f"usage.py: {type(exc).__name__}", file=sys.stderr)
        raise SystemExit(1) from None
