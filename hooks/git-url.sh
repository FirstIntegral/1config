#!/usr/bin/env bash
# git-url.sh — sourced by checkpoint.sh and notes-sync.sh. One parser for remote URLs.
#
#   git_url_parse URL             -> "host owner repo" (lowercase), or nothing when unparsed
#   git_url_host_effective HOST   -> the HostName ssh dials for HOST (resolves an ssh config alias)
#
# Parsed shapes:
#   [user@]host:owner/repo[.git]                        scp-like
#   scheme://[user[:pw]@]host[:port]/owner/repo[.git]   ssh, git, https, http, git+ssh, ...
# ssh.github.com folds to github.com. A local path, file://, and an scp-like
# absolute path (host:/srv/git/x.git) stay unparsed.
#
# shortcut: owner is the first path component and repo the second, so a GitLab
# subgroup remote keys on group/subgroup. Upgrade when such a remote needs notes.

git_url_parse() {
  local url="$1" host rest owner repo
  url="${url%%\?*}"
  url="${url%/}"
  url="${url%.git}"
  url="${url%/}"
  case "$url" in
    ''|file://*|/*|./*|../*|'~'*) return 0 ;;
    *://*)
      rest="${url#*://}"
      case "$rest" in */*) ;; *) return 0 ;; esac
      host="${rest%%/*}"
      rest="${rest#*/}"
      host="${host##*@}"
      case "$host" in
        '['*']'*) host="${host#\[}"; host="${host%%\]*}" ;;
        *) host="${host%%:*}" ;;
      esac
      ;;
    *:*)
      host="${url%%:*}"
      rest="${url#*:}"
      case "$host" in ''|*/*) return 0 ;; esac
      host="${host##*@}"
      # A one-letter host is a drive letter, not a remote.
      [ "${#host}" -gt 1 ] || return 0
      ;;
    *) return 0 ;;
  esac
  owner="${rest%%/*}"
  repo="${rest#*/}"
  repo="${repo%%/*}"
  if [ -z "$host" ] || [ -z "$owner" ] || [ -z "$repo" ] || [ "$owner" = "$rest" ]; then
    return 0
  fi
  host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
  [ "$host" = "ssh.github.com" ] && host="github.com"
  printf '%s %s %s\n' "$host" \
    "$(printf '%s' "$owner" | tr '[:upper:]' '[:lower:]')" \
    "$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')"
}

# `Host gh-work` with `HostName github.com` is a common two-account setup.
# ssh -G prints the resolved config and opens no connection.
# GIT_URL_SSH_CONFIG is for verify.sh only.
git_url_host_effective() {
  local host="$1" real=""
  if command -v ssh >/dev/null 2>&1; then
    if [ -n "${GIT_URL_SSH_CONFIG:-}" ]; then
      real="$(timeout 5 ssh -F "$GIT_URL_SSH_CONFIG" -G "$host" 2>/dev/null | awk '$1 == "hostname" { print $2; exit }')"
    else
      real="$(timeout 5 ssh -G "$host" 2>/dev/null | awk '$1 == "hostname" { print $2; exit }')"
    fi
  fi
  [ -n "$real" ] || real="$host"
  real="$(printf '%s' "$real" | tr '[:upper:]' '[:lower:]')"
  [ "$real" = "ssh.github.com" ] && real="github.com"
  printf '%s\n' "$real"
}
