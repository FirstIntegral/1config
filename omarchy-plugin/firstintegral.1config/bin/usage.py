#!/usr/bin/env python3
"""Local AI-usage snapshot for the 1config Omarchy plugin.

Reads ledgers already on this machine. Also reads the OpenCode Go plan from
https://opencode.ai/zen/go/v1/usage with the key already in auth.json. That
call is cached for ten minutes. The key never leaves the request header.
Does not emit paths, prompts, credentials, or message text.

  usage.py                 one JSON object on stdout
  usage.py --refresh-go    ignore the Go cache and read the plan again
  usage.py --self-test
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path


# Fixed roster. Anything else in the Omarchy usage directory is ignored.
# Order is the display order. Used tools are pulled in front of this list.
ROSTER = (
    ("claude", "Claude", ("claude",), (".claude",)),
    ("grok", "Grok", ("grok",), (".grok",)),
    ("openai", "OpenAI", ("openai",), (".openai", ".config/openai")),
    ("opencode", "OpenCode", ("opencode",), (".local/share/opencode", ".config/opencode")),
    ("codex", "Codex", ("codex",), (".codex",)),
    ("cursor", "Cursor", ("cursor", "cursor-agent"), (".cursor", ".config/Cursor", ".config/cursor")),
)
ROSTER_IDS = {item[0] for item in ROSTER}
FACE = {item[0]: item[1] for item in ROSTER}
WEEKDAYS = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
GO_USAGE_URL = "https://opencode.ai/zen/go/v1/usage"
GO_TTL = timedelta(minutes=10)
GO_WINDOWS = (("rolling", "Rolling"), ("weekly", "Weekly"), ("monthly", "Monthly"))


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


def _bucket_tokens(bucket: object) -> int:
    if isinstance(bucket, bool) or bucket is None:
        return 0
    if isinstance(bucket, (int, float)):
        return int(bucket)
    if not isinstance(bucket, dict):
        return 0
    if "total" in bucket:
        return int_or_zero(bucket.get("total"))
    return (
        int_or_zero(bucket.get("inputTokens"))
        + int_or_zero(bucket.get("outputTokens"))
        + int_or_zero(bucket.get("cacheReadInputTokens"))
        + int_or_zero(bucket.get("cacheCreationInputTokens"))
    )


def _models_from_records(data: dict) -> list[dict]:
    totals: dict[str, int] = {}
    usage = data.get("modelUsage")
    if isinstance(usage, dict):
        for raw_id, bucket in usage.items():
            name = clean_model(raw_id)
            if not name:
                continue
            totals[name] = totals.get(name, 0) + _bucket_tokens(bucket)
    today = data.get("todayTokensByModel")
    if isinstance(today, dict):
        for raw_id, bucket in today.items():
            name = clean_model(raw_id)
            if not name or name in totals:
                continue
            totals[name] = _bucket_tokens(bucket)
    ranked = sorted(totals.items(), key=lambda item: item[1], reverse=True)
    return [
        {"id": name, "tokens": tokens, "label": format_tokens(tokens)}
        for name, tokens in ranked[:6]
        if tokens > 0
    ]


def _home_has_dir(home: Path, rels: tuple[str, ...]) -> bool:
    for rel in rels:
        path = home.joinpath(*Path(rel).parts)
        try:
            if path.is_dir():
                return True
        except OSError:
            continue
    return False


def _has_bin(which, names: tuple[str, ...]) -> bool:
    for name in names:
        try:
            found = which(name)
        except OSError:
            continue
        if found:
            return True
    return False


def agent_used(agent: dict) -> bool:
    if int_or_zero(agent.get("todayTokens")) > 0:
        return True
    if int_or_zero(agent.get("weekTokens")) > 0:
        return True
    if int_or_zero(agent.get("weekTurns")) > 0:
        return True
    if agent.get("limits"):
        return True
    if agent.get("models"):
        return True
    for day in agent.get("days") or []:
        if isinstance(day, dict) and int_or_zero(day.get("tokens")) > 0:
            return True
    return False


def _blank_agent(agent_id: str, name: str) -> dict:
    return {
        "id": agent_id,
        "name": name,
        "source": "none",
        "sourceLabel": "",
        "ready": False,
        "present": False,
        "used": False,
        "status": "",
        "todayTokens": 0,
        "todayLabel": "0",
        "weekTokens": None,
        "weekLabel": "—",
        "todayPrompts": 0,
        "todaySessions": 0,
        "updatedAt": "",
        "limits": [],
        "models": [],
        "days": [],
    }


def _mark_agent(agent: dict, name: str, present: bool) -> dict:
    used = agent_used(agent)
    agent["used"] = used
    agent["present"] = bool(present) or used
    if not (agent.get("id") == "opencode" and agent.get("plan")):
        agent["name"] = name
    if not used and not agent.get("status"):
        if not agent["present"]:
            agent["status"] = "Not on this machine"
        elif agent.get("source") == "none":
            agent["status"] = "No usage record on this machine"
        else:
            agent["status"] = "No usage this week"
    return agent


def omarchy_agent(path: Path, now: datetime) -> dict | None:
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
        "models": _models_from_records(data),
        "days": _message_days(data.get("recentDays"), now),
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
    top = sorted(models.items(), key=lambda item: item[1], reverse=True)[:6]
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


def go_cache_path(home: Path) -> Path:
    return home / ".local" / "state" / "1config" / "opencode-go.json"


def read_go_key(home: Path) -> str:
    path = home / ".local" / "share" / "opencode" / "auth.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return ""
    entry = data.get("opencode-go") if isinstance(data, dict) else None
    key = entry.get("key") if isinstance(entry, dict) else ""
    if not isinstance(key, str):
        return ""
    key = key.strip()
    if not key or any(ch.isspace() for ch in key):
        return ""
    return key


def slim_go_usage(usage: dict) -> dict:
    slim: dict[str, dict] = {}
    for key, _label in GO_WINDOWS:
        window = usage.get(key)
        if not isinstance(window, dict):
            continue
        percent = as_percent(window.get("percent"), fraction_if_unit=False)
        if percent is None:
            continue
        slim[key] = {
            "status": "rate-limited" if window.get("status") == "rate-limited" else "ok",
            "percent": percent,
            "resetsAt": str(window.get("resetsAt") or "")[:40],
        }
    return slim


def go_windows(usage: dict) -> list[dict]:
    limits = []
    for key, label in GO_WINDOWS:
        window = slim_go_usage(usage).get(key)
        if window is None:
            continue
        used = float(window["percent"])
        if window["status"] == "rate-limited":
            used = 100.0
        detail = ""
        if key == "rolling" and used == 0:
            detail = "Starts on first use"
        limits.append(
            {
                "label": label,
                "usedPct": used,
                "resetsAt": window["resetsAt"],
                "detail": detail,
            }
        )
    return limits


def read_go_cache(home: Path) -> tuple[dict | None, datetime | None]:
    try:
        payload = json.loads(go_cache_path(home).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None, None
    if not isinstance(payload, dict) or not isinstance(payload.get("usage"), dict):
        return None, None
    return payload["usage"], parse_time(payload.get("fetchedAt"))


def write_go_cache(home: Path, now: datetime, usage: dict) -> None:
    path = go_cache_path(home)
    slim = slim_go_usage(usage)
    if not slim:
        return
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        blob = json.dumps(
            {"fetchedAt": now.isoformat(timespec="seconds"), "usage": slim},
            separators=(",", ":"),
        )
        temporary = path.with_suffix(".json.tmp")
        temporary.write_text(blob + "\n", encoding="utf-8")
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    except OSError:
        return


def fetch_go_usage(key: str) -> dict | None:
    # Cloudflare rejects the Python default client. curl's client is accepted.
    request = urllib.request.Request(
        GO_USAGE_URL,
        headers={
            "Authorization": "Bearer " + key,
            "Accept": "application/json",
            "User-Agent": "curl/8.7.1",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            payload = json.loads(response.read(16384).decode("utf-8", "replace"))
    except (OSError, urllib.error.URLError, json.JSONDecodeError, TimeoutError, ValueError):
        return None
    usage = payload.get("usage") if isinstance(payload, dict) else None
    return usage if isinstance(usage, dict) else None


def go_limits(home: Path, now: datetime, *, force: bool) -> list[dict]:
    cached, fetched_at = read_go_cache(home)
    fresh = False
    if cached is not None and fetched_at is not None:
        age = now - as_local(fetched_at, now)
        fresh = timedelta(0) <= age < GO_TTL
    if cached is not None and fresh and not force:
        return go_windows(cached)
    key = read_go_key(home)
    if key:
        fetched = fetch_go_usage(key)
        if fetched is not None:
            write_go_cache(home, now, fetched)
            return go_windows(fetched)
    if cached is not None:
        return go_windows(cached)
    return []


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
        "days": [],
        "todayCostLabel": "",
        "weekCostLabel": "",
    }


def _week_slots(now: datetime) -> list[dict]:
    start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    slots = []
    for offset in range(6, -1, -1):
        day = start - timedelta(days=offset)
        slots.append(
            {
                "date": day.strftime("%Y-%m-%d"),
                "label": "Today" if offset == 0 else WEEKDAYS[day.weekday()],
                "tokens": 0,
                "cost": 0.0,
                "today": offset == 0,
            }
        )
    return slots


def _message_days(recent: object, now: datetime) -> list[dict]:
    counts: dict[str, int] = {}
    if isinstance(recent, list):
        for day in recent:
            if not isinstance(day, dict):
                continue
            counts[str(day.get("date") or "")[:10]] = int_or_zero(day.get("messageCount"))
    if not any(counts.values()):
        return []
    slots = _week_slots(now)
    for slot in slots:
        slot["tokens"] = counts.get(slot["date"], 0)
    finished = _finish_days(slots)
    for row in finished:
        count = int(row["tokens"])
        row["tokenLabel"] = (format_tokens(count) + " msgs") if count else "0"
        row["cost"] = 0
        row["costLabel"] = ""
    return finished


def _finish_days(slots: list[dict]) -> list[dict]:
    finished = []
    for slot in slots:
        cost = float(slot["cost"])
        finished.append(
            {
                "date": slot["date"],
                "label": slot["label"],
                "tokens": int(slot["tokens"]),
                "tokenLabel": format_tokens(int(slot["tokens"])),
                "cost": round(cost, 4),
                "costLabel": format_cost(cost) if cost or slot["today"] else "",
                "today": bool(slot["today"]),
            }
        )
    return finished


def _opencode_card(
    today_tokens: int,
    week_tokens: int,
    today_cost: float | None,
    week_cost: float | None,
    turns: int,
    models: list[dict],
    days: list[dict] | None = None,
) -> dict:
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
    card["todayCostLabel"] = "" if today_cost is None else format_cost(today_cost)
    card["weekCostLabel"] = "" if week_cost is None else format_cost(week_cost)
    card["weekTurns"] = turns
    card["models"] = models
    card["days"] = days or []
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
    models: dict[str, list[float]] = defaultdict(lambda: [0.0, 0.0])
    slots = _week_slots(now)
    by_date = {slot["date"]: slot for slot in slots}
    for created, cost, total, inp, out, reasoning, cache_read, cache_write, model in rows:
        tokens = int(as_float(total) or (as_float(inp) + as_float(out) + as_float(reasoning) + as_float(cache_read) + as_float(cache_write)))
        price = as_float(cost)
        week_tokens += tokens
        week_cost += price
        created_at = datetime.fromtimestamp(int(created or 0) / 1000, tz=now.tzinfo)
        slot = by_date.get(created_at.strftime("%Y-%m-%d"))
        if slot is not None:
            slot["tokens"] += tokens
            slot["cost"] += price
        if int(created or 0) >= today_start:
            today_tokens += tokens
            today_cost += price
        name = clean_model(model)
        if name:
            models[name][0] += tokens
            models[name][1] += price
    top = sorted(models.items(), key=lambda item: item[1][0], reverse=True)[:6]
    return _opencode_card(
        today_tokens,
        week_tokens,
        today_cost,
        week_cost,
        len(rows),
        [
            {
                "id": name,
                "tokens": int(parts[0]),
                "label": format_tokens(int(parts[0])),
                "cost": round(parts[1], 4),
                "costLabel": format_cost(parts[1]) if parts[1] else "",
            }
            for name, parts in top
        ],
        _finish_days(slots),
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
        if agent.get("used") is False:
            continue
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


def _git_out(root: Path, args: list[str]) -> str | None:
    try:
        proc = subprocess.run(
            ["git", "-C", str(root), *args],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout.strip()


def _detail(value: str) -> str:
    cleaned = "".join(ch for ch in value if ch.isalnum() or ch in " /_-")
    return cleaned.strip()[:40] or "unknown"


def _vital(vital_id: str, group: str, name: str, state: str, detail: str) -> dict:
    if state not in {"ok", "warn", "fail"}:
        state = "fail"
    return {
        "id": vital_id,
        "group": group,
        "name": name,
        "state": state,
        "detail": _detail(detail),
    }


def _count_files(root: Path, rels: tuple[str, ...]) -> int:
    found = 0
    for rel in rels:
        if (root / rel).is_file():
            found += 1
    return found


def _ratio(found: int, total: int) -> tuple[str, str]:
    detail = f"{found}/{total}"
    if found == total:
        return "ok", detail
    if found == 0:
        return "fail", detail
    return "warn", detail


def _ahead_behind(raw: str | None) -> tuple[str, str]:
    if raw is None or not raw.strip():
        return "warn", "no ref"
    parts = raw.split()
    if len(parts) != 2 or not all(part.isdigit() for part in parts):
        return "warn", "no ref"
    behind, ahead = int(parts[0]), int(parts[1])
    if behind == 0 and ahead == 0:
        return "ok", "level"
    if behind and ahead:
        return "fail", "diverged"
    if ahead:
        return "warn", f"ahead {ahead}"
    return "warn", f"behind {behind}"


def _gitconfig(home: Path) -> dict[str, str]:
    text = ""
    for rel in (Path(".gitconfig"), Path(".config/git/config")):
        path = home / rel
        try:
            if path.is_file():
                text += "\n" + path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
    section = ""
    values: dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].split(";", 1)[0].strip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip().lower().split()[0]
            continue
        if "=" not in line or not section:
            continue
        key, val = line.split("=", 1)
        values[f"{section}.{key.strip().lower()}"] = val.strip().strip('"').strip("'")
    return values


def _signing_vital(home: Path) -> dict:
    values = _gitconfig(home)
    if not values:
        return _vital("signing", "machine", "Commit signing", "fail", "unset")
    signed = values.get("commit.gpgsign", "").lower() in {"true", "yes", "on", "1"}
    program = values.get("gpg.program", "").replace("\\", "/").rstrip("/")
    wrapper = program.endswith("gpg-git.sh")
    key_set = bool(values.get("user.signingkey", "").strip())
    if signed and wrapper and key_set:
        return _vital("signing", "machine", "Commit signing", "ok", "wrapper")
    if signed and wrapper:
        return _vital("signing", "machine", "Commit signing", "warn", "no key")
    if signed:
        return _vital("signing", "machine", "Commit signing", "warn", "other program")
    return _vital("signing", "machine", "Commit signing", "fail", "unsigned")


def _tree_digest(path: Path) -> str:
    digest = hashlib.sha256()
    files: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(path):
        dirnames[:] = sorted(name for name in dirnames if name != "__pycache__")
        for name in filenames:
            if name.endswith(".pyc"):
                continue
            files.append(Path(dirpath) / name)
    for file in sorted(files):
        digest.update(file.relative_to(path).as_posix().encode())
        digest.update(b"\0")
        try:
            digest.update(file.read_bytes())
        except OSError:
            digest.update(b"?")
        digest.update(b"\0")
    return digest.hexdigest()


def _plugin_vital(home: Path, root: Path) -> dict:
    plugins = home / ".config" / "omarchy" / "plugins"
    if not plugins.is_dir():
        return _vital("plugin", "machine", "Plugin copy", "ok", "no shell")
    src = root / "omarchy-plugin" / "firstintegral.1config"
    dst = plugins / "firstintegral.1config"
    if not src.is_dir() or not dst.is_dir():
        return _vital("plugin", "machine", "Plugin copy", "fail", "missing")
    try:
        same = _tree_digest(src) == _tree_digest(dst)
    except OSError:
        return _vital("plugin", "machine", "Plugin copy", "warn", "unread")
    if same:
        return _vital("plugin", "machine", "Plugin copy", "ok", "matches")
    return _vital("plugin", "machine", "Plugin copy", "warn", "drifted")


def _guard_vital(home: Path, root: Path, vital_id: str, name: str, script: str, flag: str, pending: str | None) -> dict:
    if not (home / script).is_file():
        return _vital(vital_id, "guards", name, "fail", "not installed")
    hot = (home / flag).exists()
    if pending and (root / pending).exists():
        hot = True
    if hot:
        return _vital(vital_id, "guards", name, "warn", "residue")
    return _vital(vital_id, "guards", name, "ok", "clear")


def _boot_vital(home: Path, root: Path) -> dict:
    src = root / "boot-dashboard" / "agents-boot-status.desktop"
    launch = root / "boot-dashboard" / "launch.sh"
    dst = home / ".config" / "autostart" / "agents-boot-status.desktop"
    if not src.is_file() or not launch.is_file():
        return _vital("boot", "guards", "Boot dashboard", "fail", "missing")
    if not dst.is_file():
        return _vital("boot", "guards", "Boot dashboard", "fail", "not installed")
    expected = "Exec=" + launch.as_posix()
    try:
        lines = dst.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return _vital("boot", "guards", "Boot dashboard", "warn", "unread")
    if any(line.strip() == expected for line in lines):
        return _vital("boot", "guards", "Boot dashboard", "ok", "installed")
    return _vital("boot", "guards", "Boot dashboard", "warn", "drifted")


def _permissions_vital(root: Path) -> dict:
    path = root / "permissions.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeError):
        return _vital("permissions", "rules", "Permissions", "fail", "broken")
    defaults = data.get("defaults")
    bucket = data.get("permissions")
    if not isinstance(defaults, dict) or not isinstance(bucket, dict):
        return _vital("permissions", "rules", "Permissions", "fail", "broken")
    if not isinstance(bucket.get("allow"), list) or not isinstance(bucket.get("deny"), list):
        return _vital("permissions", "rules", "Permissions", "fail", "broken")
    flag = defaults.get("bash_without_prompt")
    if not isinstance(flag, bool):
        return _vital("permissions", "rules", "Permissions", "fail", "broken")
    local = root / "local.json"
    if local.is_file():
        try:
            extra = json.loads(local.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError, UnicodeError):
            return _vital("permissions", "rules", "Permissions", "warn", "local broken")
        if isinstance(extra, dict) and isinstance(extra.get("bash_without_prompt"), bool):
            flag = extra["bash_without_prompt"]
    return _vital("permissions", "rules", "Permissions", "ok", "autonomy on" if flag else "autonomy off")


def _slip_state(root: Path) -> tuple[str, str]:
    slip_path = root / "boot-dashboard" / "close-slip.txt"
    try:
        if not slip_path.is_file():
            return "warn", "no exit"
        first = slip_path.read_text(encoding="utf-8", errors="replace").splitlines()[:1]
    except OSError:
        return "warn", "no exit"
    if first and first[0].strip() == "CLEAN":
        return "ok", "clean"
    return "warn", "warn"


CHECKOUT_FILES = ("setup.sh", "verify.sh", "sync.sh", "AGENTS.md")
HOOK_FILES = (
    "hooks/gpg-git.sh",
    "hooks/gpg-agent-unlock.sh",
    "hooks/check-links.sh",
    "hooks/check-claude-memory.sh",
    "hooks/watch-stale.sh",
    "hooks/checkpoint.sh",
    "hooks/brain-sync.sh",
    "hooks/digit-refuse.sh",
    "hooks/merge-strays.sh",
)
SCAFFOLD_FILES = (
    "project-template/AGENTS.md",
    "paper-template/main.tex",
    "paper-template/build.sh",
    "paper-template/lean/lakefile.toml",
)
VITAL_IDS = (
    "checkout",
    "tree",
    "remote",
    "level",
    "links",
    "permissions",
    "hooks",
    "scaffolds",
    "slip",
    "memory",
    "symlinks",
    "boot",
    "tools",
    "tex",
    "lean",
    "signing",
    "plugin",
)


def _verdict(vitals: list[dict]) -> str:
    states = {item["state"] for item in vitals}
    if "fail" in states:
        return "fault"
    if "warn" in states:
        return "warn"
    return "clear"


def brain_status(home: Path, which=None, git=None) -> dict:
    finder = shutil.which if which is None else which
    runner = _git_out if git is None else git
    root = home / ".agents"
    present = (root / "setup.sh").is_file() and (root / "AGENTS.md").is_file()
    commit = ""
    branch = ""
    dirty = False
    links = 0
    slip, _slip_detail = _slip_state(root)
    head = runner(root, ["rev-parse", "--short", "HEAD"])
    if head:
        commit = _token(head, 12)
    ref = runner(root, ["rev-parse", "--abbrev-ref", "HEAD"])
    if ref:
        branch = _token(ref, 40)
    status = runner(root, ["status", "--porcelain", "--untracked-files=no"])
    if status:
        dirty = True
    if present:
        target = (root / "AGENTS.md").resolve()
        for rel in LINK_RELS:
            path = home / rel
            try:
                if path.is_symlink() and path.resolve() == target:
                    links += 1
            except OSError:
                continue

    checkout_state, checkout_detail = _ratio(_count_files(root, CHECKOUT_FILES), len(CHECKOUT_FILES))
    if status is None:
        tree_state, tree_detail = "fail", "no repo"
    elif status:
        tree_state, tree_detail = "warn", "dirty"
    else:
        tree_state, tree_detail = "ok", "clean"

    allow_path = root / "BRAIN_REMOTE"
    origin = runner(root, ["remote", "get-url", "origin"])
    try:
        allowed = {
            line.strip()
            for line in allow_path.read_text(encoding="utf-8", errors="replace").splitlines()
            if line.strip() and not line.strip().startswith("#")
        } if allow_path.is_file() else set()
    except OSError:
        allowed = set()
    if not allowed:
        remote_state, remote_detail = "fail", "no list"
    elif not origin:
        remote_state, remote_detail = "fail", "none"
    elif origin in allowed:
        remote_state, remote_detail = "ok", "listed"
    else:
        remote_state, remote_detail = "fail", "other"
    level_state, level_detail = _ahead_behind(
        runner(root, ["rev-list", "--left-right", "--count", "origin/main...HEAD"])
    )

    if links == 3:
        link_state, link_detail = "ok", "3/3"
    elif links == 0:
        link_state, link_detail = "fail", "0/3"
    else:
        link_state, link_detail = "warn", f"{links}/3"

    hook_state, hook_detail = _ratio(_count_files(root, HOOK_FILES), len(HOOK_FILES))
    scaffold_state, scaffold_detail = _ratio(_count_files(root, SCAFFOLD_FILES), len(SCAFFOLD_FILES))
    tool_hits = sum(1 for name in ("claude", "grok", "opencode") if finder(name))
    if tool_hits == 3:
        tool_state, tool_detail = "ok", "3/3"
    elif tool_hits == 0:
        tool_state, tool_detail = "fail", "0/3"
    else:
        tool_state, tool_detail = "warn", f"{tool_hits}/3"
    tex_state, tex_detail = ("ok", "ready") if finder("latexmk") or finder("pdflatex") else ("fail", "missing")
    lean_ready = bool(finder("lean")) or (home / ".elan" / "bin" / "lean").is_file()
    lean_state, lean_detail = ("ok", "ready") if lean_ready else ("fail", "missing")
    tools = [{"id": name, "present": finder(name) is not None} for name in ("claude", "grok", "opencode")]

    vitals = [
        _vital("checkout", "checkout", "Checkout", checkout_state, checkout_detail),
        _vital("tree", "checkout", "Work tree", tree_state, tree_detail),
        _vital("remote", "checkout", "Remote", remote_state, remote_detail),
        _vital("level", "checkout", "Matches origin", level_state, level_detail),
        _vital("links", "rules", "Rules links", link_state, link_detail),
        _permissions_vital(root),
        _vital("hooks", "rules", "Hooks", hook_state, hook_detail),
        _vital("scaffolds", "rules", "Scaffolds", scaffold_state, scaffold_detail),
        _vital("slip", "guards", "Boot slip", slip if slip != "unknown" else "warn", _slip_detail),
        _guard_vital(
            home,
            root,
            "memory",
            "Memory guard",
            "cron-jobs/claude-memory-guard/check-memory.sh",
            "cron-jobs/claude-memory-guard/NEEDS-MEMORY-MERGE",
            "backups/claude-residue/PENDING.md",
        ),
        _guard_vital(
            home,
            root,
            "symlinks",
            "Symlink guard",
            "cron-jobs/agents-symlink-guard/check-links.sh",
            "cron-jobs/agents-symlink-guard/NEEDS-SYMLINK-MERGE",
            None,
        ),
        _boot_vital(home, root),
        _vital("tools", "machine", "Three tools", tool_state, tool_detail),
        _vital("tex", "machine", "TeX", tex_state, tex_detail),
        _vital("lean", "machine", "Lean", lean_state, lean_detail),
        _signing_vital(home),
        _plugin_vital(home, root),
    ]
    verdict = _verdict(vitals)
    groups = []
    for group_id, group_name in (
        ("checkout", "Checkout"),
        ("rules", "Rules"),
        ("guards", "Guards"),
        ("machine", "Machine"),
    ):
        groups.append(
            {
                "id": group_id,
                "name": group_name,
                "items": [item for item in vitals if item["group"] == group_id],
            }
        )
    return {
        "name": "1config",
        "oneLine": "One rules file for Claude, Grok, and OpenCode. This checkout is the global brain.",
        "remoteLabel": "FirstIntegral/1config",
        "present": present,
        "commit": commit,
        "branch": branch,
        "dirty": dirty,
        "links": links,
        "linksExpected": 3,
        "tools": tools,
        "slip": "clean" if slip == "ok" else slip,
        "verdict": verdict,
        "vitals": vitals,
        "groups": groups,
    }


def attach_go(card: dict, home: Path, now: datetime, *, force: bool) -> dict:
    limits = go_limits(home, now, force=force)
    if not limits:
        return card
    card["limits"] = limits
    card["name"] = "OpenCode Go"
    card["plan"] = "Go"
    monthly = next((item for item in limits if item["label"] == "Monthly"), None)
    if monthly is not None:
        card["headline"] = f"{monthly['usedPct']:g}%"
    return card


def collect(home: Path, now: datetime | None = None, *, force_go: bool = False, which=None) -> dict:
    now = now or datetime.now().astimezone()
    finder = shutil.which if which is None else which
    by_id: dict[str, dict] = {}
    loaded: set[str] = set()
    usage_dir = home / ".local" / "state" / "omarchy" / "agents" / "usage"
    if usage_dir.is_dir():
        for path in sorted(usage_dir.glob("*.json")):
            agent = omarchy_agent(path, now)
            if agent is None or agent["id"] not in ROSTER_IDS:
                continue
            by_id[agent["id"]] = agent
            loaded.add(agent["id"])
    by_id["grok"] = grok_agent(home, now)
    by_id["opencode"] = attach_go(opencode_agent(home, now), home, now, force=force_go)
    roster: list[dict] = []
    for agent_id, name, bins, rels in ROSTER:
        agent = by_id.get(agent_id) or _blank_agent(agent_id, name)
        present = agent_id in loaded or _home_has_dir(home, rels) or _has_bin(finder, bins)
        roster.append(_mark_agent(agent, name, present))
    agents = [item for item in roster if item["used"]] + [item for item in roster if not item["used"]]
    summary = bar_summary(agents)
    brain = brain_status(home, which=finder)
    lines = list(summary["lines"])
    lines.insert(0, "brain " + str(brain["verdict"]))
    return {
        "schemaVersion": 1,
        "generatedAt": now.isoformat(timespec="seconds"),
        "hostname": _hostname(),
        "bar": {"label": summary["label"], "alarm": summary["alarm"], "todayTokens": summary["todayTokens"]},
        "tooltip": lines,
        "agents": agents,
        "brain": brain,
        "note": "Each tool is its own box. Tools with no usage stay hidden until you ask. By model starts off. m shows the model boxes. OpenCode Go is rolling, weekly, and monthly. s is spend. u refreshes Claude and Codex, and reads Go again.",
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
                    "modelUsage": {
                        "claude-opus": {
                            "inputTokens": 60,
                            "outputTokens": 40,
                            "cacheReadInputTokens": 0,
                            "cacheCreationInputTokens": 0,
                        }
                    },
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
        cache_dir = home / ".local" / "state" / "1config"
        cache_dir.mkdir(parents=True)
        (usage / "fireworks.json").write_text(
            json.dumps(
                {
                    "id": "fireworks",
                    "name": "Skip",
                    "ready": True,
                    "todayTotalTokens": 500,
                    "limits": [{"label": "Monthly", "percent": 0.9, "resetsAt": "2026-10-16T00:00:00Z"}],
                }
            ),
            encoding="utf-8",
        )
        (cache_dir / "opencode-go.json").write_text(
            json.dumps(
                {
                    "fetchedAt": now.isoformat(),
                    "usage": {
                        "rolling": {"status": "ok", "percent": 0, "resetsAt": "2026-10-09T20:00:00Z"},
                        "weekly": {"status": "ok", "percent": 1, "resetsAt": "2026-10-12T00:00:00Z"},
                        "monthly": {"status": "ok", "percent": 40, "resetsAt": "2026-10-24T14:13:49Z"},
                    },
                }
            ),
            encoding="utf-8",
        )
        payload = collect(home, now, which=lambda _name: None)
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
    assert opencode["models"][0]["cost"] == 1.25, opencode
    assert opencode["weekCostLabel"] == "$1.25", opencode
    assert len(opencode["days"]) == 7, opencode["days"]
    assert opencode["days"][-1]["today"] is True, opencode["days"]
    assert opencode["days"][-1]["label"] == "Today", opencode["days"]
    assert opencode["days"][-1]["tokens"] == 21, opencode["days"]
    assert opencode["days"][-1]["cost"] == 1.25, opencode["days"]
    assert opencode["days"][0]["date"] == "2026-10-03", opencode["days"]
    assert sum(day["tokens"] for day in opencode["days"]) == 21
    assert opencode["name"] == "OpenCode Go", opencode["name"]
    assert opencode["headline"] == "40%", opencode
    assert [item["label"] for item in opencode["limits"]] == ["Rolling", "Weekly", "Monthly"]
    assert opencode["limits"][0]["detail"] == "Starts on first use", opencode["limits"]
    assert opencode["limits"][1]["usedPct"] == 1, opencode["limits"]
    assert opencode["limits"][2]["usedPct"] == 40, opencode["limits"]
    blocked = go_windows({"rolling": {"status": "rate-limited", "percent": 99, "resetsAt": ""}})
    assert blocked[0]["usedPct"] == 100 and blocked[0]["detail"] == "", blocked
    assert payload["bar"]["label"] == "Claude 50%", payload["bar"]
    assert [item["id"] for item in payload["agents"]] == [
        "claude",
        "grok",
        "opencode",
        "openai",
        "codex",
        "cursor",
    ], [item["id"] for item in payload["agents"]]
    assert claude["models"][0]["id"] == "claude-opus", claude["models"]
    assert claude["models"][0]["tokens"] == 100, claude["models"]
    assert claude["days"][-1]["tokenLabel"] == "4 msgs", claude["days"]
    assert payload["agents"][3]["used"] is False, payload["agents"][3]
    assert payload["agents"][3]["present"] is False, payload["agents"][3]
    assert payload["agents"][3]["status"] == "Not on this machine", payload["agents"][3]
    assert payload["agents"][4]["used"] is False and payload["agents"][4]["status"] == "Not on this machine"
    assert payload["agents"][5]["used"] is False and payload["agents"][5]["status"] == "Not on this machine"
    cursor_only = _mark_agent(_blank_agent("cursor", "Cursor"), "Cursor", True)
    assert cursor_only["status"] == "No usage record on this machine", cursor_only
    assert "fireworks" not in [item["id"] for item in payload["agents"]]
    brain = payload["brain"]
    assert brain["present"] is False, brain
    assert brain["links"] == 0, brain
    assert brain["verdict"] == "fault", brain["verdict"]
    assert payload["tooltip"][0] == "brain fault", payload["tooltip"]
    assert [item["id"] for item in brain["vitals"]] == list(VITAL_IDS), [item["id"] for item in brain["vitals"]]
    empty_expect = {
        "checkout": ("fail", "0/4"),
        "tree": ("fail", "no repo"),
        "remote": ("fail", "no list"),
        "level": ("warn", "no ref"),
        "links": ("fail", "0/3"),
        "permissions": ("fail", "broken"),
        "hooks": ("fail", "0/9"),
        "scaffolds": ("fail", "0/4"),
        "slip": ("warn", "no exit"),
        "memory": ("fail", "not installed"),
        "symlinks": ("fail", "not installed"),
        "boot": ("fail", "missing"),
        "tools": ("fail", "0/3"),
        "tex": ("fail", "missing"),
        "lean": ("fail", "missing"),
        "signing": ("fail", "unset"),
        "plugin": ("ok", "no shell"),
    }
    for item in brain["vitals"]:
        assert (item["state"], item["detail"]) == empty_expect[item["id"]], item
    assert [group["id"] for group in brain["groups"]] == ["checkout", "rules", "guards", "machine"], brain["groups"]
    assert "global brain" in brain["oneLine"], brain
    assert _ahead_behind("1\t1") == ("fail", "diverged")
    assert _ahead_behind("0\t2") == ("warn", "ahead 2")
    assert _ahead_behind("3\t0") == ("warn", "behind 3")
    assert _ahead_behind("0\t0") == ("ok", "level")
    assert _ahead_behind(None) == ("warn", "no ref")
    with tempfile.TemporaryDirectory() as healthy_tmp:
        healthy = Path(healthy_tmp)
        root = healthy / ".agents"
        root.mkdir()
        for name in CHECKOUT_FILES:
            (root / name).write_text("ok\n", encoding="utf-8")
        (root / "BRAIN_REMOTE").write_text("https://example.test/brain.git\n", encoding="utf-8")
        for rel in HOOK_FILES + SCAFFOLD_FILES:
            path = root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("ok\n", encoding="utf-8")
        (root / "permissions.json").write_text(
            json.dumps(
                {
                    "defaults": {"bash_without_prompt": True},
                    "permissions": {"allow": [], "deny": []},
                }
            ),
            encoding="utf-8",
        )
        slip_dir = root / "boot-dashboard"
        slip_dir.mkdir()
        (slip_dir / "close-slip.txt").write_text("CLEAN\n", encoding="utf-8")
        (slip_dir / "launch.sh").write_text("#!/bin/sh\n", encoding="utf-8")
        (slip_dir / "agents-boot-status.desktop").write_text(
            "[Desktop Entry]\nExec=/home/USER/.agents/boot-dashboard/launch.sh\n",
            encoding="utf-8",
        )
        auto = healthy / ".config" / "autostart"
        auto.mkdir(parents=True)
        launch = (slip_dir / "launch.sh").as_posix()
        (auto / "agents-boot-status.desktop").write_text(
            "[Desktop Entry]\nExec=" + launch + "\n",
            encoding="utf-8",
        )
        for script, flag_parent in (
            ("cron-jobs/claude-memory-guard/check-memory.sh", "cron-jobs/claude-memory-guard"),
            ("cron-jobs/agents-symlink-guard/check-links.sh", "cron-jobs/agents-symlink-guard"),
        ):
            guard = healthy / script
            guard.parent.mkdir(parents=True, exist_ok=True)
            guard.write_text("#!/bin/sh\n", encoding="utf-8")
            assert flag_parent
        target = root / "AGENTS.md"
        for rel in LINK_RELS:
            link = healthy / rel
            link.parent.mkdir(parents=True, exist_ok=True)
            link.symlink_to(target)
        (healthy / ".gitconfig").write_text(
            "[commit]\ngpgsign = true\n[gpg]\nprogram = gpg-git.sh\n[user]\nsigningkey = TESTKEY\n",
            encoding="utf-8",
        )

        def fake_git(_root: Path, args: list[str]) -> str | None:
            key = tuple(args)
            if key == ("status", "--porcelain", "--untracked-files=no"):
                return ""
            if key == ("rev-parse", "--short", "HEAD"):
                return "abc1234"
            if key == ("rev-parse", "--abbrev-ref", "HEAD"):
                return "main"
            if key == ("remote", "get-url", "origin"):
                return "https://example.test/brain.git"
            if key == ("rev-list", "--left-right", "--count", "origin/main...HEAD"):
                return "0\t0"
            return None

        def finder(name: str) -> str | None:
            if name in {"claude", "grok", "opencode", "latexmk", "lean"}:
                return "yes"
            return None

        healthy_brain = brain_status(healthy, which=finder, git=fake_git)
    assert healthy_brain["verdict"] == "clear", [
        (item["id"], item["state"], item["detail"])
        for item in healthy_brain["vitals"]
        if item["state"] != "ok"
    ]
    assert all(item["state"] == "ok" for item in healthy_brain["vitals"]), healthy_brain["vitals"]
    assert healthy_brain["slip"] == "clean", healthy_brain["slip"]
    assert healthy_brain["commit"] == "abc1234", healthy_brain
    healthy_blob = json.dumps(healthy_brain)
    assert "example.test" not in healthy_blob, healthy_blob
    blob = json.dumps(payload)
    for banned in ("/tmp", "Bearer", "sk-", "usage.json", "@"):
        assert banned not in blob, banned
        assert banned not in healthy_blob, banned
    print("self-test ok")


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        self_test()
        return 0
    json.dump(collect(Path.home(), force_go="--refresh-go" in argv), sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except Exception as exc:  # one line, no traceback into the bar journal
        print(f"usage.py: {type(exc).__name__}", file=sys.stderr)
        raise SystemExit(1) from None
