#!/usr/bin/env python3
"""Digit refuse: a measurement token in prose must already be in a table.

Exact characters only. A cemetery token in digit-refuse.deny must not be
typeset at all. Fuzzy match, a near number, an LLM read, and a repo-wide
search are refused before any scan (exit 2, no files written).

Exit 0 prints nothing. Exit 1 prints file:line. Exit 2 is a refusal.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

KILL_FLAGS = {
    "--fuzzy",
    "--near",
    "--llm",
    "--repo",
    "--anywhere",
    "--close",
    "--substr",
}

TABLE_ENVS = {"tabular", "tabularx", "tabular*", "longtable", "longtabu", "tblr"}
SCOPES = {"paper", "chapter", "section"}

# One measurement, as the author typed it after tex syntax is unfolded.
# Alternation order matters: a fraction must win over the integers inside it.
# The trailing lookbehind keeps a decimal's fraction from becoming its own
# integer. The lookahead allows a sentence period ("100/135.") and rejects
# a decimal that we stopped inside ("10" in "10.5" is not a token).
TOKEN_RE = re.compile(
    r"(?<![A-Za-z0-9.])("
    r"-?\d{1,6}/\d{1,6}"
    r"|-?\d+\.\d+"
    r"|-?\d+(?:\.\d+)?%"
    r"|-?\d+(?:\.\d+)?[eE][+-]?\d+"
    r"|\d+(?:--\d+)+"
    r"|-?\d{3,}"
    r")(?![A-Za-z0-9])(?!\.\d)"
)

YEAR_RE = re.compile(r"^-?(?:19|20)\d{2}$")
BARE_INT_RE = re.compile(r"^-?\d+$")
INPUT_RE = re.compile(r"\\(?:input|include)\s*\{([^{}]+)\}")
MACRO_RE = re.compile(
    r"\\(?:newcommand|renewcommand|providecommand|def)\s*\{\\(\w+)\}\s*\{([^{}]*)\}"
    r"|\\def\s*\\(\w+)\s*\{([^{}]*)\}"
)
NONTYPESET = (
    "label",
    "ref",
    "cref",
    "Cref",
    "eqref",
    "pageref",
    "cite",
    "citep",
    "citet",
    "citeauthor",
    "includegraphics",
    "bibliography",
    "addbibresource",
    "url",
    "lstinputlisting",
    "graphicspath",
    "bibliographystyle",
    "hypersetup",
)


class GiveUp(Exception):
    def __init__(self, message: str, code: int) -> None:
        super().__init__(message)
        self.code = code


def refuse(message: str = "digit-refuse: refused") -> None:
    raise GiveUp(message, 2)


def fail(message: str) -> None:
    raise GiveUp(message, 1)


def strip_comment(line: str) -> str:
    i = 0
    n = len(line)
    while i < n:
        if line[i] == "\\":
            i += 2
            continue
        if line[i] == "%":
            return line[:i]
        i += 1
    return line


def parse_cfg(path: Path) -> tuple[str, set[str]]:
    scope = "paper"
    skip: set[str] = set()
    if not path.is_file():
        return scope, skip
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if "=" not in line:
            refuse("digit-refuse: refused bad cfg")
        key, value = (part.strip() for part in line.split("=", 1))
        if key == "scope":
            if value not in SCOPES:
                refuse("digit-refuse: refused bad cfg")
            scope = value
        elif key == "skip-cmd":
            if not re.fullmatch(r"[A-Za-z]+", value):
                refuse("digit-refuse: refused bad cfg")
            skip.add(value)
        else:
            refuse("digit-refuse: refused bad cfg")
    return scope, skip


def load_deny(path: Path) -> list[str]:
    if not path.is_file():
        return []
    tokens: list[str] = []
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        token = normalize_token(line)
        if token is None or BARE_INT_RE.fullmatch(token):
            refuse(f"digit-refuse: refused bare token {line.strip()}")
        if token not in tokens:
            tokens.append(token)
    return tokens


def normalize_token(raw: str) -> str | None:
    found = tokens_of(raw)
    if len(found) != 1:
        return None
    return found[0]


def prepare(text: str) -> str:
    text = text.translate(str.maketrans({"–": "--", "—": "--", "−": "-"}))
    text = text.replace("$", "")
    text = text.replace(r"\%", "%")
    text = re.sub(r"(?<=\d)\{\\,\}(?=\d)", "", text)
    text = re.sub(r"(?<=\d)\\,(?=\d)", "", text)
    text = re.sub(r"\\frac\{(-?\d+)\}\{(-?\d+)\}", r"\1/\2", text)
    text = re.sub(r"\\num\{([^{}]*)\}", r"\1", text)
    return text


def tied_by_single_hyphen(text: str, start: int, end: int) -> bool:
    """02-23-20174 is an identifier. 13--2 is a result and is not seen here."""
    if start >= 2 and text[start - 1] == "-" and text[start - 2].isdigit() and text[start - 2 : start] != "--":
        if start < 3 or text[start - 3] != "-":
            return True
    if end + 1 < len(text) and text[end] == "-" and text[end + 1].isdigit():
        if end + 2 >= len(text) or text[end + 1 : end + 3] != "--":
            if end == 0 or text[end - 1] != "-":
                return True
    return False


def tokens_of(text: str) -> list[str]:
    prepared = prepare(text)
    out: list[str] = []
    for match in TOKEN_RE.finditer(prepared):
        token = match.group(1)
        if YEAR_RE.fullmatch(token):
            continue
        if BARE_INT_RE.fullmatch(token) and tied_by_single_hyphen(prepared, match.start(1), match.end(1)):
            continue
        out.append(token)
    return out


def blank_command(text: str, name: str) -> str:
    """Replace \\name{...} with spaces. Newlines stay so line numbers hold."""
    needle = "\\" + name
    out = list(text)
    i = 0
    n = len(text)
    while i < n:
        j = text.find(needle, i)
        if j < 0:
            break
        after = j + len(needle)
        if after < n and text[after].isalpha():
            i = after
            continue
        k = after
        while k < n and text[k] in " \t":
            k += 1
        if k >= n or text[k] != "{":
            i = after
            continue
        depth = 0
        end = k
        while end < n:
            if text[end] == "{":
                depth += 1
            elif text[end] == "}":
                depth -= 1
                if depth == 0:
                    end += 1
                    break
            end += 1
        for pos in range(j, end):
            if out[pos] != "\n":
                out[pos] = " "
        i = end
    return "".join(out)


def blank_nontypeset(text: str) -> str:
    for name in NONTYPESET:
        text = blank_command(text, name)
    return text


def search_dirs(source: Path, main: Path) -> list[Path]:
    dirs = [source.parent, main.parent, main.parent / "shared"]
    for part in os.environ.get("TEXINPUTS", "").split(":"):
        if part:
            dirs.append(Path(part))
    seen: set[Path] = set()
    out: list[Path] = []
    for directory in dirs:
        try:
            resolved = directory.resolve()
        except OSError:
            continue
        if resolved in seen:
            continue
        seen.add(resolved)
        out.append(directory)
    return out


def resolve_input(name: str, source: Path, main: Path) -> Path | None:
    rel = name.strip().strip('"').strip("'")
    if not rel or rel.startswith("/") or ".." in Path(rel).parts:
        return None
    stems = [rel] if rel.endswith(".tex") else [rel + ".tex", rel]
    for directory in search_dirs(source, main):
        for stem in stems:
            candidate = directory / stem
            if candidate.is_file():
                return candidate.resolve()
    return None


class Line:
    def __init__(self, path: Path, number: int, text: str) -> None:
        self.path = path
        self.number = number
        self.text = text


def expand_file(path: Path, main: Path, stack: tuple[Path, ...]) -> list[Line]:
    if path in stack:
        fail(f"digit-refuse: input cycle {path}")
    try:
        raw = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        fail(f"digit-refuse: cannot read {path}: {exc}")
    lines: list[Line] = []
    for number, raw_line in enumerate(raw.splitlines(), 1):
        code = strip_comment(raw_line)
        pieces = split_inputs(code)
        if pieces is None:
            lines.append(Line(path, number, code))
            continue
        for kind, payload in pieces:
            if kind == "text":
                if payload:
                    lines.append(Line(path, number, payload))
                continue
            child = resolve_input(payload, path, main)
            if child is None:
                fail(f"{display_path(path, main)}:{number}: missing input {payload}")
            lines.extend(expand_file(child, main, stack + (path,)))
    return lines


def split_inputs(code: str) -> list[tuple[str, str]] | None:
    matches = list(INPUT_RE.finditer(code))
    if not matches:
        return None
    pieces: list[tuple[str, str]] = []
    cursor = 0
    for match in matches:
        pieces.append(("text", code[cursor : match.start()]))
        pieces.append(("input", match.group(1)))
        cursor = match.end()
    pieces.append(("text", code[cursor:]))
    return pieces


def collect_macros(lines: list[Line]) -> dict[str, str]:
    full = "\n".join(line.text for line in lines)
    defs: dict[str, str] = {}
    for match in MACRO_RE.finditer(full):
        if match.group(1):
            defs[match.group(1)] = match.group(2).replace("\n", " ")
        else:
            defs[match.group(3)] = match.group(4).replace("\n", " ")
    return defs


def apply_macros(text: str, defs: dict[str, str]) -> str:
    if not defs:
        return text
    patterns = [
        (
            name,
            re.compile(r"(?<![A-Za-z{])\\" + re.escape(name) + r"(?![A-Za-z])"),
            body,
        )
        for name, body in defs.items()
    ]
    for _ in range(6):
        changed = False
        for _name, pattern, body in patterns:
            text, count = pattern.subn(lambda _m, b=body: b, text)
            changed = changed or count > 0
        if not changed:
            break
    return text


def display_path(path: Path, main: Path) -> str:
    try:
        return str(path.resolve().relative_to(main.parent.resolve()))
    except ValueError:
        return str(path)


def skip_space(text: str, i: int) -> int:
    while i < len(text) and text[i] in " \t":
        i += 1
    return i


def command_at(text: str, i: int) -> tuple[str, int] | None:
    if i >= len(text) or text[i] != "\\":
        return None
    j = i + 1
    if j < len(text) and not text[j].isalpha():
        return None
    while j < len(text) and text[j].isalpha():
        j += 1
    if j == i + 1:
        return None
    return text[i + 1 : j], j


def consume_braced(text: str, i: int) -> int:
    """i points at '{'. Return the index after the matching '}'."""
    depth = 0
    while i < len(text):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return len(text)


def consume_bracket(text: str, i: int) -> int:
    depth = 0
    while i < len(text):
        if text[i] == "[":
            depth += 1
        elif text[i] == "]":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return len(text)


def classify(text: str, mask_cmds: set[str]) -> list[str]:
    """One kind per character: prose, table, caption, mask, or skip."""
    kinds = ["prose"] * len(text)
    env: list[str] = []
    caption = 0
    mask = 0
    i = 0
    n = len(text)

    def paint(a: int, b: int, kind: str) -> None:
        for pos in range(a, b):
            if text[pos] != "\n":
                kinds[pos] = kind

    def current() -> str:
        if mask:
            return "mask"
        if any(name in TABLE_ENVS for name in env):
            return "table"
        if caption:
            return "caption"
        return "prose"

    while i < n:
        if text[i] == "\\":
            parsed = command_at(text, i)
            if parsed is None:
                step = 2 if i + 1 < n else 1
                paint(i, i + step, current())
                i += step
                continue
            name, after = parsed
            if name == "begin":
                k = skip_space(text, after)
                if k < n and text[k] == "{":
                    end_name = consume_braced(text, k)
                    envname = text[k + 1 : end_name - 1]
                    cursor = skip_space(text, end_name)
                    if cursor < n and text[cursor] == "[":
                        cursor = consume_bracket(text, cursor)
                        cursor = skip_space(text, cursor)
                    if cursor < n and text[cursor] == "{":
                        cursor = consume_braced(text, cursor)
                        cursor = skip_space(text, cursor)
                    if envname in ("tabularx", "tblr") and cursor < n and text[cursor] == "{":
                        cursor = consume_braced(text, cursor)
                    env.append(envname)
                    paint(i, cursor, "skip")
                    i = cursor
                    continue
            if name == "end":
                k = skip_space(text, after)
                end_at = after
                closing = ""
                if k < n and text[k] == "{":
                    end_at = consume_braced(text, k)
                    closing = text[k + 1 : end_at - 1]
                paint(i, end_at, "skip")
                if closing and closing in env:
                    while env and env[-1] != closing:
                        env.pop()
                    if env and env[-1] == closing:
                        env.pop()
                i = end_at
                continue
            if name == "caption" and caption == 0 and mask == 0:
                k = skip_space(text, after)
                if k < n and text[k] == "{":
                    caption = 1
                    paint(i, k + 1, "caption")
                    i = k + 1
                    continue
            if name in mask_cmds and mask == 0 and caption == 0:
                k = skip_space(text, after)
                if k < n and text[k] == "{":
                    mask = 1
                    paint(i, k + 1, "mask")
                    i = k + 1
                    continue
            paint(i, after, current())
            i = after
            continue
        kind = current()
        if text[i] == "{" and caption:
            caption += 1
        elif text[i] == "}" and caption:
            caption -= 1
            kinds[i] = "caption"
            i += 1
            continue
        elif text[i] == "{" and mask:
            mask += 1
        elif text[i] == "}" and mask:
            mask -= 1
            kinds[i] = "mask"
            i += 1
            continue
        if text[i] != "\n":
            kinds[i] = kind
        i += 1
    return kinds


def token_in_text(token: str, text: str) -> bool:
    if token in text:
        return True
    pattern = r"\s*".join(re.escape(ch) for ch in token)
    return re.search(pattern, text) is not None


def pdf_text(path: Path) -> str:
    if not path.is_file():
        fail(f"digit-refuse: no pdf {path}")
    try:
        proc = subprocess.run(
            ["pdftotext", "-layout", "-q", str(path), "-"],
            check=False,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        fail("digit-refuse: pdftotext missing")
    if proc.returncode != 0:
        fail(f"digit-refuse: pdftotext failed ({proc.returncode})")
    return proc.stdout.translate(str.maketrans({"–": "--", "—": "--", "−": "-"}))


def scope_ids(lines: list[Line], scope: str) -> list[int]:
    if scope == "paper":
        return [1] * len(lines)
    ids: list[int] = []
    current = 0
    marker = r"\chapter" if scope == "chapter" else r"\section"
    for line in lines:
        if re.search(re.escape(marker) + r"\b", line.text):
            current += 1
        ids.append(current)
    return ids


def check(main: Path, pdf: Path) -> list[str]:
    main = main.resolve()
    cfg_scope, skip = parse_cfg(main.parent / "digit-refuse.cfg")
    deny = load_deny(main.parent / "digit-refuse.deny")
    lines = expand_file(main, main, ())
    defs = collect_macros(lines)
    for line in lines:
        line.text = apply_macros(line.text, defs)
    # Package pins live in the preamble (\pgfplotsset{compat=1.18}). They are
    # not claims. A macro defined there still expands at its use in the body.
    for index, line in enumerate(lines):
        if r"\begin{document}" in line.text:
            for earlier in lines[:index]:
                earlier.text = ""
            break
    shown = blank_nontypeset("\n".join(line.text for line in lines))
    # apply_macros / blank keep newline count because they run per the joined
    # text and neither inserts a newline. Guard that assumption.
    shown_lines = shown.split("\n")
    if len(shown_lines) != len(lines):
        fail("digit-refuse: internal line map drifted")
    kinds = classify(shown, {"TODO"} | skip)
    offsets: list[int] = []
    cursor = 0
    for line in shown_lines:
        offsets.append(cursor)
        cursor += len(line) + 1

    scopes = scope_ids(lines, cfg_scope)
    legal: dict[int, set[str]] = {}
    prose_hits: list[tuple[int, str]] = []
    denied_hits: list[tuple[int, str]] = []

    def add_legal(scope_id: int, token: str) -> None:
        legal.setdefault(scope_id, set()).add(token)

    for index, line in enumerate(shown_lines):
        start = offsets[index]
        runs: list[tuple[str, int, int]] = []
        pos = 0
        while pos < len(line):
            kind = kinds[start + pos]
            end = pos + 1
            while end < len(line) and kinds[start + end] == kind:
                end += 1
            runs.append((kind, pos, end))
            pos = end
        scope_id = scopes[index]
        for kind, a, b in runs:
            chunk = line[a:b]
            found = tokens_of(chunk)
            if kind in {"table", "caption"}:
                for token in found:
                    add_legal(scope_id, token)
            elif kind == "prose":
                for token in found:
                    prose_hits.append((index, token))
            if kind != "skip":
                for token in found:
                    if token in deny:
                        denied_hits.append((index, token))

    pdf_body = pdf_text(pdf)
    for token in deny:
        if token_in_text(token, pdf_body):
            if not any(hit_token == token for _idx, hit_token in denied_hits):
                denied_hits.append((-1, token))

    problems: list[tuple[str, int, str, str]] = []
    seen: set[tuple[int, str, str]] = set()

    def add(index: int, token: str, reason: str) -> None:
        key = (index, token, reason)
        if key in seen:
            return
        seen.add(key)
        if index < 0:
            problems.append(("pdf", 0, token, reason))
            return
        line = lines[index]
        problems.append((display_path(line.path, main), line.number, token, reason))

    for index, token in denied_hits:
        add(index, token, "denied")

    all_legal = set().union(*legal.values()) if legal else set()
    for index, token in prose_hits:
        if token in deny:
            continue
        scope_id = scopes[index]
        if cfg_scope == "paper" or scope_id == 0:
            allowed = all_legal
        else:
            allowed = legal.get(scope_id, set())
        if token not in allowed:
            add(index, token, "not in a table")

    problems.sort(key=lambda item: (item[0], item[1], item[2], item[3]))
    return [f"{path}:{number}: {token} {reason}" for path, number, token, reason in problems]


def argv_refused(argv: list[str]) -> bool:
    for arg in argv:
        if arg in KILL_FLAGS:
            return True
        if arg.startswith("--"):
            return True
    return False


def main(argv: list[str]) -> int:
    if argv_refused(argv[1:]):
        print("digit-refuse: refused", file=sys.stderr)
        return 2
    if len(argv) != 3:
        print("digit-refuse: refused", file=sys.stderr)
        return 2
    try:
        rows = check(Path(argv[1]), Path(argv[2]))
    except GiveUp as exc:
        print(exc, file=sys.stderr if exc.code == 2 else sys.stdout)
        return exc.code
    if rows:
        print("\n".join(rows))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
