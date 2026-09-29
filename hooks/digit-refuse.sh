#!/usr/bin/env bash
# Measurement tokens in prose must already sit in a table. Exact match.
# Exit 0 is silent. Exit 1 prints file:line. Exit 2 refuses a fuzzy check
# and writes nothing.
# Usage: digit-refuse.sh main.tex main.pdf
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
here="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$here/digit-refuse.py" "$@"
