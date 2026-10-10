#!/usr/bin/env bash
# Home spill guard. See home-spill-guard.py.
set -euo pipefail
mode="${1:-sweep}"
case "$mode" in
  sweep|sweep-live|pretool) ;;
  *)
    echo "usage: home-spill-guard.sh sweep|pretool" >&2
    exit 2
    ;;
esac
here="$(readlink -f "$0")"
exec python3 "$(dirname "$here")/home-spill-guard.py" "$mode"
