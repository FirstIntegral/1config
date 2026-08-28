#!/usr/bin/env bash
# Updates opencode, grok, and claude CLI apps; refreshes ~/.agents/SETUP.md inventory.
# Invoked on boot (@reboot cron) and resume from suspend.
# SOURCE: ~/.agents/updater/ — setup.sh copies to ~/cron-jobs/ai-terminal-tools-update-on-boot/
# (logs/lock stay in the installed dir). Keep installed copy byte-identical.
set -u

DIR="${UPD_INSTALL_DIR:-$HOME/cron-jobs/ai-terminal-tools-update-on-boot}"
LOG="$DIR/update-apps.log"
LOCK="$DIR/.update.lock"
TIMEOUT_DEFAULT="${TIMEOUT_DEFAULT:-300}"
# Per-run slice for claude CDN download (resume across boots). Full ~275MB on a
# slow link may need several boots; progress lives in ~/.claude/downloads/.
# Override: TIMEOUT_CLAUDE_SLICE=3600 ./update-apps.sh
TIMEOUT_CLAUDE_SLICE="${TIMEOUT_CLAUDE_SLICE:-600}"
SETUP_MD="${SETUP_MD:-$HOME/.agents/SETUP.md}"
CLAUDE_VERSIONS_DIR="${CLAUDE_VERSIONS_DIR:-$HOME/.local/share/claude/versions}"
CLAUDE_DOWNLOADS_DIR="${CLAUDE_DOWNLOADS_DIR:-$HOME/.claude/downloads}"
CLAUDE_STAGING_DIR="${CLAUDE_STAGING_DIR:-$HOME/.cache/claude/staging}"
CLAUDE_CDN="${CLAUDE_CDN:-https://downloads.claude.ai/claude-code-releases}"
# Incomplete native installs leave tiny/empty files; real binaries are ~250MB+
CLAUDE_MIN_BYTES=50000000
ts() { date '+%Y-%m-%d %H:%M:%S'; }

# Refuse to run if another update is already in progress (boot-check or resume)
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "[$(ts)] update-apps: another run holds the lock → exit" >> "$LOG"
  exit 0
fi

# Ensure the installed CLI bins are on PATH (cron runs with a minimal env)
export PATH="$HOME/.opencode/bin:$HOME/.grok/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"

# --- GitHub token (raises unauth 60/hr → 5000/hr; opencode upgrade hits api.github.com) ---
load_github_token() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    export GITHUB_TOKEN
    return 0
  fi
  if [ -n "${GH_TOKEN:-}" ]; then
    export GITHUB_TOKEN="$GH_TOKEN"
    return 0
  fi
  local f
  for f in \
    "$HOME/.config/github/token" \
    "$HOME/.config/gh/token" \
    "$HOME/.github_token"
  do
    if [ -f "$f" ] && [ -s "$f" ]; then
      GITHUB_TOKEN="$(tr -d '[:space:]' < "$f")"
      if [ -n "$GITHUB_TOKEN" ]; then
        export GITHUB_TOKEN
        return 0
      fi
    fi
  done
  return 1
}

gh_api() {
  local url="$1"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsS --max-time 15 \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$url"
  else
    curl -fsS --max-time 15 \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$url"
  fi
}

gh_rate_remaining() {
  gh_api "https://api.github.com/rate_limit" 2>/dev/null | python3 -c '
import sys, json
try:
    print(int(json.load(sys.stdin)["rate"]["remaining"]))
except Exception:
    pass
' 2>/dev/null
}

opencode_latest_tag() {
  gh_api "https://api.github.com/repos/anomalyco/opencode/releases/latest" 2>/dev/null | python3 -c '
import sys, json, re
try:
    tag = json.load(sys.stdin).get("tag_name") or ""
    print(re.sub(r"^v", "", tag))
except Exception:
    pass
' 2>/dev/null
}

clean_incomplete_claude() {
  # Remove partial native installs (empty/tiny version files) and orphan staging.
  local d="$CLAUDE_VERSIONS_DIR"
  if [ -d "$d" ]; then
    local f size name
    for f in "$d"/*; do
      [ -f "$f" ] || continue
      name="$(basename "$f")"
      case "$name" in
        [0-9]*) ;;
        *) continue ;;
      esac
      size="$(stat -c%s "$f" 2>/dev/null || echo 0)"
      if [ "${size:-0}" -lt "$CLAUDE_MIN_BYTES" ]; then
        echo "[$(ts)] clean incomplete claude binary: $f (${size} bytes)" >> "$LOG"
        rm -f "$f"
      fi
    done
  fi
  # claude update uses PID-scoped staging; leftover dirs are pure waste after kill
  if [ -d "$CLAUDE_STAGING_DIR" ]; then
    rm -rf "${CLAUDE_STAGING_DIR:?}"/*
  fi
}

claude_detect_platform() {
  local os arch
  case "$(uname -s)" in
    Linux) os="linux" ;;
    Darwin) os="darwin" ;;
    *) echo ""; return 1 ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch="x64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) echo ""; return 1 ;;
  esac
  if [ "$os" = "linux" ]; then
    if [ -f /lib/libc.musl-x86_64.so.1 ] || [ -f /lib/libc.musl-aarch64.so.1 ] \
      || ldd /bin/ls 2>&1 | grep -q musl; then
      echo "linux-${arch}-musl"
      return 0
    fi
  fi
  echo "${os}-${arch}"
}

# Resumable CDN install — survives timeout/reboot (unlike `claude update` staging).
# Returns: 0 success / already latest
#          2 partial download saved (soft — will continue next run)
#          1 hard failure
claude_cdn_update() {
  local platform latest current manifest checksum expected_size partial dest
  local versions_dir="$CLAUDE_VERSIONS_DIR"
  local dl_dir="$CLAUDE_DOWNLOADS_DIR"
  local bin_link="$HOME/.local/bin/claude"

  platform="$(claude_detect_platform)" || {
    echo "[$(ts)]    claude: unsupported platform" >> "$LOG"
    return 1
  }

  latest="$(curl -fsSL --max-time 30 "$CLAUDE_CDN/latest" 2>/dev/null | tr -d '[:space:]')" || true
  if [[ ! "${latest:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo "[$(ts)]    claude: failed to read latest version from CDN" >> "$LOG"
    return 1
  fi

  current="$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  if [ -n "${current:-}" ] && [ "$current" = "$latest" ]; then
    echo "[$(ts)]    claude already latest ($current)" >> "$LOG"
    return 0
  fi
  echo "[$(ts)]    claude CDN: ${current:-?} → $latest ($platform)" >> "$LOG"

  manifest="$(curl -fsSL --max-time 30 "$CLAUDE_CDN/$latest/manifest.json" 2>/dev/null)" || true
  if [ -z "${manifest:-}" ]; then
    echo "[$(ts)]    claude: manifest download failed" >> "$LOG"
    return 1
  fi

  # checksum + size from manifest
  read -r checksum expected_size < <(printf '%s' "$manifest" | python3 -c '
import sys, json
m = json.load(sys.stdin)
p = m.get("platforms", {}).get(sys.argv[1], {})
print(p.get("checksum") or "", p.get("size") or 0)
' "$platform" 2>/dev/null) || true

  if [[ ! "${checksum:-}" =~ ^[a-f0-9]{64}$ ]]; then
    echo "[$(ts)]    claude: no checksum for platform $platform in manifest" >> "$LOG"
    return 1
  fi
  echo "[$(ts)]    expected size=${expected_size} sha256=${checksum:0:12}…" >> "$LOG"

  mkdir -p "$dl_dir" "$versions_dir" "$(dirname "$bin_link")"
  partial="$dl_dir/claude-$latest-$platform.partial"
  dest="$versions_dir/$latest"

  # Already have a good binary from a prior partial complete?
  if [ -f "$dest" ]; then
    local have
    have="$(stat -c%s "$dest" 2>/dev/null || echo 0)"
    if [ "$have" = "$expected_size" ]; then
      local actual
      actual="$(sha256sum "$dest" | awk '{print $1}')"
      if [ "$actual" = "$checksum" ]; then
        ln -sfn "$dest" "$bin_link"
        echo "[$(ts)]    claude: existing $latest verified → symlink updated" >> "$LOG"
        return 0
      fi
    fi
    # bad file
    rm -f "$dest"
  fi

  # Resume CDN download into stable path (progress survives kills)
  echo "[$(ts)]    downloading (resume OK, slice=${TIMEOUT_CLAUDE_SLICE}s)…" >> "$LOG"
  # --max-time is wall-clock for this slice; -C - resumes; fail soft on timeout (exit 28)
  # Do not use curl -f with -C -: a 416 Range-not-satisfiable on a complete
  # file would look like failure.
  local crc=0
  curl -L --retry 3 --retry-delay 2 \
    -C - \
    --connect-timeout 20 \
    --max-time "$TIMEOUT_CLAUDE_SLICE" \
    -o "$partial" \
    "$CLAUDE_CDN/$latest/$platform/claude" >>"$LOG" 2>&1 || crc=$?

  local got
  got="$(stat -c%s "$partial" 2>/dev/null || echo 0)"
  echo "[$(ts)]    download slice end rc=$crc size=${got}/${expected_size}" >> "$LOG"

  if [ "$got" -lt "${expected_size:-0}" ] 2>/dev/null; then
    # Incomplete — keep partial for next boot/resume
    # 28 = operation timeout, 18 = partial file, 33 = HTTP range error mid-resume
    if [ "$crc" -eq 28 ] || [ "$crc" -eq 18 ] || [ "$crc" -eq 33 ] || [ "$got" -gt 0 ]; then
      echo "[$(ts)]    claude PARTIAL saved — will resume next boot/resume (${got}/${expected_size})" >> "$LOG"
      return 2
    fi
    echo "[$(ts)]    claude download failed (rc=$crc, size=$got)" >> "$LOG"
    return 1
  fi

  # Full size — verify checksum
  local actual
  actual="$(sha256sum "$partial" | awk '{print $1}')"
  if [ "$actual" != "$checksum" ]; then
    echo "[$(ts)]    claude checksum MISMATCH (got ${actual:0:12}… want ${checksum:0:12}…) — delete partial" >> "$LOG"
    rm -f "$partial"
    return 1
  fi

  chmod +x "$partial"
  mv -f "$partial" "$dest"
  ln -sfn "$dest" "$bin_link"

  # Drop older version binaries except the two newest (keep rollback room)
  if [ -d "$versions_dir" ]; then
    # shellcheck disable=SC2012
    ls -1t "$versions_dir" 2>/dev/null | tail -n +3 | while read -r old; do
      case "$old" in
        [0-9]*) rm -f "$versions_dir/$old" ;;
      esac
    done
  fi

  echo "[$(ts)]    claude installed $latest → $dest" >> "$LOG"
  return 0
}

{
  echo "==================================================="
  echo "[$(ts)] update-apps run START"
  echo "  host: $(hostname)  user: $(whoami)  PATH=$PATH"
  if command -v opencode >/dev/null 2>&1; then
    echo "  opencode: $(opencode --version 2>&1)"
  else
    echo "  opencode: NOT FOUND"
  fi
  if command -v grok >/dev/null 2>&1; then
    echo "  grok:     $(grok --version 2>&1)"
  else
    echo "  grok:     NOT FOUND"
  fi
  if command -v claude >/dev/null 2>&1; then
    echo "  claude:   $(claude --version 2>&1)"
  else
    echo "  claude:   NOT FOUND"
  fi
  if load_github_token; then
    echo "  github:   token loaded (auth API rate limit)"
  else
    echo "  github:   no token (unauth 60/hr — put PAT in ~/.config/github/token)"
  fi
} >> "$LOG"

fail=0

# Always scrub partial claude installs before upgrades
clean_incomplete_claude

# --- opencode ---
if command -v opencode >/dev/null 2>&1; then
  echo "[$(ts)] -> opencode upgrade" >> "$LOG"
  load_github_token || true
  remaining="$(gh_rate_remaining || true)"
  if [ -n "${remaining:-}" ]; then
    echo "[$(ts)]    github rate remaining=${remaining}" >> "$LOG"
  fi

  # Need spare: pre-check + upgrade call
  if [ -n "${remaining:-}" ] && [ "$remaining" -lt 3 ] 2>/dev/null; then
    echo "[$(ts)] !! opencode SKIPPED — GitHub API rate limit exhausted (remaining=${remaining})" >> "$LOG"
    echo "[$(ts)]    fix: wait for reset, or write a classic PAT (public_repo) to ~/.config/github/token" >> "$LOG"
  else
    local_ver="$(opencode --version 2>/dev/null | head -1 | tr -d '[:space:]')"
    latest_ver="$(opencode_latest_tag || true)"
    if [ -n "${latest_ver:-}" ] && [ -n "${local_ver:-}" ] && [ "$latest_ver" = "$local_ver" ]; then
      echo "[$(ts)] opencode already latest ($local_ver) — skip upgrade call" >> "$LOG"
    else
      if [ -n "${latest_ver:-}" ]; then
        echo "[$(ts)]    local=${local_ver:-?} latest=${latest_ver}" >> "$LOG"
      fi
      if timeout "$TIMEOUT_DEFAULT" env ${GITHUB_TOKEN:+GITHUB_TOKEN="$GITHUB_TOKEN"} opencode upgrade >>"$LOG" 2>&1; then
        echo "[$(ts)] opencode OK -> $(opencode --version 2>&1)" >> "$LOG"
      else
        rc=$?
        if [ "$rc" -eq 124 ]; then
          echo "[$(ts)] !! opencode upgrade TIMED OUT after ${TIMEOUT_DEFAULT}s" >> "$LOG"
          fail=1
        else
          if tail -n 20 "$LOG" | grep -qiE 'rate limit|403|StatusCode: non 2xx'; then
            echo "[$(ts)] !! opencode upgrade blocked by GitHub (403/rate limit) — soft skip" >> "$LOG"
          else
            echo "[$(ts)] !! opencode upgrade FAILED (exit $rc)" >> "$LOG"
            fail=1
          fi
        fi
      fi
    fi
  fi
else
  echo "[$(ts)] opencode not found — skipping upgrade" >> "$LOG"
fi

# --- grok ---
if command -v grok >/dev/null 2>&1; then
  echo "[$(ts)] -> grok update" >> "$LOG"
  if timeout "$TIMEOUT_DEFAULT" grok update >>"$LOG" 2>&1; then
    echo "[$(ts)] grok OK -> $(grok --version 2>&1)" >> "$LOG"
  else
    rc=$?
    if [ "$rc" -eq 124 ]; then
      echo "[$(ts)] !! grok update TIMED OUT after ${TIMEOUT_DEFAULT}s" >> "$LOG"
    else
      echo "[$(ts)] !! grok update FAILED (exit $rc)" >> "$LOG"
    fi
    fail=1
  fi
else
  echo "[$(ts)] grok not found — skipping update" >> "$LOG"
fi

# --- claude (CDN resume path; NOT `claude update` which restarts every kill) ---
if command -v claude >/dev/null 2>&1 || [ -d "$CLAUDE_VERSIONS_DIR" ]; then
  echo "[$(ts)] -> claude update (CDN resume)" >> "$LOG"
  clean_incomplete_claude
  crc=0
  claude_cdn_update || crc=$?
  case "$crc" in
    0)
      echo "[$(ts)] claude OK -> $(claude --version 2>&1)" >> "$LOG"
      ;;
    2)
      # Partial progress is success-ish for boot path (no red fail for "still downloading")
      echo "[$(ts)] claude PARTIAL — progress kept; not a hard fail" >> "$LOG"
      ;;
    *)
      echo "[$(ts)] !! claude CDN update FAILED (rc=$crc) — falling back to claude update" >> "$LOG"
      if command -v claude >/dev/null 2>&1; then
        if timeout "$TIMEOUT_CLAUDE_SLICE" claude update >>"$LOG" 2>&1; then
          echo "[$(ts)] claude OK (fallback) -> $(claude --version 2>&1)" >> "$LOG"
        else
          rc=$?
          if [ "$rc" -eq 124 ]; then
            echo "[$(ts)] !! claude update TIMED OUT after ${TIMEOUT_CLAUDE_SLICE}s" >> "$LOG"
          else
            echo "[$(ts)] !! claude update FAILED (exit $rc)" >> "$LOG"
          fi
          fail=1
          clean_incomplete_claude
        fi
      else
        fail=1
      fi
      ;;
  esac
else
  echo "[$(ts)] claude not found — skipping update" >> "$LOG"
fi

# --- refresh SETUP.md inventory only when installed versions changed --------
if [ -f "$SETUP_MD" ] && command -v python3 >/dev/null 2>&1; then
  echo "[$(ts)] -> refresh SETUP.md tool inventory" >> "$LOG"
  if SETUP_MD="$SETUP_MD" INVENTORY_SOURCE=update-apps \
      python3 "$DIR/refresh-inventory.py" >>"$LOG" 2>&1
  then
    echo "[$(ts)] inventory OK" >> "$LOG"
  else
    echo "[$(ts)] !! inventory refresh FAILED" >> "$LOG"
  fi
else
  echo "[$(ts)] inventory skip (no SETUP.md or python3)" >> "$LOG"
fi

echo "[$(ts)] update-apps run END (fail=$fail)" >> "$LOG"
exit $fail
