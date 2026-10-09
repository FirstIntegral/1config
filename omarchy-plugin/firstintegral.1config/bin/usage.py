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


FACE = {
    "claude": "Claude",
    "grok": "Grok",
    "opencode": "OpenCode",
    "codex": "Codex",
    "fireworks": "Fireworks",
}

CORE_IDS = ("claude", "grok", "opencode")
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
        "blurb": "OpenCode Go windows come from opencode.ai. The other tools are read on this machine.",
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


def collect(home: Path, now: datetime | None = None, *, force_go: bool = False) -> dict:
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
    by_id["opencode"] = attach_go(opencode_agent(home, now), home, now, force=force_go)
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
        "note": "OpenCode Go is the plan on opencode.ai: rolling, weekly, monthly. The dollar credit balance stays on the console. u refreshes Claude, Codex, and Fireworks, and reads Go again.",
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
        cache_dir = home / ".local" / "state" / "1config"
        cache_dir.mkdir(parents=True)
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
    json.dump(collect(Path.home(), force_go="--refresh-go" in argv), sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except Exception as exc:  # one line, no traceback into the bar journal
        print(f"usage.py: {type(exc).__name__}", file=sys.stderr)
        raise SystemExit(1) from None
