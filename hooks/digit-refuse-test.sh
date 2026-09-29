#!/usr/bin/env bash
# Fixture gate for digit-refuse. Each plant is a real PDF.
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

HOOK="$(cd "$(dirname "$0")" && pwd)/digit-refuse.sh"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

fail() {
  echo "digit-refuse-test: $*" >&2
  exit 1
}

run() {
  local dir="$1"
  shift
  set +e
  out="$(cd "$dir" && bash "$HOOK" "$@" 2>"$dir/err")"
  rc=$?
  set -e
  printf '%s' "$out" >"$dir/out"
  echo "$rc" >"$dir/rc"
}

expect_rc() {
  local dir="$1" want="$2"
  got="$(cat "$dir/rc")"
  [ "$got" = "$want" ] || fail "$dir exit $got want $want -- $(cat "$dir/out") $(cat "$dir/err")"
}

build_pdf() {
  local dir="$1"
  (cd "$dir" && pdflatex -interaction=nonstopmode -halt-on-error main.tex >latex.log)
}

write_doc() {
  local dir="$1" body="$2"
  mkdir -p "$dir"
  cat >"$dir/main.tex" <<EOF
\\documentclass{article}
\\newcommand{\\TODO}[1]{\\textbf{[TODO: #1]}}
\\begin{document}
$body
\\end{document}
EOF
}

# Kill switch: refused before any scan, and it writes nothing.
mkdir -p "$ROOT/kill"
printf 'marker\n' >"$ROOT/kill/marker"
before="$(ls -A "$ROOT/kill" | sort)"
set +e
bash "$HOOK" --fuzzy >"$ROOT/kill/out" 2>"$ROOT/kill/err"
rc=$?
set -e
[ "$rc" = "2" ] || fail "fuzzy exit $rc"
[ ! -s "$ROOT/kill/out" ] || fail "fuzzy wrote stdout"
after="$(ls -A "$ROOT/kill" | sort)"
# out and err are the test's files. The hook must not add its own.
[ "$before" = "marker" ] || fail "kill dir was not empty of hook output"
grep -q 'refused' "$ROOT/kill/err" || fail "fuzzy stderr"
for flag in --near --llm --repo --anywhere --close --substr --nope; do
  set +e
  bash "$HOOK" "$flag" >/dev/null 2>"$ROOT/kill/err2"
  rc=$?
  set -e
  [ "$rc" = "2" ] || fail "$flag exit $rc"
done

# Bare integer in the deny file is a refusal, not a scan.
mkdir -p "$ROOT/bare"
printf '100\n' >"$ROOT/bare/digit-refuse.deny"
printf 'x\n' >"$ROOT/bare/main.tex"
printf '%%pdf\n' >"$ROOT/bare/main.pdf"
set +e
bash "$HOOK" main.tex main.pdf >"$ROOT/bare/out" 2>"$ROOT/bare/err"
rc=$?
set -e
# run from the deny file's directory
rm -f "$ROOT/bare/out" "$ROOT/bare/err"
set +e
out="$(cd "$ROOT/bare" && bash "$HOOK" main.tex main.pdf 2>"$ROOT/bare/err")"
rc=$?
set -e
[ "$rc" = "2" ] || fail "bare exit $rc"
[ -z "$out" ] || fail "bare wrote stdout"
grep -q 'refused bare token' "$ROOT/bare/err" || fail "bare stderr"

# Pass: 100/135 in the prose and in the table. Silent.
write_doc "$ROOT/pass" '
The score is 100/135.
\begin{table}
\caption{D=10 paired wins}
\begin{tabular}{ll}
score & 100/135 \\
\end{tabular}
\end{table}
'
build_pdf "$ROOT/pass"
run "$ROOT/pass" main.tex main.pdf
expect_rc "$ROOT/pass" 0
[ ! -s "$ROOT/pass/out" ] || fail "pass was not silent: $(cat "$ROOT/pass/out")"

# Near number does not pass.
write_doc "$ROOT/near" '
The score is 100/136.
\begin{table}
\caption{D=10}
\begin{tabular}{ll}
score & 100/135 \\
\end{tabular}
\end{table}
'
build_pdf "$ROOT/near"
run "$ROOT/near" main.tex main.pdf
expect_rc "$ROOT/near" 1
grep -q '100/136 not in a table' "$ROOT/near/out" || fail "near miss text: $(cat "$ROOT/near/out")"
grep -q '100/135' "$ROOT/near/out" && fail "near reported the legal token" || true

# Cemetery token fails even when the table also contains it.
write_doc "$ROOT/deny" '
Do not cite 118/135.
\begin{table}
\caption{old}
\begin{tabular}{ll}
old & 118/135 \\
\end{tabular}
\end{table}
'
printf '118/135\n' >"$ROOT/deny/digit-refuse.deny"
build_pdf "$ROOT/deny"
run "$ROOT/deny" main.tex main.pdf
expect_rc "$ROOT/deny" 1
grep -q '118/135 denied' "$ROOT/deny/out" || fail "deny text: $(cat "$ROOT/deny/out")"

# A comment is not typeset. The skeleton may name the dead token there.
write_doc "$ROOT/comment" '
% 118/135
The score is 100/135.
\begin{table}
\caption{D=10}
\begin{tabular}{ll}
score & 100/135 \\
\end{tabular}
\end{table}
'
printf '118/135\n' >"$ROOT/comment/digit-refuse.deny"
build_pdf "$ROOT/comment"
run "$ROOT/comment" main.tex main.pdf
expect_rc "$ROOT/comment" 0
[ ! -s "$ROOT/comment/out" ] || fail "comment was not silent: $(cat "$ROOT/comment/out")"

# An honest TODO is not a claim. A cemetery token inside a TODO still ships.
write_doc "$ROOT/todo" '
\TODO{measure: rerun the cell}
The score is 100/135.
\begin{table}
\caption{D=10}
\begin{tabular}{ll}
score & 100/135 \\
\end{tabular}
\end{table}
'
build_pdf "$ROOT/todo"
run "$ROOT/todo" main.tex main.pdf
expect_rc "$ROOT/todo" 0
[ ! -s "$ROOT/todo/out" ] || fail "todo was not silent: $(cat "$ROOT/todo/out")"

write_doc "$ROOT/tododeny" '
\TODO{do not cite 118/135}
\begin{table}
\caption{empty}
\begin{tabular}{ll}
score & 1 \\
\end{tabular}
\end{table}
'
printf '118/135\n' >"$ROOT/tododeny/digit-refuse.deny"
build_pdf "$ROOT/tododeny"
run "$ROOT/tododeny" main.tex main.pdf
expect_rc "$ROOT/tododeny" 1
grep -q '118/135 denied' "$ROOT/tododeny/out" || fail "todo deny: $(cat "$ROOT/tododeny/out")"

# Three-digit integer in prose, absent from the table.
write_doc "$ROOT/nfe" '
Budget 8000.
\begin{table}
\caption{D=10}
\begin{tabular}{ll}
score & 100/135 \\
\end{tabular}
\end{table}
'
build_pdf "$ROOT/nfe"
run "$ROOT/nfe" main.tex main.pdf
expect_rc "$ROOT/nfe" 1
grep -q '8000 not in a table' "$ROOT/nfe/out" || fail "nfe: $(cat "$ROOT/nfe/out")"

# Same integer in the caption is the table speaking.
write_doc "$ROOT/nfecap" '
Budget 8000.
\begin{table}
\caption{Budget 8000.}
\begin{tabular}{ll}
score & 1 \\
\end{tabular}
\end{table}
'
build_pdf "$ROOT/nfecap"
run "$ROOT/nfecap" main.tex main.pdf
expect_rc "$ROOT/nfecap" 0
[ ! -s "$ROOT/nfecap/out" ] || fail "caption was not silent: $(cat "$ROOT/nfecap/out")"

# A single-hyphen digit group is an identifier (student id), not a measurement.
write_doc "$ROOT/ident" '
Student 02-23-20174 scored 100/135.
\begin{table}
\caption{D=10}
\begin{tabular}{ll}
score & 100/135 \\
\end{tabular}
\end{table}
'
build_pdf "$ROOT/ident"
run "$ROOT/ident" main.tex main.pdf
expect_rc "$ROOT/ident" 0
[ ! -s "$ROOT/ident/out" ] || fail "identifier was not silent: $(cat "$ROOT/ident/out")"

# A calendar year is not a measurement token.
write_doc "$ROOT/year" '
Recorded in 2026.
\begin{table}
\caption{D=10}
\begin{tabular}{ll}
score & 100/135 \\
\end{tabular}
\end{table}
'
build_pdf "$ROOT/year"
run "$ROOT/year" main.tex main.pdf
expect_rc "$ROOT/year" 0
[ ! -s "$ROOT/year/out" ] || fail "year was not silent: $(cat "$ROOT/year/out")"

# Chapter scope: a later chapter may not borrow an earlier table.
# Front matter may.
mkdir -p "$ROOT/chap"
cat >"$ROOT/chap/main.tex" <<'EOF'
\documentclass{report}
\begin{document}
Front matter 100/135.
\chapter{One}
\begin{table}
\caption{D=10}
\begin{tabular}{ll}
score & 100/135 \\
\end{tabular}
\end{table}
\chapter{Two}
Later chapter says 100/135.
\end{document}
EOF
printf 'scope=chapter\n' >"$ROOT/chap/digit-refuse.cfg"
build_pdf "$ROOT/chap"
run "$ROOT/chap" main.tex main.pdf
expect_rc "$ROOT/chap" 1
grep -q '100/135 not in a table' "$ROOT/chap/out" || fail "chapter: $(cat "$ROOT/chap/out")"
# The front-matter hit must not be the failure.
grep -q 'main.tex:3:' "$ROOT/chap/out" && fail "front matter was refused" || true

# Paper scope allows the later chapter to use the same table.
mkdir -p "$ROOT/paper"
cp "$ROOT/chap/main.tex" "$ROOT/paper/main.tex"
cp "$ROOT/chap/main.pdf" "$ROOT/paper/main.pdf"
printf 'scope=paper\n' >"$ROOT/paper/digit-refuse.cfg"
run "$ROOT/paper" main.tex main.pdf
expect_rc "$ROOT/paper" 0
[ ! -s "$ROOT/paper/out" ] || fail "paper scope: $(cat "$ROOT/paper/out")"

# A package pin in the preamble is not a claim.
write_doc "$ROOT/preamble" '
The score is 100/135.
\begin{table}
\caption{D=10}
\begin{tabular}{ll}
score & 100/135 \\
\end{tabular}
\end{table}
'
# write_doc already opened the document. Inject the pin above \begin{document}.
sed -i 's/\\begin{document}/\\newcommand{\\compat}{1.18}\n\\begin{document}/' "$ROOT/preamble/main.tex"
build_pdf "$ROOT/preamble"
run "$ROOT/preamble" main.tex main.pdf
expect_rc "$ROOT/preamble" 0
[ ! -s "$ROOT/preamble/out" ] || fail "preamble was not silent: $(cat "$ROOT/preamble/out")"

# Included table file counts. The token is not "somewhere in the repo";
# it is on the tex input path.
mkdir -p "$ROOT/inc"
cat >"$ROOT/inc/main.tex" <<'EOF'
\documentclass{article}
\begin{document}
The score is 100/135.
\input{tab}
\end{document}
EOF
cat >"$ROOT/inc/tab.tex" <<'EOF'
\begin{table}
\caption{D=10}
\begin{tabular}{ll}
score & 100/135 \\
\end{tabular}
\end{table}
EOF
build_pdf "$ROOT/inc"
run "$ROOT/inc" main.tex main.pdf
expect_rc "$ROOT/inc" 0
[ ! -s "$ROOT/inc/out" ] || fail "input was not silent: $(cat "$ROOT/inc/out")"

echo "digit-refuse-test: ok"
