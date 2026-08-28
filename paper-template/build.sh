#!/usr/bin/env bash
# Build the reference-free paper with latexmk until cross-references settle.
# Usage: bash docs/paper/build.sh [clean]
set -euo pipefail

cd "$(dirname "$0")"

if [ "${1:-}" = "clean" ]; then
  latexmk -C
  echo "cleaned"
  exit 0
fi

# No bibliography by design — no biber/bibtex pass.
latexmk -pdf -interaction=nonstopmode -halt-on-error main.tex

pages="$(pdfinfo main.pdf 2>/dev/null | awk '/^Pages:/ {print $2}')"
echo "built main.pdf (${pages:-?} pages)"

# Unresolved markers are a build result, not a warning to scroll past.
todos="$(grep -n '\\TODO{' main.tex | grep -v 'newcommand' || true)"
if [ -n "$todos" ]; then
  echo "open TODOs: $(printf '%s\n' "$todos" | wc -l)"
  printf '%s\n' "$todos" | head -20
fi
