#!/usr/bin/env bash
# claude-memory-guard — catch Claude (and Grok) sneaky tool-memory residue.
#
# On @reboot / @daily:
#   1. Scan ~/.claude/projects/*/memory/ for anything beyond a lone DISABLED stub
#   2. If residue: archive → stage for AI merge → wipe back to stub
#   3. If ~/.grok/memory/ reappears: archive + delete (config keeps it disabled)
#
# Cron cannot do semantic "important facts" merge (no LLM). It stages packets
# under ~/.agents/backups/claude-residue/ and sets NEEDS-MEMORY-MERGE. AI tools, on
# session start / continue_project, must process PENDING.md into standard files
# (global/project AGENTS.md, session_compact.md, docs/DECISIONS.md), then clear
# the flag.
#
# Flag name is NEEDS-MEMORY-MERGE (not bare NEEDS-MERGE) so it is not confused
# with the symlink guard's NEEDS-SYMLINK-MERGE.
#
# Env overrides (for tests): CLAUDE_PROJECTS_ROOT, GROK_MEMORY, AGENTS_HOME, GUARD_DIR
# Path-resolution cache: AGENTS_CACHE_FILE (default ~/.cache/agents-path-map)
set -u

AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
CLAUDE_PROJECTS_ROOT="${CLAUDE_PROJECTS_ROOT:-$HOME/.claude/projects}"
GROK_MEMORY="${GROK_MEMORY:-$HOME/.grok/memory}"
DIR="${GUARD_DIR:-$HOME/cron-jobs/claude-memory-guard}"
LOG="$DIR/check-memory.log"
FLAG="$DIR/NEEDS-MEMORY-MERGE"
RESIDUE_ROOT="$AGENTS_HOME/backups/claude-residue"
PENDING="$RESIDUE_ROOT/PENDING.md"
CACHE_FILE="${AGENTS_CACHE_FILE:-$HOME/.cache/agents-path-map}"
TS="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$DIR" "$RESIDUE_ROOT"
log() { echo "[$TS] $*" >> "$LOG"; }

# flock-serialized: cron @reboot and boot dashboard may both fire at login.
exec 9>"$DIR/.lock"
flock 9

DISABLED_STUB='# Memory Index — DISABLED

Disabled by user policy. Do not write memories here.
Durable facts live in `~/.agents/AGENTS.md` (global rules) and the project'\''s
`AGENTS.md` / `session_compact.md` (project facts).
'

is_clean_memory_dir() {
  local d="$1" f="$d/MEMORY.md"
  [ -f "$f" ] || return 1
  grep -qi "disabled by user policy" "$f" 2>/dev/null || return 1
  local x base
  for x in "$d"/* "$d"/.[!.]* "$d"/..?*; do
    [ -e "$x" ] || continue
    base="$(basename "$x")"
    [ "$base" = "MEMORY.md" ] && continue
    return 1
  done
  return 0
}

# Resolve Claude's encoded project dir name to a real path when possible.
# Encoding: absolute path with "/" → "-" and a leading "-".
# e.g. /home/USER/Projects/foo → -home-USER-Projects-foo
# Strategy: (1) naive slash-restore if that path exists (works when no path
# component contains "-"); (2) cached resolution (~/.cache/agents-path-map);
# (3) walk common roots + deep find under ~/Projects.
resolve_encoded_project() {
  local enc="$1"
  RESOLVED_PATH=""
  # Cache hit (validated: dir still exists)
  if [ -f "$CACHE_FILE" ]; then
    local cached
    cached="$(awk -F'\t' -v e="$enc" '$1==e {print $2; exit}' "$CACHE_FILE" 2>/dev/null || true)"
    if [ -n "${cached:-}" ] && [ -d "$cached" ]; then
      RESOLVED_PATH="$cached"
      return
    fi
  fi
  RESOLVED_PATH="$(
    ENCODED="$enc" HOME_DIR="$HOME" python3 - <<'PY'
import os
from pathlib import Path

enc = os.environ["ENCODED"]
home = Path(os.environ["HOME_DIR"])

def encode(p: Path) -> str:
    try:
        s = str(p.resolve())
    except Exception:
        s = str(p)
    return "-" + s.lstrip("/").replace("/", "-")

# Fast path: reverse encode when path segments have no hyphens
if enc.startswith("-"):
    naive = Path("/" + enc[1:].replace("-", "/"))
    try:
        if naive.is_dir() and encode(naive) == enc:
            print(naive)
            raise SystemExit(0)
    except OSError:
        pass

candidates = []
roots = [
    home,
    home / "Projects",
    home / "Projects" / "sites",
    Path("/media") / home.name,
    Path("/tmp"),
]
for root in roots:
    if not root.is_dir():
        continue
    candidates.append(root)
    try:
        for dirpath, dirnames, _ in os.walk(root):
            # skip heavy / hidden trees
            dirnames[:] = [d for d in dirnames if not d.startswith(".") and d not in
                           ("node_modules", ".git", "venv", ".venv", "dist", "build", "target")]
            # cap depth from this root
            try:
                depth = len(Path(dirpath).relative_to(root).parts)
            except ValueError:
                depth = 0
            if depth > 6:
                dirnames.clear()
                continue
            candidates.append(Path(dirpath))
            if len(candidates) > 5000:
                break
    except OSError:
        pass
    if len(candidates) > 5000:
        break

seen = set()
for c in candidates:
    key = str(c)
    if key in seen:
        continue
    seen.add(key)
    if encode(c) == enc:
        print(c)
        raise SystemExit(0)
print("")
PY
  )"
}

found_residue=0
packet_dir="$RESIDUE_ROOT/$TS"
packets_written=0

shopt -s nullglob
for d in "$CLAUDE_PROJECTS_ROOT"/*/memory; do
  [ -d "$d" ] || continue
  if is_clean_memory_dir "$d"; then
    log "OK       $d"
    continue
  fi

  found_residue=1
  enc="$(basename "$(dirname "$d")")"
  resolve_encoded_project "$enc"
  resolved="${RESOLVED_PATH:-}"
  if [ -n "$resolved" ] && [ -d "$resolved" ] \
     && ! awk -F'\t' -v e="$enc" '$1==e {found=1} END{exit !found}' "$CACHE_FILE" 2>/dev/null; then
    mkdir -p "$(dirname "$CACHE_FILE")"
    printf '%s\t%s\n' "$enc" "$resolved" >> "$CACHE_FILE"
  fi

  mkdir -p "$packet_dir"
  dest="$packet_dir/$enc"
  cp -a "$d" "$dest"
  log "RESIDUE  $d → archived $dest (resolved=${resolved:-UNKNOWN})"

  # Stage human/AI-readable packet summary
  {
    echo "## Packet $TS / $enc"
    echo
    echo "- **encoded:** \`$enc\`"
    echo "- **resolved project:** \`${resolved:-UNKNOWN}\`"
    echo "- **archive:** \`$dest\`"
    echo "- **files:**"
    find "$dest" -type f | sort | while read -r f; do
      echo "  - \`${f#$dest/}\` ($(wc -c < "$f") bytes)"
    done
    echo
    echo "### Contents (for merge)"
    echo
    find "$dest" -type f | sort | while read -r f; do
      rel="${f#$dest/}"
      # Skip pure DISABLED stub re-import
      if [ "$(basename "$f")" = "MEMORY.md" ] && grep -qi "disabled by user policy" "$f" 2>/dev/null; then
        continue
      fi
      echo "#### \`$rel\`"
      echo
      echo '```markdown'
      cat "$f"
      echo
      echo '```'
      echo
    done
    echo "---"
    echo
  } >> "$packet_dir/PACKET.md"

  # Project-local import drop if we know the path
  if [ -n "$resolved" ] && [ -d "$resolved" ]; then
    import_f="$resolved/claude_memory_import.md"
    {
      echo "# Claude memory residue — merge into standard project files"
      echo
      echo "Auto-captured $TS by claude-memory-guard. **AI: merge durable facts into**"
      echo "\`AGENTS.md\` / \`session_compact.md\` / \`docs/DECISIONS.md\` as appropriate,"
      echo "append a short note to \`session_transcript.md\`, then **delete this file**."
      echo
      echo "Global packet: \`$packet_dir/PACKET.md\`"
      echo
      echo "## Captured files"
      echo
      find "$dest" -type f | sort | while read -r f; do
        rel="${f#$dest/}"
        if [ "$(basename "$f")" = "MEMORY.md" ] && grep -qi "disabled by user policy" "$f" 2>/dev/null; then
          continue
        fi
        echo "### \`$rel\`"
        echo
        echo '```markdown'
        cat "$f"
        echo
        echo '```'
        echo
      done
    } > "$import_f"
    log "STAGED   $import_f"
  fi

  # Wipe back to stub-only
  find "$d" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  printf '%s\n' "$DISABLED_STUB" > "$d/MEMORY.md"
  log "WIPED    $d → DISABLED stub only"
  packets_written=$((packets_written + 1))
done
shopt -u nullglob

# Grok memory store must not exist
if [ -e "$GROK_MEMORY" ]; then
  found_residue=1
  mkdir -p "$packet_dir"
  cp -a "$GROK_MEMORY" "$packet_dir/grok-memory"
  rm -rf "$GROK_MEMORY"
  {
    echo "## Packet $TS / grok-memory"
    echo
    echo "- **path:** \`$GROK_MEMORY\` (deleted after archive)"
    echo "- **archive:** \`$packet_dir/grok-memory\`"
    echo "- **note:** Grok memory is disabled; any durable facts in the archive belong in shared markdown."
    echo
    echo "---"
    echo
  } >> "$packet_dir/PACKET.md"
  log "REMOVED  $GROK_MEMORY → $packet_dir/grok-memory"
  packets_written=$((packets_written + 1))
fi

if [ "$packets_written" -gt 0 ] && [ -f "$packet_dir/PACKET.md" ]; then
  # Prepend/update PENDING index
  tmp="$(mktemp)"
  {
    echo "# Claude / Grok memory residue — PENDING MERGE"
    echo
    echo "Updated: $TS"
    echo
    echo "AI tools (**all three**): on **session start** and **\`continue_project\`**, if this"
    echo "file lists unprocessed packets (or \`$FLAG\` exists):"
    echo
    echo "1. Read each packet under \`~/.agents/backups/claude-residue/\` listed below."
    echo "2. Merge durable facts into the right place:"
    echo "   - global/cross-project → \`~/.agents/AGENTS.md\`"
    echo "   - project conventions/commands → project \`AGENTS.md\`"
    echo "   - current handoff state → \`session_compact.md\`"
    echo "   - architecture choices + why → \`docs/DECISIONS.md\`"
    echo "3. If the project has \`session_transcript.md\`, append a one-line note"
    echo "   that residue was imported (write-only; do not read the rest of the file)."
    echo "4. Delete any project \`claude_memory_import.md\` you processed."
    echo "5. Remove processed packet lines from this file; if none left, delete this"
    echo "   file and \`$FLAG\`."
    echo
    echo "Flag file (memory only — not the symlink guard): \`$FLAG\`"
    echo
    echo "## Unprocessed packets"
    echo
    echo "- \`$packet_dir/PACKET.md\` ($packets_written capture(s) at $TS)"
    if [ -f "$PENDING" ]; then
      # keep prior packet lines
      grep -E '^\- `' "$PENDING" | grep -v "$packet_dir" || true
    fi
    echo
  } > "$tmp"
  mv "$tmp" "$PENDING"
  echo "$packet_dir" >> "$FLAG"
  # Migrate legacy flag name if present
  if [ -f "$DIR/NEEDS-MERGE" ]; then
    cat "$DIR/NEEDS-MERGE" >> "$FLAG" 2>/dev/null || true
    rm -f "$DIR/NEEDS-MERGE"
    log "MIGRATED legacy NEEDS-MERGE -> NEEDS-MEMORY-MERGE"
  fi
  log "FLAG     $FLAG (packets=$packets_written)"
else
  # Still migrate legacy empty/stale flag names
  if [ -f "$DIR/NEEDS-MERGE" ]; then
    mv "$DIR/NEEDS-MERGE" "$FLAG"
    log "MIGRATED legacy NEEDS-MERGE -> NEEDS-MEMORY-MERGE"
  fi
  log "CLEAN    no tool-memory residue"
fi

if [ "$found_residue" = 1 ]; then
  exit 2
fi
exit 0
