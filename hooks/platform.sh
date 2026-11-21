#!/usr/bin/env bash
# platform.sh — sourced by setup.sh. Which package family this machine is.
#
#   platform_detect OS_RELEASE_FILE HAS_OMARCHY   (HAS_OMARCHY is 1 or 0)
#
# Sets FAMILY (omarchy, debian, arch, or unknown), PLATFORM_ID (the ID line of
# the os-release file), and HINT (the one install line for what setup.sh needs).
# Omarchy wins over the os-release file: it is Arch underneath, and its own
# package command is the one a person there uses.

platform_detect() {
  local file="$1" has_omarchy="${2:-0}" id="" like="" line key value
  FAMILY=unknown
  PLATFORM_ID=""
  HINT="install python3, flock (util-linux), git, cron, gnupg, gnome-keyring"
  if [ -f "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      key="${line%%=*}"
      value="${line#*=}"
      value="${value%\"}"
      value="${value#\"}"
      case "$key" in
        ID) id="$value" ;;
        ID_LIKE) like="$value" ;;
      esac
    done < "$file"
  fi
  PLATFORM_ID="$id"
  if [ "$has_omarchy" = 1 ]; then
    FAMILY=omarchy
    HINT="omarchy pkg add python util-linux cronie git gnupg gnome-keyring texlive-meta"
  elif printf '%s %s\n' "$id" "$like" | grep -qiE 'ubuntu|debian'; then
    FAMILY=debian
    HINT="sudo apt-get install -y python3 util-linux cron git gnupg gnome-keyring texlive-full"
  elif printf '%s %s\n' "$id" "$like" | grep -qi arch; then
    FAMILY=arch
    HINT="sudo pacman -S --needed python util-linux cronie git gnupg gnome-keyring texlive-meta"
  fi
}
