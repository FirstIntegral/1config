#!/usr/bin/env bash
# secret-scan.sh — refuse to let a credential leave in a commit.
#
#   bash ~/.agents/hooks/secret-scan.sh <repo> [<base>]
#
# Scans the lines that `git add -A` and a commit would add on top of <base>
# (default HEAD, or the empty tree when the repo has no commit yet). The real
# index is not touched: the scan stages into a scratch copy.
#
# Two layers:
#   1. Built-in patterns for token shapes that have no innocent reading
#      (private key blocks; GitHub, GitLab, Slack, AWS, Google, OpenAI,
#      Anthropic, xAI, npm, Hugging Face, Stripe tokens; a password inside a URL).
#   2. gitleaks, when it is on PATH, for the long tail. It is the maintained
#      scanner; the built-in list exists so the gate is never a no-op on a
#      machine without it.
# A line that carries `gitleaks:allow` is skipped by both. That is how a
# fixture keeps a fake token.
#
# Sourced, it only defines:
#   secret_name_hit <basename>   -> 0 when the file name alone says "secret"
#
# Exit 0 clean · 1 a finding (path:line and the rule on stderr, never the value) · 2 usage
# SECRET_SCAN_NO_GITLEAKS=1 skips layer 2 (verify.sh uses it to test layer 1 alone).

# Names a checkpoint must not be the one to add. A sample file is not a secret.
secret_name_hit() {
  case "$1" in
    .env.example|.env.sample|.env.template|.env.dist|.env.defaults) return 1 ;;
    .env|.env.*) return 0 ;;
    *.pem|*.p12|*.pfx|*.ppk|*.keystore|*.jks) return 0 ;;
    id_rsa|id_dsa|id_ecdsa|id_ed25519) return 0 ;;
    keystore.properties|local.properties|.netrc|credentials.json) return 0 ;;
    *service-account*.json|google-play*.json|pc-api-*.json) return 0 ;;
  esac
  return 1
}

# Sourced: stop here.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  return 0
fi

set -uo pipefail
[ $# -ge 1 ] && [ $# -le 2 ] || { echo "usage: secret-scan.sh <repo> [<base>]" >&2; exit 2; }
REPO="$(cd "$1" && pwd -P)" || exit 2
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { echo "secret-scan: not a git repo: $REPO" >&2; exit 2; }

BASE="${2:-}"
if [ -z "$BASE" ]; then
  if git -C "$REPO" rev-parse -q --verify HEAD >/dev/null 2>&1; then
    BASE=HEAD
  else
    BASE="$(git -C "$REPO" hash-object -t tree /dev/null)"
  fi
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
real_index="$(git -C "$REPO" rev-parse --git-path index)"
case "$real_index" in /*) ;; *) real_index="$REPO/$real_index" ;; esac
[ -f "$real_index" ] && cp "$real_index" "$WORK/index"
export GIT_INDEX_FILE="$WORK/index"
git -C "$REPO" add -A >/dev/null 2>&1 || { echo "secret-scan: cannot stage a scratch index" >&2; exit 2; }
git -C "$REPO" diff --cached --no-color --no-ext-diff -U0 "$BASE" > "$WORK/diff" 2>/dev/null \
  || { echo "secret-scan: cannot diff against $BASE" >&2; exit 2; }
unset GIT_INDEX_FILE

# Layer 1. Also writes each file's added lines under $WORK/added/ for layer 2.
python3 - "$WORK/diff" "$WORK/added" <<'PY'
import os
import re
import sys

diff_path, added_root = sys.argv[1], sys.argv[2]
RULES = [
    ("private-key", r"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY(?: BLOCK)?-----"),
    ("github-token", r"\bgh[pousr]_[A-Za-z0-9]{36,}\b"),
    ("github-fine-grained-token", r"\bgithub_pat_[A-Za-z0-9_]{50,}\b"),
    ("gitlab-token", r"\bglpat-[A-Za-z0-9_\-]{20,}\b"),
    ("slack-token", r"\bxox[abprs]-[A-Za-z0-9\-]{10,}\b"),
    ("aws-access-key-id", r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"),
    ("google-api-key", r"\bAIza[0-9A-Za-z_\-]{35}\b"),
    ("anthropic-key", r"\bsk-ant-[A-Za-z0-9_\-]{20,}"),
    ("openai-key", r"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_\-]{40,}"),
    ("xai-key", r"\bxai-[A-Za-z0-9]{40,}\b"),
    ("npm-token", r"\bnpm_[A-Za-z0-9]{36}\b"),
    ("huggingface-token", r"\bhf_[A-Za-z0-9]{30,}\b"),
    ("stripe-live-key", r"\b[sr]k_live_[0-9A-Za-z]{20,}\b"),
    ("url-password", r"\b[a-z][a-z0-9+.\-]*://[^/\s:@]+:[A-Za-z0-9._~%+\-]{8,}@[A-Za-z0-9]"),
]
RULES = [(name, re.compile(rx)) for name, rx in RULES]

findings = []
path = None
line_no = 0
out = None
with open(diff_path, "r", encoding="utf-8", errors="replace") as fh:
    for raw in fh:
        line = raw.rstrip("\n")
        if line.startswith("+++ "):
            if out:
                out.close()
                out = None
            target = line[4:]
            if target == "/dev/null":
                path = None
                continue
            path = target[2:] if target.startswith("b/") else target
            dest = os.path.join(added_root, path)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            out = open(dest, "w", encoding="utf-8")
            continue
        if line.startswith("@@"):
            m = re.match(r"@@ -\S+ \+(\d+)", line)
            line_no = int(m.group(1)) if m else 0
            continue
        if path is None or not line.startswith("+") or line.startswith("+++"):
            continue
        text = line[1:]
        if out:
            out.write(text + "\n")
        if "gitleaks:allow" not in text:
            for name, rx in RULES:
                if rx.search(text):
                    findings.append((path, line_no, name))
                    break
        line_no += 1
if out:
    out.close()
for path, n, name in findings:
    sys.stderr.write(f"secret-scan: {path}:{n}: {name}\n")
sys.exit(1 if findings else 0)
PY
rc=$?
[ "$rc" -le 1 ] || { echo "secret-scan: scanner failed (exit $rc)" >&2; exit 2; }
found=$rc

# Layer 2. Old and new gitleaks spell the directory scan differently, so the
# first form that runs wins. A report with a finding counts; a gitleaks that
# cannot run does not hide layer 1's answer.
if [ "${SECRET_SCAN_NO_GITLEAKS:-0}" != 1 ] && command -v gitleaks >/dev/null 2>&1 && [ -d "$WORK/added" ]; then
  report="$WORK/gitleaks.json"
  cfg=()
  [ -f "$REPO/.gitleaks.toml" ] && cfg=(--config "$REPO/.gitleaks.toml")
  gl_rc=0
  if gitleaks dir --help >/dev/null 2>&1; then
    gitleaks dir "$WORK/added" --no-banner --redact --exit-code 3 \
      --report-format json --report-path "$report" ${cfg[@]+"${cfg[@]}"} >/dev/null 2>&1 || gl_rc=$?
  else
    gitleaks detect --no-git --source "$WORK/added" --no-banner --redact --exit-code 3 \
      --report-format json --report-path "$report" ${cfg[@]+"${cfg[@]}"} >/dev/null 2>&1 || gl_rc=$?
  fi
  if [ "$gl_rc" -eq 3 ]; then
    found=1
    python3 - "$report" "$WORK/added" <<'PY' || true
import json, os, sys
try:
    rows = json.load(open(sys.argv[1]))
except Exception:
    rows = []
root = sys.argv[2].rstrip("/") + "/"
for r in rows:
    f = str(r.get("File", ""))
    f = f[len(root):] if f.startswith(root) else f
    sys.stderr.write(f"secret-scan: {f}: gitleaks {r.get('RuleID', 'rule')}\n")
if not rows:
    sys.stderr.write("secret-scan: gitleaks reported a finding\n")
PY
  elif [ "$gl_rc" -ne 0 ]; then
    echo "secret-scan: gitleaks did not run cleanly (exit $gl_rc); built-in patterns still applied" >&2
  fi
fi

exit "$found"
