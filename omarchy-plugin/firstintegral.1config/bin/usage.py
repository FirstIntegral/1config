#!/usr/bin/env python3
"""Local AI-usage snapshot for the 1config Omarchy plugin.

Reads ledgers already on this machine. Does not call a provider, and does not
emit paths, prompts, credentials, or message text.

  usage.py            one JSON object on stdout
  usage.py --self-test
"""

from __future__ import annotations

import json
import sqlite3
import sys
import tempfile
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path


SHORT = {
    "claude": "C",
    "grok": "G",
    "opencode": "O",
    "codex": "X",
    "fireworks": "F",
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


def opencode_agent(home: Path, now: datetime) -> dict:
    db_path = home / ".local" / "share" / "opencode" / "opencode.db"
    empty = {
        "id": "opencode",
        "name": "OpenCode",
        "source": "opencode-db",
        "sourceLabel": "OpenCode local database",
        "ready": False,
        "status": "No OpenCode database on this machine",
        "todayTokens": 0,
        "todayLabel": "0",
        "weekTokens": 0,
        "weekLabel": "0",
        "todayPrompts": 0,
        "todaySessions": 0,
        "weekTurns": 0,
        "updatedAt": "",
        "limits": [],
        "models": [],
    }
    if not db_path.is_file():
        return empty
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
    try:
        connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        try:
            week = connection.execute(query, (week_start,)).fetchone()
            today = connection.execute(query, (today_start,)).fetchone()
        finally:
            connection.close()
    except sqlite3.Error:
        empty["status"] = "OpenCode database could not be read"
        return empty
    def total(row: tuple) -> int:
        return sum(int(part or 0) for part in row[:5])
    week_tokens = total(week)
    today_tokens = total(today)
    return {
        "id": "opencode",
        "name": "OpenCode",
        "source": "opencode-db",
        "sourceLabel": "OpenCode local database",
        "ready": True,
        "status": "",
        "todayTokens": today_tokens,
        "todayLabel": format_tokens(today_tokens),
        "weekTokens": week_tokens,
        "weekLabel": format_tokens(week_tokens),
        "todayPrompts": 0,
        "todaySessions": int(today[5] or 0),
        "weekTurns": int(week[5] or 0),
        "updatedAt": "",
        "limits": [],
        "models": [],
    }


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
        short = SHORT.get(hottest[1], hottest[1][:1].upper() or "?")
        label = f"{short} {round(hottest[0])}%"
    else:
        label = format_tokens(today)
    return {"label": label, "alarm": alarm, "todayTokens": today, "lines": lines}


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
        "note": "Timer reads this machine only. u asks Omarchy to refresh provider limits.",
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
    assert opencode["todayTokens"] == 15, opencode
    assert payload["bar"]["label"] == "C 50%", payload["bar"]
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
