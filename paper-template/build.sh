#!/usr/bin/env bash
# Build the reference-free paper with latexmk until cross-references settle.
# Optional Lean kernel-check: if lean/ exists and lake is on PATH, also
# `lake build`. Missing lake is a Gap, not a failed PDF. Type errors fail.
# Usage: bash docs/paper/build.sh [clean]
set -euo pipefail

cd "$(dirname "$0")"
export PATH="${HOME}/.elan/bin:${PATH:-}"

if [ "${1:-}" = "clean" ]; then
  latexmk -C
  if [ -d lean ] && command -v lake >/dev/null 2>&1; then
    (cd lean && lake clean) || true
  fi
  echo "cleaned"
  exit 0
fi

# No bibliography by design — no biber/bibtex pass.
latexmk -pdf -interaction=nonstopmode -halt-on-error main.tex

# Digit refuse: prose measurement tokens must already be in a table.
# Fuzzy / near / LLM / repo-wide search is not this hook. Silence means clean.
refuse="${HOME}/.agents/hooks/digit-refuse.sh"
if [ ! -x "$refuse" ]; then
  echo "digit-refuse: missing $refuse" >&2
  exit 1
fi
bash "$refuse" main.tex main.pdf

pages="$(pdfinfo main.pdf 2>/dev/null | awk '/^Pages:/ {print $2}')"
echo "built main.pdf (${pages:-?} pages)"

# Unresolved markers are a build result, not a warning to scroll past.
todos="$(grep -n '\\TODO{' main.tex | grep -v 'newcommand' || true)"
if [ -n "$todos" ]; then
  echo "open TODOs: $(printf '%s\n' "$todos" | wc -l)"
  printf '%s\n' "$todos" | head -20
fi

# Opt-in Lean: only if this paper copied lean/. Never fetch Mathlib here.
if [ -d lean ]; then
  if command -v lake >/dev/null 2>&1; then
    echo "lean: lake build"
    (cd lean && lake build)
    sorry_lines="$(grep -RInE --include='*.lean' -e '\bsorry\b' -e '\badmit\b' lean || true)"
    if [ -n "$sorry_lines" ]; then
      echo "lean sorry: $(printf '%s\n' "$sorry_lines" | wc -l)"
      printf '%s\n' "$sorry_lines"
    else
      echo "lean sorry: 0"
    fi
    echo "lean: lake build ok (kernel-checked Lean statements; not a proof that LaTeX matches)"
  else
    echo "LEAN SKIPPED: lake not on PATH — bash ~/.agents/hooks/install-elan.sh"
  fi
fi
