#!/usr/bin/env bash
# brain-remote.sh — sourced by sync.sh, brain-sync.sh, checkpoint.sh, notes-sync.sh, and verify.sh.
# Loads the URL allowlist from BRAIN_REMOTE. Does not hardcode a GitHub path.
# One reader for that file: comments, blank lines, and CRLF are handled here only.

brain_remote_load() {
  local file="$1" line
  BRAIN_REMOTE_URLS=()
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      ''|\#*) continue ;;
    esac
    BRAIN_REMOTE_URLS+=("$line")
  done < "$file"
  [ "${#BRAIN_REMOTE_URLS[@]}" -gt 0 ]
}

brain_remote_ok() {
  local u="$1" x
  for x in "${BRAIN_REMOTE_URLS[@]}"; do
    [ "$u" = "$x" ] && return 0
  done
  return 1
}
