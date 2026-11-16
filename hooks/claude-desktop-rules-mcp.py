#!/usr/bin/env python3
"""claude-desktop-rules-mcp.py — one MCP tool that returns the 1config rules.

Claude Desktop remote chat does not load ~/.claude/CLAUDE.md. It does announce
stdio MCP servers from claude_desktop_config.json. This server exposes one
tool, read_1config_rules, whose description tells the model to call it before
a 1config trigger. The rules stay in ~/.agents/AGENTS.md until that call.

    python3 ~/.agents/hooks/claude-desktop-rules-mcp.py
    python3 ~/.agents/hooks/claude-desktop-rules-mcp.py self-test

CLAUDE_DESKTOP_RULES_FILE overrides the rules path. The fixture uses it.
Speak MCP only on stdout. Diagnostics go to stderr.
"""
import json
import os
import pathlib
import select
import subprocess
import sys

TOOL_NAME = "read_1config_rules"
TOOL_DESCRIPTION = (
    "Read the user's 1config global rules and follow them. "
    "Call this before create_project, continue_project, checkpoint_project, "
    "writepaper_project, explain_thing, or global_brain_update. "
    "The file is local. This tool returns it. "
    "Reading AGENTS.md and CLAUDE.md is allowed."
)


def rules_path():
    override = os.environ.get("CLAUDE_DESKTOP_RULES_FILE")
    if override:
        return pathlib.Path(override)
    return pathlib.Path(__file__).resolve().parent.parent / "AGENTS.md"


def read_rules():
    path = rules_path()
    try:
        return path.read_text(encoding="utf-8"), None
    except OSError as err:
        return None, f"could not read {path}: {err.strerror or err}"


def send(obj):
    body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
    header = f"Content-Length: {len(body)}\r\n\r\n".encode("ascii")
    sys.stdout.buffer.write(header + body)
    sys.stdout.buffer.flush()


def recv():
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = sys.stdin.buffer.read(1)
        if not chunk:
            return None
        buf += chunk
    header, rest = buf.split(b"\r\n\r\n", 1)
    length = 0
    for line in header.decode("ascii", "replace").split("\r\n"):
        if line.lower().startswith("content-length:"):
            length = int(line.split(":", 1)[1].strip())
    while len(rest) < length:
        more = sys.stdin.buffer.read(length - len(rest))
        if not more:
            return None
        rest += more
    return json.loads(rest.decode("utf-8"))


def result(req, payload):
    send({"jsonrpc": "2.0", "id": req.get("id"), "result": payload})


def failure(req, code, message):
    send({"jsonrpc": "2.0", "id": req.get("id"), "error": {"code": code, "message": message}})


def handle(req):
    method = req.get("method")
    if method == "initialize":
        version = (req.get("params") or {}).get("protocolVersion") or "2024-11-05"
        result(req, {
            "protocolVersion": version,
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": "1config", "version": "1"},
        })
        return
    if method == "tools/list":
        result(req, {"tools": [{
            "name": TOOL_NAME,
            "description": TOOL_DESCRIPTION,
            "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
        }]})
        return
    if method == "tools/call":
        name = (req.get("params") or {}).get("name")
        if name != TOOL_NAME:
            failure(req, -32602, f"unknown tool {name}")
            return
        text, err = read_rules()
        if err:
            result(req, {"content": [{"type": "text", "text": err}], "isError": True})
        else:
            result(req, {"content": [{"type": "text", "text": text}], "isError": False})
        return
    if method == "ping":
        result(req, {})
        return
    if "id" in req:
        failure(req, -32601, f"unknown method {method}")


def serve():
    while True:
        req = recv()
        if req is None:
            return
        if req.get("method") in ("notifications/initialized", "initialized"):
            continue
        handle(req)


def self_test():
    def fail(msg):
        print(f"FAIL: {msg}", file=sys.stderr)
        raise SystemExit(1)

    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        rules = pathlib.Path(tmp) / "RULES.md"
        rules.write_text("RULES_MARKER_1config\n", encoding="utf-8")
        env = os.environ.copy()
        env["CLAUDE_DESKTOP_RULES_FILE"] = str(rules)
        proc = subprocess.Popen(
            [sys.executable, str(pathlib.Path(__file__).resolve())],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            env=env,
        )

        def send_msg(msg):
            body = json.dumps(msg).encode("utf-8")
            proc.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode("ascii") + body)
            proc.stdin.flush()

        def recv_msg():
            buf = b""
            while b"\r\n\r\n" not in buf:
                ready, _, _ = select.select([proc.stdout], [], [], 5)
                if not ready:
                    fail("timed out waiting for the MCP server")
                chunk = os.read(proc.stdout.fileno(), 1)
                if not chunk:
                    fail("MCP server closed stdout")
                buf += chunk
            header, rest = buf.split(b"\r\n\r\n", 1)
            length = 0
            for line in header.decode("ascii", "replace").split("\r\n"):
                if line.lower().startswith("content-length:"):
                    length = int(line.split(":", 1)[1].strip())
            while len(rest) < length:
                ready, _, _ = select.select([proc.stdout], [], [], 5)
                if not ready:
                    fail("timed out reading an MCP body")
                more = os.read(proc.stdout.fileno(), length - len(rest))
                if not more:
                    fail("MCP body ended early")
                rest += more
            return json.loads(rest.decode("utf-8"))

        try:
            send_msg({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2024-11-05"}})
            init = recv_msg()
            if init.get("result", {}).get("serverInfo", {}).get("name") != "1config":
                fail(f"initialize failed: {init}")
            send_msg({"jsonrpc": "2.0", "method": "notifications/initialized"})
            send_msg({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
            listed = recv_msg()
            tools = listed.get("result", {}).get("tools", [])
            if len(tools) != 1 or tools[0].get("name") != TOOL_NAME:
                fail(f"tools/list failed: {listed}")
            if "continue_project" not in tools[0].get("description", ""):
                fail("tool description does not name continue_project")
            send_msg({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": TOOL_NAME, "arguments": {}}})
            called = recv_msg()
            text = called.get("result", {}).get("content", [{}])[0].get("text", "")
            if "RULES_MARKER_1config" not in text or called.get("result", {}).get("isError"):
                fail(f"tools/call failed: {called}")
        finally:
            if proc.poll() is None:
                proc.kill()
            proc.wait(timeout=5)
    print("ok")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "self-test":
        self_test()
        return
    serve()


if __name__ == "__main__":
    main()
